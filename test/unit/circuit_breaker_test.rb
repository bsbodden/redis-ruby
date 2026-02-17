# frozen_string_literal: true

require_relative "../test_helper"

module RR
  class CircuitBreakerTest < Minitest::Test
    def setup
      @circuit_breaker = RR::CircuitBreaker.new(
        failure_threshold: 3,
        success_threshold: 2,
        reset_timeout: 0.5
      )
    end

    def test_initial_state_is_closed
      assert_equal :closed, @circuit_breaker.state
      assert @circuit_breaker.closed?
      refute @circuit_breaker.open?
      refute @circuit_breaker.half_open?
    end

    def test_circuit_opens_after_threshold_failures
      3.times { @circuit_breaker.send(:record_failure) }
      assert_equal :open, @circuit_breaker.state
      assert @circuit_breaker.open?
      refute @circuit_breaker.closed?
    end

    def test_circuit_stays_closed_below_threshold
      2.times { @circuit_breaker.send(:record_failure) }
      assert_equal :closed, @circuit_breaker.state
      assert @circuit_breaker.closed?
    end

    def test_circuit_resets_on_success
      2.times { @circuit_breaker.send(:record_failure) }
      @circuit_breaker.send(:record_success)
      assert_equal :closed, @circuit_breaker.state
      assert_equal 0, @circuit_breaker.failure_count
    end

    def test_open_circuit_rejects_calls
      3.times { @circuit_breaker.send(:record_failure) }

      error = assert_raises(RR::CircuitBreakerOpenError) do
        @circuit_breaker.call { "should not execute" }
      end

      assert_match(/Circuit breaker is OPEN/, error.message)
    end

    def test_circuit_transitions_to_half_open_after_timeout
      3.times { @circuit_breaker.send(:record_failure) }
      assert_equal :open, @circuit_breaker.state

      # Wait for reset timeout
      sleep 0.6

      # Next call should transition to half-open
      @circuit_breaker.call { "test" } rescue nil
      assert_equal :half_open, @circuit_breaker.state
      assert @circuit_breaker.half_open?
    end

    def test_half_open_circuit_closes_after_success_threshold
      # Open the circuit
      3.times { @circuit_breaker.send(:record_failure) }
      sleep 0.6

      # Transition to half-open and record successes
      @circuit_breaker.call { "test" } rescue nil
      2.times { @circuit_breaker.send(:record_success) }

      assert_equal :closed, @circuit_breaker.state
      assert @circuit_breaker.closed?
    end

    def test_half_open_circuit_reopens_on_failure
      # Open the circuit
      3.times { @circuit_breaker.send(:record_failure) }
      sleep 0.6

      # Transition to half-open
      @circuit_breaker.call { "test" } rescue nil

      # Record a failure
      @circuit_breaker.send(:record_failure)

      assert_equal :open, @circuit_breaker.state
      assert @circuit_breaker.open?
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
      3.times { @circuit_breaker.send(:record_failure) }
      assert_equal :open, @circuit_breaker.state

      @circuit_breaker.reset!

      assert_equal :closed, @circuit_breaker.state
      assert_equal 0, @circuit_breaker.failure_count
      assert_equal 0, @circuit_breaker.success_count
      assert @circuit_breaker.closed?
    end

    def test_trip_manually_opens_circuit
      assert @circuit_breaker.closed?

      @circuit_breaker.trip!

      assert_equal :open, @circuit_breaker.state
      assert @circuit_breaker.open?

      # Should reject calls
      assert_raises(RR::CircuitBreakerOpenError) do
        @circuit_breaker.call { "test" }
      end
    end

    def test_state_query_methods
      # Initially closed
      assert @circuit_breaker.closed?
      refute @circuit_breaker.open?
      refute @circuit_breaker.half_open?

      # Open circuit
      @circuit_breaker.trip!
      refute @circuit_breaker.closed?
      assert @circuit_breaker.open?
      refute @circuit_breaker.half_open?

      # Wait for reset timeout and transition to half-open
      sleep 0.6
      @circuit_breaker.call { "test" } rescue nil
      refute @circuit_breaker.closed?
      refute @circuit_breaker.open?
      assert @circuit_breaker.half_open?
    end

    def test_state_change_callback_runs_synchronously
      results = []
      breaker = RR::CircuitBreaker.new(
        failure_threshold: 3,
        on_state_change: ->(_old_state, new_state, _metrics) {
          results << new_state
        }
      )

      breaker.trip!
      # Callback must have completed by the time trip! returns
      assert_equal [:open], results, "on_state_change callback should run synchronously"

      breaker.reset!
      assert_equal [:open, :closed], results, "on_state_change callback should run synchronously"
    end

    def test_state_change_callback_can_query_circuit_state
      # Callback should be able to call state methods without deadlock
      observed_state = nil
      breaker = RR::CircuitBreaker.new(
        failure_threshold: 3,
        on_state_change: ->(_old_state, _new_state, _metrics) {
          observed_state = breaker.open?
        }
      )

      breaker.trip!
      assert observed_state, "Callback should observe open? == true without deadlock"
    end
  end
end

