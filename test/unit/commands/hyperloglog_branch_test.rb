# frozen_string_literal: true

require_relative "../unit_test_helper"

# MockClient that includes HyperLogLog module
class HyperLogLogMockClient
  include RR::Commands::HyperLogLog

  attr_accessor :last_call, :last_call_1arg, :last_call_2args,
                :call_return_value, :call_1arg_return_value, :call_2arg_return_value

  def initialize
    @last_call = nil
    @last_call_1arg = nil
    @last_call_2args = nil
    @call_return_value = nil
    @call_1arg_return_value = nil
    @call_2arg_return_value = nil
  end

  def call(command, *args)
    @last_call = [command, *args]
    @call_return_value
  end

  def call_1arg(command, arg)
    @last_call_1arg = [command, arg]
    @call_1arg_return_value
  end

  def call_2args(command, arg1, arg2)
    @last_call_2args = [command, arg1, arg2]
    @call_2arg_return_value
  end
end

class HyperLogLogBranchTest < Minitest::Test
  def setup
    @client = HyperLogLogMockClient.new
  end

  # ============================================================
  # pfadd - single element (fast path) and multiple elements
  # ============================================================

  def test_pfadd_single_element_fast_path
    @client.call_2arg_return_value = 1
    result = @client.pfadd("hll", "elem1")

    assert_equal %w[PFADD hll elem1], @client.last_call_2args
    assert_equal 1, result
    # Verify slow path was NOT used
    assert_nil @client.last_call
  end

  def test_pfadd_multiple_elements_slow_path
    @client.call_return_value = 1
    result = @client.pfadd("hll", "a", "b", "c")

    assert_equal %w[PFADD hll a b c], @client.last_call
    assert_equal 1, result
  end

  def test_pfadd_returns_zero_no_change
    @client.call_2arg_return_value = 0
    result = @client.pfadd("hll", "elem1")

    assert_equal 0, result
  end

  def test_pfadd_no_elements
    @client.call_return_value = 0
    result = @client.pfadd("hll")

    assert_equal %w[PFADD hll], @client.last_call
    assert_equal 0, result
  end

  # ============================================================
  # pfcount - single key (fast path) and multiple keys
  # ============================================================

  def test_pfcount_single_key_fast_path
    @client.call_1arg_return_value = 42
    result = @client.pfcount("hll")

    assert_equal %w[PFCOUNT hll], @client.last_call_1arg
    assert_equal 42, result
    assert_nil @client.last_call
  end

  def test_pfcount_multiple_keys_slow_path
    @client.call_return_value = 100
    result = @client.pfcount("hll1", "hll2")

    assert_equal %w[PFCOUNT hll1 hll2], @client.last_call
    assert_equal 100, result
  end

  def test_pfcount_returns_zero
    @client.call_1arg_return_value = 0
    result = @client.pfcount("empty_hll")

    assert_equal 0, result
  end

  # ============================================================
  # pfmerge - single source (fast path) and multiple sources
  # ============================================================

  def test_pfmerge_single_source_fast_path
    @client.call_2arg_return_value = "OK"
    result = @client.pfmerge("dest", "src1")

    assert_equal %w[PFMERGE dest src1], @client.last_call_2args
    assert_equal "OK", result
    assert_nil @client.last_call
  end

  def test_pfmerge_multiple_sources_slow_path
    @client.call_return_value = "OK"
    result = @client.pfmerge("dest", "src1", "src2", "src3")

    assert_equal %w[PFMERGE dest src1 src2 src3], @client.last_call
    assert_equal "OK", result
  end

  # ============================================================
  # Frozen command constants
  # ============================================================

  def test_frozen_command_constants
    assert_equal "PFADD", RR::Commands::HyperLogLog::CMD_PFADD
    assert_equal "PFCOUNT", RR::Commands::HyperLogLog::CMD_PFCOUNT
    assert_equal "PFMERGE", RR::Commands::HyperLogLog::CMD_PFMERGE
  end
end
