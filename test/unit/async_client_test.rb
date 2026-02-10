# frozen_string_literal: true

require_relative "unit_test_helper"
require "socket"

class AsyncClientBranchTest < Minitest::Test
  def setup
    @mock_socket = mock("socket")
    setup_mock_socket_options
  end

  # ============================================================
  # Initialization
  # ============================================================

  def test_initialization_defaults
    setup_connected_socket

    client = RedisRuby::AsyncClient.new(host: "localhost", port: 6379)

    assert_equal "localhost", client.host
    assert_equal 6379, client.port
    assert_equal 0, client.db
    assert_in_delta(5.0, client.timeout)
    client.close
  end

  def test_initialization_with_url
    setup_connected_socket
    # SELECT 2 response
    @mock_socket.stubs(:write)
    @mock_socket.stubs(:flush)
    @mock_socket.stubs(:read_nonblock).returns("+OK\r\n")

    client = RedisRuby::AsyncClient.new(url: "redis://localhost:6380/2")

    assert_equal "localhost", client.host
    assert_equal 6380, client.port
    assert_equal 2, client.db
    client.close
  end

  def test_initialization_with_password
    setup_connected_socket
    # AUTH response
    @mock_socket.stubs(:write)
    @mock_socket.stubs(:flush)
    @mock_socket.stubs(:read_nonblock).returns("+OK\r\n")

    client = RedisRuby::AsyncClient.new(host: "localhost", port: 6379, password: "secret")

    assert_kind_of RedisRuby::AsyncClient, client
    client.close
  end

  def test_initialization_with_url_containing_password
    setup_connected_socket
    @mock_socket.stubs(:write)
    @mock_socket.stubs(:flush)
    @mock_socket.stubs(:read_nonblock).returns("+OK\r\n")

    client = RedisRuby::AsyncClient.new(url: "redis://:mypass@localhost:6379/0")

    assert_equal "localhost", client.host
    assert_equal 6379, client.port
    client.close
  end

  def test_initialization_db_zero_does_not_select
    setup_connected_socket
    # With db=0, no SELECT should be called
    client = RedisRuby::AsyncClient.new(host: "localhost", port: 6379, db: 0)

    assert_equal 0, client.db
    client.close
  end

  # ============================================================
  # call, call_1arg, call_2args, call_3args
  # ============================================================

  def test_call_success
    setup_connected_socket
    @mock_socket.expects(:write)
    @mock_socket.expects(:read_nonblock).returns("+PONG\r\n")

    client = RedisRuby::AsyncClient.new(host: "localhost", port: 6379)
    result = client.call("PING")

    assert_equal "PONG", result
    client.close
  end

  def test_call_raises_on_command_error
    setup_connected_socket
    @mock_socket.expects(:write)
    @mock_socket.expects(:read_nonblock).returns("-ERR bad command\r\n")

    client = RedisRuby::AsyncClient.new(host: "localhost", port: 6379)
    assert_raises(RedisRuby::CommandError) { client.call("BAD") }
    client.close
  end

  def test_call_1arg_success
    setup_connected_socket
    @mock_socket.expects(:write)
    @mock_socket.expects(:read_nonblock).returns("$5\r\nhello\r\n")

    client = RedisRuby::AsyncClient.new(host: "localhost", port: 6379)
    result = client.call_1arg("GET", "key")

    assert_equal "hello", result
    client.close
  end

  def test_call_1arg_raises_on_error
    setup_connected_socket
    @mock_socket.expects(:write)
    @mock_socket.expects(:read_nonblock).returns("-ERR problem\r\n")

    client = RedisRuby::AsyncClient.new(host: "localhost", port: 6379)
    assert_raises(RedisRuby::CommandError) { client.call_1arg("GET", "key") }
    client.close
  end

  def test_call_2args_success
    setup_connected_socket
    @mock_socket.expects(:write)
    @mock_socket.expects(:read_nonblock).returns("+OK\r\n")

    client = RedisRuby::AsyncClient.new(host: "localhost", port: 6379)
    result = client.call_2args("SET", "key", "val")

    assert_equal "OK", result
    client.close
  end

  def test_call_2args_raises_on_error
    setup_connected_socket
    @mock_socket.expects(:write)
    @mock_socket.expects(:read_nonblock).returns("-ERR problem\r\n")

    client = RedisRuby::AsyncClient.new(host: "localhost", port: 6379)
    assert_raises(RedisRuby::CommandError) { client.call_2args("SET", "key", "val") }
    client.close
  end

  def test_call_3args_success
    setup_connected_socket
    @mock_socket.expects(:write)
    @mock_socket.expects(:read_nonblock).returns(":1\r\n")

    client = RedisRuby::AsyncClient.new(host: "localhost", port: 6379)
    result = client.call_3args("HSET", "hash", "field", "value")

    assert_equal 1, result
    client.close
  end

  def test_call_3args_raises_on_error
    setup_connected_socket
    @mock_socket.expects(:write)
    @mock_socket.expects(:read_nonblock).returns("-ERR problem\r\n")

    client = RedisRuby::AsyncClient.new(host: "localhost", port: 6379)
    assert_raises(RedisRuby::CommandError) { client.call_3args("CMD", "a", "b", "c") }
    client.close
  end

  # ============================================================
  # ping
  # ============================================================

  def test_ping
    setup_connected_socket
    @mock_socket.expects(:write).with("*1\r\n$4\r\nPING\r\n")
    @mock_socket.expects(:read_nonblock).returns("+PONG\r\n")

    client = RedisRuby::AsyncClient.new(host: "localhost", port: 6379)

    assert_equal "PONG", client.ping
    client.close
  end

  # ============================================================
  # connected?
  # ============================================================

  def test_connected_true
    setup_connected_socket
    @mock_socket.stubs(:closed?).returns(false)

    client = RedisRuby::AsyncClient.new(host: "localhost", port: 6379)

    assert_predicate client, :connected?
    client.close
  end

  def test_connected_false_after_close
    setup_connected_socket
    client = RedisRuby::AsyncClient.new(host: "localhost", port: 6379)
    @mock_socket.expects(:close)
    client.close

    refute_predicate client, :connected?
  end

  def test_connected_false_when_no_connection
    # Create client, close it, set connection to nil
    setup_connected_socket
    client = RedisRuby::AsyncClient.new(host: "localhost", port: 6379)
    @mock_socket.expects(:close)
    client.close

    refute_predicate client, :connected?
  end

  # ============================================================
  # close / disconnect / quit aliases
  # ============================================================

  def test_disconnect_alias
    setup_connected_socket
    client = RedisRuby::AsyncClient.new(host: "localhost", port: 6379)
    @mock_socket.expects(:close)
    client.disconnect

    refute_predicate client, :connected?
  end

  def test_quit_alias
    setup_connected_socket
    client = RedisRuby::AsyncClient.new(host: "localhost", port: 6379)
    @mock_socket.expects(:close)
    client.quit

    refute_predicate client, :connected?
  end

  # ============================================================
  # watch - with and without block
  # ============================================================

  def test_watch_without_block
    setup_connected_socket
    @mock_socket.stubs(:write)
    @mock_socket.stubs(:flush)
    @mock_socket.stubs(:read_nonblock).returns("+OK\r\n")

    client = RedisRuby::AsyncClient.new(host: "localhost", port: 6379)
    result = client.watch("key1")

    assert_equal "OK", result
    client.close
  end

  def test_watch_with_block
    setup_connected_socket
    @mock_socket.stubs(:write)
    @mock_socket.stubs(:flush)
    @mock_socket.stubs(:read_nonblock).returns("+OK\r\n")

    client = RedisRuby::AsyncClient.new(host: "localhost", port: 6379)
    block_executed = false
    client.watch("key1") { block_executed = true }

    assert block_executed
    client.close
  end

  # ============================================================
  # unwatch
  # ============================================================

  def test_unwatch
    setup_connected_socket
    @mock_socket.stubs(:write)
    @mock_socket.stubs(:flush)
    @mock_socket.stubs(:read_nonblock).returns("+OK\r\n")

    client = RedisRuby::AsyncClient.new(host: "localhost", port: 6379)
    result = client.unwatch

    assert_equal "OK", result
    client.close
  end

  # ============================================================
  # Command modules included
  # ============================================================

  def test_includes_all_command_modules
    setup_connected_socket
    client = RedisRuby::AsyncClient.new(host: "localhost", port: 6379)

    assert_respond_to client, :get
    assert_respond_to client, :set
    assert_respond_to client, :hget
    assert_respond_to client, :lpush
    assert_respond_to client, :sadd
    assert_respond_to client, :zadd
    assert_respond_to client, :pfadd
    assert_respond_to client, :publish
    assert_respond_to client, :json_set
    client.close
  end

  # ============================================================
  # ensure_connected reconnects
  # ============================================================

  def test_ensure_connected_reconnects_when_disconnected
    setup_connected_socket

    client = RedisRuby::AsyncClient.new(host: "localhost", port: 6379)
    @mock_socket.expects(:close)
    client.close

    # Reconnect on next call
    new_socket = mock("new_socket")
    new_socket.stubs(:setsockopt)
    new_socket.stubs(:sync=)
    new_socket.stubs(:closed?).returns(false)
    new_socket.stubs(:close)
    new_socket.expects(:write)
    new_socket.expects(:read_nonblock).returns("+PONG\r\n")
    TCPSocket.stubs(:new).returns(new_socket)

    result = client.ping

    assert_equal "PONG", result
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
  end
end
