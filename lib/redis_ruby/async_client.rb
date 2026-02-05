# frozen_string_literal: true

require "uri"

module RedisRuby
  # Asynchronous Redis client for single-fiber use
  #
  # Provides a single connection for use within one fiber. When used inside
  # an `Async` block, I/O operations yield to the fiber scheduler.
  #
  # IMPORTANT: This client is NOT safe for concurrent access from multiple
  # fibers. For concurrent operations, use AsyncPooledClient instead which
  # provides fiber-safe connection pooling.
  #
  # @example Basic async usage (single fiber)
  #   require "async"
  #
  #   Async do
  #     client = RedisRuby::AsyncClient.new(url: "redis://localhost:6379")
  #     client.set("key", "value")
  #     client.get("key") # => "value"
  #   end
  #
  # @example Concurrent commands (use AsyncPooledClient!)
  #   require "async"
  #
  #   Async do |task|
  #     # For concurrent access, use AsyncPooledClient
  #     client = RedisRuby::AsyncPooledClient.new(
  #       url: "redis://localhost:6379",
  #       pool: { limit: 10 }
  #     )
  #
  #     # Now safe to run concurrent commands
  #     tasks = 10.times.map do |i|
  #       task.async { client.get("key:#{i}") }
  #     end
  #
  #     results = tasks.map(&:wait)
  #   end
  #
  class AsyncClient
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

    attr_reader :host, :port, :db, :timeout

    DEFAULT_HOST = "localhost"
    DEFAULT_PORT = 6379
    DEFAULT_DB = 0
    DEFAULT_TIMEOUT = 5.0

    # Initialize a new async Redis client
    #
    # @param url [String, nil] Redis URL (redis://host:port/db)
    # @param host [String] Redis host
    # @param port [Integer] Redis port
    # @param db [Integer] Redis database number
    # @param password [String, nil] Redis password
    # @param timeout [Float] Connection timeout in seconds
    #
    # @note This client is for single-fiber use only. For concurrent access
    #   from multiple fibers, use AsyncPooledClient instead.
    def initialize(url: nil, host: DEFAULT_HOST, port: DEFAULT_PORT, db: DEFAULT_DB,
                   password: nil, timeout: DEFAULT_TIMEOUT)
      # Initialize ALL instance variables upfront for consistent object shapes (YJIT optimization)
      @host = host
      @port = port
      @db = db
      @password = password
      @timeout = timeout
      @connection = nil

      # Override from URL if provided
      parse_url(url) if url

      ensure_connected
    end

    # Execute a Redis command
    #
    # Yields to fiber scheduler during I/O operations.
    #
    # @param command [String] Command name
    # @param args [Array] Command arguments
    # @return [Object] Command result
    #
    # @note Not safe for concurrent access. Use AsyncPooledClient for
    #   concurrent operations from multiple fibers.
    def call(command, *)
      ensure_connected
      result = @connection.call(command, *)
      raise result if result.is_a?(CommandError)

      result
    end

    # Fast-path method for single-argument commands (avoids splat allocation)
    def call_1arg(command, arg)
      ensure_connected
      result = @connection.call_1arg(command, arg)
      raise result if result.is_a?(CommandError)

      result
    end

    # Fast-path method for two-argument commands (avoids splat allocation)
    def call_2args(command, arg1, arg2)
      ensure_connected
      result = @connection.call_2args(command, arg1, arg2)
      raise result if result.is_a?(CommandError)

      result
    end

    # Fast-path method for three-argument commands (avoids splat allocation)
    def call_3args(command, arg1, arg2, arg3)
      ensure_connected
      result = @connection.call_3args(command, arg1, arg2, arg3)
      raise result if result.is_a?(CommandError)

      result
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
      ensure_connected
      pipeline = Pipeline.new(@connection)
      yield pipeline
      results = pipeline.execute
      results.map { |r| r.is_a?(CommandError) ? raise(r) : r }
    end

    # Execute commands in a transaction (MULTI/EXEC)
    #
    # @yield [Transaction] transaction object to queue commands
    # @return [Array, nil] results from all commands, or nil if aborted
    def multi
      ensure_connected
      transaction = Transaction.new(@connection)
      yield transaction
      results = transaction.execute
      return nil if results.nil?

      # Handle case where transaction itself failed (e.g., MISCONF)
      raise results if results.is_a?(CommandError)

      results.map { |r| r.is_a?(CommandError) ? raise(r) : r }
    end

    # Watch keys for changes (optimistic locking)
    #
    # @param keys [Array<String>] keys to watch
    # @yield [optional] block to execute while watching
    # @return [Object] result of block, or "OK" if no block
    def watch(*keys, &block)
      ensure_connected
      result = @connection.call("WATCH", *keys)
      return result unless block

      begin
        yield
      ensure
        @connection.call("UNWATCH")
      end
    end

    # Unwatch all watched keys
    #
    # @return [String] "OK"
    def unwatch
      call("UNWATCH")
    end

    # Close the connection
    def close
      @connection&.close
      @connection = nil
    end

    alias disconnect close
    alias quit close

    # Check if connected
    #
    # @return [Boolean]
    def connected?
      @connection&.connected? || false
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

    # Ensure connection is established
    def ensure_connected
      return if @connection&.connected?

      @connection = Connection::TCP.new(host: @host, port: @port, timeout: @timeout)
      authenticate if @password
      select_db if @db.positive?
    end

    # Authenticate with password
    def authenticate
      @connection.call("AUTH", @password)
    end

    # Select database
    def select_db
      @connection.call("SELECT", @db.to_s)
    end
  end
end
