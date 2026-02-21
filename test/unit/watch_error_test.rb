# frozen_string_literal: true

require_relative "unit_test_helper"

# Tests for redis-rb issue #772
# WatchError is provided as an exception class for user-level optimistic
# locking retry patterns. multi returns nil on watch abort (redis-rb convention),
# and users can raise WatchError themselves if desired.
class WatchErrorTest < Minitest::Test
  def test_watch_error_class_exists
    assert defined?(RR::WatchError)
  end

  def test_watch_error_inherits_from_error
    assert_operator RR::WatchError, :<, RR::Error
  end

  def test_watch_error_can_be_raised_and_rescued
    assert_raises(RR::WatchError) do
      raise RR::WatchError, "Watched variable changed"
    end
  end

  def test_watch_error_rescuable_as_rr_error
    assert_raises(RR::Error) do
      raise RR::WatchError, "Watched variable changed"
    end
  end

  def test_multi_returns_nil_when_watch_aborted
    client = RR::Client.new
    client.stubs(:ensure_connected)

    connection = mock("connection")
    connection.stubs(:call).with("MULTI").returns("OK")
    connection.stubs(:call).with("SET", "key", "value").returns("QUEUED")
    connection.stubs(:call).with("EXEC").returns(nil)

    client.instance_variable_set(:@connection, connection)

    # multi returns nil on aborted transaction (redis-rb convention)
    result = client.multi do |tx|
      tx.set("key", "value")
    end

    assert_nil result
  end

  def test_watch_block_returns_nil_on_aborted_exec
    client = RR::Client.new
    client.stubs(:ensure_connected)

    connection = mock("connection")
    connection.stubs(:call).with("WATCH", "key").returns("OK")
    connection.stubs(:call).with("MULTI").returns("OK")
    connection.stubs(:call).with("SET", "key", "new_value").returns("QUEUED")
    connection.stubs(:call).with("EXEC").returns(nil)
    connection.stubs(:call).with("UNWATCH").returns("OK")

    client.instance_variable_set(:@connection, connection)

    # watch block also returns nil, allowing user to detect and retry
    result = client.watch("key") do
      client.multi do |tx|
        tx.set("key", "new_value")
      end
    end

    assert_nil result
  end

  def test_user_can_raise_watch_error_in_retry_pattern
    # Demonstrates the intended usage pattern for WatchError
    assert_raises(RR::WatchError) do
      raise RR::WatchError, "Watched variable changed"
    end
  end
end
