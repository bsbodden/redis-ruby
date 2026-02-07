# frozen_string_literal: true

require "minitest/autorun"
require_relative "../test_helper"

class RetryPolicyTest < Minitest::Test
  # --- Backoff Strategies ---

  def test_no_backoff_returns_zero
    backoff = RedisRuby::NoBackoff.new

    assert_equal 0, backoff.compute(1)
    assert_equal 0, backoff.compute(5)
  end

  def test_constant_backoff_returns_fixed_value
    backoff = RedisRuby::ConstantBackoff.new(0.5)

    assert_in_delta(0.5, backoff.compute(1))
    assert_in_delta(0.5, backoff.compute(10))
  end

  def test_exponential_backoff_grows_exponentially
    backoff = RedisRuby::ExponentialBackoff.new(base: 0.1, cap: 10.0)
    # failures: 1 => 0.1, 2 => 0.2, 3 => 0.4, 4 => 0.8, ...
    assert_in_delta 0.1, backoff.compute(1), 0.001
    assert_in_delta 0.2, backoff.compute(2), 0.001
    assert_in_delta 0.4, backoff.compute(3), 0.001
    assert_in_delta 0.8, backoff.compute(4), 0.001
  end

  def test_exponential_backoff_respects_cap
    backoff = RedisRuby::ExponentialBackoff.new(base: 1.0, cap: 5.0)
    # failures: 1 => 1.0, 2 => 2.0, 3 => 4.0, 4 => 5.0 (capped), 5 => 5.0
    assert_in_delta 5.0, backoff.compute(4), 0.001
    assert_in_delta 5.0, backoff.compute(10), 0.001
  end

  def test_exponential_with_jitter_backoff_within_range
    backoff = RedisRuby::ExponentialWithJitterBackoff.new(base: 0.1, cap: 10.0)
    100.times do
      val = backoff.compute(3)
      # For failures=3, base * 2^(3-1) = 0.4, jitter in [0, 0.4]
      assert_operator val, :>=, 0, "Jitter should be >= 0, got #{val}"
      assert_operator val, :<=, 0.4, "Jitter should be <= cap for this failure, got #{val}"
    end
  end

  def test_equal_jitter_backoff_within_range
    backoff = RedisRuby::EqualJitterBackoff.new(base: 0.1, cap: 10.0)
    100.times do
      val = backoff.compute(3)
      # half + random(half), half = 0.4/2 = 0.2, range [0.2, 0.4]
      assert_operator val, :>=, 0.2 - 0.001, "EqualJitter should be >= half, got #{val}"
      assert_operator val, :<=, 0.4 + 0.001, "EqualJitter should be <= delay, got #{val}"
    end
  end

  # --- Retry Policy ---

  def test_retry_succeeds_on_first_try
    policy = RedisRuby::Retry.new(retries: 3)
    calls = 0
    result = policy.call do
      calls += 1
      "OK"
    end

    assert_equal "OK", result
    assert_equal 1, calls
  end

  def test_retry_retries_on_connection_error
    policy = RedisRuby::Retry.new(retries: 3, backoff: RedisRuby::NoBackoff.new)
    calls = 0
    result = policy.call do
      calls += 1
      raise RedisRuby::ConnectionError, "lost" if calls < 3

      "OK"
    end

    assert_equal "OK", result
    assert_equal 3, calls
  end

  def test_retry_retries_on_timeout_error
    policy = RedisRuby::Retry.new(retries: 3, backoff: RedisRuby::NoBackoff.new)
    calls = 0
    result = policy.call do
      calls += 1
      raise RedisRuby::TimeoutError, "timed out" if calls < 2

      "OK"
    end

    assert_equal "OK", result
    assert_equal 2, calls
  end

  def test_retry_raises_after_exhausting_retries
    policy = RedisRuby::Retry.new(retries: 2, backoff: RedisRuby::NoBackoff.new)
    calls = 0
    assert_raises(RedisRuby::ConnectionError) do
      policy.call do
        calls += 1
        raise RedisRuby::ConnectionError, "always fails"
      end
    end
    # Initial attempt + 2 retries = 3 total calls
    assert_equal 3, calls
  end

  def test_retry_does_not_catch_command_errors
    policy = RedisRuby::Retry.new(retries: 3, backoff: RedisRuby::NoBackoff.new)
    calls = 0
    assert_raises(RedisRuby::CommandError) do
      policy.call do
        calls += 1
        raise RedisRuby::CommandError, "ERR wrong type"
      end
    end
    assert_equal 1, calls
  end

  def test_retry_with_custom_supported_errors
    policy = RedisRuby::Retry.new(
      retries: 2,
      supported_errors: [RedisRuby::ConnectionError],
      backoff: RedisRuby::NoBackoff.new
    )

    calls = 0
    assert_raises(RedisRuby::TimeoutError) do
      policy.call do
        calls += 1
        raise RedisRuby::TimeoutError, "timeout"
      end
    end
    assert_equal 1, calls, "TimeoutError should not be retried when not in supported_errors"
  end

  def test_retry_default_supported_errors
    policy = RedisRuby::Retry.new(retries: 2, backoff: RedisRuby::NoBackoff.new)
    # Both ConnectionError and TimeoutError should be retried by default
    calls = 0
    result = policy.call do
      calls += 1
      raise RedisRuby::ConnectionError, "lost" if calls == 1
      raise RedisRuby::TimeoutError, "slow" if calls == 2

      "OK"
    end

    assert_equal "OK", result
    assert_equal 3, calls
  end

  def test_retry_zero_retries_raises_immediately
    policy = RedisRuby::Retry.new(retries: 0, backoff: RedisRuby::NoBackoff.new)
    calls = 0
    assert_raises(RedisRuby::ConnectionError) do
      policy.call do
        calls += 1
        raise RedisRuby::ConnectionError, "fail"
      end
    end
    assert_equal 1, calls
  end

  def test_retry_with_reconnect_callback
    reconnected = false
    policy = RedisRuby::Retry.new(
      retries: 1,
      backoff: RedisRuby::NoBackoff.new,
      on_retry: ->(_error, _attempt) { reconnected = true }
    )
    calls = 0
    policy.call do
      calls += 1
      raise RedisRuby::ConnectionError, "lost" if calls == 1

      "OK"
    end

    assert reconnected, "on_retry callback should have been called"
  end
end
