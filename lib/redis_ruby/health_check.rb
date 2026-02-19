# frozen_string_literal: true

require "monitor"

module RR
  # Health check system for Active-Active Redis connections
  #
  # Provides a flexible framework for monitoring connection health across
  # multiple database endpoints with configurable policies and callbacks.
  #
  # @example Basic usage with PingHealthCheck
  #   runner = RR::HealthCheckRunner.new(interval: 5.0)
  #
  #   # Add health checks for each database
  #   runner.add_check(database_id: 0, connection: conn1)
  #   runner.add_check(database_id: 1, connection: conn2)
  #
  #   # Register callback for health state changes
  #   runner.on_health_change do |database_id, old_state, new_state|
  #     puts "Database #{database_id}: #{old_state} -> #{new_state}"
  #   end
  #
  #   # Start monitoring
  #   runner.start
  #
  #   # Check health status
  #   runner.healthy?(0)  # => true/false
  #
  #   # Stop monitoring
  #   runner.stop
  #
  # @example Custom health check
  #   class CustomHealthCheck < RR::HealthCheck
  #     def check(connection)
  #       # Custom health check logic
  #       connection.call("INFO", "server")
  #       true
  #     rescue => e
  #       false
  #     end
  #   end
  #
  #   runner = RR::HealthCheckRunner.new(
  #     health_check_class: CustomHealthCheck,
  #     interval: 10.0,
  #     probes: 5,
  #     probe_delay: 0.2,
  #     policy: :majority
  #   )
  #
  module HealthCheck
    # Abstract base class for health checks
    #
    # Subclasses must implement the {#check} method to perform
    # the actual health check logic.
    #
    # @abstract Subclass and override {#check} to implement a custom health check
    class Base
      # Perform a health check on the given connection
      #
      # @param connection [Object] The connection to check
      # @return [Boolean] true if healthy, false otherwise
      # @raise [NotImplementedError] if not implemented by subclass
      def check(connection)
        raise NotImplementedError, "#{self.class}#check must be implemented"
      end
    end

    # PING-based health check
    #
    # Sends a PING command to verify the connection is responsive.
    # This is the default and most common health check for Redis.
    #
    # @example
    #   health_check = RR::HealthCheck::Ping.new
    #   healthy = health_check.check(connection)  # => true/false
    class Ping < Base
      # Check connection health using PING command
      #
      # @param connection [Object] Redis connection object
      # @return [Boolean] true if PING succeeds, false otherwise
      def check(connection)
        return false unless connection&.connected?

        result = connection.call("PING")
        result == "PONG"
      rescue StandardError
        false
      end
    end

    # Background health check runner
    #
    # Runs health checks in a background thread at regular intervals,
    # tracks health state per database, and invokes callbacks when
    # health state changes.
    #
    # Thread-safe and uses monotonic time for accurate intervals.
    #
    # @example Basic usage
    #   runner = RR::HealthCheckRunner.new
    #   runner.add_check(database_id: 0, connection: conn)
    #   runner.start
    #   runner.healthy?(0)  # => true/false
    #   runner.stop
    #
    # @example With custom configuration
    #   runner = RR::HealthCheckRunner.new(
    #     interval: 10.0,           # Check every 10 seconds
    #     probes: 5,                # 5 probes per check
    #     probe_delay: 0.2,         # 200ms between probes
    #     policy: :majority         # >50% must pass
    #   )
    #
    class Runner
      include MonitorMixin

      # Health check policies
      POLICIES = {
        all: ->(passed, total) { passed == total },
        majority: ->(passed, total) { passed > total / 2.0 },
        any: ->(passed, _total) { passed.positive? },
      }.freeze

      DEFAULT_INTERVAL = 5.0
      DEFAULT_PROBES = 3
      DEFAULT_PROBE_DELAY = 0.1
      DEFAULT_POLICY = :all

      attr_reader :interval, :probes, :probe_delay, :policy

      # Initialize a new health check runner
      #
      # @param health_check_class [Class] Health check class to use (default: Ping)
      # @param interval [Float] Seconds between health check cycles (default: 5.0)
      # @param probes [Integer] Number of probes per check cycle (default: 3)
      # @param probe_delay [Float] Seconds between probes (default: 0.1)
      # @param policy [Symbol] Health check policy - :all, :majority, or :any (default: :all)
      # @raise [ArgumentError] if policy is invalid
      def initialize(health_check_class: Ping, interval: DEFAULT_INTERVAL,
                     probes: DEFAULT_PROBES, probe_delay: DEFAULT_PROBE_DELAY,
                     policy: DEFAULT_POLICY)
        super() # Initialize MonitorMixin

        raise ArgumentError, "Invalid policy: #{policy}" unless POLICIES.key?(policy)
        raise ArgumentError, "Interval must be positive" unless interval.positive?
        raise ArgumentError, "Probes must be positive" unless probes.positive?
        raise ArgumentError, "Probe delay must be non-negative" unless probe_delay >= 0

        @health_check = health_check_class.new
        @interval = interval
        @probes = probes
        @probe_delay = probe_delay
        @policy = policy
        @policy_fn = POLICIES[policy]

        # Thread-safe state
        @checks = {} # database_id => connection
        @health_state = {} # database_id => boolean
        @callbacks = []
        @running = false
        @thread = nil
        @stop_requested = false
      end

      # Add a health check for a database connection
      #
      # @param database_id [Object] Unique identifier for the database
      # @param connection [Object] Connection object to check
      # @return [void]
      def add_check(database_id:, connection:)
        synchronize do
          @checks[database_id] = connection
          @health_state[database_id] = false # Start as unhealthy until first check
        end
      end

      # Remove a health check for a database
      #
      # @param database_id [Object] Database identifier
      # @return [void]
      def remove_check(database_id)
        synchronize do
          @checks.delete(database_id)
          @health_state.delete(database_id)
        end
      end

      # Check if a database is healthy
      #
      # @param database_id [Object] Database identifier
      # @return [Boolean] true if healthy, false otherwise
      def healthy?(database_id)
        synchronize { @health_state.fetch(database_id, false) }
      end

      # Register a callback for health state changes
      #
      # The callback will be invoked whenever a database's health state changes.
      #
      # @yield [database_id, old_state, new_state] Callback block
      # @yieldparam database_id [Object] Database identifier
      # @yieldparam old_state [Boolean] Previous health state
      # @yieldparam new_state [Boolean] New health state
      # @return [void]
      #
      # @example
      #   runner.on_health_change do |db_id, old_state, new_state|
      #     if new_state
      #       puts "Database #{db_id} is now healthy"
      #     else
      #       puts "Database #{db_id} is now unhealthy"
      #     end
      #   end
      def on_health_change(&block)
        synchronize { @callbacks << block }
      end

      # Start the health check runner
      #
      # Starts a background thread that runs health checks at the configured interval.
      # Does nothing if already running.
      #
      # @return [Thread] The background thread
      def start
        synchronize do
          return @thread if @running

          @running = true
          @stop_requested = false
          @thread = Thread.new { run_health_checks }
        end

        @thread
      end

      # Stop the health check runner
      #
      # Gracefully stops the background thread.
      #
      # @param wait [Boolean] Wait for thread to finish (default: true)
      # @return [void]
      def stop(wait: true)
        synchronize do
          return unless @running

          @stop_requested = true
        end

        @thread&.join if wait
      end

      # Check if the runner is currently running
      #
      # @return [Boolean] true if running, false otherwise
      def running?
        synchronize { @running }
      end

      private

      # Main health check loop (runs in background thread)
      def run_health_checks
        loop do
          break if @stop_requested

          cycle_start = monotonic_time
          perform_health_checks
          sleep_until_next_cycle(cycle_start)
        end
      ensure
        synchronize { @running = false }
      end

      # Perform health checks for all databases
      def perform_health_checks
        checks_snapshot = synchronize { @checks.dup }

        checks_snapshot.each do |database_id, connection|
          new_state = check_database_health(connection)
          update_health_state(database_id, new_state)
        end
      end

      # Check health of a single database using multiple probes
      #
      # @param connection [Object] Connection to check
      # @return [Boolean] true if healthy according to policy, false otherwise
      def check_database_health(connection)
        passed = 0

        @probes.times do |i|
          passed += 1 if @health_check.check(connection)
          sleep(@probe_delay) if i < @probes - 1 && @probe_delay.positive?
        end

        @policy_fn.call(passed, @probes)
      end

      # Update health state and invoke callbacks if changed
      #
      # @param database_id [Object] Database identifier
      # @param new_state [Boolean] New health state
      # @return [void]
      def update_health_state(database_id, new_state)
        old_state = nil
        callbacks_to_invoke = nil

        synchronize do
          old_state = @health_state[database_id]
          return if old_state == new_state # No change

          @health_state[database_id] = new_state
          callbacks_to_invoke = @callbacks.dup
        end

        # Invoke callbacks outside the lock to avoid deadlocks
        invoke_callbacks(callbacks_to_invoke, database_id, old_state, new_state)
      end

      # Invoke health change callbacks
      #
      # @param callbacks [Array<Proc>] Callbacks to invoke
      # @param database_id [Object] Database identifier
      # @param old_state [Boolean] Previous health state
      # @param new_state [Boolean] New health state
      # @return [void]
      def invoke_callbacks(callbacks, database_id, old_state, new_state)
        callbacks.each do |callback|
          callback.call(database_id, old_state, new_state)
        rescue StandardError => e
          warn "Error in health check callback: #{e.message}"
        end
      end

      # Sleep until the next health check cycle
      #
      # @param cycle_start [Float] Monotonic time when cycle started
      # @return [void]
      def sleep_until_next_cycle(cycle_start)
        elapsed = monotonic_time - cycle_start
        sleep_time = [@interval - elapsed, 0].max
        sleep(sleep_time) if sleep_time.positive? && !@stop_requested
      end

      # Get monotonic time for accurate intervals
      #
      # @return [Float] Monotonic time in seconds
      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end

# Load additional health check implementations
require_relative "health_check/lag_aware"
require_relative "health_check/rest_api"
