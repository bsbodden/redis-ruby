# frozen_string_literal: true

require_relative "unit_test_helper"

class DNSClientTest < Minitest::Test
  # ============================================================
  # retry_with_different_ip should retry the command after reconnection
  # ============================================================

  def test_call_retries_command_after_reconnection
    mock_conn = mock("connection")
    mock_conn.stubs(:connected?).returns(true)
    mock_conn.stubs(:close)

    # First call raises, second call (after reconnect) succeeds
    seq = sequence("call_seq")
    mock_conn.expects(:call).with("GET", "key").in_sequence(seq).raises(RR::ConnectionError, "lost connection")
    mock_conn.expects(:call).with("GET", "key").in_sequence(seq).returns("value")

    mock_resolver = mock("resolver")
    mock_resolver.stubs(:resolve).returns("10.0.0.2")

    client = RR::DNSClient.new(hostname: "redis.example.com", reconnect_attempts: 3)
    client.instance_variable_set(:@connection, mock_conn)
    client.instance_variable_set(:@dns_resolver, mock_resolver)
    client.stubs(:create_connection).returns(mock_conn)

    result = client.call("GET", "key")

    assert_equal "value", result
  end

  def test_call_1arg_retries_command_after_reconnection
    mock_conn = mock("connection")
    mock_conn.stubs(:connected?).returns(true)
    mock_conn.stubs(:close)

    seq = sequence("call_seq")
    mock_conn.expects(:call_1arg).with("GET", "key").in_sequence(seq).raises(RR::ConnectionError, "lost connection")
    mock_conn.expects(:call_1arg).with("GET", "key").in_sequence(seq).returns("value")

    mock_resolver = mock("resolver")
    mock_resolver.stubs(:resolve).returns("10.0.0.2")

    client = RR::DNSClient.new(hostname: "redis.example.com", reconnect_attempts: 3)
    client.instance_variable_set(:@connection, mock_conn)
    client.instance_variable_set(:@dns_resolver, mock_resolver)
    client.stubs(:create_connection).returns(mock_conn)

    result = client.call_1arg("GET", "key")

    assert_equal "value", result
  end

  def test_call_2args_retries_command_after_reconnection
    mock_conn = mock("connection")
    mock_conn.stubs(:connected?).returns(true)
    mock_conn.stubs(:close)

    seq = sequence("call_seq")
    mock_conn.expects(:call_2args).with("SET", "key", "val").in_sequence(seq).raises(RR::ConnectionError,
                                                                                     "lost connection")
    mock_conn.expects(:call_2args).with("SET", "key", "val").in_sequence(seq).returns("OK")

    mock_resolver = mock("resolver")
    mock_resolver.stubs(:resolve).returns("10.0.0.2")

    client = RR::DNSClient.new(hostname: "redis.example.com", reconnect_attempts: 3)
    client.instance_variable_set(:@connection, mock_conn)
    client.instance_variable_set(:@dns_resolver, mock_resolver)
    client.stubs(:create_connection).returns(mock_conn)

    result = client.call_2args("SET", "key", "val")

    assert_equal "OK", result
  end

  def test_call_raises_after_exhausting_reconnect_attempts
    mock_conn = mock("connection")
    mock_conn.stubs(:connected?).returns(true)
    mock_conn.stubs(:close)
    # Command always fails, and reconnection also always fails
    mock_conn.stubs(:call).raises(RR::ConnectionError, "lost connection")

    mock_resolver = mock("resolver")
    mock_resolver.stubs(:resolve).raises(StandardError, "DNS resolution failed")

    client = RR::DNSClient.new(hostname: "redis.example.com", reconnect_attempts: 2)
    client.instance_variable_set(:@connection, mock_conn)
    client.instance_variable_set(:@dns_resolver, mock_resolver)
    client.stubs(:create_connection).returns(mock_conn)

    assert_raises(RR::ConnectionError) { client.call("GET", "key") }
  end
end
