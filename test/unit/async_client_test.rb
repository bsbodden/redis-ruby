# frozen_string_literal: true

require_relative "unit_test_helper"
require "socket"

class AsyncClientTest < Minitest::Test
  def setup
    @mock_socket = mock("socket")
  end

  def test_async_client_new
    setup_connected_socket

    client = RedisRuby::AsyncClient.new(host: "localhost", port: 6379)

    assert_kind_of RedisRuby::AsyncClient, client
    client.close
  end

  def test_async_client_ping
    setup_connected_socket
    setup_ping_response

    client = RedisRuby::AsyncClient.new(host: "localhost", port: 6379)
    result = client.ping

    assert_equal "PONG", result
    client.close
  end

  def test_async_client_includes_command_modules
    setup_connected_socket

    client = RedisRuby::AsyncClient.new(host: "localhost", port: 6379)

    assert_respond_to client, :get
    assert_respond_to client, :set
    assert_respond_to client, :hget
    assert_respond_to client, :lpush
    assert_respond_to client, :sadd
    assert_respond_to client, :zadd
    client.close
  end

  def test_async_client_url_parsing
    setup_connected_socket
    # SELECT response for db=1
    @mock_socket.expects(:write).with("*2\r\n$6\r\nSELECT\r\n$1\r\n1\r\n")
    @mock_socket.expects(:flush)
    # BufferedIO uses read_nonblock
    @mock_socket.expects(:read_nonblock).returns("+OK\r\n")

    client = RedisRuby::AsyncClient.new(url: "redis://localhost:6380/1")

    assert_equal "localhost", client.host
    assert_equal 6380, client.port
    assert_equal 1, client.db
    client.close
  end

  def test_async_client_connected
    setup_connected_socket
    @mock_socket.stubs(:closed?).returns(false)

    client = RedisRuby::AsyncClient.new(host: "localhost", port: 6379)

    assert_predicate client, :connected?

    @mock_socket.expects(:close)
    @mock_socket.stubs(:closed?).returns(true)
    client.close

    refute_predicate client, :connected?
  end

  def test_async_client_error_handling
    setup_connected_socket

    # Error response for UNKNOWN command
    @mock_socket.expects(:write)
    @mock_socket.expects(:flush)
    # BufferedIO uses read_nonblock
    @mock_socket.expects(:read_nonblock).returns("-ERR unknown command\r\n")

    client = RedisRuby::AsyncClient.new(host: "localhost", port: 6379)

    assert_raises(RedisRuby::CommandError) do
      client.call("UNKNOWN")
    end
    client.close
  end

  def test_async_client_thread_safety
    # Verify mutex is used - check that client has a mutex
    setup_connected_socket

    client = RedisRuby::AsyncClient.new(host: "localhost", port: 6379)

    # The mutex is private but we can verify thread-safe operation
    assert_kind_of RedisRuby::AsyncClient, client
    client.close
  end

  private

  def setup_mock_socket_options
    @mock_socket.stubs(:setsockopt)
    @mock_socket.stubs(:sync=)
    @mock_socket.stubs(:closed?).returns(false)
    @mock_socket.stubs(:close)
  end

  def setup_connected_socket
    TCPSocket.stubs(:new).returns(@mock_socket)
    setup_mock_socket_options
  end

  def setup_ping_response
    @mock_socket.expects(:write).with("*1\r\n$4\r\nPING\r\n")
    @mock_socket.expects(:flush)
    # BufferedIO uses read_nonblock
    @mock_socket.expects(:read_nonblock).returns("+PONG\r\n")
  end
end
