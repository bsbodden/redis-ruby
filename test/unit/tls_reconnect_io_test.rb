# frozen_string_literal: true

require_relative "unit_test_helper"

# Tests for redis-rb issue #972
# TLS reconnection must handle non-blocking IO states
# (WaitReadable, WaitWritable) during the SSL handshake phase.
class TLSReconnectIOTest < Minitest::Test
  def test_ssl_setup_handles_wait_readable_during_handshake
    # The SSL handshake can raise IO::WaitReadable on non-blocking sockets
    # The connection should retry the handshake after waiting
    ssl_socket = mock("ssl_socket")
    ssl_socket.stubs(:hostname=)
    ssl_socket.stubs(:post_connection_check)

    tcp_socket = mock("tcp_socket")
    tcp_socket.stubs(:setsockopt)
    tcp_socket.stubs(:closed?).returns(false)
    tcp_socket.stubs(:wait_readable).returns(true)

    ssl_context = mock("ssl_context")

    # First connect returns :wait_readable, second succeeds
    seq = sequence("handshake")
    ssl_socket.expects(:connect_nonblock).with(exception: false).returns(:wait_readable).in_sequence(seq)
    ssl_socket.expects(:connect_nonblock).with(exception: false).returns(ssl_socket).in_sequence(seq)

    conn = RR::Connection::SSL.allocate
    conn.instance_variable_set(:@tcp_socket, tcp_socket)
    conn.instance_variable_set(:@host, "localhost")
    conn.instance_variable_set(:@timeout, 5.0)
    conn.instance_variable_set(:@ssl_params, {})

    OpenSSL::SSL::SSLSocket.stubs(:new).returns(ssl_socket)

    conn.send(:setup_ssl_layer_with_timeout, ssl_context)
  end

  def test_ssl_setup_handles_wait_writable_during_handshake
    ssl_socket = mock("ssl_socket")
    ssl_socket.stubs(:hostname=)
    ssl_socket.stubs(:post_connection_check)

    tcp_socket = mock("tcp_socket")
    tcp_socket.stubs(:setsockopt)
    tcp_socket.stubs(:closed?).returns(false)
    tcp_socket.stubs(:wait_writable).returns(true)

    ssl_context = mock("ssl_context")

    seq = sequence("handshake")
    ssl_socket.expects(:connect_nonblock).with(exception: false).returns(:wait_writable).in_sequence(seq)
    ssl_socket.expects(:connect_nonblock).with(exception: false).returns(ssl_socket).in_sequence(seq)

    conn = RR::Connection::SSL.allocate
    conn.instance_variable_set(:@tcp_socket, tcp_socket)
    conn.instance_variable_set(:@host, "localhost")
    conn.instance_variable_set(:@timeout, 5.0)
    conn.instance_variable_set(:@ssl_params, {})

    OpenSSL::SSL::SSLSocket.stubs(:new).returns(ssl_socket)

    conn.send(:setup_ssl_layer_with_timeout, ssl_context)
  end

  def test_ssl_setup_timeout_during_handshake
    ssl_socket = mock("ssl_socket")
    ssl_socket.stubs(:hostname=)
    ssl_socket.stubs(:close)

    # Always returns :wait_readable (never completes)
    ssl_socket.stubs(:connect_nonblock).with(exception: false).returns(:wait_readable)

    tcp_socket = mock("tcp_socket")
    tcp_socket.stubs(:setsockopt)
    tcp_socket.stubs(:closed?).returns(false)
    tcp_socket.stubs(:close)
    # wait_readable returns nil on timeout
    tcp_socket.stubs(:wait_readable).returns(nil)

    ssl_context = mock("ssl_context")

    conn = RR::Connection::SSL.allocate
    conn.instance_variable_set(:@tcp_socket, tcp_socket)
    conn.instance_variable_set(:@host, "localhost")
    conn.instance_variable_set(:@timeout, 0.1)
    conn.instance_variable_set(:@ssl_params, {})

    OpenSSL::SSL::SSLSocket.stubs(:new).returns(ssl_socket)

    assert_raises(RR::TimeoutError) do
      conn.send(:setup_ssl_layer_with_timeout, ssl_context)
    end
  end
end
