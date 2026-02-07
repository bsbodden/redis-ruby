# frozen_string_literal: true

require_relative "unit_test_helper"

# Load the redis-rb compatibility layer
require "redis"

# ============================================================================
# Future Class Branch Coverage Tests
# ============================================================================
class FutureBranchTest < Minitest::Test
  # ---------- Initialization ----------

  def test_future_stores_command
    future = Redis::Future.new(%w[GET key])

    assert_equal %w[GET key], future.command
  end

  def test_future_starts_unresolved
    future = Redis::Future.new(%w[GET key])

    refute_predicate future, :resolved?
  end

  # ---------- value branches ----------

  def test_value_raises_when_not_resolved
    future = Redis::Future.new(%w[GET key])
    assert_raises(Redis::FutureNotReady) { future.value }
  end

  def test_value_returns_value_when_resolved
    future = Redis::Future.new(%w[GET key])
    future._set_value("hello")

    assert_equal "hello", future.value
  end

  def test_value_returns_nil_when_resolved_with_nil
    future = Redis::Future.new(%w[GET key])
    future._set_value(nil)

    assert_nil future.value
  end

  def test_value_returns_integer_when_resolved
    future = Redis::Future.new(%w[INCR key])
    future._set_value(42)

    assert_equal 42, future.value
  end

  # ---------- value with transformation ----------

  def test_value_with_transformation
    future = Redis::Future.new(%w[GET key])
    future.then(&:upcase)
    future._set_value("hello")

    assert_equal "HELLO", future.value
  end

  def test_value_without_transformation
    future = Redis::Future.new(%w[GET key])
    future._set_value("hello")

    assert_equal "hello", future.value
  end

  def test_then_returns_self
    future = Redis::Future.new(%w[GET key])
    result = future.then { |v| v }

    assert_same future, result
  end

  def test_chained_transformation
    future = Redis::Future.new(%w[GET key])
    # Only the last transformation applies
    future.then { |v| v.to_i * 2 }
    future._set_value("5")

    assert_equal 10, future.value
  end

  # ---------- resolved? ----------

  def test_resolved_false_before_set
    future = Redis::Future.new(["PING"])

    refute_predicate future, :resolved?
  end

  def test_resolved_true_after_set
    future = Redis::Future.new(["PING"])
    future._set_value("PONG")

    assert_predicate future, :resolved?
  end

  # ---------- _set_value ----------

  def test_set_value_marks_as_resolved
    future = Redis::Future.new(%w[GET key])
    future._set_value("val")

    assert_predicate future, :resolved?
  end

  def test_set_value_stores_the_value
    future = Redis::Future.new(%w[GET key])
    future._set_value([1, 2, 3])

    assert_equal [1, 2, 3], future.value
  end

  # ---------- inspect branches ----------

  def test_inspect_when_resolved
    future = Redis::Future.new(%w[GET key])
    future._set_value("hello")
    result = future.inspect

    assert_includes result, "@value="
    assert_includes result, "hello"
  end

  def test_inspect_when_pending
    future = Redis::Future.new(%w[GET key])
    result = future.inspect

    assert_includes result, "(pending)"
  end

  # ---------- class / is_a? / instance_of? / kind_of? ----------

  def test_class_returns_future
    future = Redis::Future.new(%w[GET key])

    assert_instance_of Redis::Future, future
  end

  def test_is_a_future
    future = Redis::Future.new(%w[GET key])

    assert_kind_of Redis::Future, future
  end

  def test_is_a_basic_object
    future = Redis::Future.new(%w[GET key])

    assert_kind_of BasicObject, future
  end

  def test_is_not_a_string
    future = Redis::Future.new(%w[GET key])

    refute_kind_of String, future
  end

  def test_instance_of_future
    future = Redis::Future.new(%w[GET key])

    assert_instance_of Redis::Future, future
  end

  def test_not_instance_of_string
    future = Redis::Future.new(%w[GET key])

    refute_instance_of String, future
  end

  def test_kind_of_is_alias_for_is_a
    future = Redis::Future.new(%w[GET key])

    assert_kind_of Redis::Future, future
    refute_kind_of String, future
  end

  # ---------- instance_variable_defined? branches ----------

  def test_instance_variable_defined_command
    future = Redis::Future.new(%w[GET key])

    assert future.instance_variable_defined?(:@command)
  end

  def test_instance_variable_defined_value
    future = Redis::Future.new(%w[GET key])

    assert future.instance_variable_defined?(:@value)
  end

  def test_instance_variable_defined_resolved
    future = Redis::Future.new(%w[GET key])

    assert future.instance_variable_defined?(:@resolved)
  end

  def test_instance_variable_defined_transformation
    future = Redis::Future.new(%w[GET key])

    assert future.instance_variable_defined?(:@transformation)
  end

  def test_instance_variable_defined_inner_futures_before_set
    future = Redis::Future.new(%w[GET key])

    refute future.instance_variable_defined?(:@inner_futures)
  end

  def test_instance_variable_defined_inner_futures_after_set
    future = Redis::Future.new(["EXEC"])
    future.instance_variable_set(:@inner_futures, [])

    assert future.instance_variable_defined?(:@inner_futures)
  end

  def test_instance_variable_defined_unknown
    future = Redis::Future.new(%w[GET key])

    refute future.instance_variable_defined?(:@nonexistent)
  end

  # ---------- instance_variable_get branches ----------

  def test_instance_variable_get_command
    future = Redis::Future.new(%w[GET key])

    assert_equal %w[GET key], future.instance_variable_get(:@command)
  end

  def test_instance_variable_get_value
    future = Redis::Future.new(%w[GET key])
    future._set_value("hello")

    assert_equal "hello", future.instance_variable_get(:@value)
  end

  def test_instance_variable_get_resolved
    future = Redis::Future.new(%w[GET key])

    refute future.instance_variable_get(:@resolved)
  end

  def test_instance_variable_get_transformation
    future = Redis::Future.new(%w[GET key])

    assert_nil future.instance_variable_get(:@transformation)
  end

  def test_instance_variable_get_inner_futures
    future = Redis::Future.new(["EXEC"])
    inner = [Redis::Future.new(%w[SET k v])]
    future.instance_variable_set(:@inner_futures, inner)

    assert_equal inner, future.instance_variable_get(:@inner_futures)
  end

  def test_instance_variable_get_unknown
    future = Redis::Future.new(%w[GET key])

    assert_nil future.instance_variable_get(:@unknown)
  end

  # ---------- instance_variable_set branches ----------

  def test_instance_variable_set_command
    future = Redis::Future.new(%w[GET key])
    future.instance_variable_set(:@command, %w[SET k v])

    assert_equal %w[SET k v], future.instance_variable_get(:@command)
  end

  def test_instance_variable_set_value
    future = Redis::Future.new(%w[GET key])
    future.instance_variable_set(:@value, "test")

    assert_equal "test", future.instance_variable_get(:@value)
  end

  def test_instance_variable_set_resolved
    future = Redis::Future.new(%w[GET key])
    future.instance_variable_set(:@resolved, true)

    assert_predicate future, :resolved?
  end

  def test_instance_variable_set_transformation
    block = proc(&:to_i)
    future = Redis::Future.new(%w[GET key])
    future.instance_variable_set(:@transformation, block)
    future._set_value("42")

    assert_equal 42, future.value
  end

  def test_instance_variable_set_inner_futures
    future = Redis::Future.new(["EXEC"])
    inner = []
    future.instance_variable_set(:@inner_futures, inner)

    assert_equal inner, future.instance_variable_get(:@inner_futures)
  end
end

# ============================================================================
# FutureNotReady Tests
# ============================================================================
class FutureNotReadyTest < Minitest::Test
  def test_future_not_ready_message
    error = Redis::FutureNotReady.new

    assert_includes error.message, "pipeline"
  end

  def test_future_not_ready_is_runtime_error
    assert_operator Redis::FutureNotReady, :<, RuntimeError
  end
end

# ============================================================================
# PipelinedConnection Branch Coverage Tests
# ============================================================================
class PipelinedConnectionBranchTest < Minitest::Test
  def setup
    @mock_client = mock("client")
    @mock_pipeline = mock("pipeline")
    @mock_pipeline.stubs(:call).returns(nil)
    @mock_pipeline.stubs(:call_1arg).returns(nil)
    @mock_pipeline.stubs(:call_2args).returns(nil)
    @mock_pipeline.stubs(:call_3args).returns(nil)
  end

  # ---------- call returns Future ----------

  def test_call_returns_future
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.call("GET", "key")

    assert_instance_of Redis::Future, future
    assert_equal %w[GET key], future.command
  end

  def test_call_queues_in_pipeline
    @mock_pipeline.expects(:call).with("SET", "k", "v").once
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.call("SET", "k", "v")
  end

  # ---------- Fast path variants ----------

  def test_call_1arg_returns_future
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.call_1arg("GET", "key")

    assert_instance_of Redis::Future, future
    assert_equal %w[GET key], future.command
  end

  def test_call_2args_returns_future
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.call_2args("SET", "k", "v")

    assert_instance_of Redis::Future, future
    assert_equal %w[SET k v], future.command
  end

  def test_call_3args_returns_future
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.call_3args("HSET", "h", "f", "v")

    assert_instance_of Redis::Future, future
    assert_equal %w[HSET h f v], future.command
  end

  # ---------- _resolve_futures branches ----------

  def test_resolve_futures_sets_values
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    f1 = pc.call("SET", "k", "v")
    f2 = pc.call_1arg("GET", "k")

    pc._resolve_futures(%w[OK value])

    assert_equal "OK", f1.value
    assert_equal "value", f2.value
  end

  def test_resolve_futures_with_inner_futures_and_array_result
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    exec_future = pc.call("EXEC")

    inner1 = Redis::Future.new(%w[SET k v])
    inner2 = Redis::Future.new(%w[GET k])
    exec_future.instance_variable_set(:@inner_futures, [inner1, inner2])

    # EXEC returns an array of results
    pc._resolve_futures([%w[OK value]])

    # Inner futures should be resolved
    assert_equal "OK", inner1.value
    assert_equal "value", inner2.value
    # exec_future should have the transformed result
    assert_equal %w[OK value], exec_future.value
  end

  def test_resolve_futures_with_inner_futures_non_array_result
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    exec_future = pc.call("EXEC")

    inner1 = Redis::Future.new(%w[SET k v])
    exec_future.instance_variable_set(:@inner_futures, [inner1])

    # EXEC returns nil (aborted transaction)
    pc._resolve_futures([nil])

    # The future should be set with nil
    assert_nil exec_future.value
  end

  def test_resolve_futures_without_inner_futures
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    f1 = pc.call("PING")
    pc._resolve_futures(["PONG"])

    assert_equal "PONG", f1.value
  end

  def test_resolve_futures_inner_futures_respects_result_length
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    exec_future = pc.call("EXEC")

    inner1 = Redis::Future.new(%w[SET k1 v1])
    inner2 = Redis::Future.new(%w[SET k2 v2])
    exec_future.instance_variable_set(:@inner_futures, [inner1, inner2])

    # Result has matching number of items
    pc._resolve_futures([%w[OK OK]])

    assert_equal "OK", inner1.value
    assert_equal "OK", inner2.value
    # The exec_future value should be the mapped values from inner futures
    assert_equal %w[OK OK], exec_future.value
  end

  # ---------- _get_values ----------

  def test_get_values_returns_transformed_values
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.call("SET", "k", "v")
    f2 = pc.call_1arg("GET", "k")
    f2.then { |v| v&.upcase }

    pc._resolve_futures(%w[OK hello])

    values = pc._get_values

    assert_equal %w[OK HELLO], values
  end

  # ---------- Command delegation methods ----------

  def test_ping
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.ping

    assert_instance_of Redis::Future, future
  end

  def test_set_simple
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    @mock_pipeline.expects(:call_2args).with("SET", "k", "v")
    future = pc.set("k", "v")

    assert_instance_of Redis::Future, future
  end

  def test_set_with_options
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    @mock_pipeline.expects(:call).with("SET", "k", "v", "EX", 100)
    future = pc.set("k", "v", ex: 100)

    assert_instance_of Redis::Future, future
  end

  def test_set_with_nx
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    @mock_pipeline.expects(:call).with("SET", "k", "v", "NX")
    future = pc.set("k", "v", nx: true)

    assert_instance_of Redis::Future, future
  end

  def test_set_with_xx
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    @mock_pipeline.expects(:call).with("SET", "k", "v", "XX")
    pc.set("k", "v", xx: true)
  end

  def test_set_with_keepttl
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    @mock_pipeline.expects(:call).with("SET", "k", "v", "KEEPTTL")
    pc.set("k", "v", keepttl: true)
  end

  def test_set_with_get
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    @mock_pipeline.expects(:call).with("SET", "k", "v", "GET")
    pc.set("k", "v", get: true)
  end

  def test_set_with_px
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    @mock_pipeline.expects(:call).with("SET", "k", "v", "PX", 5000)
    pc.set("k", "v", px: 5000)
  end

  def test_set_with_exat
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    @mock_pipeline.expects(:call).with("SET", "k", "v", "EXAT", 1_700_000_000)
    pc.set("k", "v", exat: 1_700_000_000)
  end

  def test_set_with_pxat
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    @mock_pipeline.expects(:call).with("SET", "k", "v", "PXAT", 1_700_000_000_000)
    pc.set("k", "v", pxat: 1_700_000_000_000)
  end

  def test_get
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.get("key")

    assert_instance_of Redis::Future, future
  end

  def test_del_single_key
    @mock_pipeline.expects(:call_1arg).with("DEL", "key")
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.del("key")
  end

  def test_del_multiple_keys
    @mock_pipeline.expects(:call).with("DEL", "k1", "k2")
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.del("k1", "k2")
  end

  def test_exists_single_key
    @mock_pipeline.expects(:call_1arg).with("EXISTS", "key")
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.exists("key")
  end

  def test_exists_multiple_keys
    @mock_pipeline.expects(:call).with("EXISTS", "k1", "k2")
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.exists("k1", "k2")
  end

  def test_incr
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.incr("counter")

    assert_instance_of Redis::Future, future
  end

  def test_decr
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.decr("counter")

    assert_instance_of Redis::Future, future
  end

  def test_mget
    @mock_pipeline.expects(:call).with("MGET", "k1", "k2")
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.mget("k1", "k2")
  end

  def test_mapped_mget_returns_transformed_future
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.mapped_mget("k1", "k2")
    # The future should have a transformation
    assert_instance_of Redis::Future, future
  end

  def test_hset_with_2_field_values
    @mock_pipeline.expects(:call_3args).with("HSET", "h", "f", "v")
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.hset("h", "f", "v")
  end

  def test_hset_with_multiple_field_values
    @mock_pipeline.expects(:call).with("HSET", "h", "f1", "v1", "f2", "v2")
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.hset("h", "f1", "v1", "f2", "v2")
  end

  def test_hget
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.hget("h", "f")

    assert_instance_of Redis::Future, future
  end

  def test_hdel_single
    @mock_pipeline.expects(:call_2args).with("HDEL", "h", "f")
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.hdel("h", "f")
  end

  def test_hdel_multiple
    @mock_pipeline.expects(:call).with("HDEL", "h", "f1", "f2")
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.hdel("h", "f1", "f2")
  end

  def test_hgetall
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.hgetall("myhash")
    # Has transformation applied
    assert_instance_of Redis::Future, future
  end

  def test_lpush
    @mock_pipeline.expects(:call).with("LPUSH", "list", "val")
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.lpush("list", "val")
  end

  def test_rpush
    @mock_pipeline.expects(:call).with("RPUSH", "list", "val")
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.rpush("list", "val")
  end

  def test_lpop_without_count
    @mock_pipeline.expects(:call_1arg).with("LPOP", "list")
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.lpop("list")
  end

  def test_lpop_with_count
    @mock_pipeline.expects(:call_2args).with("LPOP", "list", 3)
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.lpop("list", 3)
  end

  def test_rpop_without_count
    @mock_pipeline.expects(:call_1arg).with("RPOP", "list")
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.rpop("list")
  end

  def test_rpop_with_count
    @mock_pipeline.expects(:call_2args).with("RPOP", "list", 2)
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.rpop("list", 2)
  end

  def test_sadd_single
    @mock_pipeline.expects(:call_2args).with("SADD", "set", "member")
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.sadd("set", "member")
  end

  def test_sadd_multiple
    @mock_pipeline.expects(:call).with("SADD", "set", "m1", "m2")
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.sadd("set", "m1", "m2")
  end

  def test_srem_single
    @mock_pipeline.expects(:call_2args).with("SREM", "set", "member")
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.srem("set", "member")
  end

  def test_srem_multiple
    @mock_pipeline.expects(:call).with("SREM", "set", "m1", "m2")
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.srem("set", "m1", "m2")
  end

  def test_sadd_boolean_single
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.sadd?("set", "member")

    assert_instance_of Redis::Future, future
  end

  def test_srem_boolean_single
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.srem?("set", "member")

    assert_instance_of Redis::Future, future
  end

  def test_zpopmin_without_count
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.zpopmin("zset")

    assert_instance_of Redis::Future, future
  end

  def test_zpopmin_with_count
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.zpopmin("zset", 3)

    assert_instance_of Redis::Future, future
  end

  def test_zpopmax_without_count
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.zpopmax("zset")

    assert_instance_of Redis::Future, future
  end

  def test_zpopmax_with_count
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.zpopmax("zset", 3)

    assert_instance_of Redis::Future, future
  end

  def test_zadd_basic
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.zadd("zset", 1.0, "member")

    assert_instance_of Redis::Future, future
  end

  def test_zadd_with_options
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.zadd("zset", 1.0, "member", nx: true, ch: true)

    assert_instance_of Redis::Future, future
  end

  def test_zrem_single
    @mock_pipeline.expects(:call_2args).with("ZREM", "zset", "member")
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.zrem("zset", "member")
  end

  def test_zrem_multiple
    @mock_pipeline.expects(:call).with("ZREM", "zset", "m1", "m2")
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.zrem("zset", "m1", "m2")
  end

  def test_zrange_without_scores
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.zrange("zset", 0, -1)
  end

  def test_zrange_with_scores
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.zrange("zset", 0, -1, withscores: true)
  end

  def test_zrevrange_without_scores
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.zrevrange("zset", 0, -1)
  end

  def test_zrevrange_with_scores
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.zrevrange("zset", 0, -1, withscores: true)
  end

  def test_zrangebyscore_basic
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.zrangebyscore("zset", "-inf", "+inf")
  end

  def test_zrangebyscore_with_scores_and_limit
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.zrangebyscore("zset", "-inf", "+inf", withscores: true, limit: [0, 10])
  end

  def test_zrevrangebyscore_basic
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.zrevrangebyscore("zset", "+inf", "-inf")
  end

  def test_zrevrangebyscore_with_scores_and_limit
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.zrevrangebyscore("zset", "+inf", "-inf", withscores: true, limit: [0, 5])
  end

  def test_zincrby
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.zincrby("zset", 1.5, "member")

    assert_instance_of Redis::Future, future
  end

  def test_info_with_section
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.info("server")

    assert_instance_of Redis::Future, future
  end

  def test_info_without_section
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.info

    assert_instance_of Redis::Future, future
  end

  def test_config_get
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.config("get", "maxmemory")

    assert_instance_of Redis::Future, future
  end

  def test_config_set
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.config("set", "maxmemory", "100mb")

    assert_instance_of Redis::Future, future
  end

  # ---------- multi inside pipeline ----------

  def test_multi_inside_pipeline
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    exec_future = pc.multi do |tx|
      tx.set("k", "v")
      tx.get("k")
    end

    assert_instance_of Redis::Future, exec_future
    # exec_future should have @inner_futures set
    assert exec_future.instance_variable_defined?(:@inner_futures)
  end

  def test_multi_without_block
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    exec_future = pc.multi

    assert_instance_of Redis::Future, exec_future
  end

  # ---------- nested pipelining ----------

  def test_pipelined_yields_self
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    yielded = nil
    pc.pipelined { |p| yielded = p }

    assert_same pc, yielded
  end

  def test_pipelined_without_block
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.pipelined # Should not raise
  end

  # ---------- method_missing / respond_to_missing? ----------

  def test_method_missing_delegates_to_call
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.custom_command("arg1")

    assert_instance_of Redis::Future, future
  end

  def test_respond_to_missing_returns_true
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)

    assert_respond_to pc, :any_arbitrary_method
  end

  # ---------- transform_zpop_result branches ----------

  def test_transform_zpop_result_nil
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.zpopmin("zset")
    future._set_value(nil)
    result = future.value

    assert_nil result
  end

  def test_transform_zpop_result_empty_array
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.zpopmin("zset")
    future._set_value([])
    result = future.value

    assert_nil result
  end

  def test_transform_zpop_result_flat_pair
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.zpopmin("zset")
    future._set_value(["member", "1.5"])
    result = future.value

    assert_equal ["member", 1.5], result
  end

  def test_transform_zpop_result_nested_pair
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.zpopmin("zset")
    future._set_value([["member", "2.0"]])
    result = future.value

    assert_equal ["member", 2.0], result
  end

  def test_transform_zpop_result_with_count
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.zpopmin("zset", 2)
    future._set_value([["m1", "1.0"], ["m2", "2.0"]])
    result = future.value

    assert_equal [["m1", 1.0], ["m2", 2.0]], result
  end

  def test_transform_zpop_result_other_format
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.zpopmin("zset")
    future._set_value("unexpected")
    result = future.value

    assert_equal "unexpected", result
  end

  # ---------- parse_score branches ----------

  def test_parse_score_nil
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.zincrby("zset", 1, "member")
    future._set_value(nil)
    result = future.value

    assert_nil result
  end

  def test_parse_score_float
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.zincrby("zset", 1, "member")
    future._set_value(3.14)
    result = future.value

    assert_in_delta(3.14, result)
  end

  def test_parse_score_inf
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.zincrby("zset", 1, "member")
    future._set_value("inf")
    result = future.value

    assert_equal Float::INFINITY, result
  end

  def test_parse_score_positive_inf
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.zincrby("zset", 1, "member")
    future._set_value("+inf")
    result = future.value

    assert_equal Float::INFINITY, result
  end

  def test_parse_score_negative_inf
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.zincrby("zset", 1, "member")
    future._set_value("-inf")
    result = future.value

    assert_equal(-Float::INFINITY, result)
  end

  def test_parse_score_string_number
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.zincrby("zset", 1, "member")
    future._set_value("42.5")
    result = future.value

    assert_in_delta(42.5, result)
  end

  # ---------- parse_info branches ----------

  def test_parse_info_non_string
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.info
    future._set_value(42)
    result = future.value

    assert_equal 42, result
  end

  def test_parse_info_string
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.info
    future._set_value("# Server\nredis_version:7.0.0\nused_memory:1024\n\n# Comment\n")
    result = future.value

    assert_instance_of Hash, result
    assert_equal "7.0.0", result["redis_version"]
    assert_equal "1024", result["used_memory"]
  end

  # ---------- select / keys ----------

  def test_select
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.select(5)

    assert_instance_of Redis::Future, future
  end

  def test_keys_default_pattern
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.keys

    assert_instance_of Redis::Future, future
  end

  def test_keys_custom_pattern
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.keys("user:*")

    assert_instance_of Redis::Future, future
  end

  # ---------- Additional hash commands ----------

  def test_mapped_hmget
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.mapped_hmget("h", "f1", "f2")

    assert_instance_of Redis::Future, future
  end

  def test_hsetnx
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.hsetnx("h", "f", "v")

    assert_instance_of Redis::Future, future
  end

  def test_hmget
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.hmget("h", "f1", "f2")

    assert_instance_of Redis::Future, future
  end

  def test_hmset
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.hmset("h", "f", "v")

    assert_instance_of Redis::Future, future
  end

  def test_hexists
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.hexists("h", "f")

    assert_instance_of Redis::Future, future
  end

  # ---------- Additional set commands ----------

  def test_sismember
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.sismember("s", "m")

    assert_instance_of Redis::Future, future
  end

  def test_smembers
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.smembers("s")

    assert_instance_of Redis::Future, future
  end

  def test_scard
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.scard("s")

    assert_instance_of Redis::Future, future
  end

  def test_spop_without_count
    @mock_pipeline.expects(:call_1arg).with("SPOP", "s")
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.spop("s")
  end

  def test_spop_with_count
    @mock_pipeline.expects(:call_2args).with("SPOP", "s", 3)
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.spop("s", 3)
  end

  def test_srandmember_without_count
    @mock_pipeline.expects(:call_1arg).with("SRANDMEMBER", "s")
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.srandmember("s")
  end

  def test_srandmember_with_count
    @mock_pipeline.expects(:call_2args).with("SRANDMEMBER", "s", 5)
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    pc.srandmember("s", 5)
  end

  # ---------- Expire-related commands ----------

  def test_expire
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.expire("k", 100)

    assert_instance_of Redis::Future, future
  end

  def test_pexpire
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.pexpire("k", 5000)

    assert_instance_of Redis::Future, future
  end

  def test_ttl
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.ttl("k")

    assert_instance_of Redis::Future, future
  end

  def test_pttl
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.pttl("k")

    assert_instance_of Redis::Future, future
  end

  def test_persist
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.persist("k")

    assert_instance_of Redis::Future, future
  end

  def test_type
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.type("k")

    assert_instance_of Redis::Future, future
  end

  def test_rename
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.rename("old", "new")

    assert_instance_of Redis::Future, future
  end

  def test_renamenx
    pc = Redis::PipelinedConnection.new(@mock_client, @mock_pipeline)
    future = pc.renamenx("old", "new")

    assert_instance_of Redis::Future, future
  end
end

# ============================================================================
# MultiConnection Branch Coverage Tests
# ============================================================================
class MultiConnectionBranchTest < Minitest::Test
  def setup
    @mock_transaction = mock("transaction")
    @mock_transaction.stubs(:call).returns("QUEUED")
    @mock_transaction.stubs(:call_1arg).returns("QUEUED")
    @mock_transaction.stubs(:call_2args).returns("QUEUED")
    @mock_transaction.stubs(:call_3args).returns("QUEUED")
  end

  # ---------- call returns Future ----------

  def test_call_returns_future
    mc = Redis::MultiConnection.new(@mock_transaction)
    future = mc.call("SET", "k", "v")

    assert_instance_of Redis::Future, future
    assert_equal %w[SET k v], future.command
  end

  def test_call_1arg_returns_future
    mc = Redis::MultiConnection.new(@mock_transaction)
    future = mc.call_1arg("GET", "k")

    assert_instance_of Redis::Future, future
    assert_equal %w[GET k], future.command
  end

  def test_call_2args_returns_future
    mc = Redis::MultiConnection.new(@mock_transaction)
    future = mc.call_2args("HGET", "h", "f")

    assert_instance_of Redis::Future, future
    assert_equal %w[HGET h f], future.command
  end

  def test_call_3args_returns_future
    mc = Redis::MultiConnection.new(@mock_transaction)
    future = mc.call_3args("HSET", "h", "f", "v")

    assert_instance_of Redis::Future, future
    assert_equal %w[HSET h f v], future.command
  end

  # ---------- _resolve_futures branches ----------

  def test_resolve_futures_sets_values
    mc = Redis::MultiConnection.new(@mock_transaction)
    f1 = mc.call("SET", "k", "v")
    f2 = mc.call_1arg("GET", "k")

    mc._resolve_futures(%w[OK value])

    assert_equal "OK", f1.value
    assert_equal "value", f2.value
  end

  def test_resolve_futures_nil_results
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.call("SET", "k", "v")

    # Should not raise on nil results (aborted transaction)
    mc._resolve_futures(nil)
  end

  def test_resolve_futures_respects_result_length
    mc = Redis::MultiConnection.new(@mock_transaction)
    f1 = mc.call("SET", "k", "v")
    f2 = mc.call("GET", "k")

    # Fewer results than futures
    mc._resolve_futures(["OK"])

    assert_equal "OK", f1.value
    assert_raises(Redis::FutureNotReady) { f2.value }
  end

  # ---------- _futures ----------

  def test_futures_returns_array
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.call("SET", "k", "v")
    mc.call_1arg("GET", "k")

    futures = mc._futures

    assert_instance_of Array, futures
    assert_equal 2, futures.length
  end

  # ---------- Common commands ----------

  def test_ping
    mc = Redis::MultiConnection.new(@mock_transaction)
    future = mc.ping

    assert_instance_of Redis::Future, future
  end

  def test_set_simple
    @mock_transaction.expects(:call_2args).with("SET", "k", "v")
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.set("k", "v")
  end

  def test_set_with_options
    @mock_transaction.expects(:call).with("SET", "k", "v", "EX", 100)
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.set("k", "v", ex: 100)
  end

  def test_set_with_all_options
    @mock_transaction.expects(:call).with("SET", "k", "v", "PX", 5000, "NX", "KEEPTTL", "GET")
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.set("k", "v", px: 5000, nx: true, keepttl: true, get: true)
  end

  def test_get
    mc = Redis::MultiConnection.new(@mock_transaction)
    future = mc.get("key")

    assert_instance_of Redis::Future, future
  end

  def test_del_single
    @mock_transaction.expects(:call_1arg).with("DEL", "key")
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.del("key")
  end

  def test_del_multiple
    @mock_transaction.expects(:call).with("DEL", "k1", "k2")
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.del("k1", "k2")
  end

  def test_incr
    mc = Redis::MultiConnection.new(@mock_transaction)
    future = mc.incr("counter")

    assert_instance_of Redis::Future, future
  end

  def test_decr
    mc = Redis::MultiConnection.new(@mock_transaction)
    future = mc.decr("counter")

    assert_instance_of Redis::Future, future
  end

  def test_incrby
    mc = Redis::MultiConnection.new(@mock_transaction)
    future = mc.incrby("counter", 5)

    assert_instance_of Redis::Future, future
  end

  def test_decrby
    mc = Redis::MultiConnection.new(@mock_transaction)
    future = mc.decrby("counter", 3)

    assert_instance_of Redis::Future, future
  end

  def test_incrbyfloat
    mc = Redis::MultiConnection.new(@mock_transaction)
    future = mc.incrbyfloat("counter", 1.5)

    assert_instance_of Redis::Future, future
  end

  def test_hset_2_args
    @mock_transaction.expects(:call_3args).with("HSET", "h", "f", "v")
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.hset("h", "f", "v")
  end

  def test_hset_multiple_args
    @mock_transaction.expects(:call).with("HSET", "h", "f1", "v1", "f2", "v2")
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.hset("h", "f1", "v1", "f2", "v2")
  end

  def test_hget
    mc = Redis::MultiConnection.new(@mock_transaction)
    future = mc.hget("h", "f")

    assert_instance_of Redis::Future, future
  end

  def test_hgetall
    mc = Redis::MultiConnection.new(@mock_transaction)
    future = mc.hgetall("myhash")

    assert_instance_of Redis::Future, future
  end

  def test_hdel_single
    @mock_transaction.expects(:call_2args).with("HDEL", "h", "f")
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.hdel("h", "f")
  end

  def test_hdel_multiple
    @mock_transaction.expects(:call).with("HDEL", "h", "f1", "f2")
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.hdel("h", "f1", "f2")
  end

  def test_sadd_single
    @mock_transaction.expects(:call_2args).with("SADD", "s", "m")
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.sadd("s", "m")
  end

  def test_sadd_multiple
    @mock_transaction.expects(:call).with("SADD", "s", "m1", "m2")
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.sadd("s", "m1", "m2")
  end

  def test_sadd_boolean
    mc = Redis::MultiConnection.new(@mock_transaction)
    future = mc.sadd?("s", "m")

    assert_instance_of Redis::Future, future
  end

  def test_srem_single
    @mock_transaction.expects(:call_2args).with("SREM", "s", "m")
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.srem("s", "m")
  end

  def test_srem_multiple
    @mock_transaction.expects(:call).with("SREM", "s", "m1", "m2")
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.srem("s", "m1", "m2")
  end

  def test_srem_boolean
    mc = Redis::MultiConnection.new(@mock_transaction)
    future = mc.srem?("s", "m")

    assert_instance_of Redis::Future, future
  end

  def test_exists_single
    @mock_transaction.expects(:call_1arg).with("EXISTS", "key")
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.exists("key")
  end

  def test_exists_multiple
    @mock_transaction.expects(:call).with("EXISTS", "k1", "k2")
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.exists("k1", "k2")
  end

  def test_exists_boolean
    mc = Redis::MultiConnection.new(@mock_transaction)
    future = mc.exists?("key")

    assert_instance_of Redis::Future, future
  end

  def test_exists_boolean_multiple
    mc = Redis::MultiConnection.new(@mock_transaction)
    future = mc.exists?("k1", "k2")

    assert_instance_of Redis::Future, future
  end

  def test_lpush
    mc = Redis::MultiConnection.new(@mock_transaction)
    future = mc.lpush("list", "val")

    assert_instance_of Redis::Future, future
  end

  def test_rpush
    mc = Redis::MultiConnection.new(@mock_transaction)
    future = mc.rpush("list", "val")

    assert_instance_of Redis::Future, future
  end

  def test_lpop_without_count
    @mock_transaction.expects(:call_1arg).with("LPOP", "list")
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.lpop("list")
  end

  def test_lpop_with_count
    @mock_transaction.expects(:call_2args).with("LPOP", "list", 3)
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.lpop("list", 3)
  end

  def test_rpop_without_count
    @mock_transaction.expects(:call_1arg).with("RPOP", "list")
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.rpop("list")
  end

  def test_rpop_with_count
    @mock_transaction.expects(:call_2args).with("RPOP", "list", 2)
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.rpop("list", 2)
  end

  def test_zadd_basic
    mc = Redis::MultiConnection.new(@mock_transaction)
    future = mc.zadd("zset", 1.0, "m")

    assert_instance_of Redis::Future, future
  end

  def test_zadd_with_all_flags
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.zadd("zset", 1.0, "m", nx: true, xx: true, gt: true, lt: true, ch: true)
  end

  def test_zrem_single
    @mock_transaction.expects(:call_2args).with("ZREM", "z", "m")
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.zrem("z", "m")
  end

  def test_zrem_multiple
    @mock_transaction.expects(:call).with("ZREM", "z", "m1", "m2")
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.zrem("z", "m1", "m2")
  end

  def test_zrange_without_scores
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.zrange("z", 0, -1)
  end

  def test_zrange_with_scores_via_withscores
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.zrange("z", 0, -1, withscores: true)
  end

  def test_zrange_with_scores_via_with_scores
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.zrange("z", 0, -1, with_scores: true)
  end

  def test_zrevrange_without_scores
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.zrevrange("z", 0, -1)
  end

  def test_zrevrange_with_scores
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.zrevrange("z", 0, -1, withscores: true)
  end

  def test_zrangebyscore_basic
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.zrangebyscore("z", "-inf", "+inf")
  end

  def test_zrangebyscore_with_options
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.zrangebyscore("z", "-inf", "+inf", withscores: true, limit: [0, 10])
  end

  def test_zrangebyscore_with_with_scores
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.zrangebyscore("z", "-inf", "+inf", with_scores: true)
  end

  def test_zrevrangebyscore_basic
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.zrevrangebyscore("z", "+inf", "-inf")
  end

  def test_zrevrangebyscore_with_options
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.zrevrangebyscore("z", "+inf", "-inf", withscores: true, limit: [0, 5])
  end

  def test_zpopmin_without_count
    @mock_transaction.expects(:call_1arg).with("ZPOPMIN", "z")
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.zpopmin("z")
  end

  def test_zpopmin_with_count
    @mock_transaction.expects(:call_2args).with("ZPOPMIN", "z", 3)
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.zpopmin("z", 3)
  end

  def test_zpopmax_without_count
    @mock_transaction.expects(:call_1arg).with("ZPOPMAX", "z")
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.zpopmax("z")
  end

  def test_zpopmax_with_count
    @mock_transaction.expects(:call_2args).with("ZPOPMAX", "z", 2)
    mc = Redis::MultiConnection.new(@mock_transaction)
    mc.zpopmax("z", 2)
  end

  def test_info_with_section
    mc = Redis::MultiConnection.new(@mock_transaction)
    future = mc.info("server")

    assert_instance_of Redis::Future, future
  end

  def test_info_without_section
    mc = Redis::MultiConnection.new(@mock_transaction)
    future = mc.info

    assert_instance_of Redis::Future, future
  end

  def test_method_missing
    mc = Redis::MultiConnection.new(@mock_transaction)
    future = mc.custom_command("arg1")

    assert_instance_of Redis::Future, future
  end

  def test_respond_to_missing
    mc = Redis::MultiConnection.new(@mock_transaction)

    assert_respond_to mc, :anything_at_all
  end

  # ---------- parse_info branches ----------

  def test_parse_info_non_string_pass_through
    mc = Redis::MultiConnection.new(@mock_transaction)
    future = mc.info
    future._set_value(42)
    result = future.value

    assert_equal 42, result
  end

  def test_parse_info_string
    mc = Redis::MultiConnection.new(@mock_transaction)
    future = mc.info
    future._set_value("# Server\nredis_version:7.0.0\nused_memory:1024\n\n")
    result = future.value

    assert_instance_of Hash, result
    assert_equal "7.0.0", result["redis_version"]
  end

  # ---------- Additional commands ----------

  def test_expire
    mc = Redis::MultiConnection.new(@mock_transaction)
    future = mc.expire("k", 100)

    assert_instance_of Redis::Future, future
  end

  def test_ttl
    mc = Redis::MultiConnection.new(@mock_transaction)
    future = mc.ttl("k")

    assert_instance_of Redis::Future, future
  end

  def test_persist
    mc = Redis::MultiConnection.new(@mock_transaction)
    future = mc.persist("k")

    assert_instance_of Redis::Future, future
  end

  def test_type
    mc = Redis::MultiConnection.new(@mock_transaction)
    future = mc.type("k")

    assert_instance_of Redis::Future, future
  end

  def test_rename
    mc = Redis::MultiConnection.new(@mock_transaction)
    future = mc.rename("old", "new")

    assert_instance_of Redis::Future, future
  end

  def test_select
    mc = Redis::MultiConnection.new(@mock_transaction)
    future = mc.select(2)

    assert_instance_of Redis::Future, future
  end

  def test_keys
    mc = Redis::MultiConnection.new(@mock_transaction)
    future = mc.keys("*")

    assert_instance_of Redis::Future, future
  end
end

# ============================================================================
# PipelineMultiWrapper Branch Coverage Tests
# ============================================================================
class PipelineMultiWrapperBranchTest < Minitest::Test
  def setup
    @mock_pipeline = mock("pipeline")
    @mock_pipeline.stubs(:call).returns(nil)
    @mock_pipeline.stubs(:call_1arg).returns(nil)
    @mock_pipeline.stubs(:call_2args).returns(nil)
    @mock_pipeline.stubs(:call_3args).returns(nil)
    @pipeline_futures = []
    @inner_futures = []
  end

  def test_call_creates_queued_and_user_futures
    wrapper = Redis::PipelineMultiWrapper.new(@mock_pipeline, @pipeline_futures, @inner_futures)
    user_future = wrapper.call("SET", "k", "v")

    assert_instance_of Redis::Future, user_future
    assert_equal 1, @pipeline_futures.length
    assert_equal 1, @inner_futures.length
  end

  def test_call_1arg_creates_both_futures
    wrapper = Redis::PipelineMultiWrapper.new(@mock_pipeline, @pipeline_futures, @inner_futures)
    user_future = wrapper.call_1arg("GET", "k")

    assert_instance_of Redis::Future, user_future
    assert_equal 1, @pipeline_futures.length
    assert_equal 1, @inner_futures.length
    assert_equal %w[GET k], user_future.command
  end

  def test_call_2args_creates_both_futures
    wrapper = Redis::PipelineMultiWrapper.new(@mock_pipeline, @pipeline_futures, @inner_futures)
    user_future = wrapper.call_2args("SET", "k", "v")

    assert_instance_of Redis::Future, user_future
    assert_equal 1, @pipeline_futures.length
    assert_equal 1, @inner_futures.length
    assert_equal %w[SET k v], user_future.command
  end

  def test_call_3args_creates_both_futures
    wrapper = Redis::PipelineMultiWrapper.new(@mock_pipeline, @pipeline_futures, @inner_futures)
    user_future = wrapper.call_3args("HSET", "h", "f", "v")

    assert_instance_of Redis::Future, user_future
    assert_equal 1, @pipeline_futures.length
    assert_equal 1, @inner_futures.length
    assert_equal %w[HSET h f v], user_future.command
  end

  # ---------- Command shortcuts ----------

  def test_set_simple
    wrapper = Redis::PipelineMultiWrapper.new(@mock_pipeline, @pipeline_futures, @inner_futures)
    @mock_pipeline.expects(:call_2args).with("SET", "k", "v")
    wrapper.set("k", "v")
  end

  def test_set_with_options
    wrapper = Redis::PipelineMultiWrapper.new(@mock_pipeline, @pipeline_futures, @inner_futures)
    @mock_pipeline.expects(:call).with("SET", "k", "v", "EX", 100)
    wrapper.set("k", "v", ex: 100)
  end

  def test_set_with_px
    wrapper = Redis::PipelineMultiWrapper.new(@mock_pipeline, @pipeline_futures, @inner_futures)
    wrapper.set("k", "v", px: 5000)
  end

  def test_set_with_exat
    wrapper = Redis::PipelineMultiWrapper.new(@mock_pipeline, @pipeline_futures, @inner_futures)
    wrapper.set("k", "v", exat: 1_700_000_000)
  end

  def test_set_with_pxat
    wrapper = Redis::PipelineMultiWrapper.new(@mock_pipeline, @pipeline_futures, @inner_futures)
    wrapper.set("k", "v", pxat: 1_700_000_000_000)
  end

  def test_set_with_nx
    wrapper = Redis::PipelineMultiWrapper.new(@mock_pipeline, @pipeline_futures, @inner_futures)
    wrapper.set("k", "v", nx: true)
  end

  def test_set_with_xx
    wrapper = Redis::PipelineMultiWrapper.new(@mock_pipeline, @pipeline_futures, @inner_futures)
    wrapper.set("k", "v", xx: true)
  end

  def test_set_with_keepttl
    wrapper = Redis::PipelineMultiWrapper.new(@mock_pipeline, @pipeline_futures, @inner_futures)
    wrapper.set("k", "v", keepttl: true)
  end

  def test_set_with_get
    wrapper = Redis::PipelineMultiWrapper.new(@mock_pipeline, @pipeline_futures, @inner_futures)
    wrapper.set("k", "v", get: true)
  end

  def test_get
    wrapper = Redis::PipelineMultiWrapper.new(@mock_pipeline, @pipeline_futures, @inner_futures)
    future = wrapper.get("k")

    assert_instance_of Redis::Future, future
  end

  def test_del_single
    wrapper = Redis::PipelineMultiWrapper.new(@mock_pipeline, @pipeline_futures, @inner_futures)
    @mock_pipeline.expects(:call_1arg).with("DEL", "k")
    wrapper.del("k")
  end

  def test_del_multiple
    wrapper = Redis::PipelineMultiWrapper.new(@mock_pipeline, @pipeline_futures, @inner_futures)
    @mock_pipeline.expects(:call).with("DEL", "k1", "k2")
    wrapper.del("k1", "k2")
  end

  def test_incr
    wrapper = Redis::PipelineMultiWrapper.new(@mock_pipeline, @pipeline_futures, @inner_futures)
    future = wrapper.incr("counter")

    assert_instance_of Redis::Future, future
  end

  def test_decr
    wrapper = Redis::PipelineMultiWrapper.new(@mock_pipeline, @pipeline_futures, @inner_futures)
    future = wrapper.decr("counter")

    assert_instance_of Redis::Future, future
  end

  def test_lpush
    wrapper = Redis::PipelineMultiWrapper.new(@mock_pipeline, @pipeline_futures, @inner_futures)
    wrapper.lpush("list", "v1", "v2")
  end

  def test_rpush
    wrapper = Redis::PipelineMultiWrapper.new(@mock_pipeline, @pipeline_futures, @inner_futures)
    wrapper.rpush("list", "v1")
  end

  def test_sadd_single
    wrapper = Redis::PipelineMultiWrapper.new(@mock_pipeline, @pipeline_futures, @inner_futures)
    @mock_pipeline.expects(:call_2args).with("SADD", "s", "m")
    wrapper.sadd("s", "m")
  end

  def test_sadd_multiple
    wrapper = Redis::PipelineMultiWrapper.new(@mock_pipeline, @pipeline_futures, @inner_futures)
    @mock_pipeline.expects(:call).with("SADD", "s", "m1", "m2")
    wrapper.sadd("s", "m1", "m2")
  end

  def test_hset_2_fields
    wrapper = Redis::PipelineMultiWrapper.new(@mock_pipeline, @pipeline_futures, @inner_futures)
    @mock_pipeline.expects(:call_3args).with("HSET", "h", "f", "v")
    wrapper.hset("h", "f", "v")
  end

  def test_hset_multiple_fields
    wrapper = Redis::PipelineMultiWrapper.new(@mock_pipeline, @pipeline_futures, @inner_futures)
    @mock_pipeline.expects(:call).with("HSET", "h", "f1", "v1", "f2", "v2")
    wrapper.hset("h", "f1", "v1", "f2", "v2")
  end

  def test_hget
    wrapper = Redis::PipelineMultiWrapper.new(@mock_pipeline, @pipeline_futures, @inner_futures)
    future = wrapper.hget("h", "f")

    assert_instance_of Redis::Future, future
  end

  def test_hgetall
    wrapper = Redis::PipelineMultiWrapper.new(@mock_pipeline, @pipeline_futures, @inner_futures)
    future = wrapper.hgetall("h")

    assert_instance_of Redis::Future, future
  end

  def test_hmset
    wrapper = Redis::PipelineMultiWrapper.new(@mock_pipeline, @pipeline_futures, @inner_futures)
    wrapper.hmset("h", "f1", "v1", "f2", "v2")
  end

  def test_method_missing
    wrapper = Redis::PipelineMultiWrapper.new(@mock_pipeline, @pipeline_futures, @inner_futures)
    future = wrapper.custom_command("arg")

    assert_instance_of Redis::Future, future
  end

  def test_respond_to_missing
    wrapper = Redis::PipelineMultiWrapper.new(@mock_pipeline, @pipeline_futures, @inner_futures)

    assert_respond_to wrapper, :anything
  end
end
