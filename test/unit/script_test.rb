# frozen_string_literal: true

require "minitest/autorun"
require_relative "../test_helper"

class ScriptTest < Minitest::Test
  def setup
    @client = RR::Client.new
    @connection = mock("connection")
    @client.instance_variable_set(:@connection, @connection)
    @connection.stubs(:connected?).returns(true)
  end

  def test_register_script_returns_script_object
    script = @client.register_script("return 1")

    assert_instance_of RR::Script, script
  end

  def test_script_sha
    script = @client.register_script("return 1")

    assert_equal Digest::SHA1.hexdigest("return 1"), script.sha
  end

  def test_script_call_tries_evalsha_first
    script = @client.register_script("return 1")
    # No keys/args uses call_2args fast path
    @connection.expects(:call_2args).with("EVALSHA", script.sha, 0).returns(1)
    result = script.call

    assert_equal 1, result
  end

  def test_script_call_falls_back_to_eval_on_noscript
    script = @client.register_script("return 1")
    error = RR::CommandError.new("NOSCRIPT No matching script")
    # No keys/args uses call_2args fast path
    @connection.expects(:call_2args).with("EVALSHA", script.sha, 0).raises(error)
    @connection.expects(:call_2args).with("EVAL", "return 1", 0).returns(1)
    result = script.call

    assert_equal 1, result
  end

  def test_script_call_with_keys
    script = @client.register_script("return redis.call('GET', KEYS[1])")
    # With keys/args uses call_direct (varargs)
    @connection.expects(:call_direct).with("EVALSHA", script.sha, 1, "mykey").returns("value")
    result = script.call(keys: ["mykey"])

    assert_equal "value", result
  end

  def test_script_call_with_args
    script = @client.register_script("return ARGV[1]")
    # With args uses call_direct (varargs)
    @connection.expects(:call_direct).with("EVALSHA", script.sha, 0, "hello").returns("hello")
    result = script.call(args: ["hello"])

    assert_equal "hello", result
  end

  def test_script_call_with_keys_and_args
    script = @client.register_script("return redis.call('SET', KEYS[1], ARGV[1])")
    # With keys and args uses call_direct (varargs)
    @connection.expects(:call_direct).with("EVALSHA", script.sha, 1, "mykey", "myval").returns("OK")
    result = script.call(keys: ["mykey"], args: ["myval"])

    assert_equal "OK", result
  end

  def test_script_call_multiple_keys_and_args
    script = @client.register_script("return 1")
    # With multiple keys/args uses call_direct (varargs)
    @connection.expects(:call_direct).with("EVALSHA", script.sha, 2, "k1", "k2", "a1", "a2").returns(1)
    result = script.call(keys: %w[k1 k2], args: %w[a1 a2])

    assert_equal 1, result
  end

  def test_script_does_not_catch_other_command_errors
    script = @client.register_script("return invalid")
    error = RR::CommandError.new("ERR Error compiling script")
    # No keys/args uses call_2args fast path
    @connection.expects(:call_2args).with("EVALSHA", script.sha, 0).raises(error)
    assert_raises(RR::CommandError) { script.call }
  end

  def test_script_source
    script = @client.register_script("return 42")

    assert_equal "return 42", script.source
  end
end
