# frozen_string_literal: true

require "test_helper"

class StreamsIntegrationTest < Minitest::Test
  def setup
    @redis = RedisRuby.new(host: ENV.fetch("REDIS_HOST", "redis"), port: ENV.fetch("REDIS_PORT", 6379).to_i)
    @redis.del("stream:test", "stream:test2")
  end

  def teardown
    # Clean up consumer groups
    begin
      @redis.xgroup_destroy("stream:test", "mygroup")
    rescue RedisRuby::CommandError
      # Ignore if group doesn't exist
    end
    @redis.del("stream:test", "stream:test2")
    @redis.close
  end

  # XADD tests
  def test_xadd_auto_id
    id = @redis.xadd("stream:test", { "field" => "value" })
    assert_match(/\d+-\d+/, id)
  end

  def test_xadd_explicit_id
    id = @redis.xadd("stream:test", { "field" => "value" }, id: "1000-0")
    assert_equal "1000-0", id
  end

  def test_xadd_multiple_fields
    id = @redis.xadd("stream:test", { "name" => "Alice", "age" => "30", "city" => "NYC" })
    refute_nil id

    entries = @redis.xrange("stream:test", "-", "+")
    assert_equal 1, entries.length
    assert_equal({ "name" => "Alice", "age" => "30", "city" => "NYC" }, entries[0][1])
  end

  def test_xadd_with_maxlen
    10.times { |i| @redis.xadd("stream:test", { "i" => i.to_s }) }
    @redis.xadd("stream:test", { "i" => "10" }, maxlen: 5)

    length = @redis.xlen("stream:test")
    assert_operator length, :<=, 5
  end

  def test_xadd_with_maxlen_approximate
    10.times { |i| @redis.xadd("stream:test", { "i" => i.to_s }) }
    @redis.xadd("stream:test", { "i" => "10" }, maxlen: 5, approximate: true)

    # Approximate may keep more entries
    length = @redis.xlen("stream:test")
    assert_operator length, :<=, 11
  end

  def test_xadd_with_minid
    @redis.xadd("stream:test", { "a" => "1" }, id: "1000-0")
    @redis.xadd("stream:test", { "b" => "2" }, id: "2000-0")
    @redis.xadd("stream:test", { "c" => "3" }, id: "3000-0", minid: "2500-0")

    entries = @redis.xrange("stream:test", "-", "+")
    # Should have trimmed entries before minid
    assert entries.all? { |e| e[0] >= "2500-0" }
  end

  def test_xadd_nomkstream
    # NOMKSTREAM prevents creating stream if it doesn't exist
    result = @redis.xadd("stream:nonexistent", { "a" => "1" }, nomkstream: true)
    assert_nil result
  end

  # XLEN tests
  def test_xlen_empty
    assert_equal 0, @redis.xlen("stream:test")
  end

  def test_xlen_with_entries
    3.times { |i| @redis.xadd("stream:test", { "i" => i.to_s }) }
    assert_equal 3, @redis.xlen("stream:test")
  end

  # XRANGE tests
  def test_xrange_all
    @redis.xadd("stream:test", { "a" => "1" }, id: "1-0")
    @redis.xadd("stream:test", { "b" => "2" }, id: "2-0")
    @redis.xadd("stream:test", { "c" => "3" }, id: "3-0")

    entries = @redis.xrange("stream:test", "-", "+")
    assert_equal 3, entries.length
    assert_equal "1-0", entries[0][0]
    assert_equal({ "a" => "1" }, entries[0][1])
  end

  def test_xrange_with_range
    @redis.xadd("stream:test", { "a" => "1" }, id: "1-0")
    @redis.xadd("stream:test", { "b" => "2" }, id: "2-0")
    @redis.xadd("stream:test", { "c" => "3" }, id: "3-0")

    entries = @redis.xrange("stream:test", "1-0", "2-0")
    assert_equal 2, entries.length
  end

  def test_xrange_with_count
    5.times { |i| @redis.xadd("stream:test", { "i" => i.to_s }) }

    entries = @redis.xrange("stream:test", "-", "+", count: 2)
    assert_equal 2, entries.length
  end

  # XREVRANGE tests
  def test_xrevrange
    @redis.xadd("stream:test", { "a" => "1" }, id: "1-0")
    @redis.xadd("stream:test", { "b" => "2" }, id: "2-0")
    @redis.xadd("stream:test", { "c" => "3" }, id: "3-0")

    entries = @redis.xrevrange("stream:test", "+", "-")
    assert_equal 3, entries.length
    assert_equal "3-0", entries[0][0]  # Newest first
  end

  # XREAD tests
  def test_xread_single_stream
    @redis.xadd("stream:test", { "a" => "1" }, id: "1-0")
    @redis.xadd("stream:test", { "b" => "2" }, id: "2-0")

    result = @redis.xread("stream:test", "0-0")
    assert_equal 1, result.length
    assert_equal "stream:test", result[0][0]
    assert_equal 2, result[0][1].length
  end

  def test_xread_from_id
    @redis.xadd("stream:test", { "a" => "1" }, id: "1-0")
    @redis.xadd("stream:test", { "b" => "2" }, id: "2-0")
    @redis.xadd("stream:test", { "c" => "3" }, id: "3-0")

    result = @redis.xread("stream:test", "1-0")  # After 1-0
    entries = result[0][1]
    assert_equal 2, entries.length
    assert_equal "2-0", entries[0][0]
  end

  def test_xread_multiple_streams
    @redis.xadd("stream:test", { "a" => "1" })
    @redis.xadd("stream:test2", { "b" => "2" })

    result = @redis.xread({ "stream:test" => "0-0", "stream:test2" => "0-0" })
    assert_equal 2, result.length
  end

  def test_xread_with_count
    5.times { |i| @redis.xadd("stream:test", { "i" => i.to_s }) }

    result = @redis.xread("stream:test", "0-0", count: 2)
    assert_equal 2, result[0][1].length
  end

  # XREAD with BLOCK is tricky to test without threading
  # Skip for now, tested manually

  # XGROUP tests
  def test_xgroup_create
    @redis.xadd("stream:test", { "a" => "1" })
    result = @redis.xgroup_create("stream:test", "mygroup", "$")
    assert_equal "OK", result
  end

  def test_xgroup_create_from_beginning
    @redis.xadd("stream:test", { "a" => "1" })
    result = @redis.xgroup_create("stream:test", "mygroup", "0")
    assert_equal "OK", result
  end

  def test_xgroup_create_mkstream
    result = @redis.xgroup_create("stream:newstream", "mygroup", "$", mkstream: true)
    assert_equal "OK", result
    @redis.del("stream:newstream")
  end

  def test_xgroup_destroy
    @redis.xadd("stream:test", { "a" => "1" })
    @redis.xgroup_create("stream:test", "mygroup", "$")

    result = @redis.xgroup_destroy("stream:test", "mygroup")
    assert_equal 1, result
  end

  def test_xgroup_setid
    @redis.xadd("stream:test", { "a" => "1" })
    @redis.xgroup_create("stream:test", "mygroup", "$")

    result = @redis.xgroup_setid("stream:test", "mygroup", "0")
    assert_equal "OK", result
  end

  def test_xgroup_createconsumer
    @redis.xadd("stream:test", { "a" => "1" })
    @redis.xgroup_create("stream:test", "mygroup", "0")

    result = @redis.xgroup_createconsumer("stream:test", "mygroup", "consumer1")
    assert_equal 1, result
  end

  def test_xgroup_delconsumer
    @redis.xadd("stream:test", { "a" => "1" })
    @redis.xgroup_create("stream:test", "mygroup", "0")
    @redis.xgroup_createconsumer("stream:test", "mygroup", "consumer1")

    result = @redis.xgroup_delconsumer("stream:test", "mygroup", "consumer1")
    assert_equal 0, result  # 0 pending messages
  end

  # XREADGROUP tests
  def test_xreadgroup
    @redis.xadd("stream:test", { "a" => "1" })
    @redis.xadd("stream:test", { "b" => "2" })
    @redis.xgroup_create("stream:test", "mygroup", "0")

    result = @redis.xreadgroup("mygroup", "consumer1", "stream:test", ">")
    assert_equal 1, result.length
    assert_equal 2, result[0][1].length
  end

  def test_xreadgroup_pending
    @redis.xadd("stream:test", { "a" => "1" })
    @redis.xgroup_create("stream:test", "mygroup", "0")

    # First read makes it pending
    @redis.xreadgroup("mygroup", "consumer1", "stream:test", ">")

    # Read pending entries with "0"
    result = @redis.xreadgroup("mygroup", "consumer1", "stream:test", "0")
    assert_equal 1, result[0][1].length
  end

  # XACK tests
  def test_xack
    id = @redis.xadd("stream:test", { "a" => "1" })
    @redis.xgroup_create("stream:test", "mygroup", "0")
    @redis.xreadgroup("mygroup", "consumer1", "stream:test", ">")

    result = @redis.xack("stream:test", "mygroup", id)
    assert_equal 1, result
  end

  def test_xack_multiple
    id1 = @redis.xadd("stream:test", { "a" => "1" })
    id2 = @redis.xadd("stream:test", { "b" => "2" })
    @redis.xgroup_create("stream:test", "mygroup", "0")
    @redis.xreadgroup("mygroup", "consumer1", "stream:test", ">")

    result = @redis.xack("stream:test", "mygroup", id1, id2)
    assert_equal 2, result
  end

  # XPENDING tests
  def test_xpending_summary
    @redis.xadd("stream:test", { "a" => "1" })
    @redis.xgroup_create("stream:test", "mygroup", "0")
    @redis.xreadgroup("mygroup", "consumer1", "stream:test", ">")

    result = @redis.xpending("stream:test", "mygroup")
    assert_equal 1, result[0]  # pending count
  end

  def test_xpending_detailed
    id = @redis.xadd("stream:test", { "a" => "1" })
    @redis.xgroup_create("stream:test", "mygroup", "0")
    @redis.xreadgroup("mygroup", "consumer1", "stream:test", ">")

    result = @redis.xpending("stream:test", "mygroup", "-", "+", 10)
    assert_equal 1, result.length
    assert_equal id, result[0][0]
    assert_equal "consumer1", result[0][1]
  end

  # XCLAIM tests
  def test_xclaim
    id = @redis.xadd("stream:test", { "a" => "1" })
    @redis.xgroup_create("stream:test", "mygroup", "0")
    @redis.xreadgroup("mygroup", "consumer1", "stream:test", ">")

    # Claim with 0 min-idle-time (claim immediately)
    result = @redis.xclaim("stream:test", "mygroup", "consumer2", 0, id)
    assert_equal 1, result.length
    assert_equal id, result[0][0]
  end

  # XINFO tests
  def test_xinfo_stream
    @redis.xadd("stream:test", { "a" => "1" })
    result = @redis.xinfo_stream("stream:test")

    assert_kind_of Hash, result
    assert_equal 1, result["length"]
  end

  def test_xinfo_groups
    @redis.xadd("stream:test", { "a" => "1" })
    @redis.xgroup_create("stream:test", "mygroup", "0")

    result = @redis.xinfo_groups("stream:test")
    assert_equal 1, result.length
    assert_equal "mygroup", result[0]["name"]
  end

  def test_xinfo_consumers
    @redis.xadd("stream:test", { "a" => "1" })
    @redis.xgroup_create("stream:test", "mygroup", "0")
    @redis.xreadgroup("mygroup", "consumer1", "stream:test", ">")

    result = @redis.xinfo_consumers("stream:test", "mygroup")
    assert_equal 1, result.length
    assert_equal "consumer1", result[0]["name"]
  end

  # XDEL tests
  def test_xdel
    id = @redis.xadd("stream:test", { "a" => "1" })
    result = @redis.xdel("stream:test", id)

    assert_equal 1, result
    assert_equal 0, @redis.xlen("stream:test")
  end

  # XTRIM tests
  def test_xtrim_maxlen
    10.times { @redis.xadd("stream:test", { "a" => "1" }) }

    result = @redis.xtrim("stream:test", maxlen: 5)
    assert_equal 5, result  # 5 entries deleted
    assert_equal 5, @redis.xlen("stream:test")
  end

  def test_xtrim_minid
    @redis.xadd("stream:test", { "a" => "1" }, id: "1-0")
    @redis.xadd("stream:test", { "b" => "2" }, id: "2-0")
    @redis.xadd("stream:test", { "c" => "3" }, id: "3-0")

    result = @redis.xtrim("stream:test", minid: "2-0")
    assert_equal 1, result  # 1 entry deleted
  end
end
