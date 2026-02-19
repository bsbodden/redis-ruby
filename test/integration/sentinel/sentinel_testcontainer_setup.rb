# frozen_string_literal: true

# TestContainer setup methods for sentinel tests
module SentinelTestcontainerSetup
  def start_with_testcontainers!
    puts "Starting Redis Sentinel with TestContainers..."

    create_docker_network
    start_master_tc
    start_replica_tc
    start_sentinels_tc
    wait_for_sentinel_ready

    puts "Redis Sentinel cluster ready!"
  end

  private

  def create_docker_network
    require "docker"
    @network_name = "redis_sentinel_test_#{Process.pid}"
    @network = Docker::Network.create(@network_name)
  end

  def start_master_tc
    puts "Starting Redis master..."

    @master_container = Testcontainers::DockerContainer.new(REDIS_IMAGE)
    @master_container.with_exposed_port(MASTER_INTERNAL_PORT)
    @master_container.with_name("redis-master-#{Process.pid}")
    @master_container.start

    @network.connect(@master_container._id, { "Aliases" => ["redis-master"] })
    wait_for_redis(@master_container, MASTER_INTERNAL_PORT)
    puts "Master started at #{@master_container.host}:#{@master_container.mapped_port(MASTER_INTERNAL_PORT)}"
  end

  def start_replica_tc
    puts "Starting Redis replica..."

    @replica_container = Testcontainers::DockerContainer.new(REDIS_IMAGE)
    @replica_container.with_exposed_port(MASTER_INTERNAL_PORT)
    @replica_container.with_command("redis-server", "--port", MASTER_INTERNAL_PORT.to_s,
                                    "--replicaof", "redis-master", MASTER_INTERNAL_PORT.to_s)
    @replica_container.with_name("redis-replica-#{Process.pid}")
    @replica_container.start

    @network.connect(@replica_container._id, { "Aliases" => ["redis-replica"] })
    wait_for_redis(@replica_container, MASTER_INTERNAL_PORT)
    puts "Replica started at #{@replica_container.host}:#{@replica_container.mapped_port(MASTER_INTERNAL_PORT)}"
  end

  def start_sentinels_tc
    puts "Starting Sentinels..."
    @sentinel_containers = []
    3.times { |i| start_single_sentinel(i) }
  end

  def start_single_sentinel(index)
    container = Testcontainers::DockerContainer.new(SENTINEL_IMAGE)
    configure_sentinel_container(container, index)
    container.start
    @network.connect(container._id, { "Aliases" => ["sentinel-#{index}"] })
    @sentinel_containers << container
    puts "Sentinel #{index} started at #{container.host}:#{container.mapped_port(26_379)}"
  end

  def configure_sentinel_container(container, index)
    container.with_exposed_port(26_379)
    container.with_env("REDIS_MASTER_HOST", "redis-master")
    container.with_env("REDIS_MASTER_PORT_NUMBER", MASTER_INTERNAL_PORT.to_s)
    container.with_env("REDIS_MASTER_SET", SERVICE_NAME)
    container.with_env("REDIS_SENTINEL_QUORUM", "2")
    container.with_env("REDIS_SENTINEL_DOWN_AFTER_MILLISECONDS", "5000")
    container.with_env("REDIS_SENTINEL_FAILOVER_TIMEOUT", "10000")
    container.with_name("sentinel-#{index}-#{Process.pid}")
  end

  def wait_for_sentinel_ready(timeout: 60)
    puts "Waiting for Sentinel cluster to be ready..."
    start_time = Time.now

    loop do
      raise "Timeout waiting for Sentinel cluster" if Time.now - start_time > timeout
      break if check_sentinel_container_ready

      sleep 1
    end
    puts "Sentinel cluster is ready!"
  end

  def check_sentinel_container_ready
    sentinel = @sentinel_containers.first
    port = sentinel.mapped_port(26_379)
    conn = RR::Connection::TCP.new(host: sentinel.host, port: port, timeout: 5.0)
    result = conn.call("SENTINEL", "MASTER", SERVICE_NAME)
    conn.close

    return false unless result.is_a?(Array) && result.any?

    info = parse_sentinel_info(result)
    info["flags"] && !info["flags"].include?("down")
  rescue StandardError => e
    puts "Waiting... (#{e.class}: #{e.message})"
    false
  end
end
