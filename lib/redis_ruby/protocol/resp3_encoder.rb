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

      # Pre-encoded command prefixes for ultra-fast path
      # Format: *{argc}\r\n${cmdlen}\r\n{CMD}\r\n
      #
      # String commands
      GET_PREFIX = "*2\r\n$3\r\nGET\r\n".b.freeze
      SET_PREFIX = "*3\r\n$3\r\nSET\r\n".b.freeze
      DEL_PREFIX = "*2\r\n$3\r\nDEL\r\n".b.freeze
      INCR_PREFIX = "*2\r\n$4\r\nINCR\r\n".b.freeze
      DECR_PREFIX = "*2\r\n$4\r\nDECR\r\n".b.freeze
      EXISTS_PREFIX = "*2\r\n$6\r\nEXISTS\r\n".b.freeze

      # Hash commands
      HGET_PREFIX = "*3\r\n$4\r\nHGET\r\n".b.freeze
      HSET_PREFIX = "*4\r\n$4\r\nHSET\r\n".b.freeze
      HDEL_PREFIX = "*3\r\n$4\r\nHDEL\r\n".b.freeze

      # List commands
      LPUSH_PREFIX = "*3\r\n$5\r\nLPUSH\r\n".b.freeze
      RPUSH_PREFIX = "*3\r\n$5\r\nRPUSH\r\n".b.freeze
      LPOP_PREFIX = "*2\r\n$4\r\nLPOP\r\n".b.freeze
      RPOP_PREFIX = "*2\r\n$4\r\nRPOP\r\n".b.freeze

      # Key commands
      EXPIRE_PREFIX = "*3\r\n$6\r\nEXPIRE\r\n".b.freeze
      TTL_PREFIX = "*2\r\n$3\r\nTTL\r\n".b.freeze

      # Batch commands (variable length - just the command part)
      MGET_CMD = "$4\r\nMGET\r\n".b.freeze
      MSET_CMD = "$4\r\nMSET\r\n".b.freeze

      # Cache size strings 0-1024 to avoid allocations
      # Most Redis values are small, so this covers the common case
      SIZE_CACHE_LIMIT = 1024
      SIZE_CACHE = Array.new(SIZE_CACHE_LIMIT + 1) { |i| i.to_s.b.freeze }.freeze

      # Ruby 3.1+ has Symbol#name which returns frozen string (faster than to_s)
      USE_SYMBOL_NAME = Symbol.method_defined?(:name)

      # Default buffer capacity - sized for typical commands
      # Smaller initial size reduces allocation overhead
      DEFAULT_BUFFER_CAPACITY = 4096

      # Buffer cutoff threshold - if buffer exceeds this, reallocate
      # Prevents memory bloat from large payloads persisting
      BUFFER_CUTOFF = 65_536 # 64KB

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

        # Ultra-fast path for GET key (most common)
        return encode_get_fast(args[0]) if argc == 1 && command == "GET"

        # Ultra-fast path for SET key value (second most common)
        return encode_set_fast(args[0], args[1]) if argc == 2 && command == "SET"

        # Fast path for hash commands
        return encode_hget_fast(args[0], args[1]) if argc == 2 && command == "HGET"

        return encode_hset_fast(args[0], args[1], args[2]) if argc == 3 && command == "HSET"

        return encode_hdel_fast(args[0], args[1]) if argc == 2 && command == "HDEL"

        # Fast path for list commands (single value)
        return encode_lpush_fast(args[0], args[1]) if argc == 2 && command == "LPUSH"

        return encode_rpush_fast(args[0], args[1]) if argc == 2 && command == "RPUSH"

        return encode_lpop_fast(args[0]) if argc == 1 && command == "LPOP"

        return encode_rpop_fast(args[0]) if argc == 1 && command == "RPOP"

        # Fast path for key commands
        return encode_expire_fast(args[0], args[1]) if argc == 2 && command == "EXPIRE"

        return encode_ttl_fast(args[0]) if argc == 1 && command == "TTL"

        # Fast path for batch commands
        return encode_mget_fast(args) if command == "MGET" && argc.positive?

        return encode_mset_fast(args) if command == "MSET" && argc.positive? && argc.even?

        # Fast path for 0-2 args: check directly instead of iterating
        has_hash = case argc
                   when 0 then false
                   when 1 then args[0].is_a?(Hash)
                   when 2 then args[0].is_a?(Hash) || args[1].is_a?(Hash)
                   else args.any?(Hash)
                   end

        if has_hash
          encode_with_hash(command, args)
        else
          dump_array_fast(command, args)
        end
      end

      # Ultra-fast GET encoding - single key lookup
      # @api private
      def encode_get_fast(key)
        @buffer.clear
        @buffer << GET_PREFIX
        dump_bulk_string_fast(key, @buffer)
        @buffer
      end

      # Ultra-fast SET encoding - key + value
      # @api private
      def encode_set_fast(key, value)
        @buffer.clear
        @buffer << SET_PREFIX
        dump_bulk_string_fast(key, @buffer)
        dump_bulk_string_fast(value, @buffer)
        @buffer
      end

      # Ultra-fast HGET encoding - hash + field
      # @api private
      def encode_hget_fast(hash, field)
        @buffer.clear
        @buffer << HGET_PREFIX
        dump_bulk_string_fast(hash, @buffer)
        dump_bulk_string_fast(field, @buffer)
        @buffer
      end

      # Ultra-fast HSET encoding - hash + field + value
      # @api private
      def encode_hset_fast(hash, field, value)
        @buffer.clear
        @buffer << HSET_PREFIX
        dump_bulk_string_fast(hash, @buffer)
        dump_bulk_string_fast(field, @buffer)
        dump_bulk_string_fast(value, @buffer)
        @buffer
      end

      # Ultra-fast HDEL encoding - hash + field
      # @api private
      def encode_hdel_fast(hash, field)
        @buffer.clear
        @buffer << HDEL_PREFIX
        dump_bulk_string_fast(hash, @buffer)
        dump_bulk_string_fast(field, @buffer)
        @buffer
      end

      # Ultra-fast LPUSH encoding - list + single value
      # @api private
      def encode_lpush_fast(list, value)
        @buffer.clear
        @buffer << LPUSH_PREFIX
        dump_bulk_string_fast(list, @buffer)
        dump_bulk_string_fast(value, @buffer)
        @buffer
      end

      # Ultra-fast RPUSH encoding - list + single value
      # @api private
      def encode_rpush_fast(list, value)
        @buffer.clear
        @buffer << RPUSH_PREFIX
        dump_bulk_string_fast(list, @buffer)
        dump_bulk_string_fast(value, @buffer)
        @buffer
      end

      # Ultra-fast LPOP encoding - list
      # @api private
      def encode_lpop_fast(list)
        @buffer.clear
        @buffer << LPOP_PREFIX
        dump_bulk_string_fast(list, @buffer)
        @buffer
      end

      # Ultra-fast RPOP encoding - list
      # @api private
      def encode_rpop_fast(list)
        @buffer.clear
        @buffer << RPOP_PREFIX
        dump_bulk_string_fast(list, @buffer)
        @buffer
      end

      # Ultra-fast EXPIRE encoding - key + seconds
      # @api private
      def encode_expire_fast(key, seconds)
        @buffer.clear
        @buffer << EXPIRE_PREFIX
        dump_bulk_string_fast(key, @buffer)
        dump_bulk_string_fast(seconds, @buffer)
        @buffer
      end

      # Ultra-fast TTL encoding - key
      # @api private
      def encode_ttl_fast(key)
        @buffer.clear
        @buffer << TTL_PREFIX
        dump_bulk_string_fast(key, @buffer)
        @buffer
      end

      # Ultra-fast MGET encoding - multiple keys
      # @api private
      def encode_mget_fast(keys)
        @buffer.clear
        @buffer << ARRAY_PREFIX << int_to_s(keys.size + 1) << EOL << MGET_CMD
        keys.each { |key| dump_bulk_string_fast(key, @buffer) }
        @buffer
      end

      # Ultra-fast MSET encoding - key-value pairs
      # @api private
      def encode_mset_fast(args)
        @buffer.clear
        @buffer << ARRAY_PREFIX << int_to_s(args.size + 1) << EOL << MSET_CMD
        args.each { |arg| dump_bulk_string_fast(arg, @buffer) }
        @buffer
      end

      # Encode multiple commands for pipelining
      # Uses separate pipeline buffer for larger capacity
      #
      # @param commands [Array<Array>] Array of command arrays
      # @return [String] RESP3 encoded commands concatenated (binary encoding)
      def encode_pipeline(commands)
        # Reset buffer if it grew too large (prevents memory bloat)
        reset_buffer_if_large
        @buffer.clear
        commands.each do |cmd|
          # Fast path: check first element for common commands
          first = cmd[0]
          size = cmd.size
          case first
          when "GET"
            if size == 2
              @buffer << GET_PREFIX
              dump_bulk_string_fast(cmd[1], @buffer)
              next
            end
          when "SET"
            if size == 3
              @buffer << SET_PREFIX
              dump_bulk_string_fast(cmd[1], @buffer)
              dump_bulk_string_fast(cmd[2], @buffer)
              next
            end
          when "HGET"
            if size == 3
              @buffer << HGET_PREFIX
              dump_bulk_string_fast(cmd[1], @buffer)
              dump_bulk_string_fast(cmd[2], @buffer)
              next
            end
          when "HSET"
            if size == 4
              @buffer << HSET_PREFIX
              dump_bulk_string_fast(cmd[1], @buffer)
              dump_bulk_string_fast(cmd[2], @buffer)
              dump_bulk_string_fast(cmd[3], @buffer)
              next
            end
          when "LPUSH"
            if size == 3
              @buffer << LPUSH_PREFIX
              dump_bulk_string_fast(cmd[1], @buffer)
              dump_bulk_string_fast(cmd[2], @buffer)
              next
            end
          when "RPUSH"
            if size == 3
              @buffer << RPUSH_PREFIX
              dump_bulk_string_fast(cmd[1], @buffer)
              dump_bulk_string_fast(cmd[2], @buffer)
              next
            end
          when "LPOP"
            if size == 2
              @buffer << LPOP_PREFIX
              dump_bulk_string_fast(cmd[1], @buffer)
              next
            end
          when "RPOP"
            if size == 2
              @buffer << RPOP_PREFIX
              dump_bulk_string_fast(cmd[1], @buffer)
              next
            end
          when "EXPIRE"
            if size == 3
              @buffer << EXPIRE_PREFIX
              dump_bulk_string_fast(cmd[1], @buffer)
              dump_bulk_string_fast(cmd[2], @buffer)
              next
            end
          when "TTL"
            if size == 2
              @buffer << TTL_PREFIX
              dump_bulk_string_fast(cmd[1], @buffer)
              next
            end
          when "INCR"
            if size == 2
              @buffer << INCR_PREFIX
              dump_bulk_string_fast(cmd[1], @buffer)
              next
            end
          when "DECR"
            if size == 2
              @buffer << DECR_PREFIX
              dump_bulk_string_fast(cmd[1], @buffer)
              next
            end
          when "DEL"
            if size == 2
              @buffer << DEL_PREFIX
              dump_bulk_string_fast(cmd[1], @buffer)
              next
            end
          when "EXISTS"
            if size == 2
              @buffer << EXISTS_PREFIX
              dump_bulk_string_fast(cmd[1], @buffer)
              next
            end
          end
          # Slow path for other commands
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

      # Reset buffer if it grew too large (prevents memory bloat from large payloads)
      # Only reallocates when buffer exceeds cutoff threshold
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
      else
        def dump_element(element, buffer)
          case element
          when String
            dump_string(element, buffer)
          when Symbol
            dump_string_value(element.to_s, buffer)
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
