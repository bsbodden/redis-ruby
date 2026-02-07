# frozen_string_literal: true

require "test_helper"

# Tests for redis-rb compatible Transaction behavior
# These tests ensure Transaction supports all the methods and signatures
# that redis-rb users expect.
class TransactionCompatibilityTest < RedisRubyTestCase
  use_testcontainers!

  # Test that sadd? works in transactions
  def test_transaction_sadd_question
    results = redis.multi do |tx|
      tx.sadd?("test:set", "member1")
      tx.sadd?("test:set", "member1") # duplicate
      tx.sadd?("test:set", "member2")
    end

    # sadd? should return integers in transaction (1 for added, 0 for existing)
    assert_equal [1, 0, 1], results
  ensure
    redis.del("test:set")
  end

  # Test that srem? works in transactions
  def test_transaction_srem_question
    redis.sadd("test:set", "member1", "member2")

    results = redis.multi do |tx|
      tx.srem?("test:set", "member1")
      tx.srem?("test:set", "member1") # already removed
      tx.srem?("test:set", "nonexistent")
    end

    # srem? should return integers in transaction (1 for removed, 0 for not found)
    assert_equal [1, 0, 0], results
  ensure
    redis.del("test:set")
  end

  # Test that info works in transactions
  def test_transaction_info
    results = redis.multi do |tx|
      tx.info
      tx.info("server")
    end

    # info returns a string in transaction
    assert_equal 2, results.length
    assert_kind_of String, results[0]
    assert_kind_of String, results[1]
    assert_includes results[1], "redis_version"
  end

  # Test that zrange accepts with_scores: keyword (alias for withscores:)
  def test_transaction_zrange_with_scores_keyword
    redis.zadd("test:zset", 1, "a", 2, "b", 3, "c")

    results = redis.multi do |tx|
      tx.zrange("test:zset", 0, -1)
      tx.zrange("test:zset", 0, -1, with_scores: true)
      tx.zrange("test:zset", 0, -1, withscores: true) # original keyword should still work
    end

    assert_equal %w[a b c], results[0]
    # with_scores should return [member, score, member, score, ...]
    assert_equal %w[a 1 b 2 c 3], results[1]
    assert_equal %w[a 1 b 2 c 3], results[2]
  ensure
    redis.del("test:zset")
  end

  # Test that zrevrange accepts with_scores: keyword
  def test_transaction_zrevrange_with_scores_keyword
    redis.zadd("test:zset", 1, "a", 2, "b", 3, "c")

    results = redis.multi do |tx|
      tx.zrevrange("test:zset", 0, -1, with_scores: true)
    end

    assert_equal %w[c 3 b 2 a 1], results[0]
  ensure
    redis.del("test:zset")
  end

  # Test that zrangebyscore accepts with_scores: keyword
  def test_transaction_zrangebyscore_with_scores_keyword
    redis.zadd("test:zset", 1, "a", 2, "b", 3, "c")

    results = redis.multi do |tx|
      tx.zrangebyscore("test:zset", 1, 2, with_scores: true)
    end

    assert_equal %w[a 1 b 2], results[0]
  ensure
    redis.del("test:zset")
  end

  # Test that zrevrangebyscore accepts with_scores: keyword
  def test_transaction_zrevrangebyscore_with_scores_keyword
    redis.zadd("test:zset", 1, "a", 2, "b", 3, "c")

    results = redis.multi do |tx|
      tx.zrevrangebyscore("test:zset", 3, 2, with_scores: true)
    end

    assert_equal %w[c 3 b 2], results[0]
  ensure
    redis.del("test:zset")
  end

  # Test that arbitrary commands work via method_missing
  def test_transaction_arbitrary_command_via_method_missing
    results = redis.multi do |tx|
      tx.set("test:key", "value")
      tx.get("test:key")
      tx.echo("hello") # Less common command, should work via method_missing if not defined
    end

    assert_equal %w[OK value hello], results
  ensure
    redis.del("test:key")
  end

  # Test exists? convenience method in transaction
  def test_transaction_exists_question
    redis.set("test:key", "value")

    results = redis.multi do |tx|
      tx.exists?("test:key")
      tx.exists?("test:nonexistent")
    end

    # exists? returns count in transaction
    assert_equal [1, 0], results
  ensure
    redis.del("test:key")
  end

  # Test sismember? convenience method in transaction
  def test_transaction_sismember_question
    redis.sadd("test:set", "member1")

    results = redis.multi do |tx|
      tx.sismember?("test:set", "member1")
      tx.sismember?("test:set", "nonexistent")
    end

    # sismember? returns 1/0 in transaction
    assert_equal [1, 0], results
  ensure
    redis.del("test:set")
  end

  # Test mapped_mget in transaction
  def test_transaction_mapped_mget
    redis.set("test:k1", "v1")
    redis.set("test:k2", "v2")

    results = redis.multi do |tx|
      tx.mapped_mget("test:k1", "test:k2")
    end

    # In transaction, returns array of values, not hash
    assert_equal [%w[v1 v2]], results
  ensure
    redis.del("test:k1", "test:k2")
  end

  # Test mapped_hmget in transaction
  def test_transaction_mapped_hmget
    redis.hset("test:hash", "f1", "v1", "f2", "v2")

    results = redis.multi do |tx|
      tx.mapped_hmget("test:hash", "f1", "f2")
    end

    # In transaction, returns array of values
    assert_equal [%w[v1 v2]], results
  ensure
    redis.del("test:hash")
  end
end
