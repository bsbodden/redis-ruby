# frozen_string_literal: true

require_relative "../unit_test_helper"

class ScriptingBranchTest < Minitest::Test
  class MockClient
    include RedisRuby::Commands::Scripting

    attr_reader :last_command

    def call(*args)
      @last_command = args
      mock_return(args)
    end

    def call_1arg(cmd, a1)
      @last_command = [cmd, a1]
      "OK"
    end

    def call_2args(cmd, a1, a2 = nil)
      @last_command = a2.nil? ? [cmd, a1] : [cmd, a1, a2]
      mock_return(@last_command)
    end

    def call_3args(cmd, a1, a2, a3)
      @last_command = [cmd, a1, a2, a3]
      "OK"
    end

    private

    def mock_return(args)
      case args[0]
      when "SCRIPT"
        case args[1]
        when "EXISTS" then [1, 0]
        when "LOAD" then "abc123sha"
        else "OK"
        end
      else
        "result"
      end
    end
  end

  def setup
    @client = MockClient.new
  end

  # eval
  def test_eval_fast_path_no_keys
    @client.eval("return 42", 0)

    assert_equal ["EVAL", "return 42", 0], @client.last_command
  end

  def test_eval_with_keys_and_args
    @client.eval("return KEYS[1]", 1, "key1", "arg1")

    assert_equal ["EVAL", "return KEYS[1]", 1, "key1", "arg1"], @client.last_command
  end

  # evalsha
  def test_evalsha_fast_path_no_keys
    @client.evalsha("abc123", 0)

    assert_equal ["EVALSHA", "abc123", 0], @client.last_command
  end

  def test_evalsha_with_keys_and_args
    @client.evalsha("abc123", 2, "k1", "k2", "a1")

    assert_equal ["EVALSHA", "abc123", 2, "k1", "k2", "a1"], @client.last_command
  end

  # eval_ro
  def test_eval_ro_fast_path
    @client.eval_ro("return 1", 0)

    assert_equal ["EVAL_RO", "return 1", 0], @client.last_command
  end

  def test_eval_ro_with_keys
    @client.eval_ro("return KEYS[1]", 1, "key1")

    assert_equal ["EVAL_RO", "return KEYS[1]", 1, "key1"], @client.last_command
  end

  # evalsha_ro
  def test_evalsha_ro_fast_path
    @client.evalsha_ro("sha1", 0)

    assert_equal ["EVALSHA_RO", "sha1", 0], @client.last_command
  end

  def test_evalsha_ro_with_keys
    @client.evalsha_ro("sha1", 1, "key1")

    assert_equal ["EVALSHA_RO", "sha1", 1, "key1"], @client.last_command
  end

  # script_load
  def test_script_load
    result = @client.script_load("return 42")

    assert_equal ["SCRIPT", "LOAD", "return 42"], @client.last_command
    assert_equal "abc123sha", result
  end

  # script_exists
  def test_script_exists
    result = @client.script_exists("sha1", "sha2")

    assert_equal %w[SCRIPT EXISTS sha1 sha2], @client.last_command
    assert_equal [true, false], result
  end

  # script_flush
  def test_script_flush_no_mode
    @client.script_flush

    assert_equal %w[SCRIPT FLUSH SYNC], @client.last_command
  end

  def test_script_flush_async
    @client.script_flush(:async)

    assert_equal %w[SCRIPT FLUSH ASYNC], @client.last_command
  end

  def test_script_flush_sync
    @client.script_flush(:sync)

    assert_equal %w[SCRIPT FLUSH SYNC], @client.last_command
  end

  # script_kill
  def test_script_kill
    @client.script_kill

    assert_equal %w[SCRIPT KILL], @client.last_command
  end

  # script_debug
  def test_script_debug
    @client.script_debug(:yes)

    assert_equal %w[SCRIPT DEBUG YES], @client.last_command
  end

  # register_script
  def test_register_script
    script_obj = @client.register_script("return 42")

    assert_instance_of RedisRuby::Script, script_obj
  end

  # evalsha_or_eval
  def test_evalsha_or_eval_success
    result = @client.evalsha_or_eval("return 42", ["key1"], ["arg1"])
    # Should try evalsha first
    assert_equal "result", result
  end

  def test_evalsha_or_eval_noscript_fallback
    # Create a client that raises NOSCRIPT on evalsha, then succeeds on eval
    client = NoscriptMockClient.new
    result = client.evalsha_or_eval("return 42", ["key1"])

    assert_equal "eval_result", result
    assert client.eval_called
  end

  class NoscriptMockClient
    include RedisRuby::Commands::Scripting

    attr_reader :eval_called

    def call(*args)
      if args[0] == "EVALSHA"
        raise RedisRuby::CommandError, "NOSCRIPT No matching script"
      elsif args[0] == "EVAL"
        @eval_called = true
        "eval_result"
      end
    end

    def call_2args(cmd, _a1, _a2)
      if cmd == "EVALSHA"
        raise RedisRuby::CommandError, "NOSCRIPT No matching script"
      elsif cmd == "EVAL"
        @eval_called = true
        "eval_result"
      end
    end
  end

  def test_evalsha_or_eval_non_noscript_error_raised
    client = OtherErrorMockClient.new
    assert_raises(RedisRuby::CommandError) do
      client.evalsha_or_eval("return 42")
    end
  end

  class OtherErrorMockClient
    include RedisRuby::Commands::Scripting

    def call(*_args)
      raise RedisRuby::CommandError, "ERR some other error"
    end

    def call_2args(_cmd, _a1, _a2)
      raise RedisRuby::CommandError, "ERR some other error"
    end
  end
end
