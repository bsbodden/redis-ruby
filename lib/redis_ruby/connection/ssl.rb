# frozen_string_literal: true

require "socket"
require "openssl"

module RedisRuby
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
      attr_reader :host, :port, :timeout

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
        @host = host
        @port = port
        @timeout = timeout
        @ssl_params = ssl_params
        @encoder = Protocol::RESP3Encoder.new
        @pid = nil  # Track process ID for fork safety
        connect
      end

      # Execute a Redis command
      #
      # @param command [String] Command name
      # @param args [Array] Command arguments
      # @return [Object] Command result
      def call(command, *args)
        ensure_connected
        write_command(command, *args)
        read_response
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

      # Ensure we have a valid connection, reconnecting if forked
      #
      # @return [void]
      # @raise [ConnectionError] if reconnection fails
      def ensure_connected
        # Fork safety: detect if we're in a child process
        if @pid && @pid != Process.pid
          # We've forked - the socket is shared with parent, must reconnect
          @ssl_socket = nil
          @tcp_socket = nil
          reconnect
        elsif !connected?
          reconnect
        end
      end

      # Reconnect to the server
      #
      # @return [void]
      def reconnect
        close rescue nil
        connect
      end

      # Close the connection
      def close
        @ssl_socket&.close
        @tcp_socket&.close
      end

      # Check if connected
      #
      # @return [Boolean] true if connected
      def connected?
        @ssl_socket && !@ssl_socket.closed?
      end

      private

      # Establish SSL connection
      def connect
        @tcp_socket = TCPSocket.new(@host, @port)
        configure_tcp_socket

        ssl_context = create_ssl_context
        @ssl_socket = OpenSSL::SSL::SSLSocket.new(@tcp_socket, ssl_context)
        @ssl_socket.hostname = @host  # SNI support
        @ssl_socket.connect
        @ssl_socket.post_connection_check(@host) if verify_peer?

        @buffered_io = Protocol::BufferedIO.new(@ssl_socket, read_timeout: @timeout, write_timeout: @timeout)
        @decoder = Protocol::RESP3Decoder.new(@buffered_io)
        @pid = Process.pid  # Track PID for fork safety
      end

      # Configure underlying TCP socket
      def configure_tcp_socket
        @tcp_socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
        @tcp_socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, 1)
      end

      # Create SSL context with configured parameters
      def create_ssl_context
        context = OpenSSL::SSL::SSLContext.new

        # Set verification mode
        context.verify_mode = @ssl_params.fetch(:verify_mode, OpenSSL::SSL::VERIFY_PEER)

        # Set CA certificate
        if @ssl_params[:ca_file]
          context.ca_file = @ssl_params[:ca_file]
        elsif @ssl_params[:ca_path]
          context.ca_path = @ssl_params[:ca_path]
        else
          # Use system CA certificates
          context.set_params(verify_mode: context.verify_mode)
        end

        # Set client certificate for mTLS
        context.cert = @ssl_params[:cert] if @ssl_params[:cert]
        context.key = @ssl_params[:key] if @ssl_params[:key]

        # Set ciphers
        context.ciphers = @ssl_params[:ciphers] if @ssl_params[:ciphers]

        # Set minimum TLS version (default to TLS 1.2)
        context.min_version = @ssl_params.fetch(:min_version, OpenSSL::SSL::TLS1_2_VERSION)

        context
      end

      # Check if peer verification is enabled
      def verify_peer?
        @ssl_params.fetch(:verify_mode, OpenSSL::SSL::VERIFY_PEER) != OpenSSL::SSL::VERIFY_NONE
      end

      # Write a single command to the socket
      def write_command(command, *args)
        encoded = @encoder.encode_command(command, *args)
        @ssl_socket.write(encoded)
        @ssl_socket.flush
      end

      # Write multiple commands to the socket
      def write_pipeline(commands)
        encoded = @encoder.encode_pipeline(commands)
        @ssl_socket.write(encoded)
        @ssl_socket.flush
      end

      # Read a response from the socket
      def read_response
        @decoder.decode
      end
    end
  end
end
