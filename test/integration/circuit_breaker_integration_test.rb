# frozen_string_literal: true

require_relative "../test_helper"

module RR
  class CircuitBreakerIntegrationTest < Minitest::Test
    def setup
      @circuit_breaker = RR::CircuitBreaker.new(
        failure_threshold: 3,
        success_threshold: 2,
        reset_timeout: 0.5
      )
      @redis = RR.new(circuit_breaker: @circuit_breaker)
      @redis.flushdb
    end

    def teardown
      @redis.close
      @circuit_breaker.reset!
    end

    def test_client_works_with_circuit_breaker
      result = @redis.set("key", "value")

      assert_equal "OK", result

      value = @redis.get("key")

      assert_equal "value", value

      assert_equal :closed, @circuit_breaker.state
    end

    def test_circuit_breaker_opens_on_connection_failures
      # Create a client with no retry policy and circuit breaker
      circuit_breaker = RR::CircuitBreaker.new(failure_threshold: 3)
      redis = RR::Client.new(
        host: "nonexistent.invalid", # Invalid host to force connection failures
        timeout: 0.1,                  # Short timeout
        reconnect_attempts: 0,         # No retries
        circuit_breaker: circuit_breaker
      )

      # Try to execute commands - should fail and open circuit
      3.times do
        redis.get("key")

        flunk "Expected connection error"
      rescue RR::ConnectionError, RR::TimeoutError
        # Expected - connection failures
      end

      # Circuit should now be open
      assert_equal :open, circuit_breaker.state

      # Next attempt should raise CircuitBreakerOpenError
      assert_raises(RR::CircuitBreakerOpenError) do
        redis.get("key")
      end
    end

    def test_health_check_returns_true_when_healthy
      assert_predicate @redis, :healthy?
    end

    def test_health_check_returns_false_when_circuit_open
      # Open the circuit
      @circuit_breaker.trip!

      refute_predicate @redis, :healthy?
    end

    def test_health_check_with_custom_command
      result = @redis.health_check(command: "PING")

      assert result
    end

    def test_health_check_catches_errors
      # Create a client pointing to invalid host
      redis = RR::Client.new(
        host: "nonexistent.invalid",
        timeout: 0.1,
        reconnect_attempts: 0
      )

      # Health check should return false
      refute redis.health_check
      refute_predicate redis, :healthy?
    end

    def test_pooled_client_works_with_circuit_breaker
      circuit_breaker = RR::CircuitBreaker.new(failure_threshold: 3)
      pooled = RR.pooled(circuit_breaker: circuit_breaker, pool: { size: 5 })

      result = pooled.set("key", "value")

      assert_equal "OK", result

      assert_equal :closed, circuit_breaker.state

      pooled.close
    end

    def test_circuit_breaker_prevents_cascading_failures
      # Create a client with circuit breaker and no retries
      circuit_breaker = RR::CircuitBreaker.new(failure_threshold: 3)
      redis = RR::Client.new(
        host: "nonexistent.invalid",
        timeout: 0.1,
        reconnect_attempts: 0,
        circuit_breaker: circuit_breaker
      )

      # Try to execute commands
      errors = 0
      circuit_open_errors = 0

      10.times do
        redis.get("key")
      rescue RR::CircuitBreakerOpenError
        circuit_open_errors += 1
      rescue RR::ConnectionError, RR::TimeoutError
        errors += 1
      end

      # After 3 failures, circuit should open and prevent further attempts
      assert_equal 3, errors, "Should have 3 connection errors before circuit opens"
      assert_equal 7, circuit_open_errors, "Should have 7 circuit breaker errors after circuit opens"
    end
  end
end
