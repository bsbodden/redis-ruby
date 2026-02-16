# frozen_string_literal: true

require "test_helper"

class TransactionTest < RedisRubyTestCase
  use_testcontainers!

  def test_multi_basic
    results = redis.multi do |tx|
      tx.set("test:tx1", "value1")
      tx.set("test:tx2", "value2")
      tx.get("test:tx1")
      tx.get("test:tx2")
    end

    assert_equal %w[OK OK value1 value2], results
  ensure
    redis.del("test:tx1", "test:tx2")
  end

  def test_multi_empty
    results = redis.multi do |_tx|
      # No commands
    end

    assert_empty results
  end

  def test_multi_with_incr
    redis.set("test:counter", "0")
    results = redis.multi do |tx|
      tx.incr("test:counter")
      tx.incr("test:counter")
      tx.incr("test:counter")
    end

    assert_equal [1, 2, 3], results
    assert_equal "3", redis.get("test:counter")
  ensure
    redis.del("test:counter")
  end

  def test_multi_atomicity
    redis.set("test:key", "original")

    results = redis.multi do |tx|
      tx.set("test:key", "new_value")
      tx.get("test:key")
    end

    # Both operations should execute atomically
    assert_equal %w[OK new_value], results
    assert_equal "new_value", redis.get("test:key")
  ensure
    redis.del("test:key")
  end

  def test_multi_with_hash
    results = redis.multi do |tx|
      tx.hset("test:hash", "f1", "v1", "f2", "v2")
      tx.hget("test:hash", "f1")
      tx.hgetall("test:hash")
    end

    assert_equal 2, results[0]
    assert_equal "v1", results[1]
    # hgetall returns array in transaction
    assert_kind_of Array, results[2]
  ensure
    redis.del("test:hash")
  end

  def test_multi_with_list
    results = redis.multi do |tx|
      tx.rpush("test:list", "a", "b", "c")
      tx.lrange("test:list", 0, -1)
      tx.lpop("test:list")
    end

    assert_equal 3, results[0]
    assert_equal %w[a b c], results[1]
    assert_equal "a", results[2]
  ensure
    redis.del("test:list")
  end

  def test_watch_basic
    redis.set("test:watched", "original")

    result = redis.watch("test:watched") do
      current = redis.get("test:watched")
      redis.multi do |tx|
        tx.set("test:watched", "#{current}_modified")
      end
    end

    assert_equal ["OK"], result
    assert_equal "original_modified", redis.get("test:watched")
  ensure
    redis.del("test:watched")
  end

  def test_watch_aborts_on_change
    redis.set("test:watched", "original")

    # This test simulates what happens when watched key changes
    # In a real scenario, another client would modify the key
    result = redis.watch("test:watched") do
      _current = redis.get("test:watched")

      # Modify the key while watching (simulates another client)
      # We need a separate connection for this
      redis2 = RR::Client.new(url: @redis_url)
      redis2.set("test:watched", "changed_by_other")
      redis2.close

      # Now try to execute transaction - should abort
      redis.multi do |tx|
        tx.set("test:watched", "new_value")
      end
    end

    # Transaction should return nil when aborted
    assert_nil result
    # Original value should remain (or the value set by redis2)
    assert_equal "changed_by_other", redis.get("test:watched")
  ensure
    redis.del("test:watched")
  end

  def test_watch_multiple_keys
    redis.set("test:key1", "value1")
    redis.set("test:key2", "value2")

    result = redis.watch("test:key1", "test:key2") do
      v1 = redis.get("test:key1")
      v2 = redis.get("test:key2")
      redis.multi do |tx|
        tx.set("test:result", "#{v1}_#{v2}")
      end
    end

    assert_equal ["OK"], result
    assert_equal "value1_value2", redis.get("test:result")
  ensure
    redis.del("test:key1", "test:key2", "test:result")
  end

  def test_unwatch
    redis.set("test:key", "value")
    redis.watch("test:key")
    result = redis.unwatch

    assert_equal "OK", result
  ensure
    redis.del("test:key")
  end
end
