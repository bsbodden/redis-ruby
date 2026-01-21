# frozen_string_literal: true

require "test_helper"

class HyperLogLogIntegrationTest < Minitest::Test
  def setup
    @redis = RedisRuby.new(host: ENV.fetch("REDIS_HOST", "redis"), port: ENV.fetch("REDIS_PORT", 6379).to_i)
    @redis.del("hll:test", "hll:test2", "hll:merged")
  end

  def teardown
    @redis.del("hll:test", "hll:test2", "hll:merged")
    @redis.close
  end

  # PFADD tests
  def test_pfadd_single_element
    result = @redis.pfadd("hll:test", "element1")
    assert_equal 1, result
  end

  def test_pfadd_multiple_elements
    result = @redis.pfadd("hll:test", "a", "b", "c", "d", "e")
    assert_equal 1, result
  end

  def test_pfadd_duplicate_elements
    @redis.pfadd("hll:test", "element1")
    result = @redis.pfadd("hll:test", "element1")
    assert_equal 0, result  # No change
  end

  def test_pfadd_returns_1_when_cardinality_changes
    @redis.pfadd("hll:test", "a", "b", "c")
    result = @redis.pfadd("hll:test", "d")  # New element
    assert_equal 1, result
  end

  # PFCOUNT tests
  def test_pfcount_empty_key
    result = @redis.pfcount("hll:nonexistent")
    assert_equal 0, result
  end

  def test_pfcount_single_key
    @redis.pfadd("hll:test", "a", "b", "c", "d", "e")
    result = @redis.pfcount("hll:test")
    assert_equal 5, result
  end

  def test_pfcount_approximate_cardinality
    # Add 1000 unique elements
    1000.times { |i| @redis.pfadd("hll:test", "element#{i}") }
    result = @redis.pfcount("hll:test")

    # HyperLogLog has ~0.81% standard error
    # So count should be within ~2% of 1000
    assert_in_delta(1000, result, 50)
  end

  def test_pfcount_multiple_keys
    @redis.pfadd("hll:test", "a", "b", "c")
    @redis.pfadd("hll:test2", "c", "d", "e")

    # Union count (a, b, c, d, e = 5 unique)
    result = @redis.pfcount("hll:test", "hll:test2")
    assert_equal 5, result
  end

  # PFMERGE tests
  def test_pfmerge_single_source
    @redis.pfadd("hll:test", "a", "b", "c")
    result = @redis.pfmerge("hll:merged", "hll:test")

    assert_equal "OK", result
    assert_equal 3, @redis.pfcount("hll:merged")
  end

  def test_pfmerge_multiple_sources
    @redis.pfadd("hll:test", "a", "b", "c")
    @redis.pfadd("hll:test2", "c", "d", "e")

    result = @redis.pfmerge("hll:merged", "hll:test", "hll:test2")

    assert_equal "OK", result
    assert_equal 5, @redis.pfcount("hll:merged")
  end

  def test_pfmerge_includes_destination_if_exists
    @redis.pfadd("hll:merged", "x", "y", "z")
    @redis.pfadd("hll:test", "a", "b")

    # PFMERGE merges sources into destination (union)
    @redis.pfmerge("hll:merged", "hll:test")

    # Result includes both existing destination and source
    assert_equal 5, @redis.pfcount("hll:merged")
  end

  def test_pfmerge_with_nonexistent_source
    @redis.pfadd("hll:test", "a", "b", "c")

    result = @redis.pfmerge("hll:merged", "hll:test", "hll:nonexistent")

    assert_equal "OK", result
    assert_equal 3, @redis.pfcount("hll:merged")
  end

  # Edge cases
  def test_pfadd_with_many_elements
    elements = (1..100).map { |i| "element#{i}" }
    result = @redis.pfadd("hll:test", *elements)

    assert_equal 1, result
    count = @redis.pfcount("hll:test")
    assert_in_delta(100, count, 5)
  end

  def test_hyperloglog_memory_efficiency
    # HyperLogLog should use ~12KB regardless of cardinality
    10_000.times { |i| @redis.pfadd("hll:test", "element#{i}") }

    # Verify it still counts correctly
    count = @redis.pfcount("hll:test")
    assert_in_delta(10_000, count, 200)
  end
end
