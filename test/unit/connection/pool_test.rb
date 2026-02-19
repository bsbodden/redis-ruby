# frozen_string_literal: true

require_relative "../unit_test_helper"
require "socket"

class ConnectionPoolTest < Minitest::Test
  def setup
    @mock_socket = mock("socket")
    setup_mock_socket_options
  end

  def test_pool_initialization_with_defaults
    Socket.stubs(:tcp).returns(@mock_socket)

    pool = RR::Connection::Pool.new(host: "localhost", port: 6379)

    assert_equal 5, pool.size
    assert_equal 5, pool.timeout
  end

  def test_pool_initialization_with_custom_size
    Socket.stubs(:tcp).returns(@mock_socket)

    pool = RR::Connection::Pool.new(host: "localhost", port: 6379, size: 10)

    assert_equal 10, pool.size
  end

  def test_pool_initialization_with_custom_timeout
    Socket.stubs(:tcp).returns(@mock_socket)

    pool = RR::Connection::Pool.new(host: "localhost", port: 6379, pool_timeout: 10)

    assert_equal 10, pool.timeout
  end

  def test_pool_with_block_returns_result
    Socket.stubs(:tcp).returns(@mock_socket)
    setup_ping_response

    pool = RR::Connection::Pool.new(host: "localhost", port: 6379)

    result = pool.with do |conn|
      conn.call("PING")
    end

    assert_equal "PONG", result
  end

  def test_pool_reuses_connections
    Socket.stubs(:tcp).returns(@mock_socket)
    @mock_socket.stubs(:closed?).returns(false)

    pool = RR::Connection::Pool.new(host: "localhost", port: 6379, size: 1)

    # First checkout
    conn1 = nil
    pool.with { |c| conn1 = c }

    # Second checkout should get the same connection
    conn2 = nil
    pool.with { |c| conn2 = c }

    assert_same conn1, conn2
  end

  def test_pool_creates_connections_lazily
    # TCPSocket.new should not be called until we checkout
    Socket.expects(:tcp).never

    _pool = RR::Connection::Pool.new(host: "localhost", port: 6379, size: 5)
    # No assertions needed - just verifying TCPSocket.new wasn't called
  end

  def test_pool_creates_connection_on_first_checkout
    Socket.expects(:tcp).once.returns(@mock_socket)

    pool = RR::Connection::Pool.new(host: "localhost", port: 6379, size: 5)
    pool.with do |_conn|
      # Intentionally empty; verifying connection creation
    end
  end

  def test_pool_checkout_returns_connection
    Socket.stubs(:tcp).returns(@mock_socket)

    pool = RR::Connection::Pool.new(host: "localhost", port: 6379)

    pool.with do |conn|
      assert_instance_of RR::Connection::TCP, conn
    end
  end

  def test_pool_close_closes_all_connections
    Socket.stubs(:tcp).returns(@mock_socket)
    @mock_socket.stubs(:closed?).returns(false)

    pool = RR::Connection::Pool.new(host: "localhost", port: 6379, size: 2)

    # Create connections by checking them out
    pool.with do |_conn|
      # Intentionally empty; just triggering connection creation
    end

    @mock_socket.expects(:close).at_least_once

    pool.close
  end

  def test_pool_available_returns_count
    Socket.stubs(:tcp).returns(@mock_socket)
    @mock_socket.stubs(:closed?).returns(false)

    pool = RR::Connection::Pool.new(host: "localhost", port: 6379, size: 3)

    assert_equal 3, pool.available
  end

  def test_pool_with_circuit_breaker_delegates_execution
    Socket.stubs(:tcp).returns(@mock_socket)
    setup_ping_response

    cb_called = false
    cb = Object.new
    cb.define_singleton_method(:call) do |&blk|
      cb_called = true
      blk.call
    end

    pool = RR::Connection::Pool.new(host: "localhost", port: 6379, circuit_breaker: cb)

    result = pool.with do |conn|
      conn.call("PING")
    end

    assert cb_called, "Circuit breaker should have been called"
    assert_equal "PONG", result
  end

  private

  def setup_mock_socket_options
    @mock_socket.stubs(:setsockopt)
    @mock_socket.stubs(:sync=)
    @mock_socket.stubs(:closed?).returns(false)
    @mock_socket.stubs(:close)
  end

  def setup_ping_response
    @mock_socket.expects(:write).with("*1\r\n$4\r\nPING\r\n")
    # BufferedIO uses read_nonblock
    @mock_socket.expects(:read_nonblock).returns("+PONG\r\n")
  end
end
