# frozen_string_literal: true

require_relative "../unit_test_helper"

class RESP3EncoderComprehensiveTest < Minitest::Test
  def setup
    @encoder = RR::Protocol::RESP3Encoder.new
  end

  # ============================================================
  # Fast path command encoding tests
  # ============================================================

  def test_encode_get_fast_path
    result = @encoder.encode_command("GET", "mykey")

    assert_equal "*2\r\n$3\r\nGET\r\n$5\r\nmykey\r\n", result
  end

  def test_encode_set_fast_path
    result = @encoder.encode_command("SET", "mykey", "myvalue")

    assert_equal "*3\r\n$3\r\nSET\r\n$5\r\nmykey\r\n$7\r\nmyvalue\r\n", result
  end

  def test_encode_hget_fast_path
    result = @encoder.encode_command("HGET", "myhash", "field1")

    assert_equal "*3\r\n$4\r\nHGET\r\n$6\r\nmyhash\r\n$6\r\nfield1\r\n", result
  end

  def test_encode_hset_fast_path
    result = @encoder.encode_command("HSET", "myhash", "field1", "value1")

    assert_equal "*4\r\n$4\r\nHSET\r\n$6\r\nmyhash\r\n$6\r\nfield1\r\n$6\r\nvalue1\r\n", result
  end

  def test_encode_hdel_fast_path
    result = @encoder.encode_command("HDEL", "myhash", "field1")

    assert_equal "*3\r\n$4\r\nHDEL\r\n$6\r\nmyhash\r\n$6\r\nfield1\r\n", result
  end

  def test_encode_lpush_fast_path
    result = @encoder.encode_command("LPUSH", "mylist", "value1")

    assert_equal "*3\r\n$5\r\nLPUSH\r\n$6\r\nmylist\r\n$6\r\nvalue1\r\n", result
  end

  def test_encode_rpush_fast_path
    result = @encoder.encode_command("RPUSH", "mylist", "value1")

    assert_equal "*3\r\n$5\r\nRPUSH\r\n$6\r\nmylist\r\n$6\r\nvalue1\r\n", result
  end

  def test_encode_lpop_fast_path
    result = @encoder.encode_command("LPOP", "mylist")

    assert_equal "*2\r\n$4\r\nLPOP\r\n$6\r\nmylist\r\n", result
  end

  def test_encode_rpop_fast_path
    result = @encoder.encode_command("RPOP", "mylist")

    assert_equal "*2\r\n$4\r\nRPOP\r\n$6\r\nmylist\r\n", result
  end

  def test_encode_expire_fast_path
    result = @encoder.encode_command("EXPIRE", "mykey", 60)

    assert_equal "*3\r\n$6\r\nEXPIRE\r\n$5\r\nmykey\r\n$2\r\n60\r\n", result
  end

  def test_encode_ttl_fast_path
    result = @encoder.encode_command("TTL", "mykey")

    assert_equal "*2\r\n$3\r\nTTL\r\n$5\r\nmykey\r\n", result
  end

  def test_encode_mget_fast_path
    result = @encoder.encode_command("MGET", "key1", "key2", "key3")

    assert_includes result, "MGET"
    assert_includes result, "key1"
    assert_includes result, "key2"
    assert_includes result, "key3"
  end

  def test_encode_mset_fast_path
    result = @encoder.encode_command("MSET", "key1", "val1", "key2", "val2")

    assert_includes result, "MSET"
    assert_includes result, "key1"
    assert_includes result, "val1"
    assert_includes result, "key2"
    assert_includes result, "val2"
  end
  # ============================================================
  # Hash argument encoding tests
  # ============================================================

  def test_encode_command_with_hash_arg_first_position
    result = @encoder.encode_command("HSET", { field1: "value1", field2: "value2" })

    assert_includes result, "field1"
    assert_includes result, "value1"
    assert_includes result, "field2"
    assert_includes result, "value2"
  end

  def test_encode_command_with_hash_arg_second_position
    result = @encoder.encode_command("HMSET", "myhash", { field1: "value1" })

    assert_includes result, "myhash"
    assert_includes result, "field1"
    assert_includes result, "value1"
  end

  def test_encode_command_with_hash_in_multiple_args
    # Test branch where argc > 2 and needs to check all args for Hash
    result = @encoder.encode_command("SOMECOMMAND", "arg1", "arg2", { opt: "val" })

    assert_includes result, "SOMECOMMAND"
    assert_includes result, "arg1"
    assert_includes result, "arg2"
    assert_includes result, "opt"
    assert_includes result, "val"
  end

  def test_encode_command_no_hash_args_zero_args
    result = @encoder.encode_command("PING")

    assert_equal "*1\r\n$4\r\nPING\r\n", result
  end

  def test_encode_command_no_hash_args_one_arg
    result = @encoder.encode_command("ECHO", "hello")

    assert_equal "*2\r\n$4\r\nECHO\r\n$5\r\nhello\r\n", result
  end

  def test_encode_command_no_hash_args_two_args
    result = @encoder.encode_command("GETEX", "key", "EX")

    assert_includes result, "GETEX"
    assert_includes result, "key"
    assert_includes result, "EX"
  end

  def test_encode_command_no_hash_args_many_args
    result = @encoder.encode_command("ZADD", "zset", "NX", "1", "member1", "2", "member2")

    assert_includes result, "ZADD"
    assert_includes result, "zset"
    assert_includes result, "member1"
    assert_includes result, "member2"
  end
end

class RESP3EncoderComprehensiveTestPart2 < Minitest::Test
  def setup
    @encoder = RR::Protocol::RESP3Encoder.new
  end

  # ============================================================
  # Fast path command encoding tests
  # ============================================================

  # ============================================================
  # Pipeline encoding tests
  # ============================================================

  def test_encode_pipeline_with_get_commands
    commands = [%w[GET key1], %w[GET key2]]
    result = @encoder.encode_pipeline(commands)

    assert_includes result, "GET"
    assert_includes result, "key1"
    assert_includes result, "key2"
  end

  def test_encode_pipeline_with_set_commands
    commands = [[" key1", "val1"], ["SET", "key2", "val2"]]
    result = @encoder.encode_pipeline(commands)

    assert_includes result, "SET"
  end

  def test_encode_pipeline_with_hget_commands
    commands = [%w[HGET hash1 field1], %w[HGET hash2 field2]]
    result = @encoder.encode_pipeline(commands)

    assert_includes result, "HGET"
    assert_includes result, "hash1"
    assert_includes result, "field1"
  end

  def test_encode_pipeline_with_hset_commands
    commands = [%w[HSET hash1 field1 val1]]
    result = @encoder.encode_pipeline(commands)

    assert_includes result, "HSET"
  end

  def test_encode_pipeline_with_lpush_commands
    commands = [%w[LPUSH list1 val1]]
    result = @encoder.encode_pipeline(commands)

    assert_includes result, "LPUSH"
  end

  def test_encode_pipeline_with_rpush_commands
    commands = [%w[RPUSH list1 val1]]
    result = @encoder.encode_pipeline(commands)

    assert_includes result, "RPUSH"
  end

  def test_encode_pipeline_with_lpop_commands
    commands = [%w[LPOP list1]]
    result = @encoder.encode_pipeline(commands)

    assert_includes result, "LPOP"
  end

  def test_encode_pipeline_with_rpop_commands
    commands = [%w[RPOP list1]]
    result = @encoder.encode_pipeline(commands)

    assert_includes result, "RPOP"
  end

  def test_encode_pipeline_with_incr_commands
    commands = [%w[INCR counter]]
    result = @encoder.encode_pipeline(commands)

    assert_includes result, "INCR"
    assert_includes result, "counter"
  end

  def test_encode_pipeline_with_decr_commands
    commands = [%w[DECR counter]]
    result = @encoder.encode_pipeline(commands)

    assert_includes result, "DECR"
    assert_includes result, "counter"
  end

  def test_encode_pipeline_with_del_commands
    commands = [%w[DEL key1]]
    result = @encoder.encode_pipeline(commands)

    assert_includes result, "DEL"
    assert_includes result, "key1"
  end

  def test_encode_pipeline_with_exists_commands
    commands = [%w[EXISTS key1]]
    result = @encoder.encode_pipeline(commands)

    assert_includes result, "EXISTS"
    assert_includes result, "key1"
  end

  def test_encode_pipeline_with_expire_commands
    commands = [%w[EXPIRE key1 60]]
    result = @encoder.encode_pipeline(commands)

    assert_includes result, "EXPIRE"
  end

  def test_encode_pipeline_with_ttl_commands
    commands = [%w[TTL key1]]
    result = @encoder.encode_pipeline(commands)

    assert_includes result, "TTL"
    assert_includes result, "key1"
  end

  def test_encode_pipeline_with_non_fast_path_commands
    commands = [%w[ZADD zset 1 member1], %w[LPUSH list a b c]]
    result = @encoder.encode_pipeline(commands)

    assert_includes result, "ZADD"
    assert_includes result, "LPUSH"
  end

  def test_encode_pipeline_with_hash_arguments
    commands = [["HMSET", "hash", { field1: "val1" }]]
    result = @encoder.encode_pipeline(commands)

    assert_includes result, "HMSET"
    assert_includes result, "field1"
    assert_includes result, "val1"
  end
  # ============================================================
  # Bulk string encoding tests
  # ============================================================

  def test_encode_bulk_string_with_symbol
    result = @encoder.encode_bulk_string(:mysymbol)

    assert_equal "$8\r\nmysymbol\r\n", result
  end

  def test_encode_bulk_string_with_integer
    result = @encoder.encode_bulk_string(42)

    assert_equal "$2\r\n42\r\n", result
  end

  def test_encode_bulk_string_with_float
    result = @encoder.encode_bulk_string(3.14)

    assert_equal "$4\r\n3.14\r\n", result
  end

  def test_encode_bulk_string_with_nil
    result = @encoder.encode_bulk_string(nil)

    assert_equal "$-1\r\n", result
  end

  def test_encode_bulk_string_with_empty_string
    result = @encoder.encode_bulk_string("")

    assert_equal "$0\r\n\r\n", result
  end

  def test_encode_bulk_string_with_large_string
    # Test size beyond cache limit (1024)
    large_string = "x" * 2000
    result = @encoder.encode_bulk_string(large_string)

    assert_includes result, "$2000\r\n"
    assert_includes result, large_string
  end

  def test_encode_bulk_string_with_size_at_cache_boundary
    # Test exactly at cache limit
    boundary_string = "x" * 1024
    result = @encoder.encode_bulk_string(boundary_string)

    assert_includes result, "$1024\r\n"
  end
end

class RESP3EncoderComprehensiveTestPart3 < Minitest::Test
  def setup
    @encoder = RR::Protocol::RESP3Encoder.new
  end

  # ============================================================
  # Fast path command encoding tests
  # ============================================================

  # ============================================================
  # Buffer management tests
  # ============================================================

  def test_buffer_reset_when_large
    # Encode a very large command to grow the buffer
    large_value = "x" * 100_000
    @encoder.encode_command("SET", "key", large_value)

    # Next encode should reset buffer
    result = @encoder.encode_command("GET", "small")

    assert_equal "*2\r\n$3\r\nGET\r\n$5\r\nsmall\r\n", result
  end

  def test_multiple_encodes_reuse_buffer
    result1 = @encoder.encode_command("GET", "key1").dup
    result2 = @encoder.encode_command("GET", "key2").dup

    assert_equal "*2\r\n$3\r\nGET\r\n$4\r\nkey1\r\n", result1
    assert_equal "*2\r\n$3\r\nGET\r\n$4\r\nkey2\r\n", result2
  end
  # ============================================================
  # Data type encoding tests
  # ============================================================

  def test_encode_command_with_symbol_args
    result = @encoder.encode_command("SET", :mykey, :myvalue)

    assert_includes result, "mykey"
    assert_includes result, "myvalue"
  end

  def test_encode_command_with_integer_args
    result = @encoder.encode_command("INCRBY", "counter", 10)

    assert_includes result, "counter"
    assert_includes result, "10"
  end

  def test_encode_command_with_float_args
    result = @encoder.encode_command("INCRBYFLOAT", "counter", 1.5)

    assert_includes result, "counter"
    assert_includes result, "1.5"
  end

  def test_encode_command_with_mixed_types
    result = @encoder.encode_command("ZADD", "zset", 1.5, "member", 2, :another)

    assert_includes result, "ZADD"
    assert_includes result, "zset"
    assert_includes result, "1.5"
    assert_includes result, "member"
    assert_includes result, "2"
    assert_includes result, "another"
  end
  # ============================================================
  # Edge cases
  # ============================================================

  def test_encode_command_with_special_characters
    result = @encoder.encode_command("SET", "key", "value\twith\ttabs")

    assert_includes result, "value\twith\ttabs"
  end

  def test_encode_command_with_newlines_in_value
    result = @encoder.encode_command("SET", "key", "line1\nline2")

    assert_includes result, "line1\nline2"
  end

  def test_encode_command_with_crlf_in_value
    result = @encoder.encode_command("SET", "key", "line1\r\nline2")

    assert_includes result, "line1\r\nline2"
  end

  def test_encode_command_with_unicode
    result = @encoder.encode_command("SET", "key", "")

    assert_includes result, ""
  end

  def test_encode_command_with_binary_data
    binary = "\x00\x01\x02\xFF".b
    result = @encoder.encode_command("SET", "key", binary)

    assert_includes result.b, binary
  end

  def test_encode_pipeline_empty
    result = @encoder.encode_pipeline([])

    assert_equal "", result
  end

  def test_encode_pipeline_single_command
    result = @encoder.encode_pipeline([["PING"]])

    assert_includes result, "PING"
  end

  def test_encode_pipeline_many_commands
    commands = Array.new(100) { |i| ["SET", "key#{i}", "val#{i}"] }
    result = @encoder.encode_pipeline(commands)

    assert_includes result, "key0"
    assert_includes result, "key99"
  end
end
