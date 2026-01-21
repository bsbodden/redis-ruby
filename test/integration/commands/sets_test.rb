# frozen_string_literal: true

require "test_helper"

class SetsCommandsTest < RedisRubyTestCase
  use_testcontainers!

  def test_sadd_and_smembers
    redis.sadd("test:set", "a", "b", "c")
    members = redis.smembers("test:set")
    assert_equal 3, members.length
    assert_includes members, "a"
    assert_includes members, "b"
    assert_includes members, "c"
  ensure
    redis.del("test:set")
  end

  def test_srem
    redis.sadd("test:set", "a", "b", "c")
    assert_equal 2, redis.srem("test:set", "a", "b")
    assert_equal %w[c], redis.smembers("test:set")
  ensure
    redis.del("test:set")
  end

  def test_sismember
    redis.sadd("test:set", "a", "b")
    assert_equal 1, redis.sismember("test:set", "a")
    assert_equal 0, redis.sismember("test:set", "c")
  ensure
    redis.del("test:set")
  end

  def test_scard
    redis.sadd("test:set", "a", "b", "c")
    assert_equal 3, redis.scard("test:set")
  ensure
    redis.del("test:set")
  end

  def test_spop
    redis.sadd("test:set", "a", "b", "c")
    member = redis.spop("test:set")
    assert_includes %w[a b c], member
    assert_equal 2, redis.scard("test:set")
  ensure
    redis.del("test:set")
  end

  def test_sinter
    redis.sadd("test:set1", "a", "b", "c")
    redis.sadd("test:set2", "b", "c", "d")
    result = redis.sinter("test:set1", "test:set2")
    assert_equal 2, result.length
    assert_includes result, "b"
    assert_includes result, "c"
  ensure
    redis.del("test:set1", "test:set2")
  end

  def test_sunion
    redis.sadd("test:set1", "a", "b")
    redis.sadd("test:set2", "b", "c")
    result = redis.sunion("test:set1", "test:set2")
    assert_equal 3, result.length
    assert_includes result, "a"
    assert_includes result, "b"
    assert_includes result, "c"
  ensure
    redis.del("test:set1", "test:set2")
  end

  def test_sdiff
    redis.sadd("test:set1", "a", "b", "c")
    redis.sadd("test:set2", "b", "c", "d")
    result = redis.sdiff("test:set1", "test:set2")
    assert_equal %w[a], result
  ensure
    redis.del("test:set1", "test:set2")
  end

  def test_sinterstore
    redis.sadd("test:set1", "a", "b", "c")
    redis.sadd("test:set2", "b", "c", "d")
    count = redis.sinterstore("test:result", "test:set1", "test:set2")
    assert_equal 2, count
    result = redis.smembers("test:result")
    assert_includes result, "b"
    assert_includes result, "c"
  ensure
    redis.del("test:set1", "test:set2", "test:result")
  end

  def test_smove
    redis.sadd("test:src", "a", "b")
    redis.sadd("test:dst", "c")
    assert_equal 1, redis.smove("test:src", "test:dst", "a")
    assert_equal %w[b], redis.smembers("test:src")
    members = redis.smembers("test:dst")
    assert_includes members, "a"
    assert_includes members, "c"
  ensure
    redis.del("test:src", "test:dst")
  end
end
