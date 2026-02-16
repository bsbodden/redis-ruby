# frozen_string_literal: true

require_relative "sentinel_test_helper"

# Redis Sentinel failover and resilience tests
#
# Tests Sentinel behavior during failures and recovery:
# - Master discovery after reconnection
# - Reconnection handling
# - Role verification
#
# Based on test patterns from redis-rb, redis-py, Jedis, and Lettuce
class SentinelFailoverIntegrationTest < SentinelTestCase
  use_sentinel_testcontainers!

  # Test: Client reconnects after disconnect
  def test_reconnection_after_disconnect
    key = "sentinel:reconnect:key"

    # Initial operation
    sentinel_client.call("SET", key, "value1")

    assert_equal "value1", sentinel_client.call("GET", key)

    # Force disconnect
    sentinel_client.reconnect

    # Operations should work after reconnect
    sentinel_client.call("SET", key, "value2")

    assert_equal "value2", sentinel_client.call("GET", key)
  ensure
    begin
      sentinel_client.call("DEL", key)
    rescue StandardError
      nil
    end
  end

  # Test: Multiple reconnections work
  def test_multiple_reconnections
    key = "sentinel:multirecon:key"

    5.times do |i|
      sentinel_client.call("SET", key, "value#{i}")

      assert_equal "value#{i}", sentinel_client.call("GET", key)

      # Force reconnect
      sentinel_client.reconnect
    end

    # Final verification
    sentinel_client.call("SET", key, "final")

    assert_equal "final", sentinel_client.call("GET", key)
  ensure
    begin
      sentinel_client.call("DEL", key)
    rescue StandardError
      nil
    end
  end

  # Test: Client is master role by default
  def test_default_master_role
    assert_predicate sentinel_client, :master?
    refute_predicate sentinel_client, :replica?
  end

  # Test: Can verify connection state
  def test_connection_state
    # Not connected initially
    new_client = create_sentinel_client_with_nat_translation(
      sentinels: sentinel_addresses,
      service_name: service_name
    )

    refute_predicate new_client, :connected?

    # Connected after operation
    new_client.call("PING")

    assert_predicate new_client, :connected?

    # Disconnected after close
    new_client.close

    refute_predicate new_client, :connected?
  end

  # Test: Operations work after close and reopen
  def test_operations_after_reopen
    key = "sentinel:reopen:key"

    # Initial operations
    sentinel_client.call("SET", key, "value1")

    assert_equal "value1", sentinel_client.call("GET", key)

    # Close and create new client
    sentinel_client.close

    new_client = create_sentinel_client_with_nat_translation(
      sentinels: sentinel_addresses,
      service_name: service_name
    )

    # Operations with new client
    new_client.call("SET", key, "value2")

    assert_equal "value2", new_client.call("GET", key)
  ensure
    begin
      new_client&.call("DEL", key)
    rescue StandardError
      nil
    end
    new_client&.close
  end

  # Test: Many operations in sequence
  def test_many_sequential_operations
    key = "sentinel:sequential:key"

    100.times do |i|
      sentinel_client.call("SET", key, "value#{i}")
    end

    assert_equal "value99", sentinel_client.call("GET", key)
  ensure
    begin
      sentinel_client.call("DEL", key)
    rescue StandardError
      nil
    end
  end

  # Test: Data persists across reconnections
  def test_data_persistence_across_reconnections
    key = "sentinel:persist:key"

    # Set data
    sentinel_client.call("SET", key, "persistent_value")

    # Force reconnect multiple times
    3.times do
      sentinel_client.reconnect

      assert_equal "persistent_value", sentinel_client.call("GET", key)
    end
  ensure
    begin
      sentinel_client.call("DEL", key)
    rescue StandardError
      nil
    end
  end

  # Test: Hash operations persist
  def test_hash_persistence
    key = "sentinel:hash:persist"

    sentinel_client.call("HSET", key, "field1", "value1", "field2", "value2")

    sentinel_client.reconnect

    assert_equal "value1", sentinel_client.call("HGET", key, "field1")
    assert_equal "value2", sentinel_client.call("HGET", key, "field2")
  ensure
    begin
      sentinel_client.call("DEL", key)
    rescue StandardError
      nil
    end
  end

  # Test: List operations persist
  def test_list_persistence
    key = "sentinel:list:persist"

    sentinel_client.call("RPUSH", key, "a", "b", "c")

    sentinel_client.reconnect

    assert_equal %w[a b c], sentinel_client.call("LRANGE", key, 0, -1)
  ensure
    begin
      sentinel_client.call("DEL", key)
    rescue StandardError
      nil
    end
  end

  # Test: Counter increments persist
  def test_counter_persistence
    key = "sentinel:counter:persist"

    sentinel_client.call("SET", key, "0")
    10.times { sentinel_client.call("INCR", key) }

    sentinel_client.reconnect

    assert_equal "10", sentinel_client.call("GET", key)
  ensure
    begin
      sentinel_client.call("DEL", key)
    rescue StandardError
      nil
    end
  end

  # Test: Client handles rapid reconnections
  def test_rapid_reconnections
    key = "sentinel:rapid:key"

    20.times do |i|
      sentinel_client.call("SET", key, "value#{i}")
      sentinel_client.reconnect if i.even?
    end

    assert_equal "value19", sentinel_client.call("GET", key)
  ensure
    begin
      sentinel_client.call("DEL", key)
    rescue StandardError
      nil
    end
  end

  # Test: Sentinel manager accessible
  def test_sentinel_manager_accessible
    refute_nil sentinel_client.sentinel_manager
    assert_kind_of RR::SentinelManager, sentinel_client.sentinel_manager
  end

  # Test: Current address available after connection
  def test_current_address_available
    sentinel_client.call("PING")

    address = sentinel_client.current_address

    refute_nil address
    refute_nil address[:host]
    refute_nil address[:port]
  end

  # Test: Service name accessible
  def test_service_name_accessible
    assert_equal service_name, sentinel_client.service_name
  end

  # Test: Role accessible
  def test_role_accessible
    assert_equal :master, sentinel_client.role
  end
end
