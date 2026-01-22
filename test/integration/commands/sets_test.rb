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

  # SMISMEMBER tests (Redis 6.2+)
  def test_smismember_all_present
    redis.sadd("test:set", "a", "b", "c")

    result = redis.smismember("test:set", "a", "b", "c")

    assert_equal [1, 1, 1], result
  ensure
    redis.del("test:set")
  end

  def test_smismember_some_missing
    redis.sadd("test:set", "a", "c")

    result = redis.smismember("test:set", "a", "b", "c")

    assert_equal [1, 0, 1], result
  ensure
    redis.del("test:set")
  end

  def test_smismember_all_missing
    redis.sadd("test:set", "x", "y", "z")

    result = redis.smismember("test:set", "a", "b", "c")

    assert_equal [0, 0, 0], result
  ensure
    redis.del("test:set")
  end

  def test_smismember_empty_set
    redis.del("test:set")

    result = redis.smismember("test:set", "a", "b")

    assert_equal [0, 0], result
  end

  def test_smismember_single_member
    redis.sadd("test:set", "a", "b")

    result = redis.smismember("test:set", "a")

    assert_equal [1], result
  ensure
    redis.del("test:set")
  end

  # SRANDMEMBER tests
  def test_srandmember
    redis.sadd("test:set", "a", "b", "c")

    result = redis.srandmember("test:set")

    assert_includes %w[a b c], result
  ensure
    redis.del("test:set")
  end

  def test_srandmember_with_count
    redis.sadd("test:set", "a", "b", "c")

    result = redis.srandmember("test:set", 2)

    assert_equal 2, result.length
    result.each { |m| assert_includes %w[a b c], m }
  ensure
    redis.del("test:set")
  end

  def test_srandmember_with_negative_count
    redis.sadd("test:set", "a", "b")

    result = redis.srandmember("test:set", -5)

    # Negative count allows duplicates
    assert_equal 5, result.length
    result.each { |m| assert_includes %w[a b], m }
  ensure
    redis.del("test:set")
  end

  # SPOP with count tests
  def test_spop_with_count
    redis.sadd("test:set", "a", "b", "c", "d", "e")

    result = redis.spop("test:set", 3)

    assert_equal 3, result.length
    assert_equal 2, redis.scard("test:set")
  ensure
    redis.del("test:set")
  end

  # SUNIONSTORE tests
  def test_sunionstore
    redis.sadd("test:set1", "a", "b")
    redis.sadd("test:set2", "b", "c")

    count = redis.sunionstore("test:result", "test:set1", "test:set2")

    assert_equal 3, count
    members = redis.smembers("test:result")

    assert_equal 3, members.length
    assert_includes members, "a"
    assert_includes members, "b"
    assert_includes members, "c"
  ensure
    redis.del("test:set1", "test:set2", "test:result")
  end

  # SDIFFSTORE tests
  def test_sdiffstore
    redis.sadd("test:set1", "a", "b", "c")
    redis.sadd("test:set2", "b", "c")

    count = redis.sdiffstore("test:result", "test:set1", "test:set2")

    assert_equal 1, count
    assert_equal %w[a], redis.smembers("test:result")
  ensure
    redis.del("test:set1", "test:set2", "test:result")
  end

  # SINTERCARD tests (Redis 7.0+)
  def test_sintercard
    redis.sadd("test:set1", "a", "b", "c")
    redis.sadd("test:set2", "b", "c", "d")

    count = redis.sintercard("test:set1", "test:set2")

    assert_equal 2, count
  ensure
    redis.del("test:set1", "test:set2")
  end

  def test_sintercard_with_limit
    redis.sadd("test:set1", "a", "b", "c", "d", "e")
    redis.sadd("test:set2", "a", "b", "c", "d", "e")

    count = redis.sintercard("test:set1", "test:set2", limit: 3)

    assert_equal 3, count
  ensure
    redis.del("test:set1", "test:set2")
  end

  # SSCAN tests
  def test_sscan_basic
    redis.sadd("test:set", "a", "b", "c")

    cursor, members = redis.sscan("test:set", 0)

    assert_kind_of String, cursor
    assert_kind_of Array, members
  ensure
    redis.del("test:set")
  end

  def test_sscan_with_match
    redis.sadd("test:set", "test:a", "test:b", "other:c")

    cursor, members = redis.sscan("test:set", 0, match: "test:*")

    assert_kind_of String, cursor
    assert_kind_of Array, members
  ensure
    redis.del("test:set")
  end

  def test_sscan_with_count
    10.times { |i| redis.sadd("test:set", "member#{i}") }

    cursor, members = redis.sscan("test:set", 0, count: 5)

    assert_kind_of String, cursor
    assert_kind_of Array, members
  ensure
    redis.del("test:set")
  end

  # Edge cases
  def test_sadd_duplicate_members
    redis.sadd("test:set", "a", "a", "b")

    assert_equal 2, redis.scard("test:set")
  ensure
    redis.del("test:set")
  end

  def test_srem_nonexistent_member
    redis.sadd("test:set", "a", "b")

    result = redis.srem("test:set", "c")

    assert_equal 0, result
    assert_equal 2, redis.scard("test:set")
  ensure
    redis.del("test:set")
  end

  def test_smove_nonexistent_member
    redis.sadd("test:src", "a")
    redis.sadd("test:dst", "b")

    result = redis.smove("test:src", "test:dst", "c")

    assert_equal 0, result
  ensure
    redis.del("test:src", "test:dst")
  end

  def test_smembers_empty_set
    redis.del("test:set")

    result = redis.smembers("test:set")

    assert_equal [], result
  end

  def test_scard_empty_set
    redis.del("test:set")

    assert_equal 0, redis.scard("test:set")
  end

  def test_spop_empty_set
    redis.del("test:set")

    assert_nil redis.spop("test:set")
  end

  def test_srandmember_empty_set
    redis.del("test:set")

    assert_nil redis.srandmember("test:set")
  end

  # Binary data tests
  def test_sadd_binary_data
    binary_value = "\x00\x01\x02\xFF".b
    redis.sadd("test:set", binary_value)

    assert_equal 1, redis.sismember("test:set", binary_value)
    members = redis.smembers("test:set")

    assert_includes members, binary_value
  ensure
    redis.del("test:set")
  end

  def test_sinter_empty_intersection
    redis.sadd("test:set1", "a", "b")
    redis.sadd("test:set2", "c", "d")

    result = redis.sinter("test:set1", "test:set2")

    assert_equal [], result
  ensure
    redis.del("test:set1", "test:set2")
  end

  def test_sdiff_multiple_sets
    redis.sadd("test:set1", "a", "b", "c", "d")
    redis.sadd("test:set2", "b")
    redis.sadd("test:set3", "c")

    result = redis.sdiff("test:set1", "test:set2", "test:set3")

    assert_equal 2, result.length
    assert_includes result, "a"
    assert_includes result, "d"
  ensure
    redis.del("test:set1", "test:set2", "test:set3")
  end
end
