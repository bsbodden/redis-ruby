# frozen_string_literal: true

require_relative "unit_test_helper"

class RetryComprehensiveTest < Minitest::Test
  # ============================================================
  # Initialization tests
  # ============================================================

  def test_retry_class_exists
    assert_kind_of Class, RedisRuby::Retry
  end

  def test_retry_can_be_instantiated
    retry_policy = RedisRuby::Retry.new

    assert_instance_of RedisRuby::Retry, retry_policy
  end

  def test_retry_with_custom_retries
    retry_policy = RedisRuby::Retry.new(retries: 5)

    assert_instance_of RedisRuby::Retry, retry_policy
  end

  def test_retry_with_custom_backoff
    backoff = RedisRuby::NoBackoff.new
    retry_policy = RedisRuby::Retry.new(backoff: backoff)

    assert_instance_of RedisRuby::Retry, retry_policy
  end

  def test_retry_with_callback
    callback = ->(error, attempt) { puts "Attempt #{attempt}: #{error}" }
    retry_policy = RedisRuby::Retry.new(on_retry: callback)

    assert_instance_of RedisRuby::Retry, retry_policy
  end

  # ============================================================
  # Call behavior tests
  # ============================================================

  def test_call_succeeds_without_retry
    retry_policy = RedisRuby::Retry.new(retries: 3, backoff: RedisRuby::NoBackoff.new)
    call_count = 0

    result = retry_policy.call do
      call_count += 1
      "success"
    end

    assert_equal "success", result
    assert_equal 1, call_count
  end

  def test_call_retries_on_connection_error
    retry_policy = RedisRuby::Retry.new(retries: 3, backoff: RedisRuby::NoBackoff.new)
    call_count = 0

    result = retry_policy.call do
      call_count += 1
      raise RedisRuby::ConnectionError, "Connection lost" if call_count < 2

      "success"
    end

    assert_equal "success", result
    assert_equal 2, call_count
  end

  def test_call_retries_on_timeout_error
    retry_policy = RedisRuby::Retry.new(retries: 3, backoff: RedisRuby::NoBackoff.new)
    call_count = 0

    result = retry_policy.call do
      call_count += 1
      raise RedisRuby::TimeoutError, "Timed out" if call_count < 2

      "success"
    end

    assert_equal "success", result
    assert_equal 2, call_count
  end

  def test_call_raises_after_max_retries
    retry_policy = RedisRuby::Retry.new(retries: 3, backoff: RedisRuby::NoBackoff.new)
    call_count = 0

    assert_raises(RedisRuby::ConnectionError) do
      retry_policy.call do
        call_count += 1
        raise RedisRuby::ConnectionError, "Connection lost"
      end
    end

    # Should be 4 calls: 1 initial + 3 retries
    assert_equal 4, call_count
  end

  def test_call_does_not_retry_command_errors
    retry_policy = RedisRuby::Retry.new(retries: 3, backoff: RedisRuby::NoBackoff.new)
    call_count = 0

    assert_raises(RedisRuby::CommandError) do
      retry_policy.call do
        call_count += 1
        raise RedisRuby::CommandError, "WRONGTYPE"
      end
    end

    assert_equal 1, call_count
  end

  def test_call_does_not_retry_standard_errors
    retry_policy = RedisRuby::Retry.new(retries: 3, backoff: RedisRuby::NoBackoff.new)
    call_count = 0

    assert_raises(StandardError) do
      retry_policy.call do
        call_count += 1
        raise StandardError, "Some error"
      end
    end

    assert_equal 1, call_count
  end

  def test_call_with_zero_retries
    retry_policy = RedisRuby::Retry.new(retries: 0, backoff: RedisRuby::NoBackoff.new)
    call_count = 0

    assert_raises(RedisRuby::ConnectionError) do
      retry_policy.call do
        call_count += 1
        raise RedisRuby::ConnectionError, "fail"
      end
    end

    assert_equal 1, call_count
  end

  def test_callback_is_called_on_retry
    callback_calls = []
    callback = ->(error, attempt) { callback_calls << [error.message, attempt] }
    retry_policy = RedisRuby::Retry.new(retries: 2, backoff: RedisRuby::NoBackoff.new, on_retry: callback)
    call_count = 0

    result = retry_policy.call do
      call_count += 1
      raise RedisRuby::ConnectionError, "fail" if call_count < 2

      "success"
    end

    assert_equal "success", result
    assert_equal 1, callback_calls.length
    assert_equal ["fail", 1], callback_calls[0]
  end

  # ============================================================
  # Backoff strategy tests
  # ============================================================

  def test_no_backoff
    backoff = RedisRuby::NoBackoff.new

    assert_equal 0, backoff.compute(1)
    assert_equal 0, backoff.compute(5)
    assert_equal 0, backoff.compute(100)
  end

  def test_constant_backoff
    backoff = RedisRuby::ConstantBackoff.new(0.5)

    assert_in_delta 0.5, backoff.compute(1), 0.001
    assert_in_delta 0.5, backoff.compute(5), 0.001
    assert_in_delta 0.5, backoff.compute(100), 0.001
  end

  def test_exponential_backoff
    backoff = RedisRuby::ExponentialBackoff.new(base: 0.1, cap: 10.0)
    # failures=1: 0.1 * 2^0 = 0.1
    assert_in_delta 0.1, backoff.compute(1), 0.001
    # failures=2: 0.1 * 2^1 = 0.2
    assert_in_delta 0.2, backoff.compute(2), 0.001
    # failures=3: 0.1 * 2^2 = 0.4
    assert_in_delta 0.4, backoff.compute(3), 0.001
  end

  def test_exponential_backoff_cap
    backoff = RedisRuby::ExponentialBackoff.new(base: 1.0, cap: 5.0)
    # failures=10: 1.0 * 2^9 = 512, capped at 5.0
    assert_in_delta 5.0, backoff.compute(10), 0.001
  end

  def test_exponential_with_jitter_backoff
    backoff = RedisRuby::ExponentialWithJitterBackoff.new(base: 0.1, cap: 10.0)
    # Result should be in [0, 0.1] for failures=1
    100.times do
      delay = backoff.compute(1)

      assert_operator delay, :>=, 0, "Delay should be >= 0"
      assert_operator delay, :<=, 0.1, "Delay should be <= 0.1 for failures=1"
    end
  end

  def test_exponential_with_jitter_backoff_cap
    backoff = RedisRuby::ExponentialWithJitterBackoff.new(base: 1.0, cap: 5.0)
    # Result should be in [0, 5.0] for high failure counts
    100.times do
      delay = backoff.compute(10)

      assert_operator delay, :>=, 0, "Delay should be >= 0"
      assert_operator delay, :<=, 5.0, "Delay should be <= 5.0 (cap)"
    end
  end

  def test_equal_jitter_backoff
    backoff = RedisRuby::EqualJitterBackoff.new(base: 1.0, cap: 10.0)
    # For failures=1, delay = 1.0, half = 0.5
    # Result should be in [0.5, 1.0]
    100.times do
      delay = backoff.compute(1)

      assert_operator delay, :>=, 0.5, "Delay should be >= 0.5"
      assert_operator delay, :<=, 1.0, "Delay should be <= 1.0 for failures=1"
    end
  end

  def test_equal_jitter_backoff_cap
    backoff = RedisRuby::EqualJitterBackoff.new(base: 1.0, cap: 6.0)
    # For high failures, delay is capped at 6.0, half = 3.0
    # Result should be in [3.0, 6.0]
    100.times do
      delay = backoff.compute(10)

      assert_operator delay, :>=, 3.0, "Delay should be >= 3.0 (half of cap)"
      assert_operator delay, :<=, 6.0, "Delay should be <= 6.0 (cap)"
    end
  end
end
