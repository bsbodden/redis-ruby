# frozen_string_literal: true

require_relative "unit_test_helper"

# =====================================================================
# Comprehensive branch-coverage tests for:
#   - RR::SentinelClient  (lib/redis_ruby/sentinel_client.rb)
#   - RR::SentinelManager (lib/redis_ruby/sentinel_manager.rb)
#
# All network I/O is mocked via mocha stubs -- no real Redis needed.
# =====================================================================

# -----------------------------------------------------------------
# SentinelManager tests
# -----------------------------------------------------------------
class SentinelManagerBranchTest < Minitest::Test
  # Helper: build manager with sensible defaults
  def build_manager(sentinels: [{ host: "s1", port: 26_379 }],
                    service_name: "mymaster",
                    password: nil, sentinel_password: nil,
                    min_other_sentinels: 0, timeout: 0.5)
    RR::SentinelManager.new(
      sentinels: sentinels,
      service_name: service_name,
      password: password,
      sentinel_password: sentinel_password,
      min_other_sentinels: min_other_sentinels,
      timeout: timeout
    )
  end

  # Helper: build a fake connection object
  def mock_conn
    conn = mock("conn")
    conn.stubs(:close)
    conn
  end

  # ============================================================
  # normalize_sentinels
  # ============================================================

  def test_normalize_hash_with_symbol_keys
    mgr = build_manager(sentinels: [{ host: "h1", port: 26_379 }])

    assert_equal "h1", mgr.sentinels[0][:host]
    assert_equal 26_379, mgr.sentinels[0][:port]
  end

  def test_normalize_hash_with_string_keys
    mgr = build_manager(sentinels: [{ "host" => "h2", "port" => 26_380 }])

    assert_equal "h2", mgr.sentinels[0][:host]
    assert_equal 26_380, mgr.sentinels[0][:port]
  end

  def test_normalize_hash_missing_port_uses_default
    mgr = build_manager(sentinels: [{ host: "h3" }])

    assert_equal 26_379, mgr.sentinels[0][:port]
  end

  def test_normalize_string_with_port
    mgr = build_manager(sentinels: ["sentinel1:26380"])

    assert_equal "sentinel1", mgr.sentinels[0][:host]
    assert_equal 26_380, mgr.sentinels[0][:port]
  end

  def test_normalize_string_without_port_uses_default
    mgr = build_manager(sentinels: ["sentinel1"])

    assert_equal "sentinel1", mgr.sentinels[0][:host]
    assert_equal 26_379, mgr.sentinels[0][:port]
  end

  def test_normalize_invalid_type_raises
    assert_raises(ArgumentError) do
      build_manager(sentinels: [123])
    end
  end

  def test_normalize_multiple_sentinels
    mgr = build_manager(sentinels: [
      { host: "s1", port: 26_379 },
      "s2:26380",
      { "host" => "s3" },
    ])

    assert_equal 3, mgr.sentinels.length
  end
  # ============================================================
  # password / sentinel_password
  # ============================================================

  def test_password_used_when_set
    conn = mock_conn
    conn.expects(:call).with("AUTH", "secret").returns("OK")
    conn.expects(:call).with("SENTINEL", "MASTERS").returns([])
    RR::Connection::TCP.stubs(:new).returns(conn)

    mgr = build_manager(password: "secret")
    # discover_master will fail because no master found, but AUTH should be called
    assert_raises(RR::MasterNotFoundError) { mgr.discover_master }
  end

  def test_sentinel_password_alias
    conn = mock_conn
    conn.expects(:call).with("AUTH", "alias_pwd").returns("OK")
    conn.expects(:call).with("SENTINEL", "MASTERS").returns([])
    RR::Connection::TCP.stubs(:new).returns(conn)

    mgr = build_manager(sentinel_password: "alias_pwd")
    assert_raises(RR::MasterNotFoundError) { mgr.discover_master }
  end

  def test_no_auth_when_no_password
    conn = mock_conn
    conn.expects(:call).with("AUTH", anything).never
    conn.expects(:call).with("SENTINEL", "MASTERS").returns([])
    RR::Connection::TCP.stubs(:new).returns(conn)

    mgr = build_manager
    assert_raises(RR::MasterNotFoundError) { mgr.discover_master }
  end
end

class SentinelManagerBranchTestPart2 < Minitest::Test
  # Helper: build manager with sensible defaults
  def build_manager(sentinels: [{ host: "s1", port: 26_379 }],
                    service_name: "mymaster",
                    password: nil, sentinel_password: nil,
                    min_other_sentinels: 0, timeout: 0.5)
    RR::SentinelManager.new(
      sentinels: sentinels,
      service_name: service_name,
      password: password,
      sentinel_password: sentinel_password,
      min_other_sentinels: min_other_sentinels,
      timeout: timeout
    )
  end

  # Helper: build a fake connection object
  def mock_conn
    conn = mock("conn")
    conn.stubs(:close)
    conn
  end

  # ============================================================
  # normalize_sentinels
  # ============================================================

  # ============================================================
  # discover_master
  # ============================================================

  def test_discover_master_success
    master_info = [
      "name", "mymaster", "ip", "10.0.0.1", "port", "6379",
      "role-reported", "master", "flags", "master",
      "num-other-sentinels", "2",
    ]

    conn = mock_conn
    conn.stubs(:call).with("SENTINEL", "MASTERS").returns([master_info])
    conn.stubs(:call).with("SENTINEL", "SENTINELS", "mymaster").returns([])
    RR::Connection::TCP.stubs(:new).returns(conn)

    mgr = build_manager
    address = mgr.discover_master

    assert_equal "10.0.0.1", address[:host]
    assert_equal 6379, address[:port]
  end

  def test_discover_master_promotes_sentinel_on_success
    # First sentinel fails, second succeeds => second is promoted to front
    conn_fail = mock_conn
    conn_fail.stubs(:call).raises(StandardError, "down")
    conn_ok = stub_master_conn(default_master_info)

    RR::Connection::TCP.stubs(:new).returns(conn_fail).then.returns(conn_ok)

    sentinels = [{ host: "s1", port: 26_379 }, { host: "s2", port: 26_380 }]
    mgr = build_manager(sentinels: sentinels)
    mgr.stubs(:sleep)

    address = mgr.discover_master

    assert_equal "10.0.0.1", address[:host]
    assert_equal "s2", mgr.sentinels[0][:host]
  end

  def test_discover_master_no_promote_when_first_sentinel_succeeds
    master_info = [
      "name", "mymaster", "ip", "10.0.0.1", "port", "6379",
      "role-reported", "master", "flags", "master",
      "num-other-sentinels", "2",
    ]

    conn = mock_conn
    conn.stubs(:call).with("SENTINEL", "MASTERS").returns([master_info])
    conn.stubs(:call).with("SENTINEL", "SENTINELS", "mymaster").returns([])
    RR::Connection::TCP.stubs(:new).returns(conn)

    mgr = build_manager(sentinels: [
      { host: "s1", port: 26_379 },
      { host: "s2", port: 26_380 },
    ])
    mgr.discover_master

    # s1 should still be first (index 0, no promotion needed)
    assert_equal "s1", mgr.sentinels[0][:host]
  end

  def test_discover_master_all_sentinels_fail
    conn = mock_conn
    conn.stubs(:call).raises(StandardError, "unreachable")
    RR::Connection::TCP.stubs(:new).returns(conn)

    mgr = build_manager(sentinels: [
      { host: "s1", port: 26_379 },
      { host: "s2", port: 26_380 },
    ])
    mgr.stubs(:sleep) # skip sleep

    error = assert_raises(RR::MasterNotFoundError) { mgr.discover_master }
    assert_includes error.message, "mymaster"
    assert_includes error.message, "s1:26379"
    assert_includes error.message, "s2:26380"
  end

  def test_discover_master_nil_address_when_state_check_fails
    # Master is sdown => check_master_state returns false => address nil
    master_info = [
      "name", "mymaster", "ip", "10.0.0.1", "port", "6379",
      "role-reported", "master", "flags", "master,s_down",
      "num-other-sentinels", "2",
    ]

    conn = mock_conn
    conn.stubs(:call).with("SENTINEL", "MASTERS").returns([master_info])
    RR::Connection::TCP.stubs(:new).returns(conn)

    mgr = build_manager
    assert_raises(RR::MasterNotFoundError) { mgr.discover_master }
  end

  def test_discover_master_no_matching_service
    other_master = [
      "name", "other_service", "ip", "10.0.0.1", "port", "6379",
      "role-reported", "master", "flags", "master",
      "num-other-sentinels", "2",
    ]

    conn = mock_conn
    conn.stubs(:call).with("SENTINEL", "MASTERS").returns([other_master])
    RR::Connection::TCP.stubs(:new).returns(conn)

    mgr = build_manager
    assert_raises(RR::MasterNotFoundError) { mgr.discover_master }
  end

  private

  def default_master_info
    ["name", "mymaster", "ip", "10.0.0.1", "port", "6379",
     "role-reported", "master", "flags", "master", "num-other-sentinels", "2",]
  end

  def stub_master_conn(info)
    conn = mock_conn
    conn.stubs(:call).with("SENTINEL", "MASTERS").returns([info])
    conn.stubs(:call).with("SENTINEL", "SENTINELS", "mymaster").returns([])
    conn
  end
end

class SentinelManagerBranchTestPart3 < Minitest::Test
  # Helper: build manager with sensible defaults
  def build_manager(sentinels: [{ host: "s1", port: 26_379 }],
                    service_name: "mymaster",
                    password: nil, sentinel_password: nil,
                    min_other_sentinels: 0, timeout: 0.5)
    RR::SentinelManager.new(
      sentinels: sentinels,
      service_name: service_name,
      password: password,
      sentinel_password: sentinel_password,
      min_other_sentinels: min_other_sentinels,
      timeout: timeout
    )
  end

  # Helper: build a fake connection object
  def mock_conn
    conn = mock("conn")
    conn.stubs(:close)
    conn
  end

  # ============================================================
  # normalize_sentinels
  # ============================================================

  # ============================================================
  # check_master_state -- branch coverage
  # ============================================================

  def test_check_master_state_valid_with_role_reported
    mgr = build_manager
    state = {
      "role-reported" => "master",
      "flags" => "master",
      "num-other-sentinels" => "2",
    }

    assert mgr.send(:check_master_state, state)
  end

  def test_check_master_state_valid_via_flags_only
    mgr = build_manager
    state = {
      "role-reported" => "slave", # not master role-reported
      "flags" => "master", # but flags includes master
      "num-other-sentinels" => "0",
    }

    assert mgr.send(:check_master_state, state)
  end

  def test_check_master_state_not_master_role_or_flag
    mgr = build_manager
    state = {
      "role-reported" => "slave",
      "flags" => "slave",
      "num-other-sentinels" => "0",
    }

    refute mgr.send(:check_master_state, state)
  end

  def test_check_master_state_sdown
    mgr = build_manager
    state = {
      "role-reported" => "master",
      "flags" => "master,s_down",
      "num-other-sentinels" => "2",
    }

    refute mgr.send(:check_master_state, state)
  end

  def test_check_master_state_odown
    mgr = build_manager
    state = {
      "role-reported" => "master",
      "flags" => "master,o_down",
      "num-other-sentinels" => "2",
    }

    refute mgr.send(:check_master_state, state)
  end

  def test_check_master_state_not_enough_sentinels
    mgr = build_manager(min_other_sentinels: 3)
    state = {
      "role-reported" => "master",
      "flags" => "master",
      "num-other-sentinels" => "1",
    }

    refute mgr.send(:check_master_state, state)
  end

  def test_check_master_state_nil_flags
    mgr = build_manager
    state = {
      "role-reported" => "master",
      "flags" => nil,
      "num-other-sentinels" => "0",
    }
    # role-reported is master, but flags nil means flags&.include?("master")
    # returns nil (falsy), so first condition is:
    #   "master" == "master" || nil  => true (short-circuit)
    # Then flags&.include?("s_down") => nil (falsy) => no s_down
    # Then flags&.include?("o_down") => nil (falsy) => no o_down
    # Should pass
    assert mgr.send(:check_master_state, state)
  end
  # ============================================================
  # find_master_state
  # ============================================================

  def test_find_master_state_found
    mgr = build_manager
    masters = [
      ["name", "other", "ip", "1.2.3.4", "port", "6379"],
      ["name", "mymaster", "ip", "5.6.7.8", "port", "6380"],
    ]
    result = mgr.send(:find_master_state, masters, "mymaster")

    assert_equal "mymaster", result["name"]
    assert_equal "5.6.7.8", result["ip"]
  end

  def test_find_master_state_not_found
    mgr = build_manager
    masters = [["name", "other", "ip", "1.2.3.4", "port", "6379"]]
    result = mgr.send(:find_master_state, masters, "mymaster")

    assert_nil result
  end

  def test_find_master_state_nil_input
    mgr = build_manager
    result = mgr.send(:find_master_state, nil, "mymaster")

    assert_nil result
  end

  def test_find_master_state_non_array_input
    mgr = build_manager
    result = mgr.send(:find_master_state, "not_an_array", "mymaster")

    assert_nil result
  end
end

class SentinelManagerBranchTestPart4 < Minitest::Test
  # Helper: build manager with sensible defaults
  def build_manager(sentinels: [{ host: "s1", port: 26_379 }],
                    service_name: "mymaster",
                    password: nil, sentinel_password: nil,
                    min_other_sentinels: 0, timeout: 0.5)
    RR::SentinelManager.new(
      sentinels: sentinels,
      service_name: service_name,
      password: password,
      sentinel_password: sentinel_password,
      min_other_sentinels: min_other_sentinels,
      timeout: timeout
    )
  end

  # Helper: build a fake connection object
  def mock_conn
    conn = mock("conn")
    conn.stubs(:close)
    conn
  end

  # ============================================================
  # normalize_sentinels
  # ============================================================

  # ============================================================
  # refresh_sentinels
  # ============================================================

  def test_refresh_sentinels_adds_new_sentinel
    conn = mock_conn
    sentinel_info = %w[ip s3 port 26381]
    conn.stubs(:call).with("SENTINEL", "SENTINELS", "mymaster").returns([sentinel_info])

    mgr = build_manager(sentinels: [{ host: "s1", port: 26_379 }])
    initial_count = mgr.sentinels.length

    mgr.send(:refresh_sentinels, conn)

    assert_equal initial_count + 1, mgr.sentinels.length
    assert_equal "s3", mgr.sentinels.last[:host]
    assert_equal 26_381, mgr.sentinels.last[:port]
  end

  def test_refresh_sentinels_skips_existing
    conn = mock_conn
    sentinel_info = %w[ip s1 port 26379]
    conn.stubs(:call).with("SENTINEL", "SENTINELS", "mymaster").returns([sentinel_info])

    mgr = build_manager(sentinels: [{ host: "s1", port: 26_379 }])
    initial_count = mgr.sentinels.length

    mgr.send(:refresh_sentinels, conn)

    assert_equal initial_count, mgr.sentinels.length
  end

  def test_refresh_sentinels_non_array_response
    conn = mock_conn
    conn.stubs(:call).with("SENTINEL", "SENTINELS", "mymaster").returns("not an array")

    mgr = build_manager
    initial_count = mgr.sentinels.length

    # Should return early without error
    mgr.send(:refresh_sentinels, conn)

    assert_equal initial_count, mgr.sentinels.length
  end

  def test_refresh_sentinels_handles_error_gracefully
    conn = mock_conn
    conn.stubs(:call).with("SENTINEL", "SENTINELS", "mymaster").raises(StandardError, "boom")

    mgr = build_manager
    # Should not raise
    mgr.send(:refresh_sentinels, conn)
  end
  # ============================================================
  # discover_replicas
  # ============================================================

  def test_discover_replicas_success
    replica_info = [
      ["ip", "10.0.0.2", "port", "6380", "flags", "slave"],
      ["ip", "10.0.0.3", "port", "6381", "flags", "slave"],
    ]

    conn = mock_conn
    conn.stubs(:call).with("SENTINEL", "REPLICAS", "mymaster").returns(replica_info)
    RR::Connection::TCP.stubs(:new).returns(conn)

    mgr = build_manager
    replicas = mgr.discover_replicas

    assert_equal 2, replicas.length
    assert_equal "10.0.0.2", replicas[0][:host]
    assert_equal 6380, replicas[0][:port]
  end

  def test_discover_replicas_filters_out_sdown
    replica_info = [
      ["ip", "10.0.0.2", "port", "6380", "flags", "slave,s_down"],
      ["ip", "10.0.0.3", "port", "6381", "flags", "slave"],
    ]

    conn = mock_conn
    conn.stubs(:call).with("SENTINEL", "REPLICAS", "mymaster").returns(replica_info)
    RR::Connection::TCP.stubs(:new).returns(conn)

    mgr = build_manager
    replicas = mgr.discover_replicas

    assert_equal 1, replicas.length
    assert_equal "10.0.0.3", replicas[0][:host]
  end

  def test_discover_replicas_filters_out_odown
    replica_info = [
      ["ip", "10.0.0.2", "port", "6380", "flags", "slave,o_down"],
    ]

    conn = mock_conn
    conn.stubs(:call).with("SENTINEL", "REPLICAS", "mymaster").returns(replica_info)
    RR::Connection::TCP.stubs(:new).returns(conn)

    mgr = build_manager
    # All replicas filtered out, but returns empty array from first sentinel
    # Then second sentinel checked if available
    # With single sentinel, returns empty, not matched by !replicas.empty?
    # So falls through to raise
    assert_raises(RR::ReplicaNotFoundError) { mgr.discover_replicas }
  end

  def test_discover_replicas_filters_out_disconnected
    replica_info = [
      ["ip", "10.0.0.2", "port", "6380", "flags", "slave,disconnected"],
    ]

    conn = mock_conn
    conn.stubs(:call).with("SENTINEL", "REPLICAS", "mymaster").returns(replica_info)
    RR::Connection::TCP.stubs(:new).returns(conn)

    mgr = build_manager
    assert_raises(RR::ReplicaNotFoundError) { mgr.discover_replicas }
  end

  def test_discover_replicas_non_array_result
    conn = mock_conn
    conn.stubs(:call).with("SENTINEL", "REPLICAS", "mymaster").returns("not_array")
    RR::Connection::TCP.stubs(:new).returns(conn)

    mgr = build_manager
    assert_raises(RR::ReplicaNotFoundError) { mgr.discover_replicas }
  end

  def test_discover_replicas_all_sentinels_fail
    conn = mock_conn
    conn.stubs(:call).raises(StandardError, "err")
    RR::Connection::TCP.stubs(:new).returns(conn)

    mgr = build_manager(sentinels: [
      { host: "s1", port: 26_379 },
      { host: "s2", port: 26_380 },
    ])
    mgr.stubs(:sleep)

    error = assert_raises(RR::ReplicaNotFoundError) { mgr.discover_replicas }
    assert_includes error.message, "mymaster"
  end

  def test_discover_replicas_empty_result_from_sentinel
    conn = mock_conn
    conn.stubs(:call).with("SENTINEL", "REPLICAS", "mymaster").returns([])
    RR::Connection::TCP.stubs(:new).returns(conn)

    mgr = build_manager
    assert_raises(RR::ReplicaNotFoundError) { mgr.discover_replicas }
  end
end

class SentinelManagerBranchTestPart5 < Minitest::Test
  # Helper: build manager with sensible defaults
  def build_manager(sentinels: [{ host: "s1", port: 26_379 }],
                    service_name: "mymaster",
                    password: nil, sentinel_password: nil,
                    min_other_sentinels: 0, timeout: 0.5)
    RR::SentinelManager.new(
      sentinels: sentinels,
      service_name: service_name,
      password: password,
      sentinel_password: sentinel_password,
      min_other_sentinels: min_other_sentinels,
      timeout: timeout
    )
  end

  # Helper: build a fake connection object
  def mock_conn
    conn = mock("conn")
    conn.stubs(:close)
    conn
  end

  # ============================================================
  # normalize_sentinels
  # ============================================================

  # ============================================================
  # random_replica
  # ============================================================

  def test_random_replica
    replica_info = [
      ["ip", "10.0.0.2", "port", "6380", "flags", "slave"],
      ["ip", "10.0.0.3", "port", "6381", "flags", "slave"],
    ]

    conn = mock_conn
    conn.stubs(:call).with("SENTINEL", "REPLICAS", "mymaster").returns(replica_info)
    RR::Connection::TCP.stubs(:new).returns(conn)

    mgr = build_manager
    replica = mgr.random_replica

    assert_includes %w[10.0.0.2 10.0.0.3], replica[:host]
  end
  # ============================================================
  # rotate_replicas
  # ============================================================

  def test_rotate_replicas_yields_all_replicas
    replica_info = [
      ["ip", "10.0.0.2", "port", "6380", "flags", "slave"],
      ["ip", "10.0.0.3", "port", "6381", "flags", "slave"],
    ]

    conn = mock_conn
    conn.stubs(:call).with("SENTINEL", "REPLICAS", "mymaster").returns(replica_info)
    # discover_master is called as fallback; stub it to return empty (triggers MasterNotFoundError)
    conn.stubs(:call).with("SENTINEL", "MASTERS").returns([])
    conn.stubs(:call).with("SENTINEL", "SENTINELS", "mymaster").returns([])
    RR::Connection::TCP.stubs(:new).returns(conn)

    mgr = build_manager
    yielded = []

    # rotate_replicas yields replicas, then master fallback (which fails silently), then raises
    assert_raises(RR::ReplicaNotFoundError) do
      mgr.rotate_replicas { |addr| yielded << addr }
    end

    # Should have yielded 2 replicas
    assert_equal 2, yielded.length
  end

  def test_rotate_replicas_returns_enumerator_without_block
    replica_info = [
      ["ip", "10.0.0.2", "port", "6380", "flags", "slave"],
    ]

    conn = mock_conn
    conn.stubs(:call).with("SENTINEL", "REPLICAS", "mymaster").returns(replica_info)
    RR::Connection::TCP.stubs(:new).returns(conn)

    mgr = build_manager
    result = mgr.rotate_replicas

    assert_kind_of Enumerator, result
  end

  def test_rotate_replicas_falls_back_to_master
    replica_info = [["ip", "10.0.0.2", "port", "6380", "flags", "slave"]]
    master_info = ["name", "mymaster", "ip", "10.0.0.1", "port", "6379",
                   "role-reported", "master", "flags", "master", "num-other-sentinels", "0",]

    conn = mock_conn
    conn.stubs(:call).with("SENTINEL", "REPLICAS", "mymaster").returns(replica_info)
    conn.stubs(:call).with("SENTINEL", "MASTERS").returns([master_info])
    conn.stubs(:call).with("SENTINEL", "SENTINELS", "mymaster").returns([])
    RR::Connection::TCP.stubs(:new).returns(conn)

    mgr = build_manager
    yielded = []
    assert_raises(RR::ReplicaNotFoundError) { mgr.rotate_replicas { |addr| yielded << addr } }

    hosts = yielded.map { |a| a[:host] }

    assert_includes hosts, "10.0.0.2"
    assert_includes hosts, "10.0.0.1"
  end

  def test_rotate_replicas_master_fallback_ignored_on_error
    # If both replicas and master discovery fail, master error is swallowed
    replica_info = [
      ["ip", "10.0.0.2", "port", "6380", "flags", "slave"],
    ]

    conn = mock_conn
    conn.stubs(:call).with("SENTINEL", "REPLICAS", "mymaster").returns(replica_info)
    conn.stubs(:call).with("SENTINEL", "MASTERS").returns([])
    RR::Connection::TCP.stubs(:new).returns(conn)

    mgr = build_manager
    yielded = []

    error = assert_raises(RR::ReplicaNotFoundError) do
      mgr.rotate_replicas { |addr| yielded << addr }
    end
    assert_includes error.message, "mymaster"
  end
  # ============================================================
  # rotate_sentinels!
  # ============================================================

  def test_rotate_sentinels
    mgr = build_manager(sentinels: [
      { host: "s1", port: 26_379 },
      { host: "s2", port: 26_380 },
      { host: "s3", port: 26_381 },
    ])

    first = mgr.sentinels[0][:host]
    mgr.rotate_sentinels!

    refute_equal first, mgr.sentinels[0][:host]
  end
  # ============================================================
  # reset
  # ============================================================

  def test_reset_clears_rr_counter
    mgr = build_manager
    mgr.instance_variable_set(:@slave_rr_counter, 5)
    mgr.reset

    assert_nil mgr.instance_variable_get(:@slave_rr_counter)
  end
end

class SentinelManagerBranchTestPart6 < Minitest::Test
  # Helper: build manager with sensible defaults
  def build_manager(sentinels: [{ host: "s1", port: 26_379 }],
                    service_name: "mymaster",
                    password: nil, sentinel_password: nil,
                    min_other_sentinels: 0, timeout: 0.5)
    RR::SentinelManager.new(
      sentinels: sentinels,
      service_name: service_name,
      password: password,
      sentinel_password: sentinel_password,
      min_other_sentinels: min_other_sentinels,
      timeout: timeout
    )
  end

  # Helper: build a fake connection object
  def mock_conn
    conn = mock("conn")
    conn.stubs(:close)
    conn
  end

  # ============================================================
  # normalize_sentinels
  # ============================================================

  # ============================================================
  # sentinel_reachable?
  # ============================================================

  def test_sentinel_reachable_true
    conn = mock_conn
    conn.expects(:call).with("PING").returns("PONG")
    RR::Connection::TCP.stubs(:new).returns(conn)

    mgr = build_manager

    assert mgr.sentinel_reachable?({ host: "s1", port: 26_379 })
  end

  def test_sentinel_reachable_not_pong
    conn = mock_conn
    conn.expects(:call).with("PING").returns("NOT_PONG")
    RR::Connection::TCP.stubs(:new).returns(conn)

    mgr = build_manager

    refute mgr.sentinel_reachable?({ host: "s1", port: 26_379 })
  end

  def test_sentinel_reachable_connection_error
    RR::Connection::TCP.stubs(:new).raises(StandardError, "connection refused")

    mgr = build_manager

    refute mgr.sentinel_reachable?({ host: "s1", port: 26_379 })
  end
  # ============================================================
  # discover_sentinels
  # ============================================================

  def test_discover_sentinels_success
    sentinel_response = [
      %w[ip s2 port 26380],
      %w[ip s3 port 26381],
    ]

    conn = mock_conn
    conn.expects(:call).with("SENTINEL", "SENTINELS", "mymaster").returns(sentinel_response)
    RR::Connection::TCP.stubs(:new).returns(conn)

    mgr = build_manager
    sentinels = mgr.discover_sentinels

    assert_equal 2, sentinels.length
    assert_equal "s2", sentinels[0][:host]
    assert_equal 26_380, sentinels[0][:port]
  end

  def test_discover_sentinels_deduplicates
    sentinel_response = [
      %w[ip s2 port 26380],
      %w[ip s2 port 26380],
    ]

    conn = mock_conn
    conn.expects(:call).with("SENTINEL", "SENTINELS", "mymaster").returns(sentinel_response)
    RR::Connection::TCP.stubs(:new).returns(conn)

    mgr = build_manager
    sentinels = mgr.discover_sentinels

    assert_equal 1, sentinels.length
  end

  def test_discover_sentinels_error_continues
    conn_fail = mock_conn
    conn_fail.stubs(:call).raises(StandardError, "down")

    conn_ok = mock_conn
    conn_ok.expects(:call).with("SENTINEL", "SENTINELS", "mymaster").returns([%w[ip s3 port 26381]])

    RR::Connection::TCP.stubs(:new)
      .returns(conn_fail)
      .then.returns(conn_ok)

    mgr = build_manager(sentinels: [
      { host: "s1", port: 26_379 },
      { host: "s2", port: 26_380 },
    ])
    sentinels = mgr.discover_sentinels

    assert_equal 1, sentinels.length
    assert_equal "s3", sentinels[0][:host]
  end

  def test_discover_sentinels_breaks_when_result_found
    sentinel_response1 = [%w[ip s3 port 26381]]

    conn1 = mock_conn
    conn1.expects(:call).with("SENTINEL", "SENTINELS", "mymaster").returns(sentinel_response1)

    conn2 = mock_conn
    # Second sentinel should NOT be queried because we break after first success
    conn2.expects(:call).never

    RR::Connection::TCP.stubs(:new)
      .returns(conn1)

    mgr = build_manager(sentinels: [
      { host: "s1", port: 26_379 },
      { host: "s2", port: 26_380 },
    ])
    sentinels = mgr.discover_sentinels

    assert_equal 1, sentinels.length
  end

  def test_discover_sentinels_empty_from_all
    conn = mock_conn
    conn.stubs(:call).with("SENTINEL", "SENTINELS", "mymaster").returns([])
    RR::Connection::TCP.stubs(:new).returns(conn)

    mgr = build_manager
    sentinels = mgr.discover_sentinels

    assert_empty sentinels
  end
  # ============================================================
  # parse_info_array
  # ============================================================

  def test_parse_info_array_valid
    mgr = build_manager
    result = mgr.send(:parse_info_array, ["name", "mymaster", "ip", "1.2.3.4"])

    assert_equal "mymaster", result["name"]
    assert_equal "1.2.3.4", result["ip"]
  end

  def test_parse_info_array_nil
    mgr = build_manager

    assert_empty(mgr.send(:parse_info_array, nil))
  end

  def test_parse_info_array_non_array
    mgr = build_manager

    assert_empty(mgr.send(:parse_info_array, "string"))
  end
end

class SentinelManagerBranchTestPart7 < Minitest::Test
  # Helper: build manager with sensible defaults
  def build_manager(sentinels: [{ host: "s1", port: 26_379 }],
                    service_name: "mymaster",
                    password: nil, sentinel_password: nil,
                    min_other_sentinels: 0, timeout: 0.5)
    RR::SentinelManager.new(
      sentinels: sentinels,
      service_name: service_name,
      password: password,
      sentinel_password: sentinel_password,
      min_other_sentinels: min_other_sentinels,
      timeout: timeout
    )
  end

  # Helper: build a fake connection object
  def mock_conn
    conn = mock("conn")
    conn.stubs(:close)
    conn
  end

  # ============================================================
  # normalize_sentinels
  # ============================================================

  # ============================================================
  # verify_master_role?
  # ============================================================

  def test_verify_master_role_true
    conn = mock_conn
    conn.expects(:call).with("ROLE").returns(["master", 0, []])
    RR::Connection::TCP.stubs(:new).returns(conn)

    mgr = build_manager

    assert mgr.send(:verify_master_role?, { host: "10.0.0.1", port: 6379 })
  end

  def test_verify_master_role_false_when_slave
    conn = mock_conn
    conn.expects(:call).with("ROLE").returns(["slave", "10.0.0.1", 6379, "connected", 100])
    RR::Connection::TCP.stubs(:new).returns(conn)

    mgr = build_manager

    refute mgr.send(:verify_master_role?, { host: "10.0.0.1", port: 6379 })
  end

  def test_verify_master_role_false_on_error
    conn = mock_conn
    conn.expects(:call).with("ROLE").raises(StandardError, "connection lost")
    RR::Connection::TCP.stubs(:new).returns(conn)

    mgr = build_manager

    refute mgr.send(:verify_master_role?, { host: "10.0.0.1", port: 6379 })
  end

  def test_verify_master_role_false_when_non_array_response
    conn = mock_conn
    conn.expects(:call).with("ROLE").returns("invalid")
    RR::Connection::TCP.stubs(:new).returns(conn)

    mgr = build_manager

    refute mgr.send(:verify_master_role?, { host: "10.0.0.1", port: 6379 })
  end
  # ============================================================
  # create_sentinel_connection with password
  # ============================================================

  def test_create_sentinel_connection_with_password
    conn = mock_conn
    conn.expects(:call).with("AUTH", "my_pass").returns("OK")
    RR::Connection::TCP.stubs(:new).returns(conn)

    mgr = build_manager(password: "my_pass")
    result = mgr.send(:create_sentinel_connection, { host: "s1", port: 26_379 })

    assert_equal conn, result
  end

  def test_create_sentinel_connection_without_password
    conn = mock_conn
    conn.expects(:call).with("AUTH", anything).never
    RR::Connection::TCP.stubs(:new).returns(conn)

    mgr = build_manager
    result = mgr.send(:create_sentinel_connection, { host: "s1", port: 26_379 })

    assert_equal conn, result
  end
  # ============================================================
  # query_replicas_from_sentinel -- nil flags edge case
  # ============================================================

  def test_query_replicas_nil_flags_not_filtered
    replica_info = [
      ["ip", "10.0.0.2", "port", "6380", "flags", nil],
    ]

    conn = mock_conn
    conn.stubs(:call).with("SENTINEL", "REPLICAS", "mymaster").returns(replica_info)
    RR::Connection::TCP.stubs(:new).returns(conn)

    mgr = build_manager
    replicas = mgr.discover_replicas

    # nil flags means no s_down/o_down/disconnected, so not filtered
    assert_equal 1, replicas.length
  end
end

# -----------------------------------------------------------------
# SentinelClient tests
# -----------------------------------------------------------------
class SentinelClientBranchTest < Minitest::Test
  # Helper: create a SentinelClient with mocked internals
  def build_client(role: :master, password: nil, db: 0, ssl: false,
                   reconnect_attempts: 3)
    client = RR::SentinelClient.allocate
    client.instance_variable_set(:@service_name, "mymaster")
    client.instance_variable_set(:@role, role)
    client.instance_variable_set(:@password, password)
    client.instance_variable_set(:@db, db)
    client.instance_variable_set(:@timeout, 5.0)
    client.instance_variable_set(:@ssl, ssl)
    client.instance_variable_set(:@ssl_params, {})
    client.instance_variable_set(:@reconnect_attempts, reconnect_attempts)
    client.instance_variable_set(:@connection, nil)
    client.instance_variable_set(:@current_address, nil)
    client.instance_variable_set(:@mutex, Mutex.new)

    manager = mock("manager")
    manager.stubs(:reset)
    client.instance_variable_set(:@sentinel_manager, manager)

    client
  end

  def mock_conn
    conn = mock("conn")
    conn.stubs(:close)
    conn
  end

  # ============================================================
  # validate_role! and normalize_role
  # ============================================================

  def test_validate_role_master
    client = RR::SentinelClient.allocate
    client.send(:validate_role!, :master)
  end

  def test_validate_role_replica
    client = RR::SentinelClient.allocate
    client.send(:validate_role!, :replica)
  end

  def test_validate_role_slave
    client = RR::SentinelClient.allocate
    client.send(:validate_role!, :slave)
  end

  def test_validate_role_string
    client = RR::SentinelClient.allocate
    client.send(:validate_role!, "master")
  end

  def test_validate_role_invalid
    client = RR::SentinelClient.allocate
    error = assert_raises(ArgumentError) { client.send(:validate_role!, :unknown) }
    assert_includes error.message, "Invalid role"
    assert_includes error.message, ":unknown"
  end

  def test_normalize_role_master
    client = RR::SentinelClient.allocate

    assert_equal :master, client.send(:normalize_role, :master)
  end

  def test_normalize_role_replica
    client = RR::SentinelClient.allocate

    assert_equal :replica, client.send(:normalize_role, :replica)
  end

  def test_normalize_role_slave_to_replica
    client = RR::SentinelClient.allocate

    assert_equal :replica, client.send(:normalize_role, :slave)
  end

  def test_normalize_role_string_master
    client = RR::SentinelClient.allocate

    assert_equal :master, client.send(:normalize_role, "master")
  end

  def test_normalize_role_string_slave_to_replica
    client = RR::SentinelClient.allocate

    assert_equal :replica, client.send(:normalize_role, "slave")
  end
  # ============================================================
  # master? and replica?
  # ============================================================

  def test_master_predicate_true
    client = build_client(role: :master)

    assert_predicate client, :master?
    refute_predicate client, :replica?
  end

  def test_replica_predicate_true
    client = build_client(role: :replica)

    assert_predicate client, :replica?
    refute_predicate client, :master?
  end
  # ============================================================
  # connected?
  # ============================================================

  def test_connected_when_no_connection
    client = build_client

    refute_predicate client, :connected?
  end

  def test_connected_when_connection_exists_and_connected
    client = build_client
    conn = mock_conn
    conn.stubs(:connected?).returns(true)
    client.instance_variable_set(:@connection, conn)

    assert_predicate client, :connected?
  end

  def test_connected_when_connection_exists_but_disconnected
    client = build_client
    conn = mock_conn
    conn.stubs(:connected?).returns(false)
    client.instance_variable_set(:@connection, conn)

    refute_predicate client, :connected?
  end
  # ============================================================
  # close / disconnect / quit
  # ============================================================

  def test_close_with_connection
    client = build_client
    conn = mock_conn
    conn.expects(:close)
    client.instance_variable_set(:@connection, conn)

    client.close

    assert_nil client.instance_variable_get(:@connection)
    assert_nil client.current_address
  end

  def test_close_without_connection
    client = build_client
    # Should not raise
    client.close
  end

  def test_disconnect_alias
    client = build_client

    assert_respond_to client, :disconnect
  end

  def test_quit_alias
    client = build_client

    assert_respond_to client, :quit
  end
  # ============================================================
  # reconnect
  # ============================================================

  def test_reconnect_closes_and_resets
    client = build_client
    conn = mock_conn
    conn.expects(:close)
    client.instance_variable_set(:@connection, conn)
    client.instance_variable_set(:@current_address, { host: "x", port: 1 })

    manager = client.sentinel_manager
    manager.expects(:reset)

    client.reconnect

    assert_nil client.instance_variable_get(:@connection)
    assert_nil client.current_address
  end
end

class SentinelClientBranchTestPart2 < Minitest::Test
  # Helper: create a SentinelClient with mocked internals
  def build_client(role: :master, password: nil, db: 0, ssl: false,
                   reconnect_attempts: 3)
    client = RR::SentinelClient.allocate
    client.instance_variable_set(:@service_name, "mymaster")
    client.instance_variable_set(:@role, role)
    client.instance_variable_set(:@password, password)
    client.instance_variable_set(:@db, db)
    client.instance_variable_set(:@timeout, 5.0)
    client.instance_variable_set(:@ssl, ssl)
    client.instance_variable_set(:@ssl_params, {})
    client.instance_variable_set(:@reconnect_attempts, reconnect_attempts)
    client.instance_variable_set(:@connection, nil)
    client.instance_variable_set(:@current_address, nil)
    client.instance_variable_set(:@mutex, Mutex.new)

    manager = mock("manager")
    manager.stubs(:reset)
    client.instance_variable_set(:@sentinel_manager, manager)

    client
  end

  def mock_conn
    conn = mock("conn")
    conn.stubs(:close)
    conn
  end

  # ============================================================
  # validate_role! and normalize_role
  # ============================================================

  # ============================================================
  # discover_address (master vs replica branch)
  # ============================================================

  def test_discover_address_master_role
    client = build_client(role: :master)
    manager = client.sentinel_manager
    manager.expects(:discover_master).returns({ host: "master", port: 6379 })

    address = client.send(:discover_address)

    assert_equal "master", address[:host]
  end

  def test_discover_address_replica_role
    client = build_client(role: :replica)
    manager = client.sentinel_manager
    manager.expects(:random_replica).returns({ host: "replica", port: 6380 })

    address = client.send(:discover_address)

    assert_equal "replica", address[:host]
  end

  def test_discover_address_replica_falls_back_to_master
    client = build_client(role: :replica)
    manager = client.sentinel_manager
    manager.expects(:random_replica).raises(RR::ReplicaNotFoundError, "no replicas")
    manager.expects(:discover_master).returns({ host: "master", port: 6379 })

    address = client.send(:discover_address)

    assert_equal "master", address[:host]
  end
  # ============================================================
  # create_connection (TCP vs SSL branch)
  # ============================================================

  def test_create_connection_tcp
    client = build_client(ssl: false)
    conn = mock_conn
    RR::Connection::TCP.expects(:new).with(
      host: "master",
      port: 6379,
      timeout: 5.0
    ).returns(conn)

    result = client.send(:create_connection, { host: "master", port: 6379 })

    assert_equal conn, result
  end

  def test_create_connection_ssl
    client = build_client(ssl: true)
    conn = mock_conn
    RR::Connection::SSL.expects(:new).with(
      host: "master",
      port: 6379,
      timeout: 5.0,
      ssl_params: {}
    ).returns(conn)

    result = client.send(:create_connection, { host: "master", port: 6379 })

    assert_equal conn, result
  end
  # ============================================================
  # verify_role!
  # ============================================================

  def test_verify_role_master_correct
    client = build_client(role: :master)
    conn = mock_conn
    conn.expects(:call).with("ROLE").returns(["master", 0, []])
    client.instance_variable_set(:@connection, conn)

    # Should not raise
    client.send(:verify_role!)
  end

  def test_verify_role_master_incorrect
    client = build_client(role: :master)
    conn = mock_conn
    conn.expects(:call).with("ROLE").returns(["slave", "master", 6379, "connected", 100])
    client.instance_variable_set(:@connection, conn)

    error = assert_raises(RR::FailoverError) { client.send(:verify_role!) }
    assert_includes error.message, "master"
    assert_includes error.message, "slave"
  end

  def test_verify_role_replica_correct
    client = build_client(role: :replica)
    conn = mock_conn
    conn.expects(:call).with("ROLE").returns(["slave", "master", 6379, "connected", 100])
    client.instance_variable_set(:@connection, conn)

    # Should not raise
    client.send(:verify_role!)
  end

  def test_verify_role_replica_incorrect
    client = build_client(role: :replica)
    conn = mock_conn
    conn.expects(:call).with("ROLE").returns(["master", 0, []])
    client.instance_variable_set(:@connection, conn)

    error = assert_raises(RR::FailoverError) { client.send(:verify_role!) }
    assert_includes error.message, "replica"
    assert_includes error.message, "master"
  end
  # ============================================================
  # authenticate and select_db
  # ============================================================

  def test_authenticate
    client = build_client(password: "secret")
    conn = mock_conn
    conn.expects(:call).with("AUTH", "secret").returns("OK")
    client.instance_variable_set(:@connection, conn)

    client.send(:authenticate)
  end

  def test_select_db
    client = build_client(db: 5)
    conn = mock_conn
    conn.expects(:call).with("SELECT", "5").returns("OK")
    client.instance_variable_set(:@connection, conn)

    client.send(:select_db)
  end
end

class SentinelClientBranchTestPart3 < Minitest::Test
  # Helper: create a SentinelClient with mocked internals
  def build_client(role: :master, password: nil, db: 0, ssl: false,
                   reconnect_attempts: 3)
    client = RR::SentinelClient.allocate
    client.instance_variable_set(:@service_name, "mymaster")
    client.instance_variable_set(:@role, role)
    client.instance_variable_set(:@password, password)
    client.instance_variable_set(:@db, db)
    client.instance_variable_set(:@timeout, 5.0)
    client.instance_variable_set(:@ssl, ssl)
    client.instance_variable_set(:@ssl_params, {})
    client.instance_variable_set(:@reconnect_attempts, reconnect_attempts)
    client.instance_variable_set(:@connection, nil)
    client.instance_variable_set(:@current_address, nil)
    client.instance_variable_set(:@mutex, Mutex.new)

    manager = mock("manager")
    manager.stubs(:reset)
    client.instance_variable_set(:@sentinel_manager, manager)

    client
  end

  def mock_conn
    conn = mock("conn")
    conn.stubs(:close)
    conn
  end

  # ============================================================
  # validate_role! and normalize_role
  # ============================================================

  # ============================================================
  # ensure_connected (branches)
  # ============================================================

  def test_ensure_connected_when_already_connected
    client = build_client
    conn = mock_conn
    conn.stubs(:connected?).returns(true)
    client.instance_variable_set(:@connection, conn)

    # Should not attempt to discover or create new connection
    client.sentinel_manager.expects(:discover_master).never
    client.send(:ensure_connected)
  end

  def test_ensure_connected_when_not_connected_creates_connection
    client = build_client(role: :master, password: "pass", db: 2)
    manager = client.sentinel_manager
    manager.expects(:discover_master).returns({ host: "master", port: 6379 })

    conn = mock_conn
    conn.stubs(:connected?).returns(false, true) # first check => not connected, after setup => connected
    conn.expects(:call).with("ROLE").returns(["master", 0, []])
    conn.expects(:call).with("AUTH", "pass").returns("OK")
    conn.expects(:call).with("SELECT", "2").returns("OK")
    RR::Connection::TCP.expects(:new).returns(conn)

    client.send(:ensure_connected)

    assert_equal({ host: "master", port: 6379 }, client.current_address)
  end

  def test_ensure_connected_skips_auth_when_no_password
    client = build_client(role: :master, password: nil, db: 0)
    manager = client.sentinel_manager
    manager.expects(:discover_master).returns({ host: "master", port: 6379 })

    conn = mock_conn
    conn.stubs(:connected?).returns(false, true)
    conn.expects(:call).with("ROLE").returns(["master", 0, []])
    conn.expects(:call).with("AUTH", anything).never
    conn.expects(:call).with("SELECT", anything).never
    RR::Connection::TCP.expects(:new).returns(conn)

    client.send(:ensure_connected)
  end

  def test_ensure_connected_skips_select_when_db_zero
    client = build_client(role: :master, password: nil, db: 0)
    manager = client.sentinel_manager
    manager.expects(:discover_master).returns({ host: "master", port: 6379 })

    conn = mock_conn
    conn.stubs(:connected?).returns(false, true)
    conn.expects(:call).with("ROLE").returns(["master", 0, []])
    conn.expects(:call).with("SELECT", anything).never
    RR::Connection::TCP.expects(:new).returns(conn)

    client.send(:ensure_connected)
  end
  # ============================================================
  # readonly_error?
  # ============================================================

  def test_readonly_error_with_readonly
    client = build_client
    err = RR::CommandError.new("READONLY some message")

    assert client.send(:readonly_error?, err)
  end

  def test_readonly_error_with_cant_write
    client = build_client
    err = RR::CommandError.new("You can't write against a read only replica")

    assert client.send(:readonly_error?, err)
  end

  def test_readonly_error_other_message
    client = build_client
    err = RR::CommandError.new("ERR wrong number of arguments")

    refute client.send(:readonly_error?, err)
  end
  # ============================================================
  # handle_failover
  # ============================================================

  def test_handle_failover
    client = build_client
    conn = mock_conn
    conn.expects(:close)
    client.instance_variable_set(:@connection, conn)
    client.instance_variable_set(:@current_address, { host: "x", port: 1 })

    manager = client.sentinel_manager
    manager.expects(:reset)

    client.send(:handle_failover)

    assert_nil client.instance_variable_get(:@connection)
    assert_nil client.current_address
  end

  def test_handle_failover_when_no_connection
    client = build_client
    manager = client.sentinel_manager
    manager.expects(:reset)

    # Should not raise
    client.send(:handle_failover)
  end
  # ============================================================
  # call -- thread safety (connection nil race condition)
  # ============================================================

  def test_call_raises_connection_error_when_connection_becomes_nil
    # Simulates a race condition where another thread nils @connection
    # between ensure_connected and the actual call. Should raise
    # ConnectionError (retriable) rather than NoMethodError.
    client = build_client(reconnect_attempts: 0)
    client.stubs(:ensure_connected) # stub to no-op; @connection stays nil

    assert_raises(RR::ConnectionError) { client.call("PING") }
  end
  # ============================================================
  # call -- success path
  # ============================================================

  def test_call_success
    client = build_client
    conn = mock_conn
    conn.stubs(:connected?).returns(true)
    conn.expects(:call).with("GET", "key").returns("value")
    client.instance_variable_set(:@connection, conn)

    result = client.call("GET", "key")

    assert_equal "value", result
  end
end

class SentinelClientBranchTestPart4 < Minitest::Test
  # Helper: create a SentinelClient with mocked internals
  def build_client(role: :master, password: nil, db: 0, ssl: false,
                   reconnect_attempts: 3)
    client = RR::SentinelClient.allocate
    client.instance_variable_set(:@service_name, "mymaster")
    client.instance_variable_set(:@role, role)
    client.instance_variable_set(:@password, password)
    client.instance_variable_set(:@db, db)
    client.instance_variable_set(:@timeout, 5.0)
    client.instance_variable_set(:@ssl, ssl)
    client.instance_variable_set(:@ssl_params, {})
    client.instance_variable_set(:@reconnect_attempts, reconnect_attempts)
    client.instance_variable_set(:@connection, nil)
    client.instance_variable_set(:@current_address, nil)
    client.instance_variable_set(:@mutex, Mutex.new)

    manager = mock("manager")
    manager.stubs(:reset)
    client.instance_variable_set(:@sentinel_manager, manager)

    client
  end

  def mock_conn
    conn = mock("conn")
    conn.stubs(:close)
    conn
  end

  # ============================================================
  # validate_role! and normalize_role
  # ============================================================

  # ============================================================
  # call -- CommandError handling
  # ============================================================

  def test_call_raises_non_readonly_command_error
    client = build_client
    conn = mock_conn
    conn.stubs(:connected?).returns(true)
    error = RR::CommandError.new("ERR wrong number of arguments")
    conn.expects(:call).with("SET", "key", "val").returns(error)
    client.instance_variable_set(:@connection, conn)

    assert_raises(RR::CommandError) { client.call("SET", "key", "val") }
  end

  def test_call_handles_readonly_error_and_retries
    client = build_client(role: :master, reconnect_attempts: 1)
    client.stubs(:sleep)
    client.stubs(:reconnect)
    client.stubs(:handle_failover)

    readonly_err = RR::CommandError.new("READONLY You can't write against a read only replica")

    conn = mock_conn
    conn.stubs(:connected?).returns(true)
    conn.stubs(:close)
    # Return readonly error on every SET call
    conn.stubs(:call).with("SET", "k", "v").returns(readonly_err)
    client.instance_variable_set(:@connection, conn)

    # handle_failover -> raise ReadOnlyError -> caught by rescue ->
    # retry with reconnect -> call again -> readonly again ->
    # exhaust retries -> raise ReadOnlyError
    assert_raises(RR::ReadOnlyError) { client.call("SET", "k", "v") }
  end
  # ============================================================
  # call -- retry with exponential backoff
  # ============================================================

  def test_call_retries_on_connection_error
    client = build_client(role: :master, reconnect_attempts: 2)
    client.stubs(:sleep) # skip backoff
    # Stub reconnect to just reset connection reference (skip actual logic)
    client.stubs(:reconnect)
    conn = mock_conn
    conn.stubs(:connected?).returns(true)
    conn.stubs(:close)
    conn.stubs(:call).with("PING").raises(RR::ConnectionError, "connection lost")
      .then.raises(RR::ConnectionError, "connection lost")
      .then.returns("PONG")
    client.instance_variable_set(:@connection, conn)

    # After 2 retries, the 3rd attempt succeeds
    result = client.call("PING")

    assert_equal "PONG", result
  end

  def test_call_exhausts_retries_and_raises
    client = build_client(role: :master, reconnect_attempts: 1)
    client.stubs(:sleep) # skip backoff
    client.stubs(:reconnect)

    conn = mock_conn
    conn.stubs(:connected?).returns(true)
    conn.stubs(:close)
    conn.stubs(:call).with("PING").raises(RR::ConnectionError, "connection lost")
    client.instance_variable_set(:@connection, conn)

    assert_raises(RR::ConnectionError) { client.call("PING") }
  end

  def test_call_retries_on_failover_error
    client = build_client(role: :master, reconnect_attempts: 1)
    client.stubs(:sleep) # skip backoff
    client.stubs(:reconnect)

    conn = mock_conn
    conn.stubs(:connected?).returns(true)
    conn.stubs(:close)
    conn.stubs(:call).with("PING").raises(RR::FailoverError, "failover in progress")
    client.instance_variable_set(:@connection, conn)

    assert_raises(RR::FailoverError) { client.call("PING") }
  end
  # ============================================================
  # call -- backoff only after first retry
  # ============================================================

  def test_call_no_sleep_on_first_retry
    client = build_client(role: :master, reconnect_attempts: 2)
    client.stubs(:reconnect)

    conn = mock_conn
    conn.stubs(:connected?).returns(true)
    conn.stubs(:close)
    conn.stubs(:call).with("PING")
      .raises(RR::ConnectionError, "fail")
      .then.returns("OK")
    client.instance_variable_set(:@connection, conn)

    # First retry (attempt=1): no sleep because attempts > 1 is false
    client.expects(:sleep).never

    result = client.call("PING")

    assert_equal "OK", result
  end

  def test_call_sleeps_on_second_retry
    client = build_client(role: :master, reconnect_attempts: 3)
    client.stubs(:reconnect)

    conn = mock_conn
    conn.stubs(:connected?).returns(true)
    conn.stubs(:close)
    conn.stubs(:call).with("PING")
      .raises(RR::ConnectionError, "fail")
      .then.raises(RR::ConnectionError, "fail")
      .then.returns("OK")
    client.instance_variable_set(:@connection, conn)

    # Sleep should be called for attempt 2 (0.2s)
    client.expects(:sleep).with(0.2).once

    result = client.call("PING")

    assert_equal "OK", result
  end
  # ============================================================
  # ping
  # ============================================================

  def test_ping
    client = build_client
    conn = mock_conn
    conn.stubs(:connected?).returns(true)
    conn.expects(:call).with("PING").returns("PONG")
    client.instance_variable_set(:@connection, conn)

    assert_equal "PONG", client.ping
  end
end

class SentinelClientBranchTestPart5 < Minitest::Test
  # Helper: create a SentinelClient with mocked internals
  def build_client(role: :master, password: nil, db: 0, ssl: false,
                   reconnect_attempts: 3)
    client = RR::SentinelClient.allocate
    client.instance_variable_set(:@service_name, "mymaster")
    client.instance_variable_set(:@role, role)
    client.instance_variable_set(:@password, password)
    client.instance_variable_set(:@db, db)
    client.instance_variable_set(:@timeout, 5.0)
    client.instance_variable_set(:@ssl, ssl)
    client.instance_variable_set(:@ssl_params, {})
    client.instance_variable_set(:@reconnect_attempts, reconnect_attempts)
    client.instance_variable_set(:@connection, nil)
    client.instance_variable_set(:@current_address, nil)
    client.instance_variable_set(:@mutex, Mutex.new)

    manager = mock("manager")
    manager.stubs(:reset)
    client.instance_variable_set(:@sentinel_manager, manager)

    client
  end

  def mock_conn
    conn = mock("conn")
    conn.stubs(:close)
    conn
  end

  # ============================================================
  # validate_role! and normalize_role
  # ============================================================

  # ============================================================
  # pipelined
  # ============================================================

  def test_pipelined
    client = build_client
    conn = mock_conn
    conn.stubs(:connected?).returns(true)
    client.instance_variable_set(:@connection, conn)

    pipeline_mock = mock("pipeline")
    pipeline_mock.expects(:execute).returns(%w[OK value])
    RR::Pipeline.expects(:new).with(conn).returns(pipeline_mock)

    results = client.pipelined do |_pipe|
      # Intentionally empty; pipeline is mocked
    end

    assert_equal %w[OK value], results
  end

  def test_pipelined_raises_on_command_error
    client = build_client
    conn = mock_conn
    conn.stubs(:connected?).returns(true)
    client.instance_variable_set(:@connection, conn)

    error = RR::CommandError.new("ERR")
    pipeline_mock = mock("pipeline")
    pipeline_mock.expects(:execute).returns(["OK", error])
    RR::Pipeline.expects(:new).with(conn).returns(pipeline_mock)

    assert_raises(RR::CommandError) do
      client.pipelined do |_pipe|
        # Intentionally empty; pipeline is mocked
      end
    end
  end
  # ============================================================
  # multi (transaction)
  # ============================================================

  def test_multi_success
    client = build_client
    conn = mock_conn
    conn.stubs(:connected?).returns(true)
    client.instance_variable_set(:@connection, conn)

    tx_mock = mock("transaction")
    tx_mock.expects(:execute).returns(["OK", 1])
    RR::Transaction.expects(:new).with(conn).returns(tx_mock)

    results = client.multi do |_tx|
      # Intentionally empty; transaction is mocked
    end

    assert_equal ["OK", 1], results
  end

  def test_multi_returns_nil_when_aborted
    client = build_client
    conn = mock_conn
    conn.stubs(:connected?).returns(true)
    client.instance_variable_set(:@connection, conn)

    tx_mock = mock("transaction")
    tx_mock.expects(:execute).returns(nil)
    RR::Transaction.expects(:new).with(conn).returns(tx_mock)

    result = client.multi do |_tx|
      # Intentionally empty; transaction is mocked
    end

    assert_nil result
  end

  def test_multi_raises_command_error_result
    client = build_client
    conn = mock_conn
    conn.stubs(:connected?).returns(true)
    client.instance_variable_set(:@connection, conn)

    error = RR::CommandError.new("MISCONF")
    tx_mock = mock("transaction")
    tx_mock.expects(:execute).returns(error)
    RR::Transaction.expects(:new).with(conn).returns(tx_mock)

    assert_raises(RR::CommandError) do
      client.multi do |_tx|
        # Intentionally empty; transaction is mocked
      end
    end
  end

  def test_multi_raises_on_command_error_in_results
    client = build_client
    conn = mock_conn
    conn.stubs(:connected?).returns(true)
    client.instance_variable_set(:@connection, conn)

    error = RR::CommandError.new("ERR wrong type")
    tx_mock = mock("transaction")
    tx_mock.expects(:execute).returns(["OK", error])
    RR::Transaction.expects(:new).with(conn).returns(tx_mock)

    assert_raises(RR::CommandError) do
      client.multi do |_tx|
        # Intentionally empty; transaction is mocked
      end
    end
  end
  # ============================================================
  # watch
  # ============================================================

  def test_watch_without_block
    client = build_client
    conn = mock_conn
    conn.stubs(:connected?).returns(true)
    conn.expects(:call).with("WATCH", "key1", "key2").returns("OK")
    client.instance_variable_set(:@connection, conn)

    result = client.watch("key1", "key2")

    assert_equal "OK", result
  end

  def test_watch_with_block
    client = build_client
    conn = mock_conn
    conn.stubs(:connected?).returns(true)
    conn.expects(:call).with("WATCH", "key1").returns("OK")
    conn.expects(:call).with("UNWATCH").returns("OK")
    client.instance_variable_set(:@connection, conn)

    result = client.watch("key1") { "block_result" }

    assert_equal "block_result", result
  end

  def test_watch_with_block_ensures_unwatch
    client = build_client
    conn = mock_conn
    conn.stubs(:connected?).returns(true)
    conn.expects(:call).with("WATCH", "key1").returns("OK")
    conn.expects(:call).with("UNWATCH").returns("OK")
    client.instance_variable_set(:@connection, conn)

    assert_raises(RuntimeError) do
      client.watch("key1") { raise "boom" }
    end
  end
end

class SentinelClientBranchTestPart6 < Minitest::Test
  # Helper: create a SentinelClient with mocked internals
  def build_client(role: :master, password: nil, db: 0, ssl: false,
                   reconnect_attempts: 3)
    client = RR::SentinelClient.allocate
    client.instance_variable_set(:@service_name, "mymaster")
    client.instance_variable_set(:@role, role)
    client.instance_variable_set(:@password, password)
    client.instance_variable_set(:@db, db)
    client.instance_variable_set(:@timeout, 5.0)
    client.instance_variable_set(:@ssl, ssl)
    client.instance_variable_set(:@ssl_params, {})
    client.instance_variable_set(:@reconnect_attempts, reconnect_attempts)
    client.instance_variable_set(:@connection, nil)
    client.instance_variable_set(:@current_address, nil)
    client.instance_variable_set(:@mutex, Mutex.new)

    manager = mock("manager")
    manager.stubs(:reset)
    client.instance_variable_set(:@sentinel_manager, manager)

    client
  end

  def mock_conn
    conn = mock("conn")
    conn.stubs(:close)
    conn
  end

  # ============================================================
  # validate_role! and normalize_role
  # ============================================================

  # ============================================================
  # unwatch
  # ============================================================

  def test_unwatch
    client = build_client
    conn = mock_conn
    conn.stubs(:connected?).returns(true)
    conn.expects(:call).with("UNWATCH").returns("OK")
    client.instance_variable_set(:@connection, conn)

    result = client.unwatch

    assert_equal "OK", result
  end
  # ============================================================
  # Full initialization (with real constructor)
  # ============================================================

  def test_initialize_with_real_constructor
    client = RR::SentinelClient.new(
      sentinels: [{ host: "s1", port: 26_379 }], service_name: "mymaster",
      role: :master, password: "pass", sentinel_password: "spass",
      db: 3, timeout: 2.0, ssl: false, ssl_params: {},
      reconnect_attempts: 5, min_other_sentinels: 1
    )

    assert_equal "mymaster", client.service_name
    assert_equal :master, client.role
    assert_in_delta 2.0, client.timeout
    assert_predicate client, :master?
    refute_predicate client, :replica?
    refute_predicate client, :connected?
    assert_nil client.current_address
    assert_instance_of RR::SentinelManager, client.sentinel_manager
  end

  def test_initialize_slave_role_normalized
    client = RR::SentinelClient.new(
      sentinels: [{ host: "s1", port: 26_379 }],
      service_name: "mymaster",
      role: :slave
    )

    assert_equal :replica, client.role
    assert_predicate client, :replica?
  end

  def test_initialize_invalid_role_raises
    assert_raises(ArgumentError) do
      RR::SentinelClient.new(
        sentinels: [{ host: "s1", port: 26_379 }],
        service_name: "mymaster",
        role: :invalid
      )
    end
  end
  # ============================================================
  # sentinel_manager attribute
  # ============================================================

  def test_sentinel_manager_accessible
    client = build_client

    refute_nil client.sentinel_manager
  end
  # ============================================================
  # call -- normal (non-error) result
  # ============================================================

  def test_call_returns_normal_result
    client = build_client
    conn = mock_conn
    conn.stubs(:connected?).returns(true)
    conn.expects(:call).with("INFO").returns("redis_version:7.0.0")
    client.instance_variable_set(:@connection, conn)

    result = client.call("INFO")

    assert_equal "redis_version:7.0.0", result
  end

  def test_call_returns_nil_result
    client = build_client
    conn = mock_conn
    conn.stubs(:connected?).returns(true)
    conn.expects(:call).with("GET", "missing").returns(nil)
    client.instance_variable_set(:@connection, conn)

    result = client.call("GET", "missing")

    assert_nil result
  end

  def test_call_returns_integer_result
    client = build_client
    conn = mock_conn
    conn.stubs(:connected?).returns(true)
    conn.expects(:call).with("INCR", "counter").returns(42)
    client.instance_variable_set(:@connection, conn)

    result = client.call("INCR", "counter")

    assert_equal 42, result
  end
  # ============================================================
  # call_1arg / call_2args / call_3args fast-path methods
  # ============================================================

  def test_call_1arg_delegates_to_connection
    client = build_client
    conn = mock_conn
    conn.stubs(:connected?).returns(true)
    conn.expects(:call_1arg).with("GET", "key1").returns("value1")
    client.instance_variable_set(:@connection, conn)

    result = client.call_1arg("GET", "key1")

    assert_equal "value1", result
  end

  def test_call_2args_delegates_to_connection
    client = build_client
    conn = mock_conn
    conn.stubs(:connected?).returns(true)
    conn.expects(:call_2args).with("SET", "key1", "value1").returns("OK")
    client.instance_variable_set(:@connection, conn)

    result = client.call_2args("SET", "key1", "value1")

    assert_equal "OK", result
  end

  def test_call_3args_delegates_to_connection
    client = build_client
    conn = mock_conn
    conn.stubs(:connected?).returns(true)
    conn.expects(:call_3args).with("HSET", "hash", "field", "value").returns(1)
    client.instance_variable_set(:@connection, conn)

    result = client.call_3args("HSET", "hash", "field", "value")

    assert_equal 1, result
  end
end
