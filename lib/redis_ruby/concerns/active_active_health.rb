# frozen_string_literal: true

module RR
  module Concerns
    # Health check and auto-fallback management for ActiveActiveClient
    #
    # Extracted to keep the main client class focused on connection management
    # and command execution.
    module ActiveActiveHealth
      private

      # Start background health checks
      # @api private
      def start_health_checks
        @health_check_runner = create_health_check_runner
        register_health_check_connections
        register_health_change_callback
        @health_check_runner.start
      end

      def create_health_check_runner
        HealthCheck::Runner.new(
          interval: @health_check_interval,
          probes: @health_check_probes,
          probe_delay: @health_check_probe_delay,
          policy: @health_check_policy
        )
      end

      def register_health_check_connections
        @regions.each do |region|
          connection = create_connection(region[:host], region[:port])
          @health_check_runner.add_check(
            database_id: region[:id],
            connection: connection
          )
        rescue ConnectionError => e
          @circuit_breakers[region[:id]].trip!
          warn "Failed to create health check connection for #{region[:host]}:#{region[:port]}: #{e.message}"
        end
      end

      def register_health_change_callback
        @health_check_runner.on_health_change do |database_id, _old_state, new_state|
          handle_health_state_change(database_id, new_state)
        end
      end

      def handle_health_state_change(database_id, new_state)
        region = @regions.find { |r| r[:id] == database_id }
        return unless region

        if new_state
          @circuit_breakers[database_id].reset!
          @failure_detectors[database_id].reset!
          dispatch_database_recovered_event(database_id)
        else
          @circuit_breakers[database_id].trip!
          dispatch_database_failed_event(database_id, "Health check failed")
        end
      end

      # Start auto-fallback thread
      # @api private
      def start_auto_fallback
        @fallback_thread = Thread.new do
          loop do
            sleep @auto_fallback_interval
            break if @shutdown

            attempt_fallback_to_preferred
          rescue StandardError => e
            warn "Auto-fallback error: #{e.message}"
          end
        end
      end

      def attempt_fallback_to_preferred
        return if @current_region_index == @preferred_region_index

        preferred_circuit = @circuit_breakers[@preferred_region_index]
        return unless preferred_circuit.closed?

        old_region = @regions[@current_region_index]
        switch_to_region(@preferred_region_index)
        new_region = @regions[@current_region_index]
        dispatch_failover_event(old_region, new_region, "auto_fallback")
      end

      # Event dispatch helpers

      def dispatch_failover_event(old_region, new_region, reason)
        @event_dispatcher.dispatch(FailoverEvent.new(
                                     from_database_id: old_region[:id],
                                     to_database_id: new_region[:id],
                                     from_region: "#{old_region[:host]}:#{old_region[:port]}",
                                     to_region: "#{new_region[:host]}:#{new_region[:port]}",
                                     reason: reason,
                                     timestamp: Time.now
                                   ))
      end

      def dispatch_database_failed_event(database_id, error_message)
        region = @regions[database_id]
        @event_dispatcher.dispatch(DatabaseFailedEvent.new(
                                     database_id: database_id,
                                     region: "#{region[:host]}:#{region[:port]}",
                                     error: error_message,
                                     timestamp: Time.now
                                   ))
      end

      def dispatch_database_recovered_event(database_id)
        region = @regions[database_id]
        @event_dispatcher.dispatch(DatabaseRecoveredEvent.new(
                                     database_id: database_id,
                                     region: "#{region[:host]}:#{region[:port]}",
                                     timestamp: Time.now
                                   ))
      end
    end
  end
end
