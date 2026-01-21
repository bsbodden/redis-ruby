# frozen_string_literal: true

module RedisRuby
  module Protocol
    # RESP3 Protocol Encoder
    #
    # Encodes Ruby objects into RESP3 wire format for sending to Redis.
    # Optimized for performance using byte-level operations.
    #
    # @example Encoding a command
    #   encoder = RESP3Encoder.new
    #   encoder.encode_command("SET", "key", "value")
    #   # => "*3\r\n$3\r\nSET\r\n$3\r\nkey\r\n$5\r\nvalue\r\n"
    #
    # @see https://redis.io/docs/latest/develop/reference/protocol-spec/
    class RESP3Encoder
      # RESP3 type prefixes
      ARRAY_PREFIX = "*"
      BULK_STRING_PREFIX = "$"
      CRLF = "\r\n"

      # Null bulk string
      NULL_BULK_STRING = "$-1\r\n"

      # Pre-freeze constants for performance
      ARRAY_PREFIX_FROZEN = ARRAY_PREFIX.dup.freeze
      BULK_STRING_PREFIX_FROZEN = BULK_STRING_PREFIX.dup.freeze
      CRLF_FROZEN = CRLF.dup.freeze
      NULL_BULK_STRING_FROZEN = NULL_BULK_STRING.dup.freeze

      # Encode a Redis command as RESP3 array of bulk strings
      #
      # @param command [String] The command name (e.g., "GET", "SET")
      # @param args [Array] Command arguments
      # @return [String] RESP3 encoded command (binary encoding)
      def encode_command(command, *args)
        parts = [command, *args]
        encode_array(parts)
      end

      # Encode multiple commands for pipelining
      #
      # @param commands [Array<Array>] Array of command arrays
      # @return [String] RESP3 encoded commands concatenated (binary encoding)
      def encode_pipeline(commands)
        buffer = new_buffer
        commands.each do |cmd|
          buffer << encode_array(cmd)
        end
        buffer
      end

      # Encode a bulk string
      #
      # @param string [String, nil] The string to encode
      # @return [String] RESP3 encoded bulk string (binary encoding)
      def encode_bulk_string(string)
        return NULL_BULK_STRING_FROZEN.dup if string.nil?

        string = string.to_s
        buffer = new_buffer
        buffer << BULK_STRING_PREFIX_FROZEN
        buffer << string.bytesize.to_s
        buffer << CRLF_FROZEN
        buffer << string
        buffer << CRLF_FROZEN
        buffer
      end

      private

      # Encode an array as RESP3 array of bulk strings
      #
      # @param array [Array] Array of elements to encode
      # @return [String] RESP3 encoded array (binary encoding)
      def encode_array(array)
        buffer = new_buffer
        buffer << ARRAY_PREFIX_FROZEN
        buffer << array.size.to_s
        buffer << CRLF_FROZEN

        array.each do |element|
          buffer << encode_bulk_string(element)
        end

        buffer
      end

      # Create a new buffer with binary encoding
      # Pre-allocating capacity improves performance
      #
      # @return [String] Empty binary string buffer
      def new_buffer
        String.new(encoding: Encoding::BINARY, capacity: 128)
      end
    end
  end
end
