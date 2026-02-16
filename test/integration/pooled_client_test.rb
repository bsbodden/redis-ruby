# frozen_string_literal: true

require "test_helper"

class PooledClientIntegrationTest < RedisRubyTestCase
  use_testcontainers!

  def setup
    super
    @pooled_client = RR::PooledClient.new(url: @redis_url, pool: { size: 5 })
  end

  def teardown
    @pooled_client&.close
    super
  end

  def test_pooled_client_basic_operations
    @pooled_client.set("pooled:key", "value")
    result = @pooled_client.get("pooled:key")

    assert_equal "value", result
  ensure
    @pooled_client.del("pooled:key")
  end

  def test_pooled_client_ping
    result = @pooled_client.ping

    assert_equal "PONG", result
  end

  def test_pooled_client_pool_size
    assert_equal 5, @pooled_client.pool_size
  end

  def test_pooled_client_concurrent_threads
    # Create test data
    10.times { |i| @pooled_client.set("pooled:thread:#{i}", "value#{i}") }

    results = []
    mutex = Mutex.new

    threads = Array.new(10) do |i|
      Thread.new do
        value = @pooled_client.get("pooled:thread:#{i}")
        mutex.synchronize { results << value }
      end
    end

    threads.each(&:join)

    assert_equal 10, results.size
    10.times do |i|
      assert_includes results, "value#{i}"
    end
  ensure
    10.times { |i| @pooled_client.del("pooled:thread:#{i}") }
  end

  def test_pooled_client_pipeline
    results = @pooled_client.pipelined do |pipe|
      pipe.set("pooled:pipe:1", "value1")
      pipe.set("pooled:pipe:2", "value2")
      pipe.get("pooled:pipe:1")
      pipe.get("pooled:pipe:2")
    end

    assert_equal %w[OK OK value1 value2], results
  ensure
    @pooled_client.del("pooled:pipe:1", "pooled:pipe:2")
  end

  def test_pooled_client_transaction
    results = @pooled_client.multi do |tx|
      tx.set("pooled:tx:key", "txvalue")
      tx.incr("pooled:tx:counter")
      tx.get("pooled:tx:key")
    end

    assert_equal "OK", results[0]
    assert_equal 1, results[1]
    assert_equal "txvalue", results[2]
  ensure
    @pooled_client.del("pooled:tx:key", "pooled:tx:counter")
  end

  def test_pooled_client_with_connection_batch
    @pooled_client.with_connection do |conn|
      conn.call("SET", "pooled:batch:1", "value1")
      conn.call("SET", "pooled:batch:2", "value2")
    end

    assert_equal "value1", @pooled_client.get("pooled:batch:1")
    assert_equal "value2", @pooled_client.get("pooled:batch:2")
  ensure
    @pooled_client.del("pooled:batch:1", "pooled:batch:2")
  end

  def test_pooled_client_hash_operations
    @pooled_client.hset("pooled:hash", "field1", "value1", "field2", "value2")
    result = @pooled_client.hgetall("pooled:hash")

    assert_equal({ "field1" => "value1", "field2" => "value2" }, result)
  ensure
    @pooled_client.del("pooled:hash")
  end

  def test_pooled_client_list_operations
    @pooled_client.rpush("pooled:list", "a", "b", "c")
    result = @pooled_client.lrange("pooled:list", 0, -1)

    assert_equal %w[a b c], result
  ensure
    @pooled_client.del("pooled:list")
  end

  def test_pooled_helper_method
    client = RR.pooled(url: @redis_url, pool: { size: 3 })
    client.set("pooled:helper", "works")

    assert_equal "works", client.get("pooled:helper")
    assert_equal 3, client.pool_size
  ensure
    client&.del("pooled:helper")
    client&.close
  end
end
