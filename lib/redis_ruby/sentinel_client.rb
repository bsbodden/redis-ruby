# frozen_string_literal: true

require "uri"
require_relative "concerns/single_connection_operations"

module RedisRuby
  # Sentinel-backed Redis client
  #
  # Automatically discovers and connects to the Redis master or replica
  # through Sentinel servers. Handles automatic failover detection.
  #
  # Based on patterns from redis-py, redis-client (Ruby), and async-redis.
  #
  # @example Connect to master
  #   client = RedisRuby::SentinelClient.new(
  #     sentinels: [{ host: "sentinel1", port: 26379 }],
  #     service_name: "mymaster",
  #     role: :master
  #   )
  #   client.set("key", "value")
  #
  # @example Connect to replica (read-only)
  #   client = RedisRuby::SentinelClient.new(
  #     sentinels: [{ host: "sentinel1", port: 26379 }],
  #     service_name: "mymaster",
  #     role: :replica
  #   )
  #   client.get("key")
  #
  # @example Using the factory method
  #   client = RedisRuby.sentinel(
  #     sentinels: [{ host: "127.0.0.1", port: 26379 }],
  #     service_name: "mymaster"
  #   )
  #
  class SentinelClient
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

    attr_reader :service_name, :role, :timeout

    VALID_ROLES = %i[master replica slave].freeze
    DEFAULT_TIMEOUT = 5.0

    # Initialize a new Sentinel-backed Redis client
    #
    # @param sentinels [Array<Hash, String>] List of Sentinel servers
    # @param service_name [String] Name of the monitored master (required)
    # @param role [Symbol] :master, :replica, or :slave (defaults to :master)
    # @param password [String, nil] Redis server password
    # @param sentinel_password [String, nil] Sentinel server password
    # @param db [Integer] Redis database number
    # @param timeout [Float] Connection timeout in seconds
    # @param ssl [Boolean] Enable SSL/TLS for Redis connection
    # @param ssl_params [Hash] SSL parameters for OpenSSL::SSL::SSLContext
    # @param reconnect_attempts [Integer] Number of reconnect attempts on failure
    # @param min_other_sentinels [Integer] Minimum number of peer sentinels required
    def initialize(sentinels:, service_name:, role: :master, password: nil,
                   sentinel_password: nil, db: 0, timeout: DEFAULT_TIMEOUT,
                   ssl: false, ssl_params: {}, reconnect_attempts: 3,
                   min_other_sentinels: 0)
      validate_role!(role)

      @service_name = service_name
      @role = normalize_role(role)
      @password = password
      @db = db
      @timeout = timeout
      @ssl = ssl
      @ssl_params = ssl_params
      @reconnect_attempts = reconnect_attempts

      @sentinel_manager = SentinelManager.new(
        sentinels: sentinels,
        service_name: service_name,
        sentinel_password: sentinel_password,
        timeout: timeout,
        min_other_sentinels: min_other_sentinels
      )

      @connection = nil
      @current_address = nil
      @mutex = Mutex.new
    end

    # Execute a Redis command
    #
    # Automatically handles failover by reconnecting on READONLY errors.
    #
    # @param command [String] Command name
    # @param args [Array] Command arguments
    # @return [Object] Command result
    def call(command, *args)
      attempts = 0

      begin
        ensure_connected
        handle_call_result(@connection.call(command, *args))
      rescue ConnectionError, ReadOnlyError, FailoverError
        attempts += 1
        retry if retry_with_backoff?(attempts)
        raise
      end
    end

    # Close the connection
    def close
      @mutex.synchronize do
        @connection&.close
        @connection = nil
        @current_address = nil
      end
    end

    alias disconnect close
    alias quit close

    # Check if connected
    #
    # @return [Boolean]
    def connected?
      @connection&.connected? || false
    end

    # Get the current master address
    #
    # @return [Hash, nil] { host: String, port: Integer }
    attr_reader :current_address

    # Check if connected to master
    #
    # @return [Boolean]
    def master?
      @role == :master
    end

    # Check if connected to replica
    #
    # @return [Boolean]
    def replica?
      @role == :replica
    end

    # Force reconnection (useful after failover)
    def reconnect
      @mutex.synchronize do
        @connection&.close
        @connection = nil
        @current_address = nil
        @sentinel_manager.reset
      end
    end

    # Get the underlying Sentinel manager
    #
    # @return [SentinelManager]
    attr_reader :sentinel_manager

    private

    def handle_call_result(result)
      case result
      when CommandError
        raise result unless readonly_error?(result)

        handle_failover
        raise ReadOnlyError, result.message
      else
        result
      end
    end

    def retry_with_backoff?(attempts)
      return false if attempts > @reconnect_attempts

      sleep(0.1 * (2**(attempts - 1))) if attempts > 1
      reconnect
      true
    end

    # Validate role parameter
    def validate_role!(role)
      return if VALID_ROLES.include?(role.to_sym)

      raise ArgumentError,
            "Invalid role: #{role.inspect}. Expected :master, :replica, or :slave"
    end

    # Normalize role (treat :slave as :replica)
    def normalize_role(role)
      role.to_sym == :slave ? :replica : role.to_sym
    end

    # Ensure connection is established
    def ensure_connected
      @mutex.synchronize do
        return if @connection&.connected?

        address = discover_address
        @connection = create_connection(address)
        @current_address = address

        verify_role!
        authenticate if @password
        select_db if @db.positive?
      end
    end

    # Discover the appropriate address based on role
    def discover_address
      if @role == :master
        @sentinel_manager.discover_master
      else
        # For replica, try to get a replica, fallback to master
        begin
          @sentinel_manager.random_replica
        rescue ReplicaNotFoundError
          @sentinel_manager.discover_master
        end
      end
    end

    # Create connection to the discovered address
    def create_connection(address)
      if @ssl
        Connection::SSL.new(
          host: address[:host],
          port: address[:port],
          timeout: @timeout,
          ssl_params: @ssl_params
        )
      else
        Connection::TCP.new(
          host: address[:host],
          port: address[:port],
          timeout: @timeout
        )
      end
    end

    # Verify we're connected to the correct role (redis-client pattern)
    def verify_role!
      result = @connection.call("ROLE")
      actual_role = result[0]

      if @role == :master
        unless actual_role == "master"
          sleep SentinelManager::SENTINEL_DELAY
          raise FailoverError, "Expected to connect to a master, but the server is a #{actual_role}"
        end
      else
        unless actual_role == "slave"
          sleep SentinelManager::SENTINEL_DELAY
          raise FailoverError, "Expected to connect to a replica, but the server is a #{actual_role}"
        end
      end
    end

    # Authenticate with password
    def authenticate
      @connection.call("AUTH", @password)
    end

    # Select database
    def select_db
      @connection.call("SELECT", @db.to_s)
    end

    # Check if error is a READONLY error (indicates master demotion)
    def readonly_error?(error)
      error.message.include?("READONLY") ||
        error.message.include?("You can't write against a read only replica")
    end

    # Handle failover by resetting state
    def handle_failover
      @mutex.synchronize do
        @connection&.close
        @connection = nil
        @current_address = nil
        @sentinel_manager.reset
      end
    end
  end
end
