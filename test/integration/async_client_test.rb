# frozen_string_literal: true

require "test_helper"
require "async"

class AsyncClientIntegrationTest < RedisRubyTestCase
  use_testcontainers!

  def setup
    super
    @async_client = RR::AsyncClient.new(url: @redis_url)
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

  def test_async_client_sequential_operations_in_async_block
    # NOTE: AsyncClient is NOT safe for concurrent fiber access.
    # For concurrent operations, use AsyncPooledClient.
    # This test verifies sequential operations within an Async block work correctly.
    10.times { |i| @async_client.set("async:seq:#{i}", "value#{i}") }

    results = []

    Async do
      # Execute 10 sequential GET operations (safe for AsyncClient)
      10.times do |i|
        results << @async_client.get("async:seq:#{i}")
      end
    end

    # Verify all results were retrieved in order
    assert_equal 10, results.size
    10.times do |i|
      assert_equal "value#{i}", results[i]
    end
  ensure
    10.times { |i| @async_client.del("async:seq:#{i}") }
  end

  def test_async_client_mixed_operations
    # NOTE: Running these sequentially because AsyncClient is NOT safe for
    # concurrent fiber access. For concurrent operations, use AsyncPooledClient.
    Async do
      @async_client.set("async:mix:key", "value")
      @async_client.set("async:mix:counter", "0")
      @async_client.incr("async:mix:counter")

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
    client2 = RR::AsyncClient.new(url: @redis_url)

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

  def test_async_client_performance_inside_async_block
    # NOTE: This test verifies that AsyncClient works efficiently inside an
    # Async block with sequential operations. For concurrent operations,
    # use AsyncPooledClient.
    n = 50
    key_prefix = "async:perf"

    # Setup
    n.times { |i| @async_client.set("#{key_prefix}:#{i}", "value#{i}") }

    # Timing operations inside Async block
    start_time = Time.now
    Async do
      n.times { |i| @async_client.get("#{key_prefix}:#{i}") }
    end
    async_time = Time.now - start_time

    # Should complete in reasonable time (< 5 seconds for 50 ops)
    assert_operator async_time, :<, 5.0,
                    "Async operations too slow: #{async_time}s for #{n} operations"
  ensure
    n.times { |i| @async_client.del("#{key_prefix}:#{i}") }
  end
end
