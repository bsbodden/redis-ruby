# frozen_string_literal: true

require "test_helper"

# Tests for result format compatibility with redis-rb
# These ensure redis-ruby returns results in the same format as redis-rb
class ResultFormatCompatibilityTest < RedisRubyTestCase
  use_testcontainers!

  # hscan should return nested pairs, not flat array
  def test_hscan_returns_nested_pairs
    redis.hset("test:hash", "f1", "v1", "f2", "v2", "f3", "v3")

    cursor, data = redis.hscan("test:hash", "0")

    # Should be [[f1, v1], [f2, v2], ...] not [f1, v1, f2, v2, ...]
    assert_kind_of Array, data
    assert_kind_of Array, data[0], "Expected nested arrays, got flat: #{data.inspect}"
    assert_equal 2, data[0].length
    # Verify we got field-value pairs
    fields = data.map(&:first)
    assert_includes fields, "f1"
    assert_includes fields, "f2"
    assert_includes fields, "f3"
  ensure
    redis.del("test:hash")
  end

  # hrandfield with withvalues should return nested pairs
  def test_hrandfield_with_values_returns_nested_pairs
    redis.hset("test:hash", "f1", "v1", "f2", "v2")

    result = redis.hrandfield("test:hash", count: 2, withvalues: true)

    # Should be [[f1, v1], [f2, v2]] not [f1, v1, f2, v2]
    assert_kind_of Array, result
    assert_kind_of Array, result[0], "Expected nested arrays, got flat: #{result.inspect}"
    assert_equal 2, result[0].length
  ensure
    redis.del("test:hash")
  end

  # zpopmin without count should return single pair [member, score], not [[member, score]]
  def test_zpopmin_without_count_returns_single_pair
    redis.zadd("test:zset", 1.0, "a", 2.0, "b", 3.0, "c")

    result = redis.zpopmin("test:zset")

    # Should be ["a", 1.0] not [["a", 1.0]]
    assert_kind_of Array, result
    assert_equal 2, result.length, "Expected [member, score], got: #{result.inspect}"
    assert_equal "a", result[0]
    assert_equal 1.0, result[1]
  ensure
    redis.del("test:zset")
  end

  # zpopmin with count should return nested pairs
  def test_zpopmin_with_count_returns_nested_pairs
    redis.zadd("test:zset", 1.0, "a", 2.0, "b", 3.0, "c")

    result = redis.zpopmin("test:zset", 2)

    # Should be [["a", 1.0], ["b", 2.0]]
    assert_kind_of Array, result
    assert_kind_of Array, result[0]
    assert_equal [["a", 1.0], ["b", 2.0]], result
  ensure
    redis.del("test:zset")
  end

  # zpopmax without count should return single pair [member, score], not [[member, score]]
  def test_zpopmax_without_count_returns_single_pair
    redis.zadd("test:zset", 1.0, "a", 2.0, "b", 3.0, "c")

    result = redis.zpopmax("test:zset")

    # Should be ["c", 3.0] not [["c", 3.0]]
    assert_kind_of Array, result
    assert_equal 2, result.length, "Expected [member, score], got: #{result.inspect}"
    assert_equal "c", result[0]
    assert_equal 3.0, result[1]
  ensure
    redis.del("test:zset")
  end

  # zpopmax with count should return nested pairs
  def test_zpopmax_with_count_returns_nested_pairs
    redis.zadd("test:zset", 1.0, "a", 2.0, "b", 3.0, "c")

    result = redis.zpopmax("test:zset", 2)

    # Should be [["c", 3.0], ["b", 2.0]]
    assert_kind_of Array, result
    assert_kind_of Array, result[0]
    assert_equal [["c", 3.0], ["b", 2.0]], result
  ensure
    redis.del("test:zset")
  end

  # zpopmin on empty set returns nil
  def test_zpopmin_empty_set_returns_nil
    result = redis.zpopmin("test:nonexistent")

    assert_nil result
  end

  # zpopmax on empty set returns nil
  def test_zpopmax_empty_set_returns_nil
    result = redis.zpopmax("test:nonexistent")

    assert_nil result
  end

  # incrbyfloat should return Float, not String
  def test_incrbyfloat_returns_float
    redis.set("test:float", "1.5")

    result = redis.incrbyfloat("test:float", 0.5)

    assert_kind_of Float, result
    assert_equal 2.0, result
  ensure
    redis.del("test:float")
  end

  # hincrbyfloat should return Float, not String
  def test_hincrbyfloat_returns_float
    redis.hset("test:hash", "field", "1.5")

    result = redis.hincrbyfloat("test:hash", "field", 0.5)

    assert_kind_of Float, result
    assert_equal 2.0, result
  ensure
    redis.del("test:hash")
  end

  # zscore should return Float (already fixed, but let's verify)
  def test_zscore_returns_float
    redis.zadd("test:zset", 1.5, "member")

    result = redis.zscore("test:zset", "member")

    assert_kind_of Float, result
    assert_equal 1.5, result
  ensure
    redis.del("test:zset")
  end

  # zincrby should return Float
  def test_zincrby_returns_float
    redis.zadd("test:zset", 1.5, "member")

    result = redis.zincrby("test:zset", 0.5, "member")

    assert_kind_of Float, result
    assert_equal 2.0, result
  ensure
    redis.del("test:zset")
  end
end
