# frozen_string_literal: true

require "io/wait" unless IO.method_defined?(:wait_readable) && IO.method_defined?(:wait_writable)

module RedisRuby
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
      EOL = "\r\n".b.freeze
      EOL_SIZE = EOL.bytesize
      DEFAULT_CHUNK_SIZE = 16_384

      # Use byteindex on Ruby 3.2+ (faster), fall back to index
      USE_BYTEINDEX = String.method_defined?(:byteindex)

      attr_accessor :read_timeout, :write_timeout

      def initialize(io, read_timeout: 5.0, write_timeout: 5.0, chunk_size: DEFAULT_CHUNK_SIZE)
        @io = io
        @buffer = String.new(encoding: Encoding::BINARY, capacity: chunk_size * 2)
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
          until eol_index = @buffer.byteindex(EOL, @offset)
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
          until eol_index = @buffer.index(EOL, @offset)
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
      # @return [Integer] parsed integer
      def gets_integer
        int = 0
        negative = false
        offset = @offset

        # Ensure we have data
        fill_buffer(1) if offset >= @buffer.bytesize

        # Check for negative sign
        first_byte = @buffer.getbyte(offset)
        if first_byte == 45 # '-'.ord
          negative = true
          offset += 1
        end

        while true
          chr = @buffer.getbyte(offset)

          if chr.nil?
            # Need more data - refill and continue
            @offset = offset
            fill_buffer(1)
            offset = @offset
            next
          end

          if chr == 13 # '\r'.ord
            @offset = offset + 2 # Skip \r\n
            break
          end

          int = (int * 10) + (chr - 48)
          offset += 1
        end

        negative ? -int : int
      end

      # Read exactly `bytes` bytes, skipping the trailing CRLF
      #
      # @param bytes [Integer] number of bytes to read
      # @return [String] the read data
      def read_chomp(bytes)
        ensure_remaining(bytes + EOL_SIZE)
        str = @buffer.byteslice(@offset, bytes)
        @offset += bytes + EOL_SIZE
        str
      end

      # Read exactly `count` bytes
      #
      # @param count [Integer] number of bytes to read
      # @return [String] the read data
      def read(count)
        ensure_remaining(count)
        str = @buffer.byteslice(@offset, count)
        @offset += count
        str
      end

      # Skip `offset` bytes in the buffer
      #
      # @param bytes [Integer] number of bytes to skip
      def skip(bytes)
        ensure_remaining(bytes)
        @offset += bytes
        nil
      end

      # Write data to the underlying IO
      #
      # @param data [String] data to write
      # @return [Integer] bytes written
      def write(data)
        total = remaining = data.bytesize
        while remaining > 0
          case bytes_written = @io.write_nonblock(data, exception: false)
          when Integer
            remaining -= bytes_written
            data = data.byteslice(bytes_written..-1) if remaining > 0
          when :wait_readable
            @io.wait_readable(@read_timeout) or raise(TimeoutError, "Read timeout after #{@read_timeout}s")
          when :wait_writable
            @io.wait_writable(@write_timeout) or raise(TimeoutError, "Write timeout after #{@write_timeout}s")
          when nil
            raise ConnectionError, "Connection closed"
          end
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
      #
      # @return [Boolean]
      def closed?
        @io.closed?
      end

      # Check if at EOF
      #
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

      # Ensure at least `bytes` bytes are available in the buffer
      def ensure_remaining(bytes)
        needed = bytes - (@buffer.bytesize - @offset)
        fill_buffer(needed) if needed > 0
      end

      # Fill the buffer with more data from the underlying IO
      #
      # @param min_bytes [Integer] minimum bytes needed
      def fill_buffer(min_bytes)
        # Compact buffer if offset is past halfway point
        # Use slice! to modify in place and avoid allocation
        if @offset > 0 && @offset > @buffer.bytesize / 2
          @buffer.slice!(0, @offset)
          @offset = 0
        end

        remaining = min_bytes
        while remaining > 0
          begin
            chunk = @io.read_nonblock(@chunk_size, exception: false)
          rescue IOError, Errno::ECONNRESET => e
            raise ConnectionError, "Connection error: #{e.message}"
          end

          case chunk
          when String
            @buffer << chunk
            remaining -= chunk.bytesize
          when :wait_readable
            @io.wait_readable(@read_timeout) or raise(TimeoutError, "Read timeout after #{@read_timeout}s")
          when :wait_writable
            @io.wait_writable(@write_timeout) or raise(TimeoutError, "Write timeout after #{@write_timeout}s")
          when nil
            raise ConnectionError, "Connection closed (EOF)"
          end
        end
      end
    end
  end
end
