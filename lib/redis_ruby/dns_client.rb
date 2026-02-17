# frozen_string_literal: true

module RR
  # Redis client with DNS-based load balancing
  #
  # This client resolves a hostname to multiple IP addresses and uses
  # a load balancing strategy (round-robin or random) to distribute
  # connections across the resolved endpoints.
  #
  # This is particularly useful for:
  # - Redis Enterprise Active-Active databases with multiple endpoints
  # - Load balancing across multiple Redis instances
  # - High availability with automatic failover
  #
  # @example Basic usage
  #   client = RR.dns(
  #     hostname: "redis.example.com",
  #     port: 6379
  #   )
  #   client.set("key", "value")
  #   value = client.get("key")
  #
  # @example With authentication and SSL
  #   client = RR.dns(
  #     hostname: "redis.example.com",
  #     port: 6380,
  #     password: "secret",
  #     ssl: true
  #   )
  #
  # @example Custom load balancing strategy
  #   client = RR.dns(
  #     hostname: "redis.example.com",
  #     port: 6379,
  #     dns_strategy: :random  # or :round_robin (default)
  #   )
  #
  class DNSClient
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
    DEFAULT_TIMEOUT = 5.0

    attr_reader :hostname, :port, :db, :timeout

    # Initialize a new DNS-aware Redis client
    #
    # @param hostname [String] Hostname to resolve (must resolve to one or more IPs)
    # @param port [Integer] Redis port
    # @param db [Integer] Redis database number
    # @param password [String, nil] Redis password
    # @param timeout [Float] Connection timeout in seconds
    # @param ssl [Boolean] Enable SSL/TLS
    # @param ssl_params [Hash] SSL parameters for OpenSSL::SSL::SSLContext
    # @param dns_strategy [Symbol] Load balancing strategy (:round_robin or :random)
    # @param reconnect_attempts [Integer] Number of reconnection attempts
    def initialize(hostname:, port: DEFAULT_PORT, db: DEFAULT_DB, password: nil,
                   timeout: DEFAULT_TIMEOUT, ssl: false, ssl_params: {},
                   dns_strategy: :round_robin, reconnect_attempts: 3)
      @hostname = hostname
      @port = port
      @db = db
      @password = password
      @timeout = timeout
      @ssl = ssl
      @ssl_params = ssl_params
      @reconnect_attempts = reconnect_attempts

      @dns_resolver = DNSResolver.new(hostname: hostname, strategy: dns_strategy)
      @connection = nil
      @current_ip = nil
      @mutex = Mutex.new
    end

    # Execute a Redis command
    #
    # @param command [String] Command name
    # @param args [Array] Command arguments
    # @return [Object] Command result
    def call(command, *args)
      execute_with_retry do
        result = @connection.call(command, *args)
        raise result if result.is_a?(CommandError)

        result
      end
    end

    # Fast path for single-argument commands (GET, DEL, EXISTS, etc.)
    # @api private
    def call_1arg(command, arg)
      execute_with_retry do
        result = @connection.call_1arg(command, arg)
        raise result if result.is_a?(CommandError)

        result
      end
    end

    # Fast path for two-argument commands (SET without options, HGET, etc.)
    # @api private
    def call_2args(command, arg1, arg2)
      execute_with_retry do
        result = @connection.call_2args(command, arg1, arg2)
        raise result if result.is_a?(CommandError)

        result
      end
    end

    # Fast path for three-argument commands (HSET, LRANGE, etc.)
    # @api private
    def call_3args(command, arg1, arg2, arg3)
      execute_with_retry do
        result = @connection.call_3args(command, arg1, arg2, arg3)
        raise result if result.is_a?(CommandError)

        result
      end
    end

    # Close the connection
    def close
      @connection&.close
      @connection = nil
      @current_ip = nil
    end

    alias disconnect close
    alias quit close

    # Check if connected
    # @return [Boolean]
    def connected?
      @connection&.connected? || false
    end

    # Refresh DNS resolution and reconnect if IP changed
    def refresh_dns
      @dns_resolver.refresh
      @mutex.synchronize do
        @connection&.close
        @connection = nil
        @current_ip = nil
      end
    end

    private

    # Ensure we have a valid connection
    # @api private
    def ensure_connected
      return if @connection&.connected?

      @mutex.synchronize do
        return if @connection&.connected?

        ip = @dns_resolver.resolve
        @connection&.close rescue nil
        @connection = create_connection(ip, @port)
        @current_ip = ip

        authenticate if @password
        select_db if @db.positive?
      end
    end

    # Create a connection to the resolved IP
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

    # Execute a block with retry on connection errors, reconnecting to a
    # different IP each time.
    # @api private
    def execute_with_retry
      ensure_connected
      yield
    rescue ConnectionError, Errno::ECONNRESET, Errno::EPIPE, Errno::ECONNREFUSED, IOError => e
      reconnect_to_different_ip(e)
      yield
    end

    # Reconnect to a different IP from DNS resolution
    # @api private
    def reconnect_to_different_ip(original_error)
      attempts = 0

      while attempts < @reconnect_attempts
        attempts += 1

        begin
          @mutex.synchronize do
            @connection&.close rescue nil
            @connection = nil

            # Get next IP from DNS resolver
            ip = @dns_resolver.resolve
            @connection = create_connection(ip, @port)
            @current_ip = ip

            authenticate if @password
            select_db if @db.positive?
          end

          return # Successfully reconnected
        rescue StandardError
          raise original_error if attempts >= @reconnect_attempts
        end
      end

      raise original_error
    end
  end
end

