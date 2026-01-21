# frozen_string_literal: true

require "test_helper"
require "async"

class AsyncPooledClientIntegrationTest < RedisRubyTestCase
  use_testcontainers!

  def setup
    super
    @async_pooled_client = RedisRuby::AsyncPooledClient.new(
      url: @redis_url,
      pool: { limit: 5 }
    )
  end

  def teardown
    @async_pooled_client&.close
    super
  end

  def test_async_pooled_client_basic_operations
    Async do
      @async_pooled_client.set("async_pooled:key", "value")
      result = @async_pooled_client.get("async_pooled:key")

      assert_equal "value", result
    end
  ensure
    @async_pooled_client.del("async_pooled:key")
  end

  def test_async_pooled_client_ping
    Async do
      result = @async_pooled_client.ping

      assert_equal "PONG", result
    end
  end

  def test_async_pooled_client_pool_limit
    assert_equal 5, @async_pooled_client.pool_limit
  end

  def test_async_pooled_client_concurrent_fibers
    # Setup test data
    20.times { |i| @async_pooled_client.set("async_pooled:fiber:#{i}", "value#{i}") }

    results = []

    Async do |task|
      # Run 20 concurrent operations with only 5 connections
      tasks = Array.new(20) do |i|
        task.async { @async_pooled_client.get("async_pooled:fiber:#{i}") }
      end

      results = tasks.map(&:wait)
    end

    assert_equal 20, results.size
    20.times do |i|
      assert_equal "value#{i}", results[i]
    end
  ensure
    20.times { |i| @async_pooled_client.del("async_pooled:fiber:#{i}") }
  end

  def test_async_pooled_client_pipeline
    Async do
      results = @async_pooled_client.pipelined do |pipe|
        pipe.set("async_pooled:pipe:1", "value1")
        pipe.set("async_pooled:pipe:2", "value2")
        pipe.get("async_pooled:pipe:1")
        pipe.get("async_pooled:pipe:2")
      end

      assert_equal %w[OK OK value1 value2], results
    end
  ensure
    @async_pooled_client.del("async_pooled:pipe:1", "async_pooled:pipe:2")
  end

  def test_async_pooled_client_transaction
    Async do
      results = @async_pooled_client.multi do |tx|
        tx.set("async_pooled:tx:key", "txvalue")
        tx.incr("async_pooled:tx:counter")
        tx.get("async_pooled:tx:key")
      end

      assert_equal "OK", results[0]
      assert_equal 1, results[1]
      assert_equal "txvalue", results[2]
    end
  ensure
    @async_pooled_client.del("async_pooled:tx:key", "async_pooled:tx:counter")
  end

  def test_async_pooled_client_hash_operations
    Async do
      @async_pooled_client.hset("async_pooled:hash", "field1", "value1", "field2", "value2")
      result = @async_pooled_client.hgetall("async_pooled:hash")

      assert_equal({ "field1" => "value1", "field2" => "value2" }, result)
    end
  ensure
    @async_pooled_client.del("async_pooled:hash")
  end

  def test_async_pooled_client_list_operations
    Async do
      @async_pooled_client.rpush("async_pooled:list", "a", "b", "c")
      result = @async_pooled_client.lrange("async_pooled:list", 0, -1)

      assert_equal %w[a b c], result
    end
  ensure
    @async_pooled_client.del("async_pooled:list")
  end

  def test_async_pooled_helper_method
    client = RedisRuby.async_pooled(url: @redis_url, pool: { limit: 3 })

    Async do
      client.set("async_pooled:helper", "works")

      assert_equal "works", client.get("async_pooled:helper")
    end

    assert_equal 3, client.pool_limit
  ensure
    client&.del("async_pooled:helper")
    client&.close
  end

  def test_async_pooled_high_concurrency
    # Test that pool properly limits connections under high concurrency
    n = 50
    key_prefix = "async_pooled:high_concurrency"

    # Setup
    n.times { |i| @async_pooled_client.set("#{key_prefix}:#{i}", "value#{i}") }

    results = []

    Async do |task|
      # 50 operations with 5 connections = queuing behavior
      tasks = Array.new(n) do |i|
        task.async { @async_pooled_client.get("#{key_prefix}:#{i}") }
      end

      results = tasks.map(&:wait)
    end

    assert_equal n, results.size
    n.times do |i|
      assert_equal "value#{i}", results[i]
    end
  ensure
    n.times { |i| @async_pooled_client.del("#{key_prefix}:#{i}") }
  end
end
