# frozen_string_literal: true

require "test_helper"

class RedisRubyTest < RedisRubyTestCase
  # Use TestContainers when REDIS_URL is not set
  use_testcontainers!

  def test_version
    refute_nil RedisRuby::VERSION
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
end
