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
        assign_connection_params(host, port, size, pool_timeout, connection_timeout, password, db)
        assign_instrumentation_params(instrumentation, pool_name, host, port)
        assign_event_params(circuit_breaker, health_check_interval, event_dispatcher,
                            callback_error_handler, async_callbacks)
        @pool = ConnectionPool.new(size: size, timeout: pool_timeout) { create_connection_with_metrics }
        trigger_pool_event(:pool_created,
                           { pool_name: @pool_name, size: @size, timeout: @timeout, timestamp: Time.now })
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
        check_health_if_needed
        if @circuit_breaker
          @circuit_breaker.call { execute_pool_operation(block) }
        else
          execute_pool_operation(block)
        end
      end

      # Close all connections in the pool
      def close(reason: RR::Instrumentation::CloseReason::SHUTDOWN)
        if @instrumentation
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

      # Map of pool event types to builder lambdas
      POOL_EVENT_BUILDERS = {
        pool_created: lambda { |d|
          PoolCreatedEvent.new(pool_name: d[:pool_name], size: d[:size], timeout: d[:timeout], timestamp: d[:timestamp])
        },
        connection_created: lambda { |d|
          PoolConnectionCreatedEvent.new(
            pool_name: d[:pool_name], host: d[:host], port: d[:port],
            duration: d[:duration], timestamp: d[:timestamp]
          )
        },
        connection_acquired: lambda { |d|
          PoolConnectionAcquiredEvent.new(
            pool_name: d[:pool_name], wait_time: d[:wait_time],
            active_connections: d[:active_connections],
            idle_connections: d[:idle_connections], timestamp: d[:timestamp]
          )
        },
        connection_released: lambda { |d|
          PoolConnectionReleasedEvent.new(pool_name: d[:pool_name], active_connections: d[:active_connections],
                                          idle_connections: d[:idle_connections], timestamp: d[:timestamp])
        },
        pool_exhausted: lambda { |d|
          PoolExhaustedEvent.new(pool_name: d[:pool_name], size: d[:size], timeout: d[:timeout],
                                 timestamp: d[:timestamp])
        },
        pool_reset: lambda { |d|
          PoolResetEvent.new(pool_name: d[:pool_name], reason: d[:reason], timestamp: d[:timestamp])
        },
      }.freeze

      private

      # Assign core connection parameters
      def assign_connection_params(host, port, size, pool_timeout, connection_timeout, password, db)
        @host = host
        @port = port
        @size = size
        @timeout = pool_timeout
        @connection_timeout = connection_timeout
        @password = password
        @db = db
      end

      # Assign instrumentation parameters
      def assign_instrumentation_params(instrumentation, pool_name, host, port)
        @instrumentation = instrumentation
        @pool_name = pool_name || "#{host}:#{port}"
      end

      # Assign event and health check parameters
      def assign_event_params(circuit_breaker, health_check_interval, event_dispatcher,
                              callback_error_handler, async_callbacks)
        @circuit_breaker = circuit_breaker
        @health_check_interval = health_check_interval
        @last_health_check = nil
        @event_dispatcher = event_dispatcher
        @callback_error_handler = callback_error_handler || CallbackErrorHandler.new(strategy: :log)
        @async_callbacks = async_callbacks
      end

      # Execute pool operation with optional instrumentation
      def execute_pool_operation(block)
        if @instrumentation
          execute_pool_with_instrumentation(block)
        else
          execute_pool_without_instrumentation(block)
        end
      end

      # Execute pool operation with instrumentation metrics
      def execute_pool_with_instrumentation(block)
        checkout_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @pool.with do |conn|
          record_checkout_metrics(checkout_start)
          result = block.call(conn)
          trigger_pool_event(:connection_released, pool_connection_data)
          result
        end
      rescue ConnectionPool::TimeoutError
        @instrumentation.record_pool_exhaustion
        trigger_pool_event(:pool_exhausted, pool_exhaustion_data)
        raise
      end

      # Execute pool operation without instrumentation
      def execute_pool_without_instrumentation(block)
        @pool.with do |conn|
          trigger_pool_event(:connection_acquired, { pool_name: @pool_name, timestamp: Time.now })
          result = block.call(conn)
          trigger_pool_event(:connection_released, { pool_name: @pool_name, timestamp: Time.now })
          result
        end
      rescue ConnectionPool::TimeoutError
        trigger_pool_event(:pool_exhausted, pool_exhaustion_data)
        raise
      end

      # Record checkout metrics and trigger acquired event
      def record_checkout_metrics(checkout_start)
        checkout_duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - checkout_start
        @instrumentation.record_connection_checkout(checkout_duration)
        update_connection_counts
        trigger_pool_event(:connection_acquired, pool_connection_data.merge(wait_time: checkout_duration))
      end

      # Build common pool connection data hash
      def pool_connection_data
        { pool_name: @pool_name, active_connections: @size - @pool.available,
          idle_connections: @pool.available, timestamp: Time.now, }
      end

      # Build pool exhaustion data hash
      def pool_exhaustion_data
        { pool_name: @pool_name, size: @size, timeout: @timeout, timestamp: Time.now }
      end

      # Create a new connection with metrics tracking
      def create_connection_with_metrics
        if @instrumentation
          create_connection_instrumented
        else
          conn = create_connection
          trigger_pool_event(:connection_created, connection_created_data)
          conn
        end
      end

      # Create connection with instrumentation recording
      def create_connection_instrumented
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        conn = create_connection
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        @instrumentation.record_connection_create(duration)
        update_connection_counts
        trigger_pool_event(:connection_created, connection_created_data.merge(duration: duration))
        conn
      end

      # Build connection created event data
      def connection_created_data
        { pool_name: @pool_name, host: @host, port: @port, timestamp: Time.now }
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
        @pool.with { |conn| conn.call("PING") }
      end

      # Trigger pool lifecycle events
      def trigger_pool_event(event_type, event_data)
        return unless @event_dispatcher

        start_time = @instrumentation ? Process.clock_gettime(Process::CLOCK_MONOTONIC) : nil
        event = create_pool_event_object(event_type, event_data)
        @event_dispatcher.dispatch(event) if event
        return unless @instrumentation && start_time

        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        @instrumentation.record_callback_execution("pool_#{event_type}", duration)
      end

      def create_pool_event_object(event_type, event_data)
        POOL_EVENT_BUILDERS.fetch(event_type, nil)&.call(event_data)
      end
    end
  end
end
