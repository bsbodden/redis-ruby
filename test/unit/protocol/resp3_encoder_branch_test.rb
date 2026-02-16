# frozen_string_literal: true

require_relative "../unit_test_helper"

class RESP3EncoderBranchTest < Minitest::Test
  def setup
    @encoder = RR::Protocol::RESP3Encoder.new
  end

  # ============================================================
  # encode_command - DEL/INCR/DECR/EXISTS fast paths (single-arg)
  # ============================================================

  def test_encode_del_single_key
    result = @encoder.encode_command("DEL", "mykey")

    assert_equal "*2\r\n$3\r\nDEL\r\n$5\r\nmykey\r\n", result
  end

  def test_encode_incr_single_key
    result = @encoder.encode_command("INCR", "counter")

    assert_equal "*2\r\n$4\r\nINCR\r\n$7\r\ncounter\r\n", result
  end

  def test_encode_decr_single_key
    result = @encoder.encode_command("DECR", "counter")

    assert_equal "*2\r\n$4\r\nDECR\r\n$7\r\ncounter\r\n", result
  end

  def test_encode_exists_single_key
    result = @encoder.encode_command("EXISTS", "mykey")

    assert_equal "*2\r\n$6\r\nEXISTS\r\n$5\r\nmykey\r\n", result
  end

  # ============================================================
  # encode_command - hash argument detection branches (argc 0, 1, 2, >2)
  # ============================================================

  def test_encode_command_with_hash_arg_in_first_of_two
    result = @encoder.encode_command("CMD", { a: "1" }, "extra")

    assert_includes result, "a"
    assert_includes result, "1"
    assert_includes result, "extra"
  end

  def test_encode_command_with_hash_arg_in_second_of_two
    result = @encoder.encode_command("CMD", "extra", { b: "2" })

    assert_includes result, "extra"
    assert_includes result, "b"
    assert_includes result, "2"
  end

  def test_encode_command_with_no_hash_two_non_hash_args
    result = @encoder.encode_command("CMD", "arg1", "arg2")

    assert_includes result, "CMD"
    assert_includes result, "arg1"
    assert_includes result, "arg2"
  end

  def test_encode_command_three_or_more_args_with_hash
    result = @encoder.encode_command("CMD", "a", "b", { c: "d" })

    assert_includes result, "CMD"
    assert_includes result, "a"
    assert_includes result, "b"
    assert_includes result, "c"
    assert_includes result, "d"
  end

  def test_encode_command_three_or_more_args_without_hash
    result = @encoder.encode_command("CMD", "a", "b", "c")

    assert_includes result, "CMD"
    assert_includes result, "a"
    assert_includes result, "b"
    assert_includes result, "c"
  end

  # ============================================================
  # encode_command - MGET/MSET edge cases
  # ============================================================

  def test_encode_mget_single_key
    result = @encoder.encode_command("MGET", "key1")

    assert_includes result, "MGET"
    assert_includes result, "key1"
  end

  def test_encode_mset_two_args
    result = @encoder.encode_command("MSET", "k1", "v1")

    assert_includes result, "MSET"
    assert_includes result, "k1"
    assert_includes result, "v1"
  end

  def test_encode_mset_odd_args_falls_through
    # Odd args means argc.even? is false, falls to slow path
    result = @encoder.encode_command("MSET", "k1")

    assert_includes result, "MSET"
    assert_includes result, "k1"
  end

  # ============================================================
  # encode_with_hash - mixed hash and non-hash args
  # ============================================================

  def test_encode_with_hash_mixed_args
    result = @encoder.encode_command("XADD", "stream", { field1: "val1", field2: "val2" })

    assert_includes result, "XADD"
    assert_includes result, "stream"
    assert_includes result, "field1"
    assert_includes result, "val1"
    assert_includes result, "field2"
    assert_includes result, "val2"
  end

  # ============================================================
  # dump_element - nil, Symbol, Integer, Float, other types
  # ============================================================

  def test_encode_command_with_nil_arg
    result = @encoder.encode_command("CMD", "key", nil, "value")

    assert_includes result, "$-1\r\n"
  end

  def test_encode_command_with_symbol_arg
    result = @encoder.encode_command("CMD", :my_symbol)

    assert_includes result, "my_symbol"
  end

  def test_encode_command_with_float_arg
    result = @encoder.encode_command("ZADD", "zset", 1.5, "member")

    assert_includes result, "1.5"
  end

  def test_encode_command_with_integer_arg
    result = @encoder.encode_command("CMD", "key", 42, "value")

    assert_includes result, "42"
  end

  def test_encode_command_with_arbitrary_object
    obj = Object.new
    def obj.to_s = "custom_object"
    result = @encoder.encode_command("CMD", "key", obj)

    assert_includes result, "custom_object"
  end

  # ============================================================
  # dump_array_fast - non-ASCII string args
  # ============================================================

  def test_dump_array_fast_non_ascii_string
    result = @encoder.encode_command("CMD", "key", "value")

    assert_includes result, "value"
    assert_includes result.b, "value"
  end

  # ============================================================
  # encode_pipeline - slow path (non-fast-path commands)
  # ============================================================

  def test_encode_pipeline_unknown_command
    commands = [%w[UNKNOWN arg1]]
    result = @encoder.encode_pipeline(commands)

    assert_includes result, "UNKNOWN"
    assert_includes result, "arg1"
  end

  def test_encode_pipeline_get_wrong_arg_count
    # GET with 3 args hits slow path (size != 2)
    commands = [%w[GET key1 extra]]
    result = @encoder.encode_pipeline(commands)

    assert_includes result, "GET"
    assert_includes result, "key1"
    assert_includes result, "extra"
  end

  def test_encode_pipeline_set_wrong_arg_count
    # SET with 2 args (not 3) hits slow path
    commands = [%w[SET key1]]
    result = @encoder.encode_pipeline(commands)

    assert_includes result, "SET"
  end

  def test_encode_pipeline_hget_wrong_arg_count
    commands = [%w[HGET hash1]]
    result = @encoder.encode_pipeline(commands)

    assert_includes result, "HGET"
  end

  def test_encode_pipeline_hset_wrong_arg_count
    commands = [%w[HSET hash1 field1]]
    result = @encoder.encode_pipeline(commands)

    assert_includes result, "HSET"
  end

  def test_encode_pipeline_lpush_wrong_arg_count
    commands = [%w[LPUSH list1]]
    result = @encoder.encode_pipeline(commands)

    assert_includes result, "LPUSH"
  end

  def test_encode_pipeline_rpush_wrong_arg_count
    commands = [%w[RPUSH list1]]
    result = @encoder.encode_pipeline(commands)

    assert_includes result, "RPUSH"
  end

  def test_encode_pipeline_lpop_wrong_arg_count
    commands = [%w[LPOP list1 2]]
    result = @encoder.encode_pipeline(commands)

    assert_includes result, "LPOP"
  end

  def test_encode_pipeline_rpop_wrong_arg_count
    commands = [%w[RPOP list1 2]]
    result = @encoder.encode_pipeline(commands)

    assert_includes result, "RPOP"
  end

  def test_encode_pipeline_incr_wrong_arg_count
    commands = [["INCR"]]
    result = @encoder.encode_pipeline(commands)

    assert_includes result, "INCR"
  end

  def test_encode_pipeline_decr_wrong_arg_count
    commands = [["DECR"]]
    result = @encoder.encode_pipeline(commands)

    assert_includes result, "DECR"
  end

  def test_encode_pipeline_del_wrong_arg_count
    commands = [%w[DEL k1 k2]]
    result = @encoder.encode_pipeline(commands)

    assert_includes result, "DEL"
  end

  def test_encode_pipeline_exists_wrong_arg_count
    commands = [%w[EXISTS k1 k2]]
    result = @encoder.encode_pipeline(commands)

    assert_includes result, "EXISTS"
  end

  def test_encode_pipeline_expire_wrong_arg_count
    commands = [%w[EXPIRE key]]
    result = @encoder.encode_pipeline(commands)

    assert_includes result, "EXPIRE"
  end

  def test_encode_pipeline_ttl_wrong_arg_count
    commands = [["TTL"]]
    result = @encoder.encode_pipeline(commands)

    assert_includes result, "TTL"
  end

  # ============================================================
  # int_to_s - cache hit vs miss
  # ============================================================

  def test_int_to_s_within_cache_limit
    result = @encoder.encode_command("GET", "x" * 100)
    # Size 100 should be cached
    assert_includes result, "$100\r\n"
  end

  def test_int_to_s_beyond_cache_limit
    large = "x" * 2000
    result = @encoder.encode_command("GET", large)

    assert_includes result, "$2000\r\n"
  end

  # ============================================================
  # Buffer reset on large payloads (pipeline)
  # ============================================================

  def test_pipeline_buffer_reset_when_large
    large_value = "x" * 100_000
    @encoder.encode_pipeline([["SET", "key", large_value]])
    result = @encoder.encode_pipeline([%w[GET small]])

    assert_includes result, "GET"
    assert_includes result, "small"
  end

  # ============================================================
  # dump_string - ASCII vs non-ASCII
  # ============================================================

  def test_encode_bulk_string_ascii
    result = @encoder.encode_bulk_string("hello")

    assert_equal "$5\r\nhello\r\n", result
  end

  def test_encode_bulk_string_non_ascii
    result = @encoder.encode_bulk_string("caf\u00e9")
    # "cafe\u0301" is multi-byte
    assert_includes result.b, "caf"
  end
end
