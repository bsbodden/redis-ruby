# frozen_string_literal: true

require_relative "../unit_test_helper"

class StringsBranchTest < Minitest::Test
  class MockClient
    include RedisRuby::Commands::Strings
    attr_reader :last_command

    def call(*args)
      @last_command = args
      mock_return(args)
    end

    def call_1arg(cmd, a1)
      @last_command = [cmd, a1]
      mock_return([cmd, a1])
    end

    def call_2args(cmd, a1, a2)
      @last_command = [cmd, a1, a2]
      mock_return([cmd, a1, a2])
    end

    def call_3args(cmd, a1, a2, a3)
      @last_command = [cmd, a1, a2, a3]
      mock_return([cmd, a1, a2, a3])
    end

    private

    def mock_return(args)
      case args[0]
      when "INCRBYFLOAT" then "3.14"
      when "SETNX" then 1
      when "MSETNX" then 1
      when "GET", "GETDEL", "GETSET", "GETEX" then "value"
      when "INCR", "DECR", "INCRBY", "DECRBY", "APPEND", "STRLEN", "SETRANGE" then 42
      when "GETRANGE" then "alu"
      when "MGET" then %w[v1 v2]
      else "OK"
      end
    end
  end

  # MockClient that returns a non-String for INCRBYFLOAT to test the else branch
  class MockClientFloatDirect
    include RedisRuby::Commands::Strings
    attr_reader :last_command

    def call(*args) = (@last_command = args; "OK")
    def call_1arg(cmd, a1) = (@last_command = [cmd, a1]; "OK")

    def call_2args(cmd, a1, a2)
      @last_command = [cmd, a1, a2]
      # Return a Float directly (not a String) to test the else branch of incrbyfloat
      3.14
    end

    def call_3args(cmd, a1, a2, a3) = (@last_command = [cmd, a1, a2, a3]; 1)
  end

  def setup
    @client = MockClient.new
  end

  # ============================================================
  # SET command - fast path (no options)
  # ============================================================

  def test_set_simple_fast_path
    @client.set("mykey", "myval")
    assert_equal ["SET", "mykey", "myval"], @client.last_command
  end

  # ============================================================
  # SET command - slow path with each option individually
  # ============================================================

  def test_set_with_ex
    @client.set("mykey", "myval", ex: 60)
    assert_equal ["SET", "mykey", "myval", "EX", 60], @client.last_command
  end

  def test_set_with_px
    @client.set("mykey", "myval", px: 60000)
    assert_equal ["SET", "mykey", "myval", "PX", 60000], @client.last_command
  end

  def test_set_with_exat
    @client.set("mykey", "myval", exat: 1700000000)
    assert_equal ["SET", "mykey", "myval", "EXAT", 1700000000], @client.last_command
  end

  def test_set_with_pxat
    @client.set("mykey", "myval", pxat: 1700000000000)
    assert_equal ["SET", "mykey", "myval", "PXAT", 1700000000000], @client.last_command
  end

  def test_set_with_nx
    @client.set("mykey", "myval", nx: true)
    assert_equal ["SET", "mykey", "myval", "NX"], @client.last_command
  end

  def test_set_with_xx
    @client.set("mykey", "myval", xx: true)
    assert_equal ["SET", "mykey", "myval", "XX"], @client.last_command
  end

  def test_set_with_keepttl
    @client.set("mykey", "myval", keepttl: true)
    assert_equal ["SET", "mykey", "myval", "KEEPTTL"], @client.last_command
  end

  def test_set_with_get
    @client.set("mykey", "myval", get: true)
    assert_equal ["SET", "mykey", "myval", "GET"], @client.last_command
  end

  # ============================================================
  # SET command - multiple options combined
  # ============================================================

  def test_set_with_ex_and_nx
    @client.set("mykey", "myval", ex: 60, nx: true)
    assert_equal ["SET", "mykey", "myval", "EX", 60, "NX"], @client.last_command
  end

  def test_set_with_px_and_xx
    @client.set("mykey", "myval", px: 60000, xx: true)
    assert_equal ["SET", "mykey", "myval", "PX", 60000, "XX"], @client.last_command
  end

  def test_set_with_exat_and_keepttl_and_get
    @client.set("mykey", "myval", exat: 1700000000, keepttl: true, get: true)
    assert_equal ["SET", "mykey", "myval", "EXAT", 1700000000, "KEEPTTL", "GET"], @client.last_command
  end

  def test_set_all_options
    @client.set("mykey", "myval", ex: 60, px: 1000, exat: 170, pxat: 170000, nx: true, xx: true, keepttl: true,
                                  get: true)
    expected = ["SET", "mykey", "myval", "EX", 60, "PX", 1000, "EXAT", 170, "PXAT", 170000, "NX", "XX", "KEEPTTL",
                "GET"]
    assert_equal expected, @client.last_command
  end

  # ============================================================
  # SET - no-option defaults (false/nil) don't add args
  # ============================================================

  def test_set_with_all_defaults_explicitly_false
    @client.set("mykey", "myval", ex: nil, px: nil, exat: nil, pxat: nil, nx: false, xx: false, keepttl: false,
                                  get: false)
    # Should use fast path
    assert_equal ["SET", "mykey", "myval"], @client.last_command
  end

  # ============================================================
  # GET
  # ============================================================

  def test_get
    result = @client.get("mykey")
    assert_equal ["GET", "mykey"], @client.last_command
    assert_equal "value", result
  end

  # ============================================================
  # INCR / DECR
  # ============================================================

  def test_incr
    result = @client.incr("counter")
    assert_equal ["INCR", "counter"], @client.last_command
    assert_equal 42, result
  end

  def test_decr
    result = @client.decr("counter")
    assert_equal ["DECR", "counter"], @client.last_command
    assert_equal 42, result
  end

  # ============================================================
  # INCRBY / DECRBY
  # ============================================================

  def test_incrby
    result = @client.incrby("counter", 10)
    assert_equal ["INCRBY", "counter", 10], @client.last_command
    assert_equal 42, result
  end

  def test_decrby
    result = @client.decrby("counter", 5)
    assert_equal ["DECRBY", "counter", 5], @client.last_command
    assert_equal 42, result
  end

  # ============================================================
  # INCRBYFLOAT - String result branch
  # ============================================================

  def test_incrbyfloat_string_result
    result = @client.incrbyfloat("counter", 1.5)
    assert_equal ["INCRBYFLOAT", "counter", 1.5], @client.last_command
    assert_in_delta 3.14, result, 0.001
    assert_instance_of Float, result
  end

  # ============================================================
  # INCRBYFLOAT - non-String result branch (already Float)
  # ============================================================

  def test_incrbyfloat_non_string_result
    client = MockClientFloatDirect.new
    result = client.incrbyfloat("counter", 1.5)
    assert_equal ["INCRBYFLOAT", "counter", 1.5], client.last_command
    assert_in_delta 3.14, result, 0.001
  end

  # ============================================================
  # APPEND / STRLEN
  # ============================================================

  def test_append
    result = @client.append("mykey", "extra")
    assert_equal ["APPEND", "mykey", "extra"], @client.last_command
    assert_equal 42, result
  end

  def test_strlen
    result = @client.strlen("mykey")
    assert_equal ["STRLEN", "mykey"], @client.last_command
    assert_equal 42, result
  end

  # ============================================================
  # GETRANGE / SETRANGE
  # ============================================================

  def test_getrange
    result = @client.getrange("mykey", 1, 3)
    assert_equal ["GETRANGE", "mykey", 1, 3], @client.last_command
    assert_equal "alu", result
  end

  def test_setrange
    result = @client.setrange("mykey", 5, "new")
    assert_equal ["SETRANGE", "mykey", 5, "new"], @client.last_command
    assert_equal 42, result
  end

  # ============================================================
  # MGET / MSET / MSETNX
  # ============================================================

  def test_mget
    result = @client.mget("key1", "key2")
    assert_equal ["MGET", "key1", "key2"], @client.last_command
    assert_equal %w[v1 v2], result
  end

  def test_mget_single_key
    @client.mget("key1")
    assert_equal ["MGET", "key1"], @client.last_command
  end

  def test_mset
    @client.mset("k1", "v1", "k2", "v2")
    assert_equal ["MSET", "k1", "v1", "k2", "v2"], @client.last_command
  end

  def test_msetnx
    result = @client.msetnx("k1", "v1", "k2", "v2")
    assert_equal ["MSETNX", "k1", "v1", "k2", "v2"], @client.last_command
    assert_equal 1, result
  end

  # ============================================================
  # SETNX
  # ============================================================

  def test_setnx_returns_true_when_set
    result = @client.setnx("mykey", "myval")
    assert_equal ["SETNX", "mykey", "myval"], @client.last_command
    assert_equal true, result
  end

  def test_setnx_returns_false_when_not_set
    # Create a mock that returns 0 for SETNX
    client = MockClientSetnxFalse.new
    result = client.setnx("mykey", "myval")
    assert_equal false, result
  end

  class MockClientSetnxFalse
    include RedisRuby::Commands::Strings
    def call(*args) = 0
    def call_1arg(cmd, a1) = 0
    def call_2args(cmd, a1, a2) = 0
    def call_3args(cmd, a1, a2, a3) = 0
  end

  # ============================================================
  # SETEX / PSETEX
  # ============================================================

  def test_setex
    result = @client.setex("mykey", 60, "myval")
    assert_equal ["SETEX", "mykey", 60, "myval"], @client.last_command
    assert_equal "OK", result
  end

  def test_psetex
    result = @client.psetex("mykey", 60000, "myval")
    assert_equal ["PSETEX", "mykey", 60000, "myval"], @client.last_command
    assert_equal "OK", result
  end

  # ============================================================
  # GETSET
  # ============================================================

  def test_getset
    result = @client.getset("mykey", "newval")
    assert_equal ["GETSET", "mykey", "newval"], @client.last_command
    assert_equal "value", result
  end

  # ============================================================
  # GETDEL
  # ============================================================

  def test_getdel
    result = @client.getdel("mykey")
    assert_equal ["GETDEL", "mykey"], @client.last_command
    assert_equal "value", result
  end

  # ============================================================
  # GETEX - all option branches
  # ============================================================

  def test_getex_no_options
    result = @client.getex("mykey")
    assert_equal ["GETEX", "mykey"], @client.last_command
    assert_equal "value", result
  end

  def test_getex_with_ex
    @client.getex("mykey", ex: 60)
    assert_equal ["GETEX", "mykey", "EX", 60], @client.last_command
  end

  def test_getex_with_px
    @client.getex("mykey", px: 60000)
    assert_equal ["GETEX", "mykey", "PX", 60000], @client.last_command
  end

  def test_getex_with_exat
    @client.getex("mykey", exat: 1700000000)
    assert_equal ["GETEX", "mykey", "EXAT", 1700000000], @client.last_command
  end

  def test_getex_with_pxat
    @client.getex("mykey", pxat: 1700000000000)
    assert_equal ["GETEX", "mykey", "PXAT", 1700000000000], @client.last_command
  end

  def test_getex_with_persist
    @client.getex("mykey", persist: true)
    assert_equal ["GETEX", "mykey", "PERSIST"], @client.last_command
  end

  def test_getex_persist_false_does_not_add_option
    @client.getex("mykey", persist: false)
    assert_equal ["GETEX", "mykey"], @client.last_command
  end

  def test_getex_multiple_options
    @client.getex("mykey", ex: 60, persist: true)
    assert_equal ["GETEX", "mykey", "EX", 60, "PERSIST"], @client.last_command
  end

  def test_getex_all_expiry_options
    @client.getex("mykey", ex: 60, px: 1000, exat: 170, pxat: 170000, persist: true)
    assert_equal ["GETEX", "mykey", "EX", 60, "PX", 1000, "EXAT", 170, "PXAT", 170000, "PERSIST"],
                 @client.last_command
  end

  # ============================================================
  # SET with nil options explicitly (ensuring no args added)
  # ============================================================

  def test_set_ex_nil_does_not_add
    @client.set("k", "v", ex: nil)
    # nil ex => fast path
    assert_equal ["SET", "k", "v"], @client.last_command
  end

  def test_set_px_nil_does_not_add
    @client.set("k", "v", px: nil)
    assert_equal ["SET", "k", "v"], @client.last_command
  end

  def test_getex_ex_nil_does_not_add
    @client.getex("k", ex: nil)
    assert_equal ["GETEX", "k"], @client.last_command
  end

  def test_getex_px_nil_does_not_add
    @client.getex("k", px: nil)
    assert_equal ["GETEX", "k"], @client.last_command
  end

  def test_getex_exat_nil_does_not_add
    @client.getex("k", exat: nil)
    assert_equal ["GETEX", "k"], @client.last_command
  end

  def test_getex_pxat_nil_does_not_add
    @client.getex("k", pxat: nil)
    assert_equal ["GETEX", "k"], @client.last_command
  end
end
