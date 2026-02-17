# frozen_string_literal: true

require "socket"

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
      attr_reader :host, :port, :timeout

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
        @ever_connected = false
        @event_dispatcher = event_dispatcher
        @callback_error_handler = callback_error_handler || CallbackErrorHandler.new(strategy: :log)
        @async_callbacks = async_callbacks
        @instrumentation = instrumentation
        connect
      end

      # Execute a Redis command
      #
      # @param command [String] Command name
      # @param args [Array] Command arguments
      # @return [Object] Command result
      def call(command, *args)
        ensure_connected
        call_direct(command, *args)
      end

      # Direct call without connection check - use when caller already verified connection
      # @api private
      def call_direct(command, *args)
        write_command_fast(command, *args)
        @decoder.decode
      end

      # Ultra-fast path for single-argument commands (GET, DEL, EXISTS, etc.)
      # Avoids splat allocation overhead
      # Note: flush removed since TCP_NODELAY is enabled (no buffering)
      # @api private
      def call_1arg(command, arg)
        @socket.write(@encoder.encode_command(command, arg))
        @decoder.decode
      end

      # Ultra-fast path for two-argument commands (SET without options, HGET, etc.)
      # Avoids splat allocation overhead
      # Note: flush removed since TCP_NODELAY is enabled (no buffering)
      # @api private
      def call_2args(command, arg1, arg2)
        @socket.write(@encoder.encode_command(command, arg1, arg2))
        @decoder.decode
      end

      # Ultra-fast path for three-argument commands (HSET, etc.)
      # Avoids splat allocation overhead
      # Note: flush removed since TCP_NODELAY is enabled (no buffering)
      # @api private
      def call_3args(command, arg1, arg2, arg3)
        @socket.write(@encoder.encode_command(command, arg1, arg2, arg3))
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
            trigger_event(:marked_for_reconnect, {
              type: :marked_for_reconnect,
              host: @host,
              port: @port,
              reason: "fork_detected",
              timestamp: Time.now
            })
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

      # Register a callback for connection lifecycle events
      #
      # Supports both legacy event types and new event types:
      # - Legacy: :connected, :disconnected, :reconnected, :error
      # - New: :connection_created, :health_check, :marked_for_reconnect
      #
      # @param event_type [Symbol] Event type
      # @param callback [Proc] Callback to invoke when event occurs
      # @return [void]
      # @raise [ArgumentError] if event_type is invalid
      #
      # @example Register a callback
      #   conn.register_callback(:connected) do |event|
      #     puts "Connected to #{event[:host]}:#{event[:port]}"
      #   end
      #
      # @example Register a health check callback
      #   conn.register_callback(:health_check) do |event|
      #     puts "Health check: #{event[:healthy] ? 'OK' : 'FAILED'}"
      #   end
      def register_callback(event_type, callback = nil, &block)
        callback ||= block
        raise ArgumentError, "Callback must be provided" unless callback

        valid_events = [:connected, :disconnected, :reconnected, :error,
                        :connection_created, :health_check, :marked_for_reconnect]
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

      # Perform a health check on the connection
      #
      # @param command [String] Command to use for health check (default: "PING")
      # @return [Boolean] true if healthy, false otherwise
      def health_check(command: "PING")
        return false unless connected?

        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        healthy = false

        begin
          call(command)
          healthy = true
        rescue StandardError
          healthy = false
        ensure
          latency = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

          # Trigger health check event
          trigger_event(:health_check, {
            type: :health_check,
            host: @host,
            port: @port,
            healthy: healthy,
            latency: latency,
            timestamp: Time.now
          })
        end

        healthy
      end

      # Disconnect from the server
      #
      # @param reason [String, nil] Reason for disconnection
      # @return [void]
      def disconnect(reason: nil)
        return unless connected?

        trigger_event(:disconnected, {
          type: :disconnected,
          host: @host,
          port: @port,
          reason: reason,
          timestamp: Time.now
        })

        close
      end

      # Write a single command to the socket
      # Note: flush removed since TCP_NODELAY is enabled (no buffering)
      #
      # @param command [String, Array] Command (can be pre-built array)
      # @param args [Array] Command arguments
      # @return [void]
      def write_command(command, *args)
        encoded = if command.is_a?(Array)
                    @encoder.encode_pipeline([command])
                  else
                    @encoder.encode_command(command, *args)
                  end
        @socket.write(encoded)
      end

      # Fast path write - assumes command is a string (99% of calls)
      # Note: flush removed since TCP_NODELAY is enabled (no buffering)
      # @api private
      def write_command_fast(command, *args)
        @socket.write(@encoder.encode_command(command, *args))
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
        # Trigger connection_created event
        trigger_event(:connection_created, {
          type: :connection_created,
          host: @host,
          port: @port,
          timestamp: Time.now
        })

        @socket = TCPSocket.new(@host, @port)
        configure_socket
        @buffered_io = Protocol::BufferedIO.new(@socket, read_timeout: @timeout, write_timeout: @timeout)
        @decoder = Protocol::RESP3Decoder.new(@buffered_io)
        @pid = Process.pid # Track PID for fork safety

        # Trigger appropriate callback
        event_type = @ever_connected ? :reconnected : :connected
        @ever_connected = true

        trigger_event(event_type, {
          type: event_type,
          host: @host,
          port: @port,
          first_connection: event_type == :connected,
          timestamp: Time.now
        })
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT, Errno::ENETUNREACH,
             Socket::ResolutionError, SocketError => e
        error = ConnectionError.new("Failed to connect to #{@host}:#{@port}: #{e.message}")

        trigger_event(:error, {
          type: :error,
          host: @host,
          port: @port,
          error: error,
          timestamp: Time.now
        })

        raise error
      end

      # Trigger callbacks and events for a lifecycle event
      # @api private
      def trigger_event(event_type, event_data)
        # Track callback execution time if instrumentation is enabled
        start_time = @instrumentation ? Process.clock_gettime(Process::CLOCK_MONOTONIC) : nil

        # Trigger legacy callbacks (backward compatibility)
        trigger_legacy_callbacks(event_type, event_data)

        # Dispatch event to event dispatcher if configured
        dispatch_event(event_type, event_data) if @event_dispatcher

        # Record callback metrics
        if @instrumentation && start_time
          duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
          @instrumentation.record_callback_execution(event_type.to_s, duration)
        end
      end

      # Trigger legacy callbacks for backward compatibility
      # @api private
      def trigger_legacy_callbacks(event_type, event_data)
        return if @callbacks[event_type].empty?

        @callbacks[event_type].each do |callback|
          execute_callback(callback, event_data, "#{event_type} callback")
        end
      end

      # Execute a single callback with error handling
      # @api private
      def execute_callback(callback, event_data, context)
        if @async_callbacks
          # Execute asynchronously
          @async_callbacks.execute(context: context) do
            callback.call(event_data)
          end
        elsif @callback_error_handler
          # Execute synchronously with error handling
          @callback_error_handler.call(context: context) do
            callback.call(event_data)
          end
        else
          # Execute synchronously without error handling (backward compatibility)
          callback.call(event_data)
        end
      end

      # Dispatch event to event dispatcher
      # @api private
      def dispatch_event(event_type, event_data)
        event = create_event_object(event_type, event_data)
        return unless event

        @event_dispatcher.dispatch(event)
      end

      # Create an event object from event data
      # @api private
      def create_event_object(event_type, event_data)
        case event_type
        when :connection_created
          ConnectionCreatedEvent.new(
            host: event_data[:host],
            port: event_data[:port],
            timestamp: event_data[:timestamp]
          )
        when :connected, :reconnected
          ConnectionConnectedEvent.new(
            host: event_data[:host],
            port: event_data[:port],
            first_connection: event_data[:first_connection],
            timestamp: event_data[:timestamp]
          )
        when :disconnected
          ConnectionDisconnectedEvent.new(
            host: event_data[:host],
            port: event_data[:port],
            reason: event_data[:reason],
            timestamp: event_data[:timestamp]
          )
        when :error
          ConnectionErrorEvent.new(
            host: event_data[:host],
            port: event_data[:port],
            error: event_data[:error],
            timestamp: event_data[:timestamp]
          )
        when :health_check
          ConnectionHealthCheckEvent.new(
            host: event_data[:host],
            port: event_data[:port],
            healthy: event_data[:healthy],
            latency: event_data[:latency],
            timestamp: event_data[:timestamp]
          )
        when :marked_for_reconnect
          ConnectionMarkedForReconnectEvent.new(
            host: event_data[:host],
            port: event_data[:port],
            reason: event_data[:reason],
            timestamp: event_data[:timestamp]
          )
        end
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
      # Note: flush removed since TCP_NODELAY is enabled (no buffering)
      def write_pipeline(commands)
        encoded = @encoder.encode_pipeline(commands)
        @socket.write(encoded)
      end
    end
  end
end
