# frozen_string_literal: true

require "uri"
require_relative "concerns/pooled_operations"

module RR
  # Thread-safe Redis client with connection pooling
  #
  # Each command checks out a connection from the pool, executes,
  # and returns it. This provides thread-safety without a single mutex.
  #
  # @example Basic usage
  #   client = RR::PooledClient.new(url: "redis://localhost:6379", pool: { size: 10 })
  #   client.set("key", "value")
  #   client.get("key") # => "value"
  #
  # @example Batch operations with same connection
  #   client.with_connection do |conn|
  #     conn.call("SET", "key1", "value1")
  #     conn.call("SET", "key2", "value2")
  #   end
  #
  class PooledClient
    include Concerns::PooledOperations
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

    attr_reader :host, :port, :db, :timeout, :password

    DEFAULT_HOST = "localhost"
    DEFAULT_PORT = 6379
    DEFAULT_DB = 0
    DEFAULT_TIMEOUT = 5.0
    DEFAULT_POOL_SIZE = 5
    DEFAULT_POOL_TIMEOUT = 5.0

    # Initialize a new pooled Redis client
    #
    # @param url [String, nil] Redis URL (redis://host:port/db)
    # @param host [String] Redis host
    # @param port [Integer] Redis port
    # @param db [Integer] Redis database number
    # @param password [String, nil] Redis password
    # @param timeout [Float] Connection timeout in seconds
    # @param pool [Hash] Pool options (:size, :timeout)
    # @param instrumentation [RR::Instrumentation, nil] Instrumentation instance for metrics
    # @param circuit_breaker [RR::CircuitBreaker, nil] Circuit breaker for failure protection
    def initialize(url: nil, host: DEFAULT_HOST, port: DEFAULT_PORT, db: DEFAULT_DB,
                   password: nil, timeout: DEFAULT_TIMEOUT, pool: {}, instrumentation: nil,
                   circuit_breaker: nil)
      # Initialize ALL instance variables upfront for consistent object shapes (YJIT optimization)
      @host = host
      @port = port
      @db = db
      @password = password
      @timeout = timeout
      @pool = nil
      @instrumentation = instrumentation
      @circuit_breaker = circuit_breaker

      # Override from URL if provided
      parse_url(url) if url

      pool_size = pool.fetch(:size) { DEFAULT_POOL_SIZE }
      pool_timeout = pool.fetch(:timeout) { DEFAULT_POOL_TIMEOUT }

      @pool = Connection::Pool.new(
        host: @host,
        port: @port,
        size: pool_size,
        pool_timeout: pool_timeout,
        connection_timeout: @timeout,
        password: @password,
        db: @db
      )
    end

    # Execute a Redis command
    #
    # Checks out a connection, executes, and returns it to the pool.
    #
    # @param command [String] Command name
    # @param args [Array] Command arguments
    # @return [Object] Command result
    def call(command, *args)
      execute_with_protection(command, args)
    end

    # Fast path for single-argument commands (GET, DEL, EXISTS, etc.)
    # @api private
    def call_1arg(command, arg)
      if @circuit_breaker
        @circuit_breaker.call do
          execute_1arg_with_instrumentation(command, arg)
        end
      else
        execute_1arg_with_instrumentation(command, arg)
      end
    end

    # Fast path for two-argument commands (SET without options, HGET, etc.)
    # @api private
    def call_2args(command, arg1, arg2)
      if @circuit_breaker
        @circuit_breaker.call do
          execute_2args_with_instrumentation(command, arg1, arg2)
        end
      else
        execute_2args_with_instrumentation(command, arg1, arg2)
      end
    end

    # Fast path for three-argument commands (HSET, LRANGE, etc.)
    # @api private
    def call_3args(command, arg1, arg2, arg3)
      if @circuit_breaker
        @circuit_breaker.call do
          execute_3args_with_instrumentation(command, arg1, arg2, arg3)
        end
      else
        execute_3args_with_instrumentation(command, arg1, arg2, arg3)
      end
    end

    # Execute a block with a connection from the pool
    #
    # Use this for batch operations or when you need to ensure
    # multiple commands use the same connection.
    #
    # @yield [Connection::TCP] connection from the pool
    # @return [Object] result of the block
    def with_connection(&)
      @pool.with(&)
    end

    # Close all connections in the pool
    def close
      @pool.close
    end

    alias disconnect close
    alias quit close

    # Pool size
    #
    # @return [Integer]
    def pool_size
      @pool.size
    end

    # Available connections in pool
    #
    # @return [Integer]
    def pool_available
      @pool.available
    end

    # Check if the connection is healthy
    #
    # @param command [String] Command to use for health check (default: "PING")
    # @return [Boolean] true if healthy, false otherwise
    def healthy?(command: "PING")
      health_check(command: command)
    end

    # Perform a health check
    #
    # @param command [String] Command to use for health check (default: "PING")
    # @return [Boolean] true if healthy, false otherwise
    def health_check(command: "PING")
      # Check circuit breaker state first
      return false if @circuit_breaker && @circuit_breaker.state == :open

      # Try to execute a simple command
      begin
        call(command)
        true
      rescue
        false
      end
    end

    private

    # Execute command with circuit breaker and instrumentation protection
    def execute_with_protection(command, args)
      if @circuit_breaker
        @circuit_breaker.call do
          execute_with_instrumentation(command, args)
        end
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
      # Trigger before callbacks
      @instrumentation.before_callbacks.each { |cb| cb.call(command, args) }

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      error = nil

      begin
        result = call_without_instrumentation(command, args)
      rescue => e
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
      @pool.with do |conn|
        result = conn.call(command, *args)
        raise result if result.is_a?(CommandError)

        result
      end
    end

    # Fast path without instrumentation
    def call_1arg_without_instrumentation(command, arg)
      @pool.with do |conn|
        result = conn.call_1arg(command, arg)
        raise result if result.is_a?(CommandError)

        result
      end
    end

    def call_2args_without_instrumentation(command, arg1, arg2)
      @pool.with do |conn|
        result = conn.call_2args(command, arg1, arg2)
        raise result if result.is_a?(CommandError)

        result
      end
    end

    def call_3args_without_instrumentation(command, arg1, arg2, arg3)
      @pool.with do |conn|
        result = conn.call_3args(command, arg1, arg2, arg3)
        raise result if result.is_a?(CommandError)

        result
      end
    end
  end
end
