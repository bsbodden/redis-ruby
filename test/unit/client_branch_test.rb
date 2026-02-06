# frozen_string_literal: true

require_relative "unit_test_helper"

class ClientBranchTest < Minitest::Test
  # A mock connection that simulates a real Redis connection
  class MockConnection
    attr_reader :last_command, :connected, :closed, :calls

    def initialize
      @connected = true
      @closed = false
      @last_command = nil
      @calls = []
    end

    def call_direct(command, *args)
      @last_command = [command, *args]
      @calls << @last_command
      mock_return(command)
    end

    def call_1arg(command, arg)
      @last_command = [command, arg]
      @calls << @last_command
      mock_return(command)
    end

    def call_2args(command, arg1, arg2)
      @last_command = [command, arg1, arg2]
      @calls << @last_command
      mock_return(command)
    end

    def call_3args(command, arg1, arg2, arg3)
      @last_command = [command, arg1, arg2, arg3]
      @calls << @last_command
      mock_return(command)
    end

    def call(command, *args)
      @last_command = [command, *args]
      @calls << @last_command
      mock_return(command)
    end

    def connected?
      @connected
    end

    def close
      @connected = false
      @closed = true
    end

    private

    def mock_return(command)
      case command
      when "PING" then "PONG"
      when "GET" then "value"
      when "SET", "AUTH", "SELECT", "WATCH", "UNWATCH", "DISCARD" then "OK"
      when "HGET" then "field_value"
      when "HSET" then 1
      else "OK"
      end
    end
  end

  # Mock connection that returns a CommandError
  class ErrorConnection < MockConnection
    def call_direct(command, *args)
      @last_command = [command, *args]
      RedisRuby::CommandError.new("ERR test error")
    end

    def call_1arg(command, arg)
      @last_command = [command, arg]
      RedisRuby::CommandError.new("ERR test error")
    end

    def call_2args(command, arg1, arg2)
      @last_command = [command, arg1, arg2]
      RedisRuby::CommandError.new("ERR test error")
    end

    def call_3args(command, arg1, arg2, arg3)
      @last_command = [command, arg1, arg2, arg3]
      RedisRuby::CommandError.new("ERR test error")
    end
  end

  # ============================================================
  # Initialization tests
  # ============================================================

  def test_default_initialization
    client = RedisRuby::Client.new
    assert_equal "localhost", client.host
    assert_equal 6379, client.port
    assert_equal 0, client.db
    assert_equal 5.0, client.timeout
    assert_nil client.path
    refute client.ssl?
    refute client.unix?
    refute client.connected?
  end

  def test_custom_host_and_port
    client = RedisRuby::Client.new(host: "10.0.0.1", port: 7000)
    assert_equal "10.0.0.1", client.host
    assert_equal 7000, client.port
  end

  def test_custom_db
    client = RedisRuby::Client.new(db: 5)
    assert_equal 5, client.db
  end

  def test_custom_timeout
    client = RedisRuby::Client.new(timeout: 10.0)
    assert_equal 10.0, client.timeout
  end

  def test_unix_socket_path
    client = RedisRuby::Client.new(path: "/tmp/redis.sock")
    assert_equal "/tmp/redis.sock", client.path
    assert client.unix?
  end

  def test_ssl_flag
    client = RedisRuby::Client.new(ssl: true)
    assert client.ssl?
  end

  def test_ssl_false_by_default
    client = RedisRuby::Client.new
    refute client.ssl?
  end

  # ============================================================
  # URL parsing - redis:// scheme
  # ============================================================

  def test_parse_redis_url
    client = RedisRuby::Client.new(url: "redis://myhost:7000/3")
    assert_equal "myhost", client.host
    assert_equal 7000, client.port
    assert_equal 3, client.db
    refute client.ssl?
  end

  def test_parse_redis_url_defaults
    client = RedisRuby::Client.new(url: "redis://myhost")
    assert_equal "myhost", client.host
    assert_equal 6379, client.port
  end

  def test_parse_redis_url_with_password_only
    client = RedisRuby::Client.new(url: "redis://:secret@localhost:6379")
    assert_equal "localhost", client.host
    # Password is private, just verify no error
  end

  def test_parse_redis_url_with_user_and_password
    client = RedisRuby::Client.new(url: "redis://admin:secret@localhost:6379")
    assert_equal "localhost", client.host
  end

  # ============================================================
  # URL parsing - rediss:// scheme
  # ============================================================

  def test_parse_rediss_url
    client = RedisRuby::Client.new(url: "rediss://secure.host:6380/1")
    assert_equal "secure.host", client.host
    assert_equal 6380, client.port
    assert_equal 1, client.db
    assert client.ssl?
  end

  # ============================================================
  # URL parsing - unix:// scheme
  # ============================================================

  def test_parse_unix_url
    client = RedisRuby::Client.new(url: "unix:///var/run/redis.sock")
    assert_equal "/var/run/redis.sock", client.path
    assert_nil client.host
    assert_nil client.port
    assert client.unix?
  end

  def test_parse_unix_url_with_db_query
    client = RedisRuby::Client.new(url: "unix:///var/run/redis.sock?db=4")
    assert_equal "/var/run/redis.sock", client.path
    assert_equal 4, client.db
  end

  def test_parse_unix_url_without_query_defaults_db
    client = RedisRuby::Client.new(url: "unix:///var/run/redis.sock")
    assert_equal 0, client.db
  end

  # ============================================================
  # URL parsing - invalid scheme
  # ============================================================

  def test_parse_invalid_url_scheme
    error = assert_raises(ArgumentError) do
      RedisRuby::Client.new(url: "http://localhost:6379")
    end
    assert_match(/Unsupported URL scheme/, error.message)
  end

  # ============================================================
  # URL overrides explicit options
  # ============================================================

  def test_url_overrides_host_and_port
    client = RedisRuby::Client.new(url: "redis://urlhost:9000", host: "explicit", port: 1234)
    assert_equal "urlhost", client.host
    assert_equal 9000, client.port
  end

  # ============================================================
  # Connection state
  # ============================================================

  def test_connected_false_when_no_connection
    client = RedisRuby::Client.new
    refute client.connected?
  end

  def test_connected_returns_connection_state
    client = RedisRuby::Client.new
    mock_conn = MockConnection.new
    client.instance_variable_set(:@connection, mock_conn)
    assert client.connected?
  end

  def test_connected_false_when_connection_nil
    client = RedisRuby::Client.new
    client.instance_variable_set(:@connection, nil)
    refute client.connected?
  end

  # ============================================================
  # close / disconnect / quit
  # ============================================================

  def test_close_with_connection
    client = RedisRuby::Client.new
    mock_conn = MockConnection.new
    client.instance_variable_set(:@connection, mock_conn)

    client.close
    assert mock_conn.closed
    assert_nil client.instance_variable_get(:@connection)
  end

  def test_close_without_connection
    client = RedisRuby::Client.new
    # Should not raise
    client.close
    assert_nil client.instance_variable_get(:@connection)
  end

  def test_disconnect_alias
    client = RedisRuby::Client.new
    assert_respond_to client, :disconnect
    # Should behave same as close
    client.disconnect
  end

  def test_quit_alias
    client = RedisRuby::Client.new
    assert_respond_to client, :quit
    client.quit
  end

  # ============================================================
  # call - normal and error branches
  # ============================================================

  def test_call_returns_result
    client = RedisRuby::Client.new
    mock_conn = MockConnection.new
    client.instance_variable_set(:@connection, mock_conn)

    result = client.call("PING")
    assert_equal "PONG", result
  end

  def test_call_raises_command_error
    client = RedisRuby::Client.new
    error_conn = ErrorConnection.new
    client.instance_variable_set(:@connection, error_conn)

    assert_raises(RedisRuby::CommandError) do
      client.call("GET", "key")
    end
  end

  # ============================================================
  # call_1arg - normal and error branches
  # ============================================================

  def test_call_1arg_returns_result
    client = RedisRuby::Client.new
    mock_conn = MockConnection.new
    client.instance_variable_set(:@connection, mock_conn)

    result = client.get("mykey")
    assert_equal "value", result
  end

  def test_call_1arg_raises_command_error
    client = RedisRuby::Client.new
    error_conn = ErrorConnection.new
    client.instance_variable_set(:@connection, error_conn)

    assert_raises(RedisRuby::CommandError) do
      client.get("mykey")
    end
  end

  # ============================================================
  # call_2args - normal and error branches
  # ============================================================

  def test_call_2args_returns_result
    client = RedisRuby::Client.new
    mock_conn = MockConnection.new
    client.instance_variable_set(:@connection, mock_conn)

    result = client.set("mykey", "myval")
    assert_equal "OK", result
  end

  def test_call_2args_raises_command_error
    client = RedisRuby::Client.new
    error_conn = ErrorConnection.new
    client.instance_variable_set(:@connection, error_conn)

    assert_raises(RedisRuby::CommandError) do
      client.set("mykey", "myval")
    end
  end

  # ============================================================
  # call_3args - normal and error branches
  # ============================================================

  def test_call_3args_returns_result
    client = RedisRuby::Client.new
    mock_conn = MockConnection.new
    client.instance_variable_set(:@connection, mock_conn)

    result = client.hset("myhash", "field", "val")
    assert_equal 1, result
  end

  def test_call_3args_raises_command_error
    client = RedisRuby::Client.new
    error_conn = ErrorConnection.new
    client.instance_variable_set(:@connection, error_conn)

    assert_raises(RedisRuby::CommandError) do
      client.hset("myhash", "field", "val")
    end
  end

  # ============================================================
  # decode_responses - all result type branches
  # ============================================================

  def test_decode_responses_string_unfrozen
    client = RedisRuby::Client.new(decode_responses: true, encoding: "UTF-8")
    mock_conn = MockConnection.new
    client.instance_variable_set(:@connection, mock_conn)

    result = client.get("mykey")
    assert_equal "value", result
    assert_equal Encoding::UTF_8, result.encoding
  end

  def test_decode_responses_string_frozen
    client = RedisRuby::Client.new(decode_responses: true, encoding: "UTF-8")

    # Create a connection that returns frozen strings
    frozen_conn = MockConnection.new
    def frozen_conn.call_1arg(command, arg)
      "frozen_value".freeze
    end

    client.instance_variable_set(:@connection, frozen_conn)
    result = client.get("mykey")
    assert_equal "frozen_value", result
    assert_equal Encoding::UTF_8, result.encoding
  end

  def test_decode_responses_array
    client = RedisRuby::Client.new(decode_responses: true, encoding: "UTF-8")

    array_conn = MockConnection.new
    def array_conn.call_direct(command, *args)
      %w[val1 val2]
    end

    client.instance_variable_set(:@connection, array_conn)
    result = client.call("MGET", "k1", "k2")
    assert_instance_of Array, result
    assert_equal 2, result.length
    result.each { |v| assert_equal Encoding::UTF_8, v.encoding }
  end

  def test_decode_responses_hash
    client = RedisRuby::Client.new(decode_responses: true, encoding: "UTF-8")

    hash_conn = MockConnection.new
    def hash_conn.call_direct(command, *args)
      { "key" => "val" }
    end

    client.instance_variable_set(:@connection, hash_conn)
    result = client.call("HGETALL", "myhash")
    assert_instance_of Hash, result
    result.each do |k, v|
      assert_equal Encoding::UTF_8, k.encoding
      assert_equal Encoding::UTF_8, v.encoding
    end
  end

  def test_decode_responses_integer_passthrough
    client = RedisRuby::Client.new(decode_responses: true, encoding: "UTF-8")

    int_conn = MockConnection.new
    def int_conn.call_direct(command, *args)
      42
    end

    client.instance_variable_set(:@connection, int_conn)
    result = client.call("DBSIZE")
    assert_equal 42, result
    assert_instance_of Integer, result
  end

  def test_decode_responses_nil_passthrough
    client = RedisRuby::Client.new(decode_responses: true, encoding: "UTF-8")

    nil_conn = MockConnection.new
    def nil_conn.call_1arg(command, arg)
      nil
    end

    client.instance_variable_set(:@connection, nil_conn)
    result = client.get("nonexistent")
    assert_nil result
  end

  def test_decode_responses_disabled
    client = RedisRuby::Client.new(decode_responses: false)
    mock_conn = MockConnection.new
    client.instance_variable_set(:@connection, mock_conn)

    result = client.get("mykey")
    assert_equal "value", result
  end

  def test_decode_responses_custom_encoding
    client = RedisRuby::Client.new(decode_responses: true, encoding: "ISO-8859-1")
    mock_conn = MockConnection.new
    client.instance_variable_set(:@connection, mock_conn)

    result = client.get("mykey")
    assert_equal Encoding::ISO_8859_1, result.encoding
  end

  # ============================================================
  # ping
  # ============================================================

  def test_ping
    client = RedisRuby::Client.new
    mock_conn = MockConnection.new
    client.instance_variable_set(:@connection, mock_conn)

    result = client.ping
    assert_equal "PONG", result
  end

  # ============================================================
  # pipelined
  # ============================================================

  def test_pipelined_executes_commands
    client = RedisRuby::Client.new
    mock_conn = MockConnection.new

    # We need to mock Pipeline properly
    pipeline = mock("pipeline")
    pipeline.expects(:execute).returns(["OK", "value"])
    RedisRuby::Pipeline.expects(:new).with(mock_conn).returns(pipeline)

    client.instance_variable_set(:@connection, mock_conn)

    results = client.pipelined do |pipe|
      # block is yielded the pipeline mock
    end

    assert_equal ["OK", "value"], results
  end

  def test_pipelined_raises_command_error_in_results
    client = RedisRuby::Client.new
    mock_conn = MockConnection.new

    cmd_error = RedisRuby::CommandError.new("ERR pipeline error")
    pipeline = mock("pipeline")
    pipeline.expects(:execute).returns(["OK", cmd_error])
    RedisRuby::Pipeline.expects(:new).with(mock_conn).returns(pipeline)

    client.instance_variable_set(:@connection, mock_conn)

    assert_raises(RedisRuby::CommandError) do
      client.pipelined { |_pipe| }
    end
  end

  # ============================================================
  # multi (transaction)
  # ============================================================

  def test_multi_executes_transaction
    client = RedisRuby::Client.new
    mock_conn = MockConnection.new

    transaction = mock("transaction")
    transaction.expects(:execute).returns(["OK", 1])
    RedisRuby::Transaction.expects(:new).with(mock_conn).returns(transaction)

    client.instance_variable_set(:@connection, mock_conn)

    results = client.multi { |_tx| }
    assert_equal ["OK", 1], results
  end

  def test_multi_returns_nil_when_aborted
    client = RedisRuby::Client.new
    mock_conn = MockConnection.new

    transaction = mock("transaction")
    transaction.expects(:execute).returns(nil)
    RedisRuby::Transaction.expects(:new).with(mock_conn).returns(transaction)

    client.instance_variable_set(:@connection, mock_conn)

    result = client.multi { |_tx| }
    assert_nil result
  end

  def test_multi_raises_command_error_from_transaction_itself
    client = RedisRuby::Client.new
    mock_conn = MockConnection.new

    cmd_error = RedisRuby::CommandError.new("MISCONF config error")
    transaction = mock("transaction")
    transaction.expects(:execute).returns(cmd_error)
    RedisRuby::Transaction.expects(:new).with(mock_conn).returns(transaction)

    client.instance_variable_set(:@connection, mock_conn)

    assert_raises(RedisRuby::CommandError) do
      client.multi { |_tx| }
    end
  end

  def test_multi_raises_command_error_in_results
    client = RedisRuby::Client.new
    mock_conn = MockConnection.new

    cmd_error = RedisRuby::CommandError.new("ERR in result")
    transaction = mock("transaction")
    transaction.expects(:execute).returns(["OK", cmd_error])
    RedisRuby::Transaction.expects(:new).with(mock_conn).returns(transaction)

    client.instance_variable_set(:@connection, mock_conn)

    assert_raises(RedisRuby::CommandError) do
      client.multi { |_tx| }
    end
  end

  # ============================================================
  # watch - with and without block
  # ============================================================

  def test_watch_without_block
    client = RedisRuby::Client.new
    mock_conn = MockConnection.new
    client.instance_variable_set(:@connection, mock_conn)

    result = client.watch("key1", "key2")
    assert_equal "OK", result
  end

  def test_watch_with_block
    client = RedisRuby::Client.new
    mock_conn = MockConnection.new
    client.instance_variable_set(:@connection, mock_conn)

    block_called = false
    client.watch("key1") do
      block_called = true
    end

    assert block_called
    # UNWATCH should have been called in ensure block
    assert_equal ["UNWATCH"], mock_conn.last_command
  end

  def test_watch_with_block_unwatches_on_exception
    client = RedisRuby::Client.new
    mock_conn = MockConnection.new
    client.instance_variable_set(:@connection, mock_conn)

    assert_raises(RuntimeError) do
      client.watch("key1") do
        raise "test error"
      end
    end

    # UNWATCH should still be called even on exception
    assert_equal ["UNWATCH"], mock_conn.last_command
  end

  # ============================================================
  # discard / unwatch
  # ============================================================

  def test_discard
    client = RedisRuby::Client.new
    mock_conn = MockConnection.new
    client.instance_variable_set(:@connection, mock_conn)

    result = client.discard
    assert_equal "OK", result
  end

  def test_unwatch
    client = RedisRuby::Client.new
    mock_conn = MockConnection.new
    client.instance_variable_set(:@connection, mock_conn)

    result = client.unwatch
    assert_equal "OK", result
  end

  # ============================================================
  # ensure_connected - creates connections for different topologies
  # ============================================================

  def test_ensure_connected_creates_tcp_connection
    client = RedisRuby::Client.new(host: "localhost", port: 6379)

    RedisRuby::Connection::TCP.expects(:new)
                              .with(host: "localhost", port: 6379, timeout: 5.0)
                              .returns(MockConnection.new)

    client.send(:ensure_connected)
    assert client.connected?
  end

  def test_ensure_connected_creates_ssl_connection
    client = RedisRuby::Client.new(host: "localhost", port: 6380, ssl: true, ssl_params: { verify_mode: 0 })

    RedisRuby::Connection::SSL.expects(:new)
                              .with(host: "localhost", port: 6380, timeout: 5.0,
                                    ssl_params: { verify_mode: 0 })
                              .returns(MockConnection.new)

    client.send(:ensure_connected)
    assert client.connected?
  end

  def test_ensure_connected_creates_unix_connection
    client = RedisRuby::Client.new(path: "/tmp/redis.sock")

    RedisRuby::Connection::Unix.expects(:new)
                               .with(path: "/tmp/redis.sock", timeout: 5.0)
                               .returns(MockConnection.new)

    client.send(:ensure_connected)
    assert client.connected?
  end

  def test_ensure_connected_skips_when_already_connected
    client = RedisRuby::Client.new
    mock_conn = MockConnection.new
    client.instance_variable_set(:@connection, mock_conn)

    # Should not create a new connection
    RedisRuby::Connection::TCP.expects(:new).never

    client.send(:ensure_connected)
  end

  # ============================================================
  # authenticate - with and without username
  # ============================================================

  def test_authenticate_with_password_only
    client = RedisRuby::Client.new(password: "secret")
    mock_conn = MockConnection.new

    RedisRuby::Connection::TCP.expects(:new).returns(mock_conn)

    client.send(:ensure_connected)

    # Should have called AUTH with just the password
    auth_calls = mock_conn.calls.select { |c| c[0] == "AUTH" }
    assert_equal 1, auth_calls.length
    assert_equal ["AUTH", "secret"], auth_calls[0]
  end

  def test_authenticate_with_username_and_password
    client = RedisRuby::Client.new(username: "admin", password: "secret")
    mock_conn = MockConnection.new

    RedisRuby::Connection::TCP.expects(:new).returns(mock_conn)

    client.send(:ensure_connected)

    auth_calls = mock_conn.calls.select { |c| c[0] == "AUTH" }
    assert_equal 1, auth_calls.length
    assert_equal ["AUTH", "admin", "secret"], auth_calls[0]
  end

  def test_no_authenticate_without_password
    client = RedisRuby::Client.new
    mock_conn = MockConnection.new

    RedisRuby::Connection::TCP.expects(:new).returns(mock_conn)

    client.send(:ensure_connected)

    auth_calls = mock_conn.calls.select { |c| c[0] == "AUTH" }
    assert_empty auth_calls
  end

  # ============================================================
  # select_db - only when db > 0
  # ============================================================

  def test_select_db_when_positive
    client = RedisRuby::Client.new(db: 3)
    mock_conn = MockConnection.new

    RedisRuby::Connection::TCP.expects(:new).returns(mock_conn)

    client.send(:ensure_connected)

    select_calls = mock_conn.calls.select { |c| c[0] == "SELECT" }
    assert_equal 1, select_calls.length
    assert_equal ["SELECT", "3"], select_calls[0]
  end

  def test_no_select_db_when_zero
    client = RedisRuby::Client.new(db: 0)
    mock_conn = MockConnection.new

    RedisRuby::Connection::TCP.expects(:new).returns(mock_conn)

    client.send(:ensure_connected)

    select_calls = mock_conn.calls.select { |c| c[0] == "SELECT" }
    assert_empty select_calls
  end

  # ============================================================
  # Retry policy
  # ============================================================

  def test_retry_policy_with_reconnect_attempts
    client = RedisRuby::Client.new(reconnect_attempts: 3)
    policy = client.instance_variable_get(:@retry_policy)
    assert_instance_of RedisRuby::Retry, policy
  end

  def test_retry_policy_with_zero_reconnect_attempts
    client = RedisRuby::Client.new(reconnect_attempts: 0)
    policy = client.instance_variable_get(:@retry_policy)
    assert_instance_of RedisRuby::Retry, policy
  end

  def test_custom_retry_policy_overrides_reconnect_attempts
    custom_policy = RedisRuby::Retry.new(retries: 5)
    client = RedisRuby::Client.new(retry_policy: custom_policy, reconnect_attempts: 10)
    policy = client.instance_variable_get(:@retry_policy)
    assert_same custom_policy, policy
  end

  def test_retry_policy_nil_builds_default
    client = RedisRuby::Client.new(retry_policy: nil, reconnect_attempts: 2)
    policy = client.instance_variable_get(:@retry_policy)
    assert_instance_of RedisRuby::Retry, policy
  end

  # ============================================================
  # URL parsing edge cases
  # ============================================================

  def test_parse_tcp_url_empty_username_becomes_nil
    # redis://:password@host - user is empty string
    client = RedisRuby::Client.new(url: "redis://:mysecret@localhost:6379")
    username = client.instance_variable_get(:@username)
    assert_nil username
  end

  def test_parse_tcp_url_no_password
    client = RedisRuby::Client.new(url: "redis://localhost:6379")
    password = client.instance_variable_get(:@password)
    assert_nil password
  end

  def test_parse_tcp_url_no_db_defaults_to_zero
    client = RedisRuby::Client.new(url: "redis://localhost:6379")
    assert_equal 0, client.db
  end

  def test_parse_unix_url_with_password
    client = RedisRuby::Client.new(url: "unix://mypass@/var/run/redis.sock")
    password = client.instance_variable_get(:@password)
    assert_equal "mypass", password
  end

  # ============================================================
  # ssl? / unix? helper methods
  # ============================================================

  def test_ssl_false_default
    client = RedisRuby::Client.new
    refute client.ssl?
  end

  def test_ssl_true_when_set
    client = RedisRuby::Client.new(ssl: true)
    assert client.ssl?
  end

  def test_unix_false_when_no_path
    client = RedisRuby::Client.new
    refute client.unix?
  end

  def test_unix_true_when_path_set
    client = RedisRuby::Client.new(path: "/tmp/redis.sock")
    assert client.unix?
  end

  # ============================================================
  # decode_responses with nested structures
  # ============================================================

  def test_decode_nested_array_in_array
    client = RedisRuby::Client.new(decode_responses: true, encoding: "UTF-8")

    nested_conn = MockConnection.new
    def nested_conn.call_direct(command, *args)
      [["inner1", "inner2"], "outer"]
    end

    client.instance_variable_set(:@connection, nested_conn)
    result = client.call("CUSTOM")
    assert_instance_of Array, result
    assert_instance_of Array, result[0]
    assert_equal Encoding::UTF_8, result[0][0].encoding
    assert_equal Encoding::UTF_8, result[1].encoding
  end

  def test_decode_nested_hash_with_array_values
    client = RedisRuby::Client.new(decode_responses: true, encoding: "UTF-8")

    nested_conn = MockConnection.new
    def nested_conn.call_direct(command, *args)
      { "key" => ["val1", "val2"] }
    end

    client.instance_variable_set(:@connection, nested_conn)
    result = client.call("CUSTOM")
    assert_instance_of Hash, result
    assert_instance_of Array, result["key"]
  end

  # ============================================================
  # decode_responses with boolean/float types (non-string, non-array, non-hash)
  # ============================================================

  def test_decode_responses_boolean_passthrough
    client = RedisRuby::Client.new(decode_responses: true, encoding: "UTF-8")

    bool_conn = MockConnection.new
    def bool_conn.call_direct(command, *args)
      true
    end

    client.instance_variable_set(:@connection, bool_conn)
    result = client.call("EXISTS")
    assert_equal true, result
  end

  def test_decode_responses_float_passthrough
    client = RedisRuby::Client.new(decode_responses: true, encoding: "UTF-8")

    float_conn = MockConnection.new
    def float_conn.call_direct(command, *args)
      3.14
    end

    client.instance_variable_set(:@connection, float_conn)
    result = client.call("INCRBYFLOAT")
    assert_in_delta 3.14, result
  end
end
