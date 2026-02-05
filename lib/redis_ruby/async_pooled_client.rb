# frozen_string_literal: true

require "uri"

module RedisRuby
  # Fiber-aware Redis client with connection pooling
  #
  # Combines the async-pool gem for fiber-safe connection management
  # with Async gem for non-blocking I/O. This is the recommended client
  # for high-concurrency async applications.
  #
  # Each command checks out a connection from the pool, executes,
  # and returns it - allowing multiple fibers to execute concurrently.
  #
  # @example Basic usage with Async
  #   require "async"
  #
  #   Async do
  #     client = RedisRuby::AsyncPooledClient.new(
  #       url: "redis://localhost:6379",
  #       pool: { limit: 10 }
  #     )
  #
  #     client.set("key", "value")
  #     client.get("key") # => "value"
  #   end
  #
  # @example Concurrent operations
  #   Async do |task|
  #     client = RedisRuby::AsyncPooledClient.new(pool: { limit: 20 })
  #
  #     # Run 100 operations concurrently with only 20 connections
  #     tasks = 100.times.map do |i|
  #       task.async { client.get("key:#{i}") }
  #     end
  #
  #     results = tasks.map(&:wait)
  #   end
  #
  # @see https://github.com/socketry/async-pool
  #
  class AsyncPooledClient
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

    attr_reader :host, :port, :db, :timeout

    DEFAULT_HOST = "localhost"
    DEFAULT_PORT = 6379
    DEFAULT_DB = 0
    DEFAULT_TIMEOUT = 5.0
    DEFAULT_POOL_LIMIT = 5

    # Initialize a new async pooled Redis client
    #
    # @param url [String, nil] Redis URL (redis://host:port/db)
    # @param host [String] Redis host
    # @param port [Integer] Redis port
    # @param db [Integer] Redis database number
    # @param password [String, nil] Redis password
    # @param timeout [Float] Connection timeout in seconds
    # @param pool [Hash] Pool options (:limit)
    def initialize(url: nil, host: DEFAULT_HOST, port: DEFAULT_PORT, db: DEFAULT_DB,
                   password: nil, timeout: DEFAULT_TIMEOUT, pool: {})
      # Initialize ALL instance variables upfront for consistent object shapes (YJIT optimization)
      @host = host
      @port = port
      @db = db
      @password = password
      @timeout = timeout
      @pool = nil

      # Override from URL if provided
      parse_url(url) if url

      pool_limit = pool.fetch(:limit) { DEFAULT_POOL_LIMIT }

      @pool = Connection::AsyncPool.new(
        host: @host,
        port: @port,
        limit: pool_limit,
        connection_timeout: @timeout,
        password: @password,
        db: @db
      )
    end

    # Execute a Redis command
    #
    # Checks out a connection from the async pool, executes, and returns it.
    # Multiple fibers can execute commands concurrently.
    #
    # @param command [String] Command name
    # @param args [Array] Command arguments
    # @return [Object] Command result
    def call(command, *args)
      @pool.acquire do |conn|
        result = conn.call(command, *args)
        raise result if result.is_a?(CommandError)

        result
      end
    end

    # Fast path for single-argument commands (GET, DEL, EXISTS, etc.)
    # @api private
    def call_1arg(command, arg)
      @pool.acquire do |conn|
        result = conn.call_1arg(command, arg)
        raise result if result.is_a?(CommandError)

        result
      end
    end

    # Fast path for two-argument commands (SET without options, HGET, etc.)
    # @api private
    def call_2args(command, arg1, arg2)
      @pool.acquire do |conn|
        result = conn.call_2args(command, arg1, arg2)
        raise result if result.is_a?(CommandError)

        result
      end
    end

    # Fast path for three-argument commands (HSET, LRANGE, etc.)
    # @api private
    def call_3args(command, arg1, arg2, arg3)
      @pool.acquire do |conn|
        result = conn.call_3args(command, arg1, arg2, arg3)
        raise result if result.is_a?(CommandError)

        result
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
      @pool.acquire(&)
    end

    # Ping the Redis server
    #
    # @return [String] "PONG"
    def ping
      call("PING")
    end

    # Execute commands in a pipeline
    #
    # @yield [Pipeline] pipeline object to queue commands
    # @return [Array] results from all commands
    def pipelined
      @pool.acquire do |conn|
        pipeline = Pipeline.new(conn)
        yield pipeline
        results = pipeline.execute
        results.map { |r| r.is_a?(CommandError) ? raise(r) : r }
      end
    end

    # Execute commands in a transaction (MULTI/EXEC)
    #
    # @yield [Transaction] transaction object to queue commands
    # @return [Array, nil] results from all commands, or nil if aborted
    def multi
      @pool.acquire do |conn|
        transaction = Transaction.new(conn)
        yield transaction
        results = transaction.execute
        return nil if results.nil?

        # Handle case where transaction itself failed
        raise results if results.is_a?(CommandError)

        results.map { |r| r.is_a?(CommandError) ? raise(r) : r }
      end
    end

    # Watch keys for changes (optimistic locking)
    #
    # @param keys [Array<String>] keys to watch
    # @yield [optional] block to execute while watching
    # @return [Object] result of block, or "OK" if no block
    def watch(*keys, &block)
      @pool.acquire do |conn|
        result = conn.call("WATCH", *keys)
        return result unless block

        begin
          yield
        ensure
          conn.call("UNWATCH")
        end
      end
    end

    # Unwatch all watched keys
    #
    # @return [String] "OK"
    def unwatch
      call("UNWATCH")
    end

    # Close all connections in the pool
    def close
      @pool.close
    end

    alias disconnect close
    alias quit close

    # Pool limit
    #
    # @return [Integer]
    def pool_limit
      @pool.limit
    end

    # Check if connections are available
    #
    # @return [Boolean]
    def pool_available?
      @pool.available?
    end

    private

    # Parse Redis URL using shared utility
    def parse_url(url)
      parsed = Utils::URLParser.parse(url)
      @host = parsed[:host] || DEFAULT_HOST
      @port = parsed[:port] || DEFAULT_PORT
      @db = parsed[:db] || DEFAULT_DB
      @password = parsed[:password]
    end
  end
end
