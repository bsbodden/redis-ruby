# frozen_string_literal: true

require "socket"
require "openssl"

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
        @ssl_socket.write(@encoder.encode_command(command, arg))
        @ssl_socket.flush
        result = @decoder.decode
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
        result = @decoder.decode
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

      # Ensure we have a valid connection, reconnecting if forked
      #
      # @return [void]
      # @raise [ConnectionError] if reconnection fails
      def ensure_connected
        # Fork safety: detect if we're in a child process BEFORE checking socket state.
        # After fork, the sockets are shared with the parent and must not be reused.
        if @pid && @pid != Process.pid
          @ssl_socket = nil # Don't close - parent owns these sockets
          @tcp_socket = nil
          @pending_reads = 0
        end

        # If connected, verify the response stream is clean
        if connected?
          if @pending_reads > 0
            begin
              close
            rescue StandardError
              nil
            end
          else
            return
          end
        end

        reconnect
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
          host: @host,
          port: @port,
          timestamp: Time.now,
        })

        close
      end

      private

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
      # Uses non-blocking handshake with timeout to handle WaitReadable/WaitWritable
      # during the SSL negotiation phase (redis-rb #972).
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

          case result
          when :wait_readable
            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            raise TimeoutError, "SSL handshake timed out" if remaining <= 0
            raise TimeoutError, "SSL handshake timed out" unless IO.select([@tcp_socket], nil, nil, remaining)
          when :wait_writable
            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            raise TimeoutError, "SSL handshake timed out" if remaining <= 0
            raise TimeoutError, "SSL handshake timed out" unless IO.select(nil, [@tcp_socket], nil, remaining)
          else
            # Handshake complete
            break
          end
        end

        @ssl_socket.post_connection_check(@host) if verify_peer?
      end

      # Clean up sockets when connection setup fails
      def cleanup_sockets_on_error
        begin
          @ssl_socket&.close
        rescue StandardError
          nil
        end
        begin
          @tcp_socket&.close
        rescue StandardError
          nil
        end
        @ssl_socket = nil
        @tcp_socket = nil
      end

      # Trigger appropriate callback on successful connection
      def trigger_connect_success
        event_type = @ever_connected ? :reconnected : :connected
        @ever_connected = true
        trigger_callbacks(event_type, { type: event_type, host: @host, port: @port, timestamp: Time.now })
      end

      # Trigger error callback and raise wrapped error
      def trigger_connect_error(err)
        error = wrap_connection_error(err)
        trigger_callbacks(:error, { type: :error, host: @host, port: @port, error: error, timestamp: Time.now })
        raise error
      end

      # Wrap non-ConnectionError exceptions
      def wrap_connection_error(err)
        return err if err.is_a?(ConnectionError)

        ConnectionError.new("Failed to connect to #{@host}:#{@port}: #{err.message}")
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

      # Configure underlying TCP socket
      def configure_tcp_socket
        @tcp_socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
        @tcp_socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, 1)
      end

      # Create SSL context with configured parameters
      def create_ssl_context
        context = OpenSSL::SSL::SSLContext.new
        context.verify_mode = @ssl_params.fetch(:verify_mode) { OpenSSL::SSL::VERIFY_PEER }
        configure_ca_certificates(context)
        configure_client_certificates(context)
        context.ciphers = @ssl_params[:ciphers] if @ssl_params[:ciphers]
        context.min_version = @ssl_params.fetch(:min_version) { OpenSSL::SSL::TLS1_2_VERSION }
        context
      end

      def configure_ca_certificates(context)
        if @ssl_params[:ca_file]
          context.ca_file = @ssl_params[:ca_file]
        elsif @ssl_params[:ca_path]
          context.ca_path = @ssl_params[:ca_path]
        else
          context.set_params(verify_mode: context.verify_mode)
        end
      end

      def configure_client_certificates(context)
        context.cert = @ssl_params[:cert] if @ssl_params[:cert]
        context.key = @ssl_params[:key] if @ssl_params[:key]
      end

      # Check if peer verification is enabled
      def verify_peer?
        @ssl_params.fetch(:verify_mode) { OpenSSL::SSL::VERIFY_PEER } != OpenSSL::SSL::VERIFY_NONE
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

      # Read a response from the socket
      def read_response
        @decoder.decode
      end
    end
  end
end
