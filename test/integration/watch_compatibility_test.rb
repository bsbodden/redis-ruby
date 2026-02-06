# frozen_string_literal: true

require "test_helper"

# Tests for redis-rb compatible watch behavior
class WatchCompatibilityTest < RedisRubyTestCase
  use_testcontainers!

  # Test that watch block yields self to the block
  def test_watch_yields_self_to_block
    redis.set("test:watched", "original")

    yielded_object = nil
    result = redis.watch("test:watched") do |rd|
      yielded_object = rd
      redis.multi do |tx|
        tx.set("test:watched", "modified")
      end
    end

    assert_same redis, yielded_object
    assert_equal ["OK"], result
    assert_equal "modified", redis.get("test:watched")
  ensure
    redis.del("test:watched")
  end

  # Test that watch returns multi result when transaction succeeds
  def test_watch_returns_multi_result_on_success
    redis.set("test:watched", "original")

    result = redis.watch("test:watched") do |_rd|
      redis.multi do |tx|
        tx.set("test:watched", "new_value")
        tx.get("test:watched")
      end
    end

    assert_equal ["OK", "new_value"], result
  ensure
    redis.del("test:watched")
  end

  # Test that watch returns nil when transaction is aborted
  def test_watch_returns_nil_on_abort
    redis.set("test:watched", "original")

    result = redis.watch("test:watched") do |_rd|
      # Modify the key with a separate connection (simulates concurrent modification)
      redis2 = RedisRuby::Client.new(url: @redis_url)
      redis2.set("test:watched", "changed_by_other")
      redis2.close

      # Transaction should abort because watched key changed
      redis.multi do |tx|
        tx.set("test:watched", "new_value")
      end
    end

    assert_nil result
    assert_equal "changed_by_other", redis.get("test:watched")
  ensure
    redis.del("test:watched")
  end

  # Test that watch with array of keys works
  def test_watch_with_array_of_keys
    redis.set("test:k1", "v1")
    redis.set("test:k2", "v2")

    yielded_object = nil
    result = redis.watch("test:k1", "test:k2") do |rd|
      yielded_object = rd
      redis.multi do |tx|
        tx.set("test:result", "combined")
      end
    end

    assert_same redis, yielded_object
    assert_equal ["OK"], result
  ensure
    redis.del("test:k1", "test:k2", "test:result")
  end
end
