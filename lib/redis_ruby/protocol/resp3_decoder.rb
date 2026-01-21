# frozen_string_literal: true

require "set"

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
    # Optimized for performance using byte-level operations.
    #
    # @example Decoding a response
    #   io = TCPSocket.new("localhost", 6379)
    #   decoder = RESP3Decoder.new(io)
    #   result = decoder.decode
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

      # Special values
      CR = 13 # '\r'
      LF = 10 # '\n'

      def initialize(io)
        @io = io
      end

      # Decode the next RESP3 value from the IO stream
      #
      # @return [Object] Decoded Ruby value
      def decode
        type_byte = @io.getbyte
        return nil if type_byte.nil?

        case type_byte
        when SIMPLE_STRING then decode_simple_string
        when SIMPLE_ERROR  then decode_simple_error
        when INTEGER       then decode_integer
        when BULK_STRING   then decode_bulk_string
        when ARRAY         then decode_array
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

      private

      # Read a line (up to CRLF) and return without the terminator
      def read_line
        line = @io.gets("\r\n")
        return nil if line.nil?

        # Remove trailing \r\n (use chomp to avoid mutating frozen strings)
        line.chomp("\r\n")
      end

      # Read exactly n bytes
      def read_bytes(n)
        @io.read(n)
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
        line = read_line
        line.to_i
      end

      # $5\r\nhello\r\n -> "hello"
      # $-1\r\n -> nil
      def decode_bulk_string
        length = read_line.to_i
        return nil if length == -1

        data = read_bytes(length)
        read_bytes(2) # consume \r\n
        data
      end

      # *2\r\n... -> [...]
      # *-1\r\n -> nil
      def decode_array
        count = read_line.to_i
        return nil if count == -1

        Array.new(count) { decode }
      end

      # _\r\n -> nil
      def decode_null
        read_bytes(2) # consume \r\n
        nil
      end

      # #t\r\n -> true
      # #f\r\n -> false
      def decode_boolean
        char = @io.getbyte
        read_bytes(2) # consume \r\n

        case char
        when 116 then true  # 't'
        when 102 then false # 'f'
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
        line = read_line
        line.to_i
      end

      # !21\r\nSYNTAX invalid syntax\r\n -> CommandError
      def decode_bulk_error
        length = read_line.to_i
        message = read_bytes(length)
        read_bytes(2) # consume \r\n
        CommandError.new(message)
      end

      # =15\r\ntxt:Some string\r\n -> "Some string"
      def decode_verbatim
        length = read_line.to_i
        data = read_bytes(length)
        read_bytes(2) # consume \r\n

        # Format is "enc:content" where enc is 3 chars
        # Skip the encoding prefix and colon (4 bytes)
        data[4..]
      end

      # %2\r\n+key1\r\n:1\r\n+key2\r\n:2\r\n -> { "key1" => 1, "key2" => 2 }
      def decode_map
        count = read_line.to_i
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
        count = read_line.to_i
        result = ::Set.new

        count.times do
          result << decode
        end

        result
      end

      # >2\r\n+message\r\n+data\r\n -> PushMessage
      def decode_push
        count = read_line.to_i
        data = Array.new(count) { decode }
        PushMessage.new(data)
      end
    end

    # Protocol error for malformed RESP3 data
    class ProtocolError < RedisRuby::Error; end
  end
end
