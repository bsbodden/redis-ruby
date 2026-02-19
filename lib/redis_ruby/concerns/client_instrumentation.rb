# frozen_string_literal: true

module RR
  module Concerns
    # Extracted instrumentation and execution helpers for Client
    #
    # Provides fast-path execution methods with optional instrumentation
    # and circuit breaker support.
    module ClientInstrumentation
      private

      # Execute command with circuit breaker and instrumentation protection
      def execute_with_protection(command, args)
        if @circuit_breaker
          @circuit_breaker.call { execute_with_instrumentation(command, args) }
        else
          execute_with_instrumentation(command, args)
        end
      end

      # Execute command with optional instrumentation
      def execute_with_instrumentation(command, args)
        if @instrumentation
          call_with_instrumentation(command, args)
        else
          call_without_instrumentation(command, args)
        end
      end

      # Execute 1-arg command with optional instrumentation
      def execute_1arg_with_instrumentation(command, arg)
        if @instrumentation
          call_with_instrumentation(command, [arg])
        else
          call_1arg_without_instrumentation(command, arg)
        end
      end

      # Execute 2-args command with optional instrumentation
      def execute_2args_with_instrumentation(command, arg1, arg2)
        if @instrumentation
          call_with_instrumentation(command, [arg1, arg2])
        else
          call_2args_without_instrumentation(command, arg1, arg2)
        end
      end

      # Execute 3-args command with optional instrumentation
      def execute_3args_with_instrumentation(command, arg1, arg2, arg3)
        if @instrumentation
          call_with_instrumentation(command, [arg1, arg2, arg3])
        else
          call_3args_without_instrumentation(command, arg1, arg2, arg3)
        end
      end

      # Execute command with instrumentation
      def call_with_instrumentation(command, args)
        @instrumentation.before_callbacks.each { |cb| cb.call(command, args) }
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        error = nil

        begin
          result = call_without_instrumentation(command, args)
        rescue StandardError => e
          error = e
          raise
        ensure
          duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
          @instrumentation.record_command(command, duration, error: error)
          @instrumentation.after_callbacks.each { |cb| cb.call(command, args, duration) }
        end

        result
      end

      # Execute command without instrumentation
      def call_without_instrumentation(command, args)
        @retry_policy.call do
          ensure_connected
          result = @connection.call_direct(command, *args)
          raise result if result.is_a?(CommandError)

          @decode_responses ? decode_result(result) : result
        end
      end

      # Fast path without instrumentation
      def call_1arg_without_instrumentation(command, arg)
        @retry_policy.call do
          ensure_connected
          result = @connection.call_1arg(command, arg)
          raise result if result.is_a?(CommandError)

          @decode_responses ? decode_result(result) : result
        end
      end

      def call_2args_without_instrumentation(command, arg1, arg2)
        @retry_policy.call do
          ensure_connected
          result = @connection.call_2args(command, arg1, arg2)
          raise result if result.is_a?(CommandError)

          @decode_responses ? decode_result(result) : result
        end
      end

      def call_3args_without_instrumentation(command, arg1, arg2, arg3)
        @retry_policy.call do
          ensure_connected
          result = @connection.call_3args(command, arg1, arg2, arg3)
          raise result if result.is_a?(CommandError)

          @decode_responses ? decode_result(result) : result
        end
      end

      # Decode a result to the configured encoding
      def decode_result(result)
        case result
        when String
          result.frozen? ? result.encode(@encoding) : result.force_encoding(@encoding)
        when Array
          result.map { |v| decode_result(v) }
        when Hash
          result.each_with_object({}) { |(k, v), h| h[decode_result(k)] = decode_result(v) }
        else
          result
        end
      end
    end
  end
end
