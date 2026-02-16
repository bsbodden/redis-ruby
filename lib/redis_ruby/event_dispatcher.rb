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
          count
        else
          raise ArgumentError, "event_class must be a subclass of Event" unless event_class < Event

          count = @listeners[event_class].size
          @listeners.delete(event_class)
          count
        end
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
      listener_count(event_class) > 0
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


