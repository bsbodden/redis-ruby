# frozen_string_literal: true

module RR
  # ActiveActiveClient provides multi-region support for Redis Enterprise Active-Active databases.
  #
  # Active-Active databases use Conflict-free Replicated Data Types (CRDTs) to enable
  # geo-distributed writes across multiple regions with automatic conflict resolution.
  #
  # This client manages connections to multiple regional endpoints and provides automatic
  # failover when a region becomes unavailable.
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

    # @param regions [Array<Hash>] Array of region configurations, each with :host and :port
    # @param preferred_region [Integer] Index of preferred region (default: 0)
    # @param db [Integer] Database number (default: 0)
    # @param password [String, nil] Password for authentication
    # @param timeout [Integer] Connection timeout in seconds (default: 5)
    # @param ssl [Boolean] Enable SSL/TLS (default: false)
    # @param ssl_params [Hash] SSL parameters (default: {})
    # @param reconnect_attempts [Integer] Number of reconnection attempts per region (default: 3)
    def initialize(regions:, preferred_region: 0, db: DEFAULT_DB, password: nil,
                   timeout: DEFAULT_TIMEOUT, ssl: false, ssl_params: {},
                   reconnect_attempts: 3)
      raise ArgumentError, "regions must contain at least one region" if regions.nil? || regions.empty?

      @regions = regions.map do |region|
        {
          host: region[:host],
          port: region[:port] || DEFAULT_PORT
        }
      end
      @current_region_index = preferred_region
      @db = db
      @password = password
      @timeout = timeout
      @ssl = ssl
      @ssl_params = ssl_params
      @reconnect_attempts = reconnect_attempts

      @connection = nil
      @mutex = Mutex.new
    end

    # Execute a Redis command
    #
    # @param command [String, Symbol] The Redis command
    # @param args [Array] Command arguments
    # @return [Object] Command result
    def call(command, *args)
      ensure_connected
      result = @connection.call(command, *args)
      raise result if result.is_a?(CommandError)

      result
    rescue ConnectionError, Errno::ECONNRESET, Errno::EPIPE, Errno::ECONNREFUSED, IOError => e
      retry_with_different_region(e)
    end

    # Fast path for single-argument commands
    def call_1arg(command, arg1)
      ensure_connected
      result = @connection.call_1arg(command, arg1)
      raise result if result.is_a?(CommandError)

      result
    rescue ConnectionError, Errno::ECONNRESET, Errno::EPIPE, Errno::ECONNREFUSED, IOError
      retry_with_different_region
    end

    # Fast path for two-argument commands
    def call_2args(command, arg1, arg2)
      ensure_connected
      result = @connection.call_2args(command, arg1, arg2)
      raise result if result.is_a?(CommandError)

      result
    rescue ConnectionError, Errno::ECONNRESET, Errno::EPIPE, Errno::ECONNREFUSED, IOError
      retry_with_different_region
    end

    # Fast path for three-argument commands
    def call_3args(command, arg1, arg2, arg3)
      ensure_connected
      result = @connection.call_3args(command, arg1, arg2, arg3)
      raise result if result.is_a?(CommandError)

      result
    rescue ConnectionError, Errno::ECONNRESET, Errno::EPIPE, Errno::ECONNREFUSED, IOError
      retry_with_different_region
    end

    # Close the connection
    def close
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
      @mutex.synchronize do
        @connection&.close
        @connection = nil
        @current_region_index = (@current_region_index + 1) % @regions.size
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

    def retry_with_different_region(original_error = nil)
      @regions.size.times do
        failover_to_next_region
        begin
          ensure_connected
          return call(*@last_command) if @last_command
        rescue ConnectionError, Errno::ECONNRESET, Errno::EPIPE, Errno::ECONNREFUSED, IOError
          # Try next region
        end
      end

      # All regions failed
      raise ConnectionError, "All regions unavailable. Last error: #{original_error&.message}"
    end
  end
end

