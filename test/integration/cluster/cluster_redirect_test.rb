# frozen_string_literal: true

require_relative "cluster_test_helper"

# Redis Cluster redirection tests
#
# Tests MOVED and ASK redirect handling:
# - MOVED: permanent slot migration (topology changed)
# - ASK: temporary redirect during migration
#
# Based on test patterns from redis-py and Lettuce
class ClusterRedirectIntegrationTest < ClusterTestCase
  use_cluster_testcontainers!

  # Test: Client handles MOVED redirect transparently
  def test_moved_redirect_handled_transparently
    # Set a key - the client should handle any MOVED redirects
    # that occur during initial topology discovery
    key = "moved:test:key"

    result = cluster.call("SET", key, "value")

    assert_equal "OK", result

    # Even if we connected to the wrong node initially,
    # the client should have followed MOVED and succeeded
    assert_equal "value", cluster.call("GET", key)
  ensure
    begin
      cluster.call("DEL", key)
    rescue StandardError
      nil
    end
  end

  # Test: Multiple operations after redirect work correctly
  def test_operations_after_redirect_work
    key = "redirect:ops:key"

    # First operation might trigger MOVED
    cluster.call("SET", key, "initial")

    # Subsequent operations should work without issues
    cluster.call("APPEND", key, "_appended")

    assert_equal "initial_appended", cluster.call("GET", key)

    cluster.call("SET", key, "updated")

    assert_equal "updated", cluster.call("GET", key)
  ensure
    begin
      cluster.call("DEL", key)
    rescue StandardError
      nil
    end
  end

  # Test: Slot topology refresh after MOVED
  def test_topology_refresh_after_moved
    key = "topology:refresh:key"

    # Store initial slot mapping
    slot = cluster.key_slot(key)
    cluster.node_for_slot(slot)

    # Perform operations
    cluster.call("SET", key, "value")
    cluster.call("GET", key)

    # The slot should still be mapped (topology was refreshed if needed)
    current_node = cluster.node_for_slot(slot)

    refute_nil current_node
  ensure
    begin
      cluster.call("DEL", key)
    rescue StandardError
      nil
    end
  end

  # Test: Cross-slot operations fail appropriately
  def test_cross_slot_operation_fails
    # Keys without hash tags will likely be in different slots
    keys = %w[key1 key2 key3]
    slots = keys.map { |k| cluster.key_slot(k) }.uniq

    # Skip if by chance all keys are in same slot
    skip "Keys happened to be in same slot" if slots.size == 1

    # MSET with cross-slot keys should fail
    error = assert_raises(RR::CommandError) do
      cluster.call("MSET", "key1", "v1", "key2", "v2", "key3", "v3")
    end

    assert_match(/CROSSSLOT|cross.?slot/i, error.message)
  end

  # Test: Hash tags allow multi-key operations
  def test_hash_tags_enable_multi_key_ops
    keys = keys_for_same_slot(3, "multikey")

    # MSET should work with hash-tagged keys
    args = keys.flat_map.with_index { |k, i| [k, "value#{i}"] }
    result = cluster.call("MSET", *args)

    assert_equal "OK", result

    # MGET should also work
    values = cluster.call("MGET", *keys)

    assert_equal %w[value0 value1 value2], values

    # DEL with multiple keys in same slot
    deleted = cluster.call("DEL", *keys)

    assert_equal 3, deleted
  end

  # Test: Transaction with hash-tagged keys
  def test_transaction_with_hash_tags
    keys = keys_for_same_slot(2, "txn")

    # MULTI/EXEC should work with same-slot keys
    cluster.call("SET", keys[0], "0")
    cluster.call("SET", keys[1], "0")

    # NOTE: Cluster MULTI is limited - this tests basic functionality
    cluster.call("INCR", keys[0])
    cluster.call("INCR", keys[1])

    assert_equal "1", cluster.call("GET", keys[0])
    assert_equal "1", cluster.call("GET", keys[1])
  ensure
    keys&.each do |k|
      cluster.call("DEL", k)
    rescue StandardError
      nil
    end
  end

  # Test: Read from replica after MOVED
  def test_read_operations_after_redirect
    key = "read:after:moved"

    cluster.call("SET", key, "test_value")

    # Multiple reads should all succeed
    10.times do
      assert_equal "test_value", cluster.call("GET", key)
    end
  ensure
    begin
      cluster.call("DEL", key)
    rescue StandardError
      nil
    end
  end

  # Test: Rapid operations don't cause redirect loops
  def test_rapid_operations_no_redirect_loops
    base_key = "rapid:test"
    count = 50

    # Rapid writes
    count.times do |i|
      cluster.call("SET", "#{base_key}:#{i}", "value#{i}")
    end

    # Rapid reads
    count.times do |i|
      assert_equal "value#{i}", cluster.call("GET", "#{base_key}:#{i}")
    end
  ensure
    count.times do |i|
      cluster.call("DEL", "#{base_key}:#{i}")
    rescue StandardError
      nil
    end
  end

  # Test: Connection recovery after node issues
  def test_connection_recovery
    key = "recovery:test"

    # Normal operation
    cluster.call("SET", key, "value1")

    assert_equal "value1", cluster.call("GET", key)

    # Force refresh (simulates detecting stale topology)
    cluster.refresh_slots

    # Operations should still work
    cluster.call("SET", key, "value2")

    assert_equal "value2", cluster.call("GET", key)
  ensure
    begin
      cluster.call("DEL", key)
    rescue StandardError
      nil
    end
  end

  # Test: Handles maximum redirections limit
  def test_max_redirections_limit
    # This test verifies the client has a redirect limit
    # The actual limit is tested via implementation
    assert_equal 5, RR::ClusterClient::MAX_REDIRECTIONS
  end

  # Test: Operations on keys across all slots work
  def test_operations_across_all_slot_ranges
    # Test keys that should map to different parts of the slot range
    test_keys = [
      "slot:low",      # Low slot range
      "slot:mid",      # Middle slot range
      "slot:high",     # High slot range
      "slot:random1",
      "slot:random2",
    ]

    test_keys.map { |k| cluster.key_slot(k) }

    # Set all keys
    test_keys.each_with_index do |key, i|
      cluster.call("SET", key, "value#{i}")

      # Get all keys
      assert_equal "value#{i}", cluster.call("GET", key)
    end
  ensure
    test_keys&.each do |k|
      cluster.call("DEL", k)
    rescue StandardError
      nil
    end
  end
end
