# frozen_string_literal: true

require "test_helper"
require "digest/sha1"

class ScriptingIntegrationTest < RedisRubyTestCase
  use_testcontainers!

  def setup
    super
    @script_key1 = "script:key1:#{SecureRandom.hex(4)}"
    @script_key2 = "script:key2:#{SecureRandom.hex(4)}"
    @script_counter = "script:counter:#{SecureRandom.hex(4)}"
  end

  def teardown
    begin
      redis.del(@script_key1, @script_key2, @script_counter)
    rescue StandardError
      nil
    end
    super
  end

  # EVAL tests
  def test_eval_simple_return
    result = redis.eval("return 42", 0)

    assert_equal 42, result
  end

  def test_eval_return_string
    result = redis.eval("return 'hello'", 0)

    assert_equal "hello", result
  end

  def test_eval_return_array
    result = redis.eval("return {1, 2, 3}", 0)

    assert_equal [1, 2, 3], result
  end

  def test_eval_with_keys
    redis.set(@script_key1, "value1")
    result = redis.eval("return redis.call('GET', KEYS[1])", 1, @script_key1)

    assert_equal "value1", result
  end

  def test_eval_with_keys_and_args
    result = redis.eval("return redis.call('SET', KEYS[1], ARGV[1])", 1, @script_key1, "myvalue")

    assert_equal "OK", result
    assert_equal "myvalue", redis.get(@script_key1)
  end

  def test_eval_multiple_keys_and_args
    result = redis.eval(
      "redis.call('SET', KEYS[1], ARGV[1]); redis.call('SET', KEYS[2], ARGV[2]); return 'OK'",
      2, @script_key1, @script_key2, "val1", "val2"
    )

    assert_equal "OK", result
    assert_equal "val1", redis.get(@script_key1)
    assert_equal "val2", redis.get(@script_key2)
  end

  def test_eval_redis_call
    redis.set(@script_counter, "10")
    result = redis.eval("return redis.call('INCR', KEYS[1])", 1, @script_counter)

    assert_equal 11, result
  end

  def test_eval_redis_pcall_error_handling
    # pcall returns error as table instead of raising
    redis.del("scripting:pcall:key")
    result = redis.eval("return redis.pcall('INCR', 'scripting:pcall:key')", 0)
    # Result should be an integer (INCR on non-existent returns 1)
    assert_equal 1, result
  end

  def test_eval_complex_script
    script = <<~LUA
      local current = redis.call('GET', KEYS[1])
      if current then
        return redis.call('INCR', KEYS[1])
      else
        redis.call('SET', KEYS[1], ARGV[1])
        return tonumber(ARGV[1])
      end
    LUA

    # First call - set initial value
    result = redis.eval(script, 1, @script_counter, "100")

    assert_equal 100, result

    # Second call - increment
    result = redis.eval(script, 1, @script_counter, "100")

    assert_equal 101, result
  end

  # EVALSHA tests
  def test_evalsha
    script = "return 'hello from sha'"
    sha = Digest::SHA1.hexdigest(script)

    # First load the script
    loaded_sha = redis.script_load(script)

    assert_equal sha, loaded_sha

    # Now execute by SHA
    result = redis.evalsha(sha, 0)

    assert_equal "hello from sha", result
  end

  def test_evalsha_with_keys_and_args
    script = "return redis.call('SET', KEYS[1], ARGV[1])"
    sha = redis.script_load(script)

    result = redis.evalsha(sha, 1, @script_key1, "sha_value")

    assert_equal "OK", result
    assert_equal "sha_value", redis.get(@script_key1)
  end

  def test_evalsha_noscript_error
    fake_sha = "0000000000000000000000000000000000000000"

    error = assert_raises(RR::CommandError) do
      redis.evalsha(fake_sha, 0)
    end
    assert_match(/NOSCRIPT/, error.message)
  end

  # EVAL_RO tests (read-only, Redis 7.0+)
  def test_eval_ro
    redis.set(@script_key1, "readonly_value")
    result = redis.eval_ro("return redis.call('GET', KEYS[1])", 1, @script_key1)

    assert_equal "readonly_value", result
  end

  # EVALSHA_RO tests (read-only, Redis 7.0+)
  def test_evalsha_ro
    script = "return redis.call('GET', KEYS[1])"
    sha = redis.script_load(script)
    redis.set(@script_key1, "readonly_sha")

    result = redis.evalsha_ro(sha, 1, @script_key1)

    assert_equal "readonly_sha", result
  end

  # SCRIPT LOAD tests
  def test_script_load
    script = "return 'test script'"
    sha = redis.script_load(script)

    assert_kind_of String, sha
    assert_equal 40, sha.length # SHA1 hex is 40 chars
    assert_equal Digest::SHA1.hexdigest(script), sha
  end

  # SCRIPT EXISTS tests
  def test_script_exists_single
    script = "return 'exists test'"
    sha = redis.script_load(script)

    result = redis.script_exists(sha)

    assert_equal [true], result
  end

  def test_script_exists_multiple
    sha1 = redis.script_load("return 1")
    sha2 = redis.script_load("return 2")
    fake_sha = "0000000000000000000000000000000000000000"

    result = redis.script_exists(sha1, sha2, fake_sha)

    assert_equal [true, true, false], result
  end

  # SCRIPT FLUSH tests
  def test_script_flush
    sha = redis.script_load("return 'flush test'")

    assert_equal [true], redis.script_exists(sha)

    result = redis.script_flush

    assert_equal "OK", result

    assert_equal [false], redis.script_exists(sha)
  end

  def test_script_flush_async
    redis.script_load("return 'async flush'")
    result = redis.script_flush(:async)

    assert_equal "OK", result
  end

  def test_script_flush_sync
    redis.script_load("return 'sync flush'")
    result = redis.script_flush(:sync)

    assert_equal "OK", result
  end

  # Script with table/hash return
  def test_eval_return_table
    result = redis.eval("return {key1 = 'value1', key2 = 'value2'}", 0)
    # Lua tables with string keys become Redis arrays in RESP
    assert_kind_of Array, result
  end

  # Atomic operations
  def test_eval_atomic_increment
    redis.set(@script_counter, "0")

    # Run 10 increments
    script = "return redis.call('INCR', KEYS[1])"
    10.times do
      redis.eval(script, 1, @script_counter)
    end

    assert_equal "10", redis.get(@script_counter)
  end

  def test_eval_compare_and_swap
    script = <<~LUA
      local current = redis.call('GET', KEYS[1])
      if current == ARGV[1] then
        redis.call('SET', KEYS[1], ARGV[2])
        return 1
      else
        return 0
      end
    LUA

    redis.set(@script_key1, "old_value")

    # CAS with wrong expected value
    result = redis.eval(script, 1, @script_key1, "wrong_value", "new_value")

    assert_equal 0, result
    assert_equal "old_value", redis.get(@script_key1)

    # CAS with correct expected value
    result = redis.eval(script, 1, @script_key1, "old_value", "new_value")

    assert_equal 1, result
    assert_equal "new_value", redis.get(@script_key1)
  end
end
