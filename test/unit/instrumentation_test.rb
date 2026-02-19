# frozen_string_literal: true

require_relative "../test_helper"

module RR
  class InstrumentationTest < Minitest::Test
    def setup
      @instrumentation = RR::Instrumentation.new
    end

    def teardown
      @instrumentation.reset!
    end

    # Basic instrumentation tests
    def test_instrumentation_tracks_command_count
      @instrumentation.record_command("SET", 0.001)
      @instrumentation.record_command("GET", 0.001)
      @instrumentation.record_command("SET", 0.001)

      assert_equal 3, @instrumentation.command_count
    end

    def test_instrumentation_tracks_command_count_by_name
      @instrumentation.record_command("SET", 0.001)
      @instrumentation.record_command("SET", 0.001)
      @instrumentation.record_command("GET", 0.001)
      @instrumentation.record_command("DEL", 0.001)

      assert_equal 2, @instrumentation.command_count_by_name("SET")
      assert_equal 1, @instrumentation.command_count_by_name("GET")
      assert_equal 1, @instrumentation.command_count_by_name("DEL")
    end

    def test_instrumentation_tracks_command_latency
      @instrumentation.record_command("SET", 0.005)

      latency = @instrumentation.command_latency("SET")

      assert_kind_of Float, latency
      assert_in_delta(0.005, latency)
    end

    def test_instrumentation_tracks_average_latency
      @instrumentation.record_command("SET", 0.001)
      @instrumentation.record_command("SET", 0.002)
      @instrumentation.record_command("SET", 0.003)
      @instrumentation.record_command("SET", 0.004)
      @instrumentation.record_command("SET", 0.005)

      avg_latency = @instrumentation.average_latency("SET")

      assert_kind_of Float, avg_latency
      assert_in_delta 0.003, avg_latency, 0.0001
    end

    def test_instrumentation_tracks_error_count
      error = RR::CommandError.new("ERR unknown command")
      @instrumentation.record_command("INVALID", 0.001, error: error)

      assert_equal 1, @instrumentation.error_count
    end

    def test_instrumentation_tracks_error_count_by_type
      error = RR::CommandError.new("ERR unknown command")
      @instrumentation.record_command("INVALID", 0.001, error: error)

      assert_equal 1, @instrumentation.error_count_by_type("CommandError")
    end

    def test_instrumentation_provides_snapshot
      @instrumentation.record_command("SET", 0.001)
      @instrumentation.record_command("GET", 0.002)

      snapshot = @instrumentation.snapshot

      assert_equal 2, snapshot[:total_commands]
      assert_kind_of Hash, snapshot[:commands]
      assert_equal 1, snapshot[:commands]["SET"][:count]
      assert_equal 1, snapshot[:commands]["GET"][:count]
      assert_in_delta(0.001, snapshot[:commands]["SET"][:total_time])
      assert_in_delta(0.002, snapshot[:commands]["GET"][:total_time])
    end

    def test_instrumentation_can_be_reset
      @instrumentation.record_command("SET", 0.001)

      assert_equal 1, @instrumentation.command_count

      @instrumentation.reset!

      assert_equal 0, @instrumentation.command_count
    end

    def test_instrumentation_is_thread_safe
      threads = Array.new(10) do
        Thread.new do
          10.times { @instrumentation.record_command("SET", 0.001) }
        end
      end

      threads.each(&:join)

      assert_equal 100, @instrumentation.command_count
    end

    # Connection pool metrics tests
    # These tests are for future enhancement - pool-level metrics
    # Current instrumentation tracks command-level metrics only
    def test_pool_metrics_track_active_connections
      # Future enhancement: Add pool.pool_metrics method to PooledClient
      # that returns active/idle/total connection counts from the underlying
      # ConnectionPool object
      pool = RR.pooled(pool: { size: 5 })

      # For now, verify pool works with instrumentation
      pool.set("key", "value")
      pool.get("key")

      pool.close
    end

    def test_pool_metrics_track_wait_time
      # Future enhancement: Track time spent waiting for connections
      # from the pool (when all connections are busy)
      pool = RR.pooled(pool: { size: 1, timeout: 5 })

      # For now, verify pool works with instrumentation
      pool.set("key", "value")
      pool.get("key")

      pool.close
    end

    # Callback-based instrumentation tests
    def test_instrumentation_supports_before_command_callback
      called = false
      command_name = nil
      command_args = nil

      @instrumentation.before_command do |cmd, args|
        called = true
        command_name = cmd
        command_args = args
      end

      # Simulate calling the callback
      @instrumentation.before_callbacks.each { |cb| cb.call("SET", %w[key value]) }

      assert called
      assert_equal "SET", command_name
      assert_equal %w[key value], command_args
    end

    def test_instrumentation_supports_after_command_callback
      called = false
      command_name = nil
      duration_recorded = nil

      @instrumentation.after_command do |cmd, _args, duration|
        called = true
        command_name = cmd
        duration_recorded = duration
      end

      # Simulate calling the callback
      @instrumentation.after_callbacks.each { |cb| cb.call("SET", %w[key value], 0.005) }

      assert called
      assert_equal "SET", command_name
      assert_in_delta(0.005, duration_recorded)
    end
  end
end
