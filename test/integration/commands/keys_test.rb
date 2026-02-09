# frozen_string_literal: true

require "test_helper"

class KeysCommandsTest < RedisRubyTestCase
  use_testcontainers!

  # EXISTS tests
  def test_exists_single_key
    redis.set("test:key", "value")

    assert_equal 1, redis.exists("test:key")
  ensure
    redis.del("test:key")
  end

  def test_exists_missing_key
    assert_equal 0, redis.exists("test:nonexistent")
  end

  def test_exists_multiple_keys
    redis.set("test:key1", "value1")
    redis.set("test:key2", "value2")

    assert_equal 2, redis.exists("test:key1", "test:key2")
    assert_equal 1, redis.exists("test:key1", "test:nonexistent")
  ensure
    redis.del("test:key1", "test:key2")
  end

  def test_exists_counts_duplicates
    redis.set("test:key", "value")

    # EXISTS counts each occurrence
    assert_equal 2, redis.exists("test:key", "test:key")
  ensure
    redis.del("test:key")
  end

  # TYPE tests
  def test_type_string
    redis.set("test:string", "value")

    assert_equal "string", redis.type("test:string")
  ensure
    redis.del("test:string")
  end

  def test_type_list
    redis.rpush("test:list", "value")

    assert_equal "list", redis.type("test:list")
  ensure
    redis.del("test:list")
  end

  def test_type_set
    redis.sadd("test:set", "member")

    assert_equal "set", redis.type("test:set")
  ensure
    redis.del("test:set")
  end

  def test_type_zset
    redis.zadd("test:zset", 1, "member")

    assert_equal "zset", redis.type("test:zset")
  ensure
    redis.del("test:zset")
  end

  def test_type_hash
    redis.hset("test:hash", "field", "value")

    assert_equal "hash", redis.type("test:hash")
  ensure
    redis.del("test:hash")
  end

  def test_type_missing_key
    assert_equal "none", redis.type("test:nonexistent")
  end

  # KEYS tests
  def test_keys_pattern
    redis.set("test:foo", "1")
    redis.set("test:bar", "2")
    redis.set("test:baz", "3")
    redis.set("other:key", "4")

    result = redis.keys("test:*")

    assert_equal 3, result.length
    assert_includes result, "test:foo"
    assert_includes result, "test:bar"
    assert_includes result, "test:baz"
  ensure
    redis.del("test:foo", "test:bar", "test:baz", "other:key")
  end

  def test_keys_with_question_mark
    redis.set("test:a1", "1")
    redis.set("test:a2", "2")
    redis.set("test:ab", "3")

    result = redis.keys("test:a?")

    assert_equal 3, result.length
  ensure
    redis.del("test:a1", "test:a2", "test:ab")
  end

  # EXPIRE tests
  def test_expire_sets_ttl
    redis.set("test:key", "value")

    assert_equal 1, redis.expire("test:key", 100)
    ttl = redis.ttl("test:key")

    assert_operator ttl, :>, 0
    assert_operator ttl, :<=, 100
  ensure
    redis.del("test:key")
  end

  def test_expire_missing_key
    assert_equal 0, redis.expire("test:nonexistent", 100)
  end

  # EXPIRE with conditional options (Redis 7.0+)
  def test_expire_with_nx_no_existing_expiry
    redis.set("test:key", "value")

    # NX: only set if no expiry exists - should succeed
    assert_equal 1, redis.expire("test:key", 100, nx: true)
    ttl = redis.ttl("test:key")

    assert_operator ttl, :>, 0
    assert_operator ttl, :<=, 100
  ensure
    redis.del("test:key")
  end

  def test_expire_with_nx_existing_expiry
    redis.set("test:key", "value")
    redis.expire("test:key", 200)

    # NX: only set if no expiry exists - should fail because expiry exists
    assert_equal 0, redis.expire("test:key", 100, nx: true)
    ttl = redis.ttl("test:key")

    # TTL should still be around 200
    assert_operator ttl, :>, 100
  ensure
    redis.del("test:key")
  end

  def test_expire_with_xx_no_existing_expiry
    redis.set("test:key", "value")

    # XX: only set if expiry already exists - should fail
    assert_equal 0, redis.expire("test:key", 100, xx: true)
    assert_equal(-1, redis.ttl("test:key"))
  ensure
    redis.del("test:key")
  end

  def test_expire_with_xx_existing_expiry
    redis.set("test:key", "value")
    redis.expire("test:key", 200)

    # XX: only set if expiry already exists - should succeed
    assert_equal 1, redis.expire("test:key", 100, xx: true)
    ttl = redis.ttl("test:key")

    assert_operator ttl, :<=, 100
  ensure
    redis.del("test:key")
  end

  def test_expire_with_gt_new_ttl_greater
    redis.set("test:key", "value")
    redis.expire("test:key", 100)

    # GT: only set if new TTL > current TTL - should succeed
    assert_equal 1, redis.expire("test:key", 200, gt: true)
    ttl = redis.ttl("test:key")

    assert_operator ttl, :>, 100
  ensure
    redis.del("test:key")
  end

  def test_expire_with_gt_new_ttl_smaller
    redis.set("test:key", "value")
    redis.expire("test:key", 200)

    # GT: only set if new TTL > current TTL - should fail
    assert_equal 0, redis.expire("test:key", 100, gt: true)
    ttl = redis.ttl("test:key")

    assert_operator ttl, :>, 100
  ensure
    redis.del("test:key")
  end

  def test_expire_with_lt_new_ttl_smaller
    redis.set("test:key", "value")
    redis.expire("test:key", 200)

    # LT: only set if new TTL < current TTL - should succeed
    assert_equal 1, redis.expire("test:key", 100, lt: true)
    ttl = redis.ttl("test:key")

    assert_operator ttl, :<=, 100
  ensure
    redis.del("test:key")
  end

  def test_expire_with_lt_new_ttl_greater
    redis.set("test:key", "value")
    redis.expire("test:key", 100)

    # LT: only set if new TTL < current TTL - should fail
    assert_equal 0, redis.expire("test:key", 200, lt: true)
    ttl = redis.ttl("test:key")

    assert_operator ttl, :<=, 100
  ensure
    redis.del("test:key")
  end

  # PEXPIRE tests
  def test_pexpire_sets_ttl
    redis.set("test:key", "value")

    assert_equal 1, redis.pexpire("test:key", 100_000)
    pttl = redis.pttl("test:key")

    assert_operator pttl, :>, 0
    assert_operator pttl, :<=, 100_000
  ensure
    redis.del("test:key")
  end

  def test_pexpire_with_nx
    redis.set("test:key", "value")
    redis.pexpire("test:key", 200_000)

    # NX should fail since expiry exists
    assert_equal 0, redis.pexpire("test:key", 100_000, nx: true)
  ensure
    redis.del("test:key")
  end

  def test_pexpire_with_xx
    redis.set("test:key", "value")
    redis.pexpire("test:key", 100_000)

    # XX should succeed since expiry exists
    assert_equal 1, redis.pexpire("test:key", 200_000, xx: true)
    pttl = redis.pttl("test:key")

    assert_operator pttl, :>, 100_000
  ensure
    redis.del("test:key")
  end

  def test_pexpire_with_gt
    redis.set("test:key", "value")
    redis.pexpire("test:key", 100_000)

    # GT should succeed since new TTL > current
    assert_equal 1, redis.pexpire("test:key", 200_000, gt: true)
  ensure
    redis.del("test:key")
  end

  def test_pexpire_with_lt
    redis.set("test:key", "value")
    redis.pexpire("test:key", 200_000)

    # LT should succeed since new TTL < current
    assert_equal 1, redis.pexpire("test:key", 100_000, lt: true)
  ensure
    redis.del("test:key")
  end

  # EXPIREAT tests
  def test_expireat_sets_ttl
    redis.set("test:key", "value")
    future_time = Time.now.to_i + 100

    assert_equal 1, redis.expireat("test:key", future_time)
    ttl = redis.ttl("test:key")

    assert_operator ttl, :>, 0
    assert_operator ttl, :<=, 100
  ensure
    redis.del("test:key")
  end

  def test_expireat_with_nx
    redis.set("test:key", "value")

    # NX should succeed since no expiry
    future_time = Time.now.to_i + 100

    assert_equal 1, redis.expireat("test:key", future_time, nx: true)

    # NX should fail since expiry now exists
    new_future_time = Time.now.to_i + 200

    assert_equal 0, redis.expireat("test:key", new_future_time, nx: true)
  ensure
    redis.del("test:key")
  end

  def test_expireat_with_xx
    redis.set("test:key", "value")
    future_time = Time.now.to_i + 100

    # XX should fail since no expiry
    assert_equal 0, redis.expireat("test:key", future_time, xx: true)

    # Set an expiry first
    redis.expire("test:key", 50)

    # XX should now succeed
    assert_equal 1, redis.expireat("test:key", future_time, xx: true)
  ensure
    redis.del("test:key")
  end

  def test_expireat_with_gt
    redis.set("test:key", "value")
    smaller_time = Time.now.to_i + 50
    larger_time = Time.now.to_i + 100

    redis.expireat("test:key", smaller_time)

    # GT should succeed since new time > current
    assert_equal 1, redis.expireat("test:key", larger_time, gt: true)
  ensure
    redis.del("test:key")
  end

  def test_expireat_with_lt
    redis.set("test:key", "value")
    larger_time = Time.now.to_i + 100
    smaller_time = Time.now.to_i + 50

    redis.expireat("test:key", larger_time)

    # LT should succeed since new time < current
    assert_equal 1, redis.expireat("test:key", smaller_time, lt: true)
  ensure
    redis.del("test:key")
  end

  # PEXPIREAT tests
  def test_pexpireat_sets_ttl
    redis.set("test:key", "value")
    future_time = (Time.now.to_f * 1000).to_i + 100_000

    assert_equal 1, redis.pexpireat("test:key", future_time)
    pttl = redis.pttl("test:key")

    assert_operator pttl, :>, 0
    # Allow small tolerance for network/processing delay
    assert_operator pttl, :<=, 100_010
  ensure
    redis.del("test:key")
  end

  def test_pexpireat_with_nx
    redis.set("test:key", "value")
    future_time = (Time.now.to_f * 1000).to_i + 100_000

    # NX should succeed since no expiry
    assert_equal 1, redis.pexpireat("test:key", future_time, nx: true)

    # NX should fail since expiry now exists
    new_future_time = (Time.now.to_f * 1000).to_i + 200_000

    assert_equal 0, redis.pexpireat("test:key", new_future_time, nx: true)
  ensure
    redis.del("test:key")
  end

  def test_pexpireat_with_xx
    redis.set("test:key", "value")
    future_time = (Time.now.to_f * 1000).to_i + 100_000

    # XX should fail since no expiry
    assert_equal 0, redis.pexpireat("test:key", future_time, xx: true)

    # Set an expiry first
    redis.pexpire("test:key", 50_000)

    # XX should now succeed
    assert_equal 1, redis.pexpireat("test:key", future_time, xx: true)
  ensure
    redis.del("test:key")
  end

  def test_pexpireat_with_gt
    redis.set("test:key", "value")
    smaller_time = (Time.now.to_f * 1000).to_i + 50_000
    larger_time = (Time.now.to_f * 1000).to_i + 100_000

    redis.pexpireat("test:key", smaller_time)

    # GT should succeed since new time > current
    assert_equal 1, redis.pexpireat("test:key", larger_time, gt: true)
  ensure
    redis.del("test:key")
  end

  def test_pexpireat_with_lt
    redis.set("test:key", "value")
    larger_time = (Time.now.to_f * 1000).to_i + 100_000
    smaller_time = (Time.now.to_f * 1000).to_i + 50_000

    redis.pexpireat("test:key", larger_time)

    # LT should succeed since new time < current
    assert_equal 1, redis.pexpireat("test:key", smaller_time, lt: true)
  ensure
    redis.del("test:key")
  end

  # TTL tests
  def test_ttl_with_expiry
    redis.set("test:key", "value")
    redis.expire("test:key", 100)

    ttl = redis.ttl("test:key")

    assert_operator ttl, :>, 0
    assert_operator ttl, :<=, 100
  ensure
    redis.del("test:key")
  end

  def test_ttl_no_expiry
    redis.set("test:key", "value")

    assert_equal(-1, redis.ttl("test:key"))
  ensure
    redis.del("test:key")
  end

  def test_ttl_missing_key
    assert_equal(-2, redis.ttl("test:nonexistent"))
  end

  # PTTL tests
  def test_pttl_with_expiry
    redis.set("test:key", "value")
    redis.pexpire("test:key", 100_000)

    pttl = redis.pttl("test:key")

    assert_operator pttl, :>, 0
    assert_operator pttl, :<=, 100_000
  ensure
    redis.del("test:key")
  end

  def test_pttl_no_expiry
    redis.set("test:key", "value")

    assert_equal(-1, redis.pttl("test:key"))
  ensure
    redis.del("test:key")
  end

  def test_pttl_missing_key
    assert_equal(-2, redis.pttl("test:nonexistent"))
  end

  # PERSIST tests
  def test_persist_removes_ttl
    redis.set("test:key", "value")
    redis.expire("test:key", 100)

    assert_equal 1, redis.persist("test:key")
    assert_equal(-1, redis.ttl("test:key"))
  ensure
    redis.del("test:key")
  end

  def test_persist_no_ttl
    redis.set("test:key", "value")

    assert_equal 0, redis.persist("test:key")
  ensure
    redis.del("test:key")
  end

  def test_persist_missing_key
    assert_equal 0, redis.persist("test:nonexistent")
  end

  # EXPIRETIME tests (Redis 7.0+)
  def test_expiretime_with_expiry
    redis.set("test:key", "value")
    future_time = Time.now.to_i + 100
    redis.expireat("test:key", future_time)

    assert_equal future_time, redis.expiretime("test:key")
  ensure
    redis.del("test:key")
  end

  def test_expiretime_no_expiry
    redis.set("test:key", "value")

    assert_equal(-1, redis.expiretime("test:key"))
  ensure
    redis.del("test:key")
  end

  def test_expiretime_missing_key
    assert_equal(-2, redis.expiretime("test:nonexistent"))
  end

  # PEXPIRETIME tests (Redis 7.0+)
  def test_pexpiretime_with_expiry
    redis.set("test:key", "value")
    future_time = (Time.now.to_f * 1000).to_i + 100_000
    redis.pexpireat("test:key", future_time)

    result = redis.pexpiretime("test:key")

    # Allow some tolerance due to timing
    assert_in_delta future_time, result, 1000
  ensure
    redis.del("test:key")
  end

  def test_pexpiretime_no_expiry
    redis.set("test:key", "value")

    assert_equal(-1, redis.pexpiretime("test:key"))
  ensure
    redis.del("test:key")
  end

  def test_pexpiretime_missing_key
    assert_equal(-2, redis.pexpiretime("test:nonexistent"))
  end

  # DEL tests
  def test_del_single_key
    redis.set("test:key", "value")

    assert_equal 1, redis.del("test:key")
    assert_equal 0, redis.exists("test:key")
  end

  def test_del_multiple_keys
    redis.set("test:key1", "value1")
    redis.set("test:key2", "value2")

    assert_equal 2, redis.del("test:key1", "test:key2")
    assert_equal 0, redis.exists("test:key1", "test:key2")
  end

  def test_del_missing_key
    assert_equal 0, redis.del("test:nonexistent")
  end

  # UNLINK tests
  def test_unlink_single_key
    redis.set("test:key", "value")

    assert_equal 1, redis.unlink("test:key")
    assert_equal 0, redis.exists("test:key")
  end

  def test_unlink_multiple_keys
    redis.set("test:key1", "value1")
    redis.set("test:key2", "value2")

    assert_equal 2, redis.unlink("test:key1", "test:key2")
  end

  # RENAME tests
  def test_rename_key
    redis.set("test:old", "value")

    assert_equal "OK", redis.rename("test:old", "test:new")
    assert_equal 0, redis.exists("test:old")
    assert_equal "value", redis.get("test:new")
  ensure
    redis.del("test:old", "test:new")
  end

  def test_rename_missing_key_raises
    assert_raises(RedisRuby::CommandError) do
      redis.rename("test:nonexistent", "test:new")
    end
  end

  # RENAMENX tests
  def test_renamenx_success
    redis.set("test:old", "value")

    assert_equal 1, redis.renamenx("test:old", "test:new")
    assert_equal "value", redis.get("test:new")
  ensure
    redis.del("test:old", "test:new")
  end

  def test_renamenx_fails_if_exists
    redis.set("test:old", "value1")
    redis.set("test:new", "value2")

    assert_equal 0, redis.renamenx("test:old", "test:new")
    assert_equal "value1", redis.get("test:old")
    assert_equal "value2", redis.get("test:new")
  ensure
    redis.del("test:old", "test:new")
  end

  # DUMP and RESTORE tests
  def test_dump_and_restore
    redis.set("test:source", "value")
    serialized = redis.dump("test:source")

    refute_nil serialized
    assert_kind_of String, serialized

    redis.del("test:source")

    assert_equal "OK", redis.restore("test:dest", 0, serialized)
    assert_equal "value", redis.get("test:dest")
  ensure
    redis.del("test:source", "test:dest")
  end

  def test_dump_missing_key
    assert_nil redis.dump("test:nonexistent")
  end

  def test_restore_with_ttl
    redis.set("test:source", "value")
    serialized = redis.dump("test:source")
    redis.del("test:source")

    redis.restore("test:dest", 5000, serialized)
    ttl = redis.pttl("test:dest")

    assert_operator ttl, :>, 0
    assert_operator ttl, :<=, 5000
  ensure
    redis.del("test:dest")
  end

  def test_restore_with_replace
    redis.set("test:source", "original")
    serialized = redis.dump("test:source")
    redis.set("test:source", "modified")

    # Without REPLACE, should fail
    assert_raises(RedisRuby::CommandError) do
      redis.restore("test:source", 0, serialized)
    end

    # With REPLACE, should succeed
    assert_equal "OK", redis.restore("test:source", 0, serialized, replace: true)
    assert_equal "original", redis.get("test:source")
  ensure
    redis.del("test:source")
  end

  # COPY tests (Redis 6.2+)
  def test_copy_key
    redis.set("test:source", "value")

    assert_equal 1, redis.copy("test:source", "test:dest")
    assert_equal "value", redis.get("test:source")
    assert_equal "value", redis.get("test:dest")
  ensure
    redis.del("test:source", "test:dest")
  end

  def test_copy_missing_source
    assert_equal 0, redis.copy("test:nonexistent", "test:dest")
  end

  def test_copy_fails_if_dest_exists
    redis.set("test:source", "value1")
    redis.set("test:dest", "value2")

    assert_equal 0, redis.copy("test:source", "test:dest")
    assert_equal "value2", redis.get("test:dest")
  ensure
    redis.del("test:source", "test:dest")
  end

  def test_copy_with_replace
    redis.set("test:source", "value1")
    redis.set("test:dest", "value2")

    assert_equal 1, redis.copy("test:source", "test:dest", replace: true)
    assert_equal "value1", redis.get("test:dest")
  ensure
    redis.del("test:source", "test:dest")
  end

  # TOUCH tests
  def test_touch_keys
    redis.set("test:key1", "value1")
    redis.set("test:key2", "value2")

    assert_equal 2, redis.touch("test:key1", "test:key2")
  ensure
    redis.del("test:key1", "test:key2")
  end

  def test_touch_missing_keys
    redis.set("test:key1", "value1")

    assert_equal 1, redis.touch("test:key1", "test:nonexistent")
  ensure
    redis.del("test:key1")
  end

  # RANDOMKEY tests
  def test_randomkey_returns_key
    redis.set("test:key1", "value1")
    redis.set("test:key2", "value2")

    result = redis.randomkey

    refute_nil result
    assert_kind_of String, result
  ensure
    redis.del("test:key1", "test:key2")
  end

  # SCAN tests
  def test_scan_iterates_keys
    redis.set("test:scan1", "value1")
    redis.set("test:scan2", "value2")
    redis.set("test:scan3", "value3")

    cursor, keys = redis.scan(0, match: "test:scan*")

    # Scan may return partial results, so just check format
    assert_kind_of String, cursor
    assert_kind_of Array, keys
  ensure
    redis.del("test:scan1", "test:scan2", "test:scan3")
  end

  def test_scan_with_count
    10.times { |i| redis.set("test:scancount#{i}", "value#{i}") }

    cursor, keys = redis.scan(0, match: "test:scancount*", count: 5)

    assert_kind_of String, cursor
    assert_kind_of Array, keys
  ensure
    10.times { |i| redis.del("test:scancount#{i}") }
  end

  def test_scan_with_type
    redis.set("test:string", "value")
    redis.rpush("test:list", "item")

    cursor, keys = redis.scan(0, match: "test:*", type: "string")

    assert_kind_of String, cursor
    # Type filter should only return strings
    keys.each do |key|
      assert_equal "string", redis.type(key) if key.start_with?("test:")
    end
  ensure
    redis.del("test:string", "test:list")
  end

  # MEMORY USAGE tests
  def test_memory_usage
    redis.set("test:key", "value")

    result = redis.memory_usage("test:key")

    assert_kind_of Integer, result
    assert_operator result, :>, 0
  ensure
    redis.del("test:key")
  end

  def test_memory_usage_missing_key
    assert_nil redis.memory_usage("test:nonexistent")
  end
end
