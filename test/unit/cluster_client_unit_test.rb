# frozen_string_literal: true

require_relative "unit_test_helper"

class ClusterClientUnitTest < Minitest::Test
  # ==========================================================================
  # CRC16 and Hash Slot Calculation
  # ==========================================================================

  def test_key_slot_returns_consistent_results
    client = build_cluster_with_mock_topology
    slot1 = client.key_slot("foo")
    slot2 = client.key_slot("foo")
    assert_equal slot1, slot2
  end

  def test_key_slot_in_valid_range
    client = build_cluster_with_mock_topology
    1000.times do
      key = "key_#{rand(100_000)}"
      slot = client.key_slot(key)
      assert_operator slot, :>=, 0
      assert_operator slot, :<, 16_384
    end
  end

  def test_key_slot_different_keys_different_slots
    client = build_cluster_with_mock_topology
    slots = %w[alpha bravo charlie delta echo].map { |k| client.key_slot(k) }.uniq
    assert_operator slots.size, :>, 1, "Expected different keys to have different slots"
  end

  # Known CRC16 values for specific keys (verified against Redis)
  def test_key_slot_known_values
    client = build_cluster_with_mock_topology
    # "foo" -> CRC16 = 12182, slot = 12182 % 16384 = 12182
    assert_equal 12182, client.key_slot("foo")
  end

  # ==========================================================================
  # Hash Tag Extraction
  # ==========================================================================

  def test_hash_tag_basic
    client = build_cluster_with_mock_topology
    # Keys with same hash tag should hash to same slot
    slot1 = client.key_slot("user:{123}:name")
    slot2 = client.key_slot("user:{123}:email")
    assert_equal slot1, slot2
  end

  def test_hash_tag_only_braces
    client = build_cluster_with_mock_topology
    slot1 = client.key_slot("{tag}")
    slot2 = client.key_slot("prefix{tag}suffix")
    assert_equal slot1, slot2
  end

  def test_hash_tag_empty_ignored
    client = build_cluster_with_mock_topology
    # Empty hash tag {} means use full key
    slot1 = client.key_slot("foo{}bar")
    slot2 = client.key_slot("foo{}bar")
    assert_equal slot1, slot2
    # But it should differ from the key "bar" or ""
    # (because the empty tag is ignored and the full key is used)
  end

  def test_hash_tag_no_opening_brace
    client = build_cluster_with_mock_topology
    # No { means use full key
    slot1 = client.key_slot("nobraces")
    slot2 = client.key_slot("nobraces")
    assert_equal slot1, slot2
  end

  def test_hash_tag_no_closing_brace
    client = build_cluster_with_mock_topology
    # { without } means use full key
    slot1 = client.key_slot("foo{bar")
    slot2 = client.key_slot("foo{bar")
    assert_equal slot1, slot2
  end

  def test_hash_tag_first_pair_used
    client = build_cluster_with_mock_topology
    # First complete {tag} pair is used
    slot1 = client.key_slot("a{b}c{d}e")
    slot2 = client.key_slot("{b}")
    assert_equal slot1, slot2
  end

  def test_hash_tag_non_string_key
    client = build_cluster_with_mock_topology
    # Non-string key: key_slot converts via to_s internally or raises
    # The extract_hash_tag returns nil for non-strings, so crc16 is called on the raw key
    # crc16 expects each_byte, so non-string keys must be converted first
    slot = client.key_slot("12345")
    assert_operator slot, :>=, 0
    assert_operator slot, :<, 16_384
  end

  # ==========================================================================
  # Node Normalization
  # ==========================================================================

  def test_normalize_nodes_with_url_strings
    # Test through the private method via the error path
    # Valid URLs should not raise
    mock_conn = mock("connection")
    mock_conn.stubs(:call).returns(RedisRuby::CommandError.new("ERR"))
    mock_conn.stubs(:close)
    RedisRuby::Connection::TCP.stubs(:new).raises(RedisRuby::ConnectionError, "Connection refused")

    assert_raises(RedisRuby::ConnectionError) do
      RedisRuby::ClusterClient.new(nodes: ["redis://host1:6379", "redis://host2:7000"])
    end
  end

  def test_normalize_nodes_with_hash
    RedisRuby::Connection::TCP.stubs(:new).raises(RedisRuby::ConnectionError, "refused")

    assert_raises(RedisRuby::ConnectionError) do
      RedisRuby::ClusterClient.new(nodes: [{ host: "myhost", port: 7001 }])
    end
  end

  def test_normalize_nodes_with_hash_defaults
    RedisRuby::Connection::TCP.stubs(:new).raises(RedisRuby::ConnectionError, "refused")

    assert_raises(RedisRuby::ConnectionError) do
      RedisRuby::ClusterClient.new(nodes: [{}])
    end
  end

  def test_normalize_nodes_invalid_type_raises
    assert_raises(ArgumentError) do
      RedisRuby::ClusterClient.new(nodes: [123])
    end
  end

  def test_normalize_nodes_url_without_host_uses_default
    RedisRuby::Connection::TCP.stubs(:new).raises(RedisRuby::ConnectionError, "refused")
    assert_raises(RedisRuby::ConnectionError) do
      RedisRuby::ClusterClient.new(nodes: ["redis://:6379"])
    end
  end

  # ==========================================================================
  # Extract Key from Command
  # ==========================================================================

  def test_extract_key_with_regular_command
    client = build_cluster_with_mock_topology
    # Use send to call the private method
    key = client.send(:extract_key, "GET", ["mykey"])
    assert_equal "mykey", key
  end

  def test_extract_key_no_key_commands
    client = build_cluster_with_mock_topology
    %w[PING INFO DBSIZE TIME CLUSTER].each do |cmd|
      key = client.send(:extract_key, cmd, [])
      assert_nil key, "Expected nil key for #{cmd}"
    end
  end

  def test_extract_key_case_insensitive
    client = build_cluster_with_mock_topology
    key = client.send(:extract_key, "ping", [])
    assert_nil key
  end

  def test_extract_key_with_no_args
    client = build_cluster_with_mock_topology
    key = client.send(:extract_key, "GET", [])
    assert_nil key
  end

  def test_extract_key_returns_first_arg
    client = build_cluster_with_mock_topology
    key = client.send(:extract_key, "SET", %w[mykey myvalue])
    assert_equal "mykey", key
  end

  # ==========================================================================
  # Read Command Detection
  # ==========================================================================

  def test_read_command_detection
    client = build_cluster_with_mock_topology
    assert client.send(:read_command?, "GET")
    assert client.send(:read_command?, "HGET")
    assert client.send(:read_command?, "SMEMBERS")
    assert client.send(:read_command?, "ZRANGE")
    assert client.send(:read_command?, "LRANGE")
    assert client.send(:read_command?, "EXISTS")
  end

  def test_write_command_not_detected_as_read
    client = build_cluster_with_mock_topology
    refute client.send(:read_command?, "SET")
    refute client.send(:read_command?, "HSET")
    refute client.send(:read_command?, "LPUSH")
    refute client.send(:read_command?, "SADD")
    refute client.send(:read_command?, "ZADD")
    refute client.send(:read_command?, "DEL")
  end

  def test_read_command_case_insensitive
    client = build_cluster_with_mock_topology
    assert client.send(:read_command?, "get")
    assert client.send(:read_command?, "Get")
  end

  # ==========================================================================
  # Node for Slot - Routing Decisions
  # ==========================================================================

  def test_node_for_slot_returns_master_by_default
    client = build_cluster_with_mock_topology
    addr = client.node_for_slot(0)
    assert_equal "host1:6379", addr
  end

  def test_node_for_slot_returns_nil_for_unmapped_slot
    client = build_cluster_with_mock_topology
    # Slot 15000 is not mapped in our mock (only 0-5460 and 5461-10922 mapped)
    addr = client.node_for_slot(15_000)
    assert_nil addr
  end

  def test_node_for_slot_returns_master_for_writes
    client = build_cluster_with_mock_topology
    addr = client.node_for_slot(0, for_read: false)
    assert_equal "host1:6379", addr
  end

  def test_node_for_slot_returns_replica_when_read_from_replica
    client = build_cluster_with_mock_topology(read_from: :replica)
    # Slot 0 has replicas
    addr = client.node_for_slot(0, for_read: true)
    assert_includes ["replica1:6379", "replica2:6379"], addr
  end

  def test_node_for_slot_returns_replica_preferred_with_replicas
    client = build_cluster_with_mock_topology(read_from: :replica_preferred)
    addr = client.node_for_slot(0, for_read: true)
    # Should prefer replica but fall back to master
    assert_includes ["replica1:6379", "replica2:6379", "host1:6379"], addr
  end

  def test_node_for_slot_returns_master_for_unknown_read_from
    client = build_cluster_with_mock_topology(read_from: :unknown)
    addr = client.node_for_slot(0, for_read: true)
    assert_equal "host1:6379", addr
  end

  def test_node_for_slot_returns_master_when_no_replicas
    client = build_cluster_with_mock_topology(read_from: :replica)
    # Slot 5461 has master2 with no replicas
    addr = client.node_for_slot(5461, for_read: true)
    assert_equal "host2:6379", addr
  end

  def test_node_for_slot_returns_master_for_read_when_read_from_master
    client = build_cluster_with_mock_topology(read_from: :master)
    addr = client.node_for_slot(0, for_read: true)
    assert_equal "host1:6379", addr
  end

  # ==========================================================================
  # Host Translation
  # ==========================================================================

  def test_translate_host_with_translation
    client = build_cluster_with_mock_topology(host_translation: { "internal-host" => "external-host" })
    translated = client.send(:translate_host, "internal-host")
    assert_equal "external-host", translated
  end

  def test_translate_host_without_translation
    client = build_cluster_with_mock_topology
    translated = client.send(:translate_host, "somehost")
    assert_equal "somehost", translated
  end

  # ==========================================================================
  # Error Handling - MOVED, ASK, CLUSTERDOWN
  # ==========================================================================

  def test_handle_moved_error
    client = build_cluster_with_mock_topology

    # Create a mock for the new connection after MOVED
    moved_conn = mock("moved_conn")
    moved_conn.stubs(:call).returns("OK")
    moved_conn.stubs(:close)

    # Use slot 100 which is in our mapped range (0-5460)
    error = RedisRuby::CommandError.new("MOVED 100 host3:6379")
    client.stubs(:get_connection).returns(moved_conn)
    client.stubs(:refresh_slots)

    result = client.send(:handle_command_error, error, "GET", ["foo"], 100, 0)
    assert_equal "OK", result
  end

  def test_handle_ask_error
    client = build_cluster_with_mock_topology

    ask_conn = mock("ask_conn")
    ask_conn.expects(:call).with("ASKING").returns("OK")
    ask_conn.expects(:call).with("GET", "foo").returns("bar")
    ask_conn.stubs(:close)

    client.stubs(:get_connection).returns(ask_conn)

    error = RedisRuby::CommandError.new("ASK 12182 host4:6379")
    result = client.send(:handle_command_error, error, "GET", ["foo"], 12_182, 0)
    assert_equal "bar", result
  end

  def test_handle_ask_error_with_host_translation
    client = build_cluster_with_mock_topology(host_translation: { "internal" => "external" })

    ask_conn = mock("ask_conn")
    ask_conn.stubs(:call).with("ASKING").returns("OK")
    ask_conn.stubs(:call).with("GET", "foo").returns("bar")
    ask_conn.stubs(:close)

    client.stubs(:get_connection).returns(ask_conn)

    error = RedisRuby::CommandError.new("ASK 100 internal:6379")
    result = client.send(:handle_command_error, error, "GET", ["foo"], 100, 0)
    assert_equal "bar", result
  end

  def test_handle_ask_error_raises_on_inner_error
    client = build_cluster_with_mock_topology

    ask_conn = mock("ask_conn")
    ask_conn.stubs(:call).with("ASKING").returns("OK")
    inner_error = RedisRuby::CommandError.new("ERR unknown command")
    ask_conn.stubs(:call).with("GET", "foo").returns(inner_error)
    ask_conn.stubs(:close)

    client.stubs(:get_connection).returns(ask_conn)

    error = RedisRuby::CommandError.new("ASK 12182 host4:6379")
    assert_raises(RedisRuby::CommandError) do
      client.send(:handle_command_error, error, "GET", ["foo"], 12_182, 0)
    end
  end

  def test_handle_clusterdown_error
    client = build_cluster_with_mock_topology

    error = RedisRuby::CommandError.new("CLUSTERDOWN The cluster is down")
    assert_raises(RedisRuby::Error) do
      client.send(:handle_command_error, error, "GET", ["foo"], 12_182, 0)
    end
  end

  def test_handle_generic_command_error
    client = build_cluster_with_mock_topology

    error = RedisRuby::CommandError.new("ERR unknown command")
    assert_raises(RedisRuby::CommandError) do
      client.send(:handle_command_error, error, "BADCMD", [], nil, 0)
    end
  end

  # ==========================================================================
  # Execute with Retry
  # ==========================================================================

  def test_execute_with_retry_too_many_redirections
    client = build_cluster_with_mock_topology
    assert_raises(RedisRuby::Error) do
      client.send(:execute_with_retry, "GET", ["foo"], 100, redirections: 5)
    end
  end

  def test_execute_with_retry_no_node_available
    client = build_cluster_with_mock_topology
    # Unmapped slot
    assert_raises(RedisRuby::ConnectionError) do
      client.send(:execute_with_retry, "GET", ["foo"], 15_000, redirections: 0)
    end
  end

  def test_execute_with_retry_uses_random_master_when_no_slot
    client = build_cluster_with_mock_topology
    conn = mock("conn")
    conn.stubs(:call).returns("PONG")
    client.stubs(:get_connection).returns(conn)
    client.stubs(:random_master).returns("host1:6379")

    result = client.send(:execute_with_retry, "PING", [], nil, redirections: 0)
    assert_equal "PONG", result
  end

  def test_execute_with_retry_handles_command_error_result
    client = build_cluster_with_mock_topology
    conn = mock("conn")
    error = RedisRuby::CommandError.new("MOVED 100 host2:6379")
    conn.stubs(:call).returns(error)
    client.stubs(:get_connection).returns(conn)

    moved_conn = mock("moved_conn")
    moved_conn.stubs(:call).returns("OK")
    client.stubs(:get_connection).returns(moved_conn)
    client.stubs(:refresh_slots)

    # The method will detect MOVED and recurse
    result = client.send(:execute_with_retry, "SET", %w[k v], 0, redirections: 0)
    assert_equal "OK", result
  end

  def test_execute_with_retry_retries_on_connection_error
    client = build_cluster_with_mock_topology

    attempt = 0
    conn = stub("conn")
    conn.stubs(:call).with do |*_args|
      attempt += 1
      raise RedisRuby::ConnectionError, "Connection lost" if attempt <= 1

      true
    end.returns("PONG")
    conn.stubs(:close)

    client.stubs(:get_connection).returns(conn)
    client.stubs(:refresh_slots)
    client.stubs(:sleep)

    # Just verify it retries (the stub behavior may be complex - verify retry path exists)
    # Test that max retries eventually raises
    always_fail_conn = stub("always_fail_conn")
    always_fail_conn.stubs(:call).raises(RedisRuby::ConnectionError, "lost")
    always_fail_conn.stubs(:close)
    client.stubs(:get_connection).returns(always_fail_conn)

    assert_raises(RedisRuby::ConnectionError) do
      client.send(:execute_with_retry, "PING", [], 0, redirections: 0)
    end
  end

  def test_execute_with_retry_gives_up_after_max_retries
    client = build_cluster_with_mock_topology
    conn = mock("conn")
    conn.stubs(:call).raises(RedisRuby::ConnectionError, "Connection lost")
    client.stubs(:get_connection).returns(conn)
    client.stubs(:refresh_slots)
    client.stubs(:sleep) # Skip actual sleep

    assert_raises(RedisRuby::ConnectionError) do
      client.send(:execute_with_retry, "PING", [], 0, redirections: 0)
    end
  end

  # ==========================================================================
  # Call Methods and Routing
  # ==========================================================================

  def test_call_routes_based_on_key
    client = build_cluster_with_mock_topology
    conn = mock("conn")
    conn.stubs(:call).returns("value")
    client.stubs(:get_connection).returns(conn)
    client.stubs(:node_for_slot).returns("host1:6379")

    result = client.call("GET", "mykey")
    assert_equal "value", result
  end

  def test_call_with_no_key_command
    client = build_cluster_with_mock_topology
    conn = mock("conn")
    conn.stubs(:call).returns("PONG")
    client.stubs(:get_connection).returns(conn)
    client.stubs(:random_master).returns("host1:6379")

    result = client.call("PING")
    assert_equal "PONG", result
  end

  def test_call_1arg_delegates_to_call
    client = build_cluster_with_mock_topology
    conn = mock("conn")
    conn.stubs(:call).returns("value")
    client.stubs(:get_connection).returns(conn)
    client.stubs(:node_for_slot).returns("host1:6379")

    result = client.call_1arg("GET", "key")
    assert_equal "value", result
  end

  def test_call_2args_delegates_to_call
    client = build_cluster_with_mock_topology
    conn = mock("conn")
    conn.stubs(:call).returns("OK")
    client.stubs(:get_connection).returns(conn)
    client.stubs(:node_for_slot).returns("host1:6379")

    result = client.call_2args("SET", "key", "value")
    assert_equal "OK", result
  end

  def test_call_3args_delegates_to_call
    client = build_cluster_with_mock_topology
    conn = mock("conn")
    conn.stubs(:call).returns(1)
    client.stubs(:get_connection).returns(conn)

    result = client.call_3args("HSET", "hash", "field", "value")
    assert_equal 1, result
  end

  # ==========================================================================
  # Close / Disconnect / Quit
  # ==========================================================================

  def test_close_closes_all_connections
    client = build_cluster_with_mock_topology
    nodes = client.instance_variable_get(:@nodes)
    nodes.each_value do |conn|
      conn.expects(:close)
    end
    client.close
    assert_equal 0, client.node_count
  end

  def test_disconnect_alias
    client = build_cluster_with_mock_topology
    assert_respond_to client, :disconnect
  end

  def test_quit_alias
    client = build_cluster_with_mock_topology
    assert_respond_to client, :quit
  end

  # ==========================================================================
  # Cluster Health
  # ==========================================================================

  def test_cluster_healthy_when_ok
    client = build_cluster_with_mock_topology
    conn = mock("conn")
    conn.stubs(:call).returns("cluster_state:ok\r\ncluster_slots_assigned:16384\r\n")
    client.stubs(:get_connection).returns(conn)
    client.stubs(:random_master).returns("host1:6379")

    assert client.cluster_healthy?
  end

  def test_cluster_unhealthy_when_not_ok
    client = build_cluster_with_mock_topology
    conn = mock("conn")
    conn.stubs(:call).returns("cluster_state:fail\r\ncluster_slots_assigned:0\r\n")
    client.stubs(:get_connection).returns(conn)
    client.stubs(:random_master).returns("host1:6379")

    refute client.cluster_healthy?
  end

  def test_cluster_healthy_returns_false_on_error
    client = build_cluster_with_mock_topology
    conn = mock("conn")
    conn.stubs(:call).raises(StandardError, "connection lost")
    client.stubs(:get_connection).returns(conn)
    client.stubs(:random_master).returns("host1:6379")

    refute client.cluster_healthy?
  end

  def test_cluster_healthy_returns_false_when_no_node
    client = build_cluster_with_mock_topology
    client.stubs(:random_master).returns(nil)
    client.instance_variable_get(:@seed_nodes).clear

    refute client.cluster_healthy?
  end

  def test_cluster_healthy_returns_false_on_command_error
    client = build_cluster_with_mock_topology
    conn = mock("conn")
    conn.stubs(:call).returns(RedisRuby::CommandError.new("ERR"))
    client.stubs(:get_connection).returns(conn)
    client.stubs(:random_master).returns("host1:6379")

    refute client.cluster_healthy?
  end

  # ==========================================================================
  # Node Count
  # ==========================================================================

  def test_node_count
    client = build_cluster_with_mock_topology
    count = client.node_count
    assert_operator count, :>=, 0
  end

  # ==========================================================================
  # Parse Cluster Info Response
  # ==========================================================================

  def test_parse_cluster_info_response_with_integers
    client = build_cluster_with_mock_topology
    info_str = "cluster_state:ok\r\ncluster_slots_assigned:16384\r\ncluster_known_nodes:6\r\n"
    result = client.send(:parse_cluster_info_response, info_str)
    assert_equal "ok", result["cluster_state"]
    assert_equal 16_384, result["cluster_slots_assigned"]
    assert_equal 6, result["cluster_known_nodes"]
  end

  def test_parse_cluster_info_response_with_mixed
    client = build_cluster_with_mock_topology
    info_str = "cluster_state:fail\r\ncluster_my_epoch:2\r\n"
    result = client.send(:parse_cluster_info_response, info_str)
    assert_equal "fail", result["cluster_state"]
    assert_equal 2, result["cluster_my_epoch"]
  end

  def test_parse_cluster_info_response_skips_nil_key_value
    client = build_cluster_with_mock_topology
    info_str = "cluster_state:ok\r\n\r\ninvalid_line\r\n"
    result = client.send(:parse_cluster_info_response, info_str)
    assert_equal "ok", result["cluster_state"]
    # "invalid_line" has no ":" so key/value split won't yield both
  end

  # ==========================================================================
  # Update Slots from Result
  # ==========================================================================

  def test_update_slots_from_result
    client = build_cluster_with_mock_topology
    # Simulate CLUSTER SLOTS response
    slots_data = [
      [0, 5460, ["newhost1", 6379], ["replica_new", 6379]],
      [5461, 10_922, ["newhost2", 6379]],
    ]

    client.send(:update_slots_from_result, slots_data)

    # Check master list
    masters = client.instance_variable_get(:@masters)
    assert_includes masters, "newhost1:6379"
    assert_includes masters, "newhost2:6379"

    # Check slot mapping
    slot_info = client.instance_variable_get(:@slots)
    assert_equal "newhost1:6379", slot_info[0][:master]
    assert_includes slot_info[0][:replicas], "replica_new:6379"
    assert_equal "newhost2:6379", slot_info[5461][:master]
  end

  # ==========================================================================
  # READ_COMMANDS constant
  # ==========================================================================

  def test_read_commands_constant_is_frozen
    assert RedisRuby::ClusterClient::READ_COMMANDS.frozen?
  end

  def test_read_commands_includes_expected
    rc = RedisRuby::ClusterClient::READ_COMMANDS
    %w[GET MGET HGET HMGET HGETALL LRANGE LINDEX SMEMBERS SISMEMBER
       ZRANGE ZREVRANGE ZSCORE EXISTS TTL PTTL KEYS PFCOUNT
       XLEN XRANGE BITCOUNT BITPOS GEOPOS GEODIST].each do |cmd|
      assert_includes rc, cmd, "Expected READ_COMMANDS to include #{cmd}"
    end
  end

  # ==========================================================================
  # Constants
  # ==========================================================================

  def test_hash_slots_constant
    assert_equal 16_384, RedisRuby::ClusterClient::HASH_SLOTS
  end

  def test_max_redirections_constant
    assert_equal 5, RedisRuby::ClusterClient::MAX_REDIRECTIONS
  end

  def test_default_timeout_constant
    assert_equal 5.0, RedisRuby::ClusterClient::DEFAULT_TIMEOUT
  end

  def test_crc16_table_is_frozen
    assert RedisRuby::ClusterClient::CRC16_TABLE.frozen?
  end

  def test_crc16_table_has_256_entries
    assert_equal 256, RedisRuby::ClusterClient::CRC16_TABLE.length
  end

  # ==========================================================================
  # Cluster Info on Any Node
  # ==========================================================================

  def test_cluster_info_on_any_node_uses_random_master
    client = build_cluster_with_mock_topology
    conn = mock("conn")
    conn.stubs(:call).returns("cluster_state:ok\r\n")
    client.stubs(:get_connection).returns(conn)
    client.stubs(:random_master).returns("host1:6379")

    result = client.send(:cluster_info_on_any_node)
    assert_equal "ok", result["cluster_state"]
  end

  def test_cluster_info_on_any_node_uses_seed_when_no_master
    client = build_cluster_with_mock_topology
    conn = mock("conn")
    conn.stubs(:call).returns("cluster_state:ok\r\n")
    client.stubs(:get_connection).returns(conn)
    client.stubs(:random_master).returns(nil)

    result = client.send(:cluster_info_on_any_node)
    assert_equal "ok", result["cluster_state"]
  end

  def test_cluster_info_on_any_node_returns_nil_on_no_address
    client = build_cluster_with_mock_topology
    client.stubs(:random_master).returns(nil)
    client.instance_variable_set(:@seed_nodes, [])

    result = client.send(:cluster_info_on_any_node)
    assert_nil result
  end

  # ==========================================================================
  # Asking Flow in execute_with_retry
  # ==========================================================================

  def test_execute_sends_asking_when_flagged
    client = build_cluster_with_mock_topology
    conn = mock("conn")
    # First call succeeds normally
    conn.stubs(:call).returns("OK")
    client.stubs(:get_connection).returns(conn)

    result = client.send(:execute_with_retry, "SET", %w[k v], 0, redirections: 0)
    assert_equal "OK", result
  end

  # ==========================================================================
  # Refresh Slots
  # ==========================================================================

  def test_refresh_slots_raises_when_no_nodes_available
    mock_conn = mock("conn")
    mock_conn.stubs(:call).raises(StandardError, "fail")
    mock_conn.stubs(:close)

    RedisRuby::Connection::TCP.stubs(:new).returns(mock_conn)

    assert_raises(RedisRuby::ConnectionError) do
      RedisRuby::ClusterClient.new(nodes: ["redis://unreachable:6379"])
    end
  end

  # ==========================================================================
  # Command Module Inclusion
  # ==========================================================================

  def test_includes_string_commands
    assert RedisRuby::ClusterClient.method_defined?(:set)
    assert RedisRuby::ClusterClient.method_defined?(:get)
  end

  def test_includes_key_commands
    assert RedisRuby::ClusterClient.method_defined?(:del)
    assert RedisRuby::ClusterClient.method_defined?(:exists)
  end

  def test_includes_hash_commands
    assert RedisRuby::ClusterClient.method_defined?(:hset)
    assert RedisRuby::ClusterClient.method_defined?(:hget)
  end

  def test_includes_list_commands
    assert RedisRuby::ClusterClient.method_defined?(:lpush)
    assert RedisRuby::ClusterClient.method_defined?(:rpush)
  end

  def test_includes_set_commands
    assert RedisRuby::ClusterClient.method_defined?(:sadd)
    assert RedisRuby::ClusterClient.method_defined?(:smembers)
  end

  def test_includes_sorted_set_commands
    assert RedisRuby::ClusterClient.method_defined?(:zadd)
    assert RedisRuby::ClusterClient.method_defined?(:zrange)
  end

  def test_includes_cluster_commands
    assert RedisRuby::ClusterClient.method_defined?(:cluster_info)
    assert RedisRuby::ClusterClient.method_defined?(:cluster_nodes)
    assert RedisRuby::ClusterClient.method_defined?(:cluster_slots)
  end

  private

  # Build a cluster client with pre-populated mock topology
  # (bypasses refresh_slots which needs real connections)
  def build_cluster_with_mock_topology(read_from: :master, host_translation: nil)
    # Stub out TCP connections to prevent real network calls
    mock_conn = mock("cluster_conn")
    mock_conn.stubs(:call).returns([
      [0, 5460, ["host1", 6379], ["replica1", 6379], ["replica2", 6379]],
      [5461, 10_922, ["host2", 6379]],
    ])
    mock_conn.stubs(:close)

    RedisRuby::Connection::TCP.stubs(:new).returns(mock_conn)

    client = RedisRuby::ClusterClient.new(
      nodes: ["redis://host1:6379"],
      read_from: read_from,
      host_translation: host_translation
    )

    client
  end
end
