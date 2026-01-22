# frozen_string_literal: true

require "test_helper"

# Redis Sentinel TestContainers support
#
# Uses bitnami/redis-sentinel Docker images which provide:
# - Configurable master/replica setup
# - Sentinel quorum support
# - Failover capabilities
#
# Based on patterns from redis-rb, redis-py, Jedis, and Lettuce
module SentinelTestContainerSupport
  REDIS_IMAGE = "redis:7.0"
  SENTINEL_IMAGE = "bitnami/redis-sentinel:7.0"
  MASTER_PORT = 6379
  REPLICA_PORT = 6380
  SENTINEL_PORTS = [26379, 26380, 26381]
  SERVICE_NAME = "mymaster"

  class << self
    attr_reader :master_container, :replica_container, :sentinel_containers, :network

    def start!
      return if @started

      puts "Starting Redis Sentinel cluster..."

      # Create a Docker network for the containers
      create_network

      # Start master
      start_master

      # Start replica
      start_replica

      # Start sentinels
      start_sentinels

      # Wait for cluster to be ready
      wait_for_sentinel_ready

      puts "Redis Sentinel cluster ready!"
      @started = true
    end

    def stop!
      return unless @started

      puts "Stopping Redis Sentinel cluster..."

      @sentinel_containers&.each(&:stop)
      @replica_container&.stop
      @master_container&.stop
      cleanup_network

      @started = false
    end

    def started?
      @started
    end

    def sentinel_addresses
      @sentinel_containers&.map do |container|
        {
          host: container.host,
          port: container.mapped_port(26379)
        }
      end
    end

    def master_address
      return nil unless @master_container

      {
        host: @master_container.host,
        port: @master_container.mapped_port(MASTER_PORT)
      }
    end

    def replica_address
      return nil unless @replica_container

      {
        host: @replica_container.host,
        port: @replica_container.mapped_port(REPLICA_PORT)
      }
    end

    def service_name
      SERVICE_NAME
    end

    private

    def create_network
      @network_name = "sentinel_test_#{SecureRandom.hex(4)}"
      system("docker network create #{@network_name} 2>/dev/null")
    end

    def cleanup_network
      system("docker network rm #{@network_name} 2>/dev/null") if @network_name
    end

    def start_master
      puts "Starting Redis master..."

      @master_container = Testcontainers::DockerContainer.new(REDIS_IMAGE)
      @master_container.with_exposed_port(MASTER_PORT)
      @master_container.with_network_aliases(@network_name, "redis-master") if @network_name
      @master_container.start

      wait_for_redis(@master_container, MASTER_PORT)
      puts "Master started at #{@master_container.host}:#{@master_container.mapped_port(MASTER_PORT)}"
    end

    def start_replica
      puts "Starting Redis replica..."

      master_host = @master_container.host
      master_port = @master_container.mapped_port(MASTER_PORT)

      @replica_container = Testcontainers::DockerContainer.new(REDIS_IMAGE)
      @replica_container.with_exposed_port(REPLICA_PORT)
      @replica_container.with_command("redis-server", "--port", REPLICA_PORT.to_s,
                                       "--replicaof", master_host, master_port.to_s)
      @replica_container.with_network_aliases(@network_name, "redis-replica") if @network_name
      @replica_container.start

      wait_for_redis(@replica_container, REPLICA_PORT)
      puts "Replica started at #{@replica_container.host}:#{@replica_container.mapped_port(REPLICA_PORT)}"
    end

    def start_sentinels
      puts "Starting Sentinels..."

      master_host = @master_container.host
      master_port = @master_container.mapped_port(MASTER_PORT)

      @sentinel_containers = []

      3.times do |i|
        container = Testcontainers::DockerContainer.new(SENTINEL_IMAGE)
        container.with_exposed_port(26379)
        container.with_env("REDIS_MASTER_HOST", master_host)
        container.with_env("REDIS_MASTER_PORT_NUMBER", master_port.to_s)
        container.with_env("REDIS_MASTER_SET", SERVICE_NAME)
        container.with_env("REDIS_SENTINEL_QUORUM", "2")
        container.with_env("REDIS_SENTINEL_DOWN_AFTER_MILLISECONDS", "5000")
        container.with_env("REDIS_SENTINEL_FAILOVER_TIMEOUT", "10000")
        container.with_network_aliases(@network_name, "sentinel-#{i}") if @network_name
        container.start

        @sentinel_containers << container
        puts "Sentinel #{i} started at #{container.host}:#{container.mapped_port(26379)}"
      end
    end

    def wait_for_redis(container, port, timeout: 30)
      start_time = Time.now

      loop do
        if Time.now - start_time > timeout
          raise "Timeout waiting for Redis to be ready"
        end

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
        if Time.now - start_time > timeout
          raise "Timeout waiting for Sentinel cluster to be ready"
        end

        begin
          sentinel = @sentinel_containers.first
          port = sentinel.mapped_port(26379)
          conn = RedisRuby::Connection::TCP.new(
            host: sentinel.host,
            port: port,
            timeout: 5.0
          )

          # Check if sentinel knows about the master
          result = conn.call("SENTINEL", "MASTER", SERVICE_NAME)
          conn.close

          if result.is_a?(Array) && result.any?
            # Parse the result to check master status
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

    if self.class.use_sentinel_testcontainers?
      SentinelTestContainerSupport.start!
      @sentinel_addresses = SentinelTestContainerSupport.sentinel_addresses
      @service_name = SentinelTestContainerSupport.service_name
    else
      # Use environment variables for external sentinel
      sentinel_url = ENV["REDIS_SENTINEL_URL"]
      skip "REDIS_SENTINEL_URL not set" unless sentinel_url
      @sentinel_addresses = parse_sentinel_url(sentinel_url)
      @service_name = ENV["REDIS_SENTINEL_SERVICE"] || "mymaster"
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
    return true if self.class.use_sentinel_testcontainers?
    return true if ENV["REDIS_SENTINEL_URL"]

    false
  end

  def skip_sentinel_tests
    skip "Redis Sentinel not available (set REDIS_SENTINEL_URL or use TestContainers)"
  end

  def parse_sentinel_url(url)
    url.split(",").map do |addr|
      host, port = addr.split(":")
      { host: host, port: port.to_i }
    end
  end
end

# Clean up at exit
Minitest.after_run do
  SentinelTestContainerSupport.stop! if SentinelTestContainerSupport.started?
end
