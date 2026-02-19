# frozen_string_literal: true

module RR
  # Base class for all events in the event system.
  #
  # Events are immutable objects that represent something that happened in the system.
  # All event classes should inherit from this base class.
  #
  # @abstract Subclass and add specific attributes for your event type
  class Event
    # @return [Time] When the event occurred
    attr_reader :timestamp

    # Initialize a new event.
    #
    # @param timestamp [Time] When the event occurred (defaults to current time)
    def initialize(timestamp: Time.now)
      @timestamp = timestamp
      freeze # Make events immutable
    end

    # String representation of the event.
    #
    # @return [String]
    def to_s
      attrs = instance_variables.map do |var|
        "#{var}=#{instance_variable_get(var).inspect}"
      end.join(", ")
      "#<#{self.class.name} #{attrs}>"
    end

    alias inspect to_s
  end

  # ============================================================
  # Connection Lifecycle Events
  # ============================================================

  # Event fired when a connection is created (before connecting).
  #
  # @example
  #   event = ConnectionCreatedEvent.new(
  #     host: "localhost",
  #     port: 6379
  #   )
  class ConnectionCreatedEvent < Event
    # @return [String] Redis host
    attr_reader :host

    # @return [Integer] Redis port
    attr_reader :port

    # @return [String, nil] Unix socket path (if applicable)
    attr_reader :path

    # Initialize a new connection created event.
    #
    # @param host [String, nil] Redis host
    # @param port [Integer, nil] Redis port
    # @param path [String, nil] Unix socket path
    # @param timestamp [Time] When the event occurred (defaults to current time)
    def initialize(host: nil, port: nil, path: nil, timestamp: Time.now)
      @host = host
      @port = port
      @path = path
      super(timestamp: timestamp)
    end
  end

  # Event fired when a connection successfully connects to Redis.
  #
  # @example
  #   event = ConnectionConnectedEvent.new(
  #     host: "localhost",
  #     port: 6379,
  #     first_connection: true
  #   )
  class ConnectionConnectedEvent < Event
    # @return [String] Redis host
    attr_reader :host

    # @return [Integer] Redis port
    attr_reader :port

    # @return [String, nil] Unix socket path (if applicable)
    attr_reader :path

    # @return [Boolean] Whether this is the first connection (vs reconnection)
    attr_reader :first_connection

    # Initialize a new connection connected event.
    #
    # @param host [String, nil] Redis host
    # @param port [Integer, nil] Redis port
    # @param path [String, nil] Unix socket path
    # @param first_connection [Boolean] Whether this is the first connection
    # @param timestamp [Time] When the event occurred (defaults to current time)
    def initialize(host: nil, port: nil, path: nil, first_connection: true, timestamp: Time.now)
      @host = host
      @port = port
      @path = path
      @first_connection = first_connection
      super(timestamp: timestamp)
    end
  end

  # Event fired when a connection is disconnected.
  #
  # @example
  #   event = ConnectionDisconnectedEvent.new(
  #     host: "localhost",
  #     port: 6379,
  #     reason: "client_disconnect"
  #   )
  class ConnectionDisconnectedEvent < Event
    # @return [String] Redis host
    attr_reader :host

    # @return [Integer] Redis port
    attr_reader :port

    # @return [String, nil] Unix socket path (if applicable)
    attr_reader :path

    # @return [String, nil] Reason for disconnection
    attr_reader :reason

    # Initialize a new connection disconnected event.
    #
    # @param host [String, nil] Redis host
    # @param port [Integer, nil] Redis port
    # @param path [String, nil] Unix socket path
    # @param reason [String, nil] Reason for disconnection
    # @param timestamp [Time] When the event occurred (defaults to current time)
    def initialize(host: nil, port: nil, path: nil, reason: nil, timestamp: Time.now)
      @host = host
      @port = port
      @path = path
      @reason = reason
      super(timestamp: timestamp)
    end
  end

  # Event fired when a connection error occurs.
  #
  # @example
  #   event = ConnectionErrorEvent.new(
  #     host: "localhost",
  #     port: 6379,
  #     error: StandardError.new("Connection refused")
  #   )
  class ConnectionErrorEvent < Event
    # @return [String] Redis host
    attr_reader :host

    # @return [Integer] Redis port
    attr_reader :port

    # @return [String, nil] Unix socket path (if applicable)
    attr_reader :path

    # @return [Exception] The error that occurred
    attr_reader :error

    # Initialize a new connection error event.
    #
    # @param host [String, nil] Redis host
    # @param port [Integer, nil] Redis port
    # @param path [String, nil] Unix socket path
    # @param error [Exception] The error that occurred
    # @param timestamp [Time] When the event occurred (defaults to current time)
    def initialize(error:, host: nil, port: nil, path: nil, timestamp: Time.now)
      @host = host
      @port = port
      @path = path
      @error = error
      super(timestamp: timestamp)
    end
  end

  # Event fired when a connection health check is performed.
  #
  # @example
  #   event = ConnectionHealthCheckEvent.new(
  #     host: "localhost",
  #     port: 6379,
  #     healthy: true,
  #     latency: 0.001
  #   )
  class ConnectionHealthCheckEvent < Event
    # @return [String] Redis host
    attr_reader :host

    # @return [Integer] Redis port
    attr_reader :port

    # @return [String, nil] Unix socket path (if applicable)
    attr_reader :path

    # @return [Boolean] Whether the health check passed
    attr_reader :healthy

    # @return [Float, nil] Health check latency in seconds
    attr_reader :latency

    # Initialize a new connection health check event.
    #
    # @param host [String, nil] Redis host
    # @param port [Integer, nil] Redis port
    # @param path [String, nil] Unix socket path
    # @param healthy [Boolean] Whether the health check passed
    # @param latency [Float, nil] Health check latency in seconds
    # @param timestamp [Time] When the event occurred (defaults to current time)
    def initialize(healthy:, host: nil, port: nil, path: nil, latency: nil, timestamp: Time.now)
      @host = host
      @port = port
      @path = path
      @healthy = healthy
      @latency = latency
      super(timestamp: timestamp)
    end
  end

  # Event fired when a connection is marked for reconnection.
  #
  # @example
  #   event = ConnectionMarkedForReconnectEvent.new(
  #     host: "localhost",
  #     port: 6379,
  #     reason: "fork_detected"
  #   )
  class ConnectionMarkedForReconnectEvent < Event
    # @return [String] Redis host
    attr_reader :host

    # @return [Integer] Redis port
    attr_reader :port

    # @return [String, nil] Unix socket path (if applicable)
    attr_reader :path

    # @return [String] Reason for marking reconnection
    attr_reader :reason

    # Initialize a new connection marked for reconnect event.
    #
    # @param host [String, nil] Redis host
    # @param port [Integer, nil] Redis port
    # @param path [String, nil] Unix socket path
    # @param reason [String] Reason for marking reconnection
    # @param timestamp [Time] When the event occurred (defaults to current time)
    def initialize(reason:, host: nil, port: nil, path: nil, timestamp: Time.now)
      @host = host
      @port = port
      @path = path
      @reason = reason
      super(timestamp: timestamp)
    end
  end

  # ============================================================
  # Connection Pool Lifecycle Events
  # ============================================================

  # Event fired when a connection pool is created.
  #
  # @example
  #   event = PoolCreatedEvent.new(
  #     pool_name: "localhost:6379",
  #     size: 10,
  #     timeout: 5.0
  #   )
  class PoolCreatedEvent < Event
    # @return [String] Pool name/identifier
    attr_reader :pool_name

    # @return [Integer] Maximum pool size
    attr_reader :size

    # @return [Float] Pool timeout in seconds
    attr_reader :timeout

    # Initialize a new pool created event.
    #
    # @param pool_name [String] Pool name/identifier
    # @param size [Integer] Maximum pool size
    # @param timeout [Float] Pool timeout in seconds
    # @param timestamp [Time] When the event occurred (defaults to current time)
    def initialize(pool_name:, size:, timeout:, timestamp: Time.now)
      @pool_name = pool_name
      @size = size
      @timeout = timeout
      super(timestamp: timestamp)
    end
  end

  # Event fired when a pool creates a new connection.
  #
  # @example
  #   event = PoolConnectionCreatedEvent.new(
  #     pool_name: "localhost:6379",
  #     host: "localhost",
  #     port: 6379,
  #     duration: 0.05
  #   )
  class PoolConnectionCreatedEvent < Event
    # @return [String] Pool name/identifier
    attr_reader :pool_name

    # @return [String] Redis host
    attr_reader :host

    # @return [Integer] Redis port
    attr_reader :port

    # @return [String, nil] Unix socket path (if applicable)
    attr_reader :path

    # @return [Float, nil] Time to create connection in seconds
    attr_reader :duration

    # Initialize a new pool connection created event.
    #
    # @param pool_name [String] Pool name/identifier
    # @param host [String, nil] Redis host
    # @param port [Integer, nil] Redis port
    # @param path [String, nil] Unix socket path
    # @param duration [Float, nil] Time to create connection in seconds
    # @param timestamp [Time] When the event occurred (defaults to current time)
    def initialize(pool_name:, host: nil, port: nil, path: nil, duration: nil, timestamp: Time.now)
      @pool_name = pool_name
      @host = host
      @port = port
      @path = path
      @duration = duration
      super(timestamp: timestamp)
    end
  end

  # Event fired when a connection is acquired from the pool.
  #
  # @example
  #   event = PoolConnectionAcquiredEvent.new(
  #     pool_name: "localhost:6379",
  #     wait_time: 0.001,
  #     active_connections: 5,
  #     idle_connections: 5
  #   )
  class PoolConnectionAcquiredEvent < Event
    # @return [String] Pool name/identifier
    attr_reader :pool_name

    # @return [Float, nil] Time waiting for connection in seconds
    attr_reader :wait_time

    # @return [Integer, nil] Number of active connections
    attr_reader :active_connections

    # @return [Integer, nil] Number of idle connections
    attr_reader :idle_connections

    # Initialize a new pool connection acquired event.
    #
    # @param pool_name [String] Pool name/identifier
    # @param wait_time [Float, nil] Time waiting for connection in seconds
    # @param active_connections [Integer, nil] Number of active connections
    # @param idle_connections [Integer, nil] Number of idle connections
    # @param timestamp [Time] When the event occurred (defaults to current time)
    def initialize(pool_name:, wait_time: nil, active_connections: nil, idle_connections: nil, timestamp: Time.now)
      @pool_name = pool_name
      @wait_time = wait_time
      @active_connections = active_connections
      @idle_connections = idle_connections
      super(timestamp: timestamp)
    end
  end

  # Event fired when a connection is released back to the pool.
  #
  # @example
  #   event = PoolConnectionReleasedEvent.new(
  #     pool_name: "localhost:6379",
  #     active_connections: 4,
  #     idle_connections: 6
  #   )
  class PoolConnectionReleasedEvent < Event
    # @return [String] Pool name/identifier
    attr_reader :pool_name

    # @return [Integer, nil] Number of active connections
    attr_reader :active_connections

    # @return [Integer, nil] Number of idle connections
    attr_reader :idle_connections

    # Initialize a new pool connection released event.
    #
    # @param pool_name [String] Pool name/identifier
    # @param active_connections [Integer, nil] Number of active connections
    # @param idle_connections [Integer, nil] Number of idle connections
    # @param timestamp [Time] When the event occurred (defaults to current time)
    def initialize(pool_name:, active_connections: nil, idle_connections: nil, timestamp: Time.now)
      @pool_name = pool_name
      @active_connections = active_connections
      @idle_connections = idle_connections
      super(timestamp: timestamp)
    end
  end

  # Event fired when the pool is exhausted (no connections available).
  #
  # @example
  #   event = PoolExhaustedEvent.new(
  #     pool_name: "localhost:6379",
  #     size: 10,
  #     timeout: 5.0
  #   )
  class PoolExhaustedEvent < Event
    # @return [String] Pool name/identifier
    attr_reader :pool_name

    # @return [Integer] Maximum pool size
    attr_reader :size

    # @return [Float] Pool timeout in seconds
    attr_reader :timeout

    # Initialize a new pool exhausted event.
    #
    # @param pool_name [String] Pool name/identifier
    # @param size [Integer] Maximum pool size
    # @param timeout [Float] Pool timeout in seconds
    # @param timestamp [Time] When the event occurred (defaults to current time)
    def initialize(pool_name:, size:, timeout:, timestamp: Time.now)
      @pool_name = pool_name
      @size = size
      @timeout = timeout
      super(timestamp: timestamp)
    end
  end

  # Event fired when the pool is reset (e.g., after fork).
  #
  # @example
  #   event = PoolResetEvent.new(
  #     pool_name: "localhost:6379",
  #     reason: "fork_detected"
  #   )
  class PoolResetEvent < Event
    # @return [String] Pool name/identifier
    attr_reader :pool_name

    # @return [String] Reason for reset
    attr_reader :reason

    # Initialize a new pool reset event.
    #
    # @param pool_name [String] Pool name/identifier
    # @param reason [String] Reason for reset
    # @param timestamp [Time] When the event occurred (defaults to current time)
    def initialize(pool_name:, reason:, timestamp: Time.now)
      @pool_name = pool_name
      @reason = reason
      super(timestamp: timestamp)
    end
  end

  # ============================================================
  # Active-Active Database Events
  # ============================================================

  # Event fired when a database fails.
  #
  # This event is dispatched when a database becomes unavailable or encounters
  # a critical error that prevents it from serving requests.
  #
  # @example
  #   event = DatabaseFailedEvent.new(
  #     database_id: "db-1",
  #     region: "us-east-1",
  #     error: "Connection timeout"
  #   )
  class DatabaseFailedEvent < Event
    # @return [String] Unique identifier for the database
    attr_reader :database_id

    # @return [String] Geographic region of the database
    attr_reader :region

    # @return [String] Error message or description
    attr_reader :error

    # Initialize a new database failed event.
    #
    # @param database_id [String] Unique identifier for the database
    # @param region [String] Geographic region of the database
    # @param error [String] Error message or description
    # @param timestamp [Time] When the event occurred (defaults to current time)
    def initialize(database_id:, region:, error:, timestamp: Time.now)
      @database_id = database_id
      @region = region
      @error = error
      super(timestamp: timestamp)
    end
  end

  # Event fired when a database recovers from a failure.
  #
  # This event is dispatched when a previously failed database becomes healthy
  # and available again.
  #
  # @example
  #   event = DatabaseRecoveredEvent.new(
  #     database_id: "db-1",
  #     region: "us-east-1"
  #   )
  class DatabaseRecoveredEvent < Event
    # @return [String] Unique identifier for the database
    attr_reader :database_id

    # @return [String] Geographic region of the database
    attr_reader :region

    # Initialize a new database recovered event.
    #
    # @param database_id [String] Unique identifier for the database
    # @param region [String] Geographic region of the database
    # @param timestamp [Time] When the event occurred (defaults to current time)
    def initialize(database_id:, region:, timestamp: Time.now)
      @database_id = database_id
      @region = region
      super(timestamp: timestamp)
    end
  end

  # Event fired when a failover occurs between databases.
  #
  # This event is dispatched when the client switches from one database to another,
  # typically due to a failure or manual intervention.
  #
  # @example
  #   event = FailoverEvent.new(
  #     from_database_id: "db-1",
  #     to_database_id: "db-2",
  #     from_region: "us-east-1",
  #     to_region: "us-west-2",
  #     reason: "Connection timeout"
  #   )
  class FailoverEvent < Event
    # @return [String] Database ID we're failing over from
    attr_reader :from_database_id

    # @return [String] Database ID we're failing over to
    attr_reader :to_database_id

    # @return [String] Region we're failing over from
    attr_reader :from_region

    # @return [String] Region we're failing over to
    attr_reader :to_region

    # @return [String] Reason for the failover
    attr_reader :reason

    # Initialize a new failover event.
    #
    # @param from_database_id [String] Database ID we're failing over from
    # @param to_database_id [String] Database ID we're failing over to
    # @param from_region [String] Region we're failing over from
    # @param to_region [String] Region we're failing over to
    # @param reason [String] Reason for the failover
    # @param timestamp [Time] When the event occurred (defaults to current time)
    def initialize(from_database_id:, to_database_id:, from_region:, to_region:,
                   reason:, timestamp: Time.now)
      @from_database_id = from_database_id
      @to_database_id = to_database_id
      @from_region = from_region
      @to_region = to_region
      @reason = reason
      super(timestamp: timestamp)
    end
  end

  # Thread-safe event dispatcher for managing and dispatching events.
  #
  # The EventDispatcher allows you to register listeners (callbacks) for specific
  # event types and dispatch events to all registered listeners. It's designed to
  # be thread-safe and resilient - errors in individual listeners won't crash the
  # system or prevent other listeners from being notified.
  #
  # Inspired by redis-py's event system, adapted to idiomatic Ruby style with
  # block-based callbacks.
  #
  # @example Basic usage
  #   dispatcher = RR::EventDispatcher.new
  #
  #   # Register a listener for database failures
  #   dispatcher.on(RR::DatabaseFailedEvent) do |event|
  #     puts "Database #{event.database_id} in #{event.region} failed: #{event.error}"
  #     # Send alert, log to monitoring system, etc.
  #   end
  #
  #   # Register a listener for failovers
  #   dispatcher.on(RR::FailoverEvent) do |event|
  #     puts "Failing over from #{event.from_region} to #{event.to_region}"
  #   end
  #
  #   # Dispatch an event
  #   event = RR::DatabaseFailedEvent.new(
  #     database_id: "db-1",
  #     region: "us-east-1",
  #     error: "Connection timeout"
  #   )
  #   dispatcher.dispatch(event)
  #
  # @example Multiple listeners for the same event
  #   dispatcher = RR::EventDispatcher.new
  #
  #   # Log to file
  #   dispatcher.on(RR::DatabaseFailedEvent) do |event|
  #     File.open("failures.log", "a") do |f|
  #       f.puts "[#{event.timestamp}] #{event.database_id}: #{event.error}"
  #     end
  #   end
  #
  #   # Send alert
  #   dispatcher.on(RR::DatabaseFailedEvent) do |event|
  #     AlertService.send_alert("Database failure", event.to_s)
  #   end
  #
  #   # Update metrics
  #   dispatcher.on(RR::DatabaseFailedEvent) do |event|
  #     Metrics.increment("database.failures", tags: ["region:#{event.region}"])
  #   end
  #
  # @example Error handling
  #   dispatcher = RR::EventDispatcher.new
  #
  #   # This listener will raise an error
  #   dispatcher.on(RR::DatabaseFailedEvent) do |event|
  #     raise "Oops!"
  #   end
  #
  #   # This listener will still be called despite the error above
  #   dispatcher.on(RR::DatabaseFailedEvent) do |event|
  #     puts "This will still execute"
  #   end
  #
  #   # Errors are logged but don't crash the system
  #   dispatcher.dispatch(RR::DatabaseFailedEvent.new(
  #     database_id: "db-1",
  #     region: "us-east-1",
  #     error: "Test"
  #   ))
  #
  class EventDispatcher
    # Initialize a new event dispatcher.
    #
    # @param logger [Logger, nil] Optional logger for error reporting
    def initialize(logger: nil)
      @listeners = Hash.new { |h, k| h[k] = [] }
      @mutex = Mutex.new
      @logger = logger
    end

    # Register a listener for a specific event type.
    #
    # The listener block will be called whenever an event of the specified type
    # is dispatched. Multiple listeners can be registered for the same event type.
    #
    # @param event_class [Class] The event class to listen for (must inherit from Event)
    # @param block [Proc] The callback to execute when the event is dispatched
    # @return [Proc] The registered listener block
    # @raise [ArgumentError] If event_class is not an Event subclass or no block given
    #
    # @example
    #   dispatcher.on(DatabaseFailedEvent) do |event|
    #     puts "Database failed: #{event.database_id}"
    #   end
    def on(event_class, &block)
      raise ArgumentError, "event_class must be a subclass of Event" unless event_class < Event
      raise ArgumentError, "block required" unless block

      @mutex.synchronize do
        @listeners[event_class] << block
      end

      block
    end

    # Alias for {#on} to provide a more familiar API for some users.
    #
    # @see #on
    alias subscribe on

    # Dispatch an event to all registered listeners.
    #
    # Calls all listeners registered for the event's class. If a listener raises
    # an error, the error is logged (if a logger is configured) but does not
    # prevent other listeners from being called.
    #
    # Thread-safe: Multiple threads can dispatch events concurrently.
    #
    # @param event [Event] The event to dispatch
    # @return [Integer] Number of listeners that were notified
    # @raise [ArgumentError] If event is not an Event instance
    #
    # @example
    #   event = DatabaseFailedEvent.new(
    #     database_id: "db-1",
    #     region: "us-east-1",
    #     error: "Connection timeout"
    #   )
    #   dispatcher.dispatch(event)
    def dispatch(event)
      raise ArgumentError, "event must be an Event instance" unless event.is_a?(Event)

      # Get a snapshot of listeners for this event type
      listeners_snapshot = @mutex.synchronize do
        @listeners[event.class].dup
      end

      # Call each listener outside the mutex to avoid blocking other dispatches
      listeners_snapshot.each do |listener|
        call_listener(listener, event)
      end

      listeners_snapshot.size
    end

    # Clear all listeners for a specific event type, or all listeners if no type specified.
    #
    # @param event_class [Class, nil] The event class to clear listeners for, or nil for all
    # @return [Integer] Number of listeners that were removed
    #
    # @example Clear listeners for a specific event type
    #   dispatcher.clear_listeners(DatabaseFailedEvent)
    #
    # @example Clear all listeners
    #   dispatcher.clear_listeners
    def clear_listeners(event_class = nil)
      @mutex.synchronize do
        if event_class.nil?
          count = @listeners.values.sum(&:size)
          @listeners.clear
        else
          raise ArgumentError, "event_class must be a subclass of Event" unless event_class < Event

          count = @listeners[event_class].size
          @listeners.delete(event_class)
        end
        count
      end
    end

    # Get the number of listeners registered for a specific event type.
    #
    # @param event_class [Class] The event class to count listeners for
    # @return [Integer] Number of registered listeners
    # @raise [ArgumentError] If event_class is not an Event subclass
    #
    # @example
    #   count = dispatcher.listener_count(DatabaseFailedEvent)
    #   puts "#{count} listeners registered for database failures"
    def listener_count(event_class)
      raise ArgumentError, "event_class must be a subclass of Event" unless event_class < Event

      @mutex.synchronize do
        @listeners[event_class].size
      end
    end

    # Check if any listeners are registered for a specific event type.
    #
    # @param event_class [Class] The event class to check
    # @return [Boolean] true if at least one listener is registered
    # @raise [ArgumentError] If event_class is not an Event subclass
    #
    # @example
    #   if dispatcher.listeners?(DatabaseFailedEvent)
    #     puts "Someone is listening for database failures"
    #   end
    def listeners?(event_class)
      listener_count(event_class).positive?
    end

    private

    # Call a listener with an event, catching and logging any errors.
    #
    # Errors in listeners are caught and logged (if a logger is configured)
    # to prevent one failing listener from affecting others.
    #
    # @param listener [Proc] The listener to call
    # @param event [Event] The event to pass to the listener
    def call_listener(listener, event)
      listener.call(event)
    rescue StandardError => e
      log_listener_error(e, event)
    end

    # Log an error that occurred in a listener.
    #
    # @param error [StandardError] The error that occurred
    # @param event [Event] The event that was being processed
    def log_listener_error(error, event)
      return unless @logger

      @logger.error(
        "Error in event listener for #{event.class.name}: #{error.class.name}: #{error.message}"
      )
      @logger.error(error.backtrace.join("\n")) if error.backtrace
    end
  end
end
