# frozen_string_literal: true

require "test_helper"

class HashesCommandsTest < RedisRubyTestCase
  use_testcontainers!

  def test_hset_and_hget
    redis.hset("test:hash", "field1", "value1")
    assert_equal "value1", redis.hget("test:hash", "field1")
  ensure
    redis.del("test:hash")
  end

  def test_hset_multiple_fields
    count = redis.hset("test:hash", "f1", "v1", "f2", "v2", "f3", "v3")
    assert_equal 3, count
    assert_equal "v1", redis.hget("test:hash", "f1")
    assert_equal "v2", redis.hget("test:hash", "f2")
  ensure
    redis.del("test:hash")
  end

  def test_hget_missing_field
    redis.hset("test:hash", "field1", "value1")
    assert_nil redis.hget("test:hash", "missing")
  ensure
    redis.del("test:hash")
  end

  def test_hsetnx
    redis.del("test:hash")
    assert_equal 1, redis.hsetnx("test:hash", "field", "value1")
    assert_equal 0, redis.hsetnx("test:hash", "field", "value2")
    assert_equal "value1", redis.hget("test:hash", "field")
  ensure
    redis.del("test:hash")
  end

  def test_hmget
    redis.hset("test:hash", "f1", "v1", "f2", "v2")
    result = redis.hmget("test:hash", "f1", "f2", "f3")
    assert_equal ["v1", "v2", nil], result
  ensure
    redis.del("test:hash")
  end

  def test_hmset
    result = redis.hmset("test:hash", "f1", "v1", "f2", "v2")
    assert_equal "OK", result
    assert_equal "v1", redis.hget("test:hash", "f1")
  ensure
    redis.del("test:hash")
  end

  def test_hgetall
    redis.hset("test:hash", "f1", "v1", "f2", "v2")
    result = redis.hgetall("test:hash")
    assert_equal({ "f1" => "v1", "f2" => "v2" }, result)
  ensure
    redis.del("test:hash")
  end

  def test_hgetall_empty
    redis.del("test:hash")
    result = redis.hgetall("test:hash")
    assert_equal({}, result)
  end

  def test_hdel
    redis.hset("test:hash", "f1", "v1", "f2", "v2", "f3", "v3")
    assert_equal 2, redis.hdel("test:hash", "f1", "f2")
    assert_nil redis.hget("test:hash", "f1")
    assert_equal "v3", redis.hget("test:hash", "f3")
  ensure
    redis.del("test:hash")
  end

  def test_hexists
    redis.hset("test:hash", "field", "value")
    assert_equal 1, redis.hexists("test:hash", "field")
    assert_equal 0, redis.hexists("test:hash", "missing")
  ensure
    redis.del("test:hash")
  end

  def test_hkeys
    redis.hset("test:hash", "f1", "v1", "f2", "v2")
    keys = redis.hkeys("test:hash")
    assert_includes keys, "f1"
    assert_includes keys, "f2"
  ensure
    redis.del("test:hash")
  end

  def test_hvals
    redis.hset("test:hash", "f1", "v1", "f2", "v2")
    vals = redis.hvals("test:hash")
    assert_includes vals, "v1"
    assert_includes vals, "v2"
  ensure
    redis.del("test:hash")
  end

  def test_hlen
    redis.hset("test:hash", "f1", "v1", "f2", "v2", "f3", "v3")
    assert_equal 3, redis.hlen("test:hash")
  ensure
    redis.del("test:hash")
  end

  def test_hstrlen
    redis.hset("test:hash", "field", "hello")
    assert_equal 5, redis.hstrlen("test:hash", "field")
    assert_equal 0, redis.hstrlen("test:hash", "missing")
  ensure
    redis.del("test:hash")
  end

  def test_hincrby
    redis.hset("test:hash", "counter", "10")
    assert_equal 15, redis.hincrby("test:hash", "counter", 5)
    assert_equal 10, redis.hincrby("test:hash", "counter", -5)
  ensure
    redis.del("test:hash")
  end

  def test_hincrby_creates_field
    redis.del("test:hash")
    assert_equal 5, redis.hincrby("test:hash", "counter", 5)
  ensure
    redis.del("test:hash")
  end

  def test_hincrbyfloat
    redis.hset("test:hash", "value", "10.5")
    result = redis.hincrbyfloat("test:hash", "value", 0.1)
    assert_in_delta 10.6, result.to_f, 0.001
  ensure
    redis.del("test:hash")
  end

  def test_hscan
    redis.hset("test:hash", "f1", "v1", "f2", "v2", "f3", "v3")
    cursor, fields = redis.hscan("test:hash", 0)
    assert_kind_of String, cursor
    refute_empty fields
  ensure
    redis.del("test:hash")
  end

  def test_hrandfield
    redis.hset("test:hash", "f1", "v1", "f2", "v2", "f3", "v3")
    field = redis.hrandfield("test:hash")
    assert_includes %w[f1 f2 f3], field
  ensure
    redis.del("test:hash")
  end

  def test_hrandfield_with_count
    redis.hset("test:hash", "f1", "v1", "f2", "v2", "f3", "v3")
    fields = redis.hrandfield("test:hash", count: 2)
    assert_equal 2, fields.length
  ensure
    redis.del("test:hash")
  end
end
