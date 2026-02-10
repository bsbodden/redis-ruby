# frozen_string_literal: true

require_relative "unit_test_helper"
require "socket"

class PooledClientBranchTest < Minitest::Test
  def setup
    @mock_socket = mock("socket")
    setup_mock_socket_options
  end

  # ============================================================
  # PooledClient - Initialization
  # ============================================================

  def test_pooled_client_initialization
    TCPSocket.stubs(:new).returns(@mock_socket)
    client = RedisRuby::PooledClient.new(host: "localhost", port: 6379)

    assert_kind_of RedisRuby::PooledClient, client
    assert_equal "localhost", client.host
    assert_equal 6379, client.port
    assert_equal 0, client.db
    assert_in_delta(5.0, client.timeout)
    client.close
  end

  def test_pooled_client_with_url
    TCPSocket.stubs(:new).returns(@mock_socket)
    @mock_socket.stubs(:write)
    @mock_socket.stubs(:flush)
    @mock_socket.stubs(:read_nonblock).returns("+OK\r\n")

    client = RedisRuby::PooledClient.new(url: "redis://localhost:6380/1")

    assert_equal "localhost", client.host
    assert_equal 6380, client.port
    assert_equal 1, client.db
    client.close
  end

  def test_pooled_client_with_url_and_password
    TCPSocket.stubs(:new).returns(@mock_socket)
    @mock_socket.stubs(:write)
    @mock_socket.stubs(:flush)
    @mock_socket.stubs(:read_nonblock).returns("+OK\r\n")

    client = RedisRuby::PooledClient.new(url: "redis://:secret@localhost:6379/0")

    assert_equal "localhost", client.host
    client.close
  end

  def test_pooled_client_custom_pool_size
    TCPSocket.stubs(:new).returns(@mock_socket)
    client = RedisRuby::PooledClient.new(host: "localhost", pool: { size: 10 })

    assert_equal 10, client.pool_size
    client.close
  end

  def test_pooled_client_custom_pool_timeout
    TCPSocket.stubs(:new).returns(@mock_socket)
    client = RedisRuby::PooledClient.new(host: "localhost", pool: { size: 5, timeout: 15.0 })

    assert_equal 5, client.pool_size
    client.close
  end

  def test_pooled_client_default_pool_size
    TCPSocket.stubs(:new).returns(@mock_socket)
    client = RedisRuby::PooledClient.new(host: "localhost")

    assert_equal 5, client.pool_size
    client.close
  end

  # ============================================================
  # PooledClient - call variants
  # ============================================================

  def test_pooled_client_call
    TCPSocket.stubs(:new).returns(@mock_socket)
    @mock_socket.expects(:write).with("*1\r\n$4\r\nPING\r\n")
    @mock_socket.expects(:read_nonblock).returns("+PONG\r\n")

    client = RedisRuby::PooledClient.new(host: "localhost", port: 6379)
    result = client.call("PING")

    assert_equal "PONG", result
    client.close
  end

  def test_pooled_client_call_raises_on_error
    TCPSocket.stubs(:new).returns(@mock_socket)
    @mock_socket.expects(:write)
    @mock_socket.expects(:read_nonblock).returns("-ERR bad\r\n")

    client = RedisRuby::PooledClient.new(host: "localhost", port: 6379)
    assert_raises(RedisRuby::CommandError) { client.call("BAD") }
    client.close
  end

  def test_pooled_client_call_1arg
    TCPSocket.stubs(:new).returns(@mock_socket)
    @mock_socket.expects(:write)
    @mock_socket.expects(:read_nonblock).returns("$5\r\nhello\r\n")

    client = RedisRuby::PooledClient.new(host: "localhost", port: 6379)
    result = client.call_1arg("GET", "key")

    assert_equal "hello", result
    client.close
  end

  def test_pooled_client_call_1arg_raises_on_error
    TCPSocket.stubs(:new).returns(@mock_socket)
    @mock_socket.expects(:write)
    @mock_socket.expects(:read_nonblock).returns("-ERR fail\r\n")

    client = RedisRuby::PooledClient.new(host: "localhost", port: 6379)
    assert_raises(RedisRuby::CommandError) { client.call_1arg("GET", "key") }
    client.close
  end

  def test_pooled_client_call_2args
    TCPSocket.stubs(:new).returns(@mock_socket)
    @mock_socket.expects(:write)
    @mock_socket.expects(:read_nonblock).returns("+OK\r\n")

    client = RedisRuby::PooledClient.new(host: "localhost", port: 6379)
    result = client.call_2args("SET", "key", "val")

    assert_equal "OK", result
    client.close
  end

  def test_pooled_client_call_2args_raises_on_error
    TCPSocket.stubs(:new).returns(@mock_socket)
    @mock_socket.expects(:write)
    @mock_socket.expects(:read_nonblock).returns("-ERR fail\r\n")

    client = RedisRuby::PooledClient.new(host: "localhost", port: 6379)
    assert_raises(RedisRuby::CommandError) { client.call_2args("SET", "k", "v") }
    client.close
  end

  def test_pooled_client_call_3args
    TCPSocket.stubs(:new).returns(@mock_socket)
    @mock_socket.expects(:write)
    @mock_socket.expects(:read_nonblock).returns(":1\r\n")

    client = RedisRuby::PooledClient.new(host: "localhost", port: 6379)
    result = client.call_3args("HSET", "h", "f", "v")

    assert_equal 1, result
    client.close
  end

  def test_pooled_client_call_3args_raises_on_error
    TCPSocket.stubs(:new).returns(@mock_socket)
    @mock_socket.expects(:write)
    @mock_socket.expects(:read_nonblock).returns("-ERR fail\r\n")

    client = RedisRuby::PooledClient.new(host: "localhost", port: 6379)
    assert_raises(RedisRuby::CommandError) { client.call_3args("CMD", "a", "b", "c") }
    client.close
  end

  # ============================================================
  # PooledClient - ping, with_connection, pool_available
  # ============================================================

  def test_pooled_client_ping
    TCPSocket.stubs(:new).returns(@mock_socket)
    @mock_socket.expects(:write)
    @mock_socket.expects(:read_nonblock).returns("+PONG\r\n")

    client = RedisRuby::PooledClient.new(host: "localhost", port: 6379)

    assert_equal "PONG", client.ping
    client.close
  end

  def test_pooled_client_with_connection
    TCPSocket.stubs(:new).returns(@mock_socket)
    @mock_socket.stubs(:write)
    @mock_socket.stubs(:flush)
    @mock_socket.stubs(:read_nonblock).returns("+PONG\r\n")

    client = RedisRuby::PooledClient.new(host: "localhost", port: 6379)
    result = client.with_connection { |conn| conn.call("PING") }

    assert_equal "PONG", result
    client.close
  end

  def test_pooled_client_pool_available
    TCPSocket.stubs(:new).returns(@mock_socket)
    client = RedisRuby::PooledClient.new(host: "localhost", port: 6379, pool: { size: 5 })

    assert_equal 5, client.pool_available
    client.close
  end

  # ============================================================
  # PooledClient - watch with and without block
  # ============================================================

  def test_pooled_client_watch_without_block
    TCPSocket.stubs(:new).returns(@mock_socket)
    @mock_socket.stubs(:write)
    @mock_socket.stubs(:flush)
    @mock_socket.stubs(:read_nonblock).returns("+OK\r\n")

    client = RedisRuby::PooledClient.new(host: "localhost", port: 6379)
    result = client.watch("key1")

    assert_equal "OK", result
    client.close
  end

  def test_pooled_client_watch_with_block
    TCPSocket.stubs(:new).returns(@mock_socket)
    @mock_socket.stubs(:write)
    @mock_socket.stubs(:flush)
    @mock_socket.stubs(:read_nonblock).returns("+OK\r\n")

    client = RedisRuby::PooledClient.new(host: "localhost", port: 6379)
    executed = false
    client.watch("key1") { executed = true }

    assert executed
    client.close
  end

  # ============================================================
  # PooledClient - unwatch
  # ============================================================

  def test_pooled_client_unwatch
    TCPSocket.stubs(:new).returns(@mock_socket)
    @mock_socket.stubs(:write)
    @mock_socket.stubs(:flush)
    @mock_socket.stubs(:read_nonblock).returns("+OK\r\n")

    client = RedisRuby::PooledClient.new(host: "localhost", port: 6379)
    result = client.unwatch

    assert_equal "OK", result
    client.close
  end

  # ============================================================
  # PooledClient - close / disconnect / quit aliases
  # ============================================================

  def test_pooled_client_disconnect_alias
    TCPSocket.stubs(:new).returns(@mock_socket)
    client = RedisRuby::PooledClient.new(host: "localhost", port: 6379)
    client.disconnect
    # Should not raise
  end

  def test_pooled_client_quit_alias
    TCPSocket.stubs(:new).returns(@mock_socket)
    client = RedisRuby::PooledClient.new(host: "localhost", port: 6379)
    client.quit
    # Should not raise
  end

  # ============================================================
  # PooledClient - includes command modules
  # ============================================================

  def test_pooled_client_includes_command_modules
    TCPSocket.stubs(:new).returns(@mock_socket)
    client = RedisRuby::PooledClient.new(host: "localhost", port: 6379)

    assert_respond_to client, :get
    assert_respond_to client, :set
    assert_respond_to client, :hget
    assert_respond_to client, :lpush
    assert_respond_to client, :sadd
    assert_respond_to client, :zadd
    assert_respond_to client, :pfadd
    assert_respond_to client, :publish
    client.close
  end

  # ============================================================
  # AsyncPooledClient - basic tests (mocking the async pool)
  # ============================================================

  def test_async_pooled_client_initialization
    mock_pool = mock("async_pool")
    RedisRuby::Connection::AsyncPool.stubs(:new).returns(mock_pool)

    client = RedisRuby::AsyncPooledClient.new(host: "localhost", port: 6379)

    assert_kind_of RedisRuby::AsyncPooledClient, client
    assert_equal "localhost", client.host
    assert_equal 6379, client.port
    assert_equal 0, client.db
    assert_in_delta(5.0, client.timeout)
  end

  def test_async_pooled_client_with_url
    mock_pool = mock("async_pool")
    RedisRuby::Connection::AsyncPool.stubs(:new).returns(mock_pool)

    client = RedisRuby::AsyncPooledClient.new(url: "redis://localhost:6380/2")

    assert_equal "localhost", client.host
    assert_equal 6380, client.port
    assert_equal 2, client.db
  end

  def test_async_pooled_client_with_password_url
    mock_pool = mock("async_pool")
    RedisRuby::Connection::AsyncPool.stubs(:new).returns(mock_pool)

    client = RedisRuby::AsyncPooledClient.new(url: "redis://:secret@localhost:6379/0")

    assert_equal "localhost", client.host
  end

  def test_async_pooled_client_custom_pool_limit
    mock_pool = mock("async_pool")
    RedisRuby::Connection::AsyncPool.stubs(:new).returns(mock_pool)

    client = RedisRuby::AsyncPooledClient.new(host: "localhost", pool: { limit: 20 })

    assert_kind_of RedisRuby::AsyncPooledClient, client
  end

  def test_async_pooled_client_call
    create_yielding_pool("PONG") { |conn| conn.expects(:call).with("PING").returns("PONG") }

    client = RedisRuby::AsyncPooledClient.new(host: "localhost", port: 6379)
    result = client.call("PING")

    assert_equal "PONG", result
  end

  def test_async_pooled_client_call_raises_on_error
    create_yielding_pool(nil) { |conn| conn.expects(:call).returns(RedisRuby::CommandError.new("ERR")) }

    client = RedisRuby::AsyncPooledClient.new(host: "localhost", port: 6379)
    assert_raises(RedisRuby::CommandError) { client.call("BAD") }
  end

  def test_async_pooled_client_call_1arg
    create_yielding_pool("value") { |conn| conn.expects(:call_1arg).with("GET", "key").returns("value") }

    client = RedisRuby::AsyncPooledClient.new(host: "localhost", port: 6379)

    assert_equal "value", client.call_1arg("GET", "key")
  end

  def test_async_pooled_client_call_1arg_raises_on_error
    create_yielding_pool(nil) { |conn| conn.expects(:call_1arg).returns(RedisRuby::CommandError.new("ERR")) }

    client = RedisRuby::AsyncPooledClient.new(host: "localhost", port: 6379)
    assert_raises(RedisRuby::CommandError) { client.call_1arg("GET", "key") }
  end

  def test_async_pooled_client_call_2args
    create_yielding_pool("OK") { |conn| conn.expects(:call_2args).with("SET", "k", "v").returns("OK") }

    client = RedisRuby::AsyncPooledClient.new(host: "localhost", port: 6379)

    assert_equal "OK", client.call_2args("SET", "k", "v")
  end

  def test_async_pooled_client_call_2args_raises_on_error
    create_yielding_pool(nil) { |conn| conn.expects(:call_2args).returns(RedisRuby::CommandError.new("ERR")) }

    client = RedisRuby::AsyncPooledClient.new(host: "localhost", port: 6379)
    assert_raises(RedisRuby::CommandError) { client.call_2args("SET", "k", "v") }
  end

  def test_async_pooled_client_call_3args
    create_yielding_pool(1) { |conn| conn.expects(:call_3args).with("HSET", "h", "f", "v").returns(1) }

    client = RedisRuby::AsyncPooledClient.new(host: "localhost", port: 6379)

    assert_equal 1, client.call_3args("HSET", "h", "f", "v")
  end

  def test_async_pooled_client_call_3args_raises_on_error
    create_yielding_pool(nil) { |conn| conn.expects(:call_3args).returns(RedisRuby::CommandError.new("ERR")) }

    client = RedisRuby::AsyncPooledClient.new(host: "localhost", port: 6379)
    assert_raises(RedisRuby::CommandError) { client.call_3args("CMD", "a", "b", "c") }
  end

  def test_async_pooled_client_ping
    create_yielding_pool("PONG") { |conn| conn.expects(:call).with("PING").returns("PONG") }

    client = RedisRuby::AsyncPooledClient.new(host: "localhost", port: 6379)

    assert_equal "PONG", client.ping
  end

  def test_async_pooled_client_with_connection
    mock_conn = mock("connection")
    mock_pool = Object.new
    mock_pool.define_singleton_method(:acquire) { |&block| block.call(mock_conn) }
    mock_pool.define_singleton_method(:limit) { 5 }
    mock_pool.define_singleton_method(:available?) { true }
    mock_pool.define_singleton_method(:close) {}
    RedisRuby::Connection::AsyncPool.stubs(:new).returns(mock_pool)

    client = RedisRuby::AsyncPooledClient.new(host: "localhost", port: 6379)
    result = client.with_connection { |c| c }

    assert_equal mock_conn, result
  end

  def test_async_pooled_client_pool_limit
    mock_pool = mock("async_pool")
    mock_pool.expects(:limit).returns(10)
    RedisRuby::Connection::AsyncPool.stubs(:new).returns(mock_pool)

    client = RedisRuby::AsyncPooledClient.new(host: "localhost", pool: { limit: 10 })

    assert_equal 10, client.pool_limit
  end

  def test_async_pooled_client_pool_available
    mock_pool = mock("async_pool")
    mock_pool.expects(:available?).returns(true)
    RedisRuby::Connection::AsyncPool.stubs(:new).returns(mock_pool)

    client = RedisRuby::AsyncPooledClient.new(host: "localhost")

    assert_predicate client, :pool_available?
  end

  def test_async_pooled_client_close
    mock_pool = mock("async_pool")
    mock_pool.expects(:close)
    RedisRuby::Connection::AsyncPool.stubs(:new).returns(mock_pool)

    client = RedisRuby::AsyncPooledClient.new(host: "localhost")
    client.close
  end

  def test_async_pooled_client_disconnect_alias
    mock_pool = mock("async_pool")
    mock_pool.expects(:close)
    RedisRuby::Connection::AsyncPool.stubs(:new).returns(mock_pool)

    client = RedisRuby::AsyncPooledClient.new(host: "localhost")
    client.disconnect
  end

  def test_async_pooled_client_quit_alias
    mock_pool = mock("async_pool")
    mock_pool.expects(:close)
    RedisRuby::Connection::AsyncPool.stubs(:new).returns(mock_pool)

    client = RedisRuby::AsyncPooledClient.new(host: "localhost")
    client.quit
  end

  def test_async_pooled_client_unwatch
    create_yielding_pool("OK") { |conn| conn.expects(:call).with("UNWATCH").returns("OK") }

    client = RedisRuby::AsyncPooledClient.new(host: "localhost")

    assert_equal "OK", client.unwatch
  end

  def test_async_pooled_client_watch_without_block
    mock_pool = mock("async_pool")
    mock_conn = mock("connection")
    mock_pool.expects(:acquire).yields(mock_conn)
    mock_conn.expects(:call).with("WATCH", "k1").returns("OK")
    RedisRuby::Connection::AsyncPool.stubs(:new).returns(mock_pool)

    client = RedisRuby::AsyncPooledClient.new(host: "localhost")
    result = client.watch("k1")

    assert_equal "OK", result
  end

  def test_async_pooled_client_watch_with_block
    mock_pool = mock("async_pool")
    mock_conn = mock("connection")
    mock_pool.expects(:acquire).yields(mock_conn)
    mock_conn.expects(:call).with("WATCH", "k1").returns("OK")
    mock_conn.expects(:call).with("UNWATCH").returns("OK")
    RedisRuby::Connection::AsyncPool.stubs(:new).returns(mock_pool)

    client = RedisRuby::AsyncPooledClient.new(host: "localhost")
    executed = false
    client.watch("k1") { executed = true }

    assert executed
  end

  def test_async_pooled_client_includes_command_modules
    mock_pool = mock("async_pool")
    RedisRuby::Connection::AsyncPool.stubs(:new).returns(mock_pool)

    client = RedisRuby::AsyncPooledClient.new(host: "localhost")

    assert_respond_to client, :get
    assert_respond_to client, :set
    assert_respond_to client, :pfadd
    assert_respond_to client, :publish
  end

  private

  def setup_mock_socket_options
    @mock_socket.stubs(:setsockopt)
    @mock_socket.stubs(:sync=)
    @mock_socket.stubs(:closed?).returns(false)
    @mock_socket.stubs(:close)
  end

  # Helper: creates a mock async pool whose acquire method yields a mock connection
  # and returns the block's return value (unlike mocha's .yields which returns nil).
  # The optional setup_block is called with the mock connection so callers can set expectations.
  def create_yielding_pool(_expected_return = nil)
    mock_conn = mock("connection")
    yield mock_conn if block_given?

    mock_pool = Object.new
    conn = mock_conn
    mock_pool.define_singleton_method(:acquire) { |&block| block.call(conn) }
    RedisRuby::Connection::AsyncPool.stubs(:new).returns(mock_pool)
    mock_pool
  end
end
