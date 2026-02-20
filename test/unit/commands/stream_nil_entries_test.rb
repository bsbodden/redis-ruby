# frozen_string_literal: true

require_relative "../unit_test_helper"

# Tests for redis-rb issues #936 and #1165
# Stream commands must handle nil entries gracefully when
# referencing trimmed/deleted messages.
class StreamNilEntriesTest < Minitest::Test
  def setup
    @client = RR::Client.new
    @client.stubs(:ensure_connected)
  end

  # --- parse_entries with nil elements (redis-rb #936) ---

  def test_xclaim_handles_nil_entries_in_response
    # Simulate server returning [valid_entry, nil, valid_entry]
    # when some claimed messages have been trimmed
    mock_response = [
      ["1609459200000-0", { "field" => "value1" }],
      nil,
      ["1609459200001-0", { "field" => "value2" }],
    ]

    @client.stubs(:call).returns(mock_response)

    result = @client.xclaim("stream", "group", "consumer", 0, "1609459200000-0", "1609459200000-1", "1609459200001-0")

    # nil entries should be filtered out
    assert_equal 2, result.size
    assert_equal "1609459200000-0", result[0][0]
    assert_equal "1609459200001-0", result[1][0]
  end

  def test_xclaim_handles_all_nil_entries
    mock_response = [nil, nil]
    @client.stubs(:call).returns(mock_response)

    result = @client.xclaim("stream", "group", "consumer", 0, "id1", "id2")

    assert_equal [], result
  end

  def test_xclaim_handles_nil_response
    @client.stubs(:call).returns(nil)

    result = @client.xclaim("stream", "group", "consumer", 0, "id1")

    assert_equal [], result
  end

  # --- XAUTOCLAIM with nil entries (redis-rb #1165) ---

  def test_xautoclaim_handles_nil_entries_in_response
    # Server returns [next_id, [valid_entry, nil, valid_entry], deleted_ids]
    mock_response = [
      "1609459200002-0",
      [
        ["1609459200000-0", { "field" => "value1" }],
        nil,
        ["1609459200001-0", { "field" => "value2" }],
      ],
      ["1609459200000-1"],
    ]

    @client.stubs(:call).returns(mock_response)

    next_id, entries, deleted = @client.xautoclaim("stream", "group", "consumer", 0, "0-0")

    assert_equal "1609459200002-0", next_id
    assert_equal 2, entries.size
    assert_equal "1609459200000-0", entries[0][0]
    assert_equal "1609459200001-0", entries[1][0]
    assert_equal ["1609459200000-1"], deleted
  end

  def test_xautoclaim_handles_all_nil_entries
    mock_response = [
      "0-0",
      [nil, nil],
      [],
    ]

    @client.stubs(:call).returns(mock_response)

    next_id, entries, deleted = @client.xautoclaim("stream", "group", "consumer", 0, "0-0")

    assert_equal "0-0", next_id
    assert_equal [], entries
    assert_equal [], deleted
  end

  def test_xautoclaim_handles_nil_result
    @client.stubs(:call).returns(nil)

    result = @client.xautoclaim("stream", "group", "consumer", 0, "0-0")

    assert_nil result
  end

  # --- parse_entries with flat array entries containing nils ---

  def test_xclaim_handles_nil_fields_in_flat_array_entry
    # When RESP2 returns flat arrays: [id, [field, value, ...]]
    # and an entry has nil fields
    mock_response = [
      ["1609459200000-0", ["field1", "value1", "field2", "value2"]],
      nil,
    ]

    @client.stubs(:call).returns(mock_response)

    result = @client.xclaim("stream", "group", "consumer", 0, "id1", "id2")

    assert_equal 1, result.size
    assert_equal "1609459200000-0", result[0][0]
    assert_equal({ "field1" => "value1", "field2" => "value2" }, result[0][1])
  end
end
