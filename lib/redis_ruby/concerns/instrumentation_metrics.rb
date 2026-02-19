# frozen_string_literal: true

module RR
  module Concerns
    # Extracted snapshot, reset, and pipeline/transaction recording for Instrumentation
    #
    # Keeps the main Instrumentation class under the line limit.
    module InstrumentationMetrics
      # Record a pipeline execution
      #
      # @param duration [Float] Execution time in seconds
      # @param command_count [Integer] Number of commands in pipeline
      def record_pipeline(duration, command_count)
        synchronize do
          @pipeline_count += 1
          @pipeline_total_time += duration
          @pipeline_command_count += command_count
        end
      end

      # Record a transaction execution
      #
      # @param duration [Float] Execution time in seconds
      # @param command_count [Integer] Number of commands in transaction
      def record_transaction(duration, command_count)
        synchronize do
          @transaction_count += 1
          @transaction_total_time += duration
          @transaction_command_count += command_count
        end
      end

      # Get a snapshot of all metrics
      #
      # @return [Hash] Metrics snapshot
      def snapshot
        synchronize do
          {
            total_commands: @total_commands,
            total_errors: @total_errors,
            commands: snapshot_commands,
            errors: @errors.dup,
            pipelines: pipeline_snapshot,
            transactions: transaction_snapshot,
            pool: pool_snapshot,
            callbacks: all_callback_metrics,
          }
        end
      end

      # Get pool metrics snapshot
      #
      # @return [Hash] Pool metrics
      def pool_snapshot
        synchronize do
          build_pool_snapshot
        end
      end

      # Reset all metrics
      #
      # @return [void]
      def reset!
        synchronize do
          reset_command_metrics
          reset_pool_metrics
          reset_pipeline_metrics
          @callback_metrics.clear
        end
      end

      private

      def snapshot_commands
        @commands.transform_values { |v| v.dup.tap { |h| h.delete(:latencies) } }
      end

      def pipeline_snapshot
        {
          count: @pipeline_count,
          total_time: @pipeline_total_time,
          avg_time: @pipeline_count.zero? ? 0.0 : @pipeline_total_time / @pipeline_count,
          total_commands: @pipeline_command_count,
          avg_commands: @pipeline_count.zero? ? 0.0 : @pipeline_command_count.to_f / @pipeline_count,
        }
      end

      def transaction_snapshot
        {
          count: @transaction_count,
          total_time: @transaction_total_time,
          avg_time: @transaction_count.zero? ? 0.0 : @transaction_total_time / @transaction_count,
          total_commands: @transaction_command_count,
          avg_commands: @transaction_count.zero? ? 0.0 : @transaction_command_count.to_f / @transaction_count,
        }
      end

      def build_pool_snapshot
        creates = @pool_metrics[:connection_creates]
        avg_create = creates.zero? ? 0.0 : @pool_metrics[:connection_create_time] / creates
        {
          connection_creates: @pool_metrics[:connection_creates],
          avg_connection_create_time: avg_create,
          total_connection_wait_time: @pool_metrics[:connection_wait_time],
          total_connection_checkout_time: @pool_metrics[:connection_checkout_time],
          connection_closes: @pool_metrics[:connection_closes].dup,
          pool_exhaustions: @pool_metrics[:pool_exhaustions],
          active_connections: @pool_metrics[:active_connections],
          idle_connections: @pool_metrics[:idle_connections],
          total_connections: @pool_metrics[:active_connections] + @pool_metrics[:idle_connections],
        }
      end

      def reset_command_metrics
        @commands.clear
        @errors.clear
        @total_commands = 0
        @total_errors = 0
      end

      def reset_pool_metrics
        @pool_metrics[:connection_creates] = 0
        @pool_metrics[:connection_create_time] = 0.0
        @pool_metrics[:connection_wait_time] = 0.0
        @pool_metrics[:connection_checkout_time] = 0.0
        @pool_metrics[:connection_closes].clear
        @pool_metrics[:pool_exhaustions] = 0
        @pool_metrics[:active_connections] = 0
        @pool_metrics[:idle_connections] = 0
      end

      def reset_pipeline_metrics
        @pipeline_count = 0
        @pipeline_total_time = 0.0
        @pipeline_command_count = 0
        @transaction_count = 0
        @transaction_total_time = 0.0
        @transaction_command_count = 0
      end
    end
  end
end
