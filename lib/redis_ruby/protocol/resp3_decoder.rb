# frozen_string_literal: true

module RedisRuby
  module Protocol
    # Represents a RESP3 push message (pub/sub, invalidation, etc.)
    class PushMessage
      attr_reader :data

      def initialize(data)
        @data = data
      end
    end

    # RESP3 Protocol Decoder
    #
    # Decodes RESP3 wire format into Ruby objects.
    # Optimized for performance using byte-level operations and buffered IO.
    #
    # @example Decoding a response with BufferedIO
    #   bio = BufferedIO.new(socket, read_timeout: 5.0)
    #   decoder = RESP3Decoder.new(bio)
    #   result = decoder.decode
    #
    # @example Decoding a response with StringIO (for testing)
    #   io = StringIO.new("+OK\r\n")
    #   decoder = RESP3Decoder.new(io)
    #   result = decoder.decode  # => "OK"
    #
    # @see https://redis.io/docs/latest/develop/reference/protocol-spec/
    class RESP3Decoder
      # RESP3 type bytes (using ordinals for fast comparison)
      SIMPLE_STRING  = 43  # '+'
      SIMPLE_ERROR   = 45  # '-'
      INTEGER        = 58  # ':'
      BULK_STRING    = 36  # '$'
      ARRAY          = 42  # '*'
      NULL           = 95  # '_'
      BOOLEAN        = 35  # '#'
      DOUBLE         = 44  # ','
      BIG_NUMBER     = 40  # '('
      BULK_ERROR     = 33  # '!'
      VERBATIM       = 61  # '='
      MAP            = 37  # '%'
      SET            = 126 # '~'
      PUSH           = 62  # '>'

      # Special bytes
      CR = 13 # '\r'
      LF = 10 # '\n'
      TRUE_BYTE = 116  # 't'
      FALSE_BYTE = 102 # 'f'
      MINUS_BYTE = 45  # '-'

      # Dispatch table for less common RESP3 types
      EXTENDED_TYPE_METHODS = {
        SIMPLE_ERROR => :decode_simple_error,
        NULL => :decode_null,
        BOOLEAN => :decode_boolean,
        DOUBLE => :decode_double,
        BIG_NUMBER => :decode_big_number,
        BULK_ERROR => :decode_bulk_error,
        VERBATIM => :decode_verbatim,
        MAP => :decode_map,
        SET => :decode_set,
        PUSH => :decode_push,
      }.freeze

      def initialize(stream)
        @stream = stream
        @buffered = stream.respond_to?(:gets_integer)
      end

      # Decode the next RESP3 value from the stream
      #
      # Optimized: Most common types (BULK_STRING, INTEGER, SIMPLE_STRING) are
      # checked first and inlined for better performance.
      #
      # @return [Object] Decoded Ruby value
      def decode
        type_byte = @stream.getbyte
        return nil if type_byte.nil?

        # Fast path: most common types checked first
        return decode_bulk_string if type_byte == BULK_STRING
        return read_integer if type_byte == INTEGER
        return read_line if type_byte == SIMPLE_STRING
        return decode_array if type_byte == ARRAY

        decode_extended_type(type_byte)
      end

      private

      # Decode bulk string with fast path for common cases
      #
      # Bulk strings are the most common response type for GET operations.
      # Format: $<length>\r\n<data>\r\n
      #
      # Optimized to minimize method calls and allocations.
      def decode_bulk_string
        length = read_integer
        return nil if length == -1

        # For zero-length strings, still need to consume the trailing \r\n
        if length.zero?
          skip_bytes(2) # consume \r\n
          return "".b
        end

        read_bytes_chomp(length)
      end

      def decode_array
        count = read_integer
        return nil if count == -1

        Array.new(count) { decode }
      end

      def decode_extended_type(type_byte)
        method_name = EXTENDED_TYPE_METHODS[type_byte]
        unless method_name
          # Better error message with byte value
          char_repr = type_byte.chr rescue "\\x#{type_byte.to_s(16).rjust(2, '0')}"
          raise ProtocolError, "Unknown RESP3 type: #{char_repr} (byte: #{type_byte})"
        end

        send(method_name)
      end

      # Read a line (up to CRLF) and return without the terminator
      # Uses optimized method if available
      def read_line
        if @buffered
          @stream.gets_chomp
        else
          line = @stream.gets("\r\n")
          return nil if line.nil?

          line.chomp!("\r\n")
          line
        end
      end

      # Read an integer from the stream
      # Uses optimized byte-by-byte parsing if available
      def read_integer
        if @buffered
          @stream.gets_integer
        else
          read_line.to_i
        end
      end

      # Read exactly count bytes
      def read_bytes(count)
        @stream.read(count)
      end

      # Read bytes and skip trailing CRLF
      def read_bytes_chomp(count)
        if @buffered
          @stream.read_chomp(count)
        else
          data = @stream.read(count)
          @stream.read(2) # consume \r\n
          data
        end
      end

      # Skip n bytes
      def skip_bytes(count)
        if @buffered
          @stream.skip(count)
        else
          @stream.read(count)
        end
      end

      # +OK\r\n -> "OK"
      def decode_simple_string
        read_line
      end

      # -ERR message\r\n -> CommandError
      def decode_simple_error
        message = read_line
        CommandError.new(message)
      end

      # :1000\r\n -> 1000
      def decode_integer
        read_integer
      end

      # _\r\n -> nil
      def decode_null
        skip_bytes(2) # consume \r\n
        nil
      end

      # #t\r\n -> true
      # #f\r\n -> false
      def decode_boolean
        char = @stream.getbyte
        skip_bytes(2) # consume \r\n

        case char
        when TRUE_BYTE then true
        when FALSE_BYTE then false
        else
          raise ProtocolError, "Invalid boolean value: #{char.chr}"
        end
      end

      # ,3.14\r\n -> 3.14
      # ,inf\r\n -> Float::INFINITY
      # ,-inf\r\n -> -Float::INFINITY
      # ,nan\r\n -> Float::NAN
      def decode_double
        line = read_line

        case line
        when "inf"  then Float::INFINITY
        when "-inf" then -Float::INFINITY
        when "nan"  then Float::NAN
        else line.to_f
        end
      end

      # (12345678901234567890\r\n -> Integer
      def decode_big_number
        read_integer
      end

      # !21\r\nSYNTAX invalid syntax\r\n -> CommandError
      def decode_bulk_error
        length = read_integer
        message = read_bytes_chomp(length)
        CommandError.new(message)
      end

      # =15\r\ntxt:Some string\r\n -> "Some string"
      def decode_verbatim
        length = read_integer
        data = read_bytes_chomp(length)

        # Format is "enc:content" where enc is 3 chars
        # Skip the encoding prefix and colon (4 bytes)
        data.byteslice(4..-1)
      end

      # %2\r\n+key1\r\n:1\r\n+key2\r\n:2\r\n -> { "key1" => 1, "key2" => 2 }
      def decode_map
        count = read_integer
        result = {}

        count.times do
          key = decode
          value = decode
          result[key] = value
        end

        result
      end

      # ~3\r\n+item1\r\n+item2\r\n+item3\r\n -> Set[item1, item2, item3]
      def decode_set
        count = read_integer
        result = ::Set.new

        count.times do
          result << decode
        end

        result
      end

      # >2\r\n+message\r\n+data\r\n -> PushMessage
      def decode_push
        count = read_integer
        data = Array.new(count) { decode }
        PushMessage.new(data)
      end
    end

    # Protocol error for malformed RESP3 data
    class ProtocolError < RedisRuby::Error; end
  end
end
