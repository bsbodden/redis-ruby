# frozen_string_literal: true

require_relative "unit_test_helper"

# Tests for redis-rb issues #909, #1157
# After fork, child process must not reuse parent's connection.
# Reconnection must replay the full prelude (AUTH, SELECT).
class ForkSafetyTest < Minitest::Test
  def test_client_detects_fork_and_reconnects
    client = RR::Client.new(password: "secret", db: 2)

    # Simulate first connection
    first_conn = mock("first_connection")
    first_conn.stubs(:connected?).returns(true)
    first_conn.stubs(:call).with("AUTH", "secret").returns("OK")
    first_conn.stubs(:call).with("SELECT", "2").returns("OK")

    RR::Connection::TCP.stubs(:new).returns(first_conn)
    client.send(:ensure_connected)

    # Simulate fork by changing the pid
    original_pid = Process.pid
    client.instance_variable_set(:@pid, original_pid - 1) # Different PID = forked

    # New connection should be created with AUTH+SELECT prelude
    second_conn = mock("second_connection")
    second_conn.stubs(:connected?).returns(true)

    seq = sequence("prelude")
    second_conn.expects(:call).with("AUTH", "secret").returns("OK").in_sequence(seq)
    second_conn.expects(:call).with("SELECT", "2").returns("OK").in_sequence(seq)

    RR::Connection::TCP.stubs(:new).returns(second_conn)

    client.send(:ensure_connected)

    # Connection should be the new one, not the old one
    assert_equal second_conn, client.send(:connection)
  end

  def test_client_does_not_close_parent_connection_on_fork
    client = RR::Client.new

    first_conn = mock("first_connection")
    first_conn.stubs(:connected?).returns(true)
    # Parent's connection must NOT be closed
    first_conn.expects(:close).never

    RR::Connection::TCP.stubs(:new).returns(first_conn)
    client.send(:ensure_connected)

    # Simulate fork
    client.instance_variable_set(:@pid, Process.pid - 1)

    second_conn = mock("second_connection")
    second_conn.stubs(:connected?).returns(true)
    RR::Connection::TCP.stubs(:new).returns(second_conn)

    client.send(:ensure_connected)
  end

  def test_client_replays_auth_with_username_after_fork
    client = RR::Client.new(username: "admin", password: "secret")

    first_conn = mock("first_connection")
    first_conn.stubs(:connected?).returns(true)
    first_conn.stubs(:call).with("AUTH", "admin", "secret").returns("OK")

    RR::Connection::TCP.stubs(:new).returns(first_conn)
    client.send(:ensure_connected)

    # Simulate fork
    client.instance_variable_set(:@pid, Process.pid - 1)

    second_conn = mock("second_connection")
    second_conn.stubs(:connected?).returns(true)
    second_conn.expects(:call).with("AUTH", "admin", "secret").returns("OK")

    RR::Connection::TCP.stubs(:new).returns(second_conn)
    client.send(:ensure_connected)
  end

  def test_client_no_fork_detection_false_positive
    client = RR::Client.new(password: "secret")

    conn = mock("connection")
    conn.stubs(:connected?).returns(true)
    conn.stubs(:call).with("AUTH", "secret").returns("OK")

    RR::Connection::TCP.expects(:new).once.returns(conn)

    # First ensure_connected creates the connection
    client.send(:ensure_connected)
    # Second call should reuse (same PID, connected)
    client.send(:ensure_connected)
  end

  def test_no_prelude_when_no_password_and_default_db
    client = RR::Client.new

    conn = mock("connection")
    conn.stubs(:connected?).returns(true)
    conn.expects(:call).never # No AUTH or SELECT needed

    RR::Connection::TCP.expects(:new).returns(conn)

    client.send(:ensure_connected)
  end

  def test_tcp_connection_fork_detection_before_socket_check
    # Verify the TCP connection checks for fork before checking socket state
    conn = RR::Connection::TCP.allocate
    conn.instance_variable_set(:@host, "localhost")
    conn.instance_variable_set(:@port, 6379)
    conn.instance_variable_set(:@timeout, 5.0)
    conn.instance_variable_set(:@pending_reads, 0)
    conn.instance_variable_set(:@ever_connected, true)
    conn.instance_variable_set(:@event_dispatcher, nil)
    conn.instance_variable_set(:@callbacks, Hash.new { |h, k| h[k] = [] })

    # Simulate a socket that appears connected (shared from parent)
    socket = mock("parent_socket")
    socket.stubs(:closed?).returns(false)
    conn.instance_variable_set(:@socket, socket)

    # Set PID to a different value (simulating fork)
    conn.instance_variable_set(:@pid, Process.pid - 1)

    # After fork detection, socket should be nil'd (not closed)
    socket.expects(:close).never

    # Mock the reconnect to create a new socket
    new_socket = mock("new_socket")
    new_socket.stubs(:closed?).returns(false)
    new_socket.stubs(:setsockopt)
    new_socket.stubs(:sync=)

    Socket.stubs(:tcp).returns(new_socket)

    encoder = RR::Protocol::RESP3Encoder.new
    buffered_io = mock("buffered_io")
    decoder = mock("decoder")

    RR::Protocol::BufferedIO.stubs(:new).returns(buffered_io)
    RR::Protocol::RESP3Decoder.stubs(:new).returns(decoder)

    conn.ensure_connected

    # Socket should have been replaced
    refute_equal socket, conn.instance_variable_get(:@socket)
  end
end
