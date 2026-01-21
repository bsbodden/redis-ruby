# frozen_string_literal: true

require "test_helper"

class PipelineTest < RedisRubyTestCase
  use_testcontainers!

  def test_pipelined_basic
    results = redis.pipelined do |pipe|
      pipe.set("test:pipe1", "value1")
      pipe.set("test:pipe2", "value2")
      pipe.get("test:pipe1")
      pipe.get("test:pipe2")
    end

    assert_equal ["OK", "OK", "value1", "value2"], results
  ensure
    redis.del("test:pipe1", "test:pipe2")
  end

  def test_pipelined_empty
    results = redis.pipelined do |_pipe|
      # No commands
    end

    assert_equal [], results
  end

  def test_pipelined_with_nil_result
    redis.del("test:missing")
    results = redis.pipelined do |pipe|
      pipe.set("test:exists", "value")
      pipe.get("test:exists")
      pipe.get("test:missing")
    end

    assert_equal ["OK", "value", nil], results
  ensure
    redis.del("test:exists")
  end

  def test_pipelined_with_integers
    redis.del("test:counter")
    results = redis.pipelined do |pipe|
      pipe.incr("test:counter")
      pipe.incr("test:counter")
      pipe.incr("test:counter")
    end

    assert_equal [1, 2, 3], results
  ensure
    redis.del("test:counter")
  end

  def test_pipelined_mixed_commands
    results = redis.pipelined do |pipe|
      pipe.set("test:key", "value")
      pipe.lpush("test:list", "a", "b", "c")
      pipe.sadd("test:set", "x", "y", "z")
      pipe.get("test:key")
      pipe.lrange("test:list", 0, -1)
      pipe.smembers("test:set")
    end

    assert_equal "OK", results[0]
    assert_equal 3, results[1]
    assert_equal 3, results[2]
    assert_equal "value", results[3]
    assert_equal %w[c b a], results[4]
    assert_equal 3, results[5].length
  ensure
    redis.del("test:key", "test:list", "test:set")
  end

  def test_pipelined_hash_commands
    results = redis.pipelined do |pipe|
      pipe.hset("test:hash", "f1", "v1", "f2", "v2")
      pipe.hget("test:hash", "f1")
      pipe.hgetall("test:hash")
    end

    assert_equal 2, results[0]
    assert_equal "v1", results[1]
    # hgetall returns array in pipeline, need to convert
    assert_kind_of Array, results[2]
  ensure
    redis.del("test:hash")
  end

  def test_pipelined_sorted_set_commands
    results = redis.pipelined do |pipe|
      pipe.zadd("test:zset", 1, "one", 2, "two", 3, "three")
      pipe.zrange("test:zset", 0, -1)
      pipe.zscore("test:zset", "two")
    end

    assert_equal 3, results[0]
    assert_equal %w[one two three], results[1]
    assert_equal "2", results[2] # Note: score returned as string in pipeline
  ensure
    redis.del("test:zset")
  end

  def test_pipelined_with_expiration
    results = redis.pipelined do |pipe|
      pipe.set("test:expiring", "value", ex: 100)
      pipe.ttl("test:expiring")
    end

    assert_equal "OK", results[0]
    assert results[1] > 0 && results[1] <= 100
  ensure
    redis.del("test:expiring")
  end

  def test_pipelined_performance
    # Pipeline should be faster than individual calls for many commands
    start_pipeline = Time.now
    redis.pipelined do |pipe|
      100.times { |i| pipe.set("test:perf#{i}", "value#{i}") }
    end
    pipeline_time = Time.now - start_pipeline

    # Cleanup
    keys = (0...100).map { |i| "test:perf#{i}" }
    redis.del(*keys)

    # Just verify it completed - actual performance testing is in benchmarks
    assert pipeline_time < 5 # Should complete in under 5 seconds
  end
end
