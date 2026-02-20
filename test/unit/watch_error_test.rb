# frozen_string_literal: true

require_relative "unit_test_helper"

# Tests for redis-rb issue #772
# WatchError should be raised when EXEC returns nil inside a watch block,
# following redis-py's pattern for optimistic locking.
class WatchErrorTest < Minitest::Test
  def test_watch_error_class_exists
    assert defined?(RR::WatchError)
  end

  def test_watch_error_inherits_from_error
    assert RR::WatchError < RR::Error
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
    # Transaction#execute returns nil when EXEC returns nil (watch aborted)
    # The client's multi method should raise WatchError in this case
    # when inside a watch block
    client = RR::Client.new
    client.stubs(:ensure_connected)

    connection = mock("connection")
    connection.stubs(:call).returns("OK")  # WATCH returns OK

    # EXEC returns nil when watched keys were modified
    transaction = RR::Transaction.new(connection)
    connection.stubs(:call).with("MULTI").returns("OK")
    connection.stubs(:call).with("SET", "key", "value").returns("QUEUED")
    connection.stubs(:call).with("EXEC").returns(nil)

    client.instance_variable_set(:@connection, connection)

    # multi returns nil when EXEC returns nil
    result = client.multi do |tx|
      tx.set("key", "value")
    end

    assert_nil result
  end

  def test_watch_block_raises_watch_error_on_aborted_exec
    client = RR::Client.new
    client.stubs(:ensure_connected)

    connection = mock("connection")
    # WATCH returns OK, then EXEC returns nil, then UNWATCH returns OK
    connection.stubs(:call).with("WATCH", "key").returns("OK")
    connection.stubs(:call).with("MULTI").returns("OK")
    connection.stubs(:call).with("SET", "key", "new_value").returns("QUEUED")
    connection.stubs(:call).with("EXEC").returns(nil)
    connection.stubs(:call).with("UNWATCH").returns("OK")

    client.instance_variable_set(:@connection, connection)

    assert_raises(RR::WatchError) do
      client.watch("key") do
        client.multi do |tx|
          tx.set("key", "new_value")
        end
      end
    end
  end
end
