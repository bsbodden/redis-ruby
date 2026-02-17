# frozen_string_literal: true

require_relative "unit_test_helper"

class LockBranchTest < Minitest::Test
  def setup
    @mock_client = mock("client")
    @mock_script = mock("script")
    # register_script is called 3 times in Lock.new
    @mock_client.stubs(:register_script).returns(@mock_script)
  end

  # ============================================================
  # Initialize
  # ============================================================

  def test_initialize_defaults
    lock = RR::Lock.new(@mock_client, "resource")

    assert_equal "lock:resource", lock.name
    assert_in_delta(10.0, lock.timeout)
    assert_in_delta(0.1, lock.sleep_interval)
  end

  def test_initialize_custom_params
    lock = RR::Lock.new(@mock_client, "res", timeout: 30.0, sleep: 0.5)

    assert_in_delta(30.0, lock.timeout)
    assert_in_delta(0.5, lock.sleep_interval)
  end

  def test_initialize_thread_local_true
    lock = RR::Lock.new(@mock_client, "res", thread_local: true)

    assert lock.instance_variable_get(:@thread_local)
    assert_kind_of Hash, lock.instance_variable_get(:@local_tokens)
  end

  def test_initialize_thread_local_false
    lock = RR::Lock.new(@mock_client, "res", thread_local: false)

    refute lock.instance_variable_get(:@thread_local)
  end

  # ============================================================
  # acquire - non-blocking
  # ============================================================

  def test_acquire_nonblocking_success
    lock = RR::Lock.new(@mock_client, "res")
    @mock_client.expects(:set).returns("OK")

    assert lock.acquire
  end

  def test_acquire_nonblocking_failure
    lock = RR::Lock.new(@mock_client, "res")
    @mock_client.expects(:set).returns(nil)

    refute lock.acquire
  end

  def test_acquire_with_custom_token
    lock = RR::Lock.new(@mock_client, "res")
    @mock_client.expects(:set).with("lock:res", "my-token", nx: true, px: 10_000).returns("OK")

    assert lock.acquire(token: "my-token")
  end

  # ============================================================
  # acquire - blocking
  # ============================================================

  def test_acquire_blocking_success_first_attempt
    lock = RR::Lock.new(@mock_client, "res")
    @mock_client.expects(:set).returns("OK")

    assert lock.acquire(blocking: true)
  end

  def test_acquire_blocking_with_timeout_failure
    lock = RR::Lock.new(@mock_client, "res", sleep: 0.01)
    # Always fail to acquire
    @mock_client.stubs(:set).returns(nil)

    refute lock.acquire(blocking: true, blocking_timeout: 0.05)
  end

  def test_acquire_blocking_uses_monotonic_clock
    lock = RR::Lock.new(@mock_client, "res", sleep: 0.001)
    @mock_client.stubs(:set).returns(nil)

    # Verify monotonic clock is used (not Time.now)
    # If Time.now is used and jumps backward, this would hang.
    # We verify by checking that CLOCK_MONOTONIC is called.
    clock_called = false
    original_clock_gettime = Process.method(:clock_gettime)
    Process.define_singleton_method(:clock_gettime) do |clock_id|
      clock_called = true if clock_id == Process::CLOCK_MONOTONIC
      original_clock_gettime.call(clock_id)
    end

    refute lock.acquire(blocking: true, blocking_timeout: 0.01)
    assert clock_called, "Expected Process.clock_gettime(CLOCK_MONOTONIC) to be called"
  ensure
    # Restore original method
    Process.define_singleton_method(:clock_gettime, original_clock_gettime) if original_clock_gettime
  end

  # ============================================================
  # release
  # ============================================================

  def test_release_when_owned
    lock = RR::Lock.new(@mock_client, "res")
    @mock_client.expects(:set).returns("OK")
    lock.acquire

    @mock_script.expects(:call).returns(1)

    assert lock.release
  end

  def test_release_when_not_owned
    lock = RR::Lock.new(@mock_client, "res")

    refute lock.release
  end

  def test_release_when_script_returns_zero
    lock = RR::Lock.new(@mock_client, "res")
    @mock_client.expects(:set).returns("OK")
    lock.acquire

    @mock_script.expects(:call).returns(0)

    refute lock.release
  end

  # ============================================================
  # extend
  # ============================================================

  def test_extend_when_owned
    lock = RR::Lock.new(@mock_client, "res")
    @mock_client.expects(:set).returns("OK")
    lock.acquire

    @mock_script.expects(:call).returns(1)

    assert lock.extend(additional_time: 20)
  end

  def test_extend_when_not_owned
    lock = RR::Lock.new(@mock_client, "res")
    assert_raises(RR::Lock::LockNotOwnedError) do
      lock.extend(additional_time: 10)
    end
  end

  def test_extend_with_default_timeout
    lock = RR::Lock.new(@mock_client, "res", timeout: 15.0)
    @mock_client.expects(:set).returns("OK")
    lock.acquire

    @mock_script.expects(:call).with do |args|
      args[:argv][1] == 15_000 # default timeout in ms
    end.returns(1)

    assert lock.extend
  end

  def test_extend_with_replace_ttl
    lock = RR::Lock.new(@mock_client, "res")
    @mock_client.expects(:set).returns("OK")
    lock.acquire

    @mock_script.expects(:call).returns(1)

    assert lock.extend(additional_time: 30, replace_ttl: true)
  end

  def test_extend_returns_false_when_script_returns_zero
    lock = RR::Lock.new(@mock_client, "res")
    @mock_client.expects(:set).returns("OK")
    lock.acquire

    @mock_script.expects(:call).returns(0)

    refute lock.extend(additional_time: 10)
  end

  # ============================================================
  # reacquire
  # ============================================================

  def test_reacquire_when_owned
    lock = RR::Lock.new(@mock_client, "res")
    @mock_client.expects(:set).returns("OK")
    lock.acquire

    @mock_script.expects(:call).returns(1)

    assert lock.reacquire
  end

  def test_reacquire_when_not_owned
    lock = RR::Lock.new(@mock_client, "res")
    assert_raises(RR::Lock::LockNotOwnedError) do
      lock.reacquire
    end
  end

  def test_reacquire_returns_false_when_script_returns_zero
    lock = RR::Lock.new(@mock_client, "res")
    @mock_client.expects(:set).returns("OK")
    lock.acquire

    @mock_script.expects(:call).returns(0)

    refute lock.reacquire
  end

  # ============================================================
  # owned?
  # ============================================================

  def test_owned_true
    lock = RR::Lock.new(@mock_client, "res")
    @mock_client.expects(:set).returns("OK")
    lock.acquire

    token = lock.instance_variable_get(:@local_tokens)[Thread.current]
    @mock_client.expects(:get).with("lock:res").returns(token)

    assert_predicate lock, :owned?
  end

  def test_owned_false_different_token
    lock = RR::Lock.new(@mock_client, "res")
    @mock_client.expects(:set).returns("OK")
    lock.acquire

    @mock_client.expects(:get).with("lock:res").returns("different")

    refute_predicate lock, :owned?
  end

  def test_owned_false_no_token
    lock = RR::Lock.new(@mock_client, "res")

    refute_predicate lock, :owned?
  end

  # ============================================================
  # locked?
  # ============================================================

  def test_locked_true
    lock = RR::Lock.new(@mock_client, "res")
    @mock_client.expects(:exists).with("lock:res").returns(1)

    assert_predicate lock, :locked?
  end

  def test_locked_false
    lock = RR::Lock.new(@mock_client, "res")
    @mock_client.expects(:exists).with("lock:res").returns(0)

    refute_predicate lock, :locked?
  end

  # ============================================================
  # ttl
  # ============================================================

  def test_ttl_returns_seconds
    lock = RR::Lock.new(@mock_client, "res")
    @mock_client.expects(:pttl).with("lock:res").returns(5000)

    assert_in_delta(5.0, lock.ttl)
  end

  def test_ttl_returns_nil_when_negative
    lock = RR::Lock.new(@mock_client, "res")
    @mock_client.expects(:pttl).with("lock:res").returns(-2)

    assert_nil lock.ttl
  end

  def test_ttl_returns_nil_when_minus_one
    lock = RR::Lock.new(@mock_client, "res")
    @mock_client.expects(:pttl).with("lock:res").returns(-1)

    assert_nil lock.ttl
  end

  # ============================================================
  # synchronize
  # ============================================================

  def test_synchronize_acquires_and_releases
    lock = RR::Lock.new(@mock_client, "res")
    @mock_client.expects(:set).returns("OK")
    @mock_script.expects(:call).returns(1)

    executed = false
    lock.synchronize { executed = true }

    assert executed
  end

  def test_synchronize_raises_when_cannot_acquire
    lock = RR::Lock.new(@mock_client, "res")
    @mock_client.expects(:set).returns(nil)

    assert_raises(RR::Lock::LockAcquireError) do
      lock.synchronize(blocking: false) {}
    end
  end

  def test_synchronize_releases_on_exception
    lock = RR::Lock.new(@mock_client, "res")
    @mock_client.expects(:set).returns("OK")
    @mock_script.expects(:call).returns(1)

    assert_raises(RuntimeError) do
      lock.synchronize { raise "boom" }
    end
  end

  # ============================================================
  # Token storage: thread_local vs instance
  # ============================================================

  def test_non_thread_local_token_storage
    lock = RR::Lock.new(@mock_client, "res", thread_local: false)
    @mock_client.expects(:set).returns("OK")
    lock.acquire

    # Token stored in @token
    refute_nil lock.instance_variable_get(:@token)
  end

  def test_non_thread_local_release_clears_token
    lock = RR::Lock.new(@mock_client, "res", thread_local: false)
    @mock_client.expects(:set).returns("OK")
    lock.acquire

    @mock_script.expects(:call).returns(1)
    lock.release

    assert_nil lock.instance_variable_get(:@token)
  end

  def test_non_thread_local_owned_check
    lock = RR::Lock.new(@mock_client, "res", thread_local: false)
    @mock_client.expects(:set).returns("OK")
    lock.acquire

    token = lock.instance_variable_get(:@token)
    @mock_client.expects(:get).with("lock:res").returns(token)

    assert_predicate lock, :owned?
  end

  # ============================================================
  # Error classes
  # ============================================================

  def test_lock_error_inherits_from_error
    assert_operator RR::Lock::LockError, :<, RR::Error
  end

  def test_lock_not_owned_error_inherits_from_lock_error
    assert_operator RR::Lock::LockNotOwnedError, :<, RR::Lock::LockError
  end

  def test_lock_acquire_error_inherits_from_lock_error
    assert_operator RR::Lock::LockAcquireError, :<, RR::Lock::LockError
  end
end
