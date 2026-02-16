# frozen_string_literal: true

require_relative "../unit_test_helper"
require "stringio"

class RESP3DecoderTest < Minitest::Test
  # Helper to create decoder from string
  def decode(string)
    io = StringIO.new(string.b)
    decoder = RR::Protocol::RESP3Decoder.new(io)
    decoder.decode
  end

  # Simple Strings (+)
  def test_decode_simple_string
    assert_equal "OK", decode("+OK\r\n")
  end

  def test_decode_simple_string_pong
    assert_equal "PONG", decode("+PONG\r\n")
  end

  def test_decode_empty_simple_string
    assert_equal "", decode("+\r\n")
  end

  # Simple Errors (-)
  def test_decode_simple_error
    error = decode("-ERR unknown command\r\n")

    assert_instance_of RR::CommandError, error
    assert_equal "ERR unknown command", error.message
  end

  def test_decode_wrongtype_error
    error = decode("-WRONGTYPE Operation against a key holding the wrong kind of value\r\n")

    assert_instance_of RR::CommandError, error
    assert_includes error.message, "WRONGTYPE"
  end

  # Integers (:)
  def test_decode_integer
    assert_equal 1000, decode(":1000\r\n")
  end

  def test_decode_negative_integer
    assert_equal(-42, decode(":-42\r\n"))
  end

  def test_decode_zero
    assert_equal 0, decode(":0\r\n")
  end

  def test_decode_large_integer
    assert_equal 9_223_372_036_854_775_807, decode(":9223372036854775807\r\n")
  end

  # Bulk Strings ($)
  def test_decode_bulk_string
    assert_equal "hello", decode("$5\r\nhello\r\n")
  end

  def test_decode_bulk_string_with_crlf
    assert_equal "line1\r\nline2", decode("$12\r\nline1\r\nline2\r\n")
  end

  def test_decode_empty_bulk_string
    assert_equal "", decode("$0\r\n\r\n")
  end

  def test_decode_null_bulk_string
    assert_nil decode("$-1\r\n")
  end

  def test_decode_bulk_string_binary
    # Binary data with null bytes
    result = decode("$4\r\n\x00\x01\x02\xFF\r\n")

    assert_equal "\x00\x01\x02\xFF".b, result
  end

  # Arrays (*)
  def test_decode_array
    result = decode("*2\r\n$3\r\nfoo\r\n$3\r\nbar\r\n")

    assert_equal %w[foo bar], result
  end

  def test_decode_empty_array
    assert_empty decode("*0\r\n")
  end

  def test_decode_null_array
    assert_nil decode("*-1\r\n")
  end

  def test_decode_array_with_integers
    result = decode("*3\r\n:1\r\n:2\r\n:3\r\n")

    assert_equal [1, 2, 3], result
  end

  def test_decode_array_with_nil_element
    result = decode("*3\r\n$3\r\nfoo\r\n$-1\r\n$3\r\nbar\r\n")

    assert_equal ["foo", nil, "bar"], result
  end

  def test_decode_nested_array
    result = decode("*2\r\n*2\r\n:1\r\n:2\r\n*2\r\n:3\r\n:4\r\n")

    assert_equal [[1, 2], [3, 4]], result
  end

  # RESP3 Null (_)
  def test_decode_null
    assert_nil decode("_\r\n")
  end

  # RESP3 Boolean (#)
  def test_decode_boolean_true
    assert decode("#t\r\n")
  end

  def test_decode_boolean_false
    refute decode("#f\r\n")
  end

  # RESP3 Double (,)
  def test_decode_double
    assert_in_delta 3.14159, decode(",3.14159\r\n"), 0.00001
  end

  def test_decode_negative_double
    assert_in_delta(-2.5, decode(",-2.5\r\n"), 0.00001)
  end

  def test_decode_double_infinity
    assert_equal Float::INFINITY, decode(",inf\r\n")
  end

  def test_decode_double_negative_infinity
    assert_equal(-Float::INFINITY, decode(",-inf\r\n"))
  end

  def test_decode_double_nan
    assert_predicate decode(",nan\r\n"), :nan?
  end

  # RESP3 Big Number (()
  def test_decode_big_number
    result = decode("(12345678901234567890\r\n")

    assert_equal 12_345_678_901_234_567_890, result
  end

  def test_decode_negative_big_number
    result = decode("(-12345678901234567890\r\n")

    assert_equal(-12_345_678_901_234_567_890, result)
  end

  # RESP3 Bulk Error (!)
  def test_decode_bulk_error
    error = decode("!21\r\nSYNTAX invalid syntax\r\n")

    assert_instance_of RR::CommandError, error
    assert_equal "SYNTAX invalid syntax", error.message
  end

  # RESP3 Verbatim String (=)
  def test_decode_verbatim_string
    # =15\r\ntxt:Some string\r\n
    result = decode("=15\r\ntxt:Some string\r\n")

    assert_equal "Some string", result
  end

  def test_decode_verbatim_string_markdown
    # "mkd:# Hello World" = 4 + 13 = 17 bytes
    result = decode("=17\r\nmkd:# Hello World\r\n")

    assert_equal "# Hello World", result
  end

  # RESP3 Map (%)
  def test_decode_map
    result = decode("%2\r\n+key1\r\n:1\r\n+key2\r\n:2\r\n")

    assert_equal({ "key1" => 1, "key2" => 2 }, result)
  end

  def test_decode_empty_map
    assert_empty(decode("%0\r\n"))
  end

  def test_decode_nested_map
    result = decode("%1\r\n+outer\r\n%1\r\n+inner\r\n:42\r\n")

    assert_equal({ "outer" => { "inner" => 42 } }, result)
  end

  # RESP3 Set (~)
  def test_decode_set
    result = decode("~3\r\n+item1\r\n+item2\r\n+item3\r\n")

    assert_instance_of Set, result
    assert_equal Set.new(%w[item1 item2 item3]), result
  end

  def test_decode_empty_set
    result = decode("~0\r\n")

    assert_instance_of Set, result
    assert_empty result
  end

  # RESP3 Push (>)
  # Push messages are used for pub/sub and similar notifications
  def test_decode_push
    result = decode(">2\r\n+message\r\n+data\r\n")

    assert_instance_of RR::Protocol::PushMessage, result
    assert_equal %w[message data], result.data
  end

  # Multiple responses (for pipelining)
  def test_decode_multiple_responses
    io = StringIO.new("+OK\r\n:42\r\n$5\r\nhello\r\n".b)
    decoder = RR::Protocol::RESP3Decoder.new(io)

    assert_equal "OK", decoder.decode
    assert_equal 42, decoder.decode
    assert_equal "hello", decoder.decode
  end
end
