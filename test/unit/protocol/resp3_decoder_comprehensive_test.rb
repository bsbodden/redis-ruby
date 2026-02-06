# frozen_string_literal: true

require_relative "../unit_test_helper"
require "stringio"

class RESP3DecoderComprehensiveTest < Minitest::Test
  def decoder_for(data)
    io = StringIO.new(data.b)
    RedisRuby::Protocol::RESP3Decoder.new(io)
  end

  # ============================================================
  # Simple String tests
  # ============================================================

  def test_decode_simple_string
    decoder = decoder_for("+OK\r\n")
    assert_equal "OK", decoder.decode
  end

  def test_decode_simple_string_empty
    decoder = decoder_for("+\r\n")
    assert_equal "", decoder.decode
  end

  def test_decode_simple_string_with_spaces
    decoder = decoder_for("+Hello World\r\n")
    assert_equal "Hello World", decoder.decode
  end

  # ============================================================
  # Simple Error tests
  # ============================================================

  def test_decode_simple_error
    decoder = decoder_for("-ERR unknown command\r\n")
    result = decoder.decode
    assert_instance_of RedisRuby::CommandError, result
    assert_equal "ERR unknown command", result.message
  end

  def test_decode_simple_error_wrongtype
    decoder = decoder_for("-WRONGTYPE Operation against a key holding the wrong kind of value\r\n")
    result = decoder.decode
    assert_instance_of RedisRuby::CommandError, result
    assert_includes result.message, "WRONGTYPE"
  end

  # ============================================================
  # Integer tests
  # ============================================================

  def test_decode_integer_positive
    decoder = decoder_for(":1000\r\n")
    assert_equal 1000, decoder.decode
  end

  def test_decode_integer_zero
    decoder = decoder_for(":0\r\n")
    assert_equal 0, decoder.decode
  end

  def test_decode_integer_negative
    decoder = decoder_for(":-100\r\n")
    assert_equal(-100, decoder.decode)
  end

  def test_decode_integer_large
    decoder = decoder_for(":9223372036854775807\r\n")
    assert_equal 9223372036854775807, decoder.decode
  end

  # ============================================================
  # Bulk String tests
  # ============================================================

  def test_decode_bulk_string
    decoder = decoder_for("$5\r\nhello\r\n")
    assert_equal "hello", decoder.decode
  end

  def test_decode_bulk_string_empty
    decoder = decoder_for("$0\r\n\r\n")
    assert_equal "", decoder.decode
  end

  def test_decode_bulk_string_null
    decoder = decoder_for("$-1\r\n")
    assert_nil decoder.decode
  end

  def test_decode_bulk_string_with_crlf
    # "foo\r\nbar" = 8 bytes (f,o,o,\r,\n,b,a,r)
    decoder = decoder_for("$8\r\nfoo\r\nbar\r\n")
    assert_equal "foo\r\nbar", decoder.decode
  end

  def test_decode_bulk_string_binary
    decoder = decoder_for("$4\r\n\x00\x01\x02\xFF\r\n")
    assert_equal "\x00\x01\x02\xFF".b, decoder.decode
  end

  def test_decode_bulk_string_large
    large = "x" * 1000
    decoder = decoder_for("$1000\r\n#{large}\r\n")
    assert_equal large, decoder.decode
  end

  # ============================================================
  # Array tests
  # ============================================================

  def test_decode_array
    decoder = decoder_for("*2\r\n$3\r\nfoo\r\n$3\r\nbar\r\n")
    assert_equal %w[foo bar], decoder.decode
  end

  def test_decode_array_empty
    decoder = decoder_for("*0\r\n")
    assert_equal [], decoder.decode
  end

  def test_decode_array_null
    decoder = decoder_for("*-1\r\n")
    assert_nil decoder.decode
  end

  def test_decode_array_with_integers
    decoder = decoder_for("*3\r\n:1\r\n:2\r\n:3\r\n")
    assert_equal [1, 2, 3], decoder.decode
  end

  def test_decode_array_mixed_types
    decoder = decoder_for("*3\r\n$3\r\nfoo\r\n:42\r\n+OK\r\n")
    assert_equal ["foo", 42, "OK"], decoder.decode
  end

  def test_decode_nested_array
    decoder = decoder_for("*2\r\n*2\r\n:1\r\n:2\r\n*2\r\n:3\r\n:4\r\n")
    assert_equal [[1, 2], [3, 4]], decoder.decode
  end

  def test_decode_array_with_null_elements
    decoder = decoder_for("*3\r\n$3\r\nfoo\r\n$-1\r\n$3\r\nbar\r\n")
    assert_equal ["foo", nil, "bar"], decoder.decode
  end

  # ============================================================
  # Null tests
  # ============================================================

  def test_decode_null
    decoder = decoder_for("_\r\n")
    assert_nil decoder.decode
  end

  # ============================================================
  # Boolean tests
  # ============================================================

  def test_decode_boolean_true
    decoder = decoder_for("#t\r\n")
    assert_equal true, decoder.decode
  end

  def test_decode_boolean_false
    decoder = decoder_for("#f\r\n")
    assert_equal false, decoder.decode
  end

  def test_decode_boolean_invalid
    decoder = decoder_for("#x\r\n")
    assert_raises(RedisRuby::Protocol::ProtocolError) { decoder.decode }
  end

  # ============================================================
  # Double tests
  # ============================================================

  def test_decode_double
    decoder = decoder_for(",3.14159\r\n")
    assert_in_delta 3.14159, decoder.decode, 0.00001
  end

  def test_decode_double_negative
    decoder = decoder_for(",-2.5\r\n")
    assert_in_delta(-2.5, decoder.decode, 0.00001)
  end

  def test_decode_double_infinity
    decoder = decoder_for(",inf\r\n")
    assert_equal Float::INFINITY, decoder.decode
  end

  def test_decode_double_negative_infinity
    decoder = decoder_for(",-inf\r\n")
    assert_equal(-Float::INFINITY, decoder.decode)
  end

  def test_decode_double_nan
    decoder = decoder_for(",nan\r\n")
    assert decoder.decode.nan?
  end

  def test_decode_double_zero
    decoder = decoder_for(",0.0\r\n")
    assert_in_delta 0.0, decoder.decode, 0.00001
  end

  # ============================================================
  # Big Number tests
  # ============================================================

  def test_decode_big_number
    decoder = decoder_for("(12345678901234567890\r\n")
    assert_equal 12345678901234567890, decoder.decode
  end

  def test_decode_big_number_negative
    decoder = decoder_for("(-12345678901234567890\r\n")
    assert_equal(-12345678901234567890, decoder.decode)
  end

  # ============================================================
  # Bulk Error tests
  # ============================================================

  def test_decode_bulk_error
    decoder = decoder_for("!21\r\nSYNTAX invalid syntax\r\n")
    result = decoder.decode
    assert_instance_of RedisRuby::CommandError, result
    assert_equal "SYNTAX invalid syntax", result.message
  end

  # ============================================================
  # Verbatim String tests
  # ============================================================

  def test_decode_verbatim_txt
    # "txt:Some content" = 16 bytes (3+1+12)
    decoder = decoder_for("=16\r\ntxt:Some content\r\n")
    result = decoder.decode
    assert_equal "Some content", result
  end

  def test_decode_verbatim_mkd
    # "mkd:# Markdown" = 14 bytes (3+1+10)
    decoder = decoder_for("=14\r\nmkd:# Markdown\r\n")
    result = decoder.decode
    assert_equal "# Markdown", result
  end

  # ============================================================
  # Map tests
  # ============================================================

  def test_decode_map
    decoder = decoder_for("%2\r\n$4\r\nname\r\n$3\r\nfoo\r\n$3\r\nage\r\n:42\r\n")
    result = decoder.decode
    assert_instance_of Hash, result
    assert_equal "foo", result["name"]
    assert_equal 42, result["age"]
  end

  def test_decode_map_empty
    decoder = decoder_for("%0\r\n")
    assert_equal({}, decoder.decode)
  end

  def test_decode_map_nested
    decoder = decoder_for("%1\r\n$4\r\ndata\r\n%1\r\n$3\r\nfoo\r\n$3\r\nbar\r\n")
    result = decoder.decode
    assert_instance_of Hash, result
    assert_instance_of Hash, result["data"]
    assert_equal "bar", result["data"]["foo"]
  end

  # ============================================================
  # Set tests
  # ============================================================

  def test_decode_set
    decoder = decoder_for("~3\r\n$3\r\none\r\n$3\r\ntwo\r\n$5\r\nthree\r\n")
    result = decoder.decode
    assert_instance_of Set, result
    assert result.include?("one")
    assert result.include?("two")
    assert result.include?("three")
  end

  def test_decode_set_empty
    decoder = decoder_for("~0\r\n")
    result = decoder.decode
    assert_instance_of Set, result
    assert result.empty?
  end

  # ============================================================
  # Push tests
  # ============================================================

  def test_decode_push
    decoder = decoder_for(">3\r\n$7\r\nmessage\r\n$7\r\nchannel\r\n$7\r\npayload\r\n")
    result = decoder.decode
    assert_instance_of RedisRuby::Protocol::PushMessage, result
    assert_equal ["message", "channel", "payload"], result.data
  end

  # ============================================================
  # Unknown type tests
  # ============================================================

  def test_decode_unknown_type
    decoder = decoder_for("@invalid\r\n")
    assert_raises(RedisRuby::Protocol::ProtocolError) { decoder.decode }
  end

  # ============================================================
  # EOF tests
  # ============================================================

  def test_decode_eof
    decoder = decoder_for("")
    assert_nil decoder.decode
  end

  # ============================================================
  # Multiple values in sequence
  # ============================================================

  def test_decode_multiple_values
    decoder = decoder_for("+OK\r\n:42\r\n$5\r\nhello\r\n")
    assert_equal "OK", decoder.decode
    assert_equal 42, decoder.decode
    assert_equal "hello", decoder.decode
  end

  # ============================================================
  # PushMessage class tests
  # ============================================================

  def test_push_message_data_accessor
    msg = RedisRuby::Protocol::PushMessage.new(["type", "channel", "data"])
    assert_equal ["type", "channel", "data"], msg.data
  end
end
