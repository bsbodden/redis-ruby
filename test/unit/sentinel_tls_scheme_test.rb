# frozen_string_literal: true

require_relative "unit_test_helper"

# Tests for redis-rb issue #1249
# rediss:// scheme should auto-enable TLS for sentinel connections.
class SentinelTLSSchemeTest < Minitest::Test
  def test_rediss_scheme_enables_ssl_for_sentinel
    manager = RR::SentinelManager.new(
      sentinels: ["rediss://sentinel1.example.com:26379"],
      service_name: "mymaster"
    )

    sentinels = manager.instance_variable_get(:@sentinels)

    assert sentinels[0][:ssl]
    assert_equal "sentinel1.example.com", sentinels[0][:host]
    assert_equal 26_379, sentinels[0][:port]
  end

  def test_redis_scheme_does_not_enable_ssl
    manager = RR::SentinelManager.new(
      sentinels: ["redis://sentinel1.example.com:26379"],
      service_name: "mymaster"
    )

    sentinels = manager.instance_variable_get(:@sentinels)

    refute sentinels[0][:ssl]
  end

  def test_plain_host_port_does_not_enable_ssl
    manager = RR::SentinelManager.new(
      sentinels: ["sentinel1:26379"],
      service_name: "mymaster"
    )

    sentinels = manager.instance_variable_get(:@sentinels)

    refute sentinels[0][:ssl]
  end

  def test_hash_sentinel_with_ssl_flag
    manager = RR::SentinelManager.new(
      sentinels: [{ host: "sentinel1", port: 26_379, ssl: true }],
      service_name: "mymaster"
    )

    sentinels = manager.instance_variable_get(:@sentinels)

    assert sentinels[0][:ssl]
  end

  def test_hash_sentinel_defaults_to_no_ssl
    manager = RR::SentinelManager.new(
      sentinels: [{ host: "sentinel1", port: 26_379 }],
      service_name: "mymaster"
    )

    sentinels = manager.instance_variable_get(:@sentinels)

    refute sentinels[0][:ssl]
  end

  def test_mixed_sentinel_configs
    manager = RR::SentinelManager.new(
      sentinels: [
        "rediss://sentinel1:26379",
        { host: "sentinel2", port: 26_379 },
        "sentinel3:26379",
      ],
      service_name: "mymaster"
    )

    sentinels = manager.instance_variable_get(:@sentinels)

    assert sentinels[0][:ssl]
    refute sentinels[1][:ssl]
    refute sentinels[2][:ssl]
  end

  def test_rediss_sentinel_uses_ssl_connection
    manager = RR::SentinelManager.new(
      sentinels: [{ host: "sentinel1", port: 26_379, ssl: true }],
      service_name: "mymaster"
    )

    # SSL sentinel should create SSL connection
    RR::Connection::SSL.expects(:new).with(
      host: "sentinel1",
      port: 26_379,
      timeout: 0.5
    ).raises(RR::ConnectionError.new("expected - no real server"))

    assert_raises(RR::ConnectionError) do
      manager.send(:create_sentinel_connection, { host: "sentinel1", port: 26_379, ssl: true })
    end
  end

  def test_plain_sentinel_uses_tcp_connection
    manager = RR::SentinelManager.new(
      sentinels: [{ host: "sentinel1", port: 26_379 }],
      service_name: "mymaster"
    )

    RR::Connection::TCP.expects(:new).with(
      host: "sentinel1",
      port: 26_379,
      timeout: 0.5
    ).raises(RR::ConnectionError.new("expected - no real server"))

    assert_raises(RR::ConnectionError) do
      manager.send(:create_sentinel_connection, { host: "sentinel1", port: 26_379, ssl: false })
    end
  end
end
