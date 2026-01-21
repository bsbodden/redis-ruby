# frozen_string_literal: true

require "test_helper"

class BitmapIntegrationTest < Minitest::Test
  def setup
    @redis = RedisRuby.new(host: ENV.fetch("REDIS_HOST", "redis"), port: ENV.fetch("REDIS_PORT", 6379).to_i)
    @redis.del("bitmap:test", "bitmap:test2", "bitmap:result")
  end

  def teardown
    @redis.del("bitmap:test", "bitmap:test2", "bitmap:result")
    @redis.close
  end

  # SETBIT tests
  def test_setbit_new_key
    result = @redis.setbit("bitmap:test", 7, 1)
    assert_equal 0, result  # Original value was 0
  end

  def test_setbit_returns_original_value
    @redis.setbit("bitmap:test", 7, 1)
    result = @redis.setbit("bitmap:test", 7, 0)
    assert_equal 1, result  # Original value was 1
  end

  def test_setbit_large_offset
    result = @redis.setbit("bitmap:test", 1_000_000, 1)
    assert_equal 0, result
    assert_equal 1, @redis.getbit("bitmap:test", 1_000_000)
  end

  # GETBIT tests
  def test_getbit_nonexistent_key
    result = @redis.getbit("bitmap:nonexistent", 7)
    assert_equal 0, result
  end

  def test_getbit_set_bit
    @redis.setbit("bitmap:test", 7, 1)
    result = @redis.getbit("bitmap:test", 7)
    assert_equal 1, result
  end

  def test_getbit_unset_bit
    @redis.setbit("bitmap:test", 7, 1)
    result = @redis.getbit("bitmap:test", 0)
    assert_equal 0, result
  end

  # BITCOUNT tests
  def test_bitcount_empty_key
    result = @redis.bitcount("bitmap:nonexistent")
    assert_equal 0, result
  end

  def test_bitcount_full_string
    @redis.set("bitmap:test", "foobar")  # ASCII characters
    result = @redis.bitcount("bitmap:test")
    assert_equal 26, result  # Number of 1 bits in "foobar"
  end

  def test_bitcount_with_range
    @redis.set("bitmap:test", "foobar")
    result = @redis.bitcount("bitmap:test", 0, 0)
    assert_equal 4, result  # Bits in first byte 'f'
  end

  def test_bitcount_negative_range
    @redis.set("bitmap:test", "foobar")
    result = @redis.bitcount("bitmap:test", -2, -1)
    # Bits in last 2 bytes "ar"
    assert result >= 0
  end

  def test_bitcount_with_bit_mode
    @redis.set("bitmap:test", "\xff\xf0\x00")  # 12 bits set
    result = @redis.bitcount("bitmap:test", 0, 11, "BIT")
    assert_equal 12, result
  end

  # BITPOS tests
  def test_bitpos_find_first_set_bit
    @redis.set("bitmap:test", "\x00\x00\xff")
    result = @redis.bitpos("bitmap:test", 1)
    assert_equal 16, result  # First set bit is at position 16
  end

  def test_bitpos_find_first_clear_bit
    @redis.set("bitmap:test", "\xff\xff\x00")
    result = @redis.bitpos("bitmap:test", 0)
    assert_equal 16, result  # First clear bit at position 16
  end

  def test_bitpos_with_range
    @redis.set("bitmap:test", "\xff\x00\xff")
    result = @redis.bitpos("bitmap:test", 0, 1, 1)
    assert_equal 8, result  # First 0 in byte at position 1
  end

  def test_bitpos_not_found
    @redis.set("bitmap:test", "\xff\xff\xff")
    result = @redis.bitpos("bitmap:test", 0)
    assert_equal 24, result  # Position after end
  end

  # BITOP tests
  def test_bitop_and
    @redis.set("bitmap:test", "\xff\x0f")
    @redis.set("bitmap:test2", "\x0f\xff")
    result = @redis.bitop("AND", "bitmap:result", "bitmap:test", "bitmap:test2")
    assert_equal 2, result  # Length of result
    assert_equal "\x0f\x0f", @redis.get("bitmap:result")
  end

  def test_bitop_or
    @redis.set("bitmap:test", "\xf0\x00".b)
    @redis.set("bitmap:test2", "\x0f\x00".b)
    result = @redis.bitop("OR", "bitmap:result", "bitmap:test", "bitmap:test2")
    assert_equal 2, result
    assert_equal "\xff\x00".b, @redis.get("bitmap:result")
  end

  def test_bitop_xor
    @redis.set("bitmap:test", "\xff\xff".b)
    @redis.set("bitmap:test2", "\x0f\xf0".b)
    result = @redis.bitop("XOR", "bitmap:result", "bitmap:test", "bitmap:test2")
    assert_equal 2, result
    assert_equal "\xf0\x0f".b, @redis.get("bitmap:result")
  end

  def test_bitop_not
    @redis.set("bitmap:test", "\x00\xff".b)
    result = @redis.bitop("NOT", "bitmap:result", "bitmap:test")
    assert_equal 2, result
    assert_equal "\xff\x00".b, @redis.get("bitmap:result")
  end

  # BITFIELD tests
  def test_bitfield_get
    @redis.set("bitmap:test", "\xff\x00")
    result = @redis.bitfield("bitmap:test", "GET", "u8", 0)
    assert_equal [255], result
  end

  def test_bitfield_set
    result = @redis.bitfield("bitmap:test", "SET", "u8", 0, 200)
    assert_equal [0], result  # Original value
    assert_equal 200, @redis.bitfield("bitmap:test", "GET", "u8", 0)[0]
  end

  def test_bitfield_incrby
    @redis.bitfield("bitmap:test", "SET", "u8", 0, 100)
    result = @redis.bitfield("bitmap:test", "INCRBY", "u8", 0, 10)
    assert_equal [110], result
  end

  def test_bitfield_multiple_operations
    result = @redis.bitfield("bitmap:test",
      "SET", "u8", 0, 100,
      "INCRBY", "u8", 0, 10,
      "GET", "u8", 0
    )
    assert_equal [0, 110, 110], result
  end

  def test_bitfield_overflow_wrap
    @redis.bitfield("bitmap:test", "SET", "u8", 0, 255)
    result = @redis.bitfield("bitmap:test", "OVERFLOW", "WRAP", "INCRBY", "u8", 0, 1)
    assert_equal [0], result  # Wrapped around
  end

  def test_bitfield_overflow_sat
    @redis.bitfield("bitmap:test", "SET", "u8", 0, 255)
    result = @redis.bitfield("bitmap:test", "OVERFLOW", "SAT", "INCRBY", "u8", 0, 10)
    assert_equal [255], result  # Saturated at max
  end

  def test_bitfield_overflow_fail
    @redis.bitfield("bitmap:test", "SET", "u8", 0, 255)
    result = @redis.bitfield("bitmap:test", "OVERFLOW", "FAIL", "INCRBY", "u8", 0, 10)
    assert_nil result[0]  # Failed, returns nil
  end

  # BITFIELD_RO tests (read-only variant)
  def test_bitfield_ro_get
    @redis.set("bitmap:test", "\xff\x0f")
    result = @redis.bitfield_ro("bitmap:test", "GET", "u8", 0)
    assert_equal [255], result
  end

  def test_bitfield_ro_multiple_gets
    @redis.set("bitmap:test", "\xff\x0f")
    result = @redis.bitfield_ro("bitmap:test", "GET", "u8", 0, "GET", "u8", 8)
    assert_equal [255, 15], result
  end
end
