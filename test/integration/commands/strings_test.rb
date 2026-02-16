# frozen_string_literal: true

require "test_helper"

class StringsCommandsTest < RedisRubyTestCase
  use_testcontainers!

  # INCR / DECR
  def test_incr
    redis.set("test:incr", "10")

    assert_equal 11, redis.incr("test:incr")
    assert_equal 12, redis.incr("test:incr")
  ensure
    redis.del("test:incr")
  end

  def test_incr_creates_key_if_missing
    redis.del("test:incr_new")

    assert_equal 1, redis.incr("test:incr_new")
  ensure
    redis.del("test:incr_new")
  end

  def test_decr
    redis.set("test:decr", "10")

    assert_equal 9, redis.decr("test:decr")
    assert_equal 8, redis.decr("test:decr")
  ensure
    redis.del("test:decr")
  end

  def test_incrby
    redis.set("test:incrby", "10")

    assert_equal 15, redis.incrby("test:incrby", 5)
    assert_equal 10, redis.incrby("test:incrby", -5)
  ensure
    redis.del("test:incrby")
  end

  def test_decrby
    redis.set("test:decrby", "10")

    assert_equal 7, redis.decrby("test:decrby", 3)
  ensure
    redis.del("test:decrby")
  end

  def test_incrbyfloat
    redis.set("test:incrbyfloat", "10.5")
    result = redis.incrbyfloat("test:incrbyfloat", 0.1)

    assert_in_delta 10.6, result.to_f, 0.001
  ensure
    redis.del("test:incrbyfloat")
  end

  # APPEND
  def test_append
    redis.set("test:append", "Hello")
    length = redis.append("test:append", " World")

    assert_equal 11, length
    assert_equal "Hello World", redis.get("test:append")
  ensure
    redis.del("test:append")
  end

  def test_append_creates_key_if_missing
    redis.del("test:append_new")
    length = redis.append("test:append_new", "Hello")

    assert_equal 5, length
    assert_equal "Hello", redis.get("test:append_new")
  ensure
    redis.del("test:append_new")
  end

  # STRLEN
  def test_strlen
    redis.set("test:strlen", "Hello World")

    assert_equal 11, redis.strlen("test:strlen")
  ensure
    redis.del("test:strlen")
  end

  def test_strlen_missing_key
    redis.del("test:strlen_missing")

    assert_equal 0, redis.strlen("test:strlen_missing")
  end

  # GETRANGE / SETRANGE
  def test_getrange
    redis.set("test:getrange", "Hello World")

    assert_equal "World", redis.getrange("test:getrange", 6, 10)
    assert_equal "Hello", redis.getrange("test:getrange", 0, 4)
    assert_equal "World", redis.getrange("test:getrange", -5, -1)
  ensure
    redis.del("test:getrange")
  end

  def test_setrange
    redis.set("test:setrange", "Hello World")
    length = redis.setrange("test:setrange", 6, "Redis")

    assert_equal 11, length
    assert_equal "Hello Redis", redis.get("test:setrange")
  ensure
    redis.del("test:setrange")
  end

  # MGET / MSET
  def test_mget
    redis.set("test:mget1", "value1")
    redis.set("test:mget2", "value2")
    result = redis.mget("test:mget1", "test:mget2", "test:mget_missing")

    assert_equal ["value1", "value2", nil], result
  ensure
    redis.del("test:mget1", "test:mget2")
  end

  def test_mset
    result = redis.mset("test:mset1", "value1", "test:mset2", "value2")

    assert_equal "OK", result
    assert_equal "value1", redis.get("test:mset1")
    assert_equal "value2", redis.get("test:mset2")
  ensure
    redis.del("test:mset1", "test:mset2")
  end

  def test_msetnx
    redis.del("test:msetnx1", "test:msetnx2")

    assert_equal 1, redis.msetnx("test:msetnx1", "value1", "test:msetnx2", "value2")
    # Should fail if any key exists
    assert_equal 0, redis.msetnx("test:msetnx1", "new", "test:msetnx3", "value3")
    assert_equal "value1", redis.get("test:msetnx1") # unchanged
    assert_nil redis.get("test:msetnx3") # not set
  ensure
    redis.del("test:msetnx1", "test:msetnx2", "test:msetnx3")
  end

  # SETNX / SETEX / PSETEX
  def test_setnx
    redis.del("test:setnx")

    assert redis.setnx("test:setnx", "value")
    refute redis.setnx("test:setnx", "other")
    assert_equal "value", redis.get("test:setnx")
  ensure
    redis.del("test:setnx")
  end

  def test_setex
    redis.setex("test:setex", 10, "value")

    assert_equal "value", redis.get("test:setex")
    ttl = redis.ttl("test:setex")

    assert ttl.positive? && ttl <= 10
  ensure
    redis.del("test:setex")
  end

  def test_psetex
    redis.psetex("test:psetex", 10_000, "value")

    assert_equal "value", redis.get("test:psetex")
    pttl = redis.pttl("test:psetex")

    assert pttl.positive? && pttl <= 10_000
  ensure
    redis.del("test:psetex")
  end

  # GETSET (deprecated but still supported)
  def test_getset
    redis.set("test:getset", "old")
    old_value = redis.getset("test:getset", "new")

    assert_equal "old", old_value
    assert_equal "new", redis.get("test:getset")
  ensure
    redis.del("test:getset")
  end

  def test_getset_missing_key
    redis.del("test:getset_missing")
    old_value = redis.getset("test:getset_missing", "value")

    assert_nil old_value
    assert_equal "value", redis.get("test:getset_missing")
  ensure
    redis.del("test:getset_missing")
  end

  # GETDEL / GETEX
  def test_getdel
    redis.set("test:getdel", "value")
    result = redis.getdel("test:getdel")

    assert_equal "value", result
    assert_nil redis.get("test:getdel")
  end

  def test_getex_with_expiration
    redis.set("test:getex", "value")
    result = redis.getex("test:getex", ex: 10)

    assert_equal "value", result
    ttl = redis.ttl("test:getex")

    assert ttl.positive? && ttl <= 10
  ensure
    redis.del("test:getex")
  end

  # Binary data tests
  def test_set_get_binary_data
    binary_value = "\x00\x01\x02\xFF\xFE".b
    redis.set("test:binary", binary_value)

    result = redis.get("test:binary")

    assert_equal binary_value.bytesize, result.bytesize
    assert_equal binary_value, result
  ensure
    redis.del("test:binary")
  end

  def test_append_binary_data
    binary_first = "\x00\x01".b
    binary_second = "\x02\x03".b
    redis.set("test:binary", binary_first)
    redis.append("test:binary", binary_second)

    result = redis.get("test:binary")

    assert_equal (binary_first + binary_second), result
  ensure
    redis.del("test:binary")
  end

  def test_getrange_binary_data
    binary_value = "\x00\x01\x02\x03\x04".b
    redis.set("test:binary", binary_value)

    result = redis.getrange("test:binary", 1, 3)

    assert_equal "\x01\x02\x03".b, result
  ensure
    redis.del("test:binary")
  end

  def test_setrange_binary_data
    binary_value = "\x00\x01\x02\x03\x04".b
    redis.set("test:binary", binary_value)
    redis.setrange("test:binary", 2, "\xFF\xFF".b)

    result = redis.get("test:binary")

    assert_equal "\x00\x01\xFF\xFF\x04".b, result
  ensure
    redis.del("test:binary")
  end

  def test_strlen_binary_data
    binary_value = "\x00\x01\x02".b
    redis.set("test:binary", binary_value)

    assert_equal 3, redis.strlen("test:binary")
  ensure
    redis.del("test:binary")
  end

  # Type coercion tests
  def test_set_get_integer
    redis.set("test:int", 42)

    result = redis.get("test:int")

    assert_equal "42", result
  ensure
    redis.del("test:int")
  end

  def test_set_get_float
    redis.set("test:float", 3.14159)

    result = redis.get("test:float")

    assert_equal "3.14159", result
  ensure
    redis.del("test:float")
  end

  def test_incr_string_representation_of_number
    redis.set("test:incr", "100")

    assert_equal 101, redis.incr("test:incr")
  ensure
    redis.del("test:incr")
  end

  def test_incrbyfloat_string_representation
    redis.set("test:float", "10.5")

    result = redis.incrbyfloat("test:float", "0.5")

    assert_in_delta 11.0, result.to_f, 0.001
  ensure
    redis.del("test:float")
  end

  def test_incr_negative_number
    redis.set("test:incr", "-10")

    assert_equal(-9, redis.incr("test:incr"))
  ensure
    redis.del("test:incr")
  end

  def test_incrby_negative_increment
    redis.set("test:incrby", "10")

    assert_equal 5, redis.incrby("test:incrby", -5)
  ensure
    redis.del("test:incrby")
  end

  # Empty string tests
  def test_set_empty_string
    redis.set("test:empty", "")

    assert_equal "", redis.get("test:empty")
    assert_equal 0, redis.strlen("test:empty")
  ensure
    redis.del("test:empty")
  end

  def test_append_to_empty_string
    redis.set("test:empty", "")
    redis.append("test:empty", "value")

    assert_equal "value", redis.get("test:empty")
  ensure
    redis.del("test:empty")
  end

  # Large value tests
  def test_large_string_value
    large_value = "x" * 100_000
    redis.set("test:large", large_value)

    result = redis.get("test:large")

    assert_equal large_value.length, result.length
    assert_equal large_value, result
  ensure
    redis.del("test:large")
  end

  # Unicode tests
  def test_unicode_string
    unicode_value = "こんにちは世界"
    redis.set("test:unicode", unicode_value)

    result = redis.get("test:unicode")

    # Redis returns binary encoding, force to UTF-8 for comparison
    assert_equal unicode_value, result.force_encoding("UTF-8")
  ensure
    redis.del("test:unicode")
  end

  def test_emoji_string
    emoji_value = "Hello 👋 World 🌍"
    redis.set("test:emoji", emoji_value)

    result = redis.get("test:emoji")

    # Redis returns binary encoding, force to UTF-8 for comparison
    assert_equal emoji_value, result.force_encoding("UTF-8")
  ensure
    redis.del("test:emoji")
  end

  # Edge cases
  def test_setrange_beyond_string_length
    redis.set("test:setrange", "abc")
    redis.setrange("test:setrange", 5, "xyz")

    result = redis.get("test:setrange")

    # Redis pads with null bytes
    assert_equal "abc\x00\x00xyz", result
  ensure
    redis.del("test:setrange")
  end

  def test_getrange_out_of_bounds
    redis.set("test:getrange", "Hello")

    result = redis.getrange("test:getrange", 0, 100)

    assert_equal "Hello", result
  ensure
    redis.del("test:getrange")
  end

  def test_incr_non_numeric_raises
    redis.set("test:incr", "not_a_number")

    assert_raises(RR::CommandError) do
      redis.incr("test:incr")
    end
  ensure
    redis.del("test:incr")
  end
end
