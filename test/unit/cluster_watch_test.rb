# frozen_string_literal: true

require_relative "unit_test_helper"

# Tests for redis-rb issue #955
# Cluster WATCH/UNWATCH must route to the same node.
class ClusterWatchTest < Minitest::Test
  def build_cluster
    mock_conn = mock("cluster_conn")
    mock_conn.stubs(:call).with("CLUSTER", "SLOTS").returns([
      [0, 5460, ["host1", 6379]],
      [5461, 10_922, ["host2", 6379]],
      [10_923, 16_383, ["host3", 6379]],
    ])
    mock_conn.stubs(:close)
    RR::Connection::TCP.stubs(:new).returns(mock_conn)

    RR::ClusterClient.new(nodes: ["redis://host1:6379"])
  end

  def mock_conn_for(host, port = 6379)
    conn = mock("#{host}:#{port}")
    conn.stubs(:close)
    conn
  end

  # ============================================================
  # WATCH routes to correct node
  # ============================================================

  def test_watch_sends_to_node_owning_key
    client = build_cluster

    # "foo" hashes to slot 12182 -> host3
    slot = client.key_slot("foo")
    node_addr = client.node_for_slot(slot)

    conn = mock_conn_for("host3")
    conn.expects(:call).with("WATCH", "foo").returns("OK")
    conn.expects(:call).with("UNWATCH").returns("OK")
    client.stubs(:get_connection).with(node_addr).returns(conn)

    result = client.watch("foo") { "watched" }

    assert_equal "watched", result
  end

  # ============================================================
  # UNWATCH goes to same node as WATCH
  # ============================================================

  def test_unwatch_routes_to_same_node_as_watch
    client = build_cluster

    slot = client.key_slot("foo")
    node_addr = client.node_for_slot(slot)

    conn = mock_conn_for("host3")
    conn.expects(:call).with("WATCH", "foo").returns("OK")
    conn.expects(:call).with("UNWATCH").returns("OK")
    client.stubs(:get_connection).with(node_addr).returns(conn)

    # WATCH without block
    client.watch("foo")
    # UNWATCH must go to same connection
    client.unwatch
  end

  def test_unwatch_without_watch_raises
    client = build_cluster

    assert_raises(RR::Error) { client.unwatch }
  end

  # ============================================================
  # WATCH with block ensures UNWATCH on error
  # ============================================================

  def test_watch_block_ensures_unwatch_on_exception
    client = build_cluster

    slot = client.key_slot("foo")
    node_addr = client.node_for_slot(slot)

    conn = mock_conn_for("host3")
    conn.expects(:call).with("WATCH", "foo").returns("OK")
    conn.expects(:call).with("UNWATCH").returns("OK")
    client.stubs(:get_connection).with(node_addr).returns(conn)

    assert_raises(RuntimeError) do
      client.watch("foo") { raise "boom" }
    end
  end

  # ============================================================
  # Cross-slot WATCH prevention
  # ============================================================

  def test_watch_rejects_keys_in_different_slots
    client = build_cluster

    # "foo" and "bar" hash to different slots
    refute_equal client.key_slot("foo"), client.key_slot("bar")

    assert_raises(RR::CrossSlotError) do
      client.watch("foo", "bar")
    end
  end

  def test_watch_allows_keys_with_same_hash_tag
    client = build_cluster

    slot = client.key_slot("{user}:name")
    node_addr = client.node_for_slot(slot)

    conn = mock_conn_for("node")
    conn.expects(:call).with("WATCH", "{user}:name", "{user}:email").returns("OK")
    conn.expects(:call).with("UNWATCH").returns("OK")
    client.stubs(:get_connection).with(node_addr).returns(conn)

    # Same hash tag => same slot => should work
    assert_equal client.key_slot("{user}:name"), client.key_slot("{user}:email")

    result = client.watch("{user}:name", "{user}:email") { "ok" }

    assert_equal "ok", result
  end

  # ============================================================
  # WATCH requires at least one key
  # ============================================================

  def test_watch_requires_keys
    client = build_cluster

    assert_raises(ArgumentError) { client.watch }
  end

  # ============================================================
  # MULTI uses watched connection
  # ============================================================

  def test_multi_uses_watched_connection
    client = build_cluster

    slot = client.key_slot("foo")
    node_addr = client.node_for_slot(slot)

    conn = mock_conn_for("host3")
    conn.expects(:call).with("WATCH", "foo").returns("OK")
    client.stubs(:get_connection).with(node_addr).returns(conn)

    tx_mock = mock("transaction")
    tx_mock.expects(:execute).returns(["OK"])
    RR::Transaction.expects(:new).with(conn).returns(tx_mock)

    # WATCH sets the connection, MULTI should use it
    client.watch("foo")
    results = client.multi { |_tx| nil }

    assert_equal ["OK"], results
  end

  def test_multi_without_watch_uses_random_master
    client = build_cluster

    conn = mock_conn_for("random_master")
    client.stubs(:random_master).returns("host1:6379")
    client.stubs(:get_connection).with("host1:6379").returns(conn)

    tx_mock = mock("transaction")
    tx_mock.expects(:execute).returns(["OK"])
    RR::Transaction.expects(:new).with(conn).returns(tx_mock)

    results = client.multi { |_tx| nil }

    assert_equal ["OK"], results
  end
end
