# frozen_string_literal: true

require "socket"

module RedisRuby
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
        @path = path
        @timeout = timeout
        @encoder = Protocol::RESP3Encoder.new
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

      # Execute multiple commands in a pipeline
      #
      # @param commands [Array<Array>] Array of command arrays
      # @return [Array] Array of results
      def pipeline(commands)
        write_pipeline(commands)
        commands.map { read_response }
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

      # Establish Unix socket connection
      def connect
        @socket = UNIXSocket.new(@path)
        configure_socket
        @decoder = Protocol::RESP3Decoder.new(@socket)
      rescue Errno::ENOENT
        raise ConnectionError, "Unix socket not found: #{@path}"
      rescue Errno::EACCES
        raise ConnectionError, "Permission denied for Unix socket: #{@path}"
      rescue Errno::ECONNREFUSED
        raise ConnectionError, "Connection refused for Unix socket: #{@path}"
      end

      # Configure socket options
      def configure_socket
        # Disable sync for buffered writes (flush manually)
        @socket.sync = false
      end

      # Write a single command to the socket
      def write_command(command, *args)
        encoded = @encoder.encode_command(command, *args)
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
