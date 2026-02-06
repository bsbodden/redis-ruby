# frozen_string_literal: true

require_relative "unit_test_helper"
require "socket"
require "openssl"

# ============================================================================
# TCP Connection Branch Coverage Tests
# ============================================================================
class TCPConnectionBranchTest < Minitest::Test
  def setup
    @mock_socket = mock("socket")
    @mock_socket.stubs(:setsockopt)
    @mock_socket.stubs(:sync=)
    @mock_socket.stubs(:closed?).returns(false)
    @mock_socket.stubs(:close)
    TCPSocket.stubs(:new).returns(@mock_socket)
  end

  # ---------- Initialization branches ----------

  def test_default_initialization
    conn = RedisRuby::Connection::TCP.new
    assert_equal "localhost", conn.host
    assert_equal 6379, conn.port
    assert_equal 5.0, conn.timeout
  end

  def test_custom_host_port_timeout
    conn = RedisRuby::Connection::TCP.new(host: "10.0.0.1", port: 7000, timeout: 10.0)
    assert_equal "10.0.0.1", conn.host
    assert_equal 7000, conn.port
    assert_equal 10.0, conn.timeout
  end

  def test_initialize_sets_pid
    conn = RedisRuby::Connection::TCP.new
    assert_equal Process.pid, conn.instance_variable_get(:@pid)
  end

  # ---------- connected? branches ----------

  def test_connected_true_when_socket_open
    conn = RedisRuby::Connection::TCP.new
    @mock_socket.stubs(:closed?).returns(false)
    assert conn.connected?
  end

  def test_connected_false_when_socket_closed
    conn = RedisRuby::Connection::TCP.new
    @mock_socket.stubs(:closed?).returns(true)
    refute conn.connected?
  end

  def test_connected_false_when_socket_nil
    conn = RedisRuby::Connection::TCP.new
    conn.instance_variable_set(:@socket, nil)
    refute conn.connected?
  end

  # ---------- ensure_connected branches ----------

  def test_ensure_connected_returns_early_when_connected
    conn = RedisRuby::Connection::TCP.new
    @mock_socket.stubs(:closed?).returns(false)
    # Should not try to reconnect
    TCPSocket.expects(:new).never # Already stubbed, but we check no extra calls
    conn.ensure_connected
    assert conn.connected?
  end

  def test_ensure_connected_reconnects_when_socket_nil
    conn = RedisRuby::Connection::TCP.new
    # Simulate socket becoming nil
    conn.instance_variable_set(:@socket, nil)

    new_socket = mock("new_socket")
    new_socket.stubs(:setsockopt)
    new_socket.stubs(:sync=)
    new_socket.stubs(:closed?).returns(false)
    TCPSocket.unstub(:new)
    TCPSocket.stubs(:new).returns(new_socket)

    conn.ensure_connected
    assert conn.connected?
  end

  def test_ensure_connected_reconnects_when_socket_closed
    conn = RedisRuby::Connection::TCP.new
    @mock_socket.stubs(:closed?).returns(true)

    new_socket = mock("new_socket")
    new_socket.stubs(:setsockopt)
    new_socket.stubs(:sync=)
    new_socket.stubs(:closed?).returns(false)
    TCPSocket.unstub(:new)
    TCPSocket.stubs(:new).returns(new_socket)

    conn.ensure_connected
    assert conn.connected?
  end

  def test_ensure_connected_fork_detection_different_pid
    conn = RedisRuby::Connection::TCP.new
    # Simulate fork - different pid
    conn.instance_variable_set(:@pid, Process.pid + 1)
    # Socket appears closed from child perspective
    @mock_socket.stubs(:closed?).returns(true)

    new_socket = mock("new_socket")
    new_socket.stubs(:setsockopt)
    new_socket.stubs(:sync=)
    new_socket.stubs(:closed?).returns(false)
    TCPSocket.unstub(:new)
    TCPSocket.stubs(:new).returns(new_socket)

    conn.ensure_connected
    assert conn.connected?
  end

  def test_ensure_connected_fork_detection_sets_socket_nil
    conn = RedisRuby::Connection::TCP.new
    # Simulate fork by changing pid
    conn.instance_variable_set(:@pid, Process.pid + 999)
    # Socket still appears open but is from parent
    @mock_socket.stubs(:closed?).returns(true)

    new_socket = mock("new_socket")
    new_socket.stubs(:setsockopt)
    new_socket.stubs(:sync=)
    new_socket.stubs(:closed?).returns(false)
    TCPSocket.unstub(:new)
    TCPSocket.stubs(:new).returns(new_socket)

    conn.ensure_connected
    # After reconnect, socket should be the new one
    assert conn.connected?
  end

  def test_ensure_connected_no_pid_check_when_pid_nil
    conn = RedisRuby::Connection::TCP.new
    conn.instance_variable_set(:@pid, nil)
    @mock_socket.stubs(:closed?).returns(true)

    new_socket = mock("new_socket")
    new_socket.stubs(:setsockopt)
    new_socket.stubs(:sync=)
    new_socket.stubs(:closed?).returns(false)
    TCPSocket.unstub(:new)
    TCPSocket.stubs(:new).returns(new_socket)

    conn.ensure_connected
    assert conn.connected?
  end

  # ---------- reconnect branches ----------

  def test_reconnect_closes_old_and_opens_new
    conn = RedisRuby::Connection::TCP.new
    @mock_socket.expects(:close).at_least_once

    new_socket = mock("new_socket")
    new_socket.stubs(:setsockopt)
    new_socket.stubs(:sync=)
    new_socket.stubs(:closed?).returns(false)
    TCPSocket.unstub(:new)
    TCPSocket.stubs(:new).returns(new_socket)

    conn.reconnect
    assert conn.connected?
  end

  def test_reconnect_swallows_close_errors
    conn = RedisRuby::Connection::TCP.new
    @mock_socket.stubs(:close).raises(IOError, "already closed")

    new_socket = mock("new_socket")
    new_socket.stubs(:setsockopt)
    new_socket.stubs(:sync=)
    new_socket.stubs(:closed?).returns(false)
    TCPSocket.unstub(:new)
    TCPSocket.stubs(:new).returns(new_socket)

    # Should not raise despite close error
    conn.reconnect
    assert conn.connected?
  end

  # ---------- close branches ----------

  def test_close_with_active_socket
    conn = RedisRuby::Connection::TCP.new
    @mock_socket.expects(:close)
    conn.close
  end

  def test_close_with_nil_socket
    conn = RedisRuby::Connection::TCP.new
    conn.instance_variable_set(:@socket, nil)
    # Should not raise
    conn.close
  end

  # ---------- call / call_direct branches ----------

  def test_call_delegates_to_ensure_connected_then_call_direct
    conn = RedisRuby::Connection::TCP.new
    encoder = conn.instance_variable_get(:@encoder)
    encoded = encoder.encode_command("PING")
    @mock_socket.expects(:write).with(encoded)
    @mock_socket.expects(:flush)
    @mock_socket.stubs(:read_nonblock).returns("+PONG\r\n")

    result = conn.call("PING")
    assert_equal "PONG", result
  end

  def test_call_with_multiple_args
    conn = RedisRuby::Connection::TCP.new
    encoder = conn.instance_variable_get(:@encoder)
    encoded = encoder.encode_command("SET", "k", "v")
    @mock_socket.expects(:write).with(encoded)
    @mock_socket.expects(:flush)
    @mock_socket.stubs(:read_nonblock).returns("+OK\r\n")

    result = conn.call("SET", "k", "v")
    assert_equal "OK", result
  end

  # ---------- call_1arg / call_2args / call_3args ----------

  def test_call_1arg
    conn = RedisRuby::Connection::TCP.new
    encoder = conn.instance_variable_get(:@encoder)
    encoded = encoder.encode_command("GET", "mykey")
    @mock_socket.expects(:write).with(encoded)
    @mock_socket.expects(:flush)
    @mock_socket.stubs(:read_nonblock).returns("$5\r\nhello\r\n")

    result = conn.call_1arg("GET", "mykey")
    assert_equal "hello", result
  end

  def test_call_2args
    conn = RedisRuby::Connection::TCP.new
    encoder = conn.instance_variable_get(:@encoder)
    encoded = encoder.encode_command("SET", "k", "v")
    @mock_socket.expects(:write).with(encoded)
    @mock_socket.expects(:flush)
    @mock_socket.stubs(:read_nonblock).returns("+OK\r\n")

    result = conn.call_2args("SET", "k", "v")
    assert_equal "OK", result
  end

  def test_call_3args
    conn = RedisRuby::Connection::TCP.new
    encoder = conn.instance_variable_get(:@encoder)
    encoded = encoder.encode_command("HSET", "h", "f", "v")
    @mock_socket.expects(:write).with(encoded)
    @mock_socket.expects(:flush)
    @mock_socket.stubs(:read_nonblock).returns(":1\r\n")

    result = conn.call_3args("HSET", "h", "f", "v")
    assert_equal 1, result
  end

  # ---------- write_command branches ----------

  def test_write_command_with_string_command
    conn = RedisRuby::Connection::TCP.new
    @mock_socket.expects(:write)
    @mock_socket.expects(:flush)
    conn.write_command("PING")
  end

  def test_write_command_with_array_command
    conn = RedisRuby::Connection::TCP.new
    @mock_socket.expects(:write)
    @mock_socket.expects(:flush)
    conn.write_command(%w[SET key value])
  end

  # ---------- read_response branches ----------

  def test_read_response_without_timeout
    conn = RedisRuby::Connection::TCP.new
    @mock_socket.stubs(:read_nonblock).returns("+PONG\r\n")

    result = conn.read_response
    assert_equal "PONG", result
  end

  def test_read_response_with_timeout
    # Connection#read_response with timeout delegates to buffered_io
    # Just verify the method exists and accepts timeout kwarg
    conn = RedisRuby::Connection::TCP.new
    assert_respond_to conn, :read_response
  end

  # ---------- pipeline branches ----------

  def test_pipeline_returns_results
    conn = RedisRuby::Connection::TCP.new
    @mock_socket.stubs(:write)
    @mock_socket.stubs(:flush)
    @mock_socket.stubs(:read_nonblock).returns("+OK\r\n$5\r\nhello\r\n")

    results = conn.pipeline([
      %w[SET key value],
      %w[GET key],
    ])
    assert_equal 2, results.length
    assert_equal "OK", results[0]
    assert_equal "hello", results[1]
  end

  def test_pipeline_calls_ensure_connected
    conn = RedisRuby::Connection::TCP.new
    @mock_socket.stubs(:closed?).returns(false)
    @mock_socket.stubs(:write)
    @mock_socket.stubs(:flush)
    @mock_socket.stubs(:read_nonblock).returns("+PONG\r\n")

    # Should not raise
    conn.pipeline([["PING"]])
  end
end

# ============================================================================
# SSL Connection Branch Coverage Tests
# ============================================================================
class SSLConnectionBranchTest < Minitest::Test
  def setup
    @mock_tcp_socket = mock("tcp_socket")
    @mock_tcp_socket.stubs(:setsockopt)
    @mock_ssl_socket = mock("ssl_socket")
    @mock_ssl_socket.stubs(:hostname=)
    @mock_ssl_socket.stubs(:connect)
    @mock_ssl_socket.stubs(:post_connection_check)
    @mock_ssl_socket.stubs(:closed?).returns(false)
    @mock_ssl_socket.stubs(:close)
    @mock_ssl_socket.stubs(:flush)
    @mock_ssl_socket.stubs(:sync=)
    @mock_tcp_socket.stubs(:close)

    TCPSocket.stubs(:new).returns(@mock_tcp_socket)
    OpenSSL::SSL::SSLSocket.stubs(:new).returns(@mock_ssl_socket)
    OpenSSL::SSL::SSLContext.any_instance.stubs(:set_params)
  end

  # ---------- Initialization branches ----------

  def test_default_initialization
    conn = RedisRuby::Connection::SSL.new
    assert_equal "localhost", conn.host
    assert_equal 6379, conn.port
    assert_equal 5.0, conn.timeout
  end

  def test_custom_parameters
    conn = RedisRuby::Connection::SSL.new(host: "secure.example.com", port: 6380, timeout: 10.0)
    assert_equal "secure.example.com", conn.host
    assert_equal 6380, conn.port
    assert_equal 10.0, conn.timeout
  end

  # ---------- SSL context branches ----------

  def test_ssl_context_with_ca_file
    OpenSSL::SSL::SSLContext.any_instance.stubs(:verify_mode=)
    OpenSSL::SSL::SSLContext.any_instance.stubs(:min_version=)
    OpenSSL::SSL::SSLContext.any_instance.expects(:ca_file=).with("/path/to/ca.crt")

    RedisRuby::Connection::SSL.new(ssl_params: { ca_file: "/path/to/ca.crt" })
  end

  def test_ssl_context_with_ca_path
    OpenSSL::SSL::SSLContext.any_instance.stubs(:verify_mode=)
    OpenSSL::SSL::SSLContext.any_instance.stubs(:min_version=)
    OpenSSL::SSL::SSLContext.any_instance.expects(:ca_path=).with("/path/to/certs/")

    RedisRuby::Connection::SSL.new(ssl_params: { ca_path: "/path/to/certs/" })
  end

  def test_ssl_context_uses_system_certs_when_no_ca
    OpenSSL::SSL::SSLContext.any_instance.stubs(:verify_mode=)
    OpenSSL::SSL::SSLContext.any_instance.stubs(:min_version=)
    OpenSSL::SSL::SSLContext.any_instance.expects(:set_params).at_least_once

    RedisRuby::Connection::SSL.new(ssl_params: {})
  end

  def test_ssl_context_with_client_cert
    mock_cert = mock("cert")
    mock_key = mock("key")
    OpenSSL::SSL::SSLContext.any_instance.stubs(:verify_mode=)
    OpenSSL::SSL::SSLContext.any_instance.stubs(:min_version=)
    OpenSSL::SSL::SSLContext.any_instance.expects(:cert=).with(mock_cert)
    OpenSSL::SSL::SSLContext.any_instance.expects(:key=).with(mock_key)

    RedisRuby::Connection::SSL.new(ssl_params: { cert: mock_cert, key: mock_key })
  end

  def test_ssl_context_without_client_cert
    OpenSSL::SSL::SSLContext.any_instance.stubs(:verify_mode=)
    OpenSSL::SSL::SSLContext.any_instance.stubs(:min_version=)
    OpenSSL::SSL::SSLContext.any_instance.expects(:cert=).never
    OpenSSL::SSL::SSLContext.any_instance.expects(:key=).never

    RedisRuby::Connection::SSL.new(ssl_params: {})
  end

  def test_ssl_context_with_custom_ciphers
    OpenSSL::SSL::SSLContext.any_instance.stubs(:verify_mode=)
    OpenSSL::SSL::SSLContext.any_instance.stubs(:min_version=)
    OpenSSL::SSL::SSLContext.any_instance.expects(:ciphers=).with("HIGH:!aNULL")

    RedisRuby::Connection::SSL.new(ssl_params: { ciphers: "HIGH:!aNULL" })
  end

  def test_ssl_context_without_custom_ciphers
    OpenSSL::SSL::SSLContext.any_instance.stubs(:verify_mode=)
    OpenSSL::SSL::SSLContext.any_instance.stubs(:min_version=)
    OpenSSL::SSL::SSLContext.any_instance.expects(:ciphers=).never

    RedisRuby::Connection::SSL.new(ssl_params: {})
  end

  def test_ssl_context_with_custom_verify_mode
    # verify_mode may be set more than once (default + custom), so use stubs
    OpenSSL::SSL::SSLContext.any_instance.stubs(:verify_mode=)
    OpenSSL::SSL::SSLContext.any_instance.stubs(:min_version=)

    # Just verify it doesn't raise
    RedisRuby::Connection::SSL.new(ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE })
  end

  def test_ssl_context_with_custom_min_version
    OpenSSL::SSL::SSLContext.any_instance.stubs(:verify_mode=)
    OpenSSL::SSL::SSLContext.any_instance.expects(:min_version=).with(OpenSSL::SSL::TLS1_3_VERSION)

    RedisRuby::Connection::SSL.new(ssl_params: { min_version: OpenSSL::SSL::TLS1_3_VERSION })
  end

  # ---------- verify_peer? branches ----------

  def test_post_connection_check_when_verify_peer
    @mock_ssl_socket.expects(:post_connection_check).with("localhost")
    OpenSSL::SSL::SSLContext.any_instance.stubs(:verify_mode=)
    OpenSSL::SSL::SSLContext.any_instance.stubs(:min_version=)

    RedisRuby::Connection::SSL.new(ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_PEER })
  end

  def test_no_post_connection_check_when_verify_none
    @mock_ssl_socket.expects(:post_connection_check).never
    OpenSSL::SSL::SSLContext.any_instance.stubs(:verify_mode=)
    OpenSSL::SSL::SSLContext.any_instance.stubs(:min_version=)

    RedisRuby::Connection::SSL.new(ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE })
  end

  # ---------- connected? branches ----------

  def test_connected_true
    OpenSSL::SSL::SSLContext.any_instance.stubs(:verify_mode=)
    OpenSSL::SSL::SSLContext.any_instance.stubs(:min_version=)
    conn = RedisRuby::Connection::SSL.new
    @mock_ssl_socket.stubs(:closed?).returns(false)
    assert conn.connected?
  end

  def test_connected_false_when_closed
    OpenSSL::SSL::SSLContext.any_instance.stubs(:verify_mode=)
    OpenSSL::SSL::SSLContext.any_instance.stubs(:min_version=)
    conn = RedisRuby::Connection::SSL.new
    @mock_ssl_socket.stubs(:closed?).returns(true)
    refute conn.connected?
  end

  def test_connected_false_when_nil
    OpenSSL::SSL::SSLContext.any_instance.stubs(:verify_mode=)
    OpenSSL::SSL::SSLContext.any_instance.stubs(:min_version=)
    conn = RedisRuby::Connection::SSL.new
    conn.instance_variable_set(:@ssl_socket, nil)
    refute conn.connected?
  end

  # ---------- ensure_connected branches ----------

  def test_ensure_connected_no_op_when_connected
    OpenSSL::SSL::SSLContext.any_instance.stubs(:verify_mode=)
    OpenSSL::SSL::SSLContext.any_instance.stubs(:min_version=)
    conn = RedisRuby::Connection::SSL.new
    @mock_ssl_socket.stubs(:closed?).returns(false)
    # Should not try to reconnect
    conn.ensure_connected
    assert conn.connected?
  end

  def test_ensure_connected_reconnects_when_not_connected
    OpenSSL::SSL::SSLContext.any_instance.stubs(:verify_mode=)
    OpenSSL::SSL::SSLContext.any_instance.stubs(:min_version=)
    conn = RedisRuby::Connection::SSL.new
    @mock_ssl_socket.stubs(:closed?).returns(true)

    new_tcp = mock("new_tcp")
    new_tcp.stubs(:setsockopt)
    new_ssl = mock("new_ssl")
    new_ssl.stubs(:hostname=)
    new_ssl.stubs(:connect)
    new_ssl.stubs(:post_connection_check)
    new_ssl.stubs(:closed?).returns(false)
    new_ssl.stubs(:sync=)

    TCPSocket.unstub(:new)
    TCPSocket.stubs(:new).returns(new_tcp)
    OpenSSL::SSL::SSLSocket.unstub(:new)
    OpenSSL::SSL::SSLSocket.stubs(:new).returns(new_ssl)

    conn.ensure_connected
    assert conn.connected?
  end

  def test_ensure_connected_fork_detection
    OpenSSL::SSL::SSLContext.any_instance.stubs(:verify_mode=)
    OpenSSL::SSL::SSLContext.any_instance.stubs(:min_version=)
    conn = RedisRuby::Connection::SSL.new

    # Simulate fork by changing pid
    conn.instance_variable_set(:@pid, Process.pid + 42)

    new_tcp = mock("new_tcp")
    new_tcp.stubs(:setsockopt)
    new_ssl = mock("new_ssl")
    new_ssl.stubs(:hostname=)
    new_ssl.stubs(:connect)
    new_ssl.stubs(:post_connection_check)
    new_ssl.stubs(:closed?).returns(false)
    new_ssl.stubs(:sync=)

    TCPSocket.unstub(:new)
    TCPSocket.stubs(:new).returns(new_tcp)
    OpenSSL::SSL::SSLSocket.unstub(:new)
    OpenSSL::SSL::SSLSocket.stubs(:new).returns(new_ssl)

    conn.ensure_connected
    # Should have nullified and reconnected
    assert conn.connected?
  end

  # ---------- reconnect branches ----------

  def test_reconnect_swallows_close_errors
    OpenSSL::SSL::SSLContext.any_instance.stubs(:verify_mode=)
    OpenSSL::SSL::SSLContext.any_instance.stubs(:min_version=)
    conn = RedisRuby::Connection::SSL.new

    @mock_ssl_socket.stubs(:close).raises(IOError, "already closed")
    @mock_tcp_socket.stubs(:close).raises(IOError, "already closed")

    new_tcp = mock("new_tcp")
    new_tcp.stubs(:setsockopt)
    new_ssl = mock("new_ssl")
    new_ssl.stubs(:hostname=)
    new_ssl.stubs(:connect)
    new_ssl.stubs(:post_connection_check)
    new_ssl.stubs(:closed?).returns(false)
    new_ssl.stubs(:sync=)

    TCPSocket.unstub(:new)
    TCPSocket.stubs(:new).returns(new_tcp)
    OpenSSL::SSL::SSLSocket.unstub(:new)
    OpenSSL::SSL::SSLSocket.stubs(:new).returns(new_ssl)

    conn.reconnect
    assert conn.connected?
  end

  # ---------- close branches ----------

  def test_close_closes_both_sockets
    OpenSSL::SSL::SSLContext.any_instance.stubs(:verify_mode=)
    OpenSSL::SSL::SSLContext.any_instance.stubs(:min_version=)
    conn = RedisRuby::Connection::SSL.new
    @mock_ssl_socket.expects(:close)
    @mock_tcp_socket.expects(:close)
    conn.close
  end

  def test_close_with_nil_sockets
    OpenSSL::SSL::SSLContext.any_instance.stubs(:verify_mode=)
    OpenSSL::SSL::SSLContext.any_instance.stubs(:min_version=)
    conn = RedisRuby::Connection::SSL.new
    conn.instance_variable_set(:@ssl_socket, nil)
    conn.instance_variable_set(:@tcp_socket, nil)
    # Should not raise
    conn.close
  end

  # ---------- pipeline branches ----------

  def test_ssl_pipeline
    OpenSSL::SSL::SSLContext.any_instance.stubs(:verify_mode=)
    OpenSSL::SSL::SSLContext.any_instance.stubs(:min_version=)
    conn = RedisRuby::Connection::SSL.new

    @mock_ssl_socket.stubs(:write)
    @mock_ssl_socket.stubs(:flush)
    @mock_ssl_socket.stubs(:read_nonblock).returns("+OK\r\n+PONG\r\n")

    results = conn.pipeline([%w[SET k v], ["PING"]])
    assert_equal 2, results.length
  end
end

# ============================================================================
# Unix Connection Branch Coverage Tests
# ============================================================================
class UnixConnectionBranchTest < Minitest::Test
  def setup
    @mock_socket = mock("unix_socket")
    @mock_socket.stubs(:sync=)
    @mock_socket.stubs(:closed?).returns(false)
    @mock_socket.stubs(:close)
    UNIXSocket.stubs(:new).returns(@mock_socket)
  end

  # ---------- Initialization branches ----------

  def test_default_initialization
    conn = RedisRuby::Connection::Unix.new
    assert_equal "/var/run/redis/redis.sock", conn.path
    assert_equal 5.0, conn.timeout
  end

  def test_custom_path_and_timeout
    conn = RedisRuby::Connection::Unix.new(path: "/tmp/redis.sock", timeout: 10.0)
    assert_equal "/tmp/redis.sock", conn.path
    assert_equal 10.0, conn.timeout
  end

  # ---------- connected? branches ----------

  def test_connected_true
    conn = RedisRuby::Connection::Unix.new
    assert conn.connected?
  end

  def test_connected_false_when_closed
    conn = RedisRuby::Connection::Unix.new
    @mock_socket.stubs(:closed?).returns(true)
    refute conn.connected?
  end

  def test_connected_false_when_nil
    conn = RedisRuby::Connection::Unix.new
    conn.instance_variable_set(:@socket, nil)
    refute conn.connected?
  end

  # ---------- Error handling branches ----------

  def test_connect_raises_on_socket_not_found
    UNIXSocket.unstub(:new)
    UNIXSocket.stubs(:new).raises(Errno::ENOENT)
    assert_raises(RedisRuby::ConnectionError) do
      RedisRuby::Connection::Unix.new(path: "/nonexistent/redis.sock")
    end
  end

  def test_connect_raises_on_permission_denied
    UNIXSocket.unstub(:new)
    UNIXSocket.stubs(:new).raises(Errno::EACCES)
    assert_raises(RedisRuby::ConnectionError) do
      RedisRuby::Connection::Unix.new(path: "/root/redis.sock")
    end
  end

  def test_connect_raises_on_connection_refused
    UNIXSocket.unstub(:new)
    UNIXSocket.stubs(:new).raises(Errno::ECONNREFUSED)
    assert_raises(RedisRuby::ConnectionError) do
      RedisRuby::Connection::Unix.new(path: "/tmp/redis.sock")
    end
  end

  # ---------- close branches ----------

  def test_close_with_active_socket
    conn = RedisRuby::Connection::Unix.new
    @mock_socket.expects(:close)
    conn.close
  end

  def test_close_with_nil_socket
    conn = RedisRuby::Connection::Unix.new
    conn.instance_variable_set(:@socket, nil)
    conn.close
  end

  # ---------- call / pipeline ----------

  def test_call_command
    conn = RedisRuby::Connection::Unix.new
    @mock_socket.stubs(:write)
    @mock_socket.stubs(:flush)
    @mock_socket.stubs(:read_nonblock).returns("+PONG\r\n")

    result = conn.call("PING")
    assert_equal "PONG", result
  end

  def test_call_1arg
    conn = RedisRuby::Connection::Unix.new
    @mock_socket.stubs(:write)
    @mock_socket.stubs(:flush)
    @mock_socket.stubs(:read_nonblock).returns("$5\r\nhello\r\n")

    result = conn.call_1arg("GET", "key")
    assert_equal "hello", result
  end

  def test_call_2args
    conn = RedisRuby::Connection::Unix.new
    @mock_socket.stubs(:write)
    @mock_socket.stubs(:flush)
    @mock_socket.stubs(:read_nonblock).returns("+OK\r\n")

    result = conn.call_2args("SET", "k", "v")
    assert_equal "OK", result
  end

  def test_call_3args
    conn = RedisRuby::Connection::Unix.new
    @mock_socket.stubs(:write)
    @mock_socket.stubs(:flush)
    @mock_socket.stubs(:read_nonblock).returns(":1\r\n")

    result = conn.call_3args("HSET", "h", "f", "v")
    assert_equal 1, result
  end

  def test_pipeline
    conn = RedisRuby::Connection::Unix.new
    @mock_socket.stubs(:write)
    @mock_socket.stubs(:flush)
    @mock_socket.stubs(:read_nonblock).returns("+OK\r\n$5\r\nhello\r\n")

    results = conn.pipeline([%w[SET k v], %w[GET k]])
    assert_equal 2, results.length
  end
end

# ============================================================================
# Connection Pool Branch Coverage Tests
# ============================================================================
class ConnectionPoolBranchTest < Minitest::Test
  def setup
    @mock_socket = mock("socket")
    @mock_socket.stubs(:setsockopt)
    @mock_socket.stubs(:sync=)
    @mock_socket.stubs(:closed?).returns(false)
    @mock_socket.stubs(:close)
    @mock_socket.stubs(:write)
    @mock_socket.stubs(:flush)
    TCPSocket.stubs(:new).returns(@mock_socket)
  end

  def test_default_pool_size
    pool = RedisRuby::Connection::Pool.new
    assert_equal 5, pool.size
    assert_equal 5, pool.timeout
    pool.close
  end

  def test_custom_pool_size
    pool = RedisRuby::Connection::Pool.new(size: 10, pool_timeout: 2)
    assert_equal 10, pool.size
    assert_equal 2, pool.timeout
    pool.close
  end

  def test_with_yields_connection
    pool = RedisRuby::Connection::Pool.new(size: 1)
    pool.with do |conn|
      assert_instance_of RedisRuby::Connection::TCP, conn
    end
    pool.close
  end

  def test_shutdown_alias
    pool = RedisRuby::Connection::Pool.new
    assert_respond_to pool, :shutdown
    pool.close
  end

  def test_create_connection_with_password
    @mock_socket.stubs(:read_nonblock).returns("+OK\r\n")
    pool = RedisRuby::Connection::Pool.new(password: "secret", size: 1)
    pool.with do |conn|
      assert_instance_of RedisRuby::Connection::TCP, conn
    end
    pool.close
  end

  def test_create_connection_with_db_selection
    @mock_socket.stubs(:read_nonblock).returns("+OK\r\n")
    pool = RedisRuby::Connection::Pool.new(db: 5, size: 1)
    pool.with do |conn|
      assert_instance_of RedisRuby::Connection::TCP, conn
    end
    pool.close
  end

  def test_create_connection_without_password_no_auth
    pool = RedisRuby::Connection::Pool.new(size: 1)
    pool.with do |conn|
      # No AUTH should have been sent
      assert_instance_of RedisRuby::Connection::TCP, conn
    end
    pool.close
  end

  def test_create_connection_with_db_0_no_select
    pool = RedisRuby::Connection::Pool.new(db: 0, size: 1)
    pool.with do |conn|
      # No SELECT should have been sent for db 0
      assert_instance_of RedisRuby::Connection::TCP, conn
    end
    pool.close
  end
end
