# frozen_string_literal: true

require "monitor"

module RR
  # Production-ready circuit breaker implementation for Redis connections.
  #
  # Implements the circuit breaker pattern to prevent cascading failures by
  # temporarily blocking operations when a failure threshold is reached, allowing
  # the system to recover gracefully.
  #
  # The circuit breaker operates in three states:
  # - **CLOSED** (healthy): Normal operation. Requests pass through. Failures are
  #   counted, and after reaching the failure threshold, transitions to OPEN.
  # - **OPEN** (unhealthy): Circuit is open. All requests fail immediately without
  #   executing. After the reset timeout expires, transitions to HALF_OPEN.
  # - **HALF_OPEN** (testing recovery): Limited requests are allowed to test if
  #   the service has recovered. After reaching the success threshold, transitions
  #   to CLOSED. Any failure immediately transitions back to OPEN.
  #
  # Thread-safe using Mutex for synchronization. Uses monotonic time for accurate
  # timeout tracking that is not affected by system clock changes.
  #
  # Inspired by redis-py's circuit breaker implementation, adapted to idiomatic Ruby.
  #
  # @example Basic usage
  #   breaker = RR::CircuitBreaker.new(
  #     failure_threshold: 5,
  #     reset_timeout: 60,
  #     success_threshold: 2
  #   )
  #
  #   begin
  #     result = breaker.call do
  #       redis.get("key")
  #     end
  #   rescue RR::CircuitBreakerOpenError
  #     # Circuit is open, handle gracefully
  #     puts "Service unavailable, using fallback"
  #   end
  #
  # @example Checking circuit state
  #   if breaker.open?
  #     puts "Circuit is open, service is unhealthy"
  #   elsif breaker.half_open?
  #     puts "Circuit is testing recovery"
  #   else
  #     puts "Circuit is closed, service is healthy"
  #   end
  #
  # @example Manual control
  #   breaker.trip!   # Manually open the circuit
  #   breaker.reset!  # Manually close the circuit
  #
  class CircuitBreaker
    # Circuit breaker states
    STATE_CLOSED = :closed
    STATE_OPEN = :open
    STATE_HALF_OPEN = :half_open

    attr_reader :failure_count, :success_count, :state

    # Initialize a new circuit breaker.
    #
    # @param failure_threshold [Integer] Number of consecutive failures before
    #   opening the circuit (default: 5)
    # @param reset_timeout [Numeric] Seconds to wait in OPEN state before
    #   transitioning to HALF_OPEN (default: 60)
    # @param success_threshold [Integer] Number of consecutive successes in
    #   HALF_OPEN state required to transition to CLOSED (default: 2)
    # @param on_state_change [Proc, nil] Callback invoked on state transitions (old_state, new_state, metrics)
    # @param fallback [Proc, nil] Fallback to execute when circuit is open
    def initialize(failure_threshold: 5, reset_timeout: 60, success_threshold: 2,
                   on_state_change: nil, fallback: nil)
      @mutex = Monitor.new
      @failure_threshold = failure_threshold
      @reset_timeout = reset_timeout
      @success_threshold = success_threshold
      @state = STATE_CLOSED
      @failure_count = 0
      @success_count = 0
      @opened_at = nil
      @last_failure_time = nil
      @on_state_change = on_state_change
      @fallback = fallback

      # Metrics tracking
      @total_failures = 0
      @total_successes = 0
      @state_durations = { closed: 0.0, open: 0.0, half_open: 0.0 }
      @state_entered_at = monotonic_time
      @transition_count = 0
    end

    # Execute a block with circuit breaker protection.
    #
    # Checks the circuit state before executing. If the circuit is OPEN, raises
    # CircuitBreakerOpenError immediately (or executes fallback if provided).
    # Otherwise, executes the block and records the result (success or failure).
    #
    # @yield Block to execute
    # @return [Object] Result of the block or fallback
    # @raise [CircuitBreakerOpenError] If circuit is open and no fallback provided
    # @raise [StandardError] Any error raised by the block (after recording failure)
    def call
      @mutex.synchronize do
        check_state_transition

        if @state == STATE_OPEN
          if @fallback
            return @fallback.call
          else
            raise CircuitBreakerOpenError, "Circuit breaker is OPEN (failures: #{@failure_count})"
          end
        end
      end

      begin
        result = yield
        record_success
        result
      rescue StandardError
        record_failure
        raise
      end
    end

    # Check if the circuit is in CLOSED state (healthy).
    #
    # @return [Boolean] true if circuit is closed
    def closed?
      @mutex.synchronize { @state == STATE_CLOSED }
    end

    # Check if the circuit is in OPEN state (unhealthy).
    #
    # @return [Boolean] true if circuit is open
    def open?
      @mutex.synchronize { @state == STATE_OPEN }
    end

    # Check if the circuit is in HALF_OPEN state (testing recovery).
    #
    # @return [Boolean] true if circuit is half-open
    def half_open?
      @mutex.synchronize { @state == STATE_HALF_OPEN }
    end

    # Manually trip the circuit breaker to OPEN state.
    #
    # Useful for forcing the circuit open during maintenance or when external
    # monitoring detects issues.
    def trip!
      @mutex.synchronize do
        open_circuit
      end
    end

    # Reset the circuit breaker to CLOSED state.
    #
    # Clears all failure and success counts and transitions to CLOSED state.
    # Useful for manual recovery or testing.
    def reset!
      @mutex.synchronize do
        old_state = @state
        @state = STATE_CLOSED
        @failure_count = 0
        @success_count = 0
        @opened_at = nil
        @last_failure_time = nil

        update_state_duration(old_state)
        @state_entered_at = monotonic_time
        emit_state_change(old_state, STATE_CLOSED) if old_state != STATE_CLOSED
      end
    end

    # Get circuit breaker metrics
    #
    # @return [Hash] Metrics including state durations, counts, and transitions
    def metrics
      @mutex.synchronize do
        current_duration = monotonic_time - @state_entered_at
        durations = @state_durations.dup
        durations[@state] += current_duration

        {
          state: @state,
          failure_count: @failure_count,
          success_count: @success_count,
          total_failures: @total_failures,
          total_successes: @total_successes,
          state_durations: durations,
          transition_count: @transition_count,
          opened_at: @opened_at,
          last_failure_time: @last_failure_time
        }
      end
    end

    private

    # Record a successful operation.
    #
    # In HALF_OPEN state, increments success count and transitions to CLOSED
    # if success threshold is reached. In CLOSED state, resets failure count.
    def record_success
      @mutex.synchronize do
        @total_successes += 1

        if @state == STATE_HALF_OPEN
          @success_count += 1
          close_circuit if @success_count >= @success_threshold
        elsif @state == STATE_CLOSED
          # Reset failure count and success count on success in closed state
          @failure_count = 0
          @success_count = 0
        end
      end
    end

    # Record a failed operation.
    #
    # In HALF_OPEN state, any failure immediately reopens the circuit.
    # In CLOSED state, increments failure count and opens circuit if threshold is reached.
    def record_failure
      @mutex.synchronize do
        @failure_count += 1
        @total_failures += 1
        @last_failure_time = monotonic_time
        @success_count = 0  # Reset success count on failure

        if @state == STATE_HALF_OPEN
          # Any failure in half-open state reopens the circuit
          open_circuit
        elsif @state == STATE_CLOSED && @failure_count >= @failure_threshold
          open_circuit
        end
      end
    end

    # Check if state should transition based on timeouts.
    #
    # Called before each operation. If in OPEN state and reset timeout has
    # elapsed, transitions to HALF_OPEN state.
    #
    # Must be called within a mutex synchronize block.
    def check_state_transition
      return unless @state == STATE_OPEN
      return unless @opened_at

      time_since_open = monotonic_time - @opened_at

      if time_since_open >= @reset_timeout
        transition_to_half_open
      end
    end

    # Open the circuit.
    #
    # Transitions to OPEN state, records the time, and resets success count.
    # Must be called within a mutex synchronize block.
    def open_circuit
      old_state = @state
      update_state_duration(old_state)

      @state = STATE_OPEN
      @opened_at = monotonic_time
      @state_entered_at = monotonic_time
      @success_count = 0
      @transition_count += 1

      emit_state_change(old_state, STATE_OPEN)
    end

    # Close the circuit.
    #
    # Transitions to CLOSED state and resets all counters.
    # Must be called within a mutex synchronize block.
    def close_circuit
      old_state = @state
      update_state_duration(old_state)

      @state = STATE_CLOSED
      @state_entered_at = monotonic_time
      @failure_count = 0
      @success_count = 0
      @opened_at = nil
      @transition_count += 1

      emit_state_change(old_state, STATE_CLOSED)
    end

    # Transition to half-open state.
    #
    # Resets counters to allow testing if the service has recovered.
    # Must be called within a mutex synchronize block.
    def transition_to_half_open
      old_state = @state
      update_state_duration(old_state)

      @state = STATE_HALF_OPEN
      @state_entered_at = monotonic_time
      @failure_count = 0
      @success_count = 0
      @transition_count += 1

      emit_state_change(old_state, STATE_HALF_OPEN)
    end

    # Update state duration tracking
    #
    # Must be called within a mutex synchronize block.
    def update_state_duration(state)
      duration = monotonic_time - @state_entered_at
      @state_durations[state] += duration
    end

    # Emit state change event
    #
    # Called within a Monitor synchronize block. Monitor is reentrant,
    # so the callback can safely call state-checking methods on this
    # circuit breaker without deadlocking.
    def emit_state_change(old_state, new_state)
      return unless @on_state_change
      return if old_state == new_state

      metrics_snapshot = {
        state: new_state,
        failure_count: @failure_count,
        success_count: @success_count,
        total_failures: @total_failures,
        total_successes: @total_successes
      }

      begin
        @on_state_change.call(old_state, new_state, metrics_snapshot)
      rescue StandardError => e
        warn "Error in circuit breaker state change callback: #{e.message}"
      end
    end

    # Get monotonic time in seconds.
    #
    # Uses Process.clock_gettime with CLOCK_MONOTONIC to get time that is
    # not affected by system clock changes (NTP adjustments, DST, etc.).
    # This ensures accurate timeout tracking.
    #
    # @return [Float] Monotonic time in seconds
    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end

  # Error raised when circuit breaker is open.
  #
  # Indicates that the circuit breaker has detected too many failures and is
  # temporarily blocking operations to allow the system to recover.
  class CircuitBreakerOpenError < Error; end
end

