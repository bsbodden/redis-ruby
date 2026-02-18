# frozen_string_literal: true

require_relative "concerns/single_connection_operations"

module RR
  # Redis Enterprise Discovery Service client
  #
  # Automatically discovers and connects to Redis Enterprise databases
  # through the Discovery Service. The Discovery Service runs on port 8001
  # on each node of a Redis Enterprise cluster.
  #
  # Based on patterns from redis-py, Jedis, and Lettuce.
  #
  # @example Connect to a database
  #   client = RR::DiscoveryServiceClient.new(
  #     nodes: [
  #       { host: "node1.redis.example.com", port: 8001 },
  #       { host: "node2.redis.example.com", port: 8001 }
  #     ],
  #     database_name: "my-database"
  #   )
  #   client.set("key", "value")
  #
  # @example Connect to internal endpoint
  #   client = RR::DiscoveryServiceClient.new(
  #     nodes: [{ host: "node1.redis.example.com" }],
  #     database_name: "my-database",
  #     internal: true
  #   )
  #
  # @example Using the factory method
  #   client = RR.discovery(
  #     nodes: [{ host: "node1.redis.example.com" }],
  #     database_name: "my-database"
  #   )
  #
  class DiscoveryServiceClient
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

    attr_reader :database_name, :timeout

    DEFAULT_TIMEOUT = 5.0

    # Initialize a new Discovery Service client
    #
    # @param nodes [Array<Hash>] List of discovery service nodes with :host and optional :port
    # @param database_name [String] Name of the database to discover
    # @param internal [Boolean] Whether to discover internal endpoint (default: false)
    # @param password [String, nil] Redis database password
    # @param db [Integer] Redis database number (default: 0)
    # @param timeout [Float] Connection timeout in seconds
    # @param ssl [Boolean] Enable SSL/TLS for Redis connection
    # @param ssl_params [Hash] SSL parameters for OpenSSL::SSL::SSLContext
    # @param reconnect_attempts [Integer] Number of reconnect attempts on failure
    def initialize(nodes:, database_name:, internal: false, password: nil,
                   db: 0, timeout: DEFAULT_TIMEOUT, ssl: false, ssl_params: {},
                   reconnect_attempts: 3)
      @database_name = database_name
      @password = password
      @db = db
      @timeout = timeout
      @ssl = ssl
      @ssl_params = ssl_params
      @reconnect_attempts = reconnect_attempts

      @discovery_service = DiscoveryService.new(
        nodes: nodes,
        database_name: database_name,
        internal: internal,
        timeout: timeout
      )

      @connection = nil
      @current_address = nil
      @mutex = Mutex.new
    end

    # Execute a Redis command
    #
    # @param command [String] Command name
    # @param args [Array] Command arguments
    # @return [Object] Command result
    def call(command, *args)
      ensure_connected
      result = @connection.call(command, *args)
      raise result if result.is_a?(CommandError)

      result
    end

    # Fast path for single-argument commands (GET, DEL, EXISTS, etc.)
    # @api private
    def call_1arg(command, arg)
      ensure_connected
      result = @connection.call_1arg(command, arg)
      raise result if result.is_a?(CommandError)

      result
    end

    # Fast path for two-argument commands (SET without options, HGET, etc.)
    # @api private
    def call_2args(command, arg1, arg2)
      ensure_connected
      result = @connection.call_2args(command, arg1, arg2)
      raise result if result.is_a?(CommandError)

      result
    end

    # Fast path for three-argument commands (HSET, LRANGE, etc.)
    # @api private
    def call_3args(command, arg1, arg2, arg3)
      ensure_connected
      result = @connection.call_3args(command, arg1, arg2, arg3)
      raise result if result.is_a?(CommandError)

      result
    end

    # Close the connection
    def close
      @mutex.synchronize do
        @connection&.close
        @connection = nil
        @current_address = nil
      end
    end

    # Check if connected
    # @return [Boolean]
    def connected?
      @connection&.connected? || false
    end

    # Reconnect to the database
    def reconnect
      close
      ensure_connected
    end

    private

    # Ensure we have a valid connection
    # @api private
    def ensure_connected
      return if @connection&.connected?

      @mutex.synchronize do
        return if @connection&.connected?

        endpoint = @discovery_service.discover_endpoint
        new_address = "#{endpoint[:host]}:#{endpoint[:port]}"

        # Only reconnect if the address changed or we don't have a connection
        if @current_address != new_address || !@connection&.connected?
          @connection&.close rescue nil

          @connection = create_connection(endpoint[:host], endpoint[:port])
          @current_address = new_address

          authenticate if @password
          select_db if @db.positive?
        end
      end
    end

    # Create a connection to the discovered endpoint
    # @api private
    def create_connection(host, port)
      if @ssl
        Connection::SSL.new(host: host, port: port, timeout: @timeout, ssl_params: @ssl_params)
      else
        Connection::TCP.new(host: host, port: port, timeout: @timeout)
      end
    end

  end
end

