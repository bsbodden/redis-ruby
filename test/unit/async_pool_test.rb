# frozen_string_literal: true

require_relative "unit_test_helper"
require "socket"

class AsyncPoolPooledConnectionTest < Minitest::Test
  # ============================================================
  # PooledConnection
  # ============================================================

  def test_pooled_connection_initialize
    mock_conn = mock("connection")
    pc = RedisRuby::Connection::AsyncPool::PooledConnection.new(mock_conn)

    assert_equal 1, pc.concurrency
    assert_equal 0, pc.count
  end

  def test_pooled_connection_call_increments_count
    mock_conn = mock("connection")
    mock_conn.expects(:call).with("PING").returns("PONG")
    pc = RedisRuby::Connection::AsyncPool::PooledConnection.new(mock_conn)
    result = pc.call("PING")

    assert_equal "PONG", result
    assert_equal 1, pc.count
  end

  def test_pooled_connection_call_1arg
    mock_conn = mock("connection")
    mock_conn.expects(:call_1arg).with("GET", "key").returns("value")
    pc = RedisRuby::Connection::AsyncPool::PooledConnection.new(mock_conn)
    result = pc.call_1arg("GET", "key")

    assert_equal "value", result
    assert_equal 1, pc.count
  end

  def test_pooled_connection_call_2args
    mock_conn = mock("connection")
    mock_conn.expects(:call_2args).with("SET", "k", "v").returns("OK")
    pc = RedisRuby::Connection::AsyncPool::PooledConnection.new(mock_conn)
    result = pc.call_2args("SET", "k", "v")

    assert_equal "OK", result
    assert_equal 1, pc.count
  end

  def test_pooled_connection_call_3args
    mock_conn = mock("connection")
    mock_conn.expects(:call_3args).with("HSET", "h", "f", "v").returns(1)
    pc = RedisRuby::Connection::AsyncPool::PooledConnection.new(mock_conn)
    result = pc.call_3args("HSET", "h", "f", "v")

    assert_equal 1, result
    assert_equal 1, pc.count
  end

  def test_pooled_connection_pipeline
    mock_conn = mock("connection")
    mock_conn.expects(:pipeline).returns(%w[OK value])
    pc = RedisRuby::Connection::AsyncPool::PooledConnection.new(mock_conn)
    result = pc.pipeline

    assert_equal %w[OK value], result
    assert_equal 1, pc.count
  end

  def test_pooled_connection_viable_true
    mock_conn = mock("connection")
    mock_conn.expects(:connected?).returns(true)
    pc = RedisRuby::Connection::AsyncPool::PooledConnection.new(mock_conn)

    assert_predicate pc, :viable?
  end

  def test_pooled_connection_viable_false_when_closed
    mock_conn = mock("connection")
    pc = RedisRuby::Connection::AsyncPool::PooledConnection.new(mock_conn)
    pc.instance_variable_set(:@closed, true)

    refute_predicate pc, :viable?
  end

  def test_pooled_connection_viable_false_when_disconnected
    mock_conn = mock("connection")
    mock_conn.expects(:connected?).returns(false)
    pc = RedisRuby::Connection::AsyncPool::PooledConnection.new(mock_conn)

    refute_predicate pc, :viable?
  end

  def test_pooled_connection_closed_true
    mock_conn = mock("connection")
    pc = RedisRuby::Connection::AsyncPool::PooledConnection.new(mock_conn)
    pc.instance_variable_set(:@closed, true)

    assert_predicate pc, :closed?
  end

  def test_pooled_connection_closed_false
    mock_conn = mock("connection")
    mock_conn.expects(:connected?).returns(true)
    pc = RedisRuby::Connection::AsyncPool::PooledConnection.new(mock_conn)

    refute_predicate pc, :closed?
  end

  def test_pooled_connection_closed_when_not_connected
    mock_conn = mock("connection")
    mock_conn.expects(:connected?).returns(false)
    pc = RedisRuby::Connection::AsyncPool::PooledConnection.new(mock_conn)

    assert_predicate pc, :closed?
  end

  def test_pooled_connection_close
    mock_conn = mock("connection")
    mock_conn.expects(:close)
    pc = RedisRuby::Connection::AsyncPool::PooledConnection.new(mock_conn)
    pc.close

    assert pc.instance_variable_get(:@closed)
  end

  def test_pooled_connection_reusable
    mock_conn = mock("connection")
    mock_conn.expects(:connected?).returns(true)
    pc = RedisRuby::Connection::AsyncPool::PooledConnection.new(mock_conn)

    assert_predicate pc, :reusable?
  end

  def test_pooled_connection_not_reusable_when_closed
    mock_conn = mock("connection")
    pc = RedisRuby::Connection::AsyncPool::PooledConnection.new(mock_conn)
    pc.instance_variable_set(:@closed, true)

    refute_predicate pc, :reusable?
  end

  def test_pooled_connection_multiple_calls_increment_count
    mock_conn = mock("connection")
    mock_conn.stubs(:call).returns("PONG")
    mock_conn.stubs(:call_1arg).returns("val")
    pc = RedisRuby::Connection::AsyncPool::PooledConnection.new(mock_conn)
    pc.call("PING")
    pc.call("PING")
    pc.call_1arg("GET", "k")

    assert_equal 3, pc.count
  end
end

class AsyncPoolTest < Minitest::Test
  # ============================================================
  # AsyncPool initialization
  # ============================================================

  def test_async_pool_default_limit
    assert_equal 5, RedisRuby::Connection::AsyncPool::DEFAULT_LIMIT
  end

  def test_async_pool_requires_async_pool_gem
    # Verify that the pool requires Async::Pool::Controller
    # We test this indirectly by checking the constant exists
    assert defined?(RedisRuby::Connection::AsyncPool)
  end

  # ============================================================
  # AsyncPool with mocked dependencies
  # ============================================================

  def test_async_pool_attributes
    mock_pool_controller = mock("pool_controller")
    Async::Pool::Controller.stubs(:wrap).returns(mock_pool_controller)

    pool = RedisRuby::Connection::AsyncPool.new(host: "localhost", port: 6379, limit: 10)

    assert_equal 10, pool.limit
  end

  def test_async_pool_size
    mock_pool_controller = mock("pool_controller")
    mock_pool_controller.expects(:size).returns(3)
    Async::Pool::Controller.stubs(:wrap).returns(mock_pool_controller)

    pool = RedisRuby::Connection::AsyncPool.new(host: "localhost", port: 6379)

    assert_equal 3, pool.size
  end

  def test_async_pool_available
    mock_pool_controller = mock("pool_controller")
    mock_pool_controller.expects(:available?).returns(true)
    Async::Pool::Controller.stubs(:wrap).returns(mock_pool_controller)

    pool = RedisRuby::Connection::AsyncPool.new(host: "localhost", port: 6379)

    assert_predicate pool, :available?
  end

  def test_async_pool_close
    mock_pool_controller = mock("pool_controller")
    mock_pool_controller.expects(:close)
    Async::Pool::Controller.stubs(:wrap).returns(mock_pool_controller)

    pool = RedisRuby::Connection::AsyncPool.new(host: "localhost", port: 6379)
    pool.close
  end

  def test_async_pool_shutdown_alias
    mock_pool_controller = mock("pool_controller")
    mock_pool_controller.expects(:close)
    Async::Pool::Controller.stubs(:wrap).returns(mock_pool_controller)

    pool = RedisRuby::Connection::AsyncPool.new(host: "localhost", port: 6379)
    pool.shutdown
  end

  def test_async_pool_acquire
    mock_pool_controller = mock("pool_controller")
    mock_pool_controller.define_singleton_method(:acquire) { |&block| block.call("mock_connection") }
    Async::Pool::Controller.stubs(:wrap).returns(mock_pool_controller)

    pool = RedisRuby::Connection::AsyncPool.new(host: "localhost", port: 6379)
    result = pool.acquire { |conn| conn }

    assert_equal "mock_connection", result
  end

  def test_async_pool_with_alias
    mock_pool_controller = mock("pool_controller")
    mock_pool_controller.define_singleton_method(:acquire) { |&block| block.call("conn") }
    Async::Pool::Controller.stubs(:wrap).returns(mock_pool_controller)

    pool = RedisRuby::Connection::AsyncPool.new(host: "localhost", port: 6379)
    result = pool.with { |c| c }

    assert_equal "conn", result
  end
end
