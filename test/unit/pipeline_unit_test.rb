# frozen_string_literal: true

require_relative "unit_test_helper"

class PipelineUnitTest < Minitest::Test
  # ============================================================
  # Helper: mock connection that records pipeline calls
  # ============================================================

  class MockConnection
    attr_reader :calls, :pipeline_calls

    def initialize
      @calls = []
      @pipeline_calls = []
    end

    def call(*args)
      @calls << args
      "OK"
    end

    def pipeline(commands)
      @pipeline_calls << commands
      commands.map { "OK" }
    end
  end

  def setup
    @conn = MockConnection.new
    @pipeline = RedisRuby::Pipeline.new(@conn)
  end

  # ============================================================
  # Initialization
  # ============================================================

  def test_pipeline_initializes_with_connection
    assert_instance_of RedisRuby::Pipeline, @pipeline
  end

  def test_pipeline_starts_empty
    assert_empty @pipeline
    assert_equal 0, @pipeline.size
  end

  # ============================================================
  # call - queuing commands
  # ============================================================

  def test_call_returns_self_for_chaining
    result = @pipeline.call("SET", "key", "value")

    assert_same @pipeline, result
  end

  def test_call_queues_command
    @pipeline.call("SET", "key", "value")

    assert_equal 1, @pipeline.size
  end

  def test_call_queues_multiple_commands
    @pipeline.call("SET", "k1", "v1")
    @pipeline.call("SET", "k2", "v2")
    @pipeline.call("GET", "k1")

    assert_equal 3, @pipeline.size
  end

  # ============================================================
  # call_1arg, call_2args, call_3args
  # ============================================================

  def test_call_1arg_returns_self
    result = @pipeline.call_1arg("GET", "key")

    assert_same @pipeline, result
    assert_equal 1, @pipeline.size
  end

  def test_call_2args_returns_self
    result = @pipeline.call_2args("HGET", "hash", "field")

    assert_same @pipeline, result
    assert_equal 1, @pipeline.size
  end

  def test_call_3args_returns_self
    result = @pipeline.call_3args("HSET", "hash", "field", "value")

    assert_same @pipeline, result
    assert_equal 1, @pipeline.size
  end

  # ============================================================
  # size / length / empty?
  # ============================================================

  def test_size_and_length_are_aliases
    assert_equal @pipeline.size, @pipeline.length
    @pipeline.call("SET", "k", "v")

    assert_equal @pipeline.size, @pipeline.length
    assert_equal 1, @pipeline.size
  end

  def test_empty_is_true_when_no_commands
    assert_empty @pipeline
  end

  def test_empty_is_false_after_queueing
    @pipeline.call("SET", "k", "v")

    refute_empty @pipeline
  end

  # ============================================================
  # execute
  # ============================================================

  def test_execute_returns_empty_array_when_no_commands
    result = @pipeline.execute

    assert_empty result
    assert_empty @conn.pipeline_calls
  end

  def test_execute_sends_commands_via_pipeline
    @pipeline.call("SET", "k1", "v1")
    @pipeline.call("GET", "k1")
    result = @pipeline.execute

    assert_equal 1, @conn.pipeline_calls.size
    assert_equal 2, @conn.pipeline_calls[0].size
    assert_equal %w[OK OK], result
  end

  # ============================================================
  # ping override
  # ============================================================

  def test_ping_queues_command
    result = @pipeline.ping

    assert_same @pipeline, result
    assert_equal 1, @pipeline.size
  end

  # ============================================================
  # hgetall override
  # ============================================================

  def test_hgetall_queues_raw_command
    result = @pipeline.hgetall("myhash")

    assert_same @pipeline, result
    assert_equal 1, @pipeline.size
  end

  # ============================================================
  # zscore / zmscore overrides
  # ============================================================

  def test_zscore_queues_command
    result = @pipeline.zscore("zset", "member")

    assert_same @pipeline, result
    assert_equal 1, @pipeline.size
  end

  def test_zmscore_queues_command
    result = @pipeline.zmscore("zset", "m1", "m2")

    assert_same @pipeline, result
    assert_equal 1, @pipeline.size
  end

  # ============================================================
  # zrange branches
  # ============================================================

  def test_zrange_without_scores
    @pipeline.zrange("zset", 0, -1)
    @pipeline.execute
    cmds = @conn.pipeline_calls[0]

    assert_equal ["ZRANGE", "zset", 0, -1], cmds[0]
  end

  def test_zrange_with_withscores
    @pipeline.zrange("zset", 0, -1, withscores: true)
    @pipeline.execute
    cmds = @conn.pipeline_calls[0]

    assert_includes cmds[0], "WITHSCORES"
  end

  def test_zrange_without_withscores_false
    @pipeline.zrange("zset", 0, -1, withscores: false)
    @pipeline.execute
    cmds = @conn.pipeline_calls[0]

    refute_includes cmds[0], "WITHSCORES"
  end

  # ============================================================
  # zrevrange branches
  # ============================================================

  def test_zrevrange_without_scores
    @pipeline.zrevrange("zset", 0, -1)
    @pipeline.execute
    cmds = @conn.pipeline_calls[0]

    assert_equal ["ZREVRANGE", "zset", 0, -1], cmds[0]
  end

  def test_zrevrange_with_withscores
    @pipeline.zrevrange("zset", 0, -1, withscores: true)
    @pipeline.execute
    cmds = @conn.pipeline_calls[0]

    assert_includes cmds[0], "WITHSCORES"
  end

  def test_zrevrange_without_withscores_false
    @pipeline.zrevrange("zset", 0, -1, withscores: false)
    @pipeline.execute
    cmds = @conn.pipeline_calls[0]

    refute_includes cmds[0], "WITHSCORES"
  end

  # ============================================================
  # zrangebyscore branches
  # ============================================================

  def test_zrangebyscore_without_options
    @pipeline.zrangebyscore("zset", "-inf", "+inf")
    @pipeline.execute
    cmds = @conn.pipeline_calls[0]

    assert_equal ["ZRANGEBYSCORE", "zset", "-inf", "+inf"], cmds[0]
  end

  def test_zrangebyscore_with_withscores
    @pipeline.zrangebyscore("zset", "-inf", "+inf", withscores: true)
    @pipeline.execute
    cmds = @conn.pipeline_calls[0]

    assert_includes cmds[0], "WITHSCORES"
  end

  def test_zrangebyscore_with_limit
    @pipeline.zrangebyscore("zset", "-inf", "+inf", limit: [0, 10])
    @pipeline.execute
    cmds = @conn.pipeline_calls[0]

    assert_includes cmds[0], "LIMIT"
    assert_includes cmds[0], 0
    assert_includes cmds[0], 10
  end

  def test_zrangebyscore_with_withscores_and_limit
    @pipeline.zrangebyscore("zset", "-inf", "+inf", withscores: true, limit: [0, 5])
    @pipeline.execute
    cmds = @conn.pipeline_calls[0]

    assert_includes cmds[0], "WITHSCORES"
    assert_includes cmds[0], "LIMIT"
  end

  def test_zrangebyscore_without_withscores_without_limit
    @pipeline.zrangebyscore("zset", 0, 100, withscores: false, limit: nil)
    @pipeline.execute
    cmds = @conn.pipeline_calls[0]

    refute_includes cmds[0], "WITHSCORES"
    refute_includes cmds[0], "LIMIT"
  end

  # ============================================================
  # zrevrangebyscore branches
  # ============================================================

  def test_zrevrangebyscore_without_options
    @pipeline.zrevrangebyscore("zset", "+inf", "-inf")
    @pipeline.execute
    cmds = @conn.pipeline_calls[0]

    assert_equal ["ZREVRANGEBYSCORE", "zset", "+inf", "-inf"], cmds[0]
  end

  def test_zrevrangebyscore_with_withscores
    @pipeline.zrevrangebyscore("zset", "+inf", "-inf", withscores: true)
    @pipeline.execute
    cmds = @conn.pipeline_calls[0]

    assert_includes cmds[0], "WITHSCORES"
  end

  def test_zrevrangebyscore_with_limit
    @pipeline.zrevrangebyscore("zset", "+inf", "-inf", limit: [0, 10])
    @pipeline.execute
    cmds = @conn.pipeline_calls[0]

    assert_includes cmds[0], "LIMIT"
  end

  def test_zrevrangebyscore_with_withscores_and_limit
    @pipeline.zrevrangebyscore("zset", "+inf", "-inf", withscores: true, limit: [0, 5])
    @pipeline.execute
    cmds = @conn.pipeline_calls[0]

    assert_includes cmds[0], "WITHSCORES"
    assert_includes cmds[0], "LIMIT"
  end

  def test_zrevrangebyscore_without_withscores_without_limit
    @pipeline.zrevrangebyscore("zset", 100, 0, withscores: false, limit: nil)
    @pipeline.execute
    cmds = @conn.pipeline_calls[0]

    refute_includes cmds[0], "WITHSCORES"
    refute_includes cmds[0], "LIMIT"
  end

  # ============================================================
  # zincrby
  # ============================================================

  def test_zincrby_queues_command
    result = @pipeline.zincrby("zset", 1.5, "member")

    assert_same @pipeline, result
    assert_equal 1, @pipeline.size
  end

  # ============================================================
  # zpopmin / zpopmax branches
  # ============================================================

  def test_zpopmin_without_count
    @pipeline.zpopmin("zset")
    @pipeline.execute
    cmds = @conn.pipeline_calls[0]

    assert_equal %w[ZPOPMIN zset], cmds[0]
  end

  def test_zpopmin_with_count
    @pipeline.zpopmin("zset", 3)
    @pipeline.execute
    cmds = @conn.pipeline_calls[0]

    assert_equal ["ZPOPMIN", "zset", 3], cmds[0]
  end

  def test_zpopmax_without_count
    @pipeline.zpopmax("zset")
    @pipeline.execute
    cmds = @conn.pipeline_calls[0]

    assert_equal %w[ZPOPMAX zset], cmds[0]
  end

  def test_zpopmax_with_count
    @pipeline.zpopmax("zset", 2)
    @pipeline.execute
    cmds = @conn.pipeline_calls[0]

    assert_equal ["ZPOPMAX", "zset", 2], cmds[0]
  end

  # ============================================================
  # bzpopmin / bzpopmax
  # ============================================================

  def test_bzpopmin_default_timeout
    @pipeline.bzpopmin("zset1", "zset2")
    @pipeline.execute
    cmds = @conn.pipeline_calls[0]

    assert_equal ["BZPOPMIN", "zset1", "zset2", 0], cmds[0]
  end

  def test_bzpopmin_custom_timeout
    @pipeline.bzpopmin("zset1", timeout: 5)
    @pipeline.execute
    cmds = @conn.pipeline_calls[0]

    assert_equal ["BZPOPMIN", "zset1", 5], cmds[0]
  end

  def test_bzpopmax_default_timeout
    @pipeline.bzpopmax("zset1", "zset2")
    @pipeline.execute
    cmds = @conn.pipeline_calls[0]

    assert_equal ["BZPOPMAX", "zset1", "zset2", 0], cmds[0]
  end

  def test_bzpopmax_custom_timeout
    @pipeline.bzpopmax("zset1", timeout: 10)
    @pipeline.execute
    cmds = @conn.pipeline_calls[0]

    assert_equal ["BZPOPMAX", "zset1", 10], cmds[0]
  end

  # ============================================================
  # zscan branches
  # ============================================================

  def test_zscan_without_options
    @pipeline.zscan("zset", "0")
    @pipeline.execute
    cmds = @conn.pipeline_calls[0]

    assert_equal %w[ZSCAN zset 0], cmds[0]
  end

  def test_zscan_with_match
    @pipeline.zscan("zset", "0", match: "foo*")
    @pipeline.execute
    cmds = @conn.pipeline_calls[0]

    assert_includes cmds[0], "MATCH"
    assert_includes cmds[0], "foo*"
  end

  def test_zscan_with_count
    @pipeline.zscan("zset", "0", count: 100)
    @pipeline.execute
    cmds = @conn.pipeline_calls[0]

    assert_includes cmds[0], "COUNT"
    assert_includes cmds[0], 100
  end

  def test_zscan_with_match_and_count
    @pipeline.zscan("zset", "0", match: "bar*", count: 50)
    @pipeline.execute
    cmds = @conn.pipeline_calls[0]

    assert_includes cmds[0], "MATCH"
    assert_includes cmds[0], "bar*"
    assert_includes cmds[0], "COUNT"
    assert_includes cmds[0], 50
  end

  def test_zscan_without_match_without_count
    @pipeline.zscan("zset", "0", match: nil, count: nil)
    @pipeline.execute
    cmds = @conn.pipeline_calls[0]

    refute_includes cmds[0], "MATCH"
    refute_includes cmds[0], "COUNT"
  end

  # ============================================================
  # Commands from included modules work through pipeline
  # ============================================================

  def test_set_via_included_module
    @pipeline.set("key", "value")

    assert_equal 1, @pipeline.size
  end

  def test_get_via_included_module
    @pipeline.get("key")

    assert_equal 1, @pipeline.size
  end

  def test_del_via_included_module
    @pipeline.del("key")

    assert_equal 1, @pipeline.size
  end

  def test_incr_via_included_module
    @pipeline.incr("counter")

    assert_equal 1, @pipeline.size
  end

  def test_sadd_via_included_module
    @pipeline.sadd("myset", "member")

    assert_equal 1, @pipeline.size
  end

  def test_hset_via_included_module
    @pipeline.hset("myhash", "field", "value")

    assert_equal 1, @pipeline.size
  end

  # ============================================================
  # Chaining
  # ============================================================

  def test_chained_calls
    result = @pipeline
      .call("SET", "k1", "v1")
      .call("SET", "k2", "v2")
      .call("GET", "k1")

    assert_same @pipeline, result
    assert_equal 3, @pipeline.size
  end
end
