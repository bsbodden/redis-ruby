# frozen_string_literal: true

require "test_helper"

class ListsCommandsTest < RedisRubyTestCase
  use_testcontainers!

  def test_lpush_and_lrange
    redis.lpush("test:list", "c", "b", "a")
    assert_equal %w[a b c], redis.lrange("test:list", 0, -1)
  ensure
    redis.del("test:list")
  end

  def test_rpush
    redis.rpush("test:list", "a", "b", "c")
    assert_equal %w[a b c], redis.lrange("test:list", 0, -1)
  ensure
    redis.del("test:list")
  end

  def test_lpop
    redis.rpush("test:list", "a", "b", "c")
    assert_equal "a", redis.lpop("test:list")
    assert_equal %w[b c], redis.lrange("test:list", 0, -1)
  ensure
    redis.del("test:list")
  end

  def test_rpop
    redis.rpush("test:list", "a", "b", "c")
    assert_equal "c", redis.rpop("test:list")
    assert_equal %w[a b], redis.lrange("test:list", 0, -1)
  ensure
    redis.del("test:list")
  end

  def test_llen
    redis.rpush("test:list", "a", "b", "c")
    assert_equal 3, redis.llen("test:list")
  ensure
    redis.del("test:list")
  end

  def test_lindex
    redis.rpush("test:list", "a", "b", "c")
    assert_equal "b", redis.lindex("test:list", 1)
    assert_equal "c", redis.lindex("test:list", -1)
  ensure
    redis.del("test:list")
  end

  def test_lset
    redis.rpush("test:list", "a", "b", "c")
    redis.lset("test:list", 1, "B")
    assert_equal %w[a B c], redis.lrange("test:list", 0, -1)
  ensure
    redis.del("test:list")
  end

  def test_linsert
    redis.rpush("test:list", "a", "c")
    redis.linsert("test:list", :before, "c", "b")
    assert_equal %w[a b c], redis.lrange("test:list", 0, -1)
  ensure
    redis.del("test:list")
  end

  def test_lrem
    redis.rpush("test:list", "a", "b", "a", "c", "a")
    assert_equal 2, redis.lrem("test:list", 2, "a")
    assert_equal %w[b c a], redis.lrange("test:list", 0, -1)
  ensure
    redis.del("test:list")
  end

  def test_ltrim
    redis.rpush("test:list", "a", "b", "c", "d", "e")
    redis.ltrim("test:list", 1, 3)
    assert_equal %w[b c d], redis.lrange("test:list", 0, -1)
  ensure
    redis.del("test:list")
  end

  def test_lmove
    redis.rpush("test:src", "a", "b", "c")
    result = redis.lmove("test:src", "test:dst", :right, :left)
    assert_equal "c", result
    assert_equal %w[a b], redis.lrange("test:src", 0, -1)
    assert_equal %w[c], redis.lrange("test:dst", 0, -1)
  ensure
    redis.del("test:src", "test:dst")
  end
end
