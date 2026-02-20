# frozen_string_literal: true

require_relative "unit_test_helper"

# Tests for redis-rb issue #1259
# subscribe_with_timeout must not leak connections when called in a loop.
# The connection must be reused and properly exit pub/sub mode after timeout.
class PubSubConnectionLeakTest < Minitest::Test
  def test_subscribe_with_timeout_reuses_connection
    client = RR::Client.new
    client.stubs(:ensure_connected)

    connection = mock("connection")
    connection.stubs(:connected?).returns(true)
    connection.stubs(:write_command)

    # First subscribe: subscribe confirmation, then timeout, then unsubscribe confirmation
    subscribe_msg = ["subscribe", "channel", 1]
    unsubscribe_msg = ["unsubscribe", "channel", 0]

    connection.stubs(:read_response).returns(subscribe_msg)
      .then.raises(RR::TimeoutError.new("read timeout"))
      .then.returns(unsubscribe_msg)

    client.instance_variable_set(:@connection, connection)

    client.subscribe_with_timeout(0.1, "channel") do |on|
      on.message { |_ch, _msg| }
    end

    # Connection should still be the same object (not leaked)
    assert_equal connection, client.instance_variable_get(:@connection)
  end

  def test_cleanup_drains_unsubscribe_confirmation
    client = RR::Client.new
    client.stubs(:ensure_connected)

    connection = mock("connection")
    connection.stubs(:connected?).returns(true)
    connection.stubs(:write_command)

    # Subscribe confirmation, timeout, unsubscribe sent, then confirmation comes
    call_count = 0
    connection.stubs(:read_response).with(timeout: anything) do
      call_count += 1
      case call_count
      when 1
        ["subscribe", "ch", 1]
      when 2
        raise RR::TimeoutError, "timeout"
      when 3
        ["unsubscribe", "ch", 0]
      end
    end

    client.instance_variable_set(:@connection, connection)

    client.subscribe_with_timeout(0.1, "ch") do |on|
      on.message { |_ch, _msg| }
    end
  end

  def test_compute_read_timeout_never_negative
    # Verify that compute_read_timeout returns a positive minimum timeout
    # even after the deadline has passed (to allow reading unsubscribe confirmation)
    client = RR::Client.new
    client.stubs(:ensure_connected)

    past_deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) - 10
    result = client.send(:compute_read_timeout, 0.5, past_deadline)

    assert_operator result, :>, 0, "compute_read_timeout must return positive value even after deadline"
  end

  def test_subscription_connection_cleared_after_timeout
    client = RR::Client.new
    client.stubs(:ensure_connected)

    connection = mock("connection")
    connection.stubs(:connected?).returns(true)
    connection.stubs(:write_command)
    connection.stubs(:read_response).returns(
      ["subscribe", "ch", 1]
    ).then.raises(
      RR::TimeoutError.new("timeout")
    ).then.returns(
      ["unsubscribe", "ch", 0]
    )

    client.instance_variable_set(:@connection, connection)

    client.subscribe_with_timeout(0.1, "ch") do |on|
      on.message { |_ch, _msg| }
    end

    # @subscription_connection should be nil after cleanup
    assert_nil client.instance_variable_get(:@subscription_connection)
  end
end
