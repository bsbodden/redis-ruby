# frozen_string_literal: true

require "socket"
require_relative "tcp_event_dispatch"

module RR
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
    #
    # @example With event dispatcher
    #   dispatcher = RR::EventDispatcher.new
    #   dispatcher.on(RR::ConnectionConnectedEvent) { |event| puts "Connected!" }
    #   conn = TCP.new(host: "localhost", port: 6379, event_dispatcher: dispatcher)
    #
    # @example With async callbacks
    #   async_executor = RR::AsyncCallbackExecutor.new(pool_size: 4)
    #   conn = TCP.new(host: "localhost", port: 6379, async_callbacks: async_executor)
    class TCP
      include TCPEventDispatch

      attr_reader :host, :port, :timeout, :pending_reads

      DEFAULT_HOST = "localhost"
      DEFAULT_PORT = 6379
      DEFAULT_TIMEOUT = 5.0

      # Initialize a new TCP connection
      #
      # @param host [String] Redis server host
      # @param port [Integer] Redis server port
      # @param timeout [Float] Connection timeout in seconds
      # @param event_dispatcher [EventDispatcher, nil] Event dispatcher for lifecycle events
      # @param callback_error_handler [CallbackErrorHandler, nil] Error handler for callbacks
      # @param async_callbacks [AsyncCallbackExecutor, nil] Async executor for callbacks
      # @param instrumentation [Instrumentation, nil] Instrumentation for callback metrics
      def initialize(host: DEFAULT_HOST, port: DEFAULT_PORT, timeout: DEFAULT_TIMEOUT,
                     event_dispatcher: nil, callback_error_handler: nil, async_callbacks: nil,
                     instrumentation: nil)
        # Initialize ALL instance variables upfront for consistent object shapes (YJIT optimization)
        @host = host
        @port = port
        @timeout = timeout
        @encoder = Protocol::RESP3Encoder.new
        @socket = nil
        @buffered_io = nil
        @decoder = nil
        @pid = nil
        @callbacks = Hash.new { |h, k| h[k] = [] }
        @pending_reads = 0
        @ever_connected = false
        @event_dispatcher = event_dispatcher
        @callback_error_handler = callback_error_handler || CallbackErrorHandler.new(strategy: :log)
        @async_callbacks = async_callbacks
        @instrumentation = instrumentation
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
        call_direct(command, *)
      end

      # Direct call without connection check - use when caller already verified connection
      # @api private
      def call_direct(command, *)
        @pending_reads += 1
        write_command_fast(command, *)
        result = decode_with_push_handling
        @pending_reads -= 1
        result
      end

      # Blocking call with extended read timeout for commands like BLPOP, BRPOP
      # @param timeout [Numeric] Total read timeout (connection timeout + command timeout + padding)
      # @api private
      def blocking_call(timeout, command, *)
        @pending_reads += 1
        write_command_fast(command, *)
        result = @buffered_io.with_timeout(timeout) { decode_with_push_handling }
        @pending_reads -= 1
        result
      end

      # Ultra-fast path for single-argument commands (GET, DEL, EXISTS, etc.)
      # Avoids splat allocation overhead
      # Note: flush removed since TCP_NODELAY is enabled (no buffering)
      # @api private
      def call_1arg(command, arg)
        @pending_reads += 1
        @socket.write(@encoder.encode_command(command, arg))
        result = decode_with_push_handling
        @pending_reads -= 1
        result
      end

      # Ultra-fast path for two-argument commands (SET without options, HGET, etc.)
      # Avoids splat allocation overhead
      # Note: flush removed since TCP_NODELAY is enabled (no buffering)
      # @api private
      def call_2args(command, arg1, arg2)
        @pending_reads += 1
        @socket.write(@encoder.encode_command(command, arg1, arg2))
        result = decode_with_push_handling
        @pending_reads -= 1
        result
      end

      # Ultra-fast path for three-argument commands (HSET, etc.)
      # Avoids splat allocation overhead
      # Note: flush removed since TCP_NODELAY is enabled (no buffering)
      # @api private
      def call_3args(command, arg1, arg2, arg3)
        @pending_reads += 1
        @socket.write(@encoder.encode_command(command, arg1, arg2, arg3))
        result = decode_with_push_handling
        @pending_reads -= 1
        result
      end

      # Ensure we have a valid connection, reconnecting if forked
      # Optimized: only check Process.pid when socket exists (avoids syscall on every call)
      #
      # @return [void]
      # @raise [ConnectionError] if reconnection fails
      def ensure_connected
        # Fork safety: detect if we're in a child process BEFORE checking socket state.
        # After fork, the socket is shared with the parent and must not be reused.
        if @pid
          current_pid = Process.pid
          if @pid != current_pid
            trigger_event(:marked_for_reconnect, {
              type: :marked_for_reconnect,
              host: @host,
              port: @port,
              reason: "fork_detected",
              timestamp: Time.now,
            })
            @socket = nil # Don't close - parent owns this socket
            @pending_reads = 0
          end
        end

        # If connected, verify the response stream is clean
        if @socket && !@socket.closed?
          return if @pending_reads.zero?

          # Response stream is corrupted (interrupted between write and read).
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

      # Execute multiple commands in a pipeline
      #
      # @param commands [Array<Array>] Array of command arrays
      # @return [Array] Array of results
      def pipeline(commands)
        ensure_connected
        @pending_reads += commands.size
        write_pipeline(commands)
        # Pre-allocate array to avoid map allocation
        count = commands.size
        Array.new(count) do
          result = read_response
          @pending_reads -= 1
          result
        end
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

      # Validate the connection is clean (no pending reads from interrupted commands).
      # If the response stream is corrupted (pending_reads > 0), closes the connection
      # to prevent response desynchronization (redis-rb #1294, #1162).
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

      # Write a single command to the socket
      # Note: flush removed since TCP_NODELAY is enabled (no buffering)
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
      end

      # Fast path write - assumes command is a string (99% of calls)
      # Note: flush removed since TCP_NODELAY is enabled (no buffering)
      # @api private
      def write_command_fast(command, *)
        @socket.write(@encoder.encode_command(command, *))
      end

      # Read a response from the socket
      #
      # @param timeout [Float, nil] Optional timeout in seconds
      # @return [Object] Decoded response
      def read_response(timeout: nil)
        if timeout
          @buffered_io.with_timeout(timeout) do
            decode_with_push_handling
          end
        else
          decode_with_push_handling
        end
      end

      # Map of event types to builder lambdas
      EVENT_BUILDERS = {
        connection_created: lambda { |d|
          ConnectionCreatedEvent.new(host: d[:host], port: d[:port], timestamp: d[:timestamp])
        },
        connected: lambda { |d|
          ConnectionConnectedEvent.new(host: d[:host], port: d[:port], first_connection: d[:first_connection],
                                       timestamp: d[:timestamp])
        },
        reconnected: lambda { |d|
          ConnectionConnectedEvent.new(host: d[:host], port: d[:port], first_connection: d[:first_connection],
                                       timestamp: d[:timestamp])
        },
        disconnected: lambda { |d|
          ConnectionDisconnectedEvent.new(host: d[:host], port: d[:port], reason: d[:reason], timestamp: d[:timestamp])
        },
        error: lambda { |d|
          ConnectionErrorEvent.new(host: d[:host], port: d[:port], error: d[:error], timestamp: d[:timestamp])
        },
        health_check: lambda { |d|
          ConnectionHealthCheckEvent.new(host: d[:host], port: d[:port], healthy: d[:healthy], latency: d[:latency],
                                         timestamp: d[:timestamp])
        },
        marked_for_reconnect: lambda { |d|
          ConnectionMarkedForReconnectEvent.new(host: d[:host], port: d[:port], reason: d[:reason],
                                                timestamp: d[:timestamp])
        },
      }.freeze

      private

      # Decode a response, routing any interleaved push messages to the handler.
      # Push messages (invalidations, etc.) can arrive asynchronously on the same
      # connection. We loop until we get a non-push response.
      def decode_with_push_handling
        loop do
          result = @decoder.decode
          if result.is_a?(Protocol::PushMessage) && @push_handler
            @push_handler.call(result.data)
          elsif result.is_a?(Protocol::PushMessage)
            # No handler registered, discard push message and continue
          else
            return result
          end
        end
      end

      # Establish socket connection
      def connect
        trigger_event(:connection_created, { type: :connection_created, host: @host, port: @port, timestamp: Time.now })
        establish_tcp_socket
        @pid = Process.pid
        trigger_connect_success
      rescue StandardError => e
        trigger_connect_error(e)
      end

      # Open TCP socket and initialize protocol layers
      def establish_tcp_socket
        @socket = Socket.tcp(@host, @port, connect_timeout: @timeout)
        begin
          configure_socket
          @buffered_io = Protocol::BufferedIO.new(@socket, read_timeout: @timeout, write_timeout: @timeout)
          @decoder = Protocol::RESP3Decoder.new(@buffered_io)
        rescue StandardError
          begin
            @socket.close
          rescue StandardError
            nil
          end
          @socket = nil
          raise
        end
      end

      # Trigger appropriate callback on successful connection
      def trigger_connect_success
        event_type = @ever_connected ? :reconnected : :connected
        @ever_connected = true
        trigger_event(event_type, {
          type: event_type, host: @host, port: @port,
          first_connection: event_type == :connected, timestamp: Time.now,
        })
      end

      # Trigger error callback and raise wrapped error
      def trigger_connect_error(err)
        error = wrap_connection_error(err)
        trigger_event(:error, { type: :error, host: @host, port: @port, error: error, timestamp: Time.now })
        raise error
      end

      # Wrap non-ConnectionError exceptions
      def wrap_connection_error(err)
        return err if err.is_a?(ConnectionError)

        ConnectionError.new("Failed to connect to #{@host}:#{@port}: #{err.message}")
      end

      # Configure socket options for performance
      def configure_socket
        # Disable Nagle's algorithm for lower latency
        @socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)

        # Enable keepalive for connection health
        @socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, 1)

        # Enable sync for unbuffered writes (consistent with TCP_NODELAY)
        @socket.sync = true
      end

      # Write multiple commands to the socket
      # Note: flush removed since TCP_NODELAY is enabled (no buffering)
      def write_pipeline(commands)
        encoded = @encoder.encode_pipeline(commands)
        @socket.write(encoded)
      end
    end
  end
end
