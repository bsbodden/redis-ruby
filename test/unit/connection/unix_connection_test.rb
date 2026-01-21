# frozen_string_literal: true

require_relative "../unit_test_helper"
require "socket"

class UnixConnectionTest < Minitest::Test
  def setup
    @mock_socket = mock("unix_socket")
  end

  def test_default_path
    UNIXSocket.expects(:new).with("/var/run/redis/redis.sock").returns(@mock_socket)
    setup_socket_options

    conn = RedisRuby::Connection::Unix.new

    assert_equal "/var/run/redis/redis.sock", conn.path
  end

  def test_custom_path
    UNIXSocket.expects(:new).with("/tmp/redis.sock").returns(@mock_socket)
    setup_socket_options

    conn = RedisRuby::Connection::Unix.new(path: "/tmp/redis.sock")

    assert_equal "/tmp/redis.sock", conn.path
  end

  def test_call_encodes_and_sends_command
    UNIXSocket.expects(:new).returns(@mock_socket)
    setup_socket_options

    expected_encoded = "*1\r\n$4\r\nPING\r\n"

    @mock_socket.expects(:write).with(expected_encoded)
    @mock_socket.expects(:flush)
    @mock_socket.expects(:getbyte).returns(43) # '+'
    @mock_socket.expects(:gets).with("\r\n").returns("PONG\r\n")

    conn = RedisRuby::Connection::Unix.new
    result = conn.call("PING")

    assert_equal "PONG", result
  end

  def test_connected_returns_true_when_open
    UNIXSocket.expects(:new).returns(@mock_socket)
    setup_socket_options
    @mock_socket.stubs(:closed?).returns(false)

    conn = RedisRuby::Connection::Unix.new

    assert conn.connected?
  end

  def test_connected_returns_false_when_closed
    UNIXSocket.expects(:new).returns(@mock_socket)
    setup_socket_options
    @mock_socket.stubs(:closed?).returns(true)

    conn = RedisRuby::Connection::Unix.new

    refute conn.connected?
  end

  def test_close_closes_socket
    UNIXSocket.expects(:new).returns(@mock_socket)
    setup_socket_options
    @mock_socket.expects(:close)

    conn = RedisRuby::Connection::Unix.new
    conn.close
  end

  def test_socket_not_found_raises_connection_error
    UNIXSocket.expects(:new).raises(Errno::ENOENT)

    assert_raises(RedisRuby::ConnectionError) do
      RedisRuby::Connection::Unix.new(path: "/nonexistent/redis.sock")
    end
  end

  def test_permission_denied_raises_connection_error
    UNIXSocket.expects(:new).raises(Errno::EACCES)

    assert_raises(RedisRuby::ConnectionError) do
      RedisRuby::Connection::Unix.new(path: "/root/redis.sock")
    end
  end

  def test_connection_refused_raises_connection_error
    UNIXSocket.expects(:new).raises(Errno::ECONNREFUSED)

    assert_raises(RedisRuby::ConnectionError) do
      RedisRuby::Connection::Unix.new
    end
  end

  private

  def setup_socket_options
    @mock_socket.stubs(:sync=)
    @mock_socket.stubs(:closed?).returns(false)
    @mock_socket.stubs(:close)
  end
end
