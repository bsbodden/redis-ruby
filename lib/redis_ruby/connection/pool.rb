# frozen_string_literal: true

require "connection_pool"

module RR
  module Connection
    # Thread-safe connection pool for Redis connections
    #
    # Uses the connection_pool gem to manage a pool of TCP connections.
    # Connections are created lazily and reused across threads.
    #
    # @example Basic usage
    #   pool = Pool.new(host: "localhost", port: 6379, size: 10)
    #   pool.with do |conn|
    #     conn.call("PING")  # => "PONG"
    #   end
    #
    # @example With timeout
    #   pool = Pool.new(host: "localhost", size: 5, pool_timeout: 10)
    #   pool.with do |conn|
    #     conn.call("GET", "key")
    #   end
    #
    class Pool
      DEFAULT_SIZE = 5
      DEFAULT_TIMEOUT = 5

      attr_reader :size, :timeout, :circuit_breaker

      # Initialize a new connection pool
      #
      # @param host [String] Redis server host
      # @param port [Integer] Redis server port
      # @param size [Integer] Maximum pool size
      # @param pool_timeout [Float] Timeout waiting for connection from pool
      # @param connection_timeout [Float] Connection timeout in seconds
      # @param password [String, nil] Redis password
      # @param db [Integer] Redis database number
      # @param instrumentation [RR::Instrumentation, nil] Instrumentation instance for metrics
      # @param pool_name [String, nil] Pool name for identification in metrics
      # @param circuit_breaker [RR::CircuitBreaker, nil] Circuit breaker for pool-level failure protection
      # @param health_check_interval [Float, nil] Interval in seconds for automatic health checks (nil = disabled)
      # @param event_dispatcher [RR::EventDispatcher, nil] Event dispatcher for pool lifecycle events
      # @param callback_error_handler [RR::CallbackErrorHandler, nil] Error handler for callbacks
      # @param async_callbacks [RR::AsyncCallbackExecutor, nil] Async executor for callbacks
      def initialize(host: TCP::DEFAULT_HOST, port: TCP::DEFAULT_PORT,
                     size: DEFAULT_SIZE, pool_timeout: DEFAULT_TIMEOUT,
                     connection_timeout: TCP::DEFAULT_TIMEOUT,
                     password: nil, db: 0, instrumentation: nil, pool_name: nil,
                     circuit_breaker: nil, health_check_interval: nil,
                     event_dispatcher: nil, callback_error_handler: nil, async_callbacks: nil)
        @host = host
        @port = port
        @size = size
        @timeout = pool_timeout
        @connection_timeout = connection_timeout
        @password = password
        @db = db
        @instrumentation = instrumentation
        @pool_name = pool_name || "#{host}:#{port}"
        @circuit_breaker = circuit_breaker
        @health_check_interval = health_check_interval
        @last_health_check = nil
        @event_dispatcher = event_dispatcher
        @callback_error_handler = callback_error_handler || CallbackErrorHandler.new(strategy: :log)
        @async_callbacks = async_callbacks

        @pool = ConnectionPool.new(size: size, timeout: pool_timeout) do
          create_connection_with_metrics
        end

        # Trigger pool created event
        trigger_pool_event(:pool_created, {
          pool_name: @pool_name,
          size: @size,
          timeout: @timeout,
          timestamp: Time.now
        })
      end

      # Execute a block with a connection from the pool
      #
      # The connection is automatically returned to the pool after the block.
      # If circuit breaker is configured, wraps execution with circuit breaker protection.
      # If health check interval is configured, performs periodic health checks.
      #
      # @yield [TCP] connection from the pool
      # @return [Object] result of the block
      def with(&block)
        # Perform health check if needed
        check_health_if_needed

        execute_block = lambda do
          if @instrumentation
            checkout_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            begin
              @pool.with do |conn|
                checkout_duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - checkout_start
                @instrumentation.record_connection_checkout(checkout_duration)
                update_connection_counts

                # Trigger connection acquired event
                trigger_pool_event(:connection_acquired, {
                  pool_name: @pool_name,
                  wait_time: checkout_duration,
                  active_connections: @size - @pool.available,
                  idle_connections: @pool.available,
                  timestamp: Time.now
                })

                result = block.call(conn)

                # Trigger connection released event
                trigger_pool_event(:connection_released, {
                  pool_name: @pool_name,
                  active_connections: @size - @pool.available,
                  idle_connections: @pool.available,
                  timestamp: Time.now
                })

                result
              end
            rescue ConnectionPool::TimeoutError
              @instrumentation.record_pool_exhaustion

              # Trigger pool exhausted event
              trigger_pool_event(:pool_exhausted, {
                pool_name: @pool_name,
                size: @size,
                timeout: @timeout,
                timestamp: Time.now
              })

              raise
            end
          else
            begin
              @pool.with do |conn|
                # Trigger connection acquired event (without metrics)
                trigger_pool_event(:connection_acquired, {
                  pool_name: @pool_name,
                  timestamp: Time.now
                })

                result = block.call(conn)

                # Trigger connection released event (without metrics)
                trigger_pool_event(:connection_released, {
                  pool_name: @pool_name,
                  timestamp: Time.now
                })

                result
              end
            rescue ConnectionPool::TimeoutError
              # Trigger pool exhausted event
              trigger_pool_event(:pool_exhausted, {
                pool_name: @pool_name,
                size: @size,
                timeout: @timeout,
                timestamp: Time.now
              })

              raise
            end
          end
        end

        if @circuit_breaker
          @circuit_breaker.call(&execute_block)
        else
          execute_block.call
        end
      end

      # Close all connections in the pool
      def close(reason: RR::Instrumentation::CloseReason::SHUTDOWN)
        if @instrumentation
          # Count connections before shutdown
          conn_count = @size - @pool.available
          conn_count.times { @instrumentation.record_connection_close(reason) }
        end
        @pool.shutdown(&:close)
      end

      alias shutdown close

      # Number of available connections in the pool
      #
      # @return [Integer]
      def available
        @pool.available
      end

      private

      # Create a new connection with metrics tracking
      def create_connection_with_metrics
        if @instrumentation
          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          conn = create_connection
          duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
          @instrumentation.record_connection_create(duration)
          update_connection_counts

          # Trigger pool connection created event
          trigger_pool_event(:connection_created, {
            pool_name: @pool_name,
            host: @host,
            port: @port,
            duration: duration,
            timestamp: Time.now
          })

          conn
        else
          conn = create_connection

          # Trigger pool connection created event (without metrics)
          trigger_pool_event(:connection_created, {
            pool_name: @pool_name,
            host: @host,
            port: @port,
            timestamp: Time.now
          })

          conn
        end
      end

      # Create a new connection
      def create_connection
        conn = TCP.new(
          host: @host,
          port: @port,
          timeout: @connection_timeout,
          event_dispatcher: @event_dispatcher,
          callback_error_handler: @callback_error_handler,
          async_callbacks: @async_callbacks,
          instrumentation: @instrumentation
        )
        authenticate(conn) if @password
        select_db(conn) if @db.positive?
        conn
      end

      # Authenticate with password
      def authenticate(conn)
        result = conn.call("AUTH", @password)
        raise ConnectionError, result.message if result.is_a?(CommandError)
      end

      # Select database
      def select_db(conn)
        result = conn.call("SELECT", @db.to_s)
        raise ConnectionError, result.message if result.is_a?(CommandError)
      end

      # Update connection counts in instrumentation
      def update_connection_counts
        return unless @instrumentation

        available = @pool.available
        active = @size - available
        @instrumentation.update_connection_counts(active: active, idle: available)
      end

      # Check health if interval has elapsed
      def check_health_if_needed
        return unless @health_check_interval

        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return if @last_health_check && (now - @last_health_check) < @health_check_interval

        @last_health_check = now

        # Perform health check on a connection
        begin
          @pool.with do |conn|
            conn.call("PING")
          end
        rescue StandardError
          # Health check failed - circuit breaker will handle if configured
          raise
        end
      end

      # Trigger pool lifecycle events
      # @api private
      def trigger_pool_event(event_type, event_data)
        return unless @event_dispatcher

        # Track callback execution time if instrumentation is enabled
        start_time = @instrumentation ? Process.clock_gettime(Process::CLOCK_MONOTONIC) : nil

        # Dispatch event
        event = create_pool_event_object(event_type, event_data)
        @event_dispatcher.dispatch(event) if event

        # Record callback metrics
        if @instrumentation && start_time
          duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
          @instrumentation.record_callback_execution("pool_#{event_type}", duration)
        end
      end

      # Create a pool event object from event data
      # @api private
      def create_pool_event_object(event_type, event_data)
        case event_type
        when :pool_created
          PoolCreatedEvent.new(
            pool_name: event_data[:pool_name],
            size: event_data[:size],
            timeout: event_data[:timeout],
            timestamp: event_data[:timestamp]
          )
        when :connection_created
          PoolConnectionCreatedEvent.new(
            pool_name: event_data[:pool_name],
            host: event_data[:host],
            port: event_data[:port],
            duration: event_data[:duration],
            timestamp: event_data[:timestamp]
          )
        when :connection_acquired
          PoolConnectionAcquiredEvent.new(
            pool_name: event_data[:pool_name],
            wait_time: event_data[:wait_time],
            active_connections: event_data[:active_connections],
            idle_connections: event_data[:idle_connections],
            timestamp: event_data[:timestamp]
          )
        when :connection_released
          PoolConnectionReleasedEvent.new(
            pool_name: event_data[:pool_name],
            active_connections: event_data[:active_connections],
            idle_connections: event_data[:idle_connections],
            timestamp: event_data[:timestamp]
          )
        when :pool_exhausted
          PoolExhaustedEvent.new(
            pool_name: event_data[:pool_name],
            size: event_data[:size],
            timeout: event_data[:timeout],
            timestamp: event_data[:timestamp]
          )
        when :pool_reset
          PoolResetEvent.new(
            pool_name: event_data[:pool_name],
            reason: event_data[:reason],
            timestamp: event_data[:timestamp]
          )
        end
      end
    end
  end
end
