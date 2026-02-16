# frozen_string_literal: true

require_relative "../test_helper"

module RR
  class CircuitBreakerTest < Minitest::Test
    def setup
      @circuit_breaker = RR::CircuitBreaker.new(
        failure_threshold: 3,
        success_threshold: 2,
        timeout: 1.0,
        half_open_timeout: 0.5
      )
    end

    def test_initial_state_is_closed
      assert_equal :closed, @circuit_breaker.state
    end

    def test_circuit_opens_after_threshold_failures
      3.times { @circuit_breaker.record_failure }
      assert_equal :open, @circuit_breaker.state
    end

    def test_circuit_stays_closed_below_threshold
      2.times { @circuit_breaker.record_failure }
      assert_equal :closed, @circuit_breaker.state
    end

    def test_circuit_resets_on_success
      2.times { @circuit_breaker.record_failure }
      @circuit_breaker.record_success
      assert_equal :closed, @circuit_breaker.state
      assert_equal 0, @circuit_breaker.failure_count
    end

    def test_open_circuit_rejects_calls
      3.times { @circuit_breaker.record_failure }
      
      error = assert_raises(RR::CircuitBreakerOpenError) do
        @circuit_breaker.call { "should not execute" }
      end
      
      assert_match(/Circuit breaker is OPEN/, error.message)
    end

    def test_circuit_transitions_to_half_open_after_timeout
      3.times { @circuit_breaker.record_failure }
      assert_equal :open, @circuit_breaker.state
      
      # Wait for half-open timeout
      sleep 0.6
      
      # Next call should transition to half-open
      @circuit_breaker.call { "test" } rescue nil
      assert_equal :half_open, @circuit_breaker.state
    end

    def test_half_open_circuit_closes_after_success_threshold
      # Open the circuit
      3.times { @circuit_breaker.record_failure }
      sleep 0.6
      
      # Transition to half-open and record successes
      @circuit_breaker.call { "test" } rescue nil
      2.times { @circuit_breaker.record_success }
      
      assert_equal :closed, @circuit_breaker.state
    end

    def test_half_open_circuit_reopens_on_failure
      # Open the circuit
      3.times { @circuit_breaker.record_failure }
      sleep 0.6
      
      # Transition to half-open
      @circuit_breaker.call { "test" } rescue nil
      
      # Record a failure
      @circuit_breaker.record_failure
      
      assert_equal :open, @circuit_breaker.state
    end

    def test_call_executes_block_when_closed
      result = @circuit_breaker.call { "success" }
      assert_equal "success", result
    end

    def test_call_records_success_automatically
      @circuit_breaker.call { "success" }
      assert_equal 0, @circuit_breaker.failure_count
    end

    def test_call_records_failure_on_exception
      assert_raises(RuntimeError) do
        @circuit_breaker.call { raise "error" }
      end
      
      assert_equal 1, @circuit_breaker.failure_count
    end

    def test_thread_safety
      threads = 10.times.map do
        Thread.new do
          100.times do
            begin
              @circuit_breaker.call { rand > 0.5 ? "success" : raise("error") }
            rescue
              # Ignore errors
            end
          end
        end
      end
      
      threads.each(&:join)
      
      # Should be in a valid state
      assert [:closed, :open, :half_open].include?(@circuit_breaker.state)
    end

    def test_reset_returns_to_closed_state
      3.times { @circuit_breaker.record_failure }
      assert_equal :open, @circuit_breaker.state
      
      @circuit_breaker.reset!
      
      assert_equal :closed, @circuit_breaker.state
      assert_equal 0, @circuit_breaker.failure_count
      assert_equal 0, @circuit_breaker.success_count
    end

    def test_metrics_snapshot
      2.times { @circuit_breaker.record_failure }

      snapshot = @circuit_breaker.snapshot

      assert_equal :closed, snapshot[:state]
      assert_equal 2, snapshot[:failure_count]
      assert_equal 0, snapshot[:success_count]
      assert snapshot[:opened_at].nil?
      assert_kind_of Time, snapshot[:last_failure_time]
    end
  end
end

