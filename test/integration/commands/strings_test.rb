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
end
