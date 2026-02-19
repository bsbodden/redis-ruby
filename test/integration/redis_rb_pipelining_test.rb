# frozen_string_literal: true

require_relative "../test_helper"
require "redis"

# These tests mirror the redis-rb pipelining tests to ensure compatibility
class RedisRbPipeliningTest < Minitest::Test
  def setup
    @redis = Redis.new(url: ENV["REDIS_URL"] || "redis://localhost:6379")
    @redis.flushdb
  end

  def teardown
    @redis&.flushdb
  end

  def r
    @redis
  end

  def test_bulk_commands
    r.pipelined do |p|
      p.lpush "foo", "s1"
      p.lpush "foo", "s2"
    end

    assert_equal 2, r.llen("foo")
    assert_equal "s2", r.lpop("foo")
    assert_equal "s1", r.lpop("foo")
  end

  def test_multi_bulk_commands
    r.pipelined do |p|
      p.mset("foo", "s1", "bar", "s2")
      p.mset("baz", "s3", "qux", "s4")
    end

    assert_equal "s1", r.get("foo")
    assert_equal "s2", r.get("bar")
    assert_equal "s3", r.get("baz")
    assert_equal "s4", r.get("qux")
  end

  def test_bulk_and_multi_bulk_commands_mixed
    r.pipelined do |p|
      p.lpush "foo", "s1"
      p.lpush "foo", "s2"
      p.mset("baz", "s3", "qux", "s4")
    end

    assert_equal 2, r.llen("foo")
    assert_equal "s2", r.lpop("foo")
    assert_equal "s1", r.lpop("foo")
    assert_equal "s3", r.get("baz")
    assert_equal "s4", r.get("qux")
  end

  def test_multi_bulk_and_bulk_commands_mixed
    r.pipelined do |p|
      p.mset("baz", "s3", "qux", "s4")
      p.lpush "foo", "s1"
      p.lpush "foo", "s2"
    end

    assert_equal 2, r.llen("foo")
    assert_equal "s2", r.lpop("foo")
    assert_equal "s1", r.lpop("foo")
    assert_equal "s3", r.get("baz")
    assert_equal "s4", r.get("qux")
  end

  def test_pipelined_with_an_empty_block
    r.pipelined do
      # Intentionally empty to test empty pipeline behavior
    end

    assert_equal 0, r.dbsize
  end

  def test_returning_the_result_of_a_pipeline
    result = r.pipelined do |p|
      p.set "foo", "bar"
      p.get "foo"
      p.get "bar"
    end

    assert_equal ["OK", "bar", nil], result
  end

  def test_assignment_of_results_inside_the_block
    r.pipelined do |p|
      @first = p.sadd?("foo", 1)
      @second = p.sadd?("foo", 1)
    end

    assert @first.value
    refute @second.value
  end

  def test_assignment_of_results_inside_the_block_with_errors
    assert_raises(Redis::CommandError) do
      r.pipelined do |p|
        p.doesnt_exist
        @first = p.sadd?("foo", 1)
        @second = p.sadd?("foo", 1)
      end
    end

    assert_raises(Redis::FutureNotReady) { @first.value }
    assert_raises(Redis::FutureNotReady) { @second.value }
  end

  def test_assignment_of_results_inside_a_nested_block
    r.pipelined do |p|
      @first = p.sadd?("foo", 1)

      p.pipelined do |p2|
        @second = p2.sadd?("foo", 1)
      end
    end

    assert @first.value
    refute @second.value
  end

  def test_futures_raise_when_confused_with_something_else
    r.pipelined do |p|
      @result = p.sadd?("foo", 1)
    end

    assert_raises(NoMethodError) { @result.to_s }
  end

  def test_futures_raise_when_trying_to_access_their_values_too_early
    r.pipelined do |p|
      assert_raises(Redis::FutureNotReady) do
        p.sadd("foo", 1).value
      end
    end
  end

  def test_futures_can_be_identified
    r.pipelined do |p|
      @result = p.sadd("foo", 1)
    end

    assert_kind_of Redis::Future, @result
    assert_instance_of Redis::Future, @result
  end

  def test_returning_the_result_of_an_empty_pipeline
    result = r.pipelined do
      # Intentionally empty to test empty pipeline result
    end

    assert_empty result
  end

  def test_nesting_pipeline_blocks
    r.pipelined do |p|
      p.set("foo", "s1")
      p.pipelined do |p2|
        p2.set("bar", "s2")
      end
    end

    assert_equal "s1", r.get("foo")
    assert_equal "s2", r.get("bar")
  end

  def test_info_in_a_pipeline_returns_hash
    result = r.pipelined(&:info)

    assert_kind_of Hash, result.first
  end

  def test_config_get_in_a_pipeline_returns_hash
    result = r.pipelined do |p|
      p.config(:get, "*")
    end

    assert_kind_of Hash, result.first
  end

  def test_hgetall_in_a_pipeline_returns_hash
    r.hmset("hash", "field", "value")
    future = nil
    result = r.pipelined do |p|
      future = p.hgetall("hash")
    end

    assert_equal([{ "field" => "value" }], result)
    assert_equal({ "field" => "value" }, future.value)
  end

  def test_zpopmax_in_a_pipeline_produces_future
    r.zadd("sortedset", 1.0, "value")
    future = nil
    result = r.pipelined do |pipeline|
      future = pipeline.zpopmax("sortedset")
    end

    assert_equal [["value", 1.0]], result
    assert_equal ["value", 1.0], future.value
  end

  def test_hgetall_in_a_multi_in_a_pipeline_returns_hash
    future = nil
    result = r.pipelined do |p|
      p.multi do |m|
        m.hmset("hash", "field", "value", "field2", "value2")
        future = m.hgetall("hash")
      end
    end

    # In a pipeline, multi returns: [OK, QUEUED, QUEUED, [result1, result2]]
    # The last element is the EXEC result array
    exec_result = result.last

    assert_equal({ "field" => "value", "field2" => "value2" }, exec_result.last)
    assert_equal({ "field" => "value", "field2" => "value2" }, future.value)
  end

  def test_keys_in_a_pipeline
    r.set("key", "value")
    result = r.pipelined do |p|
      p.keys("*")
    end

    assert_equal ["key"], result.first
  end

  def test_pipeline_yields_a_connection
    r.pipelined do |p|
      p.set("foo", "bar")
    end

    assert_equal "bar", r.get("foo")
  end

  def test_pipeline_select
    r.select 1
    r.set("db", "1")

    r.pipelined do |p|
      p.select 2
      p.set("db", "2")
    end

    r.select 1

    assert_equal "1", r.get("db")

    r.select 2

    assert_equal "2", r.get("db")
  end
end
