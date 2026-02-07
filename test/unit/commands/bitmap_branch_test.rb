# frozen_string_literal: true

require_relative "../unit_test_helper"

class BitmapBranchTest < Minitest::Test
  # ============================================================
  # MockClient includes the Bitmap module and records commands
  # ============================================================

  class MockClient
    include RedisRuby::Commands::Bitmap

    attr_reader :last_command

    def call(*args)
      @last_command = args
      0
    end

    def call_1arg(cmd, a1)
      @last_command = [cmd, a1]
      0
    end

    def call_2args(cmd, a1, a2)
      @last_command = [cmd, a1, a2]
      0
    end

    def call_3args(cmd, a1, a2, a3)
      @last_command = [cmd, a1, a2, a3]
      0
    end
  end

  def setup
    @client = MockClient.new
  end

  # ============================================================
  # setbit
  # ============================================================

  def test_setbit
    result = @client.setbit("mykey", 7, 1)

    assert_equal ["SETBIT", "mykey", 7, 1], @client.last_command
    assert_equal 0, result
  end

  # ============================================================
  # getbit
  # ============================================================

  def test_getbit
    result = @client.getbit("mykey", 7)

    assert_equal ["GETBIT", "mykey", 7], @client.last_command
    assert_equal 0, result
  end

  # ============================================================
  # bitcount branches
  # ============================================================

  def test_bitcount_key_only_fast_path
    result = @client.bitcount("mykey")

    assert_equal %w[BITCOUNT mykey], @client.last_command
    assert_equal 0, result
  end

  def test_bitcount_with_byte_range_fast_path
    result = @client.bitcount("mykey", 0, 1)

    assert_equal ["BITCOUNT", "mykey", 0, 1], @client.last_command
    assert_equal 0, result
  end

  def test_bitcount_with_start_nil_and_stop_nil
    result = @client.bitcount("mykey", nil, nil)

    assert_equal %w[BITCOUNT mykey], @client.last_command
    assert_equal 0, result
  end

  def test_bitcount_with_mode
    result = @client.bitcount("mykey", 0, 7, "BIT")

    assert_equal ["BITCOUNT", "mykey", 0, 7, "BIT"], @client.last_command
    assert_equal 0, result
  end

  def test_bitcount_with_mode_lowercase
    @client.bitcount("mykey", 0, 7, "byte")

    assert_equal ["BITCOUNT", "mykey", 0, 7, "BYTE"], @client.last_command
  end

  def test_bitcount_with_start_and_stop_no_mode_uses_fast_path
    @client.bitcount("mykey", 2, 5, nil)
    # mode is nil, start and stop are present -> fast path call_3args
    assert_equal ["BITCOUNT", "mykey", 2, 5], @client.last_command
  end

  def test_bitcount_with_start_only
    # start provided but stop is nil - goes through general path
    @client.bitcount("mykey", 2, nil)
    # start.nil? is false, stop.nil? is true -> falls through to if mode block
    # mode is nil -> call_3args with start=2, stop=nil
    assert_equal ["BITCOUNT", "mykey", 2, nil], @client.last_command
  end

  # ============================================================
  # bitpos branches
  # ============================================================

  def test_bitpos_no_range_fast_path
    result = @client.bitpos("mykey", 1)

    assert_equal ["BITPOS", "mykey", 1], @client.last_command
    assert_equal 0, result
  end

  def test_bitpos_with_range_no_mode_fast_path
    result = @client.bitpos("mykey", 0, 2, 4)

    assert_equal ["BITPOS", "mykey", 0, 2, 4], @client.last_command
    assert_equal 0, result
  end

  def test_bitpos_nil_start_nil_stop
    @client.bitpos("mykey", 1, nil, nil)

    assert_equal ["BITPOS", "mykey", 1], @client.last_command
  end

  def test_bitpos_with_mode
    @client.bitpos("mykey", 1, 0, 7, "BIT")

    assert_equal ["BITPOS", "mykey", 1, 0, 7, "BIT"], @client.last_command
  end

  def test_bitpos_with_mode_lowercase
    @client.bitpos("mykey", 0, 0, 10, "byte")

    assert_equal ["BITPOS", "mykey", 0, 0, 10, "BYTE"], @client.last_command
  end

  def test_bitpos_start_only_no_stop
    # start is provided, stop is nil -> falls through to general path
    @client.bitpos("mykey", 1, 3, nil)
    cmd = @client.last_command

    assert_equal "BITPOS", cmd[0]
    assert_equal "mykey", cmd[1]
    assert_equal 1, cmd[2]
    assert_equal 3, cmd[3]
  end

  def test_bitpos_start_stop_with_nil_mode
    @client.bitpos("mykey", 1, 0, 10, nil)
    # start && stop && mode.nil? -> true, uses fast path
    assert_equal ["BITPOS", "mykey", 1, 0, 10], @client.last_command
  end

  def test_bitpos_with_start_and_mode_no_stop
    # start provided, stop nil, mode provided -> general path
    @client.bitpos("mykey", 1, 5, nil, "BIT")
    cmd = @client.last_command

    assert_equal "BITPOS", cmd[0]
    assert_includes cmd, 5
    assert_includes cmd, "BIT"
  end

  # ============================================================
  # bitop branches
  # ============================================================

  def test_bitop_single_key_fast_path
    result = @client.bitop("NOT", "result", "key1")

    assert_equal %w[BITOP NOT result key1], @client.last_command
    assert_equal 0, result
  end

  def test_bitop_multiple_keys
    result = @client.bitop("AND", "result", "key1", "key2")

    assert_equal %w[BITOP AND result key1 key2], @client.last_command
    assert_equal 0, result
  end

  def test_bitop_or_multiple_keys
    @client.bitop("OR", "dest", "k1", "k2", "k3")

    assert_equal %w[BITOP OR dest k1 k2 k3], @client.last_command
  end

  def test_bitop_xor
    @client.bitop("XOR", "dest", "k1", "k2")

    assert_equal %w[BITOP XOR dest k1 k2], @client.last_command
  end

  def test_bitop_lowercase_operation
    @client.bitop("and", "result", "k1", "k2")

    assert_equal %w[BITOP AND result k1 k2], @client.last_command
  end

  def test_bitop_lowercase_single_key
    @client.bitop("not", "result", "key1")

    assert_equal %w[BITOP NOT result key1], @client.last_command
  end

  # ============================================================
  # bitfield
  # ============================================================

  def test_bitfield_get
    @client.bitfield("mykey", "GET", "u8", 0)

    assert_equal ["BITFIELD", "mykey", "GET", "u8", 0], @client.last_command
  end

  def test_bitfield_set
    @client.bitfield("mykey", "SET", "u8", 0, 100)

    assert_equal ["BITFIELD", "mykey", "SET", "u8", 0, 100], @client.last_command
  end

  def test_bitfield_incrby
    @client.bitfield("mykey", "INCRBY", "u8", 0, 10)

    assert_equal ["BITFIELD", "mykey", "INCRBY", "u8", 0, 10], @client.last_command
  end

  def test_bitfield_with_overflow
    @client.bitfield("mykey", "OVERFLOW", "SAT", "INCRBY", "u8", 0, 100)

    assert_equal ["BITFIELD", "mykey", "OVERFLOW", "SAT", "INCRBY", "u8", 0, 100], @client.last_command
  end

  def test_bitfield_multiple_subcommands
    @client.bitfield("mykey", "SET", "u8", 0, 100, "INCRBY", "u8", 0, 10)
    cmd = @client.last_command

    assert_equal "BITFIELD", cmd[0]
    assert_equal "mykey", cmd[1]
    assert_includes cmd, "SET"
    assert_includes cmd, "INCRBY"
  end

  # ============================================================
  # bitfield_ro
  # ============================================================

  def test_bitfield_ro_get
    @client.bitfield_ro("mykey", "GET", "u8", 0)

    assert_equal ["BITFIELD_RO", "mykey", "GET", "u8", 0], @client.last_command
  end

  def test_bitfield_ro_multiple_gets
    @client.bitfield_ro("mykey", "GET", "u8", 0, "GET", "u4", 8)
    cmd = @client.last_command

    assert_equal "BITFIELD_RO", cmd[0]
    assert_equal "mykey", cmd[1]
  end
end
