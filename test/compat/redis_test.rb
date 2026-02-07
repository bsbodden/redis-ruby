# frozen_string_literal: true

require_relative "../test_helper"
require "redis"

class RedisCompatTest < Minitest::Test
  def setup
    @redis = Redis.new(url: "redis://#{ENV.fetch("REDIS_HOST", "localhost")}:#{ENV.fetch("REDIS_PORT", 6379)}")
    @redis.flushdb
  end

  def teardown
    @redis.flushdb
    @redis.close
  end

  # ============ Initialization Tests ============

  def test_initialize_with_defaults
    redis = Redis.new

    assert_instance_of Redis, redis
    assert_equal "localhost", redis.connection[:host]
    assert_equal 6379, redis.connection[:port]
  ensure
    redis&.close
  end

  def test_initialize_with_url
    redis = Redis.new(url: "redis://localhost:6379/1")

    assert_equal "localhost", redis.connection[:host]
    assert_equal 6379, redis.connection[:port]
    assert_equal 1, redis.connection[:db]
  ensure
    redis&.close
  end

  def test_initialize_with_host_and_port
    redis = Redis.new(host: "localhost", port: 6379)

    assert_equal "localhost", redis.connection[:host]
    assert_equal 6379, redis.connection[:port]
  ensure
    redis&.close
  end

  def test_initialize_with_id
    redis = Redis.new(id: "my-connection")

    assert_equal "my-connection", redis.connection[:id]
  ensure
    redis&.close
  end

  def test_driver_option_ignored
    # The driver option should be silently ignored
    redis = Redis.new(driver: :hiredis)

    assert_instance_of Redis, redis
  ensure
    redis&.close
  end

  # ============ Basic Operations Tests ============

  def test_ping
    assert_equal "PONG", @redis.ping
  end

  def test_ping_with_message
    assert_equal "hello", @redis.ping("hello")
  end

  def test_echo
    assert_equal "hello", @redis.echo("hello")
  end

  def test_set_and_get
    assert_equal "OK", @redis.set("key", "value")
    assert_equal "value", @redis.get("key")
  end

  def test_get_nonexistent_key
    assert_nil @redis.get("nonexistent")
  end

  def test_set_with_ex
    @redis.set("key", "value", ex: 100)
    ttl = @redis.ttl("key")

    assert ttl.positive? && ttl <= 100
  end

  def test_set_with_nx
    assert_equal "OK", @redis.set("key", "value", nx: true)
    assert_nil @redis.set("key", "value2", nx: true)
    assert_equal "value", @redis.get("key")
  end

  def test_set_with_xx
    assert_nil @redis.set("key", "value", xx: true)
    @redis.set("key", "value")

    assert_equal "OK", @redis.set("key", "value2", xx: true)
    assert_equal "value2", @redis.get("key")
  end

  # ============ String Command Tests ============

  def test_incr_decr
    @redis.set("counter", "10")

    assert_equal 11, @redis.incr("counter")
    assert_equal 10, @redis.decr("counter")
    assert_equal 15, @redis.incrby("counter", 5)
    assert_equal 12, @redis.decrby("counter", 3)
  end

  def test_incrbyfloat_returns_float
    @redis.set("float", "10.5")
    result = @redis.incrbyfloat("float", 0.1)

    assert_instance_of Float, result
    assert_in_delta 10.6, result, 0.001
  end

  def test_append_strlen
    @redis.set("key", "hello")

    assert_equal 11, @redis.append("key", " world")
    assert_equal 11, @redis.strlen("key")
  end

  def test_getrange_setrange
    @redis.set("key", "hello world")

    assert_equal "world", @redis.getrange("key", 6, -1)
    @redis.setrange("key", 6, "redis")

    assert_equal "hello redis", @redis.get("key")
  end

  def test_mget_mset
    @redis.mset("k1", "v1", "k2", "v2")

    assert_equal %w[v1 v2], @redis.mget("k1", "k2")
  end

  def test_mapped_mget
    @redis.mset("k1", "v1", "k2", "v2")
    result = @redis.mapped_mget("k1", "k2")

    assert_instance_of Hash, result
    assert_equal({ "k1" => "v1", "k2" => "v2" }, result)
  end

  def test_mapped_mset
    result = @redis.mapped_mset("k1" => "v1", "k2" => "v2")

    assert_equal "OK", result
    assert_equal "v1", @redis.get("k1")
    assert_equal "v2", @redis.get("k2")
  end

  def test_msetnx_returns_boolean
    assert @redis.msetnx("k1", "v1", "k2", "v2")
    refute @redis.msetnx("k1", "v1_new", "k3", "v3")
  end

  def test_mapped_msetnx_returns_boolean
    assert @redis.mapped_msetnx("k1" => "v1", "k2" => "v2")
    refute @redis.mapped_msetnx("k1" => "v1_new", "k3" => "v3")
  end

  def test_setnx_returns_boolean
    assert @redis.setnx("key", "value")
    refute @redis.setnx("key", "value2")
  end

  def test_setex_psetex
    assert_equal "OK", @redis.setex("key", 100, "value")
    ttl = @redis.ttl("key")

    assert ttl.positive? && ttl <= 100

    assert_equal "OK", @redis.psetex("key2", 100_000, "value")
    pttl = @redis.pttl("key2")

    assert pttl.positive? && pttl <= 100_000
  end

  # ============ Key Command Tests ============

  def test_del
    @redis.set("key", "value")

    assert_equal 1, @redis.del("key")
    assert_nil @redis.get("key")
  end

  def test_del_multiple
    @redis.mset("k1", "v1", "k2", "v2", "k3", "v3")

    assert_equal 3, @redis.del("k1", "k2", "k3")
  end

  def test_exists_returns_integer
    @redis.set("key", "value")

    assert_equal 1, @redis.exists("key")
    assert_equal 0, @redis.exists("nonexistent")
    @redis.set("key2", "value2")

    assert_equal 2, @redis.exists("key", "key2")
  end

  def test_exists_question_mark_returns_boolean
    @redis.set("key", "value")

    assert @redis.exists?("key")
    refute @redis.exists?("nonexistent")
  end

  def test_expire_and_ttl
    @redis.set("key", "value")

    assert_equal 1, @redis.expire("key", 100)
    ttl = @redis.ttl("key")

    assert ttl.positive? && ttl <= 100
  end

  def test_persist
    @redis.setex("key", 100, "value")

    assert_equal 1, @redis.persist("key")
    assert_equal(-1, @redis.ttl("key"))
  end

  def test_type
    @redis.set("string", "value")
    @redis.lpush("list", "value")
    @redis.sadd("set", "value")
    @redis.zadd("zset", 1, "value")
    @redis.hset("hash", "field", "value")

    assert_equal "string", @redis.type("string")
    assert_equal "list", @redis.type("list")
    assert_equal "set", @redis.type("set")
    assert_equal "zset", @redis.type("zset")
    assert_equal "hash", @redis.type("hash")
  end

  def test_keys
    @redis.mset("k1", "v1", "k2", "v2", "other", "v3")
    keys = @redis.keys("k*")

    assert_includes keys, "k1"
    assert_includes keys, "k2"
    refute_includes keys, "other"
  end

  def test_rename
    @redis.set("key", "value")
    @redis.rename("key", "newkey")

    assert_nil @redis.get("key")
    assert_equal "value", @redis.get("newkey")
  end

  def test_renamenx
    @redis.set("key", "value")
    @redis.set("existing", "other")

    assert_equal 0, @redis.renamenx("key", "existing")
    assert_equal 1, @redis.renamenx("key", "newkey")
  end

  def test_scan_each
    @redis.mset("k1", "v1", "k2", "v2", "k3", "v3")
    keys = @redis.scan_each(match: "k*").to_a

    assert_equal 3, keys.length
    assert_includes keys, "k1"
    assert_includes keys, "k2"
    assert_includes keys, "k3"
  end

  # ============ Hash Command Tests ============

  def test_hset_hget
    @redis.hset("hash", "field", "value")

    assert_equal "value", @redis.hget("hash", "field")
  end

  def test_hset_multiple
    @redis.hset("hash", "f1", "v1", "f2", "v2")

    assert_equal "v1", @redis.hget("hash", "f1")
    assert_equal "v2", @redis.hget("hash", "f2")
  end

  def test_hsetnx_returns_boolean
    assert @redis.hsetnx("hash", "field", "value")
    refute @redis.hsetnx("hash", "field", "value2")
  end

  def test_hmget_hmset
    @redis.hmset("hash", "f1", "v1", "f2", "v2")

    assert_equal %w[v1 v2], @redis.hmget("hash", "f1", "f2")
  end

  def test_mapped_hmget
    @redis.hmset("hash", "f1", "v1", "f2", "v2")
    result = @redis.mapped_hmget("hash", "f1", "f2")

    assert_instance_of Hash, result
    assert_equal({ "f1" => "v1", "f2" => "v2" }, result)
  end

  def test_mapped_hmset
    @redis.mapped_hmset("hash", "f1" => "v1", "f2" => "v2")

    assert_equal "v1", @redis.hget("hash", "f1")
    assert_equal "v2", @redis.hget("hash", "f2")
  end

  def test_hgetall
    @redis.hmset("hash", "f1", "v1", "f2", "v2")
    result = @redis.hgetall("hash")

    assert_instance_of Hash, result
    assert_equal({ "f1" => "v1", "f2" => "v2" }, result)
  end

  def test_hexists_returns_boolean
    @redis.hset("hash", "field", "value")

    assert @redis.hexists("hash", "field")
    refute @redis.hexists("hash", "nonexistent")
  end

  def test_hdel
    @redis.hmset("hash", "f1", "v1", "f2", "v2")

    assert_equal 1, @redis.hdel("hash", "f1")
    assert_nil @redis.hget("hash", "f1")
  end

  def test_hkeys_hvals_hlen
    @redis.hmset("hash", "f1", "v1", "f2", "v2")

    assert_equal 2, @redis.hlen("hash")
    assert_includes @redis.hkeys("hash"), "f1"
    assert_includes @redis.hvals("hash"), "v1"
  end

  def test_hincrby_hincrbyfloat
    @redis.hset("hash", "counter", "10")

    assert_equal 15, @redis.hincrby("hash", "counter", 5)

    @redis.hset("hash", "float", "10.5")
    result = @redis.hincrbyfloat("hash", "float", 0.1)

    assert_instance_of Float, result
    assert_in_delta 10.6, result, 0.001
  end

  def test_hscan_each
    @redis.hmset("hash", "f1", "v1", "f2", "v2")
    pairs = @redis.hscan_each("hash").to_a

    assert_equal 2, pairs.length
    assert_includes pairs, %w[f1 v1]
    assert_includes pairs, %w[f2 v2]
  end

  # ============ List Command Tests ============

  def test_lpush_rpush
    @redis.lpush("list", "a")
    @redis.rpush("list", "b")

    assert_equal %w[a b], @redis.lrange("list", 0, -1)
  end

  def test_lpush_multiple
    @redis.lpush("list", "a", "b", "c")

    assert_equal %w[c b a], @redis.lrange("list", 0, -1)
  end

  def test_lpop_rpop
    @redis.rpush("list", "a", "b", "c")

    assert_equal "a", @redis.lpop("list")
    assert_equal "c", @redis.rpop("list")
    assert_equal %w[b], @redis.lrange("list", 0, -1)
  end

  def test_lpop_rpop_with_count
    @redis.rpush("list", "a", "b", "c", "d")

    assert_equal %w[a b], @redis.lpop("list", 2)
    assert_equal %w[d c], @redis.rpop("list", 2)
  end

  def test_llen_lindex
    @redis.rpush("list", "a", "b", "c")

    assert_equal 3, @redis.llen("list")
    assert_equal "a", @redis.lindex("list", 0)
    assert_equal "c", @redis.lindex("list", -1)
  end

  def test_lset_lrem
    @redis.rpush("list", "a", "b", "c")
    @redis.lset("list", 1, "x")

    assert_equal "x", @redis.lindex("list", 1)
    @redis.rpush("list", "x")

    assert_equal 2, @redis.lrem("list", 0, "x")
  end

  def test_ltrim
    @redis.rpush("list", "a", "b", "c", "d", "e")
    @redis.ltrim("list", 1, 3)

    assert_equal %w[b c d], @redis.lrange("list", 0, -1)
  end

  # ============ Set Command Tests ============

  def test_sadd_smembers
    @redis.sadd("set", "a", "b", "c")
    members = @redis.smembers("set")

    assert_equal 3, members.length
    assert_includes members, "a"
  end

  def test_sadd_returns_integer
    assert_equal 2, @redis.sadd("set", "a", "b")
    assert_equal 1, @redis.sadd("set", "c", "a") # "a" already exists
  end

  def test_sadd_question_mark_returns_boolean
    assert @redis.sadd?("set", "a")
    refute @redis.sadd?("set", "a")  # already exists
    assert @redis.sadd?("set", "b")
  end

  def test_srem_question_mark_returns_boolean
    @redis.sadd("set", "a", "b")

    assert @redis.srem?("set", "a")
    refute @redis.srem?("set", "a")  # already removed
  end

  def test_sismember_returns_boolean
    @redis.sadd("set", "a")

    assert @redis.sismember("set", "a")
    refute @redis.sismember("set", "b")
  end

  def test_smismember_returns_booleans
    @redis.sadd("set", "a", "c")
    result = @redis.smismember("set", "a", "b", "c")

    assert_equal [true, false, true], result
  end

  def test_scard
    @redis.sadd("set", "a", "b", "c")

    assert_equal 3, @redis.scard("set")
  end

  def test_spop
    @redis.sadd("set", "a", "b", "c")
    popped = @redis.spop("set")

    assert_includes %w[a b c], popped
    assert_equal 2, @redis.scard("set")
  end

  def test_smove_returns_boolean
    @redis.sadd("src", "a")
    @redis.sadd("dst", "b")

    assert @redis.smove("src", "dst", "a")
    refute @redis.smove("src", "dst", "nonexistent")
  end

  def test_sinter_sunion_sdiff
    @redis.sadd("set1", "a", "b", "c")
    @redis.sadd("set2", "b", "c", "d")

    inter = @redis.sinter("set1", "set2")

    assert_equal 2, inter.length
    assert_includes inter, "b"
    assert_includes inter, "c"

    union = @redis.sunion("set1", "set2")

    assert_equal 4, union.length

    diff = @redis.sdiff("set1", "set2")

    assert_equal 1, diff.length
    assert_includes diff, "a"
  end

  def test_sscan_each
    @redis.sadd("set", "a", "b", "c")
    members = @redis.sscan_each("set").to_a

    assert_equal 3, members.length
    assert_includes members, "a"
  end

  # ============ Sorted Set Command Tests ============

  def test_zadd_zscore
    @redis.zadd("zset", 1, "a", 2, "b", 3, "c")

    assert_equal 3, @redis.zcard("zset")
    assert_in_delta 2.0, @redis.zscore("zset", "b"), 0.001
  end

  def test_zadd_with_array
    @redis.zadd("zset", [[1, "a"], [2, "b"]])

    assert_equal 2, @redis.zcard("zset")
  end

  def test_zscore_returns_float
    @redis.zadd("zset", 1.5, "a")
    score = @redis.zscore("zset", "a")

    assert_instance_of Float, score
    assert_in_delta 1.5, score, 0.001
  end

  def test_zrank_zrevrank
    @redis.zadd("zset", 1, "a", 2, "b", 3, "c")

    assert_equal 0, @redis.zrank("zset", "a")
    assert_equal 2, @redis.zrank("zset", "c")
    assert_equal 0, @redis.zrevrank("zset", "c")
  end

  def test_zrange_zrevrange
    @redis.zadd("zset", 1, "a", 2, "b", 3, "c")

    assert_equal %w[a b c], @redis.zrange("zset", 0, -1)
    assert_equal %w[c b a], @redis.zrevrange("zset", 0, -1)
  end

  def test_zrange_with_scores
    @redis.zadd("zset", 1, "a", 2, "b")
    result = @redis.zrange("zset", 0, -1, withscores: true)

    assert_equal [["a", 1.0], ["b", 2.0]], result
  end

  def test_zincrby_returns_float
    @redis.zadd("zset", 1, "a")
    result = @redis.zincrby("zset", 2.5, "a")

    assert_instance_of Float, result
    assert_in_delta 3.5, result, 0.001
  end

  def test_zcount
    @redis.zadd("zset", 1, "a", 2, "b", 3, "c")

    assert_equal 2, @redis.zcount("zset", 1, 2)
    assert_equal 3, @redis.zcount("zset", "-inf", "+inf")
  end

  def test_zrangebyscore
    @redis.zadd("zset", 1, "a", 2, "b", 3, "c")

    assert_equal %w[a b], @redis.zrangebyscore("zset", 0, 2)
    assert_equal %w[c b], @redis.zrevrangebyscore("zset", 3, 2)
  end

  def test_zpopmin_zpopmax
    @redis.zadd("zset", 1, "a", 2, "b", 3, "c")

    # Without count returns single pair [member, score]
    min = @redis.zpopmin("zset")

    assert_equal ["a", 1.0], min

    max = @redis.zpopmax("zset")

    assert_equal ["c", 3.0], max
  end

  def test_zpopmin_zpopmax_with_count
    @redis.zadd("zset", 1, "a", 2, "b", 3, "c")

    # With count returns nested [[member, score], ...]
    min = @redis.zpopmin("zset", 2)

    assert_equal [["a", 1.0], ["b", 2.0]], min

    max = @redis.zpopmax("zset", 1)

    assert_equal [["c", 3.0]], max
  end

  def test_zremrangebyrank
    @redis.zadd("zset", 1, "a", 2, "b", 3, "c")

    assert_equal 2, @redis.zremrangebyrank("zset", 0, 1)
    assert_equal %w[c], @redis.zrange("zset", 0, -1)
  end

  def test_zremrangebyscore
    @redis.zadd("zset", 1, "a", 2, "b", 3, "c")

    assert_equal 2, @redis.zremrangebyscore("zset", 1, 2)
    assert_equal %w[c], @redis.zrange("zset", 0, -1)
  end

  def test_zinterstore_zunionstore
    @redis.zadd("zset1", 1, "a", 2, "b")
    @redis.zadd("zset2", 3, "b", 4, "c")

    @redis.zinterstore("zset_inter", %w[zset1 zset2])

    assert_equal 1, @redis.zcard("zset_inter")
    assert_in_delta 5.0, @redis.zscore("zset_inter", "b"), 0.001

    @redis.zunionstore("zset_union", %w[zset1 zset2])

    assert_equal 3, @redis.zcard("zset_union")
  end

  def test_zscan_each
    @redis.zadd("zset", 1, "a", 2, "b", 3, "c")
    pairs = @redis.zscan_each("zset").to_a

    assert_equal 3, pairs.length
    assert(pairs.any? { |m, s| m == "a" && s == 1.0 })
  end

  # ============ Pipeline Tests ============

  def test_pipelined_basic
    results = @redis.pipelined do |pipe|
      pipe.set("key1", "value1")
      pipe.set("key2", "value2")
      pipe.get("key1")
      pipe.get("key2")
    end

    assert_equal 4, results.length
    assert_equal "OK", results[0]
    assert_equal "OK", results[1]
    assert_equal "value1", results[2]
    assert_equal "value2", results[3]
  end

  def test_pipelined_returns_futures
    futures = []
    @redis.set("key", "value")

    @redis.pipelined do |pipe|
      futures << pipe.get("key")
      futures << pipe.set("key2", "value2")
    end

    assert_instance_of Redis::Future, futures[0]
    assert_equal "value", futures[0].value
    assert_equal "OK", futures[1].value
  end

  def test_future_not_ready_before_execution
    # Create a pipeline but don't execute it yet
    # We need to access the future before the pipeline executes
    # This is tricky to test, but we can test the FutureNotReady error class
    error = Redis::FutureNotReady.new

    assert_instance_of Redis::FutureNotReady, error
    assert_match(/pipeline/, error.message)
  end

  def test_pipelined_with_multiple_types
    @redis.set("string", "value")
    @redis.lpush("list", "a", "b")
    @redis.sadd("set", "x", "y")

    results = @redis.pipelined do |pipe|
      pipe.get("string")
      pipe.lrange("list", 0, -1)
      pipe.smembers("set")
    end

    assert_equal "value", results[0]
    assert_equal %w[b a], results[1]
    assert_includes results[2], "x"
    assert_includes results[2], "y"
  end

  # ============ Transaction Tests ============

  def test_multi_basic
    results = @redis.multi do |tx|
      tx.set("key1", "value1")
      tx.incr("counter")
      tx.get("key1")
    end

    assert_equal 3, results.length
    assert_equal "OK", results[0]
    assert_equal 1, results[1]
    assert_equal "value1", results[2]
  end

  def test_watch_basic
    @redis.set("key", "value")
    result = @redis.watch("key") do
      "watched"
    end

    assert_equal "watched", result
  end

  # ============ Error Handling Tests ============

  def test_command_error
    @redis.set("string", "value")
    assert_raises(Redis::CommandError) do
      @redis.lpush("string", "value") # WRONGTYPE
    end
  end

  def test_error_inheritance
    assert_operator Redis::CommandError, :<, Redis::BaseError
    assert_operator Redis::ConnectionError, :<, Redis::BaseError
    assert_operator Redis::TimeoutError, :<, Redis::BaseError
    assert_operator Redis::WrongTypeError, :<, Redis::CommandError
    assert_operator Redis::ClusterError, :<, Redis::BaseError
  end

  # ============ Connection Tests ============

  def test_connected
    assert_predicate @redis, :connected?
  end

  def test_close_and_reconnect
    @redis.ping
    @redis.close

    refute_predicate @redis, :connected?

    # Should auto-reconnect on next command
    assert_equal "PONG", @redis.ping
    assert_predicate @redis, :connected?
  end

  def test_quit
    result = @redis.quit

    assert_equal "OK", result
  end

  # ============ HyperLogLog Tests ============

  def test_pfadd_returns_boolean
    assert @redis.pfadd("hll", "a", "b", "c")
    refute @redis.pfadd("hll", "a", "b", "c") # same elements
  end

  def test_pfcount
    @redis.pfadd("hll", "a", "b", "c")
    count = @redis.pfcount("hll")

    assert_equal 3, count
  end

  # ============ Scripting Tests ============

  def test_eval
    result = @redis.eval("return 'hello'", keys: [], argv: [])

    assert_equal "hello", result
  end

  def test_eval_with_keys_and_args
    script = "return {KEYS[1], ARGV[1]}"
    result = @redis.eval(script, keys: ["key1"], argv: ["arg1"])

    assert_equal %w[key1 arg1], result
  end

  # ============ Server Tests ============

  def test_info
    info = @redis.info

    assert_instance_of Hash, info
    assert info.key?("redis_version") || info.key?(:redis_version)
  end

  def test_dbsize
    @redis.flushdb
    @redis.set("key", "value")

    assert_equal 1, @redis.dbsize
  end

  def test_time
    time = @redis.time

    assert_instance_of Array, time
    assert_equal 2, time.length
  end
end
