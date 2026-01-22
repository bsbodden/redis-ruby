# frozen_string_literal: true

require "uri"

module RedisRuby
  # Thread-safe Redis client with connection pooling
  #
  # Each command checks out a connection from the pool, executes,
  # and returns it. This provides thread-safety without a single mutex.
  #
  # @example Basic usage
  #   client = RedisRuby::PooledClient.new(url: "redis://localhost:6379", pool: { size: 10 })
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
    def initialize(url: nil, host: DEFAULT_HOST, port: DEFAULT_PORT, db: DEFAULT_DB,
                   password: nil, timeout: DEFAULT_TIMEOUT, pool: {})
      if url
        parse_url(url)
      else
        @host = host
        @port = port
        @db = db
        @password = password
      end
      @timeout = timeout

      pool_size = pool.fetch(:size, DEFAULT_POOL_SIZE)
      pool_timeout = pool.fetch(:timeout, DEFAULT_POOL_TIMEOUT)

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
      @pool.with do |conn|
        result = conn.call(command, *args)
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
      @pool.with(&)
    end

    # Ping the Redis server
    #
    # @return [String] "PONG"
    def ping
      call("PING")
    end

    # Set a key to a value
    #
    # @param key [String] The key
    # @param value [String] The value
    # @param ex [Integer, nil] Expiration in seconds
    # @param px [Integer, nil] Expiration in milliseconds
    # @param exat [Integer, nil] Absolute Unix timestamp in seconds (Redis 6.2+)
    # @param pxat [Integer, nil] Absolute Unix timestamp in milliseconds (Redis 6.2+)
    # @param nx [Boolean] Only set if key doesn't exist
    # @param xx [Boolean] Only set if key exists
    # @param keepttl [Boolean] Keep existing TTL (Redis 6.0+)
    # @param get [Boolean] Return old value (Redis 6.2+)
    # @return [String, nil] "OK" or nil (or old value if get: true)
    def set(key, value, ex: nil, px: nil, exat: nil, pxat: nil, nx: false, xx: false, keepttl: false, get: false)
      args = [key, value]
      args.push("EX", ex) if ex
      args.push("PX", px) if px
      args.push("EXAT", exat) if exat
      args.push("PXAT", pxat) if pxat
      args.push("NX") if nx
      args.push("XX") if xx
      args.push("KEEPTTL") if keepttl
      args.push("GET") if get
      call("SET", *args)
    end

    # Get the value of a key
    #
    # @param key [String] The key
    # @return [String, nil] The value or nil
    def get(key)
      call("GET", key)
    end

    # Execute commands in a pipeline
    #
    # @yield [Pipeline] pipeline object to queue commands
    # @return [Array] results from all commands
    def pipelined
      @pool.with do |conn|
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
      @pool.with do |conn|
        transaction = Transaction.new(conn)
        yield transaction
        results = transaction.execute
        return nil if results.nil?

        results.map { |r| r.is_a?(CommandError) ? raise(r) : r }
      end
    end

    # Watch keys for changes (optimistic locking)
    #
    # @param keys [Array<String>] keys to watch
    # @yield [optional] block to execute while watching
    # @return [Object] result of block, or "OK" if no block
    def watch(*keys, &block)
      @pool.with do |conn|
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

    private

    # Parse Redis URL
    def parse_url(url)
      uri = URI.parse(url)
      @host = uri.host || DEFAULT_HOST
      @port = uri.port || DEFAULT_PORT
      @db = uri.path&.delete_prefix("/")&.to_i || DEFAULT_DB
      @password = uri.password
    end
  end
end
