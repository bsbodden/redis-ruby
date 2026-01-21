# frozen_string_literal: true

require_relative "unit_test_helper"
require "socket"

class PooledClientTest < Minitest::Test
  def setup
    @mock_socket = mock("socket")
    setup_mock_socket_options
  end

  def test_pooled_client_initialization
    TCPSocket.stubs(:new).returns(@mock_socket)

    client = RedisRuby::PooledClient.new(host: "localhost", port: 6379)

    assert_kind_of RedisRuby::PooledClient, client
    client.close
  end

  def test_pooled_client_with_url
    TCPSocket.stubs(:new).returns(@mock_socket)
    # SELECT response for db=1
    @mock_socket.stubs(:write)
    @mock_socket.stubs(:flush)
    @mock_socket.stubs(:getbyte).returns(43) # '+'
    @mock_socket.stubs(:gets).returns("OK\r\n")

    client = RedisRuby::PooledClient.new(url: "redis://localhost:6380/1")

    assert_equal "localhost", client.host
    assert_equal 6380, client.port
    assert_equal 1, client.db
    client.close
  end

  def test_pooled_client_pool_size
    TCPSocket.stubs(:new).returns(@mock_socket)

    client = RedisRuby::PooledClient.new(host: "localhost", pool: { size: 10 })

    assert_equal 10, client.pool_size
    client.close
  end

  def test_pooled_client_includes_command_modules
    TCPSocket.stubs(:new).returns(@mock_socket)

    client = RedisRuby::PooledClient.new(host: "localhost", port: 6379)

    assert_respond_to client, :get
    assert_respond_to client, :set
    assert_respond_to client, :hget
    assert_respond_to client, :lpush
    assert_respond_to client, :sadd
    assert_respond_to client, :zadd
    client.close
  end

  def test_pooled_client_call
    TCPSocket.stubs(:new).returns(@mock_socket)
    setup_ping_response

    client = RedisRuby::PooledClient.new(host: "localhost", port: 6379)

    result = client.call("PING")

    assert_equal "PONG", result
    client.close
  end

  def test_pooled_client_with_connection
    TCPSocket.stubs(:new).returns(@mock_socket)
    @mock_socket.stubs(:write)
    @mock_socket.stubs(:flush)
    @mock_socket.stubs(:getbyte).returns(43)
    @mock_socket.stubs(:gets).returns("PONG\r\n")

    client = RedisRuby::PooledClient.new(host: "localhost", port: 6379)

    # Execute multiple commands with same connection
    result = client.with_connection do |conn|
      conn.call("PING")
    end

    assert_equal "PONG", result
    client.close
  end

  def test_pooled_client_available_connections
    TCPSocket.stubs(:new).returns(@mock_socket)

    client = RedisRuby::PooledClient.new(host: "localhost", port: 6379, pool: { size: 5 })

    assert_equal 5, client.pool_available
    client.close
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
    @mock_socket.expects(:flush)
    @mock_socket.expects(:getbyte).returns(43) # '+'
    @mock_socket.expects(:gets).with("\r\n").returns("PONG\r\n")
  end
end
