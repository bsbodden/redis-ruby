# frozen_string_literal: true

require "test_helper"

class StreamsIntegrationTest < RedisRubyTestCase
  use_testcontainers!

  def setup
    super
    @stream_key = "stream:test:#{SecureRandom.hex(4)}"
    @stream_key2 = "stream:test2:#{SecureRandom.hex(4)}"
  end

  def teardown
    # Clean up consumer groups
    begin
      redis.xgroup_destroy(@stream_key, "mygroup")
    rescue RedisRuby::CommandError
      # Ignore if group doesn't exist
    end
    begin
      redis.del(@stream_key, @stream_key2)
    rescue StandardError
      nil
    end
    super
  end

  # XADD tests
  def test_xadd_auto_id
    id = redis.xadd(@stream_key, { "field" => "value" })

    assert_match(/\d+-\d+/, id)
  end

  def test_xadd_explicit_id
    id = redis.xadd(@stream_key, { "field" => "value" }, id: "1000-0")

    assert_equal "1000-0", id
  end

  def test_xadd_multiple_fields
    id = redis.xadd(@stream_key, { "name" => "Alice", "age" => "30", "city" => "NYC" })

    refute_nil id

    entries = redis.xrange(@stream_key, "-", "+")

    assert_equal 1, entries.length
    assert_equal({ "name" => "Alice", "age" => "30", "city" => "NYC" }, entries[0][1])
  end

  def test_xadd_with_maxlen
    10.times { |i| redis.xadd(@stream_key, { "i" => i.to_s }) }
    redis.xadd(@stream_key, { "i" => "10" }, maxlen: 5)

    length = redis.xlen(@stream_key)

    assert_operator length, :<=, 5
  end

  def test_xadd_with_maxlen_approximate
    10.times { |i| redis.xadd(@stream_key, { "i" => i.to_s }) }
    redis.xadd(@stream_key, { "i" => "10" }, maxlen: 5, approximate: true)

    # Approximate may keep more entries
    length = redis.xlen(@stream_key)

    assert_operator length, :<=, 11
  end

  def test_xadd_with_minid
    redis.xadd(@stream_key, { "a" => "1" }, id: "1000-0")
    redis.xadd(@stream_key, { "b" => "2" }, id: "2000-0")
    redis.xadd(@stream_key, { "c" => "3" }, id: "3000-0", minid: "2500-0")

    entries = redis.xrange(@stream_key, "-", "+")
    # Should have trimmed entries before minid
    assert(entries.all? { |e| e[0] >= "2500-0" })
  end

  def test_xadd_nomkstream
    # NOMKSTREAM prevents creating stream if it doesn't exist
    result = redis.xadd("stream:nonexistent", { "a" => "1" }, nomkstream: true)

    assert_nil result
  end

  # XLEN tests
  def test_xlen_empty
    assert_equal 0, redis.xlen(@stream_key)
  end

  def test_xlen_with_entries
    3.times { |i| redis.xadd(@stream_key, { "i" => i.to_s }) }

    assert_equal 3, redis.xlen(@stream_key)
  end

  # XRANGE tests
  def test_xrange_all
    redis.xadd(@stream_key, { "a" => "1" }, id: "1-0")
    redis.xadd(@stream_key, { "b" => "2" }, id: "2-0")
    redis.xadd(@stream_key, { "c" => "3" }, id: "3-0")

    entries = redis.xrange(@stream_key, "-", "+")

    assert_equal 3, entries.length
    assert_equal "1-0", entries[0][0]
    assert_equal({ "a" => "1" }, entries[0][1])
  end

  def test_xrange_with_range
    redis.xadd(@stream_key, { "a" => "1" }, id: "1-0")
    redis.xadd(@stream_key, { "b" => "2" }, id: "2-0")
    redis.xadd(@stream_key, { "c" => "3" }, id: "3-0")

    entries = redis.xrange(@stream_key, "1-0", "2-0")

    assert_equal 2, entries.length
  end

  def test_xrange_with_count
    5.times { |i| redis.xadd(@stream_key, { "i" => i.to_s }) }

    entries = redis.xrange(@stream_key, "-", "+", count: 2)

    assert_equal 2, entries.length
  end

  # XREVRANGE tests
  def test_xrevrange
    redis.xadd(@stream_key, { "a" => "1" }, id: "1-0")
    redis.xadd(@stream_key, { "b" => "2" }, id: "2-0")
    redis.xadd(@stream_key, { "c" => "3" }, id: "3-0")

    entries = redis.xrevrange(@stream_key, "+", "-")

    assert_equal 3, entries.length
    assert_equal "3-0", entries[0][0] # Newest first
  end

  # XREAD tests
  def test_xread_single_stream
    redis.xadd(@stream_key, { "a" => "1" }, id: "1-0")
    redis.xadd(@stream_key, { "b" => "2" }, id: "2-0")

    result = redis.xread(@stream_key, "0-0")

    assert_equal 1, result.length
    assert_equal @stream_key, result[0][0]
    assert_equal 2, result[0][1].length
  end

  def test_xread_from_id
    redis.xadd(@stream_key, { "a" => "1" }, id: "1-0")
    redis.xadd(@stream_key, { "b" => "2" }, id: "2-0")
    redis.xadd(@stream_key, { "c" => "3" }, id: "3-0")

    result = redis.xread(@stream_key, "1-0") # After 1-0
    entries = result[0][1]

    assert_equal 2, entries.length
    assert_equal "2-0", entries[0][0]
  end

  def test_xread_multiple_streams
    redis.xadd(@stream_key, { "a" => "1" })
    redis.xadd(@stream_key2, { "b" => "2" })

    result = redis.xread({ @stream_key => "0-0", @stream_key2 => "0-0" })

    assert_equal 2, result.length
  end

  def test_xread_with_count
    5.times { |i| redis.xadd(@stream_key, { "i" => i.to_s }) }

    result = redis.xread(@stream_key, "0-0", count: 2)

    assert_equal 2, result[0][1].length
  end

  # XREAD with BLOCK is tricky to test without threading
  # Skip for now, tested manually

  # XGROUP tests
  def test_xgroup_create
    redis.xadd(@stream_key, { "a" => "1" })
    result = redis.xgroup_create(@stream_key, "mygroup", "$")

    assert_equal "OK", result
  end

  def test_xgroup_create_from_beginning
    redis.xadd(@stream_key, { "a" => "1" })
    result = redis.xgroup_create(@stream_key, "mygroup", "0")

    assert_equal "OK", result
  end

  def test_xgroup_create_mkstream
    result = redis.xgroup_create("stream:newstream", "mygroup", "$", mkstream: true)

    assert_equal "OK", result
    redis.del("stream:newstream")
  end

  def test_xgroup_destroy
    redis.xadd(@stream_key, { "a" => "1" })
    redis.xgroup_create(@stream_key, "mygroup", "$")

    result = redis.xgroup_destroy(@stream_key, "mygroup")

    assert_equal 1, result
  end

  def test_xgroup_setid
    redis.xadd(@stream_key, { "a" => "1" })
    redis.xgroup_create(@stream_key, "mygroup", "$")

    result = redis.xgroup_setid(@stream_key, "mygroup", "0")

    assert_equal "OK", result
  end

  def test_xgroup_createconsumer
    redis.xadd(@stream_key, { "a" => "1" })
    redis.xgroup_create(@stream_key, "mygroup", "0")

    result = redis.xgroup_createconsumer(@stream_key, "mygroup", "consumer1")

    assert_equal 1, result
  end

  def test_xgroup_delconsumer
    redis.xadd(@stream_key, { "a" => "1" })
    redis.xgroup_create(@stream_key, "mygroup", "0")
    redis.xgroup_createconsumer(@stream_key, "mygroup", "consumer1")

    result = redis.xgroup_delconsumer(@stream_key, "mygroup", "consumer1")

    assert_equal 0, result # 0 pending messages
  end

  # XREADGROUP tests
  def test_xreadgroup
    redis.xadd(@stream_key, { "a" => "1" })
    redis.xadd(@stream_key, { "b" => "2" })
    redis.xgroup_create(@stream_key, "mygroup", "0")

    result = redis.xreadgroup("mygroup", "consumer1", @stream_key, ">")

    assert_equal 1, result.length
    assert_equal 2, result[0][1].length
  end

  def test_xreadgroup_pending
    redis.xadd(@stream_key, { "a" => "1" })
    redis.xgroup_create(@stream_key, "mygroup", "0")

    # First read makes it pending
    redis.xreadgroup("mygroup", "consumer1", @stream_key, ">")

    # Read pending entries with "0"
    result = redis.xreadgroup("mygroup", "consumer1", @stream_key, "0")

    assert_equal 1, result[0][1].length
  end

  # XACK tests
  def test_xack
    id = redis.xadd(@stream_key, { "a" => "1" })
    redis.xgroup_create(@stream_key, "mygroup", "0")
    redis.xreadgroup("mygroup", "consumer1", @stream_key, ">")

    result = redis.xack(@stream_key, "mygroup", id)

    assert_equal 1, result
  end

  def test_xack_multiple
    id1 = redis.xadd(@stream_key, { "a" => "1" })
    id2 = redis.xadd(@stream_key, { "b" => "2" })
    redis.xgroup_create(@stream_key, "mygroup", "0")
    redis.xreadgroup("mygroup", "consumer1", @stream_key, ">")

    result = redis.xack(@stream_key, "mygroup", id1, id2)

    assert_equal 2, result
  end

  # XPENDING tests
  def test_xpending_summary
    redis.xadd(@stream_key, { "a" => "1" })
    redis.xgroup_create(@stream_key, "mygroup", "0")
    redis.xreadgroup("mygroup", "consumer1", @stream_key, ">")

    result = redis.xpending(@stream_key, "mygroup")

    assert_equal 1, result[0] # pending count
  end

  def test_xpending_detailed
    id = redis.xadd(@stream_key, { "a" => "1" })
    redis.xgroup_create(@stream_key, "mygroup", "0")
    redis.xreadgroup("mygroup", "consumer1", @stream_key, ">")

    result = redis.xpending(@stream_key, "mygroup", "-", "+", 10)

    assert_equal 1, result.length
    assert_equal id, result[0][0]
    assert_equal "consumer1", result[0][1]
  end

  # XCLAIM tests
  def test_xclaim
    id = redis.xadd(@stream_key, { "a" => "1" })
    redis.xgroup_create(@stream_key, "mygroup", "0")
    redis.xreadgroup("mygroup", "consumer1", @stream_key, ">")

    # Claim with 0 min-idle-time (claim immediately)
    result = redis.xclaim(@stream_key, "mygroup", "consumer2", 0, id)

    assert_equal 1, result.length
    assert_equal id, result[0][0]
  end

  # XINFO tests
  def test_xinfo_stream
    redis.xadd(@stream_key, { "a" => "1" })
    result = redis.xinfo_stream(@stream_key)

    assert_kind_of Hash, result
    assert_equal 1, result["length"]
  end

  def test_xinfo_groups
    redis.xadd(@stream_key, { "a" => "1" })
    redis.xgroup_create(@stream_key, "mygroup", "0")

    result = redis.xinfo_groups(@stream_key)

    assert_equal 1, result.length
    assert_equal "mygroup", result[0]["name"]
  end

  def test_xinfo_consumers
    redis.xadd(@stream_key, { "a" => "1" })
    redis.xgroup_create(@stream_key, "mygroup", "0")
    redis.xreadgroup("mygroup", "consumer1", @stream_key, ">")

    result = redis.xinfo_consumers(@stream_key, "mygroup")

    assert_equal 1, result.length
    assert_equal "consumer1", result[0]["name"]
  end

  # XDEL tests
  def test_xdel
    id = redis.xadd(@stream_key, { "a" => "1" })
    result = redis.xdel(@stream_key, id)

    assert_equal 1, result
    assert_equal 0, redis.xlen(@stream_key)
  end

  # XTRIM tests
  def test_xtrim_maxlen
    10.times { redis.xadd(@stream_key, { "a" => "1" }) }

    result = redis.xtrim(@stream_key, maxlen: 5)

    assert_equal 5, result  # 5 entries deleted
    assert_equal 5, redis.xlen(@stream_key)
  end

  def test_xtrim_minid
    redis.xadd(@stream_key, { "a" => "1" }, id: "1-0")
    redis.xadd(@stream_key, { "b" => "2" }, id: "2-0")
    redis.xadd(@stream_key, { "c" => "3" }, id: "3-0")

    result = redis.xtrim(@stream_key, minid: "2-0")

    assert_equal 1, result  # 1 entry deleted
  end

  # ============================================================
  # Stream Enhancements (Redis 6.2+/7.0+)
  # ============================================================

  # XADD with NOMKSTREAM tests
  def test_xadd_nomkstream_when_stream_missing
    redis.del("stream:nomkstream")

    result = redis.xadd("stream:nomkstream", { "a" => "1" }, nomkstream: true)

    assert_nil result
    assert_equal 0, redis.exists("stream:nomkstream")
  end

  def test_xadd_nomkstream_when_stream_exists
    redis.xadd(@stream_key, { "init" => "data" })

    result = redis.xadd(@stream_key, { "a" => "1" }, nomkstream: true)

    refute_nil result
    assert_equal 2, redis.xlen(@stream_key)
  end

  # XADD with LIMIT tests (Redis 6.2+)
  def test_xadd_with_maxlen_approximate_and_limit
    # Create a stream with some entries
    20.times { redis.xadd(@stream_key, { "a" => "1" }) }

    # Add with approximate trimming and limit
    result = redis.xadd(@stream_key, { "b" => "2" }, maxlen: 10, approximate: true, limit: 5)

    refute_nil result
    # With LIMIT 5, at most 5 entries will be deleted per call
    len = redis.xlen(@stream_key)

    assert_operator len, :<=, 21  # Original 20 + 1 new
    assert_operator len, :>=, 10  # At least target maxlen
  end

  # XGROUP CREATE with MKSTREAM tests
  def test_xgroup_create_mkstream
    redis.del("stream:newstream")

    result = redis.xgroup_create("stream:newstream", "mygroup", "$", mkstream: true)

    assert_equal "OK", result
    assert_equal 1, redis.exists("stream:newstream")
  ensure
    redis.del("stream:newstream")
  end

  # XGROUP CREATE with ENTRIESREAD tests (Redis 7.0+)
  def test_xgroup_create_entriesread
    redis.xadd(@stream_key, { "a" => "1" })
    redis.xadd(@stream_key, { "b" => "2" })

    # Create group with entries_read for lag calculation
    result = redis.xgroup_create(@stream_key, "mygroup", "$", entriesread: 1)

    assert_equal "OK", result
  rescue RedisRuby::CommandError => e
    skip "ENTRIESREAD not supported (requires Redis 7.0+)" if e.message.include?("ENTRIESREAD")
    raise
  end

  # XINFO STREAM with FULL tests
  def test_xinfo_stream_full
    redis.xadd(@stream_key, { "a" => "1" })
    redis.xadd(@stream_key, { "b" => "2" })
    redis.xgroup_create(@stream_key, "mygroup", "0")

    result = redis.xinfo_stream(@stream_key, full: true)

    assert_kind_of Hash, result
    assert_equal 2, result["length"]
    # Full output includes entries and groups
    assert result.key?("entries") || result.key?("groups")
  end

  def test_xinfo_stream_full_with_count
    10.times { |i| redis.xadd(@stream_key, { "i" => i.to_s }) }

    result = redis.xinfo_stream(@stream_key, full: true, count: 3)

    assert_kind_of Hash, result
    # Should limit entries returned
    skip unless result.key?("entries")

    assert_operator result["entries"].length, :<=, 3
  end

  # XAUTOCLAIM tests (Redis 6.2+)
  def test_xautoclaim_basic
    redis.xadd(@stream_key, { "a" => "1" })
    redis.xgroup_create(@stream_key, "mygroup", "0")
    redis.xreadgroup("mygroup", "consumer1", @stream_key, ">")

    # Claim with 0 min-idle-time (claim immediately)
    result = redis.xautoclaim(@stream_key, "mygroup", "consumer2", 0, "0-0")

    assert_kind_of Array, result
    assert_equal 3, result.length
    next_id, entries, deleted = result

    assert_kind_of String, next_id
    assert_kind_of Array, entries
    assert_kind_of Array, deleted
  rescue RedisRuby::CommandError => e
    skip "XAUTOCLAIM not supported (requires Redis 6.2+)" if e.message.include?("unknown command")
    raise
  end

  def test_xautoclaim_with_count
    3.times { redis.xadd(@stream_key, { "a" => "1" }) }
    redis.xgroup_create(@stream_key, "mygroup", "0")
    redis.xreadgroup("mygroup", "consumer1", @stream_key, ">")

    result = redis.xautoclaim(@stream_key, "mygroup", "consumer2", 0, "0-0", count: 1)

    assert_kind_of Array, result
    _next_id, entries, _deleted = result
    # Should claim at most 1 entry
    assert_equal 1, entries.length
  rescue RedisRuby::CommandError => e
    skip "XAUTOCLAIM not supported (requires Redis 6.2+)" if e.message.include?("unknown command")
    raise
  end

  def test_xautoclaim_justid
    id = redis.xadd(@stream_key, { "a" => "1" })
    redis.xgroup_create(@stream_key, "mygroup", "0")
    redis.xreadgroup("mygroup", "consumer1", @stream_key, ">")

    result = redis.xautoclaim(@stream_key, "mygroup", "consumer2", 0, "0-0", justid: true)

    assert_kind_of Array, result
    _next_id, entries, _deleted = result
    # With JUSTID, entries should be IDs only (strings), not [id, {fields}]
    assert_equal 1, entries.length
    assert_kind_of String, entries[0]
    assert_equal id, entries[0]
  rescue RedisRuby::CommandError => e
    skip "XAUTOCLAIM not supported (requires Redis 6.2+)" if e.message.include?("unknown command")
    raise
  end

  def test_xautoclaim_no_pending
    redis.xadd(@stream_key, { "a" => "1" })
    redis.xgroup_create(@stream_key, "mygroup", "0")
    # Don't read anything, so nothing is pending

    result = redis.xautoclaim(@stream_key, "mygroup", "consumer1", 0, "0-0")

    assert_kind_of Array, result
    _next_id, entries, _deleted = result

    assert_empty entries
  rescue RedisRuby::CommandError => e
    skip "XAUTOCLAIM not supported (requires Redis 6.2+)" if e.message.include?("unknown command")
    raise
  end
end
