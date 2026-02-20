# frozen_string_literal: true

require_relative "unit_test_helper"

# Tests for redis-rb issue #1184
# Cluster hostname vs IP normalization via host_translation.
class ClusterHostnameTest < Minitest::Test
  # ============================================================
  # host_translation normalizes CLUSTER SLOTS addresses
  # ============================================================

  def test_host_translation_maps_announced_ip_to_reachable_host
    mock_conn = mock("cluster_conn")
    mock_conn.stubs(:close)

    # CLUSTER SLOTS returns internal IPs
    mock_conn.stubs(:call).with("CLUSTER", "SLOTS").returns([
      [0, 8191, ["172.17.0.2", 6379]],
      [8192, 16_383, ["172.17.0.3", 6379]],
    ])
    mock_conn.stubs(:call).with("AUTH", "pass").returns("OK")

    # Only the seed connection should be created initially
    RR::Connection::TCP.stubs(:new).returns(mock_conn)

    client = RR::ClusterClient.new(
      nodes: ["redis://seed:6379"],
      password: "pass",
      host_translation: {
        "172.17.0.2" => "redis-node1.example.com",
        "172.17.0.3" => "redis-node2.example.com",
      }
    )

    # Verify slot mapping uses translated addresses
    node0 = client.node_for_slot(0)
    node8k = client.node_for_slot(8192)

    assert_equal "redis-node1.example.com:6379", node0
    assert_equal "redis-node2.example.com:6379", node8k
  end

  def test_host_translation_not_applied_when_nil
    mock_conn = mock("cluster_conn")
    mock_conn.stubs(:close)
    mock_conn.stubs(:call).with("CLUSTER", "SLOTS").returns([
      [0, 16_383, ["10.0.0.1", 6379]],
    ])
    RR::Connection::TCP.stubs(:new).returns(mock_conn)

    client = RR::ClusterClient.new(
      nodes: ["redis://10.0.0.1:6379"],
      host_translation: nil
    )

    node = client.node_for_slot(0)
    assert_equal "10.0.0.1:6379", node
  end

  def test_host_translation_passes_through_unknown_hosts
    mock_conn = mock("cluster_conn")
    mock_conn.stubs(:close)
    mock_conn.stubs(:call).with("CLUSTER", "SLOTS").returns([
      [0, 16_383, ["10.0.0.99", 6379]],
    ])
    RR::Connection::TCP.stubs(:new).returns(mock_conn)

    client = RR::ClusterClient.new(
      nodes: ["redis://10.0.0.99:6379"],
      host_translation: { "10.0.0.1" => "translated.host" }
    )

    # 10.0.0.99 is not in translation table, stays as-is
    node = client.node_for_slot(0)
    assert_equal "10.0.0.99:6379", node
  end

  def test_host_translation_applied_to_replicas
    mock_conn = mock("cluster_conn")
    mock_conn.stubs(:close)
    mock_conn.stubs(:call).with("CLUSTER", "SLOTS").returns([
      [0, 16_383, ["172.17.0.2", 6379], ["172.17.0.5", 6380]],
    ])
    RR::Connection::TCP.stubs(:new).returns(mock_conn)

    client = RR::ClusterClient.new(
      nodes: ["redis://seed:6379"],
      read_from: :replica,
      host_translation: {
        "172.17.0.2" => "master.host",
        "172.17.0.5" => "replica.host",
      }
    )

    # Read from replica should use translated address
    node = client.node_for_slot(0, for_read: true)
    assert_equal "replica.host:6380", node
  end

  # ============================================================
  # Node normalization at initialization
  # ============================================================

  def test_normalize_nodes_from_urls
    mock_conn = mock("cluster_conn")
    mock_conn.stubs(:close)
    mock_conn.stubs(:call).with("CLUSTER", "SLOTS").returns([
      [0, 16_383, ["host1", 6379]],
    ])
    RR::Connection::TCP.stubs(:new).returns(mock_conn)

    # Should not raise
    RR::ClusterClient.new(nodes: [
      "redis://host1:6379",
      "redis://host2:6380",
    ])
  end

  def test_normalize_nodes_from_hashes
    mock_conn = mock("cluster_conn")
    mock_conn.stubs(:close)
    mock_conn.stubs(:call).with("CLUSTER", "SLOTS").returns([
      [0, 16_383, ["host1", 6379]],
    ])
    RR::Connection::TCP.stubs(:new).returns(mock_conn)

    # Should not raise
    RR::ClusterClient.new(nodes: [
      { host: "host1", port: 6379 },
      { host: "host2", port: 6380 },
    ])
  end

  def test_normalize_nodes_invalid_format_raises
    assert_raises(ArgumentError) do
      mock_conn = mock("cluster_conn")
      mock_conn.stubs(:close)
      mock_conn.stubs(:call).returns([])
      RR::Connection::TCP.stubs(:new).returns(mock_conn)

      RR::ClusterClient.new(nodes: [123])
    end
  end
end
