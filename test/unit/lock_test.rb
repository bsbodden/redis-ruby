# frozen_string_literal: true

require "minitest/autorun"
require_relative "../test_helper"

class LockTest < Minitest::Test
  def setup
    @mock_client = Minitest::Mock.new
    @mock_script = Minitest::Mock.new
  end

  def test_initialize_creates_lock_with_prefix
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])

    lock = RR::Lock.new(@mock_client, "my-resource")

    assert_equal "lock:my-resource", lock.name
    assert_in_delta(10.0, lock.timeout)
    @mock_client.verify
  end

  def test_initialize_with_custom_timeout
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])

    lock = RR::Lock.new(@mock_client, "resource", timeout: 30.0)

    assert_in_delta(30.0, lock.timeout)
  end

  def test_acquire_nonblocking_success
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])

    lock = RR::Lock.new(@mock_client, "resource")

    # Use a proc to match any arguments and return the expected result
    @mock_client.expect(:set, "OK") do |key, _token, **opts|
      key == "lock:resource" && opts[:nx] == true && opts[:px] == 10_000
    end

    result = lock.acquire

    assert result
    @mock_client.verify
  end

  def test_acquire_nonblocking_failure
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])

    lock = RR::Lock.new(@mock_client, "resource")

    @mock_client.expect(:set, nil) do |key, _token, **opts|
      key == "lock:resource" && opts[:nx] == true && opts[:px] == 10_000
    end

    result = lock.acquire

    refute result
    @mock_client.verify
  end

  def test_release_when_owned
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])

    lock = RR::Lock.new(@mock_client, "resource")

    @mock_client.expect(:set, "OK") do |key, _token, **opts|
      key == "lock:resource" && opts[:nx] == true && opts[:px] == 10_000
    end

    lock.acquire

    # Release script returns 1 when successful
    @mock_script.expect(:call, 1) do |args|
      args[:keys] == ["lock:resource"] && args[:argv].is_a?(Array)
    end

    result = lock.release

    assert result
    @mock_script.verify
  end

  def test_release_when_not_owned
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])

    lock = RR::Lock.new(@mock_client, "resource")
    # Never acquired, so no token

    result = lock.release

    refute result
  end

  def test_owned_returns_true_when_token_matches
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])

    lock = RR::Lock.new(@mock_client, "resource")

    @mock_client.expect(:set, "OK") do |key, _token, **opts|
      key == "lock:resource" && opts[:nx] == true && opts[:px] == 10_000
    end

    lock.acquire

    # The get should return the same token
    token = lock.instance_variable_get(:@local_tokens)[Thread.current]
    @mock_client.expect(:get, token, ["lock:resource"])

    assert_predicate lock, :owned?
    @mock_client.verify
  end

  def test_owned_returns_false_when_token_mismatch
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])

    lock = RR::Lock.new(@mock_client, "resource")

    @mock_client.expect(:set, "OK") do |key, _token, **opts|
      key == "lock:resource" && opts[:nx] == true && opts[:px] == 10_000
    end

    lock.acquire

    @mock_client.expect(:get, "different-token", ["lock:resource"])

    refute_predicate lock, :owned?
    @mock_client.verify
  end

  def test_locked_returns_true_when_key_exists
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:exists, 1, ["lock:resource"])

    lock = RR::Lock.new(@mock_client, "resource")

    assert_predicate lock, :locked?
    @mock_client.verify
  end

  def test_locked_returns_false_when_key_missing
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:exists, 0, ["lock:resource"])

    lock = RR::Lock.new(@mock_client, "resource")

    refute_predicate lock, :locked?
    @mock_client.verify
  end

  def test_ttl_returns_remaining_time
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:pttl, 5000, ["lock:resource"])

    lock = RR::Lock.new(@mock_client, "resource")

    assert_in_delta(5.0, lock.ttl)
    @mock_client.verify
  end

  def test_ttl_returns_nil_when_not_locked
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:pttl, -2, ["lock:resource"])

    lock = RR::Lock.new(@mock_client, "resource")

    assert_nil lock.ttl
    @mock_client.verify
  end
end

class LockTestPart2 < Minitest::Test
  def setup
    @mock_client = Minitest::Mock.new
    @mock_script = Minitest::Mock.new
  end

  def test_extend_increases_ttl
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])

    lock = RR::Lock.new(@mock_client, "resource")

    @mock_client.expect(:set, "OK") do |key, _token, **opts|
      key == "lock:resource" && opts[:nx] == true && opts[:px] == 10_000
    end

    lock.acquire

    @mock_script.expect(:call, 1) do |args|
      args[:keys] == ["lock:resource"] && args[:argv][1] == 15_000
    end

    result = lock.extend(additional_time: 15)

    assert result
    @mock_script.verify
  end

  def test_extend_raises_when_not_owned
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])

    lock = RR::Lock.new(@mock_client, "resource")

    assert_raises(RR::Lock::LockNotOwnedError) do
      lock.extend(additional_time: 10)
    end
  end

  def test_reacquire_resets_ttl
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])

    lock = RR::Lock.new(@mock_client, "resource")

    @mock_client.expect(:set, "OK") do |key, _token, **opts|
      key == "lock:resource" && opts[:nx] == true && opts[:px] == 10_000
    end

    lock.acquire

    @mock_script.expect(:call, 1) do |args|
      args[:keys] == ["lock:resource"] && args[:argv][1] == 10_000
    end

    result = lock.reacquire

    assert result
    @mock_script.verify
  end

  def test_reacquire_raises_when_not_owned
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])

    lock = RR::Lock.new(@mock_client, "resource")

    assert_raises(RR::Lock::LockNotOwnedError) do
      lock.reacquire
    end
  end

  def test_synchronize_acquires_and_releases
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])

    lock = RR::Lock.new(@mock_client, "resource")

    @mock_client.expect(:set, "OK") do |key, _token, **opts|
      key == "lock:resource" && opts[:nx] == true && opts[:px] == 10_000
    end

    @mock_script.expect(:call, 1) do |args|
      args[:keys] == ["lock:resource"]
    end

    executed = false
    lock.synchronize do
      executed = true
    end

    assert executed
    @mock_script.verify
  end

  def test_synchronize_releases_on_exception
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])

    lock = RR::Lock.new(@mock_client, "resource")

    @mock_client.expect(:set, "OK") do |key, _token, **opts|
      key == "lock:resource" && opts[:nx] == true && opts[:px] == 10_000
    end

    @mock_script.expect(:call, 1) do |args|
      args[:keys] == ["lock:resource"]
    end

    assert_raises(RuntimeError) do
      lock.synchronize do
        raise "test error"
      end
    end

    @mock_script.verify
  end

  def test_synchronize_raises_when_cannot_acquire
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])

    lock = RR::Lock.new(@mock_client, "resource")

    @mock_client.expect(:set, nil) do |key, _token, **opts|
      key == "lock:resource" && opts[:nx] == true && opts[:px] == 10_000
    end

    assert_raises(RR::Lock::LockAcquireError) do
      lock.synchronize(blocking: false) do
        # Should not reach here
      end
    end
  end

  def test_thread_local_tokens
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])

    lock = RR::Lock.new(@mock_client, "resource", thread_local: true)

    # Verify thread-local storage is used
    assert_kind_of Hash, lock.instance_variable_get(:@local_tokens)
    assert lock.instance_variable_get(:@thread_local)
  end

  def test_non_thread_local_tokens
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])
    @mock_client.expect(:register_script, @mock_script, [String])

    lock = RR::Lock.new(@mock_client, "resource", thread_local: false)

    refute lock.instance_variable_get(:@thread_local)
  end

  def test_extend_and_reacquire_scripts_are_same_object
    # EXTEND_SCRIPT and REACQUIRE_SCRIPT should reference the same constant
    # to avoid duplication
    assert_same RR::Lock::EXTEND_SCRIPT, RR::Lock::REACQUIRE_SCRIPT
  end
end
