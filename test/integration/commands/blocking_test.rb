# frozen_string_literal: true

require "test_helper"

class BlockingCommandsTest < RedisRubyTestCase
  use_testcontainers!

  # BLPOP tests
  def test_blpop_returns_immediately_with_data
    redis.rpush("test:list", "value1", "value2")

    result = redis.blpop("test:list", timeout: 1)

    assert_equal ["test:list", "value1"], result
  ensure
    redis.del("test:list")
  end

  def test_blpop_from_multiple_lists
    redis.rpush("test:list2", "value")

    result = redis.blpop("test:list1", "test:list2", timeout: 1)

    assert_equal ["test:list2", "value"], result
  ensure
    redis.del("test:list1", "test:list2")
  end

  def test_blpop_returns_nil_on_timeout
    result = redis.blpop("test:empty", timeout: 0.1)

    assert_nil result
  end

  def test_blpop_pops_from_left
    redis.rpush("test:list", "first", "second", "third")

    result = redis.blpop("test:list", timeout: 1)

    assert_equal ["test:list", "first"], result
    assert_equal %w[second third], redis.lrange("test:list", 0, -1)
  ensure
    redis.del("test:list")
  end

  # BRPOP tests
  def test_brpop_returns_immediately_with_data
    redis.rpush("test:list", "value1", "value2")

    result = redis.brpop("test:list", timeout: 1)

    assert_equal ["test:list", "value2"], result
  ensure
    redis.del("test:list")
  end

  def test_brpop_from_multiple_lists
    redis.rpush("test:list2", "value")

    result = redis.brpop("test:list1", "test:list2", timeout: 1)

    assert_equal ["test:list2", "value"], result
  ensure
    redis.del("test:list1", "test:list2")
  end

  def test_brpop_returns_nil_on_timeout
    result = redis.brpop("test:empty", timeout: 0.1)

    assert_nil result
  end

  def test_brpop_pops_from_right
    redis.rpush("test:list", "first", "second", "third")

    result = redis.brpop("test:list", timeout: 1)

    assert_equal ["test:list", "third"], result
    assert_equal %w[first second], redis.lrange("test:list", 0, -1)
  ensure
    redis.del("test:list")
  end

  # BRPOPLPUSH tests
  def test_brpoplpush_moves_element
    redis.rpush("test:source", "value")

    result = redis.brpoplpush("test:source", "test:dest", timeout: 1)

    assert_equal "value", result
    assert_equal 0, redis.llen("test:source")
    assert_equal ["value"], redis.lrange("test:dest", 0, -1)
  ensure
    redis.del("test:source", "test:dest")
  end

  def test_brpoplpush_returns_nil_on_timeout
    result = redis.brpoplpush("test:empty", "test:dest", timeout: 0.1)

    assert_nil result
  end

  def test_brpoplpush_rotates_list
    redis.rpush("test:list", "a", "b", "c")

    # Move from right of test:list to left of same list
    result = redis.brpoplpush("test:list", "test:list", timeout: 1)

    assert_equal "c", result
    assert_equal %w[c a b], redis.lrange("test:list", 0, -1)
  ensure
    redis.del("test:list")
  end

  # BLMOVE tests (Redis 6.2+)
  def test_blmove_left_right
    redis.rpush("test:source", "a", "b", "c")

    result = redis.blmove("test:source", "test:dest", :left, :right, timeout: 1)

    assert_equal "a", result
    assert_equal %w[b c], redis.lrange("test:source", 0, -1)
    assert_equal ["a"], redis.lrange("test:dest", 0, -1)
  ensure
    redis.del("test:source", "test:dest")
  end

  def test_blmove_right_left
    redis.rpush("test:source", "a", "b", "c")

    result = redis.blmove("test:source", "test:dest", :right, :left, timeout: 1)

    assert_equal "c", result
    assert_equal %w[a b], redis.lrange("test:source", 0, -1)
    assert_equal ["c"], redis.lrange("test:dest", 0, -1)
  ensure
    redis.del("test:source", "test:dest")
  end

  def test_blmove_returns_nil_on_timeout
    result = redis.blmove("test:empty", "test:dest", :left, :right, timeout: 0.1)

    assert_nil result
  end

  # BZPOPMIN tests
  def test_bzpopmin_returns_immediately_with_data
    redis.zadd("test:zset", 1, "one", 2, "two", 3, "three")

    result = redis.bzpopmin("test:zset", timeout: 1)

    assert_equal "test:zset", result[0]
    assert_equal "one", result[1]
    assert_in_delta 1.0, result[2], 0.001
  ensure
    redis.del("test:zset")
  end

  def test_bzpopmin_from_multiple_sets
    redis.zadd("test:zset2", 5, "five")

    result = redis.bzpopmin("test:zset1", "test:zset2", timeout: 1)

    assert_equal "test:zset2", result[0]
    assert_equal "five", result[1]
    assert_in_delta 5.0, result[2], 0.001
  ensure
    redis.del("test:zset1", "test:zset2")
  end

  def test_bzpopmin_returns_nil_on_timeout
    result = redis.bzpopmin("test:empty", timeout: 0.1)

    assert_nil result
  end

  def test_bzpopmin_pops_minimum
    redis.zadd("test:zset", 3, "three", 1, "one", 2, "two")

    result = redis.bzpopmin("test:zset", timeout: 1)

    assert_equal "one", result[1]
    # Verify "one" was removed
    assert_nil redis.zscore("test:zset", "one")
  ensure
    redis.del("test:zset")
  end

  # BZPOPMAX tests
  def test_bzpopmax_returns_immediately_with_data
    redis.zadd("test:zset", 1, "one", 2, "two", 3, "three")

    result = redis.bzpopmax("test:zset", timeout: 1)

    assert_equal "test:zset", result[0]
    assert_equal "three", result[1]
    assert_in_delta 3.0, result[2], 0.001
  ensure
    redis.del("test:zset")
  end

  def test_bzpopmax_from_multiple_sets
    redis.zadd("test:zset2", 5, "five")

    result = redis.bzpopmax("test:zset1", "test:zset2", timeout: 1)

    assert_equal "test:zset2", result[0]
    assert_equal "five", result[1]
    assert_in_delta 5.0, result[2], 0.001
  ensure
    redis.del("test:zset1", "test:zset2")
  end

  def test_bzpopmax_returns_nil_on_timeout
    result = redis.bzpopmax("test:empty", timeout: 0.1)

    assert_nil result
  end

  def test_bzpopmax_pops_maximum
    redis.zadd("test:zset", 1, "one", 3, "three", 2, "two")

    result = redis.bzpopmax("test:zset", timeout: 1)

    assert_equal "three", result[1]
    # Verify "three" was removed
    assert_nil redis.zscore("test:zset", "three")
  ensure
    redis.del("test:zset")
  end

  # Edge cases
  def test_blpop_with_empty_string_value
    redis.rpush("test:list", "")

    result = redis.blpop("test:list", timeout: 1)

    assert_equal ["test:list", ""], result
  ensure
    redis.del("test:list")
  end

  def test_brpop_with_binary_data
    binary_value = "\x00\x01\x02\xFF".b
    redis.rpush("test:list", binary_value)

    result = redis.brpop("test:list", timeout: 1)

    assert_equal "test:list", result[0]
    assert_equal binary_value, result[1]
  ensure
    redis.del("test:list")
  end

  def test_blpop_preserves_priority_order
    # First key with data should be returned
    redis.rpush("test:list3", "third")
    redis.rpush("test:list1", "first")

    result = redis.blpop("test:list1", "test:list2", "test:list3", timeout: 1)

    # Should return from test:list1 (first in argument list that has data)
    assert_equal "test:list1", result[0]
    assert_equal "first", result[1]
  ensure
    redis.del("test:list1", "test:list2", "test:list3")
  end
end
