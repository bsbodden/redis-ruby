# frozen_string_literal: true

module RR
  module Connection
    # Event dispatch infrastructure for TCP connections
    #
    # Provides callback and event dispatching for connection lifecycle events.
    # Extracted from TCP to keep class size manageable.
    module TCPEventDispatch
      VALID_EVENT_TYPES = %i[connected disconnected reconnected error
                             connection_created health_check marked_for_reconnect].freeze

      # Register a callback for connection lifecycle events
      #
      # @param event_type [Symbol] Event type
      # @param callback [Proc] Callback to invoke when event occurs
      # @return [void]
      # @raise [ArgumentError] if event_type is invalid
      def register_callback(event_type, callback = nil, &block)
        callback ||= block
        raise ArgumentError, "Callback must be provided" unless callback
        raise ArgumentError, "Invalid event type: #{event_type}" unless VALID_EVENT_TYPES.include?(event_type)

        @callbacks[event_type] << callback
      end

      # Deregister a callback for connection lifecycle events
      #
      # @param event_type [Symbol] Event type
      # @param callback [Proc] Callback to remove
      # @return [void]
      def deregister_callback(event_type, callback)
        @callbacks[event_type].delete(callback)
      end

      # Perform a health check on the connection
      #
      # @param command [String] Command to use for health check (default: "PING")
      # @return [Boolean] true if healthy, false otherwise
      def health_check(command: "PING")
        return false unless connected?

        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        healthy = begin
          call(command)
          true
        rescue StandardError
          false
        end
        latency = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        trigger_event(:health_check, {
          type: :health_check, host: @host, port: @port,
          healthy: healthy, latency: latency, timestamp: Time.now,
        })
        healthy
      end

      # Disconnect from the server
      #
      # @param reason [String, nil] Reason for disconnection
      # @return [void]
      def disconnect(reason: nil)
        return unless connected?

        trigger_event(:disconnected, {
          type: :disconnected, host: @host, port: @port,
          reason: reason, timestamp: Time.now,
        })
        close
      end

      private

      # Trigger callbacks and events for a lifecycle event
      def trigger_event(event_type, event_data)
        start_time = @instrumentation ? Process.clock_gettime(Process::CLOCK_MONOTONIC) : nil
        trigger_legacy_callbacks(event_type, event_data)
        dispatch_event(event_type, event_data) if @event_dispatcher
        return unless @instrumentation && start_time

        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        @instrumentation.record_callback_execution(event_type.to_s, duration)
      end

      # Trigger legacy callbacks for backward compatibility
      def trigger_legacy_callbacks(event_type, event_data)
        return if @callbacks[event_type].empty?

        @callbacks[event_type].each do |callback|
          execute_callback(callback, event_data, "#{event_type} callback")
        end
      end

      # Execute a single callback with error handling
      def execute_callback(callback, event_data, context)
        if @async_callbacks
          @async_callbacks.execute(context: context) { callback.call(event_data) }
        elsif @callback_error_handler
          @callback_error_handler.call(context: context) { callback.call(event_data) }
        else
          callback.call(event_data)
        end
      end

      # Dispatch event to event dispatcher
      def dispatch_event(event_type, event_data)
        event = TCP::EVENT_BUILDERS.fetch(event_type, nil)&.call(event_data)
        @event_dispatcher.dispatch(event) if event
      end
    end
  end
end
