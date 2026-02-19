# frozen_string_literal: true

require_relative "../unit_test_helper"

# Test that commands correctly handle both RESP2 (flat array) and RESP3 (Hash)
# responses for commands that return key-value pairs.
class RESP3HashHandlingTest < Minitest::Test
  def setup
    @client = RR::Client.new
  end

  # ============================================================
  # hgetall
  # ============================================================

  def test_hgetall_handles_resp3_hash_response
    @client.stubs(:call_1arg).returns({ "field1" => "value1", "field2" => "value2" })

    result = @client.hgetall("mykey")

    assert_instance_of Hash, result
    assert_equal({ "field1" => "value1", "field2" => "value2" }, result)
  end

  def test_hgetall_handles_resp2_array_response
    @client.stubs(:call_1arg).returns(%w[field1 value1 field2 value2])

    result = @client.hgetall("mykey")

    assert_instance_of Hash, result
    assert_equal({ "field1" => "value1", "field2" => "value2" }, result)
  end

  def test_hgetall_handles_empty_hash_response
    @client.stubs(:call_1arg).returns({})

    result = @client.hgetall("mykey")

    assert_empty(result)
  end

  def test_hgetall_handles_empty_array_response
    @client.stubs(:call_1arg).returns([])

    result = @client.hgetall("mykey")

    assert_empty(result)
  end
end
