# frozen_string_literal: true

require "socket"

module RedisRuby
  module Connection
    # TCP connection to Redis server
    #
    # Handles low-level socket communication with the Redis server,
    # using the RESP3 protocol for encoding/decoding.
    #
    # @example Basic usage
    #   conn = TCP.new(host: "localhost", port: 6379)
    #   conn.call("SET", "key", "value")  # => "OK"
    #   conn.call("GET", "key")           # => "value"
    #   conn.close
    #
    # @example Pipeline
    #   results = conn.pipeline([
    #     ["SET", "key1", "value1"],
    #     ["GET", "key1"]
    #   ])
    #   # => ["OK", "value1"]
    class TCP
      attr_reader :host, :port, :timeout

      DEFAULT_HOST = "localhost"
      DEFAULT_PORT = 6379
      DEFAULT_TIMEOUT = 5.0

      # Initialize a new TCP connection
      #
      # @param host [String] Redis server host
      # @param port [Integer] Redis server port
      # @param timeout [Float] Connection timeout in seconds
      def initialize(host: DEFAULT_HOST, port: DEFAULT_PORT, timeout: DEFAULT_TIMEOUT)
        # Initialize ALL instance variables upfront for consistent object shapes (YJIT optimization)
        @host = host
        @port = port
        @timeout = timeout
        @encoder = Protocol::RESP3Encoder.new
        @socket = nil
        @buffered_io = nil
        @decoder = nil
        @pid = nil
        connect
      end

      # Execute a Redis command
      #
      # @param command [String] Command name
      # @param args [Array] Command arguments
      # @return [Object] Command result
      def call(command, *)
        ensure_connected
        call_direct(command, *)
      end

      # Direct call without connection check - use when caller already verified connection
      # @api private
      def call_direct(command, *)
        write_command_fast(command, *)
        @decoder.decode
      end

      # Ensure we have a valid connection, reconnecting if forked
      # Optimized: only check Process.pid when socket exists (avoids syscall on every call)
      #
      # @return [void]
      # @raise [ConnectionError] if reconnection fails
      def ensure_connected
        return if @socket && !@socket.closed?

        # Only check for fork when we thought we had a connection
        if @pid
          current_pid = Process.pid
          if @pid != current_pid
            # We've forked - the socket is shared with parent, must reconnect
            @socket = nil # Don't close - parent owns this socket
          end
        end
        reconnect unless connected?
      end

      # Reconnect to the server
      #
      # @return [void]
      def reconnect
        begin
          close
        rescue StandardError
          nil
        end
        connect
      end

      # Execute multiple commands in a pipeline
      #
      # @param commands [Array<Array>] Array of command arrays
      # @return [Array] Array of results
      def pipeline(commands)
        ensure_connected
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

      # Write a single command to the socket
      #
      # @param command [String, Array] Command (can be pre-built array)
      # @param args [Array] Command arguments
      # @return [void]
      def write_command(command, *)
        encoded = if command.is_a?(Array)
                    @encoder.encode_pipeline([command])
                  else
                    @encoder.encode_command(command, *)
                  end
        @socket.write(encoded)
        @socket.flush
      end

      # Fast path write - assumes command is a string (99% of calls)
      # @api private
      def write_command_fast(command, *)
        @socket.write(@encoder.encode_command(command, *))
        @socket.flush
      end

      # Read a response from the socket
      #
      # @param timeout [Float, nil] Optional timeout in seconds
      # @return [Object] Decoded response
      def read_response(timeout: nil)
        if timeout
          @buffered_io.with_timeout(timeout) do
            @decoder.decode
          end
        else
          @decoder.decode
        end
      end

      private

      # Establish socket connection
      def connect
        @socket = TCPSocket.new(@host, @port)
        configure_socket
        @buffered_io = Protocol::BufferedIO.new(@socket, read_timeout: @timeout, write_timeout: @timeout)
        @decoder = Protocol::RESP3Decoder.new(@buffered_io)
        @pid = Process.pid # Track PID for fork safety
      end

      # Configure socket options for performance
      def configure_socket
        # Disable Nagle's algorithm for lower latency
        @socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)

        # Enable keepalive for connection health
        @socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, 1)

        # Disable sync for buffered writes (flush manually)
        @socket.sync = false
      end

      # Write multiple commands to the socket
      def write_pipeline(commands)
        encoded = @encoder.encode_pipeline(commands)
        @socket.write(encoded)
        @socket.flush
      end
    end
  end
end
