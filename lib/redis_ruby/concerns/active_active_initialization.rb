# frozen_string_literal: true

module RR
  module Concerns
    # Initialization helpers for ActiveActiveClient
    #
    # Extracts option parsing, region setup, and component initialization
    # to keep the main client class focused on runtime operations.
    module ActiveActiveInitialization
      private

      def apply_options(options)
        apply_connection_options(options)
        apply_health_check_options(options)
      end

      def apply_connection_options(options)
        @preferred_region_index = options.fetch(:preferred_region, 0)
        @current_region_index = @preferred_region_index
        @db = options.fetch(:db, ActiveActiveClient::DEFAULT_DB)
        @password = options[:password]
        @timeout = options.fetch(:timeout, ActiveActiveClient::DEFAULT_TIMEOUT)
        @ssl = options.fetch(:ssl, false)
        @ssl_params = options.fetch(:ssl_params, {})
        @reconnect_attempts = options.fetch(:reconnect_attempts, 3)
      end

      def apply_health_check_options(options)
        @health_check_interval = options.fetch(
          :health_check_interval, ActiveActiveClient::DEFAULT_HEALTH_CHECK_INTERVAL
        )
        @health_check_probes = options.fetch(
          :health_check_probes, ActiveActiveClient::DEFAULT_HEALTH_CHECK_PROBES
        )
        @health_check_probe_delay = options.fetch(
          :health_check_probe_delay, ActiveActiveClient::DEFAULT_HEALTH_CHECK_PROBE_DELAY
        )
        @health_check_policy = options.fetch(
          :health_check_policy, ActiveActiveClient::DEFAULT_HEALTH_CHECK_POLICY
        )
        @auto_fallback_interval = options.fetch(:auto_fallback_interval, 0)
      end

      def initialize_regions(regions)
        @regions = regions.map.with_index do |region, index|
          {
            id: index,
            host: region[:host],
            port: region[:port] || ActiveActiveClient::DEFAULT_PORT,
            weight: region[:weight] || 1.0,
          }
        end
      end

      def initialize_enterprise_components(options)
        @event_dispatcher = options[:event_dispatcher] || EventDispatcher.new
        @circuit_breakers = {}
        @failure_detectors = {}
        @health_check_runner = nil
        @fallback_thread = nil
        @shutdown = false
        @connection = nil
        @mutex = Mutex.new
      end

      def initialize_circuit_breakers_and_detectors(options)
        cb_threshold = options.fetch(
          :circuit_breaker_threshold, ActiveActiveClient::DEFAULT_CIRCUIT_BREAKER_THRESHOLD
        )
        cb_timeout = options.fetch(
          :circuit_breaker_timeout, ActiveActiveClient::DEFAULT_CIRCUIT_BREAKER_TIMEOUT
        )
        fd_window = options.fetch(:failure_window_size, ActiveActiveClient::DEFAULT_FAILURE_WINDOW_SIZE)
        fd_min = options.fetch(:min_failures, ActiveActiveClient::DEFAULT_MIN_FAILURES)
        fd_rate = options.fetch(
          :failure_rate_threshold, ActiveActiveClient::DEFAULT_FAILURE_RATE_THRESHOLD
        )

        @regions.each do |region|
          @circuit_breakers[region[:id]] = CircuitBreaker.new(
            failure_threshold: cb_threshold, reset_timeout: cb_timeout
          )
          @failure_detectors[region[:id]] = FailureDetector.new(
            window_size: fd_window, min_failures: fd_min, failure_rate_threshold: fd_rate
          )
        end
      end
    end
  end
end
