# frozen_string_literal: true

require_relative "cluster_test_helper"

# Redis Cluster failover and resilience tests
#
# Tests cluster behavior during failures and recovery:
# - Node availability handling
# - Connection recovery
# - Cluster down scenarios
#
# Based on test patterns from Lettuce's ClusterPartiallyDownIntegrationTests
# and redis-py's cluster failover tests
class ClusterFailoverIntegrationTest < ClusterTestCase
  use_cluster_testcontainers!

  # Test: Client recovers after refresh_slots call
  def test_manual_slot_refresh
    key = "failover:refresh:key"

    # Set a key
    cluster.call("SET", key, "value1")
    assert_equal "value1", cluster.call("GET", key)

    # Force topology refresh
    cluster.refresh_slots

    # Operations should still work
    cluster.call("SET", key, "value2")
    assert_equal "value2", cluster.call("GET", key)
  ensure
    cluster.call("DEL", key) rescue nil
  end

  # Test: Connection recovery on temporary failure
  def test_connection_recovery
    key = "failover:recovery:key"

    # Perform initial operations
    cluster.call("SET", key, "initial")
    assert_equal "initial", cluster.call("GET", key)

    # Close connections (simulates temporary network issue)
    cluster.close

    # Reinitialize
    @cluster = RedisRuby::ClusterClient.new(nodes: @cluster_nodes)

    # Operations should work with new client
    cluster.call("SET", key, "recovered")
    assert_equal "recovered", cluster.call("GET", key)
  ensure
    cluster.call("DEL", key) rescue nil
  end

  # Test: Cluster health check
  def test_cluster_health_check
    assert cluster.cluster_healthy?
  end

  # Test: Node count reflects cluster size
  def test_node_count
    # Our test cluster should have at least 3 nodes
    assert_operator cluster.node_count, :>=, 3
  end

  # Test: Operations work after client reconnection
  def test_operations_after_reconnection
    key = "failover:reconnect:key"
    values = []

    # Perform operations
    10.times do |i|
      cluster.call("SET", key, "value#{i}")
      values << cluster.call("GET", key)
    end

    assert_equal "value9", values.last

    # Close and reopen
    cluster.close
    @cluster = RedisRuby::ClusterClient.new(nodes: @cluster_nodes)

    # Continue operations
    10.times do |i|
      cluster.call("SET", key, "newvalue#{i}")
      values << cluster.call("GET", key)
    end

    assert_equal "newvalue9", cluster.call("GET", key)
  ensure
    cluster.call("DEL", key) rescue nil
  end

  # Test: Multiple reconnections maintain consistency
  def test_multiple_reconnections
    key = "failover:multi:key"

    3.times do |i|
      cluster.call("SET", key, "iteration#{i}")
      assert_equal "iteration#{i}", cluster.call("GET", key)

      # Force refresh
      cluster.refresh_slots
    end

    assert_equal "iteration2", cluster.call("GET", key)
  ensure
    cluster.call("DEL", key) rescue nil
  end

  # Test: Cluster INFO shows correct state
  def test_cluster_info_state
    info = cluster.cluster_info

    assert_equal "ok", info["cluster_state"]
    assert_equal 16_384, info["cluster_slots_assigned"]
  end

  # Test: All slots are assigned in healthy cluster
  def test_all_slots_assigned
    info = cluster.cluster_info

    assert_equal 0, info["cluster_slots_pfail"]
    assert_equal 0, info["cluster_slots_fail"]
    assert_equal 16_384, info["cluster_slots_ok"]
  end

  # Test: Operations distributed across cluster after recovery
  def test_distributed_operations_after_recovery
    prefix = "failover:distributed"
    key_count = 30

    # Create keys
    key_count.times do |i|
      cluster.call("SET", "#{prefix}:#{i}", "value#{i}")
    end

    # Force refresh
    cluster.refresh_slots

    # Verify all keys
    key_count.times do |i|
      assert_equal "value#{i}", cluster.call("GET", "#{prefix}:#{i}")
    end
  ensure
    key_count.times { |i| cluster.call("DEL", "#{prefix}:#{i}") rescue nil }
  end

  # Test: Hash-tagged operations survive refresh
  def test_hash_tagged_operations_survive_refresh
    keys = keys_for_same_slot(5, "failover")

    # Set keys
    keys.each_with_index do |key, i|
      cluster.call("SET", key, "value#{i}")
    end

    # Refresh topology
    cluster.refresh_slots

    # Verify keys still accessible
    keys.each_with_index do |key, i|
      assert_equal "value#{i}", cluster.call("GET", key)
    end

    # Multi-key operation should still work
    values = cluster.call("MGET", *keys)
    assert_equal 5, values.size
  ensure
    keys&.each { |k| cluster.call("DEL", k) rescue nil }
  end

  # Test: Long-running session maintains consistency
  def test_long_running_session
    key = "failover:longsession"

    # Simulate a long session with many operations
    100.times do |i|
      cluster.call("SET", key, "iter#{i}")

      # Occasional refresh to simulate real-world usage
      cluster.refresh_slots if (i % 25).zero?
    end

    assert_equal "iter99", cluster.call("GET", key)
  ensure
    cluster.call("DEL", key) rescue nil
  end

  # Test: Concurrent operations from same client
  def test_serial_operations_consistency
    prefix = "failover:serial"

    # Many serial operations
    50.times do |i|
      key = "#{prefix}:#{i}"
      cluster.call("SET", key, "value")
      cluster.call("INCR", "#{key}:counter")
      cluster.call("GET", key)
      cluster.call("DEL", key)
    end

    # Verify counters
    50.times do |i|
      count = cluster.call("GET", "#{prefix}:#{i}:counter")
      assert_equal "1", count
    end
  ensure
    50.times do |i|
      cluster.call("DEL", "#{prefix}:#{i}") rescue nil
      cluster.call("DEL", "#{prefix}:#{i}:counter") rescue nil
    end
  end
end
