# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../test_helper"

class FunctionsCommandsTest < Minitest::Test
  def setup
    @client = RR::Client.new
    @connection = mock("connection")
    @client.instance_variable_set(:@connection, @connection)
    @connection.stubs(:connected?).returns(true)
  end

  # --- FUNCTION LOAD ---

  def test_function_load
    @connection.expects(:call_2args).with("FUNCTION", "LOAD",
                                          "#!lua name=mylib\nredis.register_function('myfunc', function() return 1 end)")
      .returns("mylib")
    result = @client.function_load("#!lua name=mylib\nredis.register_function('myfunc', function() return 1 end)")

    assert_equal "mylib", result
  end

  def test_function_load_with_replace
    @connection.expects(:call_direct).with("FUNCTION", "LOAD", "REPLACE",
                                           "#!lua name=mylib\nredis.register_function('myfunc', function() return 1 end)")
      .returns("mylib")
    result = @client.function_load("#!lua name=mylib\nredis.register_function('myfunc', function() return 1 end)",
                                   replace: true)

    assert_equal "mylib", result
  end

  # --- FUNCTION LIST ---

  def test_function_list
    expected = [{ "library_name" => "mylib", "functions" => [] }]
    @connection.expects(:call_1arg).with("FUNCTION", "LIST").returns(expected)
    result = @client.function_list

    assert_equal expected, result
  end

  def test_function_list_with_library_name
    expected = [{ "library_name" => "mylib", "functions" => [] }]
    @connection.expects(:call_direct).with("FUNCTION", "LIST", "LIBRARYNAME", "mylib").returns(expected)
    result = @client.function_list(library_name: "mylib")

    assert_equal expected, result
  end

  def test_function_list_with_code
    expected = [{ "library_name" => "mylib", "library_code" => "code" }]
    @connection.expects(:call_direct).with("FUNCTION", "LIST", "WITHCODE").returns(expected)
    result = @client.function_list(with_code: true)

    assert_equal expected, result
  end

  # --- FUNCTION DELETE ---

  def test_function_delete
    @connection.expects(:call_2args).with("FUNCTION", "DELETE", "mylib").returns("OK")
    result = @client.function_delete("mylib")

    assert_equal "OK", result
  end

  # --- FUNCTION FLUSH ---

  def test_function_flush
    @connection.expects(:call_1arg).with("FUNCTION", "FLUSH").returns("OK")
    result = @client.function_flush

    assert_equal "OK", result
  end

  def test_function_flush_async
    @connection.expects(:call_2args).with("FUNCTION", "FLUSH", "ASYNC").returns("OK")
    result = @client.function_flush(:async)

    assert_equal "OK", result
  end

  # --- FUNCTION DUMP / RESTORE ---

  def test_function_dump
    @connection.expects(:call_1arg).with("FUNCTION", "DUMP").returns("binary_data")
    result = @client.function_dump

    assert_equal "binary_data", result
  end

  def test_function_restore
    @connection.expects(:call_2args).with("FUNCTION", "RESTORE", "binary_data").returns("OK")
    result = @client.function_restore("binary_data")

    assert_equal "OK", result
  end

  def test_function_restore_with_policy
    @connection.expects(:call_direct).with("FUNCTION", "RESTORE", "binary_data", "REPLACE").returns("OK")
    result = @client.function_restore("binary_data", policy: :replace)

    assert_equal "OK", result
  end

  # --- FUNCTION STATS ---

  def test_function_stats
    expected = { "running_script" => nil, "engines" => {} }
    @connection.expects(:call_1arg).with("FUNCTION", "STATS").returns(expected)
    result = @client.function_stats

    assert_equal expected, result
  end

  # --- FCALL ---

  def test_fcall
    @connection.expects(:call_direct).with("FCALL", "myfunc", 1, "key1", "arg1").returns("result")
    result = @client.fcall("myfunc", keys: ["key1"], args: ["arg1"])

    assert_equal "result", result
  end

  def test_fcall_no_keys
    @connection.expects(:call_direct).with("FCALL", "myfunc", 0, "arg1").returns("result")
    result = @client.fcall("myfunc", args: ["arg1"])

    assert_equal "result", result
  end

  def test_fcall_no_args
    @connection.expects(:call_direct).with("FCALL", "myfunc", 1, "key1").returns("result")
    result = @client.fcall("myfunc", keys: ["key1"])

    assert_equal "result", result
  end

  def test_fcall_no_keys_no_args
    @connection.expects(:call_2args).with("FCALL", "myfunc", 0).returns("result")
    result = @client.fcall("myfunc")

    assert_equal "result", result
  end

  # --- FCALL_RO ---

  def test_fcall_ro
    @connection.expects(:call_direct).with("FCALL_RO", "myfunc", 1, "key1", "arg1").returns("result")
    result = @client.fcall_ro("myfunc", keys: ["key1"], args: ["arg1"])

    assert_equal "result", result
  end

  def test_fcall_ro_no_keys
    @connection.expects(:call_2args).with("FCALL_RO", "myfunc", 0).returns("result")
    result = @client.fcall_ro("myfunc")

    assert_equal "result", result
  end
end
