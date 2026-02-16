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
end
