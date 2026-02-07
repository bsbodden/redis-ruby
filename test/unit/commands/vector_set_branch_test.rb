# frozen_string_literal: true

require_relative "../unit_test_helper"
require "json"

# Branch-coverage unit tests for RedisRuby::Commands::VectorSet
# Uses a lightweight MockClient that includes the module directly
# and records every command sent through call / call_Nargs.
class VectorSetBranchTest < Minitest::Test
  # ------------------------------------------------------------------ mock --
  class MockClient
    include RedisRuby::Commands::VectorSet

    attr_reader :last_command
    attr_accessor :next_return

    def call(*args)
      @last_command = args
      @next_return
    end

    def call_1arg(cmd, a)
      @last_command = [cmd, a]
      @next_return
    end

    def call_2args(cmd, a, b)
      @last_command = [cmd, a, b]
      @next_return
    end

    def call_3args(cmd, a, b, c)
      @last_command = [cmd, a, b, c]
      @next_return
    end
  end

  def setup
    @client = MockClient.new
  end

  # ============================================================
  # vadd
  # ============================================================

  def test_vadd_with_array_vector
    @client.next_return = 1
    result = @client.vadd("vset", [1.0, 2.0, 3.0], "item1")

    assert_equal 1, result
    cmd = @client.last_command

    assert_equal "VADD", cmd[0]
    assert_equal "vset", cmd[1]
    assert_equal "VALUES", cmd[2]
    assert_equal 3, cmd[3]
    assert_in_delta(1.0, cmd[4])
    assert_in_delta(2.0, cmd[5])
    assert_in_delta(3.0, cmd[6])
    assert_equal "item1", cmd[7]
  end

  def test_vadd_with_binary_fp32_vector
    binary = [1.0, 2.0].pack("e*")
    @client.vadd("vset", binary, "item1")
    cmd = @client.last_command

    assert_equal "VADD", cmd[0]
    assert_equal "FP32", cmd[2]
    assert_equal binary, cmd[3]
    assert_equal "item1", cmd[4]
  end

  def test_vadd_with_invalid_input_raises_argument_error
    assert_raises(ArgumentError) do
      @client.vadd("vset", 12_345, "item1")
    end
  end

  def test_vadd_with_non_binary_string_raises_argument_error
    # A UTF-8 string is not binary
    assert_raises(ArgumentError) do
      @client.vadd("vset", "not_binary", "item1")
    end
  end

  def test_vadd_with_reduce_dim
    @client.vadd("vset", [1.0, 2.0, 3.0], "item1", reduce_dim: 2)
    cmd = @client.last_command

    assert_equal "REDUCE", cmd[2]
    assert_equal 2, cmd[3]
    assert_equal "VALUES", cmd[4]
  end

  def test_vadd_with_cas
    @client.vadd("vset", [1.0, 2.0], "item1", cas: true)
    cmd = @client.last_command

    assert_includes cmd, "CAS"
  end

  def test_vadd_without_cas
    @client.vadd("vset", [1.0, 2.0], "item1", cas: false)

    refute_includes @client.last_command, "CAS"
  end

  def test_vadd_with_quantization
    @client.vadd("vset", [1.0, 2.0], "item1", quantization: "q8")

    assert_includes @client.last_command, "Q8"
  end

  def test_vadd_with_ef
    @client.vadd("vset", [1.0, 2.0], "item1", ef: 200)
    cmd = @client.last_command
    idx = cmd.index("EF")

    refute_nil idx
    assert_equal 200, cmd[idx + 1]
  end

  def test_vadd_with_attributes_hash
    @client.vadd("vset", [1.0, 2.0], "item1", attributes: { category: "electronics", price: 99.99 })
    cmd = @client.last_command
    idx = cmd.index("SETATTR")

    refute_nil idx
    parsed = JSON.parse(cmd[idx + 1])

    assert_equal "electronics", parsed["category"]
    assert_in_delta 99.99, parsed["price"]
  end

  def test_vadd_with_attributes_empty_hash
    @client.vadd("vset", [1.0, 2.0], "item1", attributes: {})
    cmd = @client.last_command
    idx = cmd.index("SETATTR")

    refute_nil idx
    assert_equal "{}", cmd[idx + 1]
  end

  def test_vadd_with_attributes_string
    @client.vadd("vset", [1.0, 2.0], "item1", attributes: '{"custom":"json"}')
    cmd = @client.last_command
    idx = cmd.index("SETATTR")

    refute_nil idx
    assert_equal '{"custom":"json"}', cmd[idx + 1]
  end

  def test_vadd_with_numlinks
    @client.vadd("vset", [1.0, 2.0], "item1", numlinks: 16)
    cmd = @client.last_command
    idx = cmd.index("M")

    refute_nil idx
    assert_equal 16, cmd[idx + 1]
  end

  def test_vadd_all_options
    @client.vadd("vset", [1.0, 2.0], "item1",
                 reduce_dim: 1, cas: true, quantization: "bin",
                 ef: 100, attributes: { a: 1 }, numlinks: 8)
    cmd = @client.last_command

    assert_includes cmd, "REDUCE"
    assert_includes cmd, "CAS"
    assert_includes cmd, "BIN"
    assert_includes cmd, "EF"
    assert_includes cmd, "SETATTR"
    assert_includes cmd, "M"
  end

  # ============================================================
  # vsim
  # ============================================================

  def test_vsim_with_array_input
    @client.next_return = %w[item1 item2]
    result = @client.vsim("vset", [1.0, 2.0, 3.0])

    assert_equal %w[item1 item2], result
    cmd = @client.last_command

    assert_equal "VSIM", cmd[0]
    assert_equal "VALUES", cmd[2]
    assert_equal 3, cmd[3]
  end

  def test_vsim_with_binary_input
    binary = [1.0, 2.0].pack("e*")
    @client.next_return = ["item1"]
    @client.vsim("vset", binary)
    cmd = @client.last_command

    assert_equal "FP32", cmd[2]
    assert_equal binary, cmd[3]
  end

  def test_vsim_with_string_element_name
    @client.next_return = ["item1"]
    @client.vsim("vset", "existing_element")
    cmd = @client.last_command

    assert_equal "ELE", cmd[2]
    assert_equal "existing_element", cmd[3]
  end

  def test_vsim_with_invalid_input_raises
    assert_raises(ArgumentError) do
      @client.vsim("vset", 12_345)
    end
  end

  def test_vsim_with_scores
    @client.next_return = ["item1", "0.95", "item2", "0.80"]
    result = @client.vsim("vset", [1.0, 2.0], with_scores: true)

    assert_instance_of Hash, result
    assert_in_delta 0.95, result["item1"]
    assert_in_delta 0.80, result["item2"]
  end

  def test_vsim_with_attribs
    @client.next_return = ["item1", '{"category":"electronics"}', "item2", '{"category":"books"}']
    result = @client.vsim("vset", [1.0, 2.0], with_attribs: true)

    assert_instance_of Hash, result
    assert_equal({ "category" => "electronics" }, result["item1"])
    assert_equal({ "category" => "books" }, result["item2"])
  end

  def test_vsim_with_scores_and_attribs
    @client.next_return = ["item1", "0.95", '{"cat":"elec"}', "item2", "0.80", '{"cat":"book"}']
    result = @client.vsim("vset", [1.0, 2.0], with_scores: true, with_attribs: true)

    assert_instance_of Hash, result
    assert_in_delta 0.95, result["item1"]["score"]
    assert_equal({ "cat" => "elec" }, result["item1"]["attributes"])
  end

  def test_vsim_with_count
    @client.next_return = ["item1"]
    @client.vsim("vset", [1.0, 2.0], count: 10)
    cmd = @client.last_command
    idx = cmd.index("COUNT")

    refute_nil idx
    assert_equal 10, cmd[idx + 1]
  end

  def test_vsim_with_ef
    @client.next_return = ["item1"]
    @client.vsim("vset", [1.0, 2.0], ef: 200)
    cmd = @client.last_command
    idx = cmd.index("EF")

    refute_nil idx
    assert_equal 200, cmd[idx + 1]
  end

  def test_vsim_with_filter
    @client.next_return = ["item1"]
    @client.vsim("vset", [1.0, 2.0], filter: ".category == 'electronics'")
    cmd = @client.last_command
    idx = cmd.index("FILTER")

    refute_nil idx
    assert_equal ".category == 'electronics'", cmd[idx + 1]
  end

  def test_vsim_with_filter_ef
    @client.next_return = ["item1"]
    @client.vsim("vset", [1.0, 2.0], filter_ef: "100")
    cmd = @client.last_command
    idx = cmd.index("FILTER-EF")

    refute_nil idx
    assert_equal "100", cmd[idx + 1]
  end

  def test_vsim_with_truth
    @client.next_return = ["item1"]
    @client.vsim("vset", [1.0, 2.0], truth: true)

    assert_includes @client.last_command, "TRUTH"
  end

  def test_vsim_with_no_thread
    @client.next_return = ["item1"]
    @client.vsim("vset", [1.0, 2.0], no_thread: true)

    assert_includes @client.last_command, "NOTHREAD"
  end

  def test_vsim_with_epsilon
    @client.next_return = ["item1"]
    @client.vsim("vset", [1.0, 2.0], epsilon: 0.01)
    cmd = @client.last_command
    idx = cmd.index("EPSILON")

    refute_nil idx
    assert_in_delta 0.01, cmd[idx + 1]
  end

  def test_vsim_without_truth_and_no_thread
    @client.next_return = ["item1"]
    @client.vsim("vset", [1.0, 2.0])

    refute_includes @client.last_command, "TRUTH"
    refute_includes @client.last_command, "NOTHREAD"
  end

  # ============================================================
  # vdim / vcard / vrem
  # ============================================================

  def test_vdim
    @client.next_return = 3
    result = @client.vdim("vset")

    assert_equal 3, result
    assert_equal %w[VDIM vset], @client.last_command
  end

  def test_vcard
    @client.next_return = 100
    result = @client.vcard("vset")

    assert_equal 100, result
    assert_equal %w[VCARD vset], @client.last_command
  end

  def test_vrem
    @client.next_return = 1
    result = @client.vrem("vset", "item1")

    assert_equal 1, result
    assert_equal %w[VREM vset item1], @client.last_command
  end

  # ============================================================
  # vemb
  # ============================================================

  def test_vemb_without_raw
    @client.next_return = ["1.0", "2.0", "3.0"]
    result = @client.vemb("vset", "item1")

    assert_equal [1.0, 2.0, 3.0], result
    assert_equal %w[VEMB vset item1], @client.last_command
  end

  def test_vemb_with_raw_array_ge_3_elements
    @client.next_return = ["NOQUANT", "raw_data", "1.5"]
    result = @client.vemb("vset", "item1", raw: true)

    assert_instance_of Hash, result
    assert_equal "NOQUANT", result["quantization"]
    assert_equal "raw_data", result["raw"]
    assert_in_delta 1.5, result["l2"]
    assert_nil result["range"]
    assert_equal %w[VEMB vset item1 RAW], @client.last_command
  end

  def test_vemb_with_raw_array_gt_3_elements_includes_range
    @client.next_return = ["Q8", "raw_data", "2.0", "0.5"]
    result = @client.vemb("vset", "item1", raw: true)

    assert_in_delta 2.0, result["l2"]
    assert_in_delta 0.5, result["range"]
  end

  def test_vemb_nil_result
    @client.next_return = nil
    result = @client.vemb("vset", "nonexistent")

    assert_nil result
  end

  def test_vemb_non_array_result
    @client.next_return = "some_string"
    result = @client.vemb("vset", "item1")

    assert_equal "some_string", result
  end

  def test_vemb_raw_short_array_uses_to_f
    # When raw: true but array length < 3, falls through to the elsif branch
    @client.next_return = ["1.0", "2.0"]
    result = @client.vemb("vset", "item1", raw: true)

    assert_equal [1.0, 2.0], result
  end

  # ============================================================
  # vlinks
  # ============================================================

  def test_vlinks_without_with_scores
    @client.next_return = [%w[a b], %w[c d]]
    result = @client.vlinks("vset", "item1")

    assert_equal [%w[a b], %w[c d]], result
    assert_equal %w[VLINKS vset item1], @client.last_command
  end

  def test_vlinks_with_with_scores_array_of_arrays
    @client.next_return = [["neighbor1", "0.95", "neighbor2", "0.80"], ["neighbor3", "0.70"]]
    result = @client.vlinks("vset", "item1", with_scores: true)

    assert_equal %w[VLINKS vset item1 WITHSCORES], @client.last_command
    assert_instance_of Array, result
    assert_instance_of Hash, result[0]
    assert_in_delta 0.95, result[0]["neighbor1"]
    assert_in_delta 0.80, result[0]["neighbor2"]
    assert_in_delta 0.70, result[1]["neighbor3"]
  end

  def test_vlinks_with_with_scores_array_of_non_arrays
    @client.next_return = ["plain_string", 42]
    result = @client.vlinks("vset", "item1", with_scores: true)
    # Non-array level items are passed through
    assert_equal "plain_string", result[0]
    assert_equal 42, result[1]
  end

  def test_vlinks_nil_result
    @client.next_return = nil
    result = @client.vlinks("vset", "nonexistent")

    assert_nil result
  end

  def test_vlinks_with_scores_nil_result
    @client.next_return = nil
    result = @client.vlinks("vset", "nonexistent", with_scores: true)

    assert_nil result
  end

  def test_vlinks_with_scores_non_array_result
    @client.next_return = "not_an_array"
    result = @client.vlinks("vset", "item1", with_scores: true)
    # When not an array, returns as-is
    assert_equal "not_an_array", result
  end

  # ============================================================
  # vinfo
  # ============================================================

  def test_vinfo
    @client.next_return = ["num_elements", 100, "dimension", 3]
    result = @client.vinfo("vset")

    assert_equal({ "num_elements" => 100, "dimension" => 3 }, result)
    assert_equal %w[VINFO vset], @client.last_command
  end

  # ============================================================
  # vsetattr
  # ============================================================

  def test_vsetattr_with_hash
    @client.vsetattr("vset", "item1", { category: "electronics" })
    cmd = @client.last_command

    assert_equal "VSETATTR", cmd[0]
    assert_equal "vset", cmd[1]
    assert_equal "item1", cmd[2]
    parsed = JSON.parse(cmd[3])

    assert_equal "electronics", parsed["category"]
  end

  def test_vsetattr_with_empty_hash
    @client.vsetattr("vset", "item1", {})
    cmd = @client.last_command

    assert_equal "{}", cmd[3]
  end

  def test_vsetattr_with_string
    @client.vsetattr("vset", "item1", '{"custom":"json"}')
    cmd = @client.last_command

    assert_equal '{"custom":"json"}', cmd[3]
  end

  # ============================================================
  # vgetattr
  # ============================================================

  def test_vgetattr_with_result
    @client.next_return = '{"category":"electronics","price":99}'
    result = @client.vgetattr("vset", "item1")

    assert_equal({ "category" => "electronics", "price" => 99 }, result)
    assert_equal %w[VGETATTR vset item1], @client.last_command
  end

  def test_vgetattr_nil_result
    @client.next_return = nil
    result = @client.vgetattr("vset", "nonexistent")

    assert_nil result
  end

  def test_vgetattr_empty_attrs
    @client.next_return = "{}"
    result = @client.vgetattr("vset", "item1")

    assert_nil result
  end

  def test_vgetattr_json_parse_error
    @client.next_return = "not{valid}json"
    result = @client.vgetattr("vset", "item1")

    assert_nil result
  end

  # ============================================================
  # vrandmember
  # ============================================================

  def test_vrandmember_fast_path
    @client.next_return = "item1"
    result = @client.vrandmember("vset")

    assert_equal "item1", result
    assert_equal %w[VRANDMEMBER vset], @client.last_command
  end

  def test_vrandmember_with_count
    @client.next_return = %w[item1 item2 item3]
    result = @client.vrandmember("vset", 3)

    assert_equal %w[item1 item2 item3], result
    assert_equal ["VRANDMEMBER", "vset", 3], @client.last_command
  end

  # ============================================================
  # parse_vsim_response (tested indirectly via vsim)
  # ============================================================

  def test_parse_vsim_response_scores_and_attribs
    @client.next_return = ["e1", "0.9", '{"a":1}', "e2", "0.8", '{"a":2}']
    result = @client.vsim("vset", [1.0], with_scores: true, with_attribs: true)

    assert_instance_of Hash, result
    assert_in_delta 0.9, result["e1"]["score"]
    assert_equal({ "a" => 1 }, result["e1"]["attributes"])
    assert_in_delta 0.8, result["e2"]["score"]
    assert_equal({ "a" => 2 }, result["e2"]["attributes"])
  end

  def test_parse_vsim_response_scores_only
    @client.next_return = ["e1", "0.9", "e2", "0.8"]
    result = @client.vsim("vset", [1.0], with_scores: true)

    assert_instance_of Hash, result
    assert_in_delta 0.9, result["e1"]
    assert_in_delta 0.8, result["e2"]
  end

  def test_parse_vsim_response_attribs_only
    @client.next_return = ["e1", '{"x":1}', "e2", '{"x":2}']
    result = @client.vsim("vset", [1.0], with_attribs: true)

    assert_instance_of Hash, result
    assert_equal({ "x" => 1 }, result["e1"])
    assert_equal({ "x" => 2 }, result["e2"])
  end

  def test_parse_vsim_response_plain
    @client.next_return = %w[e1 e2 e3]
    result = @client.vsim("vset", [1.0])

    assert_equal %w[e1 e2 e3], result
  end

  def test_parse_vsim_response_non_array
    @client.next_return = "not_an_array"
    result = @client.vsim("vset", [1.0])

    assert_equal "not_an_array", result
  end

  def test_parse_vsim_response_non_array_with_scores
    @client.next_return = "not_an_array"
    result = @client.vsim("vset", [1.0], with_scores: true)

    assert_equal "not_an_array", result
  end

  # ============================================================
  # parse_json_attrs (tested indirectly via vsim/vgetattr)
  # ============================================================

  def test_parse_json_attrs_nil_input
    @client.next_return = ["e1", "0.9", nil]
    result = @client.vsim("vset", [1.0], with_scores: true, with_attribs: true)

    assert_nil result["e1"]["attributes"]
  end

  def test_parse_json_attrs_empty_json
    @client.next_return = ["e1", "0.9", "{}"]
    result = @client.vsim("vset", [1.0], with_scores: true, with_attribs: true)

    assert_nil result["e1"]["attributes"]
  end

  def test_parse_json_attrs_valid_json
    @client.next_return = ["e1", "0.9", '{"key":"val"}']
    result = @client.vsim("vset", [1.0], with_scores: true, with_attribs: true)

    assert_equal({ "key" => "val" }, result["e1"]["attributes"])
  end

  def test_parse_json_attrs_invalid_json
    @client.next_return = ["e1", "0.9", "not{json"]
    result = @client.vsim("vset", [1.0], with_scores: true, with_attribs: true)

    assert_nil result["e1"]["attributes"]
  end

  # ============================================================
  # vsim attribs-only path with nil / invalid JSON
  # ============================================================

  def test_vsim_attribs_only_nil_attribs
    @client.next_return = ["e1", nil]
    result = @client.vsim("vset", [1.0], with_attribs: true)

    assert_nil result["e1"]
  end

  def test_vsim_attribs_only_empty_json
    @client.next_return = ["e1", "{}"]
    result = @client.vsim("vset", [1.0], with_attribs: true)

    assert_nil result["e1"]
  end

  def test_vsim_attribs_only_invalid_json
    @client.next_return = ["e1", "bad{json"]
    result = @client.vsim("vset", [1.0], with_attribs: true)

    assert_nil result["e1"]
  end
end
