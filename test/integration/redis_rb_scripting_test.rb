# frozen_string_literal: true

require_relative "../test_helper"
require "redis"

# These tests mirror the redis-rb scripting tests to ensure compatibility
class RedisRbScriptingTest < Minitest::Test
  def setup
    @redis = Redis.new(url: ENV["REDIS_URL"] || "redis://localhost:6379")
    @redis.script(:flush)
    @redis.flushdb
  end

  def teardown
    @redis.flushdb if @redis
  end

  def r
    @redis
  end

  def to_sha(script)
    r.script(:load, script)
  end

  def test_script_exists
    a = to_sha("return 1")
    b = a.succ

    assert_equal true, r.script(:exists, a)
    assert_equal false, r.script(:exists, b)
    assert_equal [true], r.script(:exists, [a])
    assert_equal [false], r.script(:exists, [b])
    assert_equal [true, false], r.script(:exists, [a, b])
  end

  def test_script_flush
    sha = to_sha("return 1")
    assert r.script(:exists, sha)
    assert_equal "OK", r.script(:flush)
    refute r.script(:exists, sha)
  end

  def test_eval_basic
    assert_equal 0, r.eval("return #KEYS")
    assert_equal 0, r.eval("return #ARGV")
  end

  def test_eval_with_keys_and_args
    assert_equal ["k1", "k2"], r.eval("return KEYS", ["k1", "k2"])
    assert_equal ["a1", "a2"], r.eval("return ARGV", [], ["a1", "a2"])
  end

  def test_eval_with_options_hash
    assert_equal 0, r.eval("return #KEYS", {})
    assert_equal 0, r.eval("return #ARGV", {})
    assert_equal ["k1", "k2"], r.eval("return KEYS", keys: ["k1", "k2"])
    assert_equal ["a1", "a2"], r.eval("return ARGV", argv: ["a1", "a2"])
  end

  def test_evalsha
    assert_equal 0, r.evalsha(to_sha("return #KEYS"))
    assert_equal 0, r.evalsha(to_sha("return #ARGV"))
  end

  def test_evalsha_with_keys_and_args
    assert_equal ["k1", "k2"], r.evalsha(to_sha("return KEYS"), ["k1", "k2"])
    assert_equal ["a1", "a2"], r.evalsha(to_sha("return ARGV"), [], ["a1", "a2"])
  end

  def test_evalsha_with_options_hash
    assert_equal 0, r.evalsha(to_sha("return #KEYS"), {})
    assert_equal 0, r.evalsha(to_sha("return #ARGV"), {})
    assert_equal ["k1", "k2"], r.evalsha(to_sha("return KEYS"), keys: ["k1", "k2"])
    assert_equal ["a1", "a2"], r.evalsha(to_sha("return ARGV"), argv: ["a1", "a2"])
  end

  def test_evalsha_no_script
    assert_raises(Redis::CommandError) do
      r.evalsha("invalidsha")
    end
  end

  def test_script_load_and_evalsha
    script = "return redis.call('set', KEYS[1], ARGV[1])"
    sha = r.script(:load, script)
    assert_equal 40, sha.length # SHA1 is 40 hex chars
    r.evalsha(sha, ["test_key"], ["test_value"])
    assert_equal "test_value", r.get("test_key")
  end

  def test_eval_set_and_get
    r.eval("redis.call('set', 'foo', 'bar')", [])
    assert_equal "bar", r.get("foo")
  end

  def test_evalsha_set_and_get
    sha = to_sha("redis.call('set', KEYS[1], ARGV[1])")
    r.evalsha(sha, ["key1"], ["value1"])
    assert_equal "value1", r.get("key1")
  end
end
