# frozen_string_literal: true

require_relative "sentinel_test_helper"

# Basic Redis Sentinel integration tests
#
# Tests fundamental Sentinel operations:
# - Master discovery
# - Replica discovery
# - Basic CRUD operations via Sentinel
# - Sentinel commands
#
# Based on test patterns from redis-rb, redis-py, Jedis, and Lettuce
class SentinelBasicIntegrationTest < SentinelTestCase
  use_sentinel_testcontainers!

  # Test: Discover master through Sentinel
  def test_discover_master
    # Force connection to discover master
    sentinel_client.call("PING")

    # After connecting, current_address should be set
    master = sentinel_client.current_address
    assert_not_nil master
    assert_not_nil master[:host]
    assert_not_nil master[:port]
    assert_kind_of Integer, master[:port]
  end

  # Test: Basic SET/GET via Sentinel client
  def test_set_and_get_via_sentinel
    key = "sentinel:basic:key"

    result = sentinel_client.call("SET", key, "hello")
    assert_equal "OK", result

    result = sentinel_client.call("GET", key)
    assert_equal "hello", result
  ensure
    sentinel_client.call("DEL", key) rescue nil
  end

  # Test: Multiple operations via Sentinel
  def test_multiple_operations
    keys = 10.times.map { |i| "sentinel:multi:#{i}" }

    # Set all keys
    keys.each_with_index do |key, i|
      sentinel_client.call("SET", key, "value#{i}")
    end

    # Get all keys
    keys.each_with_index do |key, i|
      assert_equal "value#{i}", sentinel_client.call("GET", key)
    end
  ensure
    keys&.each { |k| sentinel_client.call("DEL", k) rescue nil }
  end

  # Test: PING works via Sentinel
  def test_ping
    result = sentinel_client.call("PING")
    assert_equal "PONG", result
  end

  # Test: Hash operations via Sentinel
  def test_hash_operations
    key = "sentinel:hash"

    sentinel_client.call("HSET", key, "field1", "value1", "field2", "value2")
    assert_equal "value1", sentinel_client.call("HGET", key, "field1")
    assert_equal "value2", sentinel_client.call("HGET", key, "field2")
  ensure
    sentinel_client.call("DEL", key) rescue nil
  end

  # Test: List operations via Sentinel
  def test_list_operations
    key = "sentinel:list"

    sentinel_client.call("RPUSH", key, "a", "b", "c")
    assert_equal 3, sentinel_client.call("LLEN", key)
    assert_equal ["a", "b", "c"], sentinel_client.call("LRANGE", key, 0, -1)
  ensure
    sentinel_client.call("DEL", key) rescue nil
  end

  # Test: Set operations via Sentinel
  def test_set_operations
    key = "sentinel:set"

    sentinel_client.call("SADD", key, "a", "b", "c")
    assert_equal 3, sentinel_client.call("SCARD", key)
  ensure
    sentinel_client.call("DEL", key) rescue nil
  end

  # Test: INCR/DECR via Sentinel
  def test_incr_decr
    key = "sentinel:counter"

    sentinel_client.call("SET", key, "10")
    assert_equal 11, sentinel_client.call("INCR", key)
    assert_equal 12, sentinel_client.call("INCR", key)
    assert_equal 11, sentinel_client.call("DECR", key)
  ensure
    sentinel_client.call("DEL", key) rescue nil
  end

  # Test: TTL operations via Sentinel
  def test_ttl_operations
    key = "sentinel:ttl"

    sentinel_client.call("SET", key, "value")
    sentinel_client.call("EXPIRE", key, 100)

    ttl = sentinel_client.call("TTL", key)
    assert_operator ttl, :>, 0
    assert_operator ttl, :<=, 100
  ensure
    sentinel_client.call("DEL", key) rescue nil
  end

  # Test: EXISTS operation via Sentinel
  def test_exists
    key = "sentinel:exists"

    assert_equal 0, sentinel_client.call("EXISTS", key)

    sentinel_client.call("SET", key, "value")
    assert_equal 1, sentinel_client.call("EXISTS", key)
  ensure
    sentinel_client.call("DEL", key) rescue nil
  end

  # Test: DEL operation via Sentinel
  def test_delete
    key = "sentinel:delete"

    sentinel_client.call("SET", key, "value")
    assert_equal "value", sentinel_client.call("GET", key)

    result = sentinel_client.call("DEL", key)
    assert_equal 1, result

    assert_nil sentinel_client.call("GET", key)
  end

  # Test: Large value via Sentinel
  def test_large_value
    key = "sentinel:large"
    large_value = "x" * 100_000

    sentinel_client.call("SET", key, large_value)
    result = sentinel_client.call("GET", key)
    assert_equal large_value, result
  ensure
    sentinel_client.call("DEL", key) rescue nil
  end

  # Test: Binary data via Sentinel
  def test_binary_data
    key = "sentinel:binary"
    binary_value = (0..255).map(&:chr).join.b

    sentinel_client.call("SET", key, binary_value)
    result = sentinel_client.call("GET", key)
    assert_equal binary_value, result.b
  ensure
    sentinel_client.call("DEL", key) rescue nil
  end

  # Test: Connection maintains after multiple operations
  def test_connection_persistence
    key = "sentinel:persist"

    100.times do |i|
      sentinel_client.call("SET", key, "value#{i}")
      assert_equal "value#{i}", sentinel_client.call("GET", key)
    end
  ensure
    sentinel_client.call("DEL", key) rescue nil
  end
end
