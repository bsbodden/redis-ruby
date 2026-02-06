# frozen_string_literal: true

require_relative "../unit_test_helper"

class ClusterCommandsTest < Minitest::Test
  class MockClient
    include RedisRuby::Commands::Cluster
    attr_reader :last_command

    def call(*args)
      @last_command = args
      mock_return(args)
    end

    def call_1arg(cmd, a1)
      @last_command = [cmd, a1]
      mock_return([cmd, a1])
    end

    def call_2args(cmd, a1, a2)
      @last_command = [cmd, a1, a2]
      mock_return([cmd, a1, a2])
    end

    def call_3args(cmd, a1, a2, a3)
      @last_command = [cmd, a1, a2, a3]
      mock_return([cmd, a1, a2, a3])
    end

    private

    def mock_return(args)
      subcmd = args[1] if args[0] == "CLUSTER"
      case subcmd
      when "INFO"
        "cluster_enabled:1\r\ncluster_state:ok\r\ncluster_slots_assigned:16384\r\ncluster_known_nodes:6"
      when "NODES"
        "abc123 127.0.0.1:7000@17000 master - 0 1234 1 connected 0-5460\n" \
          "def456 127.0.0.1:7001@17001 slave abc123 0 1234 1 connected\n"
      when "SLOTS"
        [
          [0, 5460, ["127.0.0.1", 7000, "abc123"], ["127.0.0.1", 7003, "ghi789"]],
          [5461, 10922, ["127.0.0.1", 7001, "def456"]],
        ]
      when "SHARDS" then [{ "slots" => [0, 5460], "nodes" => [] }]
      when "KEYSLOT" then 12539
      when "COUNTKEYSINSLOT" then 3
      when "GETKEYSINSLOT" then %w[key1 key2]
      when "MYID" then "abc123def456"
      when "MYSHARDID" then "shard1"
      when "BUMPEPOCH" then "BUMPED"
      when "COUNT-FAILURE-REPORTS" then 2
      else "OK"
      end
    end
  end

  def setup
    @client = MockClient.new
  end

  # ============================================================
  # cluster_info - parses response into hash
  # ============================================================

  def test_cluster_info
    result = @client.cluster_info
    assert_instance_of Hash, result
    assert_equal 1, result["cluster_enabled"]
    assert_equal "ok", result["cluster_state"]
    assert_equal 16384, result["cluster_slots_assigned"]
    assert_equal 6, result["cluster_known_nodes"]
  end

  def test_cluster_info_parses_numeric_values
    result = @client.cluster_info
    # cluster_enabled should be Integer
    assert_instance_of Integer, result["cluster_enabled"]
    # cluster_state should remain a String (non-numeric)
    assert_instance_of String, result["cluster_state"]
  end

  # Test parse_cluster_info with an empty/nil line
  def test_cluster_info_skips_malformed_lines
    client = ClusterInfoMalformedMock.new
    result = client.cluster_info
    # Should skip lines without ":" and empty values
    assert_instance_of Hash, result
    assert_equal "ok", result["cluster_state"]
  end

  class ClusterInfoMalformedMock
    include RedisRuby::Commands::Cluster
    def call(*) = "OK"

    def call_1arg(cmd, subcmd)
      if subcmd == "INFO"
        "no_colon_line\r\ncluster_state:ok\r\n\r\n"
      else
        "OK"
      end
    end

    def call_2args(*) = "OK"
    def call_3args(*) = "OK"
  end

  # ============================================================
  # cluster_nodes - parses node strings
  # ============================================================

  def test_cluster_nodes
    result = @client.cluster_nodes
    assert_instance_of Array, result
    assert_equal 2, result.length
  end

  def test_cluster_nodes_parses_master
    result = @client.cluster_nodes
    master = result[0]
    assert_equal "abc123", master[:id]
    assert_equal "127.0.0.1:7000@17000", master[:address]
    assert_includes master[:flags], "master"
    assert_nil master[:master_id]
    assert_equal 1, master[:config_epoch]
    assert_equal "connected", master[:link_state]
  end

  def test_cluster_nodes_parses_slots_range
    result = @client.cluster_nodes
    master = result[0]
    assert_equal 1, master[:slots].length
    assert_instance_of Range, master[:slots][0]
    assert_equal 0, master[:slots][0].begin
    assert_equal 5460, master[:slots][0].end
  end

  def test_cluster_nodes_parses_slave
    result = @client.cluster_nodes
    slave = result[1]
    assert_equal "def456", slave[:id]
    assert_includes slave[:flags], "slave"
    assert_equal "abc123", slave[:master_id]
    assert_empty slave[:slots]
  end

  # Test node with single slot (not a range)
  def test_cluster_nodes_single_slot
    client = ClusterNodesSingleSlotMock.new
    result = client.cluster_nodes
    node = result[0]
    assert_equal 1, node[:slots].length
    assert_equal 5461, node[:slots][0]
  end

  class ClusterNodesSingleSlotMock
    include RedisRuby::Commands::Cluster
    def call(*) = "OK"

    def call_1arg(cmd, subcmd)
      if subcmd == "NODES"
        "abc123 127.0.0.1:7000@17000 master - 0 1234 1 connected 5461\n"
      else
        "OK"
      end
    end

    def call_2args(*) = "OK"
    def call_3args(*) = "OK"
  end

  # Test empty nodes response
  def test_cluster_nodes_empty_line_skipped
    client = ClusterNodesEmptyMock.new
    result = client.cluster_nodes
    assert_equal 1, result.length
  end

  class ClusterNodesEmptyMock
    include RedisRuby::Commands::Cluster
    def call(*) = "OK"

    def call_1arg(cmd, subcmd)
      if subcmd == "NODES"
        "abc123 127.0.0.1:7000@17000 master - 0 1234 1 connected 0-5460\n\n"
      else
        "OK"
      end
    end

    def call_2args(*) = "OK"
    def call_3args(*) = "OK"
  end

  # Test node with non-numeric, non-range slot info (no dash, not purely digits)
  def test_cluster_nodes_non_slot_info_skipped
    client = ClusterNodesNonSlotMock.new
    result = client.cluster_nodes
    node = result[0]
    # The "[importing]" entry has no dash and doesn't match /^\d+$/, so it's skipped
    assert_equal 1, node[:slots].length
    assert_equal 0..5460, node[:slots][0]
  end

  class ClusterNodesNonSlotMock
    include RedisRuby::Commands::Cluster
    def call(*) = "OK"

    def call_1arg(cmd, subcmd)
      if subcmd == "NODES"
        "abc123 127.0.0.1:7000@17000 master - 0 1234 1 connected 0-5460 [importing]\n"
      else
        "OK"
      end
    end

    def call_2args(*) = "OK"
    def call_3args(*) = "OK"
  end

  # ============================================================
  # cluster_slots - parses slot data
  # ============================================================

  def test_cluster_slots
    result = @client.cluster_slots
    assert_instance_of Array, result
    assert_equal 2, result.length
  end

  def test_cluster_slots_parses_first_slot_range
    result = @client.cluster_slots
    first = result[0]
    assert_equal 0, first[:start_slot]
    assert_equal 5460, first[:end_slot]
  end

  def test_cluster_slots_parses_master_info
    result = @client.cluster_slots
    master = result[0][:master]
    assert_equal "127.0.0.1", master[:host]
    assert_equal 7000, master[:port]
    assert_equal "abc123", master[:id]
  end

  def test_cluster_slots_parses_replicas
    result = @client.cluster_slots
    replicas = result[0][:replicas]
    assert_equal 1, replicas.length
    assert_equal "127.0.0.1", replicas[0][:host]
    assert_equal 7003, replicas[0][:port]
    assert_equal "ghi789", replicas[0][:id]
  end

  def test_cluster_slots_no_replicas
    result = @client.cluster_slots
    second = result[1]
    assert_empty second[:replicas]
  end

  # Test parse_node_info with nil input
  def test_parse_node_info_nil_returns_nil
    # Access via send since it's private
    result = @client.send(:parse_node_info, nil)
    assert_nil result
  end

  # ============================================================
  # cluster_shards
  # ============================================================

  def test_cluster_shards
    result = @client.cluster_shards
    assert_instance_of Array, result
    assert_equal ["CLUSTER", "SHARDS"], @client.last_command
  end

  # ============================================================
  # cluster_keyslot
  # ============================================================

  def test_cluster_keyslot
    result = @client.cluster_keyslot("mykey")
    assert_equal ["CLUSTER", "KEYSLOT", "mykey"], @client.last_command
    assert_equal 12539, result
  end

  # ============================================================
  # cluster_countkeysinslot
  # ============================================================

  def test_cluster_countkeysinslot
    result = @client.cluster_countkeysinslot(12539)
    assert_equal ["CLUSTER", "COUNTKEYSINSLOT", 12539], @client.last_command
    assert_equal 3, result
  end

  # ============================================================
  # cluster_getkeysinslot
  # ============================================================

  def test_cluster_getkeysinslot
    result = @client.cluster_getkeysinslot(12539, 10)
    assert_equal ["CLUSTER", "GETKEYSINSLOT", 12539, 10], @client.last_command
    assert_equal %w[key1 key2], result
  end

  # ============================================================
  # cluster_myid
  # ============================================================

  def test_cluster_myid
    result = @client.cluster_myid
    assert_equal ["CLUSTER", "MYID"], @client.last_command
    assert_equal "abc123def456", result
  end

  # ============================================================
  # cluster_myshardid
  # ============================================================

  def test_cluster_myshardid
    result = @client.cluster_myshardid
    assert_equal ["CLUSTER", "MYSHARDID"], @client.last_command
    assert_equal "shard1", result
  end

  # ============================================================
  # cluster_replicate
  # ============================================================

  def test_cluster_replicate
    result = @client.cluster_replicate("node123")
    assert_equal ["CLUSTER", "REPLICATE", "node123"], @client.last_command
    assert_equal "OK", result
  end

  # ============================================================
  # cluster_addslots
  # ============================================================

  def test_cluster_addslots_single
    @client.cluster_addslots(100)
    assert_equal ["CLUSTER", "ADDSLOTS", 100], @client.last_command
  end

  def test_cluster_addslots_multiple
    @client.cluster_addslots(100, 101, 102)
    assert_equal ["CLUSTER", "ADDSLOTS", 100, 101, 102], @client.last_command
  end

  # ============================================================
  # cluster_delslots
  # ============================================================

  def test_cluster_delslots_single
    @client.cluster_delslots(100)
    assert_equal ["CLUSTER", "DELSLOTS", 100], @client.last_command
  end

  def test_cluster_delslots_multiple
    @client.cluster_delslots(100, 101, 102)
    assert_equal ["CLUSTER", "DELSLOTS", 100, 101, 102], @client.last_command
  end

  # ============================================================
  # cluster_setslot - all state branches
  # ============================================================

  def test_cluster_setslot_importing
    @client.cluster_setslot(100, :importing, "node123")
    assert_equal ["CLUSTER", "SETSLOT", 100, "IMPORTING", "node123"], @client.last_command
  end

  def test_cluster_setslot_migrating
    @client.cluster_setslot(100, :migrating, "node123")
    assert_equal ["CLUSTER", "SETSLOT", 100, "MIGRATING", "node123"], @client.last_command
  end

  def test_cluster_setslot_stable
    @client.cluster_setslot(100, :stable)
    assert_equal ["CLUSTER", "SETSLOT", 100, "STABLE"], @client.last_command
  end

  def test_cluster_setslot_node
    @client.cluster_setslot(100, :node, "node123")
    assert_equal ["CLUSTER", "SETSLOT", 100, "NODE", "node123"], @client.last_command
  end

  def test_cluster_setslot_invalid_state
    assert_raises(ArgumentError) do
      @client.cluster_setslot(100, :invalid)
    end
  end

  def test_cluster_setslot_invalid_state_message
    error = assert_raises(ArgumentError) do
      @client.cluster_setslot(100, :bogus)
    end
    assert_match(/Invalid state: bogus/, error.message)
  end

  # ============================================================
  # cluster_meet - with and without cluster_bus_port
  # ============================================================

  def test_cluster_meet_without_bus_port
    @client.cluster_meet("192.168.1.1", 7000)
    assert_equal ["CLUSTER", "MEET", "192.168.1.1", 7000], @client.last_command
  end

  def test_cluster_meet_with_bus_port
    @client.cluster_meet("192.168.1.1", 7000, 17000)
    assert_equal ["CLUSTER", "MEET", "192.168.1.1", 7000, 17000], @client.last_command
  end

  def test_cluster_meet_bus_port_nil_uses_fast_path
    @client.cluster_meet("192.168.1.1", 7000, nil)
    # nil is falsy, so fast path (call_3args) is taken
    assert_equal ["CLUSTER", "MEET", "192.168.1.1", 7000], @client.last_command
  end

  # ============================================================
  # cluster_forget
  # ============================================================

  def test_cluster_forget
    result = @client.cluster_forget("node123")
    assert_equal ["CLUSTER", "FORGET", "node123"], @client.last_command
    assert_equal "OK", result
  end

  # ============================================================
  # cluster_failover - all option branches
  # ============================================================

  def test_cluster_failover_no_option
    result = @client.cluster_failover
    assert_equal ["CLUSTER", "FAILOVER"], @client.last_command
    assert_equal "OK", result
  end

  def test_cluster_failover_force
    @client.cluster_failover(:force)
    assert_equal ["CLUSTER", "FAILOVER", "FORCE"], @client.last_command
  end

  def test_cluster_failover_takeover
    @client.cluster_failover(:takeover)
    assert_equal ["CLUSTER", "FAILOVER", "TAKEOVER"], @client.last_command
  end

  def test_cluster_failover_invalid_option
    assert_raises(ArgumentError) do
      @client.cluster_failover(:invalid)
    end
  end

  def test_cluster_failover_invalid_option_message
    error = assert_raises(ArgumentError) do
      @client.cluster_failover(:bogus)
    end
    assert_match(/Invalid option: bogus/, error.message)
  end

  # ============================================================
  # cluster_reset - hard and soft branches
  # ============================================================

  def test_cluster_reset_soft_default
    @client.cluster_reset
    assert_equal ["CLUSTER", "RESET", "SOFT"], @client.last_command
  end

  def test_cluster_reset_soft_explicit
    @client.cluster_reset(hard: false)
    assert_equal ["CLUSTER", "RESET", "SOFT"], @client.last_command
  end

  def test_cluster_reset_hard
    @client.cluster_reset(hard: true)
    assert_equal ["CLUSTER", "RESET", "HARD"], @client.last_command
  end

  # ============================================================
  # cluster_saveconfig
  # ============================================================

  def test_cluster_saveconfig
    result = @client.cluster_saveconfig
    assert_equal ["CLUSTER", "SAVECONFIG"], @client.last_command
    assert_equal "OK", result
  end

  # ============================================================
  # cluster_set_config_epoch
  # ============================================================

  def test_cluster_set_config_epoch
    result = @client.cluster_set_config_epoch(5)
    assert_equal ["CLUSTER", "SET-CONFIG-EPOCH", 5], @client.last_command
    assert_equal "OK", result
  end

  # ============================================================
  # cluster_bumpepoch
  # ============================================================

  def test_cluster_bumpepoch
    result = @client.cluster_bumpepoch
    assert_equal ["CLUSTER", "BUMPEPOCH"], @client.last_command
    assert_equal "BUMPED", result
  end

  # ============================================================
  # cluster_count_failure_reports
  # ============================================================

  def test_cluster_count_failure_reports
    result = @client.cluster_count_failure_reports("node123")
    assert_equal ["CLUSTER", "COUNT-FAILURE-REPORTS", "node123"], @client.last_command
    assert_equal 2, result
  end

  # ============================================================
  # readonly
  # ============================================================

  def test_readonly
    result = @client.readonly
    assert_equal ["READONLY"], @client.last_command
    assert_equal "OK", result
  end

  # ============================================================
  # readwrite
  # ============================================================

  def test_readwrite
    result = @client.readwrite
    assert_equal ["READWRITE"], @client.last_command
    assert_equal "OK", result
  end

  # ============================================================
  # asking
  # ============================================================

  def test_asking
    result = @client.asking
    assert_equal ["ASKING"], @client.last_command
    assert_equal "OK", result
  end
end
