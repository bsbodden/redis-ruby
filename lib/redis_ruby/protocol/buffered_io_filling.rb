# frozen_string_literal: true

module RR
  module Protocol
    # Buffer filling and IO read operations for BufferedIO
    #
    # Extracted to keep BufferedIO class under the line limit.
    # Handles non-blocking reads, buffer management, and timeout handling.
    module BufferedIOFilling
      private

      # Fill the buffer with more data from the underlying IO
      #
      # Uses in-place buffer filling when buffer is empty to avoid
      # intermediate string allocations. Matches redis-client's approach.
      #
      # @param min_bytes [Integer] minimum bytes needed
      def fill_buffer(min_bytes)
        empty_buffer = reset_buffer_if_consumed

        remaining = min_bytes
        while remaining.positive?
          bytes = read_nonblock_safe(empty_buffer)
          remaining, empty_buffer = process_read_result(bytes, remaining, empty_buffer)
        end
      end

      # Reset buffer if all data has been consumed
      # @return [Boolean] whether buffer is empty
      def reset_buffer_if_consumed
        empty = @offset >= @buffer.bytesize
        if empty && @buffer.bytesize > BufferedIO::BUFFER_CUTOFF
          @buffer = String.new(encoding: Encoding::BINARY, capacity: @chunk_size)
        end
        empty
      end

      # Perform a non-blocking read, raising ConnectionError on IO failures
      def read_nonblock_safe(empty_buffer)
        if empty_buffer
          @io.read_nonblock(@chunk_size, @buffer, exception: false)
        else
          @io.read_nonblock(@chunk_size, exception: false)
        end
      rescue IOError, Errno::ECONNRESET => e
        raise ConnectionError, "Connection error: #{e.message}"
      end

      # Process the result of a read_nonblock call
      # @return [Array(Integer, Boolean)] [remaining_bytes, empty_buffer]
      def process_read_result(bytes, remaining, empty_buffer)
        case bytes
        when String
          empty_buffer = append_read_data(bytes, empty_buffer)
          [remaining - bytes.bytesize, empty_buffer]
        when :wait_readable
          wait_readable_or_timeout!
          [remaining, empty_buffer]
        when :wait_writable
          wait_writable_or_timeout!
          [remaining, empty_buffer]
        when nil
          raise ConnectionError, "Connection closed (EOF)"
        end
      end

      # Append read data to the buffer, handling in-place vs append modes
      # @return [Boolean] updated empty_buffer flag
      def append_read_data(bytes, empty_buffer)
        if empty_buffer && bytes.equal?(@buffer)
          @offset = 0
          false
        elsif empty_buffer
          @buffer.clear
          @buffer << bytes
          @offset = 0
          false
        else
          @buffer << bytes
          empty_buffer
        end
      end

      # Wait for readable or raise timeout
      def wait_readable_or_timeout!
        @io.wait_readable(@read_timeout) or raise(TimeoutError, "Read timeout after #{@read_timeout}s")
      end

      # Wait for writable or raise timeout
      def wait_writable_or_timeout!
        @io.wait_writable(@write_timeout) or raise(TimeoutError, "Write timeout after #{@write_timeout}s")
      end
    end
  end
end
