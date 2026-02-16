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
      attr_reader :path, :timeout

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
        @callbacks = Hash.new { |h, k| h[k] = [] }
        @ever_connected = false
        connect
      end

      # Execute a Redis command
      #
      # @param command [String] Command name
      # @param args [Array] Command arguments
      # @return [Object] Command result
      def call(command, *args)
        write_command(command, *args)
        read_response
      end

      # Direct call without connection check - use when caller already verified connection
      # @api private
      def call_direct(command, *args)
        write_command(command, *args)
        read_response
      end

      # Ultra-fast path for single-argument commands (GET, DEL, EXISTS, etc.)
      # Avoids splat allocation overhead
      # Note: flush removed since sync=false with manual flushing is unnecessary overhead
      # @api private
      def call_1arg(command, arg)
        @socket.write(@encoder.encode_command(command, arg))
        @decoder.decode
      end

      # Ultra-fast path for two-argument commands (SET without options, HGET, etc.)
      # Avoids splat allocation overhead
      # Note: flush removed since sync=false with manual flushing is unnecessary overhead
      # @api private
      def call_2args(command, arg1, arg2)
        @socket.write(@encoder.encode_command(command, arg1, arg2))
        @decoder.decode
      end

      # Ultra-fast path for three-argument commands (HSET, etc.)
      # Avoids splat allocation overhead
      # Note: flush removed since sync=false with manual flushing is unnecessary overhead
      # @api private
      def call_3args(command, arg1, arg2, arg3)
        @socket.write(@encoder.encode_command(command, arg1, arg2, arg3))
        @decoder.decode
      end

      # Execute multiple commands in a pipeline
      #
      # @param commands [Array<Array>] Array of command arrays
      # @return [Array] Array of results
      def pipeline(commands)
        write_pipeline(commands)
        # Pre-allocate array to avoid map allocation
        count = commands.size
        Array.new(count) { read_response }
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

        valid_events = [:connected, :disconnected, :reconnected, :error]
        unless valid_events.include?(event_type)
          raise ArgumentError, "Invalid event type: #{event_type}. Valid types: #{valid_events.join(', ')}"
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
          timestamp: Time.now
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

        # Trigger appropriate callback
        event_type = @ever_connected ? :reconnected : :connected
        @ever_connected = true

        trigger_callbacks(event_type, {
          type: event_type,
          path: @path,
          timestamp: Time.now
        })
      rescue Errno::ENOENT => e
        error = ConnectionError.new("Unix socket not found: #{@path}")
        trigger_callbacks(:error, {
          type: :error,
          path: @path,
          error: error,
          timestamp: Time.now
        })
        raise error
      rescue Errno::EACCES => e
        error = ConnectionError.new("Permission denied for Unix socket: #{@path}")
        trigger_callbacks(:error, {
          type: :error,
          path: @path,
          error: error,
          timestamp: Time.now
        })
        raise error
      rescue Errno::ECONNREFUSED => e
        error = ConnectionError.new("Connection refused for Unix socket: #{@path}")
        trigger_callbacks(:error, {
          type: :error,
          path: @path,
          error: error,
          timestamp: Time.now
        })
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
        # Disable sync for buffered writes
        @socket.sync = false
      end

      # Write a single command to the socket
      def write_command(command, *args)
        encoded = @encoder.encode_command(command, *args)
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
