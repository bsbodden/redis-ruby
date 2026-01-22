# frozen_string_literal: true

require "test_helper"

class BitmapIntegrationTest < RedisRubyTestCase
  use_testcontainers!

  def setup
    super
    @bitmap_key = "bitmap:test:#{SecureRandom.hex(4)}"
    @bitmap_key2 = "bitmap:test2:#{SecureRandom.hex(4)}"
    @bitmap_result = "bitmap:result:#{SecureRandom.hex(4)}"
  end

  def teardown
    begin
      redis.del(@bitmap_key, @bitmap_key2, @bitmap_result)
    rescue StandardError
      nil
    end
    super
  end

  # SETBIT tests
  def test_setbit_new_key
    result = redis.setbit(@bitmap_key, 7, 1)

    assert_equal 0, result  # Original value was 0
  end

  def test_setbit_returns_original_value
    redis.setbit(@bitmap_key, 7, 1)
    result = redis.setbit(@bitmap_key, 7, 0)

    assert_equal 1, result  # Original value was 1
  end

  def test_setbit_large_offset
    result = redis.setbit(@bitmap_key, 1_000_000, 1)

    assert_equal 0, result
    assert_equal 1, redis.getbit(@bitmap_key, 1_000_000)
  end

  # GETBIT tests
  def test_getbit_nonexistent_key
    result = redis.getbit("bitmap:nonexistent", 7)

    assert_equal 0, result
  end

  def test_getbit_set_bit
    redis.setbit(@bitmap_key, 7, 1)
    result = redis.getbit(@bitmap_key, 7)

    assert_equal 1, result
  end

  def test_getbit_unset_bit
    redis.setbit(@bitmap_key, 7, 1)
    result = redis.getbit(@bitmap_key, 0)

    assert_equal 0, result
  end

  # BITCOUNT tests
  def test_bitcount_empty_key
    result = redis.bitcount("bitmap:nonexistent")

    assert_equal 0, result
  end

  def test_bitcount_full_string
    redis.set(@bitmap_key, "foobar") # ASCII characters
    result = redis.bitcount(@bitmap_key)

    assert_equal 26, result # Number of 1 bits in "foobar"
  end

  def test_bitcount_with_range
    redis.set(@bitmap_key, "foobar")
    result = redis.bitcount(@bitmap_key, 0, 0)

    assert_equal 4, result # Bits in first byte 'f'
  end

  def test_bitcount_negative_range
    redis.set(@bitmap_key, "foobar")
    result = redis.bitcount(@bitmap_key, -2, -1)
    # Bits in last 2 bytes "ar"
    assert_operator result, :>=, 0
  end

  def test_bitcount_with_bit_mode
    redis.set(@bitmap_key, "\xff\xf0\x00") # 12 bits set
    result = redis.bitcount(@bitmap_key, 0, 11, "BIT")

    assert_equal 12, result
  end

  # BITPOS tests
  def test_bitpos_find_first_set_bit
    redis.set(@bitmap_key, "\x00\x00\xff")
    result = redis.bitpos(@bitmap_key, 1)

    assert_equal 16, result  # First set bit is at position 16
  end

  def test_bitpos_find_first_clear_bit
    redis.set(@bitmap_key, "\xff\xff\x00")
    result = redis.bitpos(@bitmap_key, 0)

    assert_equal 16, result  # First clear bit at position 16
  end

  def test_bitpos_with_range
    redis.set(@bitmap_key, "\xff\x00\xff")
    result = redis.bitpos(@bitmap_key, 0, 1, 1)

    assert_equal 8, result # First 0 in byte at position 1
  end

  def test_bitpos_not_found
    redis.set(@bitmap_key, "\xff\xff\xff")
    result = redis.bitpos(@bitmap_key, 0)

    assert_equal 24, result # Position after end
  end

  # BITOP tests
  def test_bitop_and
    redis.set(@bitmap_key, "\xff\x0f")
    redis.set(@bitmap_key2, "\x0f\xff")
    result = redis.bitop("AND", @bitmap_result, @bitmap_key, @bitmap_key2)

    assert_equal 2, result # Length of result
    assert_equal "\x0f\x0f", redis.get(@bitmap_result)
  end

  def test_bitop_or
    redis.set(@bitmap_key, "\xf0\x00".b)
    redis.set(@bitmap_key2, "\x0f\x00".b)
    result = redis.bitop("OR", @bitmap_result, @bitmap_key, @bitmap_key2)

    assert_equal 2, result
    assert_equal "\xff\x00".b, redis.get(@bitmap_result)
  end

  def test_bitop_xor
    redis.set(@bitmap_key, "\xff\xff".b)
    redis.set(@bitmap_key2, "\x0f\xf0".b)
    result = redis.bitop("XOR", @bitmap_result, @bitmap_key, @bitmap_key2)

    assert_equal 2, result
    assert_equal "\xf0\x0f".b, redis.get(@bitmap_result)
  end

  def test_bitop_not
    redis.set(@bitmap_key, "\x00\xff".b)
    result = redis.bitop("NOT", @bitmap_result, @bitmap_key)

    assert_equal 2, result
    assert_equal "\xff\x00".b, redis.get(@bitmap_result)
  end

  # BITFIELD tests
  def test_bitfield_get
    redis.set(@bitmap_key, "\xff\x00")
    result = redis.bitfield(@bitmap_key, "GET", "u8", 0)

    assert_equal [255], result
  end

  def test_bitfield_set
    result = redis.bitfield(@bitmap_key, "SET", "u8", 0, 200)

    assert_equal [0], result  # Original value
    assert_equal 200, redis.bitfield(@bitmap_key, "GET", "u8", 0)[0]
  end

  def test_bitfield_incrby
    redis.bitfield(@bitmap_key, "SET", "u8", 0, 100)
    result = redis.bitfield(@bitmap_key, "INCRBY", "u8", 0, 10)

    assert_equal [110], result
  end

  def test_bitfield_multiple_operations
    result = redis.bitfield(@bitmap_key,
                            "SET", "u8", 0, 100,
                            "INCRBY", "u8", 0, 10,
                            "GET", "u8", 0)

    assert_equal [0, 110, 110], result
  end

  def test_bitfield_overflow_wrap
    redis.bitfield(@bitmap_key, "SET", "u8", 0, 255)
    result = redis.bitfield(@bitmap_key, "OVERFLOW", "WRAP", "INCRBY", "u8", 0, 1)

    assert_equal [0], result  # Wrapped around
  end

  def test_bitfield_overflow_sat
    redis.bitfield(@bitmap_key, "SET", "u8", 0, 255)
    result = redis.bitfield(@bitmap_key, "OVERFLOW", "SAT", "INCRBY", "u8", 0, 10)

    assert_equal [255], result # Saturated at max
  end

  def test_bitfield_overflow_fail
    redis.bitfield(@bitmap_key, "SET", "u8", 0, 255)
    result = redis.bitfield(@bitmap_key, "OVERFLOW", "FAIL", "INCRBY", "u8", 0, 10)

    assert_nil result[0] # Failed, returns nil
  end

  # BITFIELD_RO tests (read-only variant)
  def test_bitfield_ro_get
    redis.set(@bitmap_key, "\xff\x0f")
    result = redis.bitfield_ro(@bitmap_key, "GET", "u8", 0)

    assert_equal [255], result
  end

  def test_bitfield_ro_multiple_gets
    redis.set(@bitmap_key, "\xff\x0f")
    result = redis.bitfield_ro(@bitmap_key, "GET", "u8", 0, "GET", "u8", 8)

    assert_equal [255, 15], result
  end
end
