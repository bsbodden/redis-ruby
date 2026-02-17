# frozen_string_literal: true

require_relative "../test_helper"

class RR::ConnectionCallbacksIntegrationTest < Minitest::Test
  def setup
    @events = []
  end

  def teardown
    @client&.close
  end

  # Test callbacks with Client
  def test_client_connection_callbacks
    @client = RR::Client.new(host: "localhost", port: 6379)

    # Register callbacks after connection is established
    @client.register_connection_callback(:reconnected) do |event|
      @events << [:reconnected, event]
    end

    @client.register_connection_callback(:disconnected) do |event|
      @events << [:disconnected, event]
    end

    # Trigger reconnect by accessing the connection directly
    conn = @client.instance_variable_get(:@connection)
    conn.disconnect
    conn.reconnect

    # Should have disconnected and reconnected events
    assert_equal 2, @events.size
    assert_equal :disconnected, @events[0][0]
    assert_equal :reconnected, @events[1][1][:type]
  end

  def test_client_error_callback
    # Create client with invalid host
    @client = RR::Client.allocate
    @client.instance_variable_set(:@host, "nonexistent.invalid")
    @client.instance_variable_set(:@port, 6379)
    @client.instance_variable_set(:@timeout, 0.1)
    @client.instance_variable_set(:@reconnect_attempts, 0)
    @client.instance_variable_set(:@retry_policy, nil)
    @client.instance_variable_set(:@instrumentation, nil)
    @client.instance_variable_set(:@circuit_breaker, nil)
    
    # Create connection manually
    conn = RR::Connection::TCP.allocate
    conn.instance_variable_set(:@host, "nonexistent.invalid")
    conn.instance_variable_set(:@port, 6379)
    conn.instance_variable_set(:@timeout, 0.1)
    conn.instance_variable_set(:@encoder, RR::Protocol::RESP3Encoder.new)
    conn.instance_variable_set(:@socket, nil)
    conn.instance_variable_set(:@buffered_io, nil)
    conn.instance_variable_set(:@decoder, nil)
    conn.instance_variable_set(:@pid, nil)
    conn.instance_variable_set(:@callbacks, Hash.new { |h, k| h[k] = [] })
    conn.instance_variable_set(:@ever_connected, false)
    
    conn.register_callback(:error) do |event|
      @events << [:error, event]
    end
    
    @client.instance_variable_set(:@connection, conn)
    
    assert_raises(RR::ConnectionError) do
      conn.send(:connect)
    end
    
    assert_equal 1, @events.size
    assert_equal :error, @events[0][0]
    assert_kind_of StandardError, @events[0][1][:error]
  end

  def test_multiple_callbacks_for_same_event
    @client = RR::Client.new(host: "localhost", port: 6379)

    callback1_called = false
    callback2_called = false

    @client.register_connection_callback(:disconnected) do |event|
      callback1_called = true
    end

    @client.register_connection_callback(:disconnected) do |event|
      callback2_called = true
    end

    conn = @client.instance_variable_get(:@connection)
    conn.disconnect

    assert callback1_called, "First callback should be called"
    assert callback2_called, "Second callback should be called"
  end

  def test_callback_deregistration
    @client = RR::Client.new(host: "localhost", port: 6379)

    callback_called = false
    callback = ->(event) { callback_called = true }

    @client.register_connection_callback(:disconnected, callback)
    @client.deregister_connection_callback(:disconnected, callback)

    conn = @client.instance_variable_get(:@connection)
    conn.disconnect

    refute callback_called, "Deregistered callback should not be called"
  end

  def test_callback_errors_dont_break_connection
    @client = RR::Client.new(host: "localhost", port: 6379)

    # Register a callback that raises an error
    @client.register_connection_callback(:disconnected) do |event|
      raise "Callback error!"
    end

    # Register another callback that should still be called
    second_callback_called = false
    @client.register_connection_callback(:disconnected) do |event|
      second_callback_called = true
    end

    # Disconnect should not raise, and second callback should be called
    # Suppress stderr output to avoid cluttering test output
    conn = @client.instance_variable_get(:@connection)

    # Capture stderr to suppress the expected warning
    original_stderr = $stderr
    $stderr = StringIO.new

    begin
      conn.disconnect
    ensure
      $stderr = original_stderr
    end

    assert second_callback_called, "Second callback should be called despite first callback error"
  end

  def test_reconnect_triggers_reconnected_event
    @client = RR::Client.new(host: "localhost", port: 6379)

    reconnected = false
    @client.register_connection_callback(:reconnected) do |event|
      reconnected = true
    end

    conn = @client.instance_variable_get(:@connection)
    conn.disconnect
    conn.reconnect

    assert reconnected, "Reconnected callback should be triggered"
  end
end

