# frozen_string_literal: true

require "test_helper"

class RedisRubyTest < RedisRubyTestCase
  # Use TestContainers when REDIS_URL is not set
  use_testcontainers!

  def test_version
    refute_nil RR::VERSION
  end

  def test_ping
    assert_equal "PONG", redis.ping
  end

  def test_set_and_get
    redis.set("test:key", "hello")

    assert_equal "hello", redis.get("test:key")
  ensure
    redis.del("test:key")
  end

  def test_set_with_expiration
    redis.set("test:expiring", "value", ex: 10)

    assert_equal "value", redis.get("test:expiring")
  ensure
    redis.del("test:expiring")
  end

  def test_set_nx
    redis.del("test:nx")

    assert_equal "OK", redis.set("test:nx", "first", nx: true)
    assert_nil redis.set("test:nx", "second", nx: true)
    assert_equal "first", redis.get("test:nx")
  ensure
    redis.del("test:nx")
  end

  def test_set_xx
    redis.del("test:xx")

    assert_nil redis.set("test:xx", "value", xx: true)
    redis.set("test:xx", "first")

    assert_equal "OK", redis.set("test:xx", "second", xx: true)
    assert_equal "second", redis.get("test:xx")
  ensure
    redis.del("test:xx")
  end

  def test_del
    redis.set("test:del1", "value1")
    redis.set("test:del2", "value2")

    assert_equal 2, redis.del("test:del1", "test:del2")
    assert_nil redis.get("test:del1")
    assert_nil redis.get("test:del2")
  end

  def test_exists
    redis.set("test:exists", "value")

    assert_equal 1, redis.exists("test:exists")
    assert_equal 0, redis.exists("test:nonexistent")
  ensure
    redis.del("test:exists")
  end

  def test_get_nonexistent_key
    assert_nil redis.get("test:definitely:does:not:exist")
  end

  # SET with EXAT option (absolute Unix timestamp in seconds, Redis 6.2+)
  def test_set_exat
    future_time = Time.now.to_i + 60
    redis.set("test:exat", "value", exat: future_time)

    assert_equal "value", redis.get("test:exat")
    ttl = redis.ttl("test:exat")

    assert ttl.positive? && ttl <= 60
  ensure
    redis.del("test:exat")
  end

  # SET with PXAT option (absolute Unix timestamp in milliseconds, Redis 6.2+)
  def test_set_pxat
    key = "test:pxat:#{SecureRandom.hex(8)}"
    future_time = (Time.now.to_f * 1000).to_i + 60_000
    redis.set(key, "value", pxat: future_time)

    assert_equal "value", redis.get(key)
    pttl = redis.pttl(key)

    assert pttl.positive? && pttl <= 60_000
  ensure
    redis.del(key)
  end

  # SET with KEEPTTL option (Redis 6.0+)
  def test_set_keepttl
    redis.set("test:keepttl", "first", ex: 1000)
    original_ttl = redis.ttl("test:keepttl")

    redis.set("test:keepttl", "second", keepttl: true)

    assert_equal "second", redis.get("test:keepttl")
    new_ttl = redis.ttl("test:keepttl")

    # TTL should be preserved (within tolerance)
    assert_predicate new_ttl, :positive?
    assert_operator new_ttl, :<=, original_ttl
  ensure
    redis.del("test:keepttl")
  end

  def test_set_without_keepttl_removes_ttl
    redis.set("test:keepttl", "first", ex: 1000)
    redis.set("test:keepttl", "second")

    assert_equal "second", redis.get("test:keepttl")
    # Without KEEPTTL, TTL should be removed (-1 means no expiry)
    assert_equal(-1, redis.ttl("test:keepttl"))
  ensure
    redis.del("test:keepttl")
  end

  # SET with GET option (Redis 6.2+)
  def test_set_get_returns_old_value
    redis.set("test:setget", "old_value")

    result = redis.set("test:setget", "new_value", get: true)

    assert_equal "old_value", result
    assert_equal "new_value", redis.get("test:setget")
  ensure
    redis.del("test:setget")
  end

  def test_set_get_returns_nil_for_missing_key
    redis.del("test:setget")

    result = redis.set("test:setget", "value", get: true)

    assert_nil result
    assert_equal "value", redis.get("test:setget")
  ensure
    redis.del("test:setget")
  end

  def test_set_get_with_nx
    redis.del("test:setget")

    # First set with NX + GET should return nil and set the value
    result = redis.set("test:setget", "first", nx: true, get: true)

    assert_nil result
    assert_equal "first", redis.get("test:setget")

    # Second set with NX + GET should return old value but not update
    result = redis.set("test:setget", "second", nx: true, get: true)

    assert_equal "first", result
    assert_equal "first", redis.get("test:setget")
  ensure
    redis.del("test:setget")
  end

  # SET with PX option (milliseconds)
  def test_set_px
    redis.set("test:px", "value", px: 10_000)

    assert_equal "value", redis.get("test:px")
    pttl = redis.pttl("test:px")

    assert pttl.positive? && pttl <= 10_000
  ensure
    redis.del("test:px")
  end

  # Combined options
  def test_set_xx_with_expiration
    redis.set("test:combined", "first")
    redis.set("test:combined", "second", xx: true, ex: 100)

    assert_equal "second", redis.get("test:combined")
    ttl = redis.ttl("test:combined")

    assert ttl.positive? && ttl <= 100
  ensure
    redis.del("test:combined")
  end
end
