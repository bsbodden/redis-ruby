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
      # rubocop:disable Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/PerceivedComplexity
      def decode
        type_byte = @stream.getbyte
        return nil if type_byte.nil?

        # Fast path: BULK_STRING is most common (GET responses)
        if type_byte == BULK_STRING
          length = read_integer
          return nil if length == -1

          return read_bytes_chomp(length)
        end

        # Fast path: INTEGER is very common (INCR, EXISTS, etc.)
        return read_integer if type_byte == INTEGER

        # Fast path: SIMPLE_STRING (OK response from SET)
        return read_line if type_byte == SIMPLE_STRING

        # Fast path: ARRAY (pipeline responses, MGET, etc.)
        if type_byte == ARRAY
          count = read_integer
          return nil if count == -1

          return Array.new(count) { decode }
        end

        # Less common types use case statement
        case type_byte
        when SIMPLE_ERROR  then decode_simple_error
        when NULL          then decode_null
        when BOOLEAN       then decode_boolean
        when DOUBLE        then decode_double
        when BIG_NUMBER    then decode_big_number
        when BULK_ERROR    then decode_bulk_error
        when VERBATIM      then decode_verbatim
        when MAP           then decode_map
        when SET           then decode_set
        when PUSH          then decode_push
        else
          raise ProtocolError, "Unknown RESP3 type: #{type_byte.chr}"
        end
      end
      # rubocop:enable Metrics/PerceivedComplexity
      # rubocop:enable Metrics/CyclomaticComplexity

      private

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

      # $5\r\nhello\r\n -> "hello"
      # $-1\r\n -> nil
      def decode_bulk_string
        length = read_integer
        return nil if length == -1

        read_bytes_chomp(length)
      end

      # *2\r\n... -> [...]
      # *-1\r\n -> nil
      def decode_array
        count = read_integer
        return nil if count == -1

        Array.new(count) { decode }
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
