# frozen_string_literal: true

require "io/wait" unless IO.method_defined?(:wait_readable) && IO.method_defined?(:wait_writable)
require_relative "buffered_io_filling"

module RR
  module Protocol
    # High-performance buffered IO wrapper for RESP3 parsing
    #
    # Uses a single buffer with offset tracking to minimize allocations.
    # Inspired by redis-client's BufferedIO implementation.
    #
    # @example
    #   io = BufferedIO.new(socket, read_timeout: 5.0)
    #   byte = io.getbyte
    #   line = io.gets_chomp
    #   int = io.gets_integer
    #
    class BufferedIO
      include BufferedIOFilling

      EOL = "\r\n".b.freeze
      EOL_SIZE = EOL.bytesize
      # Increased from 4KB to 16KB - reduces number of read syscalls
      # Most GET responses fit in a single read, improving throughput
      DEFAULT_CHUNK_SIZE = 16_384

      # Buffer cutoff threshold - if buffer exceeds this, reallocate on next op
      # Prevents memory bloat from large responses persisting
      BUFFER_CUTOFF = 65_536 # 64KB

      # Use byteindex on Ruby 3.2+ (faster), fall back to index
      USE_BYTEINDEX = String.method_defined?(:byteindex)

      attr_accessor :read_timeout, :write_timeout

      def initialize(io, read_timeout: 5.0, write_timeout: 5.0, chunk_size: DEFAULT_CHUNK_SIZE)
        @io = io
        # Start with smaller buffer, grows as needed
        @buffer = String.new(encoding: Encoding::BINARY, capacity: chunk_size)
        @offset = 0
        @chunk_size = chunk_size
        @read_timeout = read_timeout
        @write_timeout = write_timeout
      end

      # Read a single byte
      #
      # @return [Integer, nil] byte value or nil at EOF
      def getbyte
        fill_buffer(1) if @offset >= @buffer.bytesize
        byte = @buffer.getbyte(@offset)
        @offset += 1 if byte
        byte
      end

      if USE_BYTEINDEX
        # Read a line up to CRLF and return without the terminator (Ruby 3.2+)
        #
        # @return [String] line without CRLF
        def gets_chomp
          fill_buffer(1) if @offset >= @buffer.bytesize

          # Look for EOL in buffer using fast byteindex
          until (eol_index = @buffer.byteindex(EOL, @offset))
            fill_buffer(1)
          end

          line = @buffer.byteslice(@offset, eol_index - @offset)
          @offset = eol_index + EOL_SIZE
          line
        end
      else
        # Read a line up to CRLF and return without the terminator (Ruby < 3.2)
        #
        # @return [String] line without CRLF
        def gets_chomp
          fill_buffer(1) if @offset >= @buffer.bytesize

          # Look for EOL in buffer
          until (eol_index = @buffer.index(EOL, @offset))
            fill_buffer(1)
          end

          line = @buffer.byteslice(@offset, eol_index - @offset)
          @offset = eol_index + EOL_SIZE
          line
        end
      end

      # Parse an integer directly from the buffer (byte-by-byte)
      #
      # This is faster than gets_chomp.to_i because it avoids
      # creating an intermediate string object.
      #
      # Optimized with fast path for single-digit integers (very common)
      #
      # @return [Integer] parsed integer
      def gets_integer
        offset = @offset
        fill_buffer(1) if offset >= @buffer.bytesize

        negative, offset = check_negative_sign(offset)
        needed = 3 - (@buffer.bytesize - offset)
        fill_buffer(needed) if needed.positive?

        result = try_single_digit_fast_path(offset, negative)
        return result if result

        # Slow path: multi-digit integer
        int, offset = parse_integer_digits(offset)
        @offset = offset + 2
        negative ? -int : int
      end

      # Read exactly `bytes` bytes, skipping the trailing CRLF
      # @param bytes [Integer] number of bytes to read
      # @return [String] the read data
      def read_chomp(bytes)
        total_needed = bytes + EOL_SIZE
        needed = total_needed - (@buffer.bytesize - @offset)
        fill_buffer(needed) if needed.positive?

        str = @buffer.byteslice(@offset, bytes)
        @offset += total_needed
        str
      end

      # Read exactly `count` bytes
      # @param count [Integer] number of bytes to read
      # @return [String] the read data
      def read(count)
        needed = count - (@buffer.bytesize - @offset)
        fill_buffer(needed) if needed.positive?

        str = @buffer.byteslice(@offset, count)
        @offset += count
        str
      end

      # Skip `bytes` bytes in the buffer
      # @param bytes [Integer] number of bytes to skip
      def skip(bytes)
        needed = bytes - (@buffer.bytesize - @offset)
        fill_buffer(needed) if needed.positive?

        @offset += bytes
        nil
      end

      # Write data to the underlying IO
      # @param data [String] data to write
      # @return [Integer] bytes written
      def write(data)
        total = remaining = data.bytesize
        while remaining.positive?
          bytes_written = @io.write_nonblock(data, exception: false)
          remaining, data = handle_write_result(bytes_written, remaining, data)
        end
        total
      end

      # Flush the underlying IO
      def flush
        @io.flush
      end

      # Close the underlying IO
      def close
        @io.close
      end

      # Check if the underlying IO is closed
      # @return [Boolean]
      def closed?
        @io.closed?
      end

      # Check if at EOF
      # @return [Boolean]
      def eof?
        @offset >= @buffer.bytesize && @io.eof?
      end

      # Execute a block with a temporary timeout
      #
      # @param timeout [Float] Temporary read timeout
      # @yield Block to execute with the timeout
      # @return [Object] Result of the block
      def with_timeout(timeout)
        old_timeout = @read_timeout
        @read_timeout = timeout
        yield
      ensure
        @read_timeout = old_timeout
      end

      private

      # Handle result from write_nonblock
      # @return [Array(Integer, String)] [remaining_bytes, data]
      def handle_write_result(result, remaining, data)
        case result
        when Integer
          remaining -= result
          data = data.byteslice(result..-1) if remaining.positive?
        when :wait_readable
          wait_readable_or_timeout!
        when :wait_writable
          wait_writable_or_timeout!
        when nil
          raise ConnectionError, "Connection closed"
        end
        [remaining, data]
      end

      # Try fast path for single-digit integer followed by CR
      # @return [Integer, nil] parsed integer or nil if not single digit
      def try_single_digit_fast_path(offset, negative)
        second_byte = @buffer.getbyte(offset)
        return unless second_byte&.between?(48, 57) # '0'..'9'
        return unless @buffer.getbyte(offset + 1) == 13 # '\r'

        @offset = offset + 3 # digit + \r\n
        int = second_byte - 48
        negative ? -int : int
      end

      # Check for negative sign at current offset
      # @return [Array(Boolean, Integer)] [negative?, new_offset]
      def check_negative_sign(offset)
        if @buffer.getbyte(offset) == 45 # '-'.ord
          [true, offset + 1]
        else
          [false, offset]
        end
      end

      # Parse digit bytes until CR, refilling buffer as needed
      # @return [Array(Integer, Integer)] [parsed_int, offset_at_cr]
      def parse_integer_digits(offset)
        int = 0
        loop do
          chr = @buffer.getbyte(offset)
          if chr.nil?
            @offset = offset
            fill_buffer(1)
            offset = @offset
            next
          end
          return [int, offset] if chr == 13 # '\r'.ord

          int = (int * 10) + (chr - 48)
          offset += 1
        end
      end
    end
  end
end
