# frozen_string_literal: true

require_relative "unit_test_helper"

class TransactionUnitTest < Minitest::Test
  # ============================================================
  # Helper: mock connection that records calls
  # ============================================================

  class MockConnection
    attr_reader :calls

    def initialize
      @calls = []
    end

    def call(*args)
      @calls << args
      case args[0]
      when "MULTI" then "OK"
      when "EXEC" then @calls.select { |c| c[0] != "MULTI" && c[0] != "EXEC" }.map { "OK" }
      else "QUEUED"
      end
    end
  end

  # ============================================================
  # Initialization
  # ============================================================

  def test_transaction_initializes_with_connection
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    assert_instance_of RedisRuby::Transaction, tx
  end

  def test_transaction_starts_empty
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    assert tx.empty?
    assert_equal 0, tx.size
  end

  # ============================================================
  # call - queuing commands
  # ============================================================

  def test_call_returns_queued
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    result = tx.call("SET", "key", "value")
    assert_equal "QUEUED", result
  end

  def test_call_queues_commands
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    tx.call("SET", "key1", "value1")
    tx.call("GET", "key1")
    assert_equal 2, tx.size
  end

  # ============================================================
  # call_1arg, call_2args, call_3args
  # ============================================================

  def test_call_1arg_returns_queued
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    result = tx.call_1arg("GET", "key")
    assert_equal "QUEUED", result
    assert_equal 1, tx.size
  end

  def test_call_2args_returns_queued
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    result = tx.call_2args("HGET", "hash", "field")
    assert_equal "QUEUED", result
    assert_equal 1, tx.size
  end

  def test_call_3args_returns_queued
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    result = tx.call_3args("HSET", "hash", "field", "value")
    assert_equal "QUEUED", result
    assert_equal 1, tx.size
  end

  # ============================================================
  # size / length / empty?
  # ============================================================

  def test_size_and_length_are_aliases
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    assert_equal tx.size, tx.length
    tx.call("SET", "k", "v")
    assert_equal tx.size, tx.length
    assert_equal 1, tx.size
  end

  def test_empty_is_true_when_no_commands
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    assert tx.empty?
  end

  def test_empty_is_false_after_queueing
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    tx.call("SET", "k", "v")
    refute tx.empty?
  end

  # ============================================================
  # execute
  # ============================================================

  def test_execute_sends_multi_commands_exec
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    tx.call("SET", "key1", "value1")
    tx.call("GET", "key1")
    tx.execute

    # Should have called MULTI, SET, GET, EXEC
    assert_equal ["MULTI"], conn.calls[0]
    assert_equal ["SET", "key1", "value1"], conn.calls[1]
    assert_equal ["GET", "key1"], conn.calls[2]
    assert_equal ["EXEC"], conn.calls[3]
  end

  def test_execute_with_no_commands
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    tx.execute

    # Should still send MULTI and EXEC
    assert_equal ["MULTI"], conn.calls[0]
    assert_equal ["EXEC"], conn.calls[1]
  end

  # ============================================================
  # method_missing / respond_to_missing?
  # ============================================================

  def test_method_missing_without_kwargs
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    result = tx.echo("hello")
    assert_equal "QUEUED", result
    assert_equal 1, tx.size
  end

  def test_method_missing_with_kwargs
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    # This should go through the kwargs branch
    result = tx.custom_cmd("arg1", some_opt: "val")
    assert_equal "QUEUED", result
    assert_equal 1, tx.size
  end

  def test_respond_to_missing_returns_true
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    assert tx.respond_to?(:any_arbitrary_method)
  end

  def test_respond_to_missing_with_include_private
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    assert tx.respond_to?(:some_method, true)
  end

  # ============================================================
  # Override commands: ping, hgetall, zscore, zmscore
  # ============================================================

  def test_ping_queues_ping_command
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    result = tx.ping
    assert_equal "QUEUED", result
  end

  def test_hgetall_queues_hgetall_command
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    result = tx.hgetall("myhash")
    assert_equal "QUEUED", result
  end

  def test_zscore_queues_zscore_command
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    result = tx.zscore("zset", "member")
    assert_equal "QUEUED", result
  end

  def test_zmscore_queues_zmscore_command
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    result = tx.zmscore("zset", "m1", "m2")
    assert_equal "QUEUED", result
  end

  # ============================================================
  # zrange branches
  # ============================================================

  def test_zrange_without_scores
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    tx.zrange("zset", 0, -1)
    tx.execute
    assert_equal ["ZRANGE", "zset", 0, -1], conn.calls[1]
  end

  def test_zrange_with_withscores_true
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    tx.zrange("zset", 0, -1, withscores: true)
    tx.execute
    assert_equal ["ZRANGE", "zset", 0, -1, "WITHSCORES"], conn.calls[1]
  end

  def test_zrange_with_with_scores_true
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    tx.zrange("zset", 0, -1, with_scores: true)
    tx.execute
    assert_equal ["ZRANGE", "zset", 0, -1, "WITHSCORES"], conn.calls[1]
  end

  # ============================================================
  # zrevrange branches
  # ============================================================

  def test_zrevrange_without_scores
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    tx.zrevrange("zset", 0, -1)
    tx.execute
    assert_equal ["ZREVRANGE", "zset", 0, -1], conn.calls[1]
  end

  def test_zrevrange_with_withscores_true
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    tx.zrevrange("zset", 0, -1, withscores: true)
    tx.execute
    assert_equal ["ZREVRANGE", "zset", 0, -1, "WITHSCORES"], conn.calls[1]
  end

  def test_zrevrange_with_with_scores_true
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    tx.zrevrange("zset", 0, -1, with_scores: true)
    tx.execute
    assert_equal ["ZREVRANGE", "zset", 0, -1, "WITHSCORES"], conn.calls[1]
  end

  # ============================================================
  # zrangebyscore branches
  # ============================================================

  def test_zrangebyscore_without_options
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    tx.zrangebyscore("zset", "-inf", "+inf")
    tx.execute
    assert_equal ["ZRANGEBYSCORE", "zset", "-inf", "+inf"], conn.calls[1]
  end

  def test_zrangebyscore_with_withscores
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    tx.zrangebyscore("zset", "-inf", "+inf", withscores: true)
    tx.execute
    assert_includes conn.calls[1], "WITHSCORES"
  end

  def test_zrangebyscore_with_with_scores
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    tx.zrangebyscore("zset", "-inf", "+inf", with_scores: true)
    tx.execute
    assert_includes conn.calls[1], "WITHSCORES"
  end

  def test_zrangebyscore_with_limit
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    tx.zrangebyscore("zset", "-inf", "+inf", limit: [0, 10])
    tx.execute
    assert_includes conn.calls[1], "LIMIT"
    assert_includes conn.calls[1], 0
    assert_includes conn.calls[1], 10
  end

  def test_zrangebyscore_with_withscores_and_limit
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    tx.zrangebyscore("zset", "-inf", "+inf", withscores: true, limit: [0, 5])
    tx.execute
    assert_includes conn.calls[1], "WITHSCORES"
    assert_includes conn.calls[1], "LIMIT"
  end

  # ============================================================
  # zrevrangebyscore branches
  # ============================================================

  def test_zrevrangebyscore_without_options
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    tx.zrevrangebyscore("zset", "+inf", "-inf")
    tx.execute
    assert_equal ["ZREVRANGEBYSCORE", "zset", "+inf", "-inf"], conn.calls[1]
  end

  def test_zrevrangebyscore_with_withscores
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    tx.zrevrangebyscore("zset", "+inf", "-inf", withscores: true)
    tx.execute
    assert_includes conn.calls[1], "WITHSCORES"
  end

  def test_zrevrangebyscore_with_with_scores
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    tx.zrevrangebyscore("zset", "+inf", "-inf", with_scores: true)
    tx.execute
    assert_includes conn.calls[1], "WITHSCORES"
  end

  def test_zrevrangebyscore_with_limit
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    tx.zrevrangebyscore("zset", "+inf", "-inf", limit: [0, 10])
    tx.execute
    assert_includes conn.calls[1], "LIMIT"
  end

  def test_zrevrangebyscore_with_withscores_and_limit
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    tx.zrevrangebyscore("zset", "+inf", "-inf", withscores: true, limit: [0, 5])
    tx.execute
    assert_includes conn.calls[1], "WITHSCORES"
    assert_includes conn.calls[1], "LIMIT"
  end

  # ============================================================
  # zincrby
  # ============================================================

  def test_zincrby_queues_command
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    result = tx.zincrby("zset", 1.5, "member")
    assert_equal "QUEUED", result
  end

  # ============================================================
  # zpopmin / zpopmax branches
  # ============================================================

  def test_zpopmin_without_count
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    tx.zpopmin("zset")
    tx.execute
    assert_equal ["ZPOPMIN", "zset"], conn.calls[1]
  end

  def test_zpopmin_with_count
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    tx.zpopmin("zset", 3)
    tx.execute
    assert_equal ["ZPOPMIN", "zset", 3], conn.calls[1]
  end

  def test_zpopmax_without_count
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    tx.zpopmax("zset")
    tx.execute
    assert_equal ["ZPOPMAX", "zset"], conn.calls[1]
  end

  def test_zpopmax_with_count
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    tx.zpopmax("zset", 2)
    tx.execute
    assert_equal ["ZPOPMAX", "zset", 2], conn.calls[1]
  end

  # ============================================================
  # zscan branches
  # ============================================================

  def test_zscan_without_options
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    tx.zscan("zset", "0")
    tx.execute
    assert_equal ["ZSCAN", "zset", "0"], conn.calls[1]
  end

  def test_zscan_with_match
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    tx.zscan("zset", "0", match: "foo*")
    tx.execute
    assert_includes conn.calls[1], "MATCH"
    assert_includes conn.calls[1], "foo*"
  end

  def test_zscan_with_count
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    tx.zscan("zset", "0", count: 100)
    tx.execute
    assert_includes conn.calls[1], "COUNT"
    assert_includes conn.calls[1], 100
  end

  def test_zscan_with_match_and_count
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    tx.zscan("zset", "0", match: "bar*", count: 50)
    tx.execute
    assert_includes conn.calls[1], "MATCH"
    assert_includes conn.calls[1], "COUNT"
  end

  # ============================================================
  # Convenience methods: sadd?, srem?, exists?, sismember?
  # ============================================================

  def test_sadd_question_flattens_members
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    result = tx.sadd?("myset", "m1", "m2")
    assert_equal "QUEUED", result
  end

  def test_srem_question_flattens_members
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    result = tx.srem?("myset", "m1", "m2")
    assert_equal "QUEUED", result
  end

  def test_exists_question_flattens_keys
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    result = tx.exists?("key1", "key2")
    assert_equal "QUEUED", result
  end

  def test_sismember_question
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    result = tx.sismember?("myset", "member")
    assert_equal "QUEUED", result
  end

  # ============================================================
  # info branches
  # ============================================================

  def test_info_with_section
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    tx.info("server")
    tx.execute
    assert_equal ["INFO", "server"], conn.calls[1]
  end

  def test_info_without_section
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    tx.info
    tx.execute
    assert_equal ["INFO"], conn.calls[1]
  end

  # ============================================================
  # mapped_mget / mapped_hmget
  # ============================================================

  def test_mapped_mget_flattens_keys
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    result = tx.mapped_mget("k1", "k2")
    assert_equal "QUEUED", result
  end

  def test_mapped_hmget_flattens_fields
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    result = tx.mapped_hmget("myhash", "f1", "f2")
    assert_equal "QUEUED", result
  end

  # ============================================================
  # Commands from included modules (via method_missing or direct)
  # ============================================================

  def test_set_command_in_transaction
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    result = tx.set("key", "value")
    assert_equal "QUEUED", result
  end

  def test_get_command_in_transaction
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    result = tx.get("key")
    assert_equal "QUEUED", result
  end

  def test_del_command_in_transaction
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    result = tx.del("key")
    assert_equal "QUEUED", result
  end

  def test_incr_command_in_transaction
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    result = tx.incr("counter")
    assert_equal "QUEUED", result
  end

  def test_multiple_commands_queued_in_order
    conn = MockConnection.new
    tx = RedisRuby::Transaction.new(conn)
    tx.call("SET", "k1", "v1")
    tx.call("SET", "k2", "v2")
    tx.call("GET", "k1")
    tx.call("DEL", "k2")
    assert_equal 4, tx.size
    tx.execute
    # Verify order: MULTI, SET, SET, GET, DEL, EXEC
    assert_equal 6, conn.calls.size
    assert_equal ["MULTI"], conn.calls[0]
    assert_equal ["EXEC"], conn.calls[5]
  end

  # ============================================================
  # Client-level multi/watch/discard/unwatch
  # ============================================================

  def test_client_responds_to_multi
    client = RedisRuby::Client.new
    assert_respond_to client, :multi
  end

  def test_client_responds_to_watch
    client = RedisRuby::Client.new
    assert_respond_to client, :watch
  end

  def test_client_responds_to_unwatch
    client = RedisRuby::Client.new
    assert_respond_to client, :unwatch
  end

  def test_client_responds_to_discard
    client = RedisRuby::Client.new
    assert_respond_to client, :discard
  end
end
