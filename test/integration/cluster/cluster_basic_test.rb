# frozen_string_literal: true

require_relative "cluster_test_helper"

# Basic Redis Cluster integration tests
#
# Tests fundamental cluster operations:
# - Key routing to correct nodes
# - Hash tag support
# - Basic CRUD operations
# - Cluster commands
#
# Based on test patterns from redis-rb, redis-py, Jedis, and Lettuce
class ClusterBasicIntegrationTest < ClusterTestCase
  use_cluster_testcontainers!

  # Test: Basic SET/GET with automatic routing
  def test_set_and_get_routes_to_correct_node
    # Keys will route to different nodes based on hash slot
    keys = %w[foo bar baz hello world test]

    keys.each do |key|
      result = cluster.call("SET", key, "value_#{key}")

      assert_equal "OK", result

      result = cluster.call("GET", key)

      assert_equal "value_#{key}", result
    end
  ensure
    keys&.each do |k|
      cluster.call("DEL", k)
    rescue StandardError
      nil
    end
  end

  # Test: Hash slots are distributed (keys go to different nodes)
  def test_keys_distributed_across_slots
    keys = %w[foo bar baz qux hello world test key123]
    slots = keys.map { |k| cluster.key_slot(k) }

    # Should have at least 2 different slots for these keys
    assert_operator slots.uniq.size, :>=, 2, "Expected keys to map to different slots"
  end

  # Test: Hash tags force keys to same slot
  def test_hash_tags_colocate_keys
    keys = keys_for_same_slot(5, "mygroup")

    slots = keys.map { |k| cluster.key_slot(k) }

    assert_equal 1, slots.uniq.size, "Hash tagged keys should all be in same slot"

    # Set and verify all keys
    keys.each_with_index do |key, i|
      cluster.call("SET", key, "value#{i}")

      assert_equal "value#{i}", cluster.call("GET", key)
    end
  ensure
    keys&.each do |k|
      cluster.call("DEL", k)
    rescue StandardError
      nil
    end
  end

  # Test: MSET/MGET with hash-tagged keys (same slot)
  def test_mset_mget_same_slot
    keys = keys_for_same_slot(3, "mset")
    values = keys.map.with_index { |k, i| [k, "val#{i}"] }.flatten

    result = cluster.call("MSET", *values)

    assert_equal "OK", result

    result = cluster.call("MGET", *keys)

    assert_equal %w[val0 val1 val2], result
  ensure
    keys&.each do |k|
      cluster.call("DEL", k)
    rescue StandardError
      nil
    end
  end

  # Test: CLUSTER INFO returns cluster state
  def test_cluster_info
    info = cluster.cluster_info

    assert_kind_of Hash, info
    assert_equal "ok", info["cluster_state"]
    assert_equal 16_384, info["cluster_slots_assigned"]
    assert_operator info["cluster_known_nodes"], :>=, 3
  end

  # Test: CLUSTER KEYSLOT returns correct slot
  def test_cluster_keyslot
    # Test some known keys
    slot = cluster.call("CLUSTER", "KEYSLOT", "foo")

    assert_kind_of Integer, slot
    assert_operator slot, :>=, 0
    assert_operator slot, :<, 16_384

    # Verify it matches our local calculation
    assert_equal cluster.key_slot("foo"), slot
  end

  # Test: INCR/DECR work correctly with routing
  def test_incr_decr_operations
    key = "cluster:counter"

    cluster.call("SET", key, "10")

    assert_equal 11, cluster.call("INCR", key)
    assert_equal 12, cluster.call("INCR", key)
    assert_equal 11, cluster.call("DECR", key)
    assert_equal "11", cluster.call("GET", key)
  ensure
    begin
      cluster.call("DEL", key)
    rescue StandardError
      nil
    end
  end

  # Test: HSET/HGET work correctly
  def test_hash_operations
    key = "cluster:hash"

    cluster.call("HSET", key, "field1", "value1", "field2", "value2")

    assert_equal "value1", cluster.call("HGET", key, "field1")
    assert_equal "value2", cluster.call("HGET", key, "field2")

    all = cluster.call("HGETALL", key)

    assert_includes all, "field1"
    assert_includes all, "value1"
  ensure
    begin
      cluster.call("DEL", key)
    rescue StandardError
      nil
    end
  end

  # Test: LIST operations
  def test_list_operations
    key = "cluster:list"

    cluster.call("RPUSH", key, "a", "b", "c")

    assert_equal 3, cluster.call("LLEN", key)
    assert_equal %w[a b c], cluster.call("LRANGE", key, 0, -1)
  ensure
    begin
      cluster.call("DEL", key)
    rescue StandardError
      nil
    end
  end

  # Test: SET operations
  def test_set_operations
    key = "cluster:set"

    cluster.call("SADD", key, "a", "b", "c")

    assert_equal 3, cluster.call("SCARD", key)
    assert_equal 1, cluster.call("SISMEMBER", key, "a")
  ensure
    begin
      cluster.call("DEL", key)
    rescue StandardError
      nil
    end
  end

  # Test: SORTED SET operations
  def test_sorted_set_operations
    key = "cluster:zset"

    cluster.call("ZADD", key, 1, "a", 2, "b", 3, "c")

    assert_equal 3, cluster.call("ZCARD", key)
    assert_equal %w[a b c], cluster.call("ZRANGE", key, 0, -1)
  ensure
    begin
      cluster.call("DEL", key)
    rescue StandardError
      nil
    end
  end

  # Test: TTL and EXPIRE work
  def test_ttl_operations
    key = "cluster:ttl"

    cluster.call("SET", key, "value")
    cluster.call("EXPIRE", key, 100)

    ttl = cluster.call("TTL", key)

    assert_operator ttl, :>, 0
    assert_operator ttl, :<=, 100
  ensure
    begin
      cluster.call("DEL", key)
    rescue StandardError
      nil
    end
  end

  # Test: DELETE operation
  def test_delete_operation
    key = "cluster:delete"

    cluster.call("SET", key, "value")

    assert_equal "value", cluster.call("GET", key)

    result = cluster.call("DEL", key)

    assert_equal 1, result

    assert_nil cluster.call("GET", key)
  end

  # Test: EXISTS operation
  def test_exists_operation
    key = "cluster:exists"

    assert_equal 0, cluster.call("EXISTS", key)

    cluster.call("SET", key, "value")

    assert_equal 1, cluster.call("EXISTS", key)
  ensure
    begin
      cluster.call("DEL", key)
    rescue StandardError
      nil
    end
  end

  # Test: Large number of keys distributed across cluster
  def test_many_keys_distributed
    key_count = 100
    keys = Array.new(key_count) { |i| "bulk:#{i}" }

    # Set all keys
    keys.each_with_index do |key, i|
      cluster.call("SET", key, "value#{i}")

      # Verify all keys
      assert_equal "value#{i}", cluster.call("GET", key)
    end

    # Check slot distribution
    slots = keys.map { |k| cluster.key_slot(k) }.uniq

    assert_operator slots.size, :>, 1, "Keys should be distributed across multiple slots"
  ensure
    keys&.each do |k|
      cluster.call("DEL", k)
    rescue StandardError
      nil
    end
  end
end
