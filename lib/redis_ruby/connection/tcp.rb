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
        @host = host
        @port = port
        @timeout = timeout
        @encoder = Protocol::RESP3Encoder.new
        connect
      end

      # Execute a Redis command
      #
      # @param command [String] Command name
      # @param args [Array] Command arguments
      # @return [Object] Command result
      def call(command, *)
        write_command(command, *)
        read_response
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

      private

      # Establish socket connection
      def connect
        @socket = TCPSocket.new(@host, @port)
        configure_socket
        @buffered_io = Protocol::BufferedIO.new(@socket, read_timeout: @timeout, write_timeout: @timeout)
        @decoder = Protocol::RESP3Decoder.new(@buffered_io)
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

      # Write a single command to the socket
      def write_command(command, *)
        encoded = @encoder.encode_command(command, *)
        @socket.write(encoded)
        @socket.flush
      end

      # Write multiple commands to the socket
      def write_pipeline(commands)
        encoded = @encoder.encode_pipeline(commands)
        @socket.write(encoded)
        @socket.flush
      end

      # Read a response from the socket
      def read_response
        @decoder.decode
      end
    end
  end
end
