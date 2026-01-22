# frozen_string_literal: true

require "test_helper"

# Redis Cluster TestContainers support
#
# Uses grokzen/redis-cluster Docker image which provides:
# - 6 nodes (3 masters + 3 replicas)
# - Ports 7000-7005
# - Pre-configured cluster with 16384 slots distributed
#
# Based on patterns from redis-rb, redis-py, Jedis, and Lettuce
module ClusterTestContainerSupport
  CLUSTER_IMAGE = "grokzen/redis-cluster:7.0.10"
  CLUSTER_PORTS = (7000..7005).to_a
  MASTER_PORTS = [7000, 7001, 7002]
  REPLICA_PORTS = [7003, 7004, 7005]

  class << self
    attr_reader :container, :nodes

    def start!
      return if @started

      puts "Starting Redis Cluster container..."

      @container = Testcontainers::DockerContainer.new(CLUSTER_IMAGE)

      # Expose all cluster ports
      CLUSTER_PORTS.each do |port|
        @container.with_exposed_port(port)
      end

      # Set IP to 0.0.0.0 so cluster announces accessible addresses
      @container.with_env("IP", "0.0.0.0")

      @container.start

      # Wait for cluster to be ready
      wait_for_cluster_ready

      # Build node list with mapped ports
      @nodes = CLUSTER_PORTS.map do |port|
        mapped_port = @container.mapped_port(port)
        {
          host: @container.host,
          port: mapped_port,
          internal_port: port
        }
      end

      puts "Redis Cluster started with nodes: #{@nodes.map { |n| "#{n[:host]}:#{n[:port]}" }.join(', ')}"
      @started = true
    end

    def stop!
      return unless @started

      puts "Stopping Redis Cluster container..."
      @container&.stop
      @started = false
    end

    def started?
      @started
    end

    def master_nodes
      @nodes&.select { |n| MASTER_PORTS.include?(n[:internal_port]) }
    end

    def replica_nodes
      @nodes&.select { |n| REPLICA_PORTS.include?(n[:internal_port]) }
    end

    def seed_nodes
      # Return seed nodes in URL format
      master_nodes&.map { |n| "redis://#{n[:host]}:#{n[:port]}" }
    end

    private

    def wait_for_cluster_ready(timeout: 60)
      puts "Waiting for cluster to be ready..."
      start_time = Time.now

      loop do
        if Time.now - start_time > timeout
          raise "Timeout waiting for Redis Cluster to be ready"
        end

        begin
          # Try to connect to first node and check cluster state
          port = @container.mapped_port(7000)
          conn = RedisRuby::Connection::TCP.new(
            host: @container.host,
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
          # Cluster not ready yet
          puts "Waiting... (#{e.class}: #{e.message})"
        end

        sleep 1
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

    if self.class.use_cluster_testcontainers?
      ClusterTestContainerSupport.start!
      @cluster_nodes = ClusterTestContainerSupport.seed_nodes
    else
      # Use environment variable for external cluster
      cluster_url = ENV["REDIS_CLUSTER_URL"]
      skip "REDIS_CLUSTER_URL not set" unless cluster_url
      @cluster_nodes = cluster_url.split(",")
    end

    @cluster = RedisRuby::ClusterClient.new(nodes: @cluster_nodes)
  end

  def teardown
    @cluster&.close
  end

  attr_reader :cluster, :cluster_nodes

  private

  def cluster_available?
    # Skip if running in CI without cluster support
    return true if self.class.use_cluster_testcontainers?
    return true if ENV["REDIS_CLUSTER_URL"]

    false
  end

  def skip_cluster_tests
    skip "Redis Cluster not available (set REDIS_CLUSTER_URL or use TestContainers)"
  end

  # Helper to generate keys that hash to specific slots
  def key_for_slot(slot)
    # Find a key that hashes to the desired slot
    1000.times do |i|
      key = "key#{i}"
      return key if @cluster.key_slot(key) == slot
    end
    raise "Could not find key for slot #{slot}"
  end

  # Helper to generate keys with hash tags for same slot
  def keys_for_same_slot(count, tag = "test")
    count.times.map { |i| "{#{tag}}:key#{i}" }
  end
end

# Clean up at exit
Minitest.after_run do
  ClusterTestContainerSupport.stop! if ClusterTestContainerSupport.started?
end
