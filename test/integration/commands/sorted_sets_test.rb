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

  # ZADD with NX option tests
  def test_zadd_nx_adds_new_members
    result = redis.zadd("test:zset", 1, "one", nx: true)

    assert_equal 1, result
    assert_equal 1.0, redis.zscore("test:zset", "one")
  ensure
    redis.del("test:zset")
  end

  def test_zadd_nx_does_not_update_existing
    redis.zadd("test:zset", 1, "one")
    result = redis.zadd("test:zset", 5, "one", nx: true)

    assert_equal 0, result
    # Score should remain 1, not 5
    assert_equal 1.0, redis.zscore("test:zset", "one")
  ensure
    redis.del("test:zset")
  end

  def test_zadd_nx_mixed_new_and_existing
    redis.zadd("test:zset", 1, "one")
    result = redis.zadd("test:zset", 5, "one", 2, "two", nx: true)

    assert_equal 1, result  # Only "two" was added
    assert_equal 1.0, redis.zscore("test:zset", "one")
    assert_equal 2.0, redis.zscore("test:zset", "two")
  ensure
    redis.del("test:zset")
  end

  # ZADD with XX option tests
  def test_zadd_xx_updates_existing
    redis.zadd("test:zset", 1, "one")
    result = redis.zadd("test:zset", 5, "one", xx: true)

    assert_equal 0, result  # No new members added
    assert_equal 5.0, redis.zscore("test:zset", "one")
  ensure
    redis.del("test:zset")
  end

  def test_zadd_xx_does_not_add_new
    result = redis.zadd("test:zset", 1, "one", xx: true)

    assert_equal 0, result
    assert_nil redis.zscore("test:zset", "one")
  ensure
    redis.del("test:zset")
  end

  def test_zadd_xx_mixed_new_and_existing
    redis.zadd("test:zset", 1, "one")
    result = redis.zadd("test:zset", 5, "one", 2, "two", xx: true)

    assert_equal 0, result  # "two" was not added
    assert_equal 5.0, redis.zscore("test:zset", "one")
    assert_nil redis.zscore("test:zset", "two")
  ensure
    redis.del("test:zset")
  end

  # ZADD with GT option tests (Redis 6.2+)
  def test_zadd_gt_updates_if_greater
    redis.zadd("test:zset", 5, "one")
    result = redis.zadd("test:zset", 10, "one", gt: true)

    assert_equal 0, result
    assert_equal 10.0, redis.zscore("test:zset", "one")
  ensure
    redis.del("test:zset")
  end

  def test_zadd_gt_does_not_update_if_not_greater
    redis.zadd("test:zset", 10, "one")
    result = redis.zadd("test:zset", 5, "one", gt: true)

    assert_equal 0, result
    # Score remains 10 (5 is not greater)
    assert_equal 10.0, redis.zscore("test:zset", "one")
  ensure
    redis.del("test:zset")
  end

  def test_zadd_gt_adds_new_members
    result = redis.zadd("test:zset", 5, "one", gt: true)

    assert_equal 1, result
    assert_equal 5.0, redis.zscore("test:zset", "one")
  ensure
    redis.del("test:zset")
  end

  # ZADD with LT option tests (Redis 6.2+)
  def test_zadd_lt_updates_if_less
    redis.zadd("test:zset", 10, "one")
    result = redis.zadd("test:zset", 5, "one", lt: true)

    assert_equal 0, result
    assert_equal 5.0, redis.zscore("test:zset", "one")
  ensure
    redis.del("test:zset")
  end

  def test_zadd_lt_does_not_update_if_not_less
    redis.zadd("test:zset", 5, "one")
    result = redis.zadd("test:zset", 10, "one", lt: true)

    assert_equal 0, result
    # Score remains 5 (10 is not less)
    assert_equal 5.0, redis.zscore("test:zset", "one")
  ensure
    redis.del("test:zset")
  end

  def test_zadd_lt_adds_new_members
    result = redis.zadd("test:zset", 5, "one", lt: true)

    assert_equal 1, result
    assert_equal 5.0, redis.zscore("test:zset", "one")
  ensure
    redis.del("test:zset")
  end

  # ZADD with CH option tests
  def test_zadd_ch_returns_changed_count
    redis.zadd("test:zset", 1, "one")
    result = redis.zadd("test:zset", 5, "one", 2, "two", ch: true)

    # CH returns count of elements changed (1 updated + 1 added)
    assert_equal 2, result
  ensure
    redis.del("test:zset")
  end

  def test_zadd_ch_returns_zero_for_no_changes
    redis.zadd("test:zset", 1, "one")
    result = redis.zadd("test:zset", 1, "one", ch: true)

    # No change since score is the same
    assert_equal 0, result
  ensure
    redis.del("test:zset")
  end

  # ZADD combined options
  def test_zadd_xx_gt_combined
    redis.zadd("test:zset", 5, "one", 10, "two")
    result = redis.zadd("test:zset", 10, "one", 5, "two", 15, "three", xx: true, gt: true)

    # Only updates existing where new score > old: one (5->10)
    # two (10->5) won't update, three doesn't exist
    assert_equal 0, result
    assert_equal 10.0, redis.zscore("test:zset", "one")
    assert_equal 10.0, redis.zscore("test:zset", "two")  # unchanged
    assert_nil redis.zscore("test:zset", "three")
  ensure
    redis.del("test:zset")
  end

  def test_zadd_xx_lt_combined
    redis.zadd("test:zset", 10, "one", 5, "two")
    result = redis.zadd("test:zset", 5, "one", 10, "two", 1, "three", xx: true, lt: true)

    # Only updates existing where new score < old: one (10->5)
    # two (5->10) won't update, three doesn't exist
    assert_equal 0, result
    assert_equal 5.0, redis.zscore("test:zset", "one")
    assert_equal 5.0, redis.zscore("test:zset", "two")  # unchanged
    assert_nil redis.zscore("test:zset", "three")
  ensure
    redis.del("test:zset")
  end

  # Note: NX+GT and NX+LT combinations are NOT valid in Redis
  # Redis returns: "ERR GT, LT, and/or NX options at the same time are not compatible"

  # ZMSCORE tests (Redis 6.2+)
  def test_zmscore_returns_scores
    redis.zadd("test:zset", 1, "one", 2, "two", 3, "three")
    result = redis.zmscore("test:zset", "one", "two", "three")

    assert_equal [1.0, 2.0, 3.0], result
  ensure
    redis.del("test:zset")
  end

  def test_zmscore_returns_nil_for_missing
    redis.zadd("test:zset", 1, "one")
    result = redis.zmscore("test:zset", "one", "missing", "also_missing")

    assert_equal [1.0, nil, nil], result
  ensure
    redis.del("test:zset")
  end

  # ZRANGEBYSCORE with LIMIT tests
  def test_zrangebyscore_with_limit
    redis.zadd("test:zset", 1, "one", 2, "two", 3, "three", 4, "four", 5, "five")
    result = redis.zrangebyscore("test:zset", 1, 5, limit: [1, 2])

    assert_equal %w[two three], result
  ensure
    redis.del("test:zset")
  end

  def test_zrangebyscore_with_withscores
    redis.zadd("test:zset", 1, "one", 2, "two", 3, "three")
    result = redis.zrangebyscore("test:zset", 1, 2, withscores: true)

    assert_equal [["one", 1.0], ["two", 2.0]], result
  ensure
    redis.del("test:zset")
  end

  # ZREVRANGEBYSCORE tests
  def test_zrevrangebyscore
    redis.zadd("test:zset", 1, "one", 2, "two", 3, "three")
    result = redis.zrevrangebyscore("test:zset", 3, 1)

    assert_equal %w[three two one], result
  ensure
    redis.del("test:zset")
  end

  def test_zrevrangebyscore_with_limit
    redis.zadd("test:zset", 1, "one", 2, "two", 3, "three", 4, "four", 5, "five")
    result = redis.zrevrangebyscore("test:zset", 5, 1, limit: [1, 2])

    assert_equal %w[four three], result
  ensure
    redis.del("test:zset")
  end

  # ZLEXCOUNT tests
  def test_zlexcount
    redis.zadd("test:zset", 0, "a", 0, "b", 0, "c", 0, "d", 0, "e")
    result = redis.zlexcount("test:zset", "[b", "[d")

    assert_equal 3, result  # b, c, d
  ensure
    redis.del("test:zset")
  end

  def test_zlexcount_with_infinity
    redis.zadd("test:zset", 0, "a", 0, "b", 0, "c")
    result = redis.zlexcount("test:zset", "-", "+")

    assert_equal 3, result
  ensure
    redis.del("test:zset")
  end

  # ZRANGEBYLEX tests
  def test_zrangebylex
    redis.zadd("test:zset", 0, "a", 0, "b", 0, "c", 0, "d", 0, "e")
    result = redis.zrangebylex("test:zset", "[b", "[d")

    assert_equal %w[b c d], result
  ensure
    redis.del("test:zset")
  end

  def test_zrangebylex_with_limit
    redis.zadd("test:zset", 0, "a", 0, "b", 0, "c", 0, "d", 0, "e")
    result = redis.zrangebylex("test:zset", "-", "+", limit: [1, 2])

    assert_equal %w[b c], result
  ensure
    redis.del("test:zset")
  end

  # ZREVRANGEBYLEX tests
  def test_zrevrangebylex
    redis.zadd("test:zset", 0, "a", 0, "b", 0, "c", 0, "d", 0, "e")
    result = redis.zrevrangebylex("test:zset", "[d", "[b")

    assert_equal %w[d c b], result
  ensure
    redis.del("test:zset")
  end

  # ZREMRANGEBYLEX tests
  def test_zremrangebylex
    redis.zadd("test:zset", 0, "a", 0, "b", 0, "c", 0, "d", 0, "e")
    result = redis.zremrangebylex("test:zset", "[b", "[d")

    assert_equal 3, result
    assert_equal %w[a e], redis.zrange("test:zset", 0, -1)
  ensure
    redis.del("test:zset")
  end

  # ZSCAN tests
  def test_zscan_iterates_members
    redis.zadd("test:zset", 1, "one", 2, "two", 3, "three")
    cursor, members = redis.zscan("test:zset", 0)

    assert_kind_of String, cursor
    assert_kind_of Array, members
  ensure
    redis.del("test:zset")
  end

  def test_zscan_with_match
    redis.zadd("test:zset", 1, "test:one", 2, "test:two", 3, "other")
    cursor, members = redis.zscan("test:zset", 0, match: "test:*")

    assert_kind_of String, cursor
    assert_kind_of Array, members
  ensure
    redis.del("test:zset")
  end

  # ZINTERSTORE with weights and aggregate tests
  def test_zinterstore_with_weights
    redis.zadd("test:zset1", 1, "one", 2, "two")
    redis.zadd("test:zset2", 1, "one", 2, "two")
    count = redis.zinterstore("test:result", %w[test:zset1 test:zset2], weights: [2, 3])

    assert_equal 2, count
    # one: (1*2) + (1*3) = 5
    # two: (2*2) + (2*3) = 10
    assert_equal 5.0, redis.zscore("test:result", "one")
    assert_equal 10.0, redis.zscore("test:result", "two")
  ensure
    redis.del("test:zset1", "test:zset2", "test:result")
  end

  def test_zinterstore_with_aggregate_min
    redis.zadd("test:zset1", 1, "one", 5, "two")
    redis.zadd("test:zset2", 3, "one", 2, "two")
    count = redis.zinterstore("test:result", %w[test:zset1 test:zset2], aggregate: :min)

    assert_equal 2, count
    assert_equal 1.0, redis.zscore("test:result", "one")
    assert_equal 2.0, redis.zscore("test:result", "two")
  ensure
    redis.del("test:zset1", "test:zset2", "test:result")
  end

  def test_zinterstore_with_aggregate_max
    redis.zadd("test:zset1", 1, "one", 5, "two")
    redis.zadd("test:zset2", 3, "one", 2, "two")
    count = redis.zinterstore("test:result", %w[test:zset1 test:zset2], aggregate: :max)

    assert_equal 2, count
    assert_equal 3.0, redis.zscore("test:result", "one")
    assert_equal 5.0, redis.zscore("test:result", "two")
  ensure
    redis.del("test:zset1", "test:zset2", "test:result")
  end

  # ZUNIONSTORE with weights and aggregate tests
  def test_zunionstore_with_weights
    redis.zadd("test:zset1", 1, "one", 2, "two")
    redis.zadd("test:zset2", 3, "three")
    count = redis.zunionstore("test:result", %w[test:zset1 test:zset2], weights: [2, 3])

    assert_equal 3, count
    assert_equal 2.0, redis.zscore("test:result", "one")
    assert_equal 4.0, redis.zscore("test:result", "two")
    assert_equal 9.0, redis.zscore("test:result", "three")
  ensure
    redis.del("test:zset1", "test:zset2", "test:result")
  end

  def test_zunionstore_with_aggregate_min
    redis.zadd("test:zset1", 5, "one")
    redis.zadd("test:zset2", 3, "one")
    count = redis.zunionstore("test:result", %w[test:zset1 test:zset2], aggregate: :min)

    assert_equal 1, count
    assert_equal 3.0, redis.zscore("test:result", "one")
  ensure
    redis.del("test:zset1", "test:zset2", "test:result")
  end

  # ZPOPMIN/ZPOPMAX with count tests
  def test_zpopmin_with_count
    redis.zadd("test:zset", 1, "one", 2, "two", 3, "three")
    result = redis.zpopmin("test:zset", 2)

    assert_equal [["one", 1.0], ["two", 2.0]], result
  ensure
    redis.del("test:zset")
  end

  def test_zpopmax_with_count
    redis.zadd("test:zset", 1, "one", 2, "two", 3, "three")
    result = redis.zpopmax("test:zset", 2)

    assert_equal [["three", 3.0], ["two", 2.0]], result
  ensure
    redis.del("test:zset")
  end

  # ZRANDMEMBER tests (Redis 6.2+)
  def test_zrandmember
    redis.zadd("test:zset", 1, "one", 2, "two", 3, "three")
    result = redis.zrandmember("test:zset")

    assert_includes %w[one two three], result
  ensure
    redis.del("test:zset")
  end

  def test_zrandmember_with_count
    redis.zadd("test:zset", 1, "one", 2, "two", 3, "three")
    result = redis.zrandmember("test:zset", 2)

    assert_equal 2, result.length
    result.each { |m| assert_includes %w[one two three], m }
  ensure
    redis.del("test:zset")
  end

  def test_zrandmember_with_negative_count
    redis.zadd("test:zset", 1, "one", 2, "two")
    result = redis.zrandmember("test:zset", -5)

    # Negative count allows duplicates
    assert_equal 5, result.length
  ensure
    redis.del("test:zset")
  end

  # ZUNION tests (Redis 6.2+)
  def test_zunion_basic
    redis.zadd("test:zset1", 1, "one", 2, "two")
    redis.zadd("test:zset2", 2, "two", 3, "three")

    result = redis.zunion(%w[test:zset1 test:zset2])

    assert_equal 3, result.length
    assert_includes result, "one"
    assert_includes result, "two"
    assert_includes result, "three"
  ensure
    redis.del("test:zset1", "test:zset2")
  end

  def test_zunion_with_withscores
    redis.zadd("test:zset1", 1, "one", 2, "two")
    redis.zadd("test:zset2", 3, "two", 4, "three")

    result = redis.zunion(%w[test:zset1 test:zset2], withscores: true)

    # Results are [member, score] pairs
    assert_equal 3, result.length
    # "two" appears in both sets, default aggregate is SUM: 2 + 3 = 5
    two_entry = result.find { |m, _s| m == "two" }

    assert_equal 5.0, two_entry[1]
  ensure
    redis.del("test:zset1", "test:zset2")
  end

  def test_zunion_with_weights
    redis.zadd("test:zset1", 1, "one")
    redis.zadd("test:zset2", 1, "one")

    result = redis.zunion(%w[test:zset1 test:zset2], weights: [2, 3], withscores: true)

    # one: (1*2) + (1*3) = 5
    one_entry = result.find { |m, _s| m == "one" }

    assert_equal 5.0, one_entry[1]
  ensure
    redis.del("test:zset1", "test:zset2")
  end

  def test_zunion_with_aggregate_min
    redis.zadd("test:zset1", 5, "one")
    redis.zadd("test:zset2", 3, "one")

    result = redis.zunion(%w[test:zset1 test:zset2], aggregate: :min, withscores: true)

    one_entry = result.find { |m, _s| m == "one" }

    assert_equal 3.0, one_entry[1]
  ensure
    redis.del("test:zset1", "test:zset2")
  end

  def test_zunion_with_aggregate_max
    redis.zadd("test:zset1", 5, "one")
    redis.zadd("test:zset2", 3, "one")

    result = redis.zunion(%w[test:zset1 test:zset2], aggregate: :max, withscores: true)

    one_entry = result.find { |m, _s| m == "one" }

    assert_equal 5.0, one_entry[1]
  ensure
    redis.del("test:zset1", "test:zset2")
  end

  # ZINTER tests (Redis 6.2+)
  def test_zinter_basic
    redis.zadd("test:zset1", 1, "one", 2, "two", 3, "three")
    redis.zadd("test:zset2", 2, "two", 3, "three", 4, "four")

    result = redis.zinter(%w[test:zset1 test:zset2])

    assert_equal 2, result.length
    assert_includes result, "two"
    assert_includes result, "three"
    refute_includes result, "one"
    refute_includes result, "four"
  ensure
    redis.del("test:zset1", "test:zset2")
  end

  def test_zinter_with_withscores
    redis.zadd("test:zset1", 1, "one", 2, "two")
    redis.zadd("test:zset2", 3, "two", 4, "one")

    result = redis.zinter(%w[test:zset1 test:zset2], withscores: true)

    assert_equal 2, result.length
    # "two" has score 2 + 3 = 5, "one" has score 1 + 4 = 5
    two_entry = result.find { |m, _s| m == "two" }

    assert_equal 5.0, two_entry[1]
  ensure
    redis.del("test:zset1", "test:zset2")
  end

  def test_zinter_with_weights
    redis.zadd("test:zset1", 1, "one")
    redis.zadd("test:zset2", 1, "one")

    result = redis.zinter(%w[test:zset1 test:zset2], weights: [2, 3], withscores: true)

    one_entry = result.find { |m, _s| m == "one" }

    assert_equal 5.0, one_entry[1]
  ensure
    redis.del("test:zset1", "test:zset2")
  end

  def test_zinter_empty_result
    redis.zadd("test:zset1", 1, "one")
    redis.zadd("test:zset2", 2, "two")

    result = redis.zinter(%w[test:zset1 test:zset2])

    assert_empty result
  ensure
    redis.del("test:zset1", "test:zset2")
  end

  # ZDIFF tests (Redis 6.2+)
  def test_zdiff_basic
    redis.zadd("test:zset1", 1, "one", 2, "two", 3, "three")
    redis.zadd("test:zset2", 2, "two")

    result = redis.zdiff(%w[test:zset1 test:zset2])

    assert_equal 2, result.length
    assert_includes result, "one"
    assert_includes result, "three"
    refute_includes result, "two"
  ensure
    redis.del("test:zset1", "test:zset2")
  end

  def test_zdiff_with_withscores
    redis.zadd("test:zset1", 1, "one", 2, "two", 3, "three")
    redis.zadd("test:zset2", 2, "two")

    result = redis.zdiff(%w[test:zset1 test:zset2], withscores: true)

    assert_equal 2, result.length
    one_entry = result.find { |m, _s| m == "one" }

    assert_equal 1.0, one_entry[1]
  ensure
    redis.del("test:zset1", "test:zset2")
  end

  def test_zdiff_empty_result
    redis.zadd("test:zset1", 1, "one", 2, "two")
    redis.zadd("test:zset2", 1, "one", 2, "two")

    result = redis.zdiff(%w[test:zset1 test:zset2])

    assert_empty result
  ensure
    redis.del("test:zset1", "test:zset2")
  end

  def test_zdiff_multiple_sets
    redis.zadd("test:zset1", 1, "one", 2, "two", 3, "three", 4, "four")
    redis.zadd("test:zset2", 1, "one")
    redis.zadd("test:zset3", 3, "three")

    result = redis.zdiff(%w[test:zset1 test:zset2 test:zset3])

    assert_equal 2, result.length
    assert_includes result, "two"
    assert_includes result, "four"
  ensure
    redis.del("test:zset1", "test:zset2", "test:zset3")
  end

  # ZDIFFSTORE tests (Redis 6.2+)
  def test_zdiffstore
    redis.zadd("test:zset1", 1, "one", 2, "two", 3, "three")
    redis.zadd("test:zset2", 2, "two")

    count = redis.zdiffstore("test:result", %w[test:zset1 test:zset2])

    assert_equal 2, count
    assert_equal %w[one three], redis.zrange("test:result", 0, -1)
  ensure
    redis.del("test:zset1", "test:zset2", "test:result")
  end
end
