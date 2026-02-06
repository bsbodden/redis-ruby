# frozen_string_literal: true

require_relative "unit_test_helper"

# Load compat modules
require_relative "../../lib/redis/commands"

# MockClient that includes all Redis compat command modules
class RedisCompatMockClient
  include Redis::Commands

  attr_accessor :call_results

  def initialize
    @call_results = {}
  end

  # Stub methods that the compat modules delegate to

  def zincrby(_key, _increment, _member)
    @call_results[:zincrby]
  end

  def zmscore(_key, *_members)
    @call_results[:zmscore]
  end

  def zscan_iter(key, match: "*", count: 10)
    @call_results[:zscan_iter] || Enumerator.new { |y| y << ["member", 1.0] }
  end

  def exists(*_keys)
    @call_results[:exists]
  end

  def scan_iter(match: "*", count: 10, type: nil)
    @call_results[:scan_iter] || Enumerator.new { |y| y << "key1" }
  end

  def expire(_key, _seconds)
    @call_results[:expire]
  end

  def expireat(_key, _timestamp)
    @call_results[:expireat]
  end

  def persist(_key)
    @call_results[:persist]
  end

  def renamenx(_old, _new)
    @call_results[:renamenx]
  end

  def hmget(_key, *_fields)
    @call_results[:hmget]
  end

  def hmset(_key, *_args)
    @call_results[:hmset]
  end

  def hsetnx(_key, _field, _value)
    @call_results[:hsetnx]
  end

  def hincrbyfloat(_key, _field, _increment)
    @call_results[:hincrbyfloat]
  end

  def hscan_iter(key, match: "*", count: 10)
    @call_results[:hscan_iter] || Enumerator.new { |y| y << ["field", "val"] }
  end

  def sscan_iter(key, match: "*", count: 10)
    @call_results[:sscan_iter] || Enumerator.new { |y| y << "member1" }
  end

  def mget(*_keys)
    @call_results[:mget]
  end

  def mset(*_args)
    @call_results[:mset]
  end

  def msetnx(*_args)
    @call_results[:msetnx]
  end

  def sadd(_key, *_members)
    @call_results[:sadd]
  end

  def srem(_key, *_members)
    @call_results[:srem]
  end

  def sismember(_key, _member)
    @call_results[:sismember]
  end

  def smove(_src, _dst, _member)
    @call_results[:smove]
  end
end

class RedisCommandsCompatSortedSetsTest < Minitest::Test
  def setup
    @client = RedisCompatMockClient.new
  end

  # ============================================================
  # zincrby_compat
  # ============================================================

  def test_zincrby_compat_returns_float_from_string
    @client.call_results[:zincrby] = "3.14"
    result = @client.zincrby_compat("zset", 1.0, "member")
    assert_equal 3.14, result
  end

  def test_zincrby_compat_returns_float_as_is
    @client.call_results[:zincrby] = 3.14
    result = @client.zincrby_compat("zset", 1.0, "member")
    assert_equal 3.14, result
  end

  # ============================================================
  # zmscore_compat
  # ============================================================

  def test_zmscore_compat_converts_to_float
    @client.call_results[:zmscore] = ["1.0", "2.5", nil]
    result = @client.zmscore_compat("zset", "a", "b", "c")
    assert_equal [1.0, 2.5, nil], result
  end

  def test_zmscore_compat_empty
    @client.call_results[:zmscore] = []
    result = @client.zmscore_compat("zset")
    assert_equal [], result
  end

  # ============================================================
  # zscan_each
  # ============================================================

  def test_zscan_each_with_block
    yielded = []
    @client.call_results[:zscan_iter] = Enumerator.new { |y| y << ["m1", 1.0]; y << ["m2", 2.0] }
    @client.zscan_each("zset") { |pair| yielded << pair }
    assert_equal [["m1", 1.0], ["m2", 2.0]], yielded
  end

  def test_zscan_each_without_block
    @client.call_results[:zscan_iter] = Enumerator.new { |y| y << ["m1", 1.0] }
    result = @client.zscan_each("zset")
    assert_kind_of Enumerator, result
  end
end

class RedisCommandsCompatKeysTest < Minitest::Test
  def setup
    @client = RedisCompatMockClient.new
  end

  # ============================================================
  # exists?
  # ============================================================

  def test_exists_single_key_true
    @client.call_results[:exists] = 1
    assert @client.exists?("key1")
  end

  def test_exists_single_key_false
    @client.call_results[:exists] = 0
    refute @client.exists?("key1")
  end

  def test_exists_multiple_keys
    @client.call_results[:exists] = 2
    result = @client.exists?("key1", "key2")
    assert_equal 2, result
  end

  # ============================================================
  # scan_each
  # ============================================================

  def test_scan_each_with_block
    yielded = []
    @client.call_results[:scan_iter] = Enumerator.new { |y| y << "k1"; y << "k2" }
    @client.scan_each { |k| yielded << k }
    assert_equal ["k1", "k2"], yielded
  end

  def test_scan_each_without_block
    result = @client.scan_each
    assert_kind_of Enumerator, result
  end

  # ============================================================
  # expire?, expireat?, persist?, renamenx?
  # ============================================================

  def test_expire_true
    @client.call_results[:expire] = 1
    assert @client.expire?("key", 60)
  end

  def test_expire_false
    @client.call_results[:expire] = 0
    refute @client.expire?("key", 60)
  end

  def test_expireat_true
    @client.call_results[:expireat] = 1
    assert @client.expireat?("key", 1_700_000_000)
  end

  def test_expireat_false
    @client.call_results[:expireat] = 0
    refute @client.expireat?("key", 1_700_000_000)
  end

  def test_persist_true
    @client.call_results[:persist] = 1
    assert @client.persist?("key")
  end

  def test_persist_false
    @client.call_results[:persist] = 0
    refute @client.persist?("key")
  end

  def test_renamenx_true
    @client.call_results[:renamenx] = 1
    assert @client.renamenx?("old", "new")
  end

  def test_renamenx_false
    @client.call_results[:renamenx] = 0
    refute @client.renamenx?("old", "new")
  end
end

class RedisCommandsCompatHashesTest < Minitest::Test
  def setup
    @client = RedisCompatMockClient.new
  end

  # ============================================================
  # mapped_hmget
  # ============================================================

  def test_mapped_hmget
    @client.call_results[:hmget] = ["val1", "val2"]
    result = @client.mapped_hmget("hash", "f1", "f2")
    assert_equal({ "f1" => "val1", "f2" => "val2" }, result)
  end

  def test_mapped_hmget_with_nils
    @client.call_results[:hmget] = ["val1", nil]
    result = @client.mapped_hmget("hash", "f1", "f2")
    assert_equal({ "f1" => "val1", "f2" => nil }, result)
  end

  # ============================================================
  # mapped_hmset
  # ============================================================

  def test_mapped_hmset
    @client.call_results[:hmset] = "OK"
    result = @client.mapped_hmset("hash", { f1: "v1", f2: "v2" })
    assert_equal "OK", result
  end

  # ============================================================
  # hsetnx?
  # ============================================================

  def test_hsetnx_true
    @client.call_results[:hsetnx] = 1
    assert @client.hsetnx?("hash", "field", "value")
  end

  def test_hsetnx_false
    @client.call_results[:hsetnx] = 0
    refute @client.hsetnx?("hash", "field", "value")
  end

  # ============================================================
  # hincrbyfloat_compat
  # ============================================================

  def test_hincrbyfloat_compat_string_result
    @client.call_results[:hincrbyfloat] = "3.14"
    result = @client.hincrbyfloat_compat("hash", "field", 1.0)
    assert_equal 3.14, result
  end

  def test_hincrbyfloat_compat_float_result
    @client.call_results[:hincrbyfloat] = 3.14
    result = @client.hincrbyfloat_compat("hash", "field", 1.0)
    assert_equal 3.14, result
  end
end

class RedisCommandsCompatMainTest < Minitest::Test
  def setup
    @client = RedisCompatMockClient.new
  end

  # ============================================================
  # hscan_each
  # ============================================================

  def test_hscan_each_with_block
    yielded = []
    @client.call_results[:hscan_iter] = Enumerator.new { |y| y << ["f1", "v1"]; y << ["f2", "v2"] }
    @client.hscan_each("hash") { |pair| yielded << pair }
    assert_equal [["f1", "v1"], ["f2", "v2"]], yielded
  end

  def test_hscan_each_without_block
    result = @client.hscan_each("hash")
    assert_kind_of Enumerator, result
  end

  # ============================================================
  # sscan_each
  # ============================================================

  def test_sscan_each_with_block
    yielded = []
    @client.call_results[:sscan_iter] = Enumerator.new { |y| y << "m1"; y << "m2" }
    @client.sscan_each("set") { |member| yielded << member }
    assert_equal ["m1", "m2"], yielded
  end

  def test_sscan_each_without_block
    result = @client.sscan_each("set")
    assert_kind_of Enumerator, result
  end

  # ============================================================
  # Strings compat: mapped_mget, mapped_mset, mapped_msetnx
  # ============================================================

  def test_mapped_mget
    @client.call_results[:mget] = ["v1", "v2"]
    result = @client.mapped_mget("k1", "k2")
    assert_equal({ "k1" => "v1", "k2" => "v2" }, result)
  end

  def test_mapped_mset
    @client.call_results[:mset] = "OK"
    result = @client.mapped_mset({ k1: "v1", k2: "v2" })
    assert_equal "OK", result
  end

  def test_mapped_msetnx
    @client.call_results[:msetnx] = true
    result = @client.mapped_msetnx({ k1: "v1" })
    assert_equal true, result
  end

  # ============================================================
  # Sets compat: sadd?, srem?, sismember?, smove?
  # ============================================================

  def test_sadd_true
    @client.call_results[:sadd] = 1
    assert @client.sadd?("set", "member")
  end

  def test_sadd_false
    @client.call_results[:sadd] = 0
    refute @client.sadd?("set", "member")
  end

  def test_srem_true
    @client.call_results[:srem] = 1
    assert @client.srem?("set", "member")
  end

  def test_srem_false
    @client.call_results[:srem] = 0
    refute @client.srem?("set", "member")
  end

  def test_sismember_true
    @client.call_results[:sismember] = 1
    assert @client.sismember?("set", "member")
  end

  def test_sismember_false
    @client.call_results[:sismember] = 0
    refute @client.sismember?("set", "member")
  end

  def test_smove_true
    @client.call_results[:smove] = 1
    assert @client.smove?("src", "dst", "member")
  end

  def test_smove_false
    @client.call_results[:smove] = 0
    refute @client.smove?("src", "dst", "member")
  end
end
