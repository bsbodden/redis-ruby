# frozen_string_literal: true

require_relative "unit_test_helper"

class DiscoveryServiceClientBranchTest < Minitest::Test
  def build_client
    client = RR::DiscoveryServiceClient.allocate
    client.instance_variable_set(:@database_name, "test-db")
    client.instance_variable_set(:@password, nil)
    client.instance_variable_set(:@db, 0)
    client.instance_variable_set(:@timeout, 5.0)
    client.instance_variable_set(:@ssl, false)
    client.instance_variable_set(:@ssl_params, {})
    client.instance_variable_set(:@reconnect_attempts, 3)
    client.instance_variable_set(:@connection, nil)
    client.instance_variable_set(:@current_address, nil)
    client.instance_variable_set(:@mutex, Mutex.new)

    discovery = mock("discovery_service")
    client.instance_variable_set(:@discovery_service, discovery)

    client
  end

  def mock_conn
    conn = mock("conn")
    conn.stubs(:close)
    conn.stubs(:connected?).returns(true)
    conn
  end

  # ============================================================
  # call / call_1arg / call_2args / call_3args
  # ============================================================

  def test_call_delegates_to_connection
    client = build_client
    conn = mock_conn
    conn.expects(:call).with("PING").returns("PONG")
    client.instance_variable_set(:@connection, conn)

    assert_equal "PONG", client.call("PING")
  end

  def test_call_1arg_delegates_to_connection
    client = build_client
    conn = mock_conn
    conn.expects(:call_1arg).with("GET", "key1").returns("value1")
    client.instance_variable_set(:@connection, conn)

    assert_equal "value1", client.call_1arg("GET", "key1")
  end

  def test_call_2args_delegates_to_connection
    client = build_client
    conn = mock_conn
    conn.expects(:call_2args).with("SET", "key1", "value1").returns("OK")
    client.instance_variable_set(:@connection, conn)

    assert_equal "OK", client.call_2args("SET", "key1", "value1")
  end

  def test_call_3args_delegates_to_connection
    client = build_client
    conn = mock_conn
    conn.expects(:call_3args).with("HSET", "hash", "field", "value").returns(1)
    client.instance_variable_set(:@connection, conn)

    assert_equal 1, client.call_3args("HSET", "hash", "field", "value")
  end

  def test_call_raises_command_error
    client = build_client
    conn = mock_conn
    error = RR::CommandError.new("ERR wrong type")
    conn.expects(:call).with("PING").returns(error)
    client.instance_variable_set(:@connection, conn)

    assert_raises(RR::CommandError) { client.call("PING") }
  end
end
