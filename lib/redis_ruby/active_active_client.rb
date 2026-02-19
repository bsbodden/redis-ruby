# frozen_string_literal: true

require_relative "concerns/active_active_health"
require_relative "concerns/active_active_initialization"

module RR
  # Multi-region Redis Enterprise Active-Active client with health monitoring,
  # circuit breakers, failure detection, and automatic failover.
  #
  class ActiveActiveClient
    include Concerns::SingleConnectionOperations
    include Concerns::ActiveActiveHealth
    include Concerns::ActiveActiveInitialization
    include Commands::Strings
    include Commands::Keys
    include Commands::Hashes
    include Commands::Lists
    include Commands::Sets
    include Commands::SortedSets
    include Commands::Geo
    include Commands::HyperLogLog
    include Commands::Bitmap
    include Commands::Scripting
    include Commands::JSON
    include Commands::Search
    include Commands::Probabilistic
    include Commands::TimeSeries
    include Commands::VectorSet
    include Commands::Streams
    include Commands::PubSub
    include Commands::Functions
    include Commands::ACL
    include Commands::Server

    DEFAULT_PORT = 6379
    DEFAULT_DB = 0
    DEFAULT_TIMEOUT = 5
    DEFAULT_HEALTH_CHECK_INTERVAL = 0
    DEFAULT_HEALTH_CHECK_PROBES = 3
    DEFAULT_HEALTH_CHECK_PROBE_DELAY = 0.1
    DEFAULT_HEALTH_CHECK_POLICY = :all
    DEFAULT_CIRCUIT_BREAKER_THRESHOLD = 5
    DEFAULT_CIRCUIT_BREAKER_TIMEOUT = 60
    DEFAULT_FAILURE_WINDOW_SIZE = 2.0
    DEFAULT_MIN_FAILURES = 1000
    DEFAULT_FAILURE_RATE_THRESHOLD = 0.10

    attr_reader :event_dispatcher

    # @param regions [Array<Hash>] Region configs with :host, :port, optional :weight
    # @param options [Hash] Connection and enterprise feature options
    def initialize(regions:, **options)
      raise ArgumentError, "regions must contain at least one region" if regions.nil? || regions.empty?

      apply_options(options)
      initialize_regions(regions)
      initialize_enterprise_components(options)
      initialize_circuit_breakers_and_detectors(options)
      start_health_checks if @health_check_interval.positive?
      start_auto_fallback if @auto_fallback_interval.positive?
    end

    # Execute a Redis command with circuit breaker and failure detection
    def call(command, *args)
      execute_with_failover { |conn| conn.call(command, *args) }
    end

    # Fast path for single-argument commands
    def call_1arg(command, arg1)
      execute_with_failover { |conn| conn.call_1arg(command, arg1) }
    end

    # Fast path for two-argument commands
    def call_2args(command, arg1, arg2)
      execute_with_failover { |conn| conn.call_2args(command, arg1, arg2) }
    end

    # Fast path for three-argument commands
    def call_3args(command, arg1, arg2, arg3)
      execute_with_failover { |conn| conn.call_3args(command, arg1, arg2, arg3) }
    end

    # Close the connection and stop background threads
    def close
      @shutdown = true
      @health_check_runner&.stop
      @fallback_thread.join(1) || @fallback_thread.kill if @fallback_thread&.alive?
      @mutex.synchronize do
        @connection&.close
        @connection = nil
      end
    end

    # Check if connected
    def connected?
      @mutex.synchronize { !@connection.nil? && @connection.connected? }
    end

    # Get current region information
    def current_region
      @regions[@current_region_index]
    end

    # Manually trigger failover to next region
    def failover_to_next_region
      old_region = @regions[@current_region_index]
      @mutex.synchronize do
        @connection&.close
        @connection = nil
        @current_region_index = (@current_region_index + 1) % @regions.size
      end
      dispatch_failover_event(old_region, @regions[@current_region_index], "manual")
    end

    # Register callback for failover events
    def on_failover(&)
      @event_dispatcher.on(FailoverEvent, &)
    end

    # Register callback for database failed events
    def on_database_failed(&)
      @event_dispatcher.on(DatabaseFailedEvent, &)
    end

    # Register callback for database recovered events
    def on_database_recovered(&)
      @event_dispatcher.on(DatabaseRecoveredEvent, &)
    end

    # Get health status of all regions
    def health_status
      @regions.each_with_object({}) do |region, status|
        status[region[:id]] = {
          region: "#{region[:host]}:#{region[:port]}",
          healthy: @health_check_runner&.healthy?(region[:id]),
          circuit_state: @circuit_breakers[region[:id]].state,
          failure_stats: @failure_detectors[region[:id]].stats,
        }
      end
    end

    private

    def execute_with_failover
      region_id = @current_region_index
      @circuit_breakers[region_id].call do
        ensure_connected
        result = yield @connection
        raise result if result.is_a?(CommandError)

        @failure_detectors[region_id].record_success
        result
      end
    rescue CircuitBreakerOpenError, ConnectionError,
           Errno::ECONNRESET, Errno::EPIPE, Errno::ECONNREFUSED, IOError => e
      handle_failure(region_id, e)
      retry_with_different_region(e)
    end

    def ensure_connected
      @mutex.synchronize do
        return if @connection&.connected?

        region = @regions[@current_region_index]
        @connection = create_connection(region[:host], region[:port])
        authenticate if @password
        select_db if @db.positive?
      end
    end

    def create_connection(host, port)
      if @ssl
        Connection::SSL.new(host: host, port: port, timeout: @timeout, ssl_params: @ssl_params)
      else
        Connection::TCP.new(host: host, port: port, timeout: @timeout)
      end
    end

    def handle_failure(region_id, error)
      @failure_detectors[region_id].record_failure
      dispatch_database_failed_event(region_id, error.message)
      return unless @failure_detectors[region_id].failure_threshold_exceeded?

      @circuit_breakers[region_id].trip!
    end

    def retry_with_different_region(original_error = nil)
      attempted_regions = [@current_region_index]
      old_region = @regions[@current_region_index]

      (@regions.size - 1).times do
        next_index = find_next_healthy_region(attempted_regions)
        break unless next_index

        attempted_regions << next_index
        switch_to_region(next_index)
        dispatch_failover_event(old_region, @regions[@current_region_index], "automatic")
        begin
          ensure_connected
          return
        rescue ConnectionError, Errno::ECONNRESET, Errno::EPIPE, Errno::ECONNREFUSED, IOError => e
          handle_failure(@current_region_index, e)
        end
      end
      raise ConnectionError, "All regions unavailable. Last error: #{original_error&.message}"
    end

    def switch_to_region(region_index)
      @mutex.synchronize do
        @connection&.close
        @connection = nil
        @current_region_index = region_index
      end
    end

    def find_next_healthy_region(attempted_regions)
      available = @regions.reject { |r| attempted_regions.include?(r[:id]) }.sort_by { |r| -r[:weight] }
      available.each do |region|
        cb = @circuit_breakers[region[:id]]
        return region[:id] if cb.closed? || cb.half_open?
      end
      available.first&.fetch(:id)
    end
  end
end
