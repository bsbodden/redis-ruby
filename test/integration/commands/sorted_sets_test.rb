# frozen_string_literal: true

require "test_helper"

class SortedSetsCommandsTest < RedisRubyTestCase
  use_testcontainers!

  def test_zadd_and_zrange
    redis.zadd("test:zset", 1, "one", 2, "two", 3, "three")
    assert_equal %w[one two three], redis.zrange("test:zset", 0, -1)
  ensure
    redis.del("test:zset")
  end

  def test_zadd_with_scores
    redis.zadd("test:zset", 1, "one", 2, "two", 3, "three")
    result = redis.zrange("test:zset", 0, -1, withscores: true)
    assert_equal [["one", 1.0], ["two", 2.0], ["three", 3.0]], result
  ensure
    redis.del("test:zset")
  end

  def test_zrem
    redis.zadd("test:zset", 1, "one", 2, "two", 3, "three")
    assert_equal 2, redis.zrem("test:zset", "one", "two")
    assert_equal %w[three], redis.zrange("test:zset", 0, -1)
  ensure
    redis.del("test:zset")
  end

  def test_zscore
    redis.zadd("test:zset", 1.5, "one")
    assert_in_delta 1.5, redis.zscore("test:zset", "one"), 0.001
    assert_nil redis.zscore("test:zset", "missing")
  ensure
    redis.del("test:zset")
  end

  def test_zrank
    redis.zadd("test:zset", 1, "one", 2, "two", 3, "three")
    assert_equal 0, redis.zrank("test:zset", "one")
    assert_equal 2, redis.zrank("test:zset", "three")
    assert_nil redis.zrank("test:zset", "missing")
  ensure
    redis.del("test:zset")
  end

  def test_zrevrank
    redis.zadd("test:zset", 1, "one", 2, "two", 3, "three")
    assert_equal 2, redis.zrevrank("test:zset", "one")
    assert_equal 0, redis.zrevrank("test:zset", "three")
  ensure
    redis.del("test:zset")
  end

  def test_zcard
    redis.zadd("test:zset", 1, "one", 2, "two", 3, "three")
    assert_equal 3, redis.zcard("test:zset")
  ensure
    redis.del("test:zset")
  end

  def test_zcount
    redis.zadd("test:zset", 1, "one", 2, "two", 3, "three")
    assert_equal 2, redis.zcount("test:zset", 1, 2)
    assert_equal 3, redis.zcount("test:zset", "-inf", "+inf")
  ensure
    redis.del("test:zset")
  end

  def test_zrevrange
    redis.zadd("test:zset", 1, "one", 2, "two", 3, "three")
    assert_equal %w[three two one], redis.zrevrange("test:zset", 0, -1)
  ensure
    redis.del("test:zset")
  end

  def test_zrangebyscore
    redis.zadd("test:zset", 1, "one", 2, "two", 3, "three")
    assert_equal %w[one two], redis.zrangebyscore("test:zset", 1, 2)
  ensure
    redis.del("test:zset")
  end

  def test_zincrby
    redis.zadd("test:zset", 1, "one")
    result = redis.zincrby("test:zset", 2, "one")
    assert_in_delta 3.0, result, 0.001
  ensure
    redis.del("test:zset")
  end

  def test_zremrangebyrank
    redis.zadd("test:zset", 1, "one", 2, "two", 3, "three")
    assert_equal 2, redis.zremrangebyrank("test:zset", 0, 1)
    assert_equal %w[three], redis.zrange("test:zset", 0, -1)
  ensure
    redis.del("test:zset")
  end

  def test_zremrangebyscore
    redis.zadd("test:zset", 1, "one", 2, "two", 3, "three")
    assert_equal 2, redis.zremrangebyscore("test:zset", 1, 2)
    assert_equal %w[three], redis.zrange("test:zset", 0, -1)
  ensure
    redis.del("test:zset")
  end

  def test_zpopmin
    redis.zadd("test:zset", 1, "one", 2, "two", 3, "three")
    result = redis.zpopmin("test:zset")
    assert_equal [["one", 1.0]], result
  ensure
    redis.del("test:zset")
  end

  def test_zpopmax
    redis.zadd("test:zset", 1, "one", 2, "two", 3, "three")
    result = redis.zpopmax("test:zset")
    assert_equal [["three", 3.0]], result
  ensure
    redis.del("test:zset")
  end

  def test_zinterstore
    redis.zadd("test:zset1", 1, "one", 2, "two")
    redis.zadd("test:zset2", 2, "two", 3, "three")
    count = redis.zinterstore("test:result", %w[test:zset1 test:zset2])
    assert_equal 1, count
    assert_equal %w[two], redis.zrange("test:result", 0, -1)
  ensure
    redis.del("test:zset1", "test:zset2", "test:result")
  end

  def test_zunionstore
    redis.zadd("test:zset1", 1, "one", 2, "two")
    redis.zadd("test:zset2", 2, "two", 3, "three")
    count = redis.zunionstore("test:result", %w[test:zset1 test:zset2])
    assert_equal 3, count
    result = redis.zrange("test:result", 0, -1)
    assert_includes result, "one"
    assert_includes result, "two"
    assert_includes result, "three"
  ensure
    redis.del("test:zset1", "test:zset2", "test:result")
  end
end
