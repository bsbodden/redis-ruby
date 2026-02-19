# frozen_string_literal: true

require_relative "sentinel_test_helper"

# Redis Sentinel commands integration tests
#
# Tests Sentinel-specific commands:
# - SENTINEL MASTER
# - SENTINEL REPLICAS
# - SENTINEL SENTINELS
# - SENTINEL GET-MASTER-ADDR-BY-NAME
#
# Based on test patterns from redis-rb, redis-py, Jedis, and Lettuce
class SentinelCommandsIntegrationTest < SentinelTestCase
  use_sentinel_testcontainers!

  # Test: SENTINEL MASTER returns master info
  def test_sentinel_master
    # Connect directly to a sentinel
    sentinel = connect_to_sentinel

    result = sentinel.call("SENTINEL", "MASTER", service_name)

    assert_kind_of Array, result

    # Parse into hash
    info = parse_array_to_hash(result)

    assert_equal service_name, info["name"]
    refute_nil info["ip"]
    refute_nil info["port"]
    assert_includes info["flags"], "master"
  ensure
    sentinel&.close
  end

  # Test: SENTINEL GET-MASTER-ADDR-BY-NAME returns address
  def test_sentinel_get_master_addr
    sentinel = connect_to_sentinel

    result = sentinel.call("SENTINEL", "GET-MASTER-ADDR-BY-NAME", service_name)

    assert_kind_of Array, result
    assert_equal 2, result.size

    host, port = result

    refute_nil host
    assert_kind_of String, port # Port comes as string
    assert_match(/^\d+$/, port)
  ensure
    sentinel&.close
  end

  # Test: SENTINEL REPLICAS returns replica info
  def test_sentinel_replicas
    sentinel = connect_to_sentinel

    result = sentinel.call("SENTINEL", "REPLICAS", service_name)

    assert_kind_of Array, result

    # Should have at least one replica in our test setup
    # (may be empty if replica hasn't registered yet)
    if result.any?
      replica_info = parse_array_to_hash(result.first)

      refute_nil replica_info["ip"]
      refute_nil replica_info["port"]
      assert_includes replica_info["flags"], "slave"
    end
  ensure
    sentinel&.close
  end

  # Test: SENTINEL SENTINELS returns other sentinels
  def test_sentinel_sentinels
    sentinel = connect_to_sentinel

    result = sentinel.call("SENTINEL", "SENTINELS", service_name)

    assert_kind_of Array, result

    # Should see other sentinels (we have 3, so should see 2 others)
    # May take time for sentinels to discover each other
    if result.any?
      other_sentinel = parse_array_to_hash(result.first)

      refute_nil other_sentinel["ip"]
      refute_nil other_sentinel["port"]
      assert_includes other_sentinel["flags"], "sentinel"
    end
  ensure
    sentinel&.close
  end

  # Test: SENTINEL CKQUORUM checks quorum
  def test_sentinel_ckquorum
    sentinel = connect_to_sentinel

    result = sentinel.call("SENTINEL", "CKQUORUM", service_name)
    # Should return OK message if quorum is reachable
    assert_match(/OK|NOQUORUM/, result.to_s)
  ensure
    sentinel&.close
  end

  # Test: SENTINEL MYID returns sentinel ID
  def test_sentinel_myid
    sentinel = connect_to_sentinel

    result = sentinel.call("SENTINEL", "MYID")

    assert_kind_of String, result
    assert_equal 40, result.length # Redis IDs are 40 hex chars
  ensure
    sentinel&.close
  end

  # Test: SENTINEL MASTERS returns all masters
  def test_sentinel_masters
    sentinel = connect_to_sentinel

    result = sentinel.call("SENTINEL", "MASTERS")

    assert_kind_of Array, result
    assert_operator result.size, :>=, 1

    master_info = parse_array_to_hash(result.first)

    assert_equal service_name, master_info["name"]
    assert_includes master_info["flags"], "master"
  ensure
    sentinel&.close
  end

  # Test: INFO command on sentinel
  def test_sentinel_info
    sentinel = connect_to_sentinel

    result = sentinel.call("INFO", "sentinel")

    assert_kind_of String, result
    assert_match(/sentinel_masters/, result)
  ensure
    sentinel&.close
  end

  # Test: PING on sentinel
  def test_sentinel_ping
    sentinel = connect_to_sentinel

    result = sentinel.call("PING")

    assert_equal "PONG", result
  ensure
    sentinel&.close
  end

  # Test: Client can reconnect to master after getting address
  def test_reconnect_to_discovered_master
    host, port = discover_master_address
    master_conn = connect_to_master(host, port)

    assert_match(/role:master/, master_conn.call("INFO", "replication"))

    master_conn.call("SET", "direct:test", "value")

    assert_equal "value", master_conn.call("GET", "direct:test")
  ensure
    begin
      master_conn&.call("DEL", "direct:test")
    rescue StandardError
      nil
    end
    master_conn&.close
  end

  private

  def discover_master_address
    sentinel = connect_to_sentinel
    result = sentinel.call("SENTINEL", "GET-MASTER-ADDR-BY-NAME", service_name)
    sentinel.close
    translate_docker_address(*result)
  end

  def translate_docker_address(host, port)
    if host.match?(/^172\.\d+\.\d+\.\d+$/) || host.match?(/^192\.168\.\d+\.\d+$/)
      translated_port = case port.to_i
                        when 6379 then SentinelTestContainerSupport::MASTER_PORT
                        when 6380 then SentinelTestContainerSupport::REPLICA_PORT
                        else port.to_i
                        end
      ["127.0.0.1", translated_port]
    else
      [host, port.to_i]
    end
  end

  def connect_to_master(host, port)
    RR::Connection::TCP.new(host: host, port: port, timeout: 5.0)
  end

  def connect_to_sentinel
    addr = sentinel_addresses.first
    RR::Connection::TCP.new(
      host: addr[:host],
      port: addr[:port],
      timeout: 5.0
    )
  end

  def parse_array_to_hash(array)
    return {} unless array.is_a?(Array)

    hash = {}
    array.each_slice(2) do |key, value|
      hash[key] = value if key.is_a?(String)
    end
    hash
  end
end
