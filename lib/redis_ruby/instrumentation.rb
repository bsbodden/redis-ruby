# frozen_string_literal: true

require "monitor"

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
  class Instrumentation
    include MonitorMixin

    attr_reader :commands, :errors, :before_callbacks, :after_callbacks

    def initialize
      super() # Initialize MonitorMixin
      @commands = Hash.new { |h, k| h[k] = { count: 0, total_time: 0.0, errors: 0 } }
      @errors = Hash.new(0)
      @total_commands = 0
      @total_errors = 0
      @before_callbacks = []
      @after_callbacks = []
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

    # Get a snapshot of all metrics
    #
    # @return [Hash] Metrics snapshot
    def snapshot
      synchronize do
        {
          total_commands: @total_commands,
          total_errors: @total_errors,
          commands: @commands.transform_values(&:dup),
          errors: @errors.dup,
        }
      end
    end

    # Reset all metrics
    #
    # @return [void]
    def reset!
      synchronize do
        @commands.clear
        @errors.clear
        @total_commands = 0
        @total_errors = 0
      end
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
  end
end

