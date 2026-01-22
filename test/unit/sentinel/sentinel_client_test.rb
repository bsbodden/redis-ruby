# frozen_string_literal: true

require "test_helper"

class SentinelClientTest < Minitest::Test
  def test_initialize_with_valid_master_role
    # Don't actually connect in unit test
    client = RedisRuby::SentinelClient.allocate
    client.instance_variable_set(:@role, :master)
    client.instance_variable_set(:@service_name, "mymaster")

    assert_equal :master, client.role
    assert_equal "mymaster", client.service_name
  end

  def test_initialize_with_replica_role
    client = RedisRuby::SentinelClient.allocate
    client.instance_variable_set(:@role, :replica)

    assert_equal :replica, client.role
  end

  def test_initialize_with_slave_role_normalized
    # Test that :slave is normalized to :replica
    client = RedisRuby::SentinelClient.allocate
    client.send(:initialize,
                sentinels: [{ host: "sentinel1", port: 26_379 }],
                service_name: "mymaster",
                role: :slave)

    assert_equal :replica, client.role
  end

  def test_invalid_role
    assert_raises(ArgumentError) do
      RedisRuby::SentinelClient.new(
        sentinels: [{ host: "sentinel1", port: 26_379 }],
        service_name: "mymaster",
        role: :invalid
      )
    end
  end

  def test_master_predicate
    client = RedisRuby::SentinelClient.allocate
    client.instance_variable_set(:@role, :master)

    assert_predicate client, :master?
    refute_predicate client, :replica?
  end

  def test_replica_predicate
    client = RedisRuby::SentinelClient.allocate
    client.instance_variable_set(:@role, :replica)

    assert_predicate client, :replica?
    refute_predicate client, :master?
  end

  def test_readonly_error_detection
    client = RedisRuby::SentinelClient.allocate
    client.instance_variable_set(:@role, :master)

    error1 = RedisRuby::CommandError.new("READONLY You can't write against a read only replica")

    assert client.send(:readonly_error?, error1)

    error2 = RedisRuby::CommandError.new("ERR wrong number of arguments")

    refute client.send(:readonly_error?, error2)
  end

  def test_validate_role_with_valid_roles
    client = RedisRuby::SentinelClient.allocate

    # Should not raise for valid roles
    client.send(:validate_role!, :master)
    client.send(:validate_role!, :replica)
    client.send(:validate_role!, :slave)
  end

  def test_validate_role_with_invalid_role
    client = RedisRuby::SentinelClient.allocate

    assert_raises(ArgumentError) do
      client.send(:validate_role!, :invalid)
    end
  end

  def test_normalize_role
    client = RedisRuby::SentinelClient.allocate

    assert_equal :master, client.send(:normalize_role, :master)
    assert_equal :master, client.send(:normalize_role, "master")
    assert_equal :replica, client.send(:normalize_role, :replica)
    assert_equal :replica, client.send(:normalize_role, :slave)
  end

  def test_sentinel_manager_accessible
    client = RedisRuby::SentinelClient.allocate
    manager = RedisRuby::SentinelManager.new(
      sentinels: [{ host: "sentinel1", port: 26_379 }],
      service_name: "mymaster"
    )
    client.instance_variable_set(:@sentinel_manager, manager)

    assert_equal manager, client.sentinel_manager
  end

  def test_connected_when_no_connection
    client = RedisRuby::SentinelClient.allocate
    client.instance_variable_set(:@connection, nil)

    refute_predicate client, :connected?
  end

  def test_current_address_when_not_connected
    client = RedisRuby::SentinelClient.allocate
    client.instance_variable_set(:@current_address, nil)

    assert_nil client.current_address
  end

  def test_timeout_default
    client = RedisRuby::SentinelClient.allocate
    client.instance_variable_set(:@timeout, RedisRuby::SentinelClient::DEFAULT_TIMEOUT)

    assert_in_delta(5.0, client.timeout)
  end
end
