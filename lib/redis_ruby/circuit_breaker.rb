# frozen_string_literal: true

require "monitor"

module RR
  # Circuit breaker pattern implementation for Redis connections
  #
  # Prevents cascading failures by opening the circuit after a threshold
  # of consecutive failures, allowing the system to recover.
  #
  # States:
  # - CLOSED: Normal operation, requests pass through
  # - OPEN: Circuit is open, requests fail immediately
  # - HALF_OPEN: Testing if service has recovered
  #
  # @example Basic usage
  #   breaker = RR::CircuitBreaker.new(
  #     failure_threshold: 5,
  #     success_threshold: 2,
  #     timeout: 60.0,
  #     half_open_timeout: 30.0
  #   )
  #
  #   breaker.call do
  #     redis.get("key")
  #   end
  #
  class CircuitBreaker
    include MonitorMixin

    attr_reader :failure_count, :success_count, :state, :opened_at

    # Initialize a new circuit breaker
    #
    # @param failure_threshold [Integer] Number of failures before opening circuit
    # @param success_threshold [Integer] Number of successes to close circuit from half-open
    # @param timeout [Float] Seconds before transitioning from open to half-open
    # @param half_open_timeout [Float] Seconds to wait in half-open before retrying
    def initialize(failure_threshold: 5, success_threshold: 2, timeout: 60.0, half_open_timeout: 30.0)
      super() # Initialize MonitorMixin
      @failure_threshold = failure_threshold
      @success_threshold = success_threshold
      @timeout = timeout
      @half_open_timeout = half_open_timeout
      @state = :closed
      @failure_count = 0
      @success_count = 0
      @opened_at = nil
      @last_failure_time = nil
    end

    # Execute a block with circuit breaker protection
    #
    # @yield Block to execute
    # @return [Object] Result of the block
    # @raise [CircuitBreakerOpenError] If circuit is open
    def call
      synchronize do
        check_state_transition
        
        if @state == :open
          raise CircuitBreakerOpenError, "Circuit breaker is OPEN (failures: #{@failure_count})"
        end
      end

      begin
        result = yield
        record_success
        result
      rescue => e
        record_failure
        raise
      end
    end

    # Record a successful operation
    def record_success
      synchronize do
        @success_count += 1
        
        if @state == :half_open && @success_count >= @success_threshold
          close_circuit
        elsif @state == :closed
          # Reset failure count on success
          @failure_count = 0
        end
      end
    end

    # Record a failed operation
    def record_failure
      synchronize do
        @failure_count += 1
        @last_failure_time = Time.now
        
        if @state == :half_open
          # Any failure in half-open state reopens the circuit
          open_circuit
        elsif @state == :closed && @failure_count >= @failure_threshold
          open_circuit
        end
      end
    end

    # Reset the circuit breaker to closed state
    def reset!
      synchronize do
        @state = :closed
        @failure_count = 0
        @success_count = 0
        @opened_at = nil
        @last_failure_time = nil
      end
    end

    # Get a snapshot of current metrics
    #
    # @return [Hash] Current state and metrics
    def snapshot
      synchronize do
        {
          state: @state,
          failure_count: @failure_count,
          success_count: @success_count,
          opened_at: @opened_at,
          last_failure_time: @last_failure_time
        }
      end
    end

    private

    # Check if state should transition based on timeouts
    def check_state_transition
      return unless @state == :open
      
      time_since_open = Time.now - @opened_at
      
      if time_since_open >= @half_open_timeout
        transition_to_half_open
      end
    end

    # Open the circuit
    def open_circuit
      @state = :open
      @opened_at = Time.now
      @success_count = 0
    end

    # Close the circuit
    def close_circuit
      @state = :closed
      @failure_count = 0
      @success_count = 0
      @opened_at = nil
    end

    # Transition to half-open state
    def transition_to_half_open
      @state = :half_open
      @failure_count = 0
      @success_count = 0
    end
  end

  # Error raised when circuit breaker is open
  class CircuitBreakerOpenError < StandardError; end
end

