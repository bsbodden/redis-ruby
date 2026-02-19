# frozen_string_literal: true

require "test_helper"
require_relative "cluster_docker_support"
require_relative "cluster_readiness"

# Redis Cluster TestContainers support
#
# This module supports multiple ways to run cluster tests:
# 1. REDIS_CLUSTER_URL environment variable (external cluster)
# 2. Docker Compose via docker/docker-compose.cluster.yml
# 3. TestContainers with Docker networking
#
# For CI environments, using Docker Compose or external cluster is recommended.
module ClusterTestContainerSupport
  CLUSTER_IMAGE = "redislabs/client-libs-test:8.4.0"
  CLUSTER_PORTS = (17_000..17_005).to_a
  MASTER_PORTS = [17_000, 17_001, 17_002].freeze
  REPLICA_PORTS = [17_003, 17_004, 17_005].freeze
  COMPOSE_FILE = File.expand_path("../../../docker/docker-compose.cluster.yml", __dir__)

  extend ClusterDockerSupport
  extend ClusterReadiness

  class << self
    attr_reader :container, :nodes, :network

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
      raise "Failed to start Redis Cluster: #{e.message}. " \
            "Set REDIS_CLUSTER_URL or use: docker-compose -f docker/docker-compose.cluster.yml up -d"
    end

    def stop!
      return unless @started

      puts "Stopping Redis Cluster..."
      @compose_started ? stop_compose : cleanup
      @started = false
    end

    def started?
      @started
    end

    def available?
      return true if @started
      return true if ENV["REDIS_CLUSTER_URL"]

      system("docker info > /dev/null 2>&1")
    end

    def master_nodes
      @nodes&.select { |n| MASTER_PORTS.include?(n[:port]) }
    end

    def replica_nodes
      @nodes&.select { |n| REPLICA_PORTS.include?(n[:port]) }
    end

    def seed_nodes
      master_nodes&.map { |n| "redis://#{n[:host]}:#{n[:port]}" }
    end

    private

    def use_docker_compose?
      File.exist?(COMPOSE_FILE) && !ENV["CI"]
    end

    def start_with_compose!
      puts "Starting Redis Cluster with Docker Compose..."
      result = system("docker-compose -f #{COMPOSE_FILE} up -d 2>&1")
      raise "Docker Compose failed" unless result

      @compose_started = true
      connect_to_network! if inside_docker?
      wait_for_compose_cluster
      build_compose_node_list
      puts "Redis Cluster started with Docker Compose"
    end

    def build_compose_node_list
      cluster_ip = docker_host
      @nodes = CLUSTER_PORTS.map { |port| { host: cluster_ip, port: port } }
    end

    def stop_compose
      system("docker-compose -f #{COMPOSE_FILE} down 2>&1")
      @compose_started = false
    end

    def wait_for_compose_cluster(timeout: 90)
      host = docker_host
      port = CLUSTER_PORTS.first
      puts "Waiting for cluster to be ready (host: #{host}:#{port})..."
      wait_for_cluster_state_ok(host, port, timeout: timeout)
    end

    def start_with_testcontainers!
      puts "Starting Redis Cluster with TestContainers..."
      create_docker_network
      create_and_start_container
      wait_for_cluster_ready
      build_testcontainer_node_list
    end

    def create_docker_network
      require "docker"
      @network_name = "redis_cluster_test_#{Process.pid}"
      @network = Docker::Network.create(@network_name)
    end

    def create_and_start_container
      @container = Testcontainers::DockerContainer.new(CLUSTER_IMAGE)
      CLUSTER_PORTS.each { |port| @container.with_fixed_exposed_port(port, port) }
      @container.with_env("IP", "0.0.0.0")
      @container.with_env("INITIAL_PORT", "7000")
      @container.start
      @network.connect(@container._id)
    end

    def build_testcontainer_node_list
      @nodes = CLUSTER_PORTS.map do |port|
        { host: @container.host, port: port, internal_port: port }
      end
      puts "Redis Cluster started: #{@nodes.map { |n| "#{n[:host]}:#{n[:port]}" }.join(", ")}"
    end

    def cleanup
      begin
        @container&.stop
      rescue StandardError
        nil
      end
      begin
        @network&.remove
      rescue StandardError
        nil
      end
      @container = nil
      @network = nil
      @nodes = nil
    end

    def wait_for_cluster_ready(timeout: 90)
      puts "Waiting for cluster to be ready..."
      wait_for_cluster_state_ok(@container.host, 7000, timeout: timeout)
    end
  end
end

# Base class for cluster tests
class ClusterTestCase < Minitest::Test
  class << self
    def use_cluster_testcontainers!
      @use_cluster_testcontainers = true
    end

    def use_cluster_testcontainers?
      @use_cluster_testcontainers
    end
  end

  def setup
    skip_cluster_tests unless cluster_available?
    resolve_cluster_nodes
    initialize_cluster_client
  end

  def verify_cluster_connectivity!
    host_translation = ClusterTestContainerSupport.host_translation
    client = RR::ClusterClient.new(
      nodes: @cluster_nodes,
      host_translation: host_translation
    )
    client.call("PING")
    client.close
  rescue Errno::ECONNREFUSED, RR::ConnectionError => e
    skip "Cluster nodes announce unreachable addresses (127.0.0.1). " \
         "Set REDIS_CLUSTER_URL for external cluster or use host networking. " \
         "Error: #{e.message}"
  end

  def teardown
    @cluster&.close
  end

  attr_reader :cluster, :cluster_nodes

  private

  def resolve_cluster_nodes
    if ENV["REDIS_CLUSTER_URL"]
      @cluster_nodes = ENV["REDIS_CLUSTER_URL"].split(",")
    elsif self.class.use_cluster_testcontainers?
      start_cluster_testcontainers
    else
      skip "REDIS_CLUSTER_URL not set and TestContainers not enabled"
    end
  end

  def start_cluster_testcontainers
    ClusterTestContainerSupport.start!
    @cluster_nodes = ClusterTestContainerSupport.seed_nodes
    verify_cluster_connectivity! if ClusterTestContainerSupport.inside_docker?
  rescue StandardError => e
    skip "Failed to start Cluster: #{e.message}"
  end

  def initialize_cluster_client
    host_translation = ClusterTestContainerSupport.host_translation
    @cluster = RR::ClusterClient.new(
      nodes: @cluster_nodes,
      host_translation: host_translation
    )
  end

  def cluster_available?
    return true if ENV["REDIS_CLUSTER_URL"]
    return true if self.class.use_cluster_testcontainers? && ClusterTestContainerSupport.available?

    false
  end

  def skip_cluster_tests
    skip "Redis Cluster not available (set REDIS_CLUSTER_URL or enable TestContainers)"
  end

  def key_for_slot(slot)
    1000.times do |i|
      key = "key#{i}"
      return key if @cluster.key_slot(key) == slot
    end
    raise "Could not find key for slot #{slot}"
  end

  def keys_for_same_slot(count, tag = "test")
    Array.new(count) { |i| "{#{tag}}:key#{i}" }
  end
end

Minitest.after_run do
  ClusterTestContainerSupport.stop! if ClusterTestContainerSupport.started?
end
