# frozen_string_literal: true

require_relative "../test_helper"

module RR
  class ConnectionCallbacksTest < Minitest::Test
    def setup
      @connection = build_unconnected_tcp("localhost", 6379)
      @events = []
    end

    def teardown
      @connection.close if @connection.connected?
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
      skip "Redis server not available" unless redis_available?

      conn = build_unconnected_tcp("localhost", 6379, timeout: 5.0)
      conn.register_callback(:connected) { |event| @events << event }
      conn.send(:connect)

      assert_callback_event(:connected, host: "localhost", port: 6379)
      conn.close if conn.connected?
    end

    def test_disconnected_callback_invoked_on_disconnect
      # Use a mock socket so the connection appears connected
      @connection.instance_variable_set(:@socket, build_mock_socket)

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
      skip "Redis server not available" unless redis_available?

      conn = RR::Connection::TCP.new(host: "localhost", port: 6379)
      conn.disconnect

      conn.register_callback(:reconnected) do |event|
        @events << event
      end

      conn.reconnect

      assert_equal 1, @events.size
      event = @events.first

      assert_equal :reconnected, event[:type]
      assert_equal "localhost", event[:host]
      assert_equal 6379, event[:port]
      assert_instance_of Time, event[:timestamp]
      conn.close if conn.connected?
    end

    def test_error_callback_invoked_on_connection_error
      bad_conn = build_unconnected_tcp("nonexistent.invalid", 6379, timeout: 0.1)
      bad_conn.register_callback(:error) { |event| @events << event }

      assert_raises(RR::ConnectionError) { bad_conn.send(:connect) }

      assert_callback_event(:error)
      assert_kind_of StandardError, @events.first[:error]
    end

    private

    def redis_available?
      socket = TCPSocket.new("localhost", 6379)
      socket.close
      true
    rescue StandardError
      false
    end

    def build_unconnected_tcp(host, port, timeout: 5.0)
      conn = RR::Connection::TCP.allocate
      { host: host, port: port, timeout: timeout,
        encoder: RR::Protocol::RESP3Encoder.new,
        socket: nil, buffered_io: nil, decoder: nil, pid: nil,
        ever_connected: false, }.each { |k, v| conn.instance_variable_set(:"@#{k}", v) }
      conn.instance_variable_set(:@callbacks, Hash.new { |h, k| h[k] = [] })
      conn
    end

    def build_mock_socket
      socket = Object.new
      state = { closed: false }
      socket.define_singleton_method(:closed?) { state[:closed] }
      socket.define_singleton_method(:close) { state[:closed] = true }
      socket
    end

    def assert_callback_event(type, host: nil, port: nil)
      assert_equal 1, @events.size
      event = @events.first

      assert_equal type, event[:type]
      assert_equal host, event[:host] if host
      assert_equal port, event[:port] if port

      assert_instance_of Time, event[:timestamp]
    end
  end
end
