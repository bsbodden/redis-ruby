# frozen_string_literal: true

require_relative "../unit_test_helper"

class SSLConnectionTest < Minitest::Test
  # SSL connection tests are simpler - we just test the interface
  # Full SSL testing requires actual SSL server (integration tests)

  def test_ssl_class_exists
    assert defined?(RR::Connection::SSL)
  end

  def test_ssl_default_values
    # Test that defaults are defined
    assert_equal "localhost", RR::Connection::SSL::DEFAULT_HOST
    assert_equal 6379, RR::Connection::SSL::DEFAULT_PORT
    assert_in_delta(5.0, RR::Connection::SSL::DEFAULT_TIMEOUT)
  end

  def test_ssl_has_required_methods
    methods = RR::Connection::SSL.instance_methods(false)

    assert_includes methods, :host
    assert_includes methods, :port
    assert_includes methods, :timeout
    assert_includes methods, :call
    assert_includes methods, :pipeline
    assert_includes methods, :close
    assert_includes methods, :connected?
    # Fork safety methods
    assert_includes methods, :ensure_connected
    assert_includes methods, :reconnect
  end

  def test_close_does_not_raise_when_tcp_socket_already_closed
    # When SSL socket is closed, it also closes the underlying TCP socket.
    # Closing the TCP socket again should not raise IOError.
    ssl_conn = RR::Connection::SSL.allocate
    ssl_socket = mock("ssl_socket")
    tcp_socket = mock("tcp_socket")

    ssl_socket.expects(:close).once
    tcp_socket.stubs(:closed?).returns(true) # already closed by SSL close
    tcp_socket.expects(:close).never # should not attempt to close again

    ssl_conn.instance_variable_set(:@ssl_socket, ssl_socket)
    ssl_conn.instance_variable_set(:@tcp_socket, tcp_socket)

    ssl_conn.close # should not raise
  end
end
