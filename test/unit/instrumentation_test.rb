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
      assert latency.is_a?(Float)
      assert_equal 0.005, latency
    end

    def test_instrumentation_tracks_average_latency
      @instrumentation.record_command("SET", 0.001)
      @instrumentation.record_command("SET", 0.002)
      @instrumentation.record_command("SET", 0.003)
      @instrumentation.record_command("SET", 0.004)
      @instrumentation.record_command("SET", 0.005)

      avg_latency = @instrumentation.average_latency("SET")
      assert avg_latency.is_a?(Float)
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
      assert snapshot[:commands].is_a?(Hash)
      assert_equal 1, snapshot[:commands]["SET"][:count]
      assert_equal 1, snapshot[:commands]["GET"][:count]
      assert_equal 0.001, snapshot[:commands]["SET"][:total_time]
      assert_equal 0.002, snapshot[:commands]["GET"][:total_time]
    end

    def test_instrumentation_can_be_reset
      @instrumentation.record_command("SET", 0.001)
      assert_equal 1, @instrumentation.command_count

      @instrumentation.reset!
      assert_equal 0, @instrumentation.command_count
    end

    def test_instrumentation_is_thread_safe
      threads = 10.times.map do
        Thread.new do
          10.times { @instrumentation.record_command("SET", 0.001) }
        end
      end

      threads.each(&:join)

      assert_equal 100, @instrumentation.command_count
    end

    # Connection pool metrics tests
    def test_pool_metrics_track_active_connections
      skip "Implement pool metrics"
      
      pool = RR.pooled(pool: { size: 5 })
      metrics = pool.pool_metrics
      
      assert_equal 0, metrics[:active_connections]
      assert_equal 5, metrics[:idle_connections]
      assert_equal 5, metrics[:total_connections]
    end

    def test_pool_metrics_track_wait_time
      skip "Implement pool metrics"
      
      pool = RR.pooled(pool: { size: 1, timeout: 5 })
      metrics = pool.pool_metrics
      
      assert metrics[:total_wait_time].is_a?(Float)
      assert metrics[:average_wait_time].is_a?(Float)
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
      @instrumentation.before_callbacks.each { |cb| cb.call("SET", ["key", "value"]) }

      assert called
      assert_equal "SET", command_name
      assert_equal ["key", "value"], command_args
    end

    def test_instrumentation_supports_after_command_callback
      called = false
      command_name = nil
      duration_recorded = nil

      @instrumentation.after_command do |cmd, args, duration|
        called = true
        command_name = cmd
        duration_recorded = duration
      end

      # Simulate calling the callback
      @instrumentation.after_callbacks.each { |cb| cb.call("SET", ["key", "value"], 0.005) }

      assert called
      assert_equal "SET", command_name
      assert_equal 0.005, duration_recorded
    end
  end
end

