# frozen_string_literal: true

require "socket"
require "openssl"
require_relative "ssl_support"

module RR
  module Connection
    # SSL/TLS connection to Redis server
    #
    # Wraps TCP connection with OpenSSL for encrypted communication.
    # Supports certificate verification and client certificates.
    #
    # @example Basic SSL connection
    #   conn = SSL.new(host: "redis.example.com", port: 6379)
    #   conn.call("PING")  # => "PONG"
    #
    # @example With certificate verification
    #   conn = SSL.new(
    #     host: "redis.example.com",
    #     port: 6379,
    #     ssl_params: {
    #       ca_file: "/path/to/ca.crt",
    #       verify_mode: OpenSSL::SSL::VERIFY_PEER
    #     }
    #   )
    #
    # @example With client certificate (mTLS)
    #   conn = SSL.new(
    #     host: "redis.example.com",
    #     port: 6379,
    #     ssl_params: {
    #       cert: OpenSSL::X509::Certificate.new(File.read("client.crt")),
    #       key: OpenSSL::PKey::RSA.new(File.read("client.key")),
    #       ca_file: "/path/to/ca.crt"
    #     }
    #   )
    #
    class SSL
      include SSLSupport

      attr_reader :host, :port, :timeout, :pending_reads

      DEFAULT_HOST = "localhost"
      DEFAULT_PORT = 6379
      DEFAULT_TIMEOUT = 5.0

      # Initialize a new SSL connection
      #
      # @param host [String] Redis server host
      # @param port [Integer] Redis server port
      # @param timeout [Float] Connection timeout in seconds
      # @param ssl_params [Hash] SSL parameters for OpenSSL::SSL::SSLContext
      # @option ssl_params [String] :ca_file Path to CA certificate file
      # @option ssl_params [String] :ca_path Path to CA certificate directory
      # @option ssl_params [OpenSSL::X509::Certificate] :cert Client certificate
      # @option ssl_params [OpenSSL::PKey::PKey] :key Client private key
      # @option ssl_params [Integer] :verify_mode OpenSSL verification mode
      # @option ssl_params [String] :ciphers Allowed cipher suites
      # @option ssl_params [Integer] :min_version Minimum SSL/TLS version
      def initialize(host: DEFAULT_HOST, port: DEFAULT_PORT, timeout: DEFAULT_TIMEOUT, ssl_params: {})
        # Initialize ALL instance variables upfront for consistent object shapes (YJIT optimization)
        @host = host
        @port = port
        @timeout = timeout
        @ssl_params = ssl_params
        @encoder = Protocol::RESP3Encoder.new
        @tcp_socket = nil
        @ssl_socket = nil
        @buffered_io = nil
        @decoder = nil
        @pid = nil
        @callbacks = Hash.new { |h, k| h[k] = [] }
        @pending_reads = 0
        @ever_connected = false
        @push_handler = nil
        connect
      end

      # Register a handler for push messages (invalidation, pub/sub, etc.)
      #
      # @yield [Array] Push message data
      # @return [void]
      def on_push(&block)
        @push_handler = block
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
        result = decode_with_push_handling
        @pending_reads -= 1
        result
      end

      # Direct call without connection check - use when caller already verified connection
      # @api private
      def call_direct(command, *)
        @pending_reads += 1
        write_command(command, *)
        result = decode_with_push_handling
        @pending_reads -= 1
        result
      end

      # Ultra-fast path for single-argument commands (GET, DEL, EXISTS, etc.)
      # Avoids splat allocation overhead
      # @api private
      def call_1arg(command, arg)
        @pending_reads += 1
        @ssl_socket.write(@encoder.encode_command(command, arg))
        @ssl_socket.flush
        result = decode_with_push_handling
        @pending_reads -= 1
        result
      end

      # Ultra-fast path for two-argument commands (SET without options, HGET, etc.)
      # Avoids splat allocation overhead
      # @api private
      def call_2args(command, arg1, arg2)
        @pending_reads += 1
        @ssl_socket.write(@encoder.encode_command(command, arg1, arg2))
        @ssl_socket.flush
        result = decode_with_push_handling
        @pending_reads -= 1
        result
      end

      # Ultra-fast path for three-argument commands (HSET, etc.)
      # Avoids splat allocation overhead
      # @api private
      def call_3args(command, arg1, arg2, arg3)
        @pending_reads += 1
        @ssl_socket.write(@encoder.encode_command(command, arg1, arg2, arg3))
        @ssl_socket.flush
        result = decode_with_push_handling
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
        Array.new(count) do
          result = read_response
          @pending_reads -= 1
          result
        end
      end

      # Validate the connection is clean (no pending reads from interrupted commands).
      #
      # @return [Boolean] true if connection is valid, false if corrupted and closed
      def revalidate
        if @pending_reads.positive?
          begin
            close
          rescue StandardError
            nil
          end
          return false
        end
        connected?
      end

      # Ensure we have a valid connection, reconnecting if forked
      #
      # @return [void]
      # @raise [ConnectionError] if reconnection fails
      def ensure_connected
        handle_fork_if_needed
        verify_stream_or_close if connected?
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
        @ssl_socket&.close
        @tcp_socket&.close unless @tcp_socket&.closed?
      end

      # Check if connected
      #
      # @return [Boolean] true if connected
      def connected?
        @ssl_socket && !@ssl_socket.closed?
      end

      private

      # Fork safety: detect if we're in a child process and discard parent's sockets
      def handle_fork_if_needed
        return unless @pid && @pid != Process.pid

        @ssl_socket = nil # Don't close - parent owns these sockets
        @tcp_socket = nil
        @pending_reads = 0
      end

      # Verify response stream is clean; close if corrupted
      def verify_stream_or_close
        return if @pending_reads.zero?

        begin
          close
        rescue StandardError
          nil
        end
      end

      # Establish SSL connection
      def connect
        establish_ssl_socket
        @pid = Process.pid
        trigger_connect_success
      rescue StandardError => e
        trigger_connect_error(e)
      end

      # Create TCP socket, wrap in SSL, and initialize protocol layers
      def establish_ssl_socket
        @tcp_socket = Socket.tcp(@host, @port, connect_timeout: @timeout)
        begin
          configure_tcp_socket
          setup_ssl_layer
          @buffered_io = Protocol::BufferedIO.new(@ssl_socket, read_timeout: @timeout, write_timeout: @timeout)
          @decoder = Protocol::RESP3Decoder.new(@buffered_io)
        rescue StandardError
          cleanup_sockets_on_error
          raise
        end
      end

      # Set up the SSL socket on top of the TCP socket.
      def setup_ssl_layer
        ssl_context = create_ssl_context
        setup_ssl_layer_with_timeout(ssl_context)
      end

      # Perform SSL handshake with non-blocking IO and timeout handling
      def setup_ssl_layer_with_timeout(ssl_context)
        @ssl_socket = OpenSSL::SSL::SSLSocket.new(@tcp_socket, ssl_context)
        @ssl_socket.hostname = @host
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @timeout

        loop do
          result = @ssl_socket.connect_nonblock(exception: false)
          break unless result.is_a?(Symbol)

          wait_for_ssl_io(result, deadline)
        end

        @ssl_socket.post_connection_check(@host) if verify_peer?
      end

      def wait_for_ssl_io(direction, deadline)
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raise TimeoutError, "SSL handshake timed out" if remaining <= 0

        waited = if direction == :wait_readable
                   @tcp_socket.wait_readable(remaining)
                 else
                   @tcp_socket.wait_writable(remaining)
                 end
        raise TimeoutError, "SSL handshake timed out" unless waited
      end

      # Write a single command to the socket
      def write_command(command, *)
        encoded = @encoder.encode_command(command, *)
        @ssl_socket.write(encoded)
        @ssl_socket.flush
      end

      # Write multiple commands to the socket
      def write_pipeline(commands)
        encoded = @encoder.encode_pipeline(commands)
        @ssl_socket.write(encoded)
        @ssl_socket.flush
      end

      # Read a response from the socket, routing push messages
      def read_response
        decode_with_push_handling
      end

      # Decode a response, routing any interleaved push messages to the handler.
      def decode_with_push_handling
        loop do
          result = @decoder.decode
          if result.is_a?(Protocol::PushMessage) && @push_handler
            @push_handler.call(result.data)
          elsif result.is_a?(Protocol::PushMessage)
            # No handler registered, discard push message
          else
            return result
          end
        end
      end
    end
  end
end
