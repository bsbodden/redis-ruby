# frozen_string_literal: true

require_relative "../test_helper"

class RR::ConnectionCallbacksTest < Minitest::Test
  def setup
    @connection = RR::Connection::TCP.new(host: "localhost", port: 6379)
    @events = []
  end

  def teardown
    @connection.disconnect if @connection.connected?
  end

  # Test callback registration
  def test_register_callback
    callback = ->(event) { @events << event }
    @connection.register_callback(:connected, callback)
    
    assert_includes @connection.instance_variable_get(:@callbacks)[:connected], callback
  end

  def test_register_multiple_callbacks_for_same_event
    callback1 = ->(event) { @events << [:cb1, event] }
    callback2 = ->(event) { @events << [:cb2, event] }
    
    @connection.register_callback(:connected, callback1)
    @connection.register_callback(:connected, callback2)
    
    callbacks = @connection.instance_variable_get(:@callbacks)[:connected]
    assert_equal 2, callbacks.size
    assert_includes callbacks, callback1
    assert_includes callbacks, callback2
  end

  def test_register_callback_for_different_events
    connected_cb = ->(event) { @events << [:connected, event] }
    disconnected_cb = ->(event) { @events << [:disconnected, event] }
    
    @connection.register_callback(:connected, connected_cb)
    @connection.register_callback(:disconnected, disconnected_cb)
    
    assert_includes @connection.instance_variable_get(:@callbacks)[:connected], connected_cb
    assert_includes @connection.instance_variable_get(:@callbacks)[:disconnected], disconnected_cb
  end

  def test_register_callback_raises_for_invalid_event_type
    callback = ->(event) { @events << event }
    
    error = assert_raises(ArgumentError) do
      @connection.register_callback(:invalid_event, callback)
    end
    
    assert_match(/Invalid event type/, error.message)
  end

  # Test callback deregistration
  def test_deregister_callback
    callback = ->(event) { @events << event }
    @connection.register_callback(:connected, callback)
    @connection.deregister_callback(:connected, callback)
    
    refute_includes @connection.instance_variable_get(:@callbacks)[:connected], callback
  end

  def test_deregister_specific_callback_leaves_others
    callback1 = ->(event) { @events << [:cb1, event] }
    callback2 = ->(event) { @events << [:cb2, event] }
    
    @connection.register_callback(:connected, callback1)
    @connection.register_callback(:connected, callback2)
    @connection.deregister_callback(:connected, callback1)
    
    callbacks = @connection.instance_variable_get(:@callbacks)[:connected]
    refute_includes callbacks, callback1
    assert_includes callbacks, callback2
  end

  def test_deregister_nonexistent_callback_does_not_raise
    callback = ->(event) { @events << event }
    
    # Should not raise
    @connection.deregister_callback(:connected, callback)
  end

  # Test callback invocation
  def test_connected_callback_invoked_on_connect
    # Connection is created in setup, which triggers connect
    # So we need to create a new connection with callback registered first
    @connection.disconnect if @connection.connected?

    # Create a new connection that hasn't connected yet
    conn = RR::Connection::TCP.allocate
    conn.instance_variable_set(:@host, "localhost")
    conn.instance_variable_set(:@port, 6379)
    conn.instance_variable_set(:@timeout, 5.0)
    conn.instance_variable_set(:@encoder, RR::Protocol::RESP3Encoder.new)
    conn.instance_variable_set(:@socket, nil)
    conn.instance_variable_set(:@buffered_io, nil)
    conn.instance_variable_set(:@decoder, nil)
    conn.instance_variable_set(:@pid, nil)
    conn.instance_variable_set(:@callbacks, Hash.new { |h, k| h[k] = [] })
    conn.instance_variable_set(:@ever_connected, false)

    conn.register_callback(:connected) do |event|
      @events << event
    end

    conn.send(:connect)

    assert_equal 1, @events.size
    event = @events.first
    assert_equal :connected, event[:type]
    assert_equal "localhost", event[:host]
    assert_equal 6379, event[:port]
    assert_instance_of Time, event[:timestamp]

    conn.disconnect if conn.connected?
  end

  def test_disconnected_callback_invoked_on_disconnect
    @connection.register_callback(:disconnected) do |event|
      @events << event
    end

    @connection.disconnect

    assert_equal 1, @events.size
    event = @events.first
    assert_equal :disconnected, event[:type]
    assert_equal "localhost", event[:host]
    assert_equal 6379, event[:port]
    assert_instance_of Time, event[:timestamp]
  end

  def test_reconnected_callback_invoked_on_reconnect
    @connection.disconnect

    @connection.register_callback(:reconnected) do |event|
      @events << event
    end

    @connection.reconnect

    assert_equal 1, @events.size
    event = @events.first
    assert_equal :reconnected, event[:type]
    assert_equal "localhost", event[:host]
    assert_equal 6379, event[:port]
    assert_instance_of Time, event[:timestamp]
  end

  def test_error_callback_invoked_on_connection_error
    # Create connection to invalid host to trigger error
    # Need to use allocate to avoid calling initialize which calls connect
    bad_connection = RR::Connection::TCP.allocate
    bad_connection.instance_variable_set(:@host, "nonexistent.invalid")
    bad_connection.instance_variable_set(:@port, 6379)
    bad_connection.instance_variable_set(:@timeout, 0.1)
    bad_connection.instance_variable_set(:@encoder, RR::Protocol::RESP3Encoder.new)
    bad_connection.instance_variable_set(:@socket, nil)
    bad_connection.instance_variable_set(:@buffered_io, nil)
    bad_connection.instance_variable_set(:@decoder, nil)
    bad_connection.instance_variable_set(:@pid, nil)
    bad_connection.instance_variable_set(:@callbacks, Hash.new { |h, k| h[k] = [] })
    bad_connection.instance_variable_set(:@ever_connected, false)

    bad_connection.register_callback(:error) do |event|
      @events << event
    end

    assert_raises(RR::ConnectionError) do
      bad_connection.send(:connect)
    end

    assert_equal 1, @events.size
    event = @events.first
    assert_equal :error, event[:type]
    assert_kind_of StandardError, event[:error]
    assert_instance_of Time, event[:timestamp]
  end
end

