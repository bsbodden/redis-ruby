# frozen_string_literal: true

require_relative "../unit_test_helper"

module ClusterCommandsTestMocks
  class MockClient
    include RR::Commands::Cluster

    attr_reader :last_command

    def call(*args)
      @last_command = args
      mock_return(args)
    end

    def call_1arg(cmd, arg_one)
      @last_command = [cmd, arg_one]
      mock_return([cmd, arg_one])
    end

    def call_2args(cmd, arg_one, arg_two)
      @last_command = [cmd, arg_one, arg_two]
      mock_return([cmd, arg_one, arg_two])
    end

    def call_3args(cmd, arg_one, arg_two, arg_three)
      @last_command = [cmd, arg_one, arg_two, arg_three]
      mock_return([cmd, arg_one, arg_two, arg_three])
    end

    CLUSTER_RESPONSES = {
      "INFO" => "cluster_enabled:1\r\ncluster_state:ok\r\ncluster_slots_assigned:16384\r\ncluster_known_nodes:6",
      "NODES" => "abc123 127.0.0.1:7000@17000 master - 0 1234 1 connected 0-5460\n" \
                 "def456 127.0.0.1:7001@17001 slave abc123 0 1234 1 connected\n",
      "SLOTS" => [
        [0, 5460, ["127.0.0.1", 7000, "abc123"], ["127.0.0.1", 7003, "ghi789"]],
        [5461, 10_922, ["127.0.0.1", 7001, "def456"]],
      ],
      "SHARDS" => [{ "slots" => [0, 5460], "nodes" => [] }],
      "KEYSLOT" => 12_539, "COUNTKEYSINSLOT" => 3,
      "GETKEYSINSLOT" => %w[key1 key2],
      "MYID" => "abc123def456", "MYSHARDID" => "shard1",
      "BUMPEPOCH" => "BUMPED", "COUNT-FAILURE-REPORTS" => 2,
    }.freeze

    private

    def mock_return(args)
      subcmd = args[1] if args[0] == "CLUSTER"
      CLUSTER_RESPONSES.fetch(subcmd, "OK")
    end
  end

  class ClusterInfoMalformedMock
    include RR::Commands::Cluster

    def call(*) = "OK"

    def call_1arg(_cmd, subcmd)
      if subcmd == "INFO"
        "no_colon_line\r\ncluster_state:ok\r\n\r\n"
      else
        "OK"
      end
    end

    def call_2args(*) = "OK"
    def call_3args(*) = "OK"
  end

  class ClusterNodesSingleSlotMock
    include RR::Commands::Cluster

    def call(*) = "OK"

    def call_1arg(_cmd, subcmd)
      if subcmd == "NODES"
        "abc123 127.0.0.1:7000@17000 master - 0 1234 1 connected 5461\n"
      else
        "OK"
      end
    end

    def call_2args(*) = "OK"
    def call_3args(*) = "OK"
  end

  class ClusterNodesEmptyMock
    include RR::Commands::Cluster

    def call(*) = "OK"

    def call_1arg(_cmd, subcmd)
      if subcmd == "NODES"
        "abc123 127.0.0.1:7000@17000 master - 0 1234 1 connected 0-5460\n\n"
      else
        "OK"
      end
    end

    def call_2args(*) = "OK"
    def call_3args(*) = "OK"
  end

  class ClusterNodesNonSlotMock
    include RR::Commands::Cluster

    def call(*) = "OK"

    def call_1arg(_cmd, subcmd)
      if subcmd == "NODES"
        "abc123 127.0.0.1:7000@17000 master - 0 1234 1 connected 0-5460 [importing]\n"
      else
        "OK"
      end
    end

    def call_2args(*) = "OK"
    def call_3args(*) = "OK"
  end
end

class ClusterCommandsTest < Minitest::Test
  def setup
    @client = ClusterCommandsTestMocks::MockClient.new
  end

  # ============================================================
  # cluster_info - parses response into hash
  # ============================================================

  def test_cluster_info
    result = @client.cluster_info

    assert_instance_of Hash, result
    assert_equal 1, result["cluster_enabled"]
    assert_equal "ok", result["cluster_state"]
    assert_equal 16_384, result["cluster_slots_assigned"]
    assert_equal 6, result["cluster_known_nodes"]
  end

  def test_cluster_info_parses_numeric_values
    result = @client.cluster_info

    assert_instance_of Integer, result["cluster_enabled"]
    assert_instance_of String, result["cluster_state"]
  end

  def test_cluster_info_skips_malformed_lines
    client = ClusterCommandsTestMocks::ClusterInfoMalformedMock.new
    result = client.cluster_info

    assert_instance_of Hash, result
    assert_equal "ok", result["cluster_state"]
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

  def test_cluster_nodes_single_slot
    client = ClusterCommandsTestMocks::ClusterNodesSingleSlotMock.new
    result = client.cluster_nodes
    node = result[0]

    assert_equal 1, node[:slots].length
    assert_equal 5461, node[:slots][0]
  end

  def test_cluster_nodes_empty_line_skipped
    client = ClusterCommandsTestMocks::ClusterNodesEmptyMock.new
    result = client.cluster_nodes

    assert_equal 1, result.length
  end

  def test_cluster_nodes_non_slot_info_skipped
    client = ClusterCommandsTestMocks::ClusterNodesNonSlotMock.new
    result = client.cluster_nodes
    node = result[0]

    assert_equal 1, node[:slots].length
    assert_equal 0..5460, node[:slots][0]
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

  def test_parse_node_info_nil_returns_nil
    result = @client.send(:parse_node_info, nil)

    assert_nil result
  end
end

class ClusterCommandsTestPart2 < Minitest::Test
  def setup
    @client = ClusterCommandsTestMocks::MockClient.new
  end

  # ============================================================
  # cluster_shards / cluster_keyslot / cluster_countkeysinslot / cluster_getkeysinslot
  # ============================================================

  def test_cluster_shards
    result = @client.cluster_shards

    assert_instance_of Array, result
    assert_equal %w[CLUSTER SHARDS], @client.last_command
  end

  def test_cluster_keyslot
    result = @client.cluster_keyslot("mykey")

    assert_equal %w[CLUSTER KEYSLOT mykey], @client.last_command
    assert_equal 12_539, result
  end

  def test_cluster_countkeysinslot
    result = @client.cluster_countkeysinslot(12_539)

    assert_equal ["CLUSTER", "COUNTKEYSINSLOT", 12_539], @client.last_command
    assert_equal 3, result
  end

  def test_cluster_getkeysinslot
    result = @client.cluster_getkeysinslot(12_539, 10)

    assert_equal ["CLUSTER", "GETKEYSINSLOT", 12_539, 10], @client.last_command
    assert_equal %w[key1 key2], result
  end

  def test_cluster_myid
    result = @client.cluster_myid

    assert_equal %w[CLUSTER MYID], @client.last_command
    assert_equal "abc123def456", result
  end

  def test_cluster_myshardid
    result = @client.cluster_myshardid

    assert_equal %w[CLUSTER MYSHARDID], @client.last_command
    assert_equal "shard1", result
  end

  def test_cluster_replicate
    result = @client.cluster_replicate("node123")

    assert_equal %w[CLUSTER REPLICATE node123], @client.last_command
    assert_equal "OK", result
  end

  def test_cluster_addslots_single
    @client.cluster_addslots(100)

    assert_equal ["CLUSTER", "ADDSLOTS", 100], @client.last_command
  end

  def test_cluster_addslots_multiple
    @client.cluster_addslots(100, 101, 102)

    assert_equal ["CLUSTER", "ADDSLOTS", 100, 101, 102], @client.last_command
  end

  def test_cluster_delslots_single
    @client.cluster_delslots(100)

    assert_equal ["CLUSTER", "DELSLOTS", 100], @client.last_command
  end

  def test_cluster_delslots_multiple
    @client.cluster_delslots(100, 101, 102)

    assert_equal ["CLUSTER", "DELSLOTS", 100, 101, 102], @client.last_command
  end

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

  def test_cluster_meet_without_bus_port
    @client.cluster_meet("192.168.1.1", 7000)

    assert_equal ["CLUSTER", "MEET", "192.168.1.1", 7000], @client.last_command
  end

  def test_cluster_meet_with_bus_port
    @client.cluster_meet("192.168.1.1", 7000, 17_000)

    assert_equal ["CLUSTER", "MEET", "192.168.1.1", 7000, 17_000], @client.last_command
  end

  def test_cluster_meet_bus_port_nil_uses_fast_path
    @client.cluster_meet("192.168.1.1", 7000, nil)

    assert_equal ["CLUSTER", "MEET", "192.168.1.1", 7000], @client.last_command
  end

  def test_cluster_forget
    result = @client.cluster_forget("node123")

    assert_equal %w[CLUSTER FORGET node123], @client.last_command
    assert_equal "OK", result
  end

  def test_cluster_failover_no_option
    result = @client.cluster_failover

    assert_equal %w[CLUSTER FAILOVER], @client.last_command
    assert_equal "OK", result
  end

  def test_cluster_failover_force
    @client.cluster_failover(:force)

    assert_equal %w[CLUSTER FAILOVER FORCE], @client.last_command
  end

  def test_cluster_failover_takeover
    @client.cluster_failover(:takeover)

    assert_equal %w[CLUSTER FAILOVER TAKEOVER], @client.last_command
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

  def test_cluster_reset_soft_default
    @client.cluster_reset

    assert_equal %w[CLUSTER RESET SOFT], @client.last_command
  end

  def test_cluster_reset_soft_explicit
    @client.cluster_reset(hard: false)

    assert_equal %w[CLUSTER RESET SOFT], @client.last_command
  end

  def test_cluster_reset_hard
    @client.cluster_reset(hard: true)

    assert_equal %w[CLUSTER RESET HARD], @client.last_command
  end

  def test_cluster_saveconfig
    result = @client.cluster_saveconfig

    assert_equal %w[CLUSTER SAVECONFIG], @client.last_command
    assert_equal "OK", result
  end

  def test_cluster_set_config_epoch
    result = @client.cluster_set_config_epoch(5)

    assert_equal ["CLUSTER", "SET-CONFIG-EPOCH", 5], @client.last_command
    assert_equal "OK", result
  end

  def test_cluster_bumpepoch
    result = @client.cluster_bumpepoch

    assert_equal %w[CLUSTER BUMPEPOCH], @client.last_command
    assert_equal "BUMPED", result
  end

  def test_cluster_count_failure_reports
    result = @client.cluster_count_failure_reports("node123")

    assert_equal %w[CLUSTER COUNT-FAILURE-REPORTS node123], @client.last_command
    assert_equal 2, result
  end

  def test_readonly
    result = @client.readonly

    assert_equal ["READONLY"], @client.last_command
    assert_equal "OK", result
  end

  def test_readwrite
    result = @client.readwrite

    assert_equal ["READWRITE"], @client.last_command
    assert_equal "OK", result
  end

  def test_asking
    result = @client.asking

    assert_equal ["ASKING"], @client.last_command
    assert_equal "OK", result
  end
end
