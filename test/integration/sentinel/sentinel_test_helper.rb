# frozen_string_literal: true

require "test_helper"
require_relative "sentinel_docker_support"
require_relative "sentinel_readiness"
require_relative "sentinel_testcontainer_setup"

# Redis Sentinel TestContainers support
#
# This module supports multiple ways to run sentinel tests:
# 1. REDIS_SENTINEL_URL environment variable (external sentinels)
# 2. Docker Compose via docker/docker-compose.sentinel.yml
# 3. TestContainers with Docker networking
#
# For CI environments, using Docker Compose or external sentinels is recommended.
module SentinelTestContainerSupport
  REDIS_IMAGE = "redis:7.0"
  SENTINEL_IMAGE = "bitnami/redis-sentinel:latest"
  MASTER_PORT = 7379
  REPLICA_PORT = 7380
  MASTER_INTERNAL_PORT = 6379
  REPLICA_INTERNAL_PORT = 6380
  SENTINEL_PORTS = [26_379, 26_380, 26_381].freeze
  SERVICE_NAME = "mymaster"
  COMPOSE_FILE = File.expand_path("../../../docker/docker-compose.sentinel.yml", __dir__)

  extend SentinelDockerSupport
  extend SentinelReadiness

  class << self
    include SentinelReadiness
    include SentinelTestcontainerSetup

    attr_reader :master_container, :replica_container, :sentinel_containers, :network

    def start!
      return if @started

      use_docker_compose? ? start_with_compose! : start_with_testcontainers!
      @started = true
    rescue StandardError => e
      cleanup
      raise "Failed to start Redis Sentinel: #{e.message}. " \
            "Set REDIS_SENTINEL_URL or use: docker-compose -f docker/docker-compose.sentinel.yml up -d"
    end

    def stop!
      return unless @started

      puts "Stopping Redis Sentinel cluster..."
      @compose_started ? stop_compose : cleanup
      @started = false
    end

    def started?
      @started
    end

    def available?
      return true if @started
      return true if ENV["REDIS_SENTINEL_URL"]

      system("docker info > /dev/null 2>&1")
    end

    def sentinel_addresses
      return testcontainer_sentinel_addresses unless @compose_started
      return compose_docker_sentinel_addresses if inside_docker?

      SENTINEL_PORTS.map { |port| { host: docker_host, port: port } }
    end

    def master_address
      if @compose_started
        { host: docker_host, port: MASTER_PORT }
      elsif @master_container
        { host: @master_container.host, port: @master_container.mapped_port(MASTER_INTERNAL_PORT) }
      end
    end

    def replica_address
      if @compose_started
        { host: docker_host, port: REPLICA_PORT }
      elsif @replica_container
        { host: @replica_container.host, port: @replica_container.mapped_port(MASTER_INTERNAL_PORT) }
      end
    end

    def service_name
      SERVICE_NAME
    end

    private

    def use_docker_compose?
      File.exist?(COMPOSE_FILE) && !ENV["CI"]
    end

    def start_with_compose!
      puts "Starting Redis Sentinel with Docker Compose..."
      result = system("docker-compose -f #{COMPOSE_FILE} up -d 2>&1")
      raise "Docker Compose failed" unless result

      @compose_started = true
      connect_to_network! if inside_docker?
      wait_for_compose_sentinel
      puts "Redis Sentinel started with Docker Compose"
    end

    def stop_compose
      system("docker-compose -f #{COMPOSE_FILE} down 2>&1")
      @compose_started = false
    end

    def wait_for_compose_sentinel(timeout: 60)
      connect_to_network! if inside_docker?
      host, port = resolve_sentinel_endpoint
      puts "Waiting for Sentinel cluster to be ready (host: #{host}:#{port})..."
      wait_until_sentinel_ready(host, port, timeout: timeout)
    end

    def resolve_sentinel_endpoint
      if inside_docker?
        ips = sentinel_ips
        [ips&.first || docker_host, 26_379]
      else
        [docker_host, SENTINEL_PORTS.first]
      end
    end

    def wait_until_sentinel_ready(host, port, timeout:)
      start_time = Time.now
      loop do
        raise "Timeout waiting for Sentinel cluster" if Time.now - start_time > timeout
        return if sentinel_cluster_ready?(host, port)

        sleep 2
      end
    end

    def testcontainer_sentinel_addresses
      @sentinel_containers&.map do |container|
        { host: container.host, port: container.mapped_port(26_379) }
      end
    end

    def compose_docker_sentinel_addresses
      connect_to_network!
      ips = sentinel_ips
      return ips.map { |ip| { host: ip, port: 26_379 } } if ips

      SENTINEL_PORTS.map { |port| { host: docker_host, port: port } }
    end

    def cleanup
      @sentinel_containers&.each { |container| safe_stop(container) }
      safe_stop(@replica_container)
      safe_stop(@master_container)
      safe_remove_network(@network)
      @sentinel_containers = nil
      @replica_container = nil
      @master_container = nil
      @network = nil
    end

    def safe_stop(container)
      container&.stop
    rescue StandardError
      nil
    end

    def safe_remove_network(net)
      net&.remove
    rescue StandardError
      nil
    end
  end
end

# Base class for Sentinel tests
class SentinelTestCase < Minitest::Test
  class << self
    def use_sentinel_testcontainers!
      @use_sentinel_testcontainers = true
    end

    def use_sentinel_testcontainers?
      @use_sentinel_testcontainers
    end
  end

  def setup
    skip_sentinel_tests unless sentinel_available?
    resolve_sentinel_config
    initialize_sentinel_client
  end

  def teardown
    @sentinel_client&.close
  end

  attr_reader :sentinel_client, :sentinel_addresses, :service_name

  private

  def resolve_sentinel_config
    if ENV["REDIS_SENTINEL_URL"]
      @sentinel_addresses = parse_sentinel_url(ENV["REDIS_SENTINEL_URL"])
      @service_name = ENV["REDIS_SENTINEL_SERVICE"] || "mymaster"
    elsif self.class.use_sentinel_testcontainers?
      start_sentinel_testcontainers
    else
      skip "REDIS_SENTINEL_URL not set and TestContainers not enabled"
    end
  end

  def start_sentinel_testcontainers
    SentinelTestContainerSupport.start!
    @sentinel_addresses = SentinelTestContainerSupport.sentinel_addresses
    @service_name = SentinelTestContainerSupport.service_name
  rescue StandardError => e
    skip "Failed to start Sentinel: #{e.message}"
  end

  def initialize_sentinel_client
    @sentinel_client = create_sentinel_client_with_nat_translation(
      sentinels: @sentinel_addresses,
      service_name: @service_name
    )
  end

  def sentinel_available?
    return true if ENV["REDIS_SENTINEL_URL"]
    return true if self.class.use_sentinel_testcontainers? && SentinelTestContainerSupport.available?

    false
  end

  def skip_sentinel_tests
    skip "Redis Sentinel not available (set REDIS_SENTINEL_URL or enable TestContainers)"
  end

  def parse_sentinel_url(url)
    url.split(",").map do |addr|
      host, port = addr.split(":")
      { host: host, port: port.to_i }
    end
  end

  def create_sentinel_client_with_nat_translation(sentinels:, service_name:, **)
    client = RR::SentinelClient.new(sentinels: sentinels, service_name: service_name, **)
    apply_nat_translation(client) if SentinelTestContainerSupport.instance_variable_get(:@compose_started)
    client
  end

  def apply_nat_translation(client)
    manager = client.sentinel_manager
    original_discover_master = manager.method(:discover_master)

    manager.define_singleton_method(:discover_master) do
      address = original_discover_master.call
      translate_docker_address(address)
    end

    define_address_translator(manager)
  end

  def define_address_translator(manager)
    manager.define_singleton_method(:translate_docker_address) do |address|
      return address unless address[:host].match?(/^(172|192\.168)\.\d+\.\d+\.\d+$/)

      case address[:port]
      when 6379 then { host: "127.0.0.1", port: SentinelTestContainerSupport::MASTER_PORT }
      when 6380 then { host: "127.0.0.1", port: SentinelTestContainerSupport::REPLICA_PORT }
      else address
      end
    end
  end
end

Minitest.after_run do
  SentinelTestContainerSupport.stop! if SentinelTestContainerSupport.started?
end
