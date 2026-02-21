# frozen_string_literal: true

require_relative "unit_test_helper"

# Tests for redis-rb issue #1271
# Response transformations (hgetall, zscore, etc.) must produce correct types
# even when used inside pipeline and transaction contexts.
#
# With RESP3, hgetall returns a native Hash from the protocol layer, so the
# transformation is handled at the protocol level rather than client level.
# These tests verify that pipeline and transaction both preserve the correct types.
class PipelineMultiTransformTest < Minitest::Test
  # Pipeline should return raw results (no transformation)
  # This is by design - pipeline results are raw RESP3 values
  def test_pipeline_hgetall_returns_raw_result
    client = RR::Client.new
    client.stubs(:ensure_connected)

    connection = mock("connection")
    connection.stubs(:connected?).returns(true)
    # RESP3 returns Hash natively for HGETALL
    connection.stubs(:pipeline).returns([{ "f1" => "v1", "f2" => "v2" }])

    client.instance_variable_set(:@connection, connection)

    results = client.pipelined do |p|
      p.hgetall("myhash")
    end

    assert_instance_of Hash, results[0]
    assert_equal({ "f1" => "v1", "f2" => "v2" }, results[0])
  end

  # Transaction EXEC returns array of results from queued commands
  def test_transaction_hgetall_returns_hash_in_exec
    client = RR::Client.new
    client.stubs(:ensure_connected)

    connection = mock("connection")
    connection.stubs(:connected?).returns(true)
    connection.stubs(:call).with("MULTI").returns("OK")
    connection.stubs(:call).with("HGETALL", "myhash").returns("QUEUED")
    # EXEC returns array of results - RESP3 gives Hash for HGETALL
    connection.stubs(:call).with("EXEC").returns([{ "f1" => "v1", "f2" => "v2" }])

    client.instance_variable_set(:@connection, connection)

    results = client.multi do |tx|
      tx.hgetall("myhash")
    end

    assert_instance_of Array, results
    assert_instance_of Hash, results[0]
    assert_equal({ "f1" => "v1", "f2" => "v2" }, results[0])
  end

  # Transaction with multiple commands preserves types
  def test_transaction_preserves_result_types
    client, connection = build_client_with_connection
    stub_multi_exec(connection, ["OK", "value", { "f1" => "v1" }, 42])

    results = client.multi do |tx|
      tx.set("key", "value")
      tx.get("key")
      tx.hgetall("myhash")
      tx.incr("counter")
    end

    assert_equal "OK", results[0]
    assert_equal "value", results[1]
    assert_instance_of Hash, results[2]
    assert_equal({ "f1" => "v1" }, results[2])
    assert_equal 42, results[3]
  end

  # Pipeline with multiple result types
  def test_pipeline_preserves_result_types
    client = RR::Client.new
    client.stubs(:ensure_connected)

    connection = mock("connection")
    connection.stubs(:connected?).returns(true)
    connection.stubs(:pipeline).returns(["OK", "value", { "f1" => "v1" }, 42])

    client.instance_variable_set(:@connection, connection)

    results = client.pipelined do |p|
      p.set("key", "value")
      p.get("key")
      p.hgetall("myhash")
      p.incr("counter")
    end

    assert_equal "OK", results[0]
    assert_equal "value", results[1]
    assert_instance_of Hash, results[2]
    assert_equal({ "f1" => "v1" }, results[2])
    assert_equal 42, results[3]
  end

  # Nil transaction result (aborted by WATCH) passes through
  def test_transaction_nil_result_passes_through
    client = RR::Client.new
    client.stubs(:ensure_connected)

    connection = mock("connection")
    connection.stubs(:connected?).returns(true)
    connection.stubs(:call).with("MULTI").returns("OK")
    connection.stubs(:call).with("HGETALL", "myhash").returns("QUEUED")
    connection.stubs(:call).with("EXEC").returns(nil)

    client.instance_variable_set(:@connection, connection)

    result = client.multi do |tx|
      tx.hgetall("myhash")
    end

    assert_nil result
  end

  private

  def build_client_with_connection
    client = RR::Client.new
    client.stubs(:ensure_connected)
    connection = mock("connection")
    connection.stubs(:connected?).returns(true)
    connection.stubs(:call).returns("QUEUED")
    client.instance_variable_set(:@connection, connection)
    [client, connection]
  end

  def stub_multi_exec(connection, exec_result)
    connection.stubs(:call).with("MULTI").returns("OK")
    connection.stubs(:call).with("EXEC").returns(exec_result)
  end
end
