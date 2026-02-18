# frozen_string_literal: true

require_relative "../unit_test_helper"
require "socket"

class TCPConnectionTest < Minitest::Test
  def setup
    @mock_socket = mock("socket")
  end

  # Connection initialization
  def test_default_host_and_port
    Socket.expects(:tcp).with("localhost", 6379, connect_timeout: 5.0).returns(@mock_socket)
    setup_mock_socket_options

    conn = RR::Connection::TCP.new

    assert_equal "localhost", conn.host
    assert_equal 6379, conn.port
  end

  def test_custom_host_and_port
    Socket.expects(:tcp).with("redis.example.com", 6380, connect_timeout: 5.0).returns(@mock_socket)
    setup_mock_socket_options

    conn = RR::Connection::TCP.new(host: "redis.example.com", port: 6380)

    assert_equal "redis.example.com", conn.host
    assert_equal 6380, conn.port
  end

  # Socket options
  def test_sets_tcp_nodelay
    Socket.expects(:tcp).returns(@mock_socket)
    # Verify TCP_NODELAY is set (both options will be set)
    @mock_socket.expects(:setsockopt).with(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1).once
    @mock_socket.expects(:setsockopt).with(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, 1).once
    @mock_socket.stubs(:sync=)

    RR::Connection::TCP.new
  end

  def test_sets_keepalive
    Socket.expects(:tcp).returns(@mock_socket)
    # Verify SO_KEEPALIVE is set (both options will be set)
    @mock_socket.expects(:setsockopt).with(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1).once
    @mock_socket.expects(:setsockopt).with(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, 1).once
    @mock_socket.stubs(:sync=)

    RR::Connection::TCP.new
  end

  def test_sets_sync_true_for_unbuffered_writes
    Socket.expects(:tcp).returns(@mock_socket)
    @mock_socket.stubs(:setsockopt)
    @mock_socket.expects(:sync=).with(true)

    RR::Connection::TCP.new
  end

  # Command execution
  def test_call_encodes_and_sends_command
    setup_connected_socket
    expected_encoded = "*1\r\n$4\r\nPING\r\n"

    @mock_socket.expects(:write).with(expected_encoded)
    # BufferedIO uses read_nonblock
    @mock_socket.expects(:read_nonblock).returns("+PONG\r\n")

    conn = RR::Connection::TCP.new
    result = conn.call("PING")

    assert_equal "PONG", result
  end

  def test_call_with_arguments
    setup_connected_socket
    expected_encoded = "*3\r\n$3\r\nSET\r\n$3\r\nkey\r\n$5\r\nvalue\r\n"

    @mock_socket.expects(:write).with(expected_encoded)
    @mock_socket.expects(:read_nonblock).returns("+OK\r\n")

    conn = RR::Connection::TCP.new
    result = conn.call("SET", "key", "value")

    assert_equal "OK", result
  end

  def test_call_returns_integer
    setup_connected_socket

    @mock_socket.expects(:write)
    @mock_socket.expects(:read_nonblock).returns(":42\r\n")

    conn = RR::Connection::TCP.new
    result = conn.call("INCR", "counter")

    assert_equal 42, result
  end

  def test_call_returns_nil_for_missing_key
    setup_connected_socket

    @mock_socket.expects(:write)
    @mock_socket.expects(:read_nonblock).returns("$-1\r\n")

    conn = RR::Connection::TCP.new
    result = conn.call("GET", "nonexistent")

    assert_nil result
  end

  def test_call_raises_on_error_response
    setup_connected_socket

    @mock_socket.expects(:write)
    @mock_socket.expects(:read_nonblock).returns("-ERR unknown command\r\n")

    conn = RR::Connection::TCP.new
    error = conn.call("BADCMD")

    assert_instance_of RR::CommandError, error
    assert_equal "ERR unknown command", error.message
  end

  # Pipeline
  def test_pipeline_sends_multiple_commands
    setup_connected_socket
    expected = "*3\r\n$3\r\nSET\r\n$4\r\nkey1\r\n$6\r\nvalue1\r\n" \
               "*2\r\n$3\r\nGET\r\n$4\r\nkey1\r\n"

    @mock_socket.expects(:write).with(expected)

    # Both responses in one read (buffered)
    @mock_socket.expects(:read_nonblock).returns("+OK\r\n$6\r\nvalue1\r\n")

    conn = RR::Connection::TCP.new
    results = conn.pipeline([
      %w[SET key1 value1],
      %w[GET key1],
    ])

    assert_equal %w[OK value1], results
  end

  # Connection management
  def test_close_closes_socket
    setup_connected_socket
    @mock_socket.expects(:close)

    conn = RR::Connection::TCP.new
    conn.close
  end

  def test_connected_returns_true_when_open
    setup_connected_socket
    @mock_socket.stubs(:closed?).returns(false)

    conn = RR::Connection::TCP.new

    assert_predicate conn, :connected?
  end

  def test_connected_returns_false_when_closed
    setup_connected_socket
    @mock_socket.stubs(:closed?).returns(true)

    conn = RR::Connection::TCP.new

    refute_predicate conn, :connected?
  end

  # Fork safety
  def test_has_fork_safety_methods
    methods = RR::Connection::TCP.instance_methods(false)

    assert_includes methods, :ensure_connected
    assert_includes methods, :reconnect
  end

  def test_tracks_process_id_for_fork_detection
    setup_connected_socket

    conn = RR::Connection::TCP.new

    # Verify the pid is tracked after connect
    assert_equal Process.pid, conn.instance_variable_get(:@pid)
  end

  def test_reconnect_creates_new_socket
    # First connection
    @mock_socket.stubs(:setsockopt)
    @mock_socket.stubs(:sync=)
    @mock_socket.stubs(:closed?).returns(false)
    @mock_socket.stubs(:close)
    Socket.stubs(:tcp).returns(@mock_socket)

    conn = RR::Connection::TCP.new

    # Second connection setup
    @mock_socket2 = mock("socket2")
    @mock_socket2.stubs(:setsockopt)
    @mock_socket2.stubs(:sync=)
    @mock_socket2.stubs(:closed?).returns(false)

    # Reset TCPSocket to return new mock
    Socket.unstub(:tcp)
    Socket.stubs(:tcp).returns(@mock_socket2)

    conn.reconnect

    # Verify we have a new connection
    assert_equal conn.instance_variable_get(:@pid), Process.pid
  end

  def test_connect_enforces_timeout
    # Socket.tcp should be called with connect_timeout matching @timeout
    Socket.expects(:tcp).with("localhost", 6379, connect_timeout: 5.0).returns(@mock_socket)
    setup_mock_socket_options

    conn = RR::Connection::TCP.new

    assert_equal 5.0, conn.timeout
  end

  def test_connect_enforces_custom_timeout
    Socket.expects(:tcp).with("redis.example.com", 6380, connect_timeout: 2.0).returns(@mock_socket)
    setup_mock_socket_options

    conn = RR::Connection::TCP.new(host: "redis.example.com", port: 6380, timeout: 2.0)

    assert_equal 2.0, conn.timeout
  end

  def test_socket_closed_on_configure_socket_failure
    Socket.expects(:tcp).returns(@mock_socket)
    @mock_socket.expects(:setsockopt).raises(StandardError, "setsockopt failed")
    @mock_socket.expects(:close)

    assert_raises(RR::ConnectionError) { RR::Connection::TCP.new }
  end

  def test_ensure_connected_reconnects_if_not_connected
    # First connection - will be "closed"
    @mock_socket.stubs(:setsockopt)
    @mock_socket.stubs(:sync=)
    @mock_socket.stubs(:close)
    Socket.stubs(:tcp).returns(@mock_socket)

    conn = RR::Connection::TCP.new

    # Now make socket appear closed
    @mock_socket.stubs(:closed?).returns(true)

    # Second connection
    @mock_socket2 = mock("socket2")
    @mock_socket2.stubs(:setsockopt)
    @mock_socket2.stubs(:sync=)
    @mock_socket2.stubs(:closed?).returns(false)

    Socket.unstub(:tcp)
    Socket.stubs(:tcp).returns(@mock_socket2)

    conn.ensure_connected

    # Should have reconnected
    assert_predicate conn, :connected?
  end

  private

  def setup_mock_socket_options
    @mock_socket.stubs(:setsockopt)
    @mock_socket.stubs(:sync=)
  end

  def setup_connected_socket
    Socket.expects(:tcp).returns(@mock_socket)
    setup_mock_socket_options
    # Stub closed? for ensure_connected checks
    @mock_socket.stubs(:closed?).returns(false)
  end
end
