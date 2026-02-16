# frozen_string_literal: true

module RR
  # ActiveActiveClient provides production-ready multi-region support for Redis Enterprise
  # Active-Active databases with comprehensive health monitoring, circuit breakers, failure
  # detection, and automatic failover.
  #
  # Active-Active databases use Conflict-free Replicated Data Types (CRDTs) to enable
  # geo-distributed writes across multiple regions with automatic conflict resolution.
  #
  # This client manages connections to multiple regional endpoints and provides:
  # - Automatic failover when a region becomes unavailable
  # - Background health checks with configurable policies
  # - Circuit breaker pattern to prevent cascading failures
  # - Failure detection with sliding window analysis
  # - Auto-fallback to preferred region when healthy
  # - Event system for monitoring failover events
  #
  # @example Basic usage
  #   client = RR::ActiveActiveClient.new(
  #     regions: [
  #       { host: "redis-us-east.example.com", port: 6379 },
  #       { host: "redis-eu-west.example.com", port: 6379 },
  #       { host: "redis-ap-south.example.com", port: 6379 }
  #     ]
  #   )
  #
  #   client.set("key", "value")
  #   value = client.get("key")
  #
  # @example With authentication and SSL
  #   client = RR::ActiveActiveClient.new(
  #     regions: [
  #       { host: "redis-us.example.com", port: 6380 },
  #       { host: "redis-eu.example.com", port: 6380 }
  #     ],
  #     password: "secret",
  #     ssl: true,
  #     ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_PEER }
  #   )
  #
  # @example With enterprise features
  #   client = RR::ActiveActiveClient.new(
  #     regions: [
  #       { host: "redis-us.example.com", port: 6379, weight: 1.0 },
  #       { host: "redis-eu.example.com", port: 6379, weight: 0.8 },
  #       { host: "redis-ap.example.com", port: 6379, weight: 0.5 }
  #     ],
  #     health_check_interval: 5.0,
  #     health_check_policy: :majority,
  #     auto_fallback_interval: 30.0,
  #     circuit_breaker_threshold: 5,
  #     failure_rate_threshold: 0.10
  #   )
  #
  #   # Register event listeners
  #   client.on_failover do |event|
  #     puts "Failover: #{event.from_region} -> #{event.to_region}"
  #   end
  #
  #   client.on_database_failed do |event|
  #     puts "Database failed: #{event.region} - #{event.error}"
  #   end
  #
  class ActiveActiveClient
    include Concerns::SingleConnectionOperations
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
    DEFAULT_HEALTH_CHECK_INTERVAL = 0 # Disabled by default, set to 5.0 for production
    DEFAULT_HEALTH_CHECK_PROBES = 3
    DEFAULT_HEALTH_CHECK_PROBE_DELAY = 0.1
    DEFAULT_HEALTH_CHECK_POLICY = :all
    DEFAULT_CIRCUIT_BREAKER_THRESHOLD = 5
    DEFAULT_CIRCUIT_BREAKER_TIMEOUT = 60
    DEFAULT_FAILURE_WINDOW_SIZE = 2.0
    DEFAULT_MIN_FAILURES = 1000
    DEFAULT_FAILURE_RATE_THRESHOLD = 0.10

    attr_reader :event_dispatcher

    # @param regions [Array<Hash>] Array of region configurations, each with :host, :port, and optional :weight
    # @param preferred_region [Integer] Index of preferred region (default: 0)
    # @param db [Integer] Database number (default: 0)
    # @param password [String, nil] Password for authentication
    # @param timeout [Integer] Connection timeout in seconds (default: 5)
    # @param ssl [Boolean] Enable SSL/TLS (default: false)
    # @param ssl_params [Hash] SSL parameters (default: {})
    # @param reconnect_attempts [Integer] Number of reconnection attempts per region (default: 3)
    # @param health_check_interval [Float] Seconds between health checks (default: 5.0, 0 to disable)
    # @param health_check_probes [Integer] Number of probes per health check (default: 3)
    # @param health_check_probe_delay [Float] Seconds between probes (default: 0.1)
    # @param health_check_policy [Symbol] Health check policy: :all, :majority, :any (default: :all)
    # @param circuit_breaker_threshold [Integer] Failures before opening circuit (default: 5)
    # @param circuit_breaker_timeout [Integer] Seconds before trying half-open (default: 60)
    # @param failure_window_size [Float] Sliding window size in seconds (default: 2.0)
    # @param min_failures [Integer] Minimum failures to trigger failover (default: 1000)
    # @param failure_rate_threshold [Float] Failure rate threshold 0.0-1.0 (default: 0.10)
    # @param auto_fallback_interval [Float] Seconds between fallback attempts (default: 0, disabled)
    # @param event_dispatcher [EventDispatcher] Custom event dispatcher (default: new instance)
    def initialize(regions:, preferred_region: 0, db: DEFAULT_DB, password: nil,
                   timeout: DEFAULT_TIMEOUT, ssl: false, ssl_params: {},
                   reconnect_attempts: 3,
                   health_check_interval: DEFAULT_HEALTH_CHECK_INTERVAL,
                   health_check_probes: DEFAULT_HEALTH_CHECK_PROBES,
                   health_check_probe_delay: DEFAULT_HEALTH_CHECK_PROBE_DELAY,
                   health_check_policy: DEFAULT_HEALTH_CHECK_POLICY,
                   circuit_breaker_threshold: DEFAULT_CIRCUIT_BREAKER_THRESHOLD,
                   circuit_breaker_timeout: DEFAULT_CIRCUIT_BREAKER_TIMEOUT,
                   failure_window_size: DEFAULT_FAILURE_WINDOW_SIZE,
                   min_failures: DEFAULT_MIN_FAILURES,
                   failure_rate_threshold: DEFAULT_FAILURE_RATE_THRESHOLD,
                   auto_fallback_interval: 0,
                   event_dispatcher: nil)
      raise ArgumentError, "regions must contain at least one region" if regions.nil? || regions.empty?

      @regions = regions.map.with_index do |region, index|
        {
          id: index,
          host: region[:host],
          port: region[:port] || DEFAULT_PORT,
          weight: region[:weight] || 1.0
        }
      end
      @preferred_region_index = preferred_region
      @current_region_index = preferred_region
      @db = db
      @password = password
      @timeout = timeout
      @ssl = ssl
      @ssl_params = ssl_params
      @reconnect_attempts = reconnect_attempts

      # Enterprise features configuration
      @health_check_interval = health_check_interval
      @health_check_probes = health_check_probes
      @health_check_probe_delay = health_check_probe_delay
      @health_check_policy = health_check_policy
      @auto_fallback_interval = auto_fallback_interval

      # Initialize enterprise components
      @event_dispatcher = event_dispatcher || EventDispatcher.new
      @circuit_breakers = {}
      @failure_detectors = {}
      @health_check_runner = nil
      @fallback_thread = nil
      @shutdown = false

      @connection = nil
      @mutex = Mutex.new

      # Initialize circuit breakers and failure detectors for each region
      @regions.each do |region|
        @circuit_breakers[region[:id]] = CircuitBreaker.new(
          failure_threshold: circuit_breaker_threshold,
          reset_timeout: circuit_breaker_timeout
        )
        @failure_detectors[region[:id]] = FailureDetector.new(
          window_size: failure_window_size,
          min_failures: min_failures,
          failure_rate_threshold: failure_rate_threshold
        )
      end

      # Start health checks if enabled
      start_health_checks if @health_check_interval > 0

      # Start auto-fallback if enabled
      start_auto_fallback if @auto_fallback_interval > 0
    end

    # Execute a Redis command with circuit breaker and failure detection
    #
    # @param command [String, Symbol] The Redis command
    # @param args [Array] Command arguments
    # @return [Object] Command result
    def call(command, *args)
      region_id = @current_region_index
      circuit_breaker = @circuit_breakers[region_id]
      failure_detector = @failure_detectors[region_id]

      circuit_breaker.call do
        ensure_connected
        result = @connection.call(command, *args)
        raise result if result.is_a?(CommandError)

        failure_detector.record_success
        result
      end
    rescue CircuitBreakerOpenError => e
      # Circuit is open, try failover
      handle_failure(region_id, e)
      retry_with_different_region(e)
    rescue ConnectionError, Errno::ECONNRESET, Errno::EPIPE, Errno::ECONNREFUSED, IOError => e
      handle_failure(region_id, e)
      retry_with_different_region(e)
    end

    # Fast path for single-argument commands
    def call_1arg(command, arg1)
      region_id = @current_region_index
      circuit_breaker = @circuit_breakers[region_id]
      failure_detector = @failure_detectors[region_id]

      circuit_breaker.call do
        ensure_connected
        result = @connection.call_1arg(command, arg1)
        raise result if result.is_a?(CommandError)

        failure_detector.record_success
        result
      end
    rescue CircuitBreakerOpenError => e
      handle_failure(region_id, e)
      retry_with_different_region(e)
    rescue ConnectionError, Errno::ECONNRESET, Errno::EPIPE, Errno::ECONNREFUSED, IOError => e
      handle_failure(region_id, e)
      retry_with_different_region(e)
    end

    # Fast path for two-argument commands
    def call_2args(command, arg1, arg2)
      region_id = @current_region_index
      circuit_breaker = @circuit_breakers[region_id]
      failure_detector = @failure_detectors[region_id]

      circuit_breaker.call do
        ensure_connected
        result = @connection.call_2args(command, arg1, arg2)
        raise result if result.is_a?(CommandError)

        failure_detector.record_success
        result
      end
    rescue CircuitBreakerOpenError => e
      handle_failure(region_id, e)
      retry_with_different_region(e)
    rescue ConnectionError, Errno::ECONNRESET, Errno::EPIPE, Errno::ECONNREFUSED, IOError => e
      handle_failure(region_id, e)
      retry_with_different_region(e)
    end

    # Fast path for three-argument commands
    def call_3args(command, arg1, arg2, arg3)
      region_id = @current_region_index
      circuit_breaker = @circuit_breakers[region_id]
      failure_detector = @failure_detectors[region_id]

      circuit_breaker.call do
        ensure_connected
        result = @connection.call_3args(command, arg1, arg2, arg3)
        raise result if result.is_a?(CommandError)

        failure_detector.record_success
        result
      end
    rescue CircuitBreakerOpenError => e
      handle_failure(region_id, e)
      retry_with_different_region(e)
    rescue ConnectionError, Errno::ECONNRESET, Errno::EPIPE, Errno::ECONNREFUSED, IOError => e
      handle_failure(region_id, e)
      retry_with_different_region(e)
    end

    # Close the connection and stop background threads
    def close
      @shutdown = true

      # Stop health checks
      @health_check_runner&.stop

      # Stop auto-fallback
      @fallback_thread&.join if @fallback_thread&.alive?

      @mutex.synchronize do
        @connection&.close
        @connection = nil
      end
    end

    # Check if connected
    #
    # @return [Boolean] true if connected
    def connected?
      @mutex.synchronize do
        !@connection.nil? && @connection.connected?
      end
    end

    # Get current region information
    #
    # @return [Hash] Current region configuration
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
      new_region = @regions[@current_region_index]

      # Dispatch failover event
      @event_dispatcher.dispatch(FailoverEvent.new(
        from_database_id: old_region[:id],
        to_database_id: new_region[:id],
        from_region: "#{old_region[:host]}:#{old_region[:port]}",
        to_region: "#{new_region[:host]}:#{new_region[:port]}",
        reason: "manual",
        timestamp: Time.now
      ))
    end

    # Register callback for failover events
    #
    # @yield [event] Called when failover occurs
    # @yieldparam event [FailoverEvent] The failover event
    def on_failover(&block)
      @event_dispatcher.on(FailoverEvent, &block)
    end

    # Register callback for database failed events
    #
    # @yield [event] Called when database fails
    # @yieldparam event [DatabaseFailedEvent] The failure event
    def on_database_failed(&block)
      @event_dispatcher.on(DatabaseFailedEvent, &block)
    end

    # Register callback for database recovered events
    #
    # @yield [event] Called when database recovers
    # @yieldparam event [DatabaseRecoveredEvent] The recovery event
    def on_database_recovered(&block)
      @event_dispatcher.on(DatabaseRecoveredEvent, &block)
    end

    # Get health status of all regions
    #
    # @return [Hash] Map of region_id => health status
    def health_status
      @regions.each_with_object({}) do |region, status|
        status[region[:id]] = {
          region: "#{region[:host]}:#{region[:port]}",
          healthy: @health_check_runner ? @health_check_runner.healthy?(region[:id]) : nil,
          circuit_state: @circuit_breakers[region[:id]].state,
          failure_stats: @failure_detectors[region[:id]].stats
        }
      end
    end

    private

    def ensure_connected
      @mutex.synchronize do
        return if @connection&.connected?

        region = @regions[@current_region_index]
        @connection = create_connection(region[:host], region[:port])
        authenticate if @password
        select_db if @db.positive?
      end
    end

    # Create a connection to the specified host and port
    # @api private
    def create_connection(host, port)
      if @ssl
        Connection::SSL.new(host: host, port: port, timeout: @timeout, ssl_params: @ssl_params)
      else
        Connection::TCP.new(host: host, port: port, timeout: @timeout)
      end
    end

    # Authenticate with the Redis server
    # @api private
    def authenticate
      @connection.call("AUTH", @password)
    end

    # Select the database
    # @api private
    def select_db
      @connection.call("SELECT", @db)
    end

    # Handle failure - record in detector and check if should failover
    # @api private
    def handle_failure(region_id, error)
      failure_detector = @failure_detectors[region_id]
      failure_detector.record_failure

      # Dispatch database failed event
      region = @regions[region_id]
      @event_dispatcher.dispatch(DatabaseFailedEvent.new(
        database_id: region_id,
        region: "#{region[:host]}:#{region[:port]}",
        error: error.message,
        timestamp: Time.now
      ))

      # Check if failure threshold exceeded
      if failure_detector.failure_threshold_exceeded?
        # Trip circuit breaker
        @circuit_breakers[region_id].trip!
      end
    end

    def retry_with_different_region(original_error = nil)
      attempted_regions = [@current_region_index]
      old_region = @regions[@current_region_index]

      (@regions.size - 1).times do
        # Find next healthy region by weight
        next_region_index = find_next_healthy_region(attempted_regions)
        break unless next_region_index

        attempted_regions << next_region_index

        @mutex.synchronize do
          @connection&.close
          @connection = nil
          @current_region_index = next_region_index
        end

        new_region = @regions[@current_region_index]

        # Dispatch failover event
        @event_dispatcher.dispatch(FailoverEvent.new(
          from_database_id: old_region[:id],
          to_database_id: new_region[:id],
          from_region: "#{old_region[:host]}:#{old_region[:port]}",
          to_region: "#{new_region[:host]}:#{new_region[:port]}",
          reason: "automatic",
          timestamp: Time.now
        ))

        begin
          ensure_connected
          # Successfully connected to new region
          return
        rescue ConnectionError, Errno::ECONNRESET, Errno::EPIPE, Errno::ECONNREFUSED, IOError => e
          # Try next region
          handle_failure(@current_region_index, e)
        end
      end

      # All regions failed
      raise ConnectionError, "All regions unavailable. Last error: #{original_error&.message}"
    end

    # Find next healthy region by weight
    # @api private
    def find_next_healthy_region(attempted_regions)
      # Sort regions by weight (descending) and filter out attempted ones
      available_regions = @regions
        .reject { |r| attempted_regions.include?(r[:id]) }
        .sort_by { |r| -r[:weight] }

      # Find first region with closed circuit breaker
      available_regions.each do |region|
        circuit_breaker = @circuit_breakers[region[:id]]
        return region[:id] if circuit_breaker.closed? || circuit_breaker.half_open?
      end

      # If no healthy regions, try first available (circuit might be ready for half-open)
      available_regions.first&.fetch(:id)
    end

    # Start background health checks
    # @api private
    def start_health_checks
      @health_check_runner = HealthCheck::Runner.new(
        interval: @health_check_interval,
        probes: @health_check_probes,
        probe_delay: @health_check_probe_delay,
        policy: @health_check_policy
      )

      # Add health checks for each region
      # Note: We create separate connections for health checks to avoid interfering with main connection
      @regions.each do |region|
        begin
          connection = create_connection(region[:host], region[:port])
          @health_check_runner.add_check(
            database_id: region[:id],
            connection: connection
          )
        rescue ConnectionError => e
          # If we can't create health check connection, mark region as unhealthy
          @circuit_breakers[region[:id]].trip!
          warn "Failed to create health check connection for #{region[:host]}:#{region[:port]}: #{e.message}"
        end
      end

      # Register callback for health state changes
      @health_check_runner.on_health_change do |database_id, old_state, new_state|
        region = @regions.find { |r| r[:id] == database_id }
        next unless region

        if new_state
          # Database recovered
          @circuit_breakers[database_id].reset!
          @failure_detectors[database_id].reset!

          @event_dispatcher.dispatch(DatabaseRecoveredEvent.new(
            database_id: database_id,
            region: "#{region[:host]}:#{region[:port]}",
            timestamp: Time.now
          ))
        else
          # Database failed
          @circuit_breakers[database_id].trip!

          @event_dispatcher.dispatch(DatabaseFailedEvent.new(
            database_id: database_id,
            region: "#{region[:host]}:#{region[:port]}",
            error: "Health check failed",
            timestamp: Time.now
          ))
        end
      end

      @health_check_runner.start
    end

    # Start auto-fallback thread
    # @api private
    def start_auto_fallback
      @fallback_thread = Thread.new do
        loop do
          sleep @auto_fallback_interval
          break if @shutdown

          # Check if we can fallback to preferred region
          next if @current_region_index == @preferred_region_index

          preferred_circuit = @circuit_breakers[@preferred_region_index]
          if preferred_circuit.closed?
            # Preferred region is healthy, fallback to it
            old_region = @regions[@current_region_index]
            @mutex.synchronize do
              @connection&.close
              @connection = nil
              @current_region_index = @preferred_region_index
            end
            new_region = @regions[@current_region_index]

            @event_dispatcher.dispatch(FailoverEvent.new(
              from_database_id: old_region[:id],
              to_database_id: new_region[:id],
              from_region: "#{old_region[:host]}:#{old_region[:port]}",
              to_region: "#{new_region[:host]}:#{new_region[:port]}",
              reason: "auto_fallback",
              timestamp: Time.now
            ))
          end
        rescue StandardError => e
          # Log error but don't crash the thread
          warn "Auto-fallback error: #{e.message}"
        end
      end
    end
  end
end

