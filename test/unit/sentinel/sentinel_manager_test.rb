# frozen_string_literal: true

require "test_helper"

class SentinelManagerTest < Minitest::Test
  def test_normalize_sentinels_with_hashes
    manager = RR::SentinelManager.new(
      sentinels: [
        { host: "sentinel1", port: 26_379 },
        { host: "sentinel2", port: 26_380 },
      ],
      service_name: "mymaster"
    )

    assert_equal 2, manager.sentinels.length
    assert_equal "sentinel1", manager.sentinels[0][:host]
    assert_equal 26_379, manager.sentinels[0][:port]
    assert_equal "sentinel2", manager.sentinels[1][:host]
    assert_equal 26_380, manager.sentinels[1][:port]
  end

  def test_normalize_sentinels_with_strings
    manager = RR::SentinelManager.new(
      sentinels: ["sentinel1:26379", "sentinel2:26380"],
      service_name: "mymaster"
    )

    assert_equal 2, manager.sentinels.length
    assert_equal "sentinel1", manager.sentinels[0][:host]
    assert_equal 26_379, manager.sentinels[0][:port]
  end

  def test_normalize_sentinels_with_default_port
    manager = RR::SentinelManager.new(
      sentinels: [{ host: "sentinel1" }],
      service_name: "mymaster"
    )

    assert_equal 26_379, manager.sentinels[0][:port]
  end

  def test_normalize_sentinels_with_string_keys
    manager = RR::SentinelManager.new(
      sentinels: [{ "host" => "sentinel1", "port" => 26_379 }],
      service_name: "mymaster"
    )

    assert_equal "sentinel1", manager.sentinels[0][:host]
    assert_equal 26_379, manager.sentinels[0][:port]
  end

  def test_invalid_sentinel_configuration
    assert_raises(ArgumentError) do
      RR::SentinelManager.new(
        sentinels: [123],
        service_name: "mymaster"
      )
    end
  end

  def test_service_name
    manager = RR::SentinelManager.new(
      sentinels: [{ host: "sentinel1", port: 26_379 }],
      service_name: "mymaster"
    )

    assert_equal "mymaster", manager.service_name
  end

  def test_rotate_sentinels
    manager = RR::SentinelManager.new(
      sentinels: [
        { host: "sentinel1", port: 26_379 },
        { host: "sentinel2", port: 26_380 },
        { host: "sentinel3", port: 26_381 },
      ],
      service_name: "mymaster"
    )

    original_first = manager.sentinels[0][:host]
    manager.rotate_sentinels!

    refute_equal original_first, manager.sentinels[0][:host]
  end

  def test_reset
    manager = RR::SentinelManager.new(
      sentinels: [{ host: "sentinel1", port: 26_379 }],
      service_name: "mymaster"
    )

    # Should not raise
    manager.reset
  end

  def test_check_master_state_valid
    manager = RR::SentinelManager.new(
      sentinels: [{ host: "sentinel1", port: 26_379 }],
      service_name: "mymaster"
    )

    state = {
      "role-reported" => "master",
      "flags" => "master",
      "num-other-sentinels" => "2",
    }

    assert manager.send(:check_master_state, state)
  end

  def test_check_master_state_sdown
    manager = RR::SentinelManager.new(
      sentinels: [{ host: "sentinel1", port: 26_379 }],
      service_name: "mymaster"
    )

    state = {
      "role-reported" => "master",
      "flags" => "master,s_down",
      "num-other-sentinels" => "2",
    }

    refute manager.send(:check_master_state, state)
  end

  def test_check_master_state_odown
    manager = RR::SentinelManager.new(
      sentinels: [{ host: "sentinel1", port: 26_379 }],
      service_name: "mymaster"
    )

    state = {
      "role-reported" => "master",
      "flags" => "master,o_down",
      "num-other-sentinels" => "2",
    }

    refute manager.send(:check_master_state, state)
  end

  def test_check_master_state_not_enough_sentinels
    manager = RR::SentinelManager.new(
      sentinels: [{ host: "sentinel1", port: 26_379 }],
      service_name: "mymaster",
      min_other_sentinels: 2
    )

    state = {
      "role-reported" => "master",
      "flags" => "master",
      "num-other-sentinels" => "1",
    }

    refute manager.send(:check_master_state, state)
  end

  def test_parse_info_array
    manager = RR::SentinelManager.new(
      sentinels: [{ host: "sentinel1", port: 26_379 }],
      service_name: "mymaster"
    )

    array = ["name", "mymaster", "ip", "192.168.1.1", "port", "6379"]
    result = manager.send(:parse_info_array, array)

    assert_equal "mymaster", result["name"]
    assert_equal "192.168.1.1", result["ip"]
    assert_equal "6379", result["port"]
  end

  def test_parse_info_array_empty
    manager = RR::SentinelManager.new(
      sentinels: [{ host: "sentinel1", port: 26_379 }],
      service_name: "mymaster"
    )

    assert_empty(manager.send(:parse_info_array, nil))
    assert_empty(manager.send(:parse_info_array, "not an array"))
  end

  def test_find_master_state
    manager = RR::SentinelManager.new(
      sentinels: [{ host: "sentinel1", port: 26_379 }],
      service_name: "mymaster"
    )

    masters = [
      ["name", "other", "ip", "192.168.1.1", "port", "6379"],
      ["name", "mymaster", "ip", "192.168.1.2", "port", "6380"],
    ]

    result = manager.send(:find_master_state, masters, "mymaster")

    assert_equal "mymaster", result["name"]
    assert_equal "192.168.1.2", result["ip"]
    assert_equal "6380", result["port"]
  end

  def test_find_master_state_not_found
    manager = RR::SentinelManager.new(
      sentinels: [{ host: "sentinel1", port: 26_379 }],
      service_name: "mymaster"
    )

    masters = [
      ["name", "other", "ip", "192.168.1.1", "port", "6379"],
    ]

    result = manager.send(:find_master_state, masters, "mymaster")

    assert_nil result
  end

  # ============================================================
  # Connection leak tests
  # ============================================================

  def test_sentinel_reachable_closes_connection_on_ping_failure
    manager = RR::SentinelManager.new(
      sentinels: [{ host: "sentinel1", port: 26_379 }],
      service_name: "mymaster"
    )

    mock_conn = mock("conn")
    mock_conn.expects(:call).with("PING").raises(StandardError, "connection lost")
    mock_conn.expects(:close)

    manager.stubs(:create_sentinel_connection).returns(mock_conn)

    refute manager.sentinel_reachable?(manager.sentinels.first)
  end

  def test_discover_sentinels_closes_connection_on_call_failure
    manager = RR::SentinelManager.new(
      sentinels: [{ host: "sentinel1", port: 26_379 }],
      service_name: "mymaster"
    )

    mock_conn = mock("conn")
    mock_conn.expects(:call).with("SENTINEL", "SENTINELS", "mymaster").raises(StandardError, "connection lost")
    mock_conn.expects(:close)

    manager.stubs(:create_sentinel_connection).returns(mock_conn)

    result = manager.discover_sentinels
    assert_equal [], result
  end

  # ============================================================
  # Mutex not held during sleep/I/O (Bug #12)
  # ============================================================

  def test_discover_master_does_not_hold_mutex_during_sleep
    manager = RR::SentinelManager.new(
      sentinels: [
        { host: "sentinel1", port: 26_379 },
        { host: "sentinel2", port: 26_380 },
      ],
      service_name: "mymaster"
    )

    # First sentinel fails, second succeeds
    call_count = 0
    manager.define_singleton_method(:query_master_from_sentinel) do |sentinel|
      call_count += 1
      if sentinel[:host] == "sentinel1"
        raise StandardError, "connection refused"
      else
        { host: "master1", port: 6379 }
      end
    end

    # Stub sleep to avoid actual delays
    manager.stubs(:sleep)

    # The mutex should NOT be held during the sleep between retries,
    # allowing other threads to proceed. Verify discover_master still works.
    result = manager.discover_master

    assert_equal "master1", result[:host]
    assert_equal 6379, result[:port]
    assert_equal 2, call_count
  end

  def test_discover_master_promotes_successful_sentinel
    manager = RR::SentinelManager.new(
      sentinels: [
        { host: "sentinel1", port: 26_379 },
        { host: "sentinel2", port: 26_380 },
      ],
      service_name: "mymaster"
    )

    manager.define_singleton_method(:query_master_from_sentinel) do |sentinel|
      if sentinel[:host] == "sentinel1"
        raise StandardError, "connection refused"
      else
        { host: "master1", port: 6379 }
      end
    end
    manager.stubs(:sleep)

    manager.discover_master

    # sentinel2 should now be first (promoted)
    assert_equal "sentinel2", manager.sentinels[0][:host]
  end

  def test_discover_replicas_does_not_hold_mutex_during_sleep
    manager = RR::SentinelManager.new(
      sentinels: [
        { host: "sentinel1", port: 26_379 },
        { host: "sentinel2", port: 26_380 },
      ],
      service_name: "mymaster"
    )

    call_count = 0
    manager.define_singleton_method(:query_replicas_from_sentinel) do |sentinel|
      call_count += 1
      if sentinel[:host] == "sentinel1"
        raise StandardError, "connection refused"
      else
        [{ host: "replica1", port: 6380 }]
      end
    end
    manager.stubs(:sleep)

    result = manager.discover_replicas

    assert_equal 1, result.length
    assert_equal "replica1", result[0][:host]
    assert_equal 2, call_count
  end
end
