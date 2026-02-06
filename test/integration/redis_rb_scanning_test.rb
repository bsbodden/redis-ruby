# frozen_string_literal: true

require_relative "../test_helper"
require "redis"

# These tests mirror the redis-rb scanning tests to ensure compatibility
class RedisRbScanningTest < Minitest::Test
  def setup
    @redis = Redis.new(url: ENV["REDIS_URL"] || "redis://localhost:6379")
    @redis.flushdb
  end

  def teardown
    @redis.flushdb if @redis
  end

  def r
    @redis
  end

  def test_scan_basic
    100.times { |i| r.set("key:#{i}", "value") }

    cursor = "0"
    all_keys = []
    loop do
      cursor, keys = r.scan(cursor)
      all_keys += keys
      break if cursor == "0"
    end

    assert_equal 100, all_keys.uniq.size
  end

  def test_scan_count
    100.times { |i| r.set("key:#{i}", "value") }

    cursor = "0"
    all_keys = []
    loop do
      cursor, keys = r.scan(cursor, count: 5)
      all_keys += keys
      break if cursor == "0"
    end

    assert_equal 100, all_keys.uniq.size
  end

  def test_scan_match
    100.times { |i| r.set("key:#{i}", "value") }

    cursor = "0"
    all_keys = []
    loop do
      cursor, keys = r.scan(cursor, match: "key:1?")
      all_keys += keys
      break if cursor == "0"
    end

    assert_equal 10, all_keys.uniq.size
  end

  def test_sscan_basic
    elements = []
    100.times { |j| elements << "ele:#{j}" }
    r.sadd("set", elements)

    cursor = "0"
    all_members = []
    loop do
      cursor, members = r.sscan("set", cursor)
      all_members += members
      break if cursor == "0"
    end

    assert_equal 100, all_members.uniq.size
  end

  def test_hscan_basic
    elements = []
    100.times { |j| elements << "key:#{j}" << j.to_s }
    r.hmset("hash", *elements)

    cursor = "0"
    all_pairs = []
    loop do
      cursor, pairs = r.hscan("hash", cursor)
      all_pairs.concat(pairs)
      break if cursor == "0"
    end

    assert_equal 100, all_pairs.uniq.size
    # Each pair should be [key, value]
    all_pairs.each do |pair|
      assert_equal 2, pair.size
      assert pair[0].start_with?("key:")
    end
  end

  def test_zscan_basic
    elements = []
    100.times { |j| elements << j << "key:#{j}" }
    r.zadd("zset", elements)

    cursor = "0"
    all_pairs = []
    loop do
      cursor, pairs = r.zscan("zset", cursor)
      all_pairs.concat(pairs)
      break if cursor == "0"
    end

    assert_equal 100, all_pairs.uniq.size
    # Each pair should be [member, score] with score as Float
    all_pairs.each do |member, score|
      assert member.start_with?("key:")
      assert score.is_a?(Float)
    end
  end

  def test_scan_each_enumerator
    100.times { |i| r.set("key:#{i}", "value") }

    scan_enumerator = r.scan_each
    assert scan_enumerator.is_a?(Enumerator)

    keys_from_scan = scan_enumerator.to_a.uniq
    all_keys = r.keys("*")

    assert_equal all_keys.sort, keys_from_scan.sort
  end

  def test_scan_each_block
    100.times { |i| r.set("key:#{i}", "value") }

    keys_from_scan = []
    r.scan_each do |key|
      keys_from_scan << key
    end

    all_keys = r.keys("*")

    assert_equal all_keys.sort, keys_from_scan.uniq.sort
  end

  def test_sscan_each_enumerator
    elements = []
    100.times { |j| elements << "ele:#{j}" }
    r.sadd("set", elements)

    scan_enumerator = r.sscan_each("set")
    assert scan_enumerator.is_a?(Enumerator)

    keys_from_scan = scan_enumerator.to_a.uniq
    all_keys = r.smembers("set")

    assert_equal all_keys.sort, keys_from_scan.sort
  end

  def test_sscan_each_block
    elements = []
    100.times { |j| elements << "ele:#{j}" }
    r.sadd("set", elements)

    keys_from_scan = []
    r.sscan_each("set") do |key|
      keys_from_scan << key
    end

    all_keys = r.smembers("set")

    assert_equal all_keys.sort, keys_from_scan.uniq.sort
  end

  def test_hscan_each_enumerator
    elements = []
    100.times { |j| elements << "key:#{j}" << j.to_s }
    r.hmset("hash", *elements)

    scan_enumerator = r.hscan_each("hash")
    assert scan_enumerator.is_a?(Enumerator)

    keys_from_scan = scan_enumerator.to_a.uniq
    all_keys = r.hgetall("hash").to_a

    assert_equal all_keys.sort, keys_from_scan.sort
  end

  def test_hscan_each_block
    elements = []
    100.times { |j| elements << "key:#{j}" << j.to_s }
    r.hmset("hash", *elements)

    keys_from_scan = []
    r.hscan_each("hash") do |field, value|
      keys_from_scan << [field, value]
    end
    all_keys = r.hgetall("hash").to_a

    assert_equal all_keys.sort, keys_from_scan.uniq.sort
  end

  def test_zscan_each_enumerator
    elements = []
    100.times { |j| elements << j << "key:#{j}" }
    r.zadd("zset", elements)

    scan_enumerator = r.zscan_each("zset")
    assert scan_enumerator.is_a?(Enumerator)

    scores_from_scan = scan_enumerator.to_a.uniq
    member_scores = r.zrange("zset", 0, -1, with_scores: true)

    assert_equal member_scores.sort, scores_from_scan.sort
  end

  def test_zscan_each_block
    elements = []
    100.times { |j| elements << j << "key:#{j}" }
    r.zadd("zset", elements)

    scores_from_scan = []
    r.zscan_each("zset") do |member, score|
      scores_from_scan << [member, score]
    end
    member_scores = r.zrange("zset", 0, -1, with_scores: true)

    assert_equal member_scores.sort, scores_from_scan.sort
  end
end
