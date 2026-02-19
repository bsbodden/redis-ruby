# frozen_string_literal: true

require_relative "../test_helper"

class ActiveActiveIntegrationTest < Minitest::Test
  def setup
    # NOTE: These tests require Redis Enterprise with Active-Active databases
    # For testing purposes, we'll use a single Redis instance simulating multiple regions
    @redis_host = ENV.fetch("REDIS_HOST", "localhost")
    @redis_port = ENV.fetch("REDIS_PORT", "6379").to_i

    # Simulate multiple regions pointing to the same Redis instance
    # In production, these would be different geographic endpoints
    @regions = [
      { host: @redis_host, port: @redis_port },
      { host: @redis_host, port: @redis_port },
      { host: @redis_host, port: @redis_port },
    ]

    @client = RR.active_active(regions: @regions)
  end

  def teardown
    @client&.close
  end

  def test_basic_string_operations
    key = "active_active:test:#{SecureRandom.hex(8)}"

    @client.set(key, "hello")

    assert_equal "hello", @client.get(key)

    @client.del(key)
  end

  def test_hash_operations
    key = "active_active:hash:#{SecureRandom.hex(8)}"

    @client.hset(key, "field1", "value1")
    @client.hset(key, "field2", "value2")

    assert_equal "value1", @client.hget(key, "field1")
    assert_equal "value2", @client.hget(key, "field2")

    result = @client.hgetall(key)

    assert_equal({ "field1" => "value1", "field2" => "value2" }, result)

    @client.del(key)
  end

  def test_list_operations
    key = "active_active:list:#{SecureRandom.hex(8)}"

    @client.lpush(key, "item1")
    @client.lpush(key, "item2")
    @client.lpush(key, "item3")

    assert_equal %w[item3 item2 item1], @client.lrange(key, 0, -1)

    @client.del(key)
  end

  def test_set_operations
    key = "active_active:set:#{SecureRandom.hex(8)}"

    @client.sadd(key, "member1")
    @client.sadd(key, "member2")
    @client.sadd(key, "member3")

    members = @client.smembers(key)

    assert_equal 3, members.size
    assert_includes members, "member1"
    assert_includes members, "member2"
    assert_includes members, "member3"

    @client.del(key)
  end

  def test_sorted_set_operations
    key = "active_active:zset:#{SecureRandom.hex(8)}"

    @client.zadd(key, 1.0, "member1")
    @client.zadd(key, 2.0, "member2")
    @client.zadd(key, 3.0, "member3")

    result = @client.zrange(key, 0, -1)

    assert_equal %w[member1 member2 member3], result

    @client.del(key)
  end

  def test_connection_management
    # Connection is lazy - trigger it with a command
    @client.ping

    assert_predicate @client, :connected?

    @client.close

    refute_predicate @client, :connected?
  end

  def test_current_region
    region = @client.current_region

    assert_equal @redis_host, region[:host]
    assert_equal @redis_port, region[:port]
  end

  def test_manual_failover
    @client.failover_to_next_region

    # After failover, the region should still work
    # (even though in testing they point to the same Redis instance)
    key = "active_active:failover:#{SecureRandom.hex(8)}"
    @client.set(key, "test")

    assert_equal "test", @client.get(key)
    @client.del(key)
  end

  def test_factory_method
    client = RR.active_active(
      regions: @regions,
      db: 0
    )

    key = "active_active:factory:#{SecureRandom.hex(8)}"
    client.set(key, "factory_test")

    assert_equal "factory_test", client.get(key)
    client.del(key)
    client.close
  end

  def test_crdt_semantics_note
    # NOTE: This test documents CRDT behavior but doesn't test it
    # because we're using a single Redis instance, not a true Active-Active database
    #
    # In a real Active-Active setup with CRDTs:
    # - Writes to different regions are eventually consistent
    # - Conflicts are automatically resolved using CRDT rules
    # - For sets: "add wins over delete"
    # - For counters: increments/decrements are commutative
    # - For registers: last-write-wins with vector clocks
    #
    # Example CRDT behavior (would require actual Active-Active database):
    #   Region US: SADD myset "item1"
    #   Region EU: SADD myset "item2"
    #   After sync: myset contains both "item1" and "item2"
    #
    #   Region US: SADD myset "item3"
    #   Region EU: SREM myset "item3" (before seeing the add)
    #   After sync: myset contains "item3" (add wins)

    pass
  end
end
