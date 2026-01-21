# frozen_string_literal: true

require "test_helper"
require "async"

class AsyncClientIntegrationTest < RedisRubyTestCase
  use_testcontainers!

  def setup
    super
    @async_client = RedisRuby::AsyncClient.new(url: @redis_url)
  end

  def teardown
    @async_client&.close
    super
  end

  def test_async_client_basic_operations
    @async_client.set("async:key", "value")
    result = @async_client.get("async:key")

    assert_equal "value", result
  ensure
    @async_client.del("async:key")
  end

  def test_async_client_ping
    result = @async_client.ping

    assert_equal "PONG", result
  end

  def test_async_client_inside_async_block
    result = nil

    Async do
      @async_client.set("async:test", "async_value")
      result = @async_client.get("async:test")
    end

    assert_equal "async_value", result
  ensure
    @async_client.del("async:test")
  end

  def test_async_client_concurrent_operations
    # Set up test data
    10.times { |i| @async_client.set("async:concurrent:#{i}", "value#{i}") }

    results = []

    Async do |task|
      # Execute 10 concurrent GET operations
      tasks = Array.new(10) do |i|
        task.async { @async_client.get("async:concurrent:#{i}") }
      end

      results = tasks.map(&:wait)
    end

    # Verify all results were retrieved
    assert_equal 10, results.size
    10.times do |i|
      assert_equal "value#{i}", results[i]
    end
  ensure
    10.times { |i| @async_client.del("async:concurrent:#{i}") }
  end

  def test_async_client_mixed_operations
    Async do |task|
      # Run different operations concurrently
      set_task = task.async { @async_client.set("async:mix:key", "value") }
      incr_task = task.async do
        @async_client.set("async:mix:counter", "0")
        @async_client.incr("async:mix:counter")
      end

      set_task.wait
      incr_task.wait

      assert_equal "value", @async_client.get("async:mix:key")
      assert_equal "1", @async_client.get("async:mix:counter")
    end
  ensure
    @async_client.del("async:mix:key", "async:mix:counter")
  end

  def test_async_client_pipeline
    results = @async_client.pipelined do |pipe|
      pipe.set("async:pipe:1", "value1")
      pipe.set("async:pipe:2", "value2")
      pipe.get("async:pipe:1")
      pipe.get("async:pipe:2")
    end

    assert_equal %w[OK OK value1 value2], results
  ensure
    @async_client.del("async:pipe:1", "async:pipe:2")
  end

  def test_async_client_transaction
    results = @async_client.multi do |tx|
      tx.set("async:tx:key", "txvalue")
      tx.incr("async:tx:counter")
      tx.get("async:tx:key")
    end

    assert_equal "OK", results[0]
    assert_equal 1, results[1]
    assert_equal "txvalue", results[2]
  ensure
    @async_client.del("async:tx:key", "async:tx:counter")
  end

  def test_async_client_hash_operations
    @async_client.hset("async:hash", "field1", "value1", "field2", "value2")

    result = @async_client.hgetall("async:hash")

    assert_equal({ "field1" => "value1", "field2" => "value2" }, result)
  ensure
    @async_client.del("async:hash")
  end

  def test_async_client_list_operations
    @async_client.rpush("async:list", "a", "b", "c")

    result = @async_client.lrange("async:list", 0, -1)

    assert_equal %w[a b c], result
  ensure
    @async_client.del("async:list")
  end

  def test_async_client_set_operations
    @async_client.sadd("async:set", "a", "b", "c")

    members = @async_client.smembers("async:set")

    assert_equal %w[a b c].sort, members.sort
  ensure
    @async_client.del("async:set")
  end

  def test_async_client_sorted_set_operations
    @async_client.zadd("async:zset", 1, "a", 2, "b", 3, "c")

    result = @async_client.zrange("async:zset", 0, -1)

    assert_equal %w[a b c], result
  ensure
    @async_client.del("async:zset")
  end

  def test_async_client_multiple_connections
    # Test that multiple async clients can work concurrently
    client2 = RedisRuby::AsyncClient.new(url: @redis_url)

    Async do |task|
      task.async { @async_client.set("async:multi:1", "client1") }
      task.async { client2.set("async:multi:2", "client2") }
    end

    assert_equal "client1", @async_client.get("async:multi:1")
    assert_equal "client2", client2.get("async:multi:2")
  ensure
    @async_client.del("async:multi:1", "async:multi:2")
    client2&.close
  end

  def test_async_client_performance_concurrent_vs_sequential
    n = 50
    key_prefix = "async:perf"

    # Setup
    n.times { |i| @async_client.set("#{key_prefix}:#{i}", "value#{i}") }

    # Sequential timing
    sequential_start = Time.now
    n.times { |i| @async_client.get("#{key_prefix}:#{i}") }
    sequential_time = Time.now - sequential_start

    # Concurrent timing (inside Async)
    concurrent_start = Time.now
    Async do |task|
      tasks = Array.new(n) { |i| task.async { @async_client.get("#{key_prefix}:#{i}") } }
      tasks.map(&:wait)
    end
    concurrent_time = Time.now - concurrent_start

    # Concurrent should generally be faster or similar (depends on scheduler overhead)
    # At minimum, it shouldn't be significantly slower (allow 3x for CI variance)
    assert_operator concurrent_time, :<=, sequential_time * 3.0,
                    "Concurrent (#{concurrent_time}s) too slow vs sequential (#{sequential_time}s)"
  ensure
    n.times { |i| @async_client.del("#{key_prefix}:#{i}") }
  end
end
