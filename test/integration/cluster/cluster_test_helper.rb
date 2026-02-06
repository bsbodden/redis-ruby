# frozen_string_literal: true

require "test_helper"

# Redis Cluster TestContainers support
#
# This module supports multiple ways to run cluster tests:
# 1. REDIS_CLUSTER_URL environment variable (external cluster)
# 2. Docker Compose via docker/docker-compose.cluster.yml
# 3. TestContainers with Docker networking
#
# For CI environments, using Docker Compose or external cluster is recommended.
module ClusterTestContainerSupport
  CLUSTER_IMAGE = "grokzen/redis-cluster:7.0.10"
  CLUSTER_PORTS = (7000..7005).to_a
  MASTER_PORTS = [7000, 7001, 7002].freeze
  REPLICA_PORTS = [7003, 7004, 7005].freeze
  COMPOSE_FILE = File.expand_path("../../../docker/docker-compose.cluster.yml", __dir__)
  # External ports when using Docker Compose with port mapping
  COMPOSE_EXTERNAL_PORTS = (17_000..17_005).to_a

  # Detect whether we're running inside a Docker container
  def self.inside_docker?
    @inside_docker ||= begin
      File.exist?("/.dockerenv") || File.read("/proc/1/cgroup").include?("docker")
    rescue StandardError
      false
    end
  end

  # Connect to the cluster network if running inside Docker
  def self.connect_to_network!
    return unless inside_docker?

    container_id = begin
      File.read("/etc/hostname").strip
    rescue StandardError
      nil
    end
    return unless container_id

    # Connect to the cluster network
    system("docker network connect docker_default #{container_id} 2>/dev/null")
  end

  # Detect the Docker host
  # With host networking, cluster nodes bind to host interfaces
  def self.docker_host
    if inside_docker? && @compose_started
      # With host networking, use the Docker host gateway IP
      # This is the IP that host-networked containers use
      gateway = `ip route | grep default | awk '{print $3}'`.strip
      gateway.empty? ? "host.docker.internal" : gateway
    elsif system("getent hosts host.docker.internal >/dev/null 2>&1")
      "host.docker.internal"
    else
      "localhost"
    end
  rescue StandardError
    "localhost"
  end

  # Get host translation map for cluster client
  # Maps 127.0.0.1 (announced by cluster) to actual reachable host
  def self.host_translation
    return nil unless inside_docker? && @compose_started

    target = docker_host
    return nil if target == "127.0.0.1" || target == "localhost"

    { "127.0.0.1" => target }
  end

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
      return true if ENV["REDIS_CLUSTER_URL"]

      system("docker info > /dev/null 2>&1")
    end

    def master_nodes
      @nodes&.select { |n| MASTER_PORTS.include?(n[:internal_port]) }
    end

    def replica_nodes
      @nodes&.select { |n| REPLICA_PORTS.include?(n[:internal_port]) }
    end

    def seed_nodes
      master_nodes&.map { |n| "redis://#{n[:host]}:#{n[:port]}" }
    end

    private

    def use_docker_compose?
      # Prefer Docker Compose if available and not in CI
      File.exist?(COMPOSE_FILE) && !ENV["CI"]
    end

    def start_with_compose!
      puts "Starting Redis Cluster with Docker Compose..."

      # Start the cluster
      result = system("docker-compose -f #{COMPOSE_FILE} up -d 2>&1")
      raise "Docker Compose failed" unless result

      # Set compose_started early for network detection
      @compose_started = true

      # Connect to network if inside Docker
      connect_to_network! if inside_docker?

      # Wait for cluster to be healthy
      wait_for_compose_cluster

      # Build node list - use internal ports when inside Docker, external ports otherwise
      if inside_docker?
        cluster_ip = docker_host
        @nodes = CLUSTER_PORTS.map do |port|
          { host: cluster_ip, port: port, internal_port: port }
        end
      else
        @nodes = CLUSTER_PORTS.each_with_index.map do |internal_port, idx|
          external_port = COMPOSE_EXTERNAL_PORTS[idx]
          { host: docker_host, port: external_port, internal_port: internal_port }
        end
      end

      puts "Redis Cluster started with Docker Compose"
    end

    def stop_compose
      system("docker-compose -f #{COMPOSE_FILE} down 2>&1")
      @compose_started = false
    end

    def wait_for_compose_cluster(timeout: 90)
      host = docker_host
      port = inside_docker? ? CLUSTER_PORTS.first : COMPOSE_EXTERNAL_PORTS.first
      puts "Waiting for cluster to be ready (host: #{host}:#{port})..."
      start_time = Time.now

      loop do
        raise "Timeout waiting for Redis Cluster" if Time.now - start_time > timeout

        begin
          conn = RedisRuby::Connection::TCP.new(
            host: host,
            port: port,
            timeout: 5.0
          )
          result = conn.call("CLUSTER", "INFO")
          conn.close

          if result.include?("cluster_state:ok")
            puts "Cluster is ready!"
            return
          end
        rescue StandardError => e
          puts "Waiting... (#{e.class})"
        end

        sleep 2
      end
    end

    def start_with_testcontainers!
      puts "Starting Redis Cluster with TestContainers..."

      # Create a Docker network for cluster communication
      require "docker"
      @network_name = "redis_cluster_test_#{Process.pid}"
      @network = Docker::Network.create(@network_name)

      # Start the cluster container with network
      @container = Testcontainers::DockerContainer.new(CLUSTER_IMAGE)
      CLUSTER_PORTS.each { |port| @container.with_fixed_exposed_port(port, port) }
      @container.with_env("IP", "0.0.0.0")
      @container.with_env("INITIAL_PORT", "7000")
      @container.start

      # Connect container to network
      @network.connect(@container._id)

      wait_for_cluster_ready

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
      start_time = Time.now

      loop do
        raise "Timeout waiting for Redis Cluster" if Time.now - start_time > timeout

        begin
          conn = RedisRuby::Connection::TCP.new(
            host: @container.host,
            port: 7000,
            timeout: 5.0
          )
          result = conn.call("CLUSTER", "INFO")
          conn.close

          if result.include?("cluster_state:ok")
            puts "Cluster is ready!"
            return
          end
        rescue StandardError => e
          puts "Waiting... (#{e.class}: #{e.message})"
        end

        sleep 2
      end
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

    if ENV["REDIS_CLUSTER_URL"]
      @cluster_nodes = ENV["REDIS_CLUSTER_URL"].split(",")
    elsif self.class.use_cluster_testcontainers?
      begin
        ClusterTestContainerSupport.start!
        @cluster_nodes = ClusterTestContainerSupport.seed_nodes

        # When running inside Docker, cluster nodes announce 127.0.0.1 which isn't
        # accessible. We need to skip unless running in the same network context.
        if ClusterTestContainerSupport.inside_docker?
          # Try a simple connectivity test
          verify_cluster_connectivity!
        end
      rescue StandardError => e
        skip "Failed to start Cluster: #{e.message}"
      end
    else
      skip "REDIS_CLUSTER_URL not set and TestContainers not enabled"
    end

    host_translation = ClusterTestContainerSupport.host_translation
    @cluster = RedisRuby::ClusterClient.new(
      nodes: @cluster_nodes,
      host_translation: host_translation
    )
  end

  def verify_cluster_connectivity!
    # Try to connect and execute a simple command
    # This will fail if the cluster announces addresses we can't reach
    host_translation = ClusterTestContainerSupport.host_translation
    client = RedisRuby::ClusterClient.new(
      nodes: @cluster_nodes,
      host_translation: host_translation
    )
    client.call("PING")
    client.close
  rescue Errno::ECONNREFUSED, RedisRuby::ConnectionError => e
    skip "Cluster nodes announce unreachable addresses (127.0.0.1). " \
         "Set REDIS_CLUSTER_URL for external cluster or use host networking. " \
         "Error: #{e.message}"
  end

  def teardown
    @cluster&.close
  end

  attr_reader :cluster, :cluster_nodes

  private

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
