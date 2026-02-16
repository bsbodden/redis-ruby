# frozen_string_literal: true

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
    def initialize(failure_threshold: 5, reset_timeout: 60, success_threshold: 2)
      @mutex = Mutex.new
      @failure_threshold = failure_threshold
      @reset_timeout = reset_timeout
      @success_threshold = success_threshold
      @state = STATE_CLOSED
      @failure_count = 0
      @success_count = 0
      @opened_at = nil
      @last_failure_time = nil
    end

    # Execute a block with circuit breaker protection.
    #
    # Checks the circuit state before executing. If the circuit is OPEN, raises
    # CircuitBreakerOpenError immediately. Otherwise, executes the block and
    # records the result (success or failure).
    #
    # @yield Block to execute
    # @return [Object] Result of the block
    # @raise [CircuitBreakerOpenError] If circuit is open
    # @raise [StandardError] Any error raised by the block (after recording failure)
    def call
      @mutex.synchronize do
        check_state_transition

        if @state == STATE_OPEN
          raise CircuitBreakerOpenError, "Circuit breaker is OPEN (failures: #{@failure_count})"
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
        @state = STATE_CLOSED
        @failure_count = 0
        @success_count = 0
        @opened_at = nil
        @last_failure_time = nil
      end
    end

    private

    # Record a successful operation.
    #
    # In HALF_OPEN state, increments success count and transitions to CLOSED
    # if success threshold is reached. In CLOSED state, resets failure count.
    def record_success
      @mutex.synchronize do
        @success_count += 1

        if @state == STATE_HALF_OPEN && @success_count >= @success_threshold
          close_circuit
        elsif @state == STATE_CLOSED
          # Reset failure count on success in closed state
          @failure_count = 0
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
        @last_failure_time = monotonic_time

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
      @state = STATE_OPEN
      @opened_at = monotonic_time
      @success_count = 0
    end

    # Close the circuit.
    #
    # Transitions to CLOSED state and resets all counters.
    # Must be called within a mutex synchronize block.
    def close_circuit
      @state = STATE_CLOSED
      @failure_count = 0
      @success_count = 0
      @opened_at = nil
    end

    # Transition to half-open state.
    #
    # Resets counters to allow testing if the service has recovered.
    # Must be called within a mutex synchronize block.
    def transition_to_half_open
      @state = STATE_HALF_OPEN
      @failure_count = 0
      @success_count = 0
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

