# frozen_string_literal: true

require "test_helper"

class SentinelCommandsTest < Minitest::Test
  def setup
    @mock_connection = mock("connection")
    @client = Object.new
    @client.extend(RedisRuby::Commands::Sentinel)
    @client.define_singleton_method(:call) { |*args| @mock_connection.call(*args) }
    @client.instance_variable_set(:@mock_connection, @mock_connection)
  end

  def test_sentinel_masters
    @mock_connection.expects(:call).with("SENTINEL", "MASTERS").returns([
      ["name", "master1", "ip", "192.168.1.1", "port", "6379"],
      ["name", "master2", "ip", "192.168.1.2", "port", "6380"]
    ])

    result = @client.sentinel_masters
    assert_equal 2, result.length
    assert_equal "master1", result[0]["name"]
    assert_equal "master2", result[1]["name"]
  end

  def test_sentinel_master
    @mock_connection.expects(:call).with("SENTINEL", "MASTER", "mymaster").returns(
      ["name", "mymaster", "ip", "192.168.1.1", "port", "6379"]
    )

    result = @client.sentinel_master("mymaster")
    assert_equal "mymaster", result["name"]
    assert_equal "192.168.1.1", result["ip"]
  end

  def test_sentinel_replicas
    @mock_connection.expects(:call).with("SENTINEL", "REPLICAS", "mymaster").returns([
      ["ip", "192.168.1.2", "port", "6380", "flags", "slave"],
      ["ip", "192.168.1.3", "port", "6381", "flags", "slave"]
    ])

    result = @client.sentinel_replicas("mymaster")
    assert_equal 2, result.length
    assert_equal "192.168.1.2", result[0]["ip"]
  end

  def test_sentinel_slaves_alias
    @mock_connection.expects(:call).with("SENTINEL", "REPLICAS", "mymaster").returns([])

    result = @client.sentinel_slaves("mymaster")
    assert_equal [], result
  end

  def test_sentinel_sentinels
    @mock_connection.expects(:call).with("SENTINEL", "SENTINELS", "mymaster").returns([
      ["ip", "192.168.1.10", "port", "26379"],
      ["ip", "192.168.1.11", "port", "26379"]
    ])

    result = @client.sentinel_sentinels("mymaster")
    assert_equal 2, result.length
  end

  def test_sentinel_get_master_addr_by_name
    @mock_connection.expects(:call).with("SENTINEL", "GET-MASTER-ADDR-BY-NAME", "mymaster").returns(
      ["192.168.1.1", "6379"]
    )

    result = @client.sentinel_get_master_addr_by_name("mymaster")
    assert_equal ["192.168.1.1", "6379"], result
  end

  def test_sentinel_reset
    @mock_connection.expects(:call).with("SENTINEL", "RESET", "*").returns(1)

    result = @client.sentinel_reset("*")
    assert_equal 1, result
  end

  def test_sentinel_failover
    @mock_connection.expects(:call).with("SENTINEL", "FAILOVER", "mymaster").returns("OK")

    result = @client.sentinel_failover("mymaster")
    assert_equal "OK", result
  end

  def test_sentinel_ckquorum
    @mock_connection.expects(:call).with("SENTINEL", "CKQUORUM", "mymaster").returns("OK 3 usable Sentinels.")

    result = @client.sentinel_ckquorum("mymaster")
    assert_equal "OK 3 usable Sentinels.", result
  end

  def test_sentinel_flushconfig
    @mock_connection.expects(:call).with("SENTINEL", "FLUSHCONFIG").returns("OK")

    result = @client.sentinel_flushconfig
    assert_equal "OK", result
  end

  def test_sentinel_monitor
    @mock_connection.expects(:call).with("SENTINEL", "MONITOR", "newmaster", "192.168.1.1", "6379", "2").returns("OK")

    result = @client.sentinel_monitor("newmaster", "192.168.1.1", 6379, 2)
    assert_equal "OK", result
  end

  def test_sentinel_remove
    @mock_connection.expects(:call).with("SENTINEL", "REMOVE", "mymaster").returns("OK")

    result = @client.sentinel_remove("mymaster")
    assert_equal "OK", result
  end

  def test_sentinel_set
    @mock_connection.expects(:call).with("SENTINEL", "SET", "mymaster", "quorum", "3").returns("OK")

    result = @client.sentinel_set("mymaster", "quorum", 3)
    assert_equal "OK", result
  end

  def test_sentinel_myid
    @mock_connection.expects(:call).with("SENTINEL", "MYID").returns("abc123")

    result = @client.sentinel_myid
    assert_equal "abc123", result
  end

  def test_sentinel_ping
    @mock_connection.expects(:call).with("PING").returns("PONG")

    result = @client.sentinel_ping
    assert_equal "PONG", result
  end

  def test_sentinel_info_without_section
    @mock_connection.expects(:call).with("INFO").returns("# Server\nredis_version:8.0.0")

    result = @client.sentinel_info
    assert_includes result, "redis_version"
  end

  def test_sentinel_info_with_section
    @mock_connection.expects(:call).with("INFO", "sentinel").returns("# Sentinel\nsentinel_masters:1")

    result = @client.sentinel_info("sentinel")
    assert_includes result, "sentinel_masters"
  end
end
