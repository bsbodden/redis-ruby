# frozen_string_literal: true

require_relative "../unit_test_helper"

class RESP3EncoderTest < Minitest::Test
  def setup
    @encoder = RR::Protocol::RESP3Encoder.new
  end

  # Command encoding - the primary use case for encoder
  # Commands are sent as arrays of bulk strings

  def test_encode_simple_command
    # PING -> *1\r\n$4\r\nPING\r\n
    result = @encoder.encode_command("PING")

    assert_equal "*1\r\n$4\r\nPING\r\n", result
  end

  def test_encode_command_with_one_arg
    # GET key -> *2\r\n$3\r\nGET\r\n$3\r\nkey\r\n
    result = @encoder.encode_command("GET", "key")

    assert_equal "*2\r\n$3\r\nGET\r\n$3\r\nkey\r\n", result
  end

  def test_encode_command_with_multiple_args
    # SET key value -> *3\r\n$3\r\nSET\r\n$3\r\nkey\r\n$5\r\nvalue\r\n
    result = @encoder.encode_command("SET", "key", "value")

    assert_equal "*3\r\n$3\r\nSET\r\n$3\r\nkey\r\n$5\r\nvalue\r\n", result
  end

  def test_encode_command_with_integer_arg
    # EXPIRE key 60 -> integers should be converted to strings
    result = @encoder.encode_command("EXPIRE", "key", 60)

    assert_equal "*3\r\n$6\r\nEXPIRE\r\n$3\r\nkey\r\n$2\r\n60\r\n", result
  end

  def test_encode_command_with_binary_data
    # Binary data should be handled correctly
    binary = "\x00\x01\x02\xFF"
    result = @encoder.encode_command("SET", "key", binary)
    expected = "*3\r\n$3\r\nSET\r\n$3\r\nkey\r\n$4\r\n\x00\x01\x02\xFF\r\n".b

    assert_equal expected, result
  end

  def test_encode_command_with_unicode
    # Unicode strings - byte length matters, not character length
    # "héllo" is 6 bytes in UTF-8 (h=1, é=2, l=1, l=1, o=1)
    result = @encoder.encode_command("SET", "key", "héllo")
    expected = "*3\r\n$3\r\nSET\r\n$3\r\nkey\r\n$6\r\nhéllo\r\n".b

    assert_equal expected, result
  end

  def test_encode_command_with_empty_string
    result = @encoder.encode_command("SET", "key", "")

    assert_equal "*3\r\n$3\r\nSET\r\n$3\r\nkey\r\n$0\r\n\r\n", result
  end

  def test_encode_command_with_newlines
    # Bulk strings can contain \r\n
    result = @encoder.encode_command("SET", "key", "line1\r\nline2")

    assert_equal "*3\r\n$3\r\nSET\r\n$3\r\nkey\r\n$12\r\nline1\r\nline2\r\n", result
  end

  # Encoding for pipelining - multiple commands at once

  def test_encode_pipeline
    commands = [
      %w[SET key1 value1],
      %w[SET key2 value2],
      %w[GET key1],
    ]
    result = @encoder.encode_pipeline(commands)
    expected = "*3\r\n$3\r\nSET\r\n$4\r\nkey1\r\n$6\r\nvalue1\r\n" \
               "*3\r\n$3\r\nSET\r\n$4\r\nkey2\r\n$6\r\nvalue2\r\n" \
               "*2\r\n$3\r\nGET\r\n$4\r\nkey1\r\n"

    assert_equal expected, result
  end

  # Direct bulk string encoding (for internal use)

  def test_encode_bulk_string
    result = @encoder.encode_bulk_string("hello")

    assert_equal "$5\r\nhello\r\n", result
  end

  def test_encode_bulk_string_nil
    result = @encoder.encode_bulk_string(nil)

    assert_equal "$-1\r\n", result
  end

  # Verify encoding is binary
  def test_encoding_is_binary
    result = @encoder.encode_command("SET", "key", "value")

    assert_equal Encoding::BINARY, result.encoding
  end
end
