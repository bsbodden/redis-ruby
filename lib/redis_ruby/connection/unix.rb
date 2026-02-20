# frozen_string_literal: true

require "socket"

module RR
  module Connection
    # Unix Domain Socket connection to Redis server
    #
    # Provides faster local connections by avoiding TCP/IP overhead.
    # Only available when Redis and the client are on the same machine.
    #
    # @example Basic Unix socket connection
    #   conn = Unix.new(path: "/var/run/redis/redis.sock")
    #   conn.call("PING")  # => "PONG"
    #
    # @example With timeout
    #   conn = Unix.new(path: "/tmp/redis.sock", timeout: 10.0)
    #
    class Unix
      attr_reader :path, :timeout, :pending_reads

      DEFAULT_PATH = "/var/run/redis/redis.sock"
      DEFAULT_TIMEOUT = 5.0

      # Initialize a new Unix socket connection
      #
      # @param path [String] Path to Unix socket file
      # @param timeout [Float] Connection timeout in seconds
      def initialize(path: DEFAULT_PATH, timeout: DEFAULT_TIMEOUT)
        # Initialize ALL instance variables upfront for consistent object shapes (YJIT optimization)
        @path = path
        @timeout = timeout
        @encoder = Protocol::RESP3Encoder.new
        @socket = nil
        @buffered_io = nil
        @decoder = nil
        @pid = nil
        @callbacks = Hash.new { |h, k| h[k] = [] }
        @pending_reads = 0
        @ever_connected = false
        connect
      end

      # Execute a Redis command
      #
      # @param command [String] Command name
      # @param args [Array] Command arguments
      # @return [Object] Command result
      def call(command, *)
        ensure_connected
        @pending_reads += 1
        write_command(command, *)
        result = read_response
        @pending_reads -= 1
        result
      end

      # Direct call without connection check - use when caller already verified connection
      # @api private
      def call_direct(command, *)
        @pending_reads += 1
        write_command(command, *)
        result = read_response
        @pending_reads -= 1
        result
      end

      # Ultra-fast path for single-argument commands (GET, DEL, EXISTS, etc.)
      # Avoids splat allocation overhead
      # @api private
      def call_1arg(command, arg)
        @pending_reads += 1
        @socket.write(@encoder.encode_command(command, arg))
        result = @decoder.decode
        @pending_reads -= 1
        result
      end

      # Ultra-fast path for two-argument commands (SET without options, HGET, etc.)
      # Avoids splat allocation overhead
      # @api private
      def call_2args(command, arg1, arg2)
        @pending_reads += 1
        @socket.write(@encoder.encode_command(command, arg1, arg2))
        result = @decoder.decode
        @pending_reads -= 1
        result
      end

      # Ultra-fast path for three-argument commands (HSET, etc.)
      # Avoids splat allocation overhead
      # @api private
      def call_3args(command, arg1, arg2, arg3)
        @pending_reads += 1
        @socket.write(@encoder.encode_command(command, arg1, arg2, arg3))
        result = @decoder.decode
        @pending_reads -= 1
        result
      end

      # Execute multiple commands in a pipeline
      #
      # @param commands [Array<Array>] Array of command arrays
      # @return [Array] Array of results
      def pipeline(commands)
        ensure_connected
        @pending_reads += commands.size
        write_pipeline(commands)
        count = commands.size
        results = Array.new(count) do
          result = read_response
          @pending_reads -= 1
          result
        end
        results
      end

      # Validate the connection is clean (no pending reads from interrupted commands).
      #
      # @return [Boolean] true if connection is valid, false if corrupted and closed
      def revalidate
        if @pending_reads > 0
          begin
            close
          rescue StandardError
            nil
          end
          return false
        end
        connected?
      end

      # Ensure we have a valid connection, reconnecting if needed
      #
      # @return [void]
      # @raise [ConnectionError] if reconnection fails
      def ensure_connected
        # Fork safety: detect if we're in a child process BEFORE checking socket state.
        # After fork, the socket is shared with the parent and must not be reused.
        if @pid
          current_pid = Process.pid
          if @pid != current_pid
            @socket = nil # Don't close - parent owns this socket
            @pending_reads = 0
          end
        end

        # If connected, verify the response stream is clean
        if @socket && !@socket.closed?
          return if @pending_reads == 0

          begin
            close
          rescue StandardError
            nil
          end
        end

        reconnect unless connected?
      end

      # Reconnect to the server
      #
      # @return [void]
      def reconnect
        @pending_reads = 0
        begin
          close
        rescue StandardError
          nil
        end
        connect
      end

      # Close the connection
      def close
        @socket&.close
      end

      # Check if connected
      #
      # @return [Boolean] true if connected
      def connected?
        @socket && !@socket.closed?
      end

      # Register a callback for connection lifecycle events
      #
      # @param event_type [Symbol] Event type (:connected, :disconnected, :reconnected, :error)
      # @param callback [Proc] Callback to invoke when event occurs
      # @return [void]
      # @raise [ArgumentError] if event_type is invalid
      def register_callback(event_type, callback = nil, &block)
        callback ||= block
        raise ArgumentError, "Callback must be provided" unless callback

        valid_events = %i[connected disconnected reconnected error]
        unless valid_events.include?(event_type)
          raise ArgumentError, "Invalid event type: #{event_type}. Valid types: #{valid_events.join(", ")}"
        end

        @callbacks[event_type] << callback
      end

      # Deregister a callback for connection lifecycle events
      #
      # @param event_type [Symbol] Event type
      # @param callback [Proc] Callback to remove
      # @return [void]
      def deregister_callback(event_type, callback)
        @callbacks[event_type].delete(callback)
      end

      # Disconnect from the server
      #
      # @return [void]
      def disconnect
        return unless connected?

        trigger_callbacks(:disconnected, {
          type: :disconnected,
          path: @path,
          timestamp: Time.now,
        })

        close
      end

      private

      # Establish Unix socket connection
      def connect
        @socket = UNIXSocket.new(@path)
        configure_socket
        @buffered_io = Protocol::BufferedIO.new(@socket, read_timeout: @timeout, write_timeout: @timeout)
        @decoder = Protocol::RESP3Decoder.new(@buffered_io)
        @pid = Process.pid
        trigger_connect_success
      rescue Errno::ENOENT
        raise_connection_error("Unix socket not found: #{@path}")
      rescue Errno::EACCES
        raise_connection_error("Permission denied for Unix socket: #{@path}")
      rescue Errno::ECONNREFUSED
        raise_connection_error("Connection refused for Unix socket: #{@path}")
      end

      # Trigger connected/reconnected callback
      def trigger_connect_success
        event_type = @ever_connected ? :reconnected : :connected
        @ever_connected = true
        trigger_callbacks(event_type, { type: event_type, path: @path, timestamp: Time.now })
      end

      # Raise connection error with callback notification
      def raise_connection_error(message)
        error = ConnectionError.new(message)
        trigger_callbacks(:error, { type: :error, path: @path, error: error, timestamp: Time.now })
        raise error
      end

      # Trigger callbacks for an event
      # @api private
      def trigger_callbacks(event_type, event_data)
        @callbacks[event_type].each do |callback|
          callback.call(event_data)
        rescue StandardError => e
          # Log callback errors but don't let them break the connection
          warn "Error in #{event_type} callback: #{e.message}"
        end
      end

      # Configure socket options
      def configure_socket
        # Enable sync for unbuffered writes
        @socket.sync = true
      end

      # Write a single command to the socket
      def write_command(command, *)
        encoded = @encoder.encode_command(command, *)
        @socket.write(encoded)
      end

      # Write multiple commands to the socket
      def write_pipeline(commands)
        encoded = @encoder.encode_pipeline(commands)
        @socket.write(encoded)
      end

      # Read a response from the socket
      def read_response
        @decoder.decode
      end
    end
  end
end
