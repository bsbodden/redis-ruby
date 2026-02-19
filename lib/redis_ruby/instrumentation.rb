# frozen_string_literal: true

require "monitor"
require_relative "concerns/instrumentation_metrics"

module RR
  # Instrumentation and metrics collection for Redis operations
  #
  # Provides detailed metrics about command execution, latency, errors,
  # and connection pool usage. Thread-safe for concurrent access.
  #
  # @example Basic usage
  #   instrumentation = RR::Instrumentation.new
  #   client = RR.new(instrumentation: instrumentation)
  #
  #   client.set("key", "value")
  #   client.get("key")
  #
  #   puts instrumentation.snapshot
  #   # => { total_commands: 2, commands: { "SET" => {...}, "GET" => {...} } }
  #
  # @example With callbacks
  #   instrumentation = RR::Instrumentation.new
  #   instrumentation.before_command do |command, args|
  #     puts "Executing: #{command} #{args.inspect}"
  #   end
  #
  #   instrumentation.after_command do |command, args, duration|
  #     puts "Completed: #{command} in #{duration}ms"
  #   end
  #
  # @example Pool metrics
  #   instrumentation = RR::Instrumentation.new
  #   client = RR.pooled(instrumentation: instrumentation, pool: { size: 10 })
  #
  #   # Get pool metrics
  #   pool_stats = instrumentation.pool_snapshot
  #   # => { connection_creates: 5, connection_wait_time: 0.001, ... }
  #
  # @example Percentile latencies
  #   instrumentation = RR::Instrumentation.new(percentiles: true)
  #   # ... execute commands ...
  #   p50 = instrumentation.percentile_latency("GET", 50)  # median
  #   p95 = instrumentation.percentile_latency("GET", 95)  # 95th percentile
  #   p99 = instrumentation.percentile_latency("GET", 99)  # 99th percentile
  #
  class Instrumentation
    include MonitorMixin
    include Concerns::InstrumentationMetrics

    # Connection close reasons (matching redis-py)
    module CloseReason
      NORMAL = "normal"
      ERROR = "error"
      TIMEOUT = "timeout"
      POOL_FULL = "pool_full"
      EVICTED = "evicted"
      SHUTDOWN = "shutdown"
    end

    # Connection states
    module ConnectionState
      IDLE = "idle"
      USED = "used"
    end

    attr_reader :commands, :errors, :before_callbacks, :after_callbacks, :pool_metrics

    # Initialize instrumentation
    #
    # @param percentiles [Boolean] Enable percentile latency tracking (default: false)
    # @param percentile_window_size [Integer] Number of samples to keep for percentiles (default: 1000)
    def initialize(percentiles: false, percentile_window_size: 1000)
      super() # Initialize MonitorMixin
      initialize_command_metrics(percentiles)
      initialize_pool_metrics
      initialize_pipeline_metrics
      @percentiles_enabled = percentiles
      @percentile_window_size = percentile_window_size
    end

    # Record a command execution
    #
    # @param command [String] Command name
    # @param duration [Float] Execution time in seconds
    # @param error [Exception, nil] Error if command failed
    # @return [void]
    def record_command(command, duration, error: nil)
      synchronize do
        cmd = command.to_s.upcase
        @commands[cmd][:count] += 1
        @commands[cmd][:total_time] += duration
        @total_commands += 1

        if error
          @commands[cmd][:errors] += 1
          error_type = error.class.name.split("::").last
          @errors[error_type] += 1
          @total_errors += 1
        else
          @commands[cmd][:success] += 1
        end

        # Track latency samples for percentiles
        if @percentiles_enabled && @commands[cmd][:latencies]
          latencies = @commands[cmd][:latencies]
          latencies << duration
          # Keep only the most recent samples (sliding window)
          latencies.shift if latencies.size > @percentile_window_size
        end
      end
    end

    # Record connection creation
    #
    # @param duration [Float] Time to create connection in seconds
    # @return [void]
    def record_connection_create(duration)
      synchronize do
        @pool_metrics[:connection_creates] += 1
        @pool_metrics[:connection_create_time] += duration
      end
    end

    # Record connection wait time
    #
    # @param duration [Float] Time waiting for connection in seconds
    # @return [void]
    def record_connection_wait(duration)
      synchronize do
        @pool_metrics[:connection_wait_time] += duration
      end
    end

    # Record connection checkout time
    #
    # @param duration [Float] Time to checkout connection in seconds
    # @return [void]
    def record_connection_checkout(duration)
      synchronize do
        @pool_metrics[:connection_checkout_time] += duration
      end
    end

    # Record connection close
    #
    # @param reason [String] Reason for closing (use CloseReason constants)
    # @return [void]
    def record_connection_close(reason)
      synchronize do
        @pool_metrics[:connection_closes][reason] += 1
      end
    end

    # Record pool exhaustion event
    #
    # @return [void]
    def record_pool_exhaustion
      synchronize do
        @pool_metrics[:pool_exhaustions] += 1
      end
    end

    # Update connection counts
    #
    # @param active [Integer] Number of active connections
    # @param idle [Integer] Number of idle connections
    # @return [void]
    def update_connection_counts(active:, idle:)
      synchronize do
        @pool_metrics[:active_connections] = active
        @pool_metrics[:idle_connections] = idle
      end
    end

    # Record callback execution
    #
    # @param event_type [String] Event type (e.g., "connected", "pool_exhausted")
    # @param duration [Float] Execution time in seconds
    # @param error [Exception, nil] Error if callback failed
    # @return [void]
    def record_callback_execution(event_type, duration, error: nil)
      synchronize do
        @callback_metrics[event_type][:count] += 1
        @callback_metrics[event_type][:total_time] += duration
        @callback_metrics[event_type][:errors] += 1 if error
      end
    end

    # Get callback metrics for a specific event type
    #
    # @param event_type [String] Event type
    # @return [Hash] Callback metrics
    def callback_metrics(event_type)
      synchronize do
        metrics = @callback_metrics[event_type]
        {
          count: metrics[:count],
          total_time: metrics[:total_time],
          avg_time: metrics[:count].zero? ? 0.0 : metrics[:total_time] / metrics[:count],
          errors: metrics[:errors],
        }
      end
    end

    # Get all callback metrics
    #
    # @return [Hash] All callback metrics by event type
    def all_callback_metrics
      synchronize do
        @callback_metrics.transform_values do |metrics|
          {
            count: metrics[:count],
            total_time: metrics[:total_time],
            avg_time: metrics[:count].zero? ? 0.0 : metrics[:total_time] / metrics[:count],
            errors: metrics[:errors],
          }
        end
      end
    end

    # Get total number of commands executed
    #
    # @return [Integer]
    def command_count
      synchronize { @total_commands }
    end

    # Get number of commands executed by name
    #
    # @param command [String] Command name
    # @return [Integer]
    def command_count_by_name(command)
      synchronize { @commands[command.to_s.upcase][:count] }
    end

    # Get last recorded latency for a command
    #
    # @param command [String] Command name
    # @return [Float, nil] Latency in seconds, or nil if no data
    def command_latency(command)
      synchronize do
        cmd_data = @commands[command.to_s.upcase]
        return nil if cmd_data[:count].zero?

        cmd_data[:total_time] / cmd_data[:count]
      end
    end

    # Get average latency for a command
    #
    # @param command [String] Command name
    # @return [Float, nil] Average latency in seconds, or nil if no data
    def average_latency(command)
      command_latency(command) # Same as command_latency for now
    end

    # Get percentile latency for a command
    #
    # @param command [String] Command name
    # @param percentile [Integer] Percentile to calculate (0-100)
    # @return [Float, nil] Percentile latency in seconds, or nil if no data
    def percentile_latency(command, percentile)
      return nil unless @percentiles_enabled

      synchronize do
        cmd_data = @commands[command.to_s.upcase]
        latencies = cmd_data[:latencies]
        return nil if latencies.nil? || latencies.empty?

        calculate_percentile(latencies, percentile)
      end
    end

    # Get success rate for a command
    #
    # @param command [String] Command name
    # @return [Float, nil] Success rate (0.0-1.0), or nil if no data
    def success_rate(command)
      synchronize do
        cmd_data = @commands[command.to_s.upcase]
        return nil if cmd_data[:count].zero?

        cmd_data[:success].to_f / cmd_data[:count]
      end
    end

    # Get error rate for a command
    #
    # @param command [String] Command name
    # @return [Float, nil] Error rate (0.0-1.0), or nil if no data
    def error_rate(command)
      synchronize do
        cmd_data = @commands[command.to_s.upcase]
        return nil if cmd_data[:count].zero?

        cmd_data[:errors].to_f / cmd_data[:count]
      end
    end

    # Get total number of errors
    #
    # @return [Integer]
    def error_count
      synchronize { @total_errors }
    end

    # Get number of errors by type
    #
    # @param error_type [String] Error type name (e.g., "CommandError")
    # @return [Integer]
    def error_count_by_type(error_type)
      synchronize { @errors[error_type] }
    end

    # Register a callback to run before each command
    #
    # @yield [command, args] Block to execute before command
    # @yieldparam command [String] Command name
    # @yieldparam args [Array] Command arguments
    # @return [void]
    def before_command(&block)
      synchronize { @before_callbacks << block }
    end

    # Register a callback to run after each command
    #
    # @yield [command, args, duration] Block to execute after command
    # @yieldparam command [String] Command name
    # @yieldparam args [Array] Command arguments
    # @yieldparam duration [Float] Execution time in seconds
    # @return [void]
    def after_command(&block)
      synchronize { @after_callbacks << block }
    end

    private

    # Initialize command-level metrics
    def initialize_command_metrics(percentiles)
      @commands = Hash.new do |h, k|
        h[k] = { count: 0, total_time: 0.0, errors: 0, success: 0, latencies: percentiles ? [] : nil }
      end
      @errors = Hash.new(0)
      @total_commands = 0
      @total_errors = 0
      @before_callbacks = []
      @after_callbacks = []
      @callback_metrics = Hash.new { |h, k| h[k] = { count: 0, total_time: 0.0, errors: 0 } }
    end

    # Initialize pool metrics
    def initialize_pool_metrics
      @pool_metrics = {
        connection_creates: 0, connection_create_time: 0.0,
        connection_wait_time: 0.0, connection_checkout_time: 0.0,
        connection_closes: Hash.new(0), pool_exhaustions: 0,
        active_connections: 0, idle_connections: 0,
      }
    end

    # Initialize pipeline/transaction metrics
    def initialize_pipeline_metrics
      @pipeline_count = 0
      @pipeline_total_time = 0.0
      @pipeline_command_count = 0
      @transaction_count = 0
      @transaction_total_time = 0.0
      @transaction_command_count = 0
    end

    # Calculate percentile from sorted array of values
    #
    # @param values [Array<Float>] Array of values
    # @param percentile [Integer] Percentile to calculate (0-100)
    # @return [Float] Percentile value
    def calculate_percentile(values, percentile)
      return nil if values.empty?
      return values.first if values.size == 1

      sorted = values.sort
      rank = (percentile / 100.0) * (sorted.size - 1)
      lower = sorted[rank.floor]
      upper = sorted[rank.ceil]

      # Linear interpolation
      lower + ((upper - lower) * (rank - rank.floor))
    end
  end
end
