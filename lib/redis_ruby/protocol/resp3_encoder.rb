# frozen_string_literal: true

module RedisRuby
  module Protocol
    # RESP3 Protocol Encoder
    #
    # Encodes Ruby objects into RESP3 wire format for sending to Redis.
    # Optimized for performance using single-buffer approach and cached size strings.
    #
    # @example Encoding a command
    #   encoder = RESP3Encoder.new
    #   encoder.encode_command("SET", "key", "value")
    #   # => "*3\r\n$3\r\nSET\r\n$3\r\nkey\r\n$5\r\nvalue\r\n"
    #
    # @see https://redis.io/docs/latest/develop/reference/protocol-spec/
    class RESP3Encoder
      # Pre-frozen constants for performance
      EOL = "\r\n".b.freeze
      NULL_BULK_STRING = "$-1\r\n".b.freeze
      ARRAY_PREFIX = "*".b.freeze
      BULK_PREFIX = "$".b.freeze

      # Cache size strings 0-1024 to avoid allocations
      # Most Redis values are small, so this covers the common case
      SIZE_CACHE_LIMIT = 1024
      SIZE_CACHE = Array.new(SIZE_CACHE_LIMIT + 1) { |i| i.to_s.b.freeze }.freeze

      # Default buffer capacity - sized for typical pipeline of 100 commands
      # (100 commands * ~50 bytes per command = 5000 bytes typical)
      DEFAULT_BUFFER_CAPACITY = 16_384

      def initialize
        # Reusable buffer for encoding - avoids allocations
        @buffer = String.new(encoding: Encoding::BINARY, capacity: DEFAULT_BUFFER_CAPACITY)
      end

      # Encode a Redis command as RESP3 array of bulk strings
      #
      # @param command [String] The command name (e.g., "GET", "SET")
      # @param args [Array] Command arguments
      # @return [String] RESP3 encoded command (binary encoding)
      def encode_command(command, *args)
        # Fast path for common case: no hash arguments
        if args.none? { |a| a.is_a?(Hash) }
          dump_array_fast(command, args)
        else
          # Slow path: flatten hash arguments, reuse buffer
          @buffer.clear
          parts_count = 1 + args.sum { |a| a.is_a?(Hash) ? a.size * 2 : 1 }
          @buffer << ARRAY_PREFIX << int_to_s(parts_count) << EOL
          dump_string_value(command, @buffer)
          args.each do |arg|
            if arg.is_a?(Hash)
              arg.each_pair do |k, v|
                dump_element(k, @buffer)
                dump_element(v, @buffer)
              end
            else
              dump_element(arg, @buffer)
            end
          end
          @buffer
        end
      end

      # Encode multiple commands for pipelining
      # Uses separate pipeline buffer for larger capacity
      #
      # @param commands [Array<Array>] Array of command arrays
      # @return [String] RESP3 encoded commands concatenated (binary encoding)
      def encode_pipeline(commands)
        # Reuse buffer, sizing for pipeline
        @buffer.clear
        commands.each do |cmd|
          dump_array(cmd, @buffer)
        end
        @buffer
      end

      # Encode a bulk string (public API for compatibility)
      #
      # @param string [String, nil] The string to encode
      # @return [String] RESP3 encoded bulk string (binary encoding)
      def encode_bulk_string(string)
        return NULL_BULK_STRING.dup if string.nil?

        buffer = String.new(encoding: Encoding::BINARY, capacity: 32)
        dump_string(string.to_s, buffer)
        buffer
      end

      private

      # Fast path for arrays without hash arguments
      # Reuses internal buffer to avoid allocations
      # Note: Caller must use returned string before next encode_command call
      def dump_array_fast(command, args)
        count = args.size + 1
        @buffer.clear
        @buffer << ARRAY_PREFIX << int_to_s(count) << EOL
        dump_string_value(command, @buffer)
        args.each { |arg| dump_element(arg, @buffer) }
        @buffer
      end

      # Dump an array to buffer
      #
      # @param array [Array] Array of elements to encode
      # @param buffer [String] Buffer to write to
      # @return [String] The buffer with encoded array
      def dump_array(array, buffer = nil)
        buffer ||= String.new(encoding: Encoding::BINARY, capacity: 32 + (array.size * 16))
        buffer << ARRAY_PREFIX << int_to_s(array.size) << EOL
        array.each { |item| dump_element(item, buffer) }
        buffer
      end

      # Dump a single element to buffer
      #
      # @param element [Object] Element to encode
      # @param buffer [String] Buffer to write to
      def dump_element(element, buffer)
        case element
        when String
          dump_string(element, buffer)
        when Symbol
          dump_string_value(element.name, buffer)
        when Integer
          dump_string_value(element.to_s, buffer)
        when Float
          dump_string_value(element.to_s, buffer)
        when nil
          buffer << NULL_BULK_STRING
        else
          dump_string_value(element.to_s, buffer)
        end
      end

      # Dump a string to buffer - for strings that might need encoding conversion
      #
      # @param string [String] String to encode
      # @param buffer [String] Buffer to write to
      def dump_string(string, buffer)
        if string.ascii_only?
          dump_string_value(string, buffer)
        else
          dump_string_value(string.b, buffer)
        end
      end

      # Dump a string value to buffer - assumes proper encoding
      # Inlined for performance
      #
      # @param string [String] String to encode
      # @param buffer [String] Buffer to write to
      def dump_string_value(string, buffer)
        buffer << BULK_PREFIX << int_to_s(string.bytesize) << EOL << string << EOL
      end

      # Convert integer to string, using cache for common sizes
      # This eliminates most allocations since most sizes are < 1024
      #
      # @param int [Integer] Integer to convert
      # @return [String] Frozen string representation
      def int_to_s(int)
        if int <= SIZE_CACHE_LIMIT
          SIZE_CACHE[int]
        else
          int.to_s
        end
      end
    end
  end
end
