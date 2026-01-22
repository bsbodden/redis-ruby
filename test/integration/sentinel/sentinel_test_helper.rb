# frozen_string_literal: true

require "test_helper"

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
  MASTER_PORT = 6379
  REPLICA_PORT = 6380
  SENTINEL_PORTS = [26_379, 26_380, 26_381].freeze
  SERVICE_NAME = "mymaster"
  COMPOSE_FILE = File.expand_path("../../../docker/docker-compose.sentinel.yml", __dir__)

  # Detect whether we're running inside a Docker container
  def self.inside_docker?
    @inside_docker ||= begin
      File.exist?("/.dockerenv") || File.read("/proc/1/cgroup").include?("docker")
    rescue StandardError
      false
    end
  end

  # Connect the current container to the sentinel network if needed
  def self.connect_to_network!
    return unless inside_docker?

    container_id = begin
      File.read("/etc/hostname").strip
    rescue StandardError
      nil
    end
    return unless container_id

    # Connect to the sentinel network
    system("docker network connect docker_redis-sentinel-net #{container_id} 2>/dev/null")

    # Clear cached docker_host so it gets recalculated with container IPs
    @docker_host = nil
  end

  # Get the host address for connecting to sentinel/redis containers
  def self.docker_host
    # Always recalculate based on current state
    if inside_docker? && @compose_started
      # When inside a container with compose, use first sentinel container IP
      ips = sentinel_ips
      ips&.first || "localhost"
    elsif system("getent hosts host.docker.internal >/dev/null 2>&1")
      "host.docker.internal"
    else
      "localhost"
    end
  rescue StandardError
    "localhost"
  end

  # Get sentinel container IPs for direct connection
  def self.sentinel_ips
    return nil unless inside_docker? && @compose_started

    %w[sentinel-1 sentinel-2 sentinel-3].map do |name|
      `docker inspect #{name} --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'`.strip
    end
  end

  class << self
    attr_reader :master_container, :replica_container, :sentinel_containers, :network

    def start!
      return if @started

      if use_docker_compose?
        start_with_compose!
      else
        start_with_testcontainers!
      end

      @started = true
    rescue StandardError => e
      cleanup
      raise "Failed to start Redis Sentinel: #{e.message}. " \
            "Set REDIS_SENTINEL_URL or use: docker-compose -f docker/docker-compose.sentinel.yml up -d"
    end

    def stop!
      return unless @started

      puts "Stopping Redis Sentinel cluster..."

      if @compose_started
        stop_compose
      else
        cleanup
      end

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
      if @compose_started
        if inside_docker?
          # Use container IPs directly when inside Docker
          connect_to_network!
          ips = sentinel_ips
          if ips
            ips.map { |ip| { host: ip, port: 26_379 } }
          else
            SENTINEL_PORTS.map do |port|
              { host: docker_host, port: port }
            end
          end
        else
          SENTINEL_PORTS.map { |port| { host: docker_host, port: port } }
        end
      else
        @sentinel_containers&.map do |container|
          { host: container.host, port: container.mapped_port(26_379) }
        end
      end
    end

    def master_address
      if @compose_started
        { host: docker_host, port: MASTER_PORT }
      elsif @master_container
        { host: @master_container.host, port: @master_container.mapped_port(MASTER_PORT) }
      end
    end

    def replica_address
      if @compose_started
        { host: docker_host, port: REPLICA_PORT }
      elsif @replica_container
        { host: @replica_container.host, port: @replica_container.mapped_port(REPLICA_PORT) }
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

      # Set compose_started early so network detection works correctly
      @compose_started = true

      # Connect to network if inside Docker
      connect_to_network! if inside_docker?

      wait_for_compose_sentinel

      puts "Redis Sentinel started with Docker Compose"
    end

    def stop_compose
      system("docker-compose -f #{COMPOSE_FILE} down 2>&1")
      @compose_started = false
    end

    def wait_for_compose_sentinel(timeout: 60)
      # Ensure we're connected to the network first
      connect_to_network! if inside_docker?

      sentinel_host = if inside_docker?
                        ips = sentinel_ips
                        ips&.first || docker_host
                      else
                        docker_host
                      end
      sentinel_port = inside_docker? ? 26_379 : SENTINEL_PORTS.first

      puts "Waiting for Sentinel cluster to be ready (host: #{sentinel_host}:#{sentinel_port})..."
      start_time = Time.now

      loop do
        raise "Timeout waiting for Sentinel cluster" if Time.now - start_time > timeout

        begin
          conn = RedisRuby::Connection::TCP.new(
            host: sentinel_host,
            port: sentinel_port,
            timeout: 5.0
          )
          result = conn.call("SENTINEL", "MASTER", SERVICE_NAME)
          conn.close

          if result.is_a?(Array) && result.any?
            info = parse_sentinel_info(result)
            if info["flags"] && !info["flags"].include?("down")
              puts "Sentinel cluster is ready!"
              return
            end
          end
        rescue StandardError => e
          puts "Waiting... (#{e.class})"
        end

        sleep 2
      end
    end

    def start_with_testcontainers!
      puts "Starting Redis Sentinel with TestContainers..."

      # Create Docker network for container communication
      require "docker"
      @network_name = "redis_sentinel_test_#{Process.pid}"
      @network = Docker::Network.create(@network_name)

      start_master_tc
      start_replica_tc
      start_sentinels_tc
      wait_for_sentinel_ready

      puts "Redis Sentinel cluster ready!"
    end

    def start_master_tc
      puts "Starting Redis master..."

      @master_container = Testcontainers::DockerContainer.new(REDIS_IMAGE)
      @master_container.with_exposed_port(MASTER_PORT)
      @master_container.with_name("redis-master-#{Process.pid}")
      @master_container.start

      # Connect to network with alias
      @network.connect(@master_container._id, { "Aliases" => ["redis-master"] })

      wait_for_redis(@master_container, MASTER_PORT)
      puts "Master started at #{@master_container.host}:#{@master_container.mapped_port(MASTER_PORT)}"
    end

    def start_replica_tc
      puts "Starting Redis replica..."

      # Replica connects to master via network alias
      @replica_container = Testcontainers::DockerContainer.new(REDIS_IMAGE)
      @replica_container.with_exposed_port(MASTER_PORT)
      @replica_container.with_command("redis-server", "--port", MASTER_PORT.to_s,
                                      "--replicaof", "redis-master", MASTER_PORT.to_s)
      @replica_container.with_name("redis-replica-#{Process.pid}")
      @replica_container.start

      @network.connect(@replica_container._id, { "Aliases" => ["redis-replica"] })

      wait_for_redis(@replica_container, MASTER_PORT)
      puts "Replica started at #{@replica_container.host}:#{@replica_container.mapped_port(MASTER_PORT)}"
    end

    def start_sentinels_tc
      puts "Starting Sentinels..."

      @sentinel_containers = []

      3.times do |i|
        container = Testcontainers::DockerContainer.new(SENTINEL_IMAGE)
        container.with_exposed_port(26_379)
        container.with_env("REDIS_MASTER_HOST", "redis-master")
        container.with_env("REDIS_MASTER_PORT_NUMBER", MASTER_PORT.to_s)
        container.with_env("REDIS_MASTER_SET", SERVICE_NAME)
        container.with_env("REDIS_SENTINEL_QUORUM", "2")
        container.with_env("REDIS_SENTINEL_DOWN_AFTER_MILLISECONDS", "5000")
        container.with_env("REDIS_SENTINEL_FAILOVER_TIMEOUT", "10000")
        container.with_name("sentinel-#{i}-#{Process.pid}")
        container.start

        @network.connect(container._id, { "Aliases" => ["sentinel-#{i}"] })

        @sentinel_containers << container
        puts "Sentinel #{i} started at #{container.host}:#{container.mapped_port(26_379)}"
      end
    end

    def cleanup
      @sentinel_containers&.each do |c|
        c.stop
      rescue StandardError
        nil
      end
      begin
        @replica_container&.stop
      rescue StandardError
        nil
      end
      begin
        @master_container&.stop
      rescue StandardError
        nil
      end
      begin
        @network&.remove
      rescue StandardError
        nil
      end
      @sentinel_containers = nil
      @replica_container = nil
      @master_container = nil
      @network = nil
    end

    def wait_for_redis(container, port, timeout: 30)
      start_time = Time.now

      loop do
        raise "Timeout waiting for Redis to be ready" if Time.now - start_time > timeout

        begin
          mapped_port = container.mapped_port(port)
          conn = RedisRuby::Connection::TCP.new(
            host: container.host,
            port: mapped_port,
            timeout: 2.0
          )
          result = conn.call("PING")
          conn.close
          return if result == "PONG"
        rescue StandardError
          # Not ready yet
        end

        sleep 0.5
      end
    end

    def wait_for_sentinel_ready(timeout: 60)
      puts "Waiting for Sentinel cluster to be ready..."
      start_time = Time.now

      loop do
        raise "Timeout waiting for Sentinel cluster" if Time.now - start_time > timeout

        begin
          sentinel = @sentinel_containers.first
          port = sentinel.mapped_port(26_379)
          conn = RedisRuby::Connection::TCP.new(
            host: sentinel.host,
            port: port,
            timeout: 5.0
          )

          result = conn.call("SENTINEL", "MASTER", SERVICE_NAME)
          conn.close

          if result.is_a?(Array) && result.any?
            info = parse_sentinel_info(result)
            if info["flags"] && !info["flags"].include?("down")
              puts "Sentinel cluster is ready!"
              return
            end
          end
        rescue StandardError => e
          puts "Waiting... (#{e.class}: #{e.message})"
        end

        sleep 1
      end
    end

    def parse_sentinel_info(array)
      return {} unless array.is_a?(Array)

      hash = {}
      array.each_slice(2) do |key, value|
        hash[key] = value if key.is_a?(String)
      end
      hash
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

    if ENV["REDIS_SENTINEL_URL"]
      @sentinel_addresses = parse_sentinel_url(ENV["REDIS_SENTINEL_URL"])
      @service_name = ENV["REDIS_SENTINEL_SERVICE"] || "mymaster"
    elsif self.class.use_sentinel_testcontainers?
      begin
        SentinelTestContainerSupport.start!
        @sentinel_addresses = SentinelTestContainerSupport.sentinel_addresses
        @service_name = SentinelTestContainerSupport.service_name
      rescue StandardError => e
        skip "Failed to start Sentinel: #{e.message}"
      end
    else
      skip "REDIS_SENTINEL_URL not set and TestContainers not enabled"
    end

    @sentinel_client = RedisRuby::SentinelClient.new(
      sentinels: @sentinel_addresses,
      service_name: @service_name
    )
  end

  def teardown
    @sentinel_client&.close
  end

  attr_reader :sentinel_client, :sentinel_addresses, :service_name

  private

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
end

Minitest.after_run do
  SentinelTestContainerSupport.stop! if SentinelTestContainerSupport.started?
end
