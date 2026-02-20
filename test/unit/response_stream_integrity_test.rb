# frozen_string_literal: true

require_relative "unit_test_helper"

# Tests for redis-rb issues #1294, #1162
# Response stream integrity: AUTH/SELECT prelude responses must not
# leak into subsequent command results.
class ResponseStreamIntegrityTest < Minitest::Test
  # Verify prelude commands are fully consumed before user commands
  def test_auth_response_does_not_leak_into_get
    client = RR::Client.new(password: "secret")

    # Mock connection that tracks call order and returns appropriate values
    connection = mock("connection")
    connection.stubs(:connected?).returns(true)
    connection.stubs(:call).with("AUTH", "secret").returns("OK")

    # After AUTH, a GET should return the GET result, not "OK" from AUTH
    connection.stubs(:call_1arg).with("GET", "key").returns("myvalue")

    RR::Connection::TCP.expects(:new).returns(connection)

    client.send(:ensure_connected)
    result = client.get("key")

    assert_equal "myvalue", result
  end

  def test_auth_and_select_responses_do_not_leak_into_mget
    client = RR::Client.new(password: "secret", db: 2)

    connection = mock("connection")
    connection.stubs(:connected?).returns(true)
    connection.stubs(:call).with("AUTH", "secret").returns("OK")
    connection.stubs(:call).with("SELECT", "2").returns("OK")
    connection.stubs(:call_direct).with("MGET", "k1", "k2").returns(%w[v1 v2])

    RR::Connection::TCP.expects(:new).returns(connection)

    client.send(:ensure_connected)
    result = client.mget("k1", "k2")

    # Should be the MGET result, not "OK" from AUTH or SELECT
    assert_instance_of Array, result
    assert_equal %w[v1 v2], result
  end

  def test_prelude_order_is_auth_then_select
    client = RR::Client.new(password: "secret", db: 3)

    call_order = []
    connection = mock("connection")
    connection.stubs(:connected?).returns(true)
    connection.stubs(:call).with("AUTH", "secret").returns("OK").tap do
      call_order << :auth
    end
    connection.stubs(:call).with("SELECT", "3").returns("OK").tap do
      call_order << :select
    end

    RR::Connection::TCP.expects(:new).returns(connection)

    seq = sequence("prelude")
    connection.expects(:call).with("AUTH", "secret").returns("OK").in_sequence(seq)
    connection.expects(:call).with("SELECT", "3").returns("OK").in_sequence(seq)

    client.send(:ensure_connected)
  end

  def test_auth_failure_prevents_user_commands
    client = RR::Client.new(password: "wrong")

    connection = mock("connection")
    connection.stubs(:connected?).returns(true)
    connection.stubs(:call).with("AUTH", "wrong").raises(
      RR::CommandError.new("WRONGPASS invalid username-password pair")
    )
    connection.stubs(:close)

    RR::Connection::TCP.expects(:new).returns(connection)

    assert_raises(RR::CommandError) do
      client.send(:ensure_connected)
    end
  end

  def test_select_failure_prevents_user_commands
    client = RR::Client.new(db: 99)

    connection = mock("connection")
    connection.stubs(:connected?).returns(true)
    connection.stubs(:call).with("SELECT", "99").raises(
      RR::CommandError.new("ERR DB index is out of range")
    )
    connection.stubs(:close)

    RR::Connection::TCP.expects(:new).returns(connection)

    assert_raises(RR::CommandError) do
      client.send(:ensure_connected)
    end
  end

  # Test that TCP connection tracks pending reads for interrupt safety
  def test_tcp_connection_has_pending_reads_attribute
    conn = RR::Connection::TCP.allocate
    conn.instance_variable_set(:@pending_reads, 0)

    assert_equal 0, conn.pending_reads
  end

  def test_tcp_connection_revalidate_returns_false_with_pending_reads
    conn = RR::Connection::TCP.allocate
    conn.instance_variable_set(:@pending_reads, 1)
    conn.instance_variable_set(:@socket, nil)

    refute conn.revalidate
  end

  def test_tcp_connection_revalidate_returns_true_when_clean
    socket = mock("socket")
    socket.stubs(:closed?).returns(false)

    conn = RR::Connection::TCP.allocate
    conn.instance_variable_set(:@pending_reads, 0)
    conn.instance_variable_set(:@socket, socket)

    assert conn.revalidate
  end

  def test_tcp_connection_revalidate_closes_corrupted_connection
    socket = mock("socket")
    socket.stubs(:closed?).returns(false)
    socket.expects(:close)

    conn = RR::Connection::TCP.allocate
    conn.instance_variable_set(:@pending_reads, 1)
    conn.instance_variable_set(:@socket, socket)

    refute conn.revalidate
  end

  # Verify pipeline results aren't contaminated by prelude
  def test_pipeline_results_not_contaminated_after_reconnection
    client = RR::Client.new(password: "secret", db: 1)

    connection = mock("connection")
    connection.stubs(:connected?).returns(true)
    connection.stubs(:call).with("AUTH", "secret").returns("OK")
    connection.stubs(:call).with("SELECT", "1").returns("OK")
    # Pipeline sends commands and reads exactly N responses
    connection.stubs(:pipeline).returns(%w[OK value1])

    RR::Connection::TCP.expects(:new).returns(connection)

    client.send(:ensure_connected)

    results = client.pipelined do |p|
      p.set("key", "value1")
      p.get("key")
    end

    # Pipeline results should be command results, not prelude responses
    assert_equal %w[OK value1], results
  end

  # Verify username+password AUTH prelude is consumed
  def test_acl_auth_response_consumed_before_commands
    client = RR::Client.new(username: "admin", password: "secret")

    connection = mock("connection")
    connection.stubs(:connected?).returns(true)
    connection.stubs(:call).with("AUTH", "admin", "secret").returns("OK")
    connection.stubs(:call_2args).with("SET", "key", "value").returns("OK")

    RR::Connection::TCP.expects(:new).returns(connection)

    client.send(:ensure_connected)
    result = client.set("key", "value")

    assert_equal "OK", result
  end
end
