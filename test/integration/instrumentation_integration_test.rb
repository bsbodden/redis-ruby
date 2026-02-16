# frozen_string_literal: true

require_relative "../test_helper"

module RR
  class InstrumentationIntegrationTest < Minitest::Test
    def setup
      @instrumentation = RR::Instrumentation.new
      @redis = RR.new(instrumentation: @instrumentation)
      @redis.flushdb
    end

    def teardown
      @redis.close
      @instrumentation.reset!
    end

    def test_client_records_commands_to_instrumentation
      @instrumentation.reset!
      
      @redis.set("key1", "value1")
      @redis.get("key1")
      @redis.set("key2", "value2")
      
      assert_equal 3, @instrumentation.command_count
      assert_equal 2, @instrumentation.command_count_by_name("SET")
      assert_equal 1, @instrumentation.command_count_by_name("GET")
    end

    def test_client_records_command_latency
      @instrumentation.reset!
      
      @redis.set("key", "value")
      
      latency = @instrumentation.command_latency("SET")
      assert latency.is_a?(Float)
      assert latency > 0
    end

    def test_client_records_errors
      @instrumentation.reset!
      
      # Trigger an error
      assert_raises(RR::CommandError) do
        @redis.call("INVALID_COMMAND")
      end
      
      assert_equal 1, @instrumentation.error_count
      assert_equal 1, @instrumentation.error_count_by_type("CommandError")
    end

    def test_client_triggers_before_command_callback
      @instrumentation.reset!
      called = false
      command_name = nil
      
      @instrumentation.before_command do |cmd, args|
        called = true
        command_name = cmd
      end
      
      @redis.set("key", "value")
      
      assert called
      assert_equal "SET", command_name
    end

    def test_client_triggers_after_command_callback
      @instrumentation.reset!
      called = false
      command_name = nil
      duration = nil
      
      @instrumentation.after_command do |cmd, args, dur|
        called = true
        command_name = cmd
        duration = dur
      end
      
      @redis.set("key", "value")
      
      assert called
      assert_equal "SET", command_name
      assert duration.is_a?(Float)
      assert duration > 0
    end

    def test_instrumentation_snapshot_provides_complete_metrics
      @instrumentation.reset!
      
      @redis.set("key1", "value1")
      @redis.get("key1")
      @redis.set("key2", "value2")
      
      snapshot = @instrumentation.snapshot
      
      assert_equal 3, snapshot[:total_commands]
      assert_equal 0, snapshot[:total_errors]
      assert_equal 2, snapshot[:commands]["SET"][:count]
      assert_equal 1, snapshot[:commands]["GET"][:count]
      assert snapshot[:commands]["SET"][:total_time] > 0
      assert snapshot[:commands]["GET"][:total_time] > 0
    end

    def test_pooled_client_records_commands
      @instrumentation.reset!
      pooled = RR.pooled(instrumentation: @instrumentation, pool: { size: 5 })
      
      pooled.set("key1", "value1")
      pooled.get("key1")
      
      assert_equal 2, @instrumentation.command_count
      
      pooled.close
    end

    def test_instrumentation_works_with_pipelined_commands
      skip "Pipeline instrumentation not yet implemented - commands are queued and sent in batch"

      @instrumentation.reset!

      @redis.pipelined do |pipe|
        pipe.set("key1", "value1")
        pipe.set("key2", "value2")
        pipe.get("key1")
      end

      # Pipelined commands should be recorded individually
      assert_equal 3, @instrumentation.command_count
      assert_equal 2, @instrumentation.command_count_by_name("SET")
      assert_equal 1, @instrumentation.command_count_by_name("GET")
    end

    def test_instrumentation_works_with_transactions
      skip "Transaction instrumentation not yet implemented - commands are queued and sent in batch"

      @instrumentation.reset!

      @redis.multi do |txn|
        txn.set("key1", "value1")
        txn.set("key2", "value2")
        txn.get("key1")
      end

      # Transaction commands should be recorded individually
      # Plus MULTI and EXEC
      assert @instrumentation.command_count >= 3
    end
  end
end

