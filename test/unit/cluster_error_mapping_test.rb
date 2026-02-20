# frozen_string_literal: true

require_relative "unit_test_helper"

# Tests for redis-rb issue #1296
# Cluster-specific errors should be mapped to specific exception classes.
class ClusterErrorMappingTest < Minitest::Test
  # Helper: build a cluster client with mocked topology
  def build_cluster
    mock_conn = mock("cluster_conn")
    mock_conn.stubs(:call).with("CLUSTER", "SLOTS").returns([
      [0, 16_383, ["host1", 6379]],
    ])
    mock_conn.stubs(:close)
    RR::Connection::TCP.stubs(:new).returns(mock_conn)

    RR::ClusterClient.new(nodes: ["redis://host1:6379"])
  end

  # ============================================================
  # Error class hierarchy
  # ============================================================

  def test_cluster_error_hierarchy
    assert_operator RR::ClusterError, :<, RR::Error
    assert_operator RR::ClusterDownError, :<, RR::ClusterError
    assert_operator RR::MovedError, :<, RR::ClusterError
    assert_operator RR::AskError, :<, RR::ClusterError
    assert_operator RR::CrossSlotError, :<, RR::ClusterError
    assert_operator RR::TryAgainError, :<, RR::ClusterError
  end

  # ============================================================
  # CLUSTERDOWN raises ClusterDownError
  # ============================================================

  def test_clusterdown_raises_cluster_down_error
    client = build_cluster

    conn = mock("conn")
    conn.stubs(:close)
    conn.stubs(:call).with("SET", "key", "val").returns(
      RR::CommandError.new("CLUSTERDOWN The cluster is down")
    )
    client.stubs(:get_connection).returns(conn)

    error = assert_raises(RR::ClusterDownError) do
      client.call("SET", "key", "val")
    end
    assert_includes error.message, "CLUSTERDOWN"
  end

  # ============================================================
  # CROSSSLOT raises CrossSlotError
  # ============================================================

  def test_crossslot_raises_cross_slot_error
    client = build_cluster

    conn = mock("conn")
    conn.stubs(:close)
    conn.stubs(:call).with("MSET", "k1", "v1", "k2", "v2").returns(
      RR::CommandError.new("CROSSSLOT Keys in request don't hash to the same slot")
    )
    client.stubs(:get_connection).returns(conn)

    error = assert_raises(RR::CrossSlotError) do
      client.call("MSET", "k1", "v1", "k2", "v2")
    end
    assert_includes error.message, "CROSSSLOT"
  end

  # ============================================================
  # TRYAGAIN retries then raises TryAgainError
  # ============================================================

  def test_tryagain_retries_and_succeeds
    client = build_cluster
    client.stubs(:sleep)

    conn = mock("conn")
    conn.stubs(:close)
    seq = sequence("tryagain")
    conn.expects(:call).with("SET", "key", "val")
      .returns(RR::CommandError.new("TRYAGAIN Multiple keys request during rehashing of slot"))
      .in_sequence(seq)
    conn.expects(:call).with("SET", "key", "val")
      .returns("OK")
      .in_sequence(seq)
    client.stubs(:get_connection).returns(conn)

    result = client.call("SET", "key", "val")
    assert_equal "OK", result
  end

  def test_tryagain_exhausts_redirections
    client = build_cluster
    client.stubs(:sleep)

    conn = mock("conn")
    conn.stubs(:close)
    conn.stubs(:call).with("SET", "key", "val").returns(
      RR::CommandError.new("TRYAGAIN Multiple keys request during rehashing of slot")
    )
    client.stubs(:get_connection).returns(conn)

    assert_raises(RR::TryAgainError) do
      client.call("SET", "key", "val")
    end
  end

  # ============================================================
  # Unknown errors still raise CommandError
  # ============================================================

  def test_unknown_command_error_raises_command_error
    client = build_cluster

    conn = mock("conn")
    conn.stubs(:close)
    conn.stubs(:call).with("SET", "key", "val").returns(
      RR::CommandError.new("ERR unknown command")
    )
    client.stubs(:get_connection).returns(conn)

    assert_raises(RR::CommandError) do
      client.call("SET", "key", "val")
    end
  end
end
