# frozen_string_literal: true

require_relative "fast_path_encoders"
require_relative "pipeline_encoders"

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
      include FastPathEncoders
      include PipelineEncoders

      # Pre-frozen constants for performance
      EOL = "\r\n".b.freeze
      NULL_BULK_STRING = "$-1\r\n".b.freeze
      ARRAY_PREFIX = "*".b.freeze
      BULK_PREFIX = "$".b.freeze

      # Pre-encoded command prefixes (format: *{argc}\r\n${cmdlen}\r\n{CMD}\r\n)
      GET_PREFIX = "*2\r\n$3\r\nGET\r\n".b.freeze
      SET_PREFIX = "*3\r\n$3\r\nSET\r\n".b.freeze
      DEL_PREFIX = "*2\r\n$3\r\nDEL\r\n".b.freeze
      INCR_PREFIX = "*2\r\n$4\r\nINCR\r\n".b.freeze
      DECR_PREFIX = "*2\r\n$4\r\nDECR\r\n".b.freeze
      EXISTS_PREFIX = "*2\r\n$6\r\nEXISTS\r\n".b.freeze
      HGET_PREFIX = "*3\r\n$4\r\nHGET\r\n".b.freeze
      HSET_PREFIX = "*4\r\n$4\r\nHSET\r\n".b.freeze
      HDEL_PREFIX = "*3\r\n$4\r\nHDEL\r\n".b.freeze
      LPUSH_PREFIX = "*3\r\n$5\r\nLPUSH\r\n".b.freeze
      RPUSH_PREFIX = "*3\r\n$5\r\nRPUSH\r\n".b.freeze
      LPOP_PREFIX = "*2\r\n$4\r\nLPOP\r\n".b.freeze
      RPOP_PREFIX = "*2\r\n$4\r\nRPOP\r\n".b.freeze
      EXPIRE_PREFIX = "*3\r\n$6\r\nEXPIRE\r\n".b.freeze
      TTL_PREFIX = "*2\r\n$3\r\nTTL\r\n".b.freeze
      MGET_CMD = "$4\r\nMGET\r\n".b.freeze
      MSET_CMD = "$4\r\nMSET\r\n".b.freeze

      # Cache size strings 0-1024 to avoid allocations (most Redis values are small)
      SIZE_CACHE_LIMIT = 1024
      SIZE_CACHE = Array.new(SIZE_CACHE_LIMIT + 1) { |i| i.to_s.b.freeze }.freeze

      # Ruby 3.1+ has Symbol#name which returns frozen string (faster than to_s)
      USE_SYMBOL_NAME = Symbol.method_defined?(:name)

      DEFAULT_BUFFER_CAPACITY = 4096
      BUFFER_CUTOFF = 65_536 # 64KB - reset threshold to prevent memory bloat

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
        # Reset buffer if it grew too large (prevents memory bloat)
        reset_buffer_if_large

        argc = args.size

        # Try fast path encoders for common commands (performance-critical)
        fast_result = try_fast_path_encoding(command, args, argc)
        return fast_result if fast_result

        # General path: check for hash args and encode accordingly
        encode_general_command(command, args, argc)
      end

      # Fast path dispatch tables: command -> prefix constant
      FAST_PATH_1ARG = {
        "GET" => GET_PREFIX, "LPOP" => LPOP_PREFIX,
        "RPOP" => RPOP_PREFIX, "TTL" => TTL_PREFIX,
      }.freeze

      FAST_PATH_2ARG = {
        "SET" => SET_PREFIX, "HGET" => HGET_PREFIX,
        "HDEL" => HDEL_PREFIX, "LPUSH" => LPUSH_PREFIX,
        "RPUSH" => RPUSH_PREFIX, "EXPIRE" => EXPIRE_PREFIX,
      }.freeze

      FAST_PATH_3ARG = { "HSET" => HSET_PREFIX }.freeze

      # Encode command using general path (slower, handles hash args)
      def encode_general_command(command, args, argc)
        check_for_hash_args(args, argc) ? encode_with_hash(command, args) : dump_array_fast(command, args)
      end

      # Check if any args are hashes (optimized for common cases)
      def check_for_hash_args(args, argc)
        case argc
        when 0 then false
        when 1 then args[0].is_a?(Hash)
        when 2 then args[0].is_a?(Hash) || args[1].is_a?(Hash)
        else args.any?(Hash)
        end
      end

      # Encode multiple commands for pipelining
      # @param commands [Array<Array>] Array of command arrays
      # @return [String] RESP3 encoded commands concatenated (binary encoding)
      def encode_pipeline(commands)
        # Reset buffer if it grew too large (prevents memory bloat)
        reset_buffer_if_large
        @buffer.clear
        commands.each do |cmd|
          encode_pipeline_command(cmd)
        end
        @buffer
      end

      # Encode a single command in pipeline (fast path optimized)
      def encode_pipeline_command(cmd)
        first = cmd[0]
        size = cmd.size

        # Try fast path for common commands
        return if try_pipeline_fast_path(first, size, cmd)

        # Slow path for other commands
        dump_array(cmd, @buffer)
      end

      # Pipeline fast path dispatch tables: command -> [expected_size, prefix]
      PIPELINE_1ARG_CMDS = {
        "GET" => [2, GET_PREFIX],
        "LPOP" => [2, LPOP_PREFIX],
        "RPOP" => [2, RPOP_PREFIX],
        "TTL" => [2, TTL_PREFIX],
        "INCR" => [2, INCR_PREFIX],
        "DECR" => [2, DECR_PREFIX],
        "DEL" => [2, DEL_PREFIX],
        "EXISTS" => [2, EXISTS_PREFIX],
      }.freeze

      PIPELINE_2ARG_CMDS = {
        "SET" => [3, SET_PREFIX],
        "HGET" => [3, HGET_PREFIX],
        "LPUSH" => [3, LPUSH_PREFIX],
        "RPUSH" => [3, RPUSH_PREFIX],
        "EXPIRE" => [3, EXPIRE_PREFIX],
      }.freeze

      PIPELINE_3ARG_CMDS = {
        "HSET" => [4, HSET_PREFIX],
      }.freeze

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

      # Reset buffer if it grew too large (prevents memory bloat)
      def reset_buffer_if_large
        return unless @buffer.bytesize > BUFFER_CUTOFF

        @buffer = String.new(encoding: Encoding::BINARY, capacity: DEFAULT_BUFFER_CAPACITY)
      end

      # Encode command with hash arguments (slow path)
      def encode_with_hash(command, args)
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

      # Fast bulk string encoding - inlined for hot path
      # Handles binary encoding properly for non-ASCII strings
      def dump_bulk_string_fast(str, buffer)
        s = str.to_s
        s = s.b unless s.ascii_only?
        buffer << BULK_PREFIX << int_to_s(s.bytesize) << EOL << s << EOL
      end

      # Fast path for arrays without hash arguments
      # Reuses internal buffer to avoid allocations
      # Note: Caller must use returned string before next encode_command call
      def dump_array_fast(command, args)
        count = args.size + 1
        @buffer.clear
        @buffer << ARRAY_PREFIX << int_to_s(count) << EOL
        dump_string_value(command, @buffer)
        # Inline string handling for hot path (most args are strings)
        args.each do |arg|
          if arg.is_a?(String)
            if arg.ascii_only?
              @buffer << BULK_PREFIX << int_to_s(arg.bytesize) << EOL << arg << EOL
            else
              bin = arg.b
              @buffer << BULK_PREFIX << int_to_s(bin.bytesize) << EOL << bin << EOL
            end
          else
            dump_element(arg, @buffer)
          end
        end
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
      # Optimized: Uses Symbol#name on Ruby 3.1+ (returns frozen string, no allocation)
      #
      # @param element [Object] Element to encode
      # @param buffer [String] Buffer to write to
      if USE_SYMBOL_NAME
        def dump_element(element, buffer)
          case element
          when String
            dump_string(element, buffer)
          when Symbol
            # Symbol#name returns frozen string - faster than to_s
            dump_string_value(element.name, buffer)
          when nil
            buffer << NULL_BULK_STRING
          else
            dump_string_value(element.to_s, buffer)
          end
        end
      else
        def dump_element(element, buffer)
          case element
          when String
            dump_string(element, buffer)
          when nil
            buffer << NULL_BULK_STRING
          else
            dump_string_value(element.to_s, buffer)
          end
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
