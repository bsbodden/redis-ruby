# frozen_string_literal: true

require "minitest/autorun"
require_relative "../test_helper"

class DecodeResponsesTest < Minitest::Test
  def setup
    @connection = mock("connection")
    @connection.stubs(:connected?).returns(true)
  end

  def make_client(**)
    client = RR::Client.new(**)
    client.instance_variable_set(:@connection, @connection)
    client
  end

  # --- Default behavior (no decode) ---

  def test_default_returns_binary
    client = make_client
    # GET uses call_1arg fast path
    @connection.expects(:call_1arg).with("GET", "key").returns("hello".b)
    result = client.get("key")

    assert_equal Encoding::BINARY, result.encoding
  end

  # --- decode_responses: true ---

  def test_decode_responses_string
    client = make_client(decode_responses: true)
    # GET uses call_1arg fast path
    @connection.expects(:call_1arg).with("GET", "key").returns("hello".b)
    result = client.get("key")

    assert_equal Encoding::UTF_8, result.encoding
    assert_equal "hello", result
  end

  def test_decode_responses_nil
    client = make_client(decode_responses: true)
    # GET uses call_1arg fast path
    @connection.expects(:call_1arg).with("GET", "key").returns(nil)
    result = client.get("key")

    assert_nil result
  end

  def test_decode_responses_integer
    client = make_client(decode_responses: true)
    # INCR uses call_1arg fast path
    @connection.expects(:call_1arg).with("INCR", "counter").returns(42)
    result = client.incr("counter")

    assert_equal 42, result
  end

  def test_decode_responses_array
    client = make_client(decode_responses: true)
    # MGET uses call_direct (varargs)
    @connection.expects(:call_direct).with("MGET", "k1", "k2").returns(["v1".b, "v2".b])
    result = client.mget("k1", "k2")

    assert_equal %w[v1 v2], result
    result.each { |v| assert_equal Encoding::UTF_8, v.encoding }
  end

  def test_decode_responses_array_with_nil
    client = make_client(decode_responses: true)
    # MGET uses call_direct (varargs)
    @connection.expects(:call_direct).with("MGET", "k1", "k2").returns(["v1".b, nil])
    result = client.mget("k1", "k2")

    assert_equal ["v1", nil], result
    assert_equal Encoding::UTF_8, result[0].encoding
  end

  def test_decode_responses_hash
    client = make_client(decode_responses: true)
    # HGETALL uses call_1arg fast path
    @connection.expects(:call_1arg).with("HGETALL", "myhash").returns(["field".b, "value".b])
    result = client.hgetall("myhash")

    assert_equal({ "field" => "value" }, result)
    result.each do |k, v|
      assert_equal Encoding::UTF_8, k.encoding
      assert_equal Encoding::UTF_8, v.encoding
    end
  end

  def test_decode_responses_custom_encoding
    client = make_client(decode_responses: true, encoding: "ISO-8859-1")
    # GET uses call_1arg fast path
    @connection.expects(:call_1arg).with("GET", "key").returns("hello".b)
    result = client.get("key")

    assert_equal Encoding::ISO_8859_1, result.encoding
  end

  def test_decode_responses_ok_string
    client = make_client(decode_responses: true)
    # SET without options uses call_2args fast path
    @connection.expects(:call_2args).with("SET", "key", "value").returns("OK".b)
    result = client.set("key", "value")

    assert_equal Encoding::UTF_8, result.encoding
    assert_equal "OK", result
  end

  def test_decode_responses_boolean
    client = make_client(decode_responses: true)
    # EXISTS with single key uses call_1arg fast path
    @connection.expects(:call_1arg).with("EXISTS", "key").returns(1)
    result = client.exists("key")

    assert_equal 1, result
  end
end
