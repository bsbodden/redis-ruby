# frozen_string_literal: true

require "uri"

module RedisRuby
  # Asynchronous Redis client using Fiber Scheduler
  #
  # When used inside an `Async` block, all I/O operations automatically
  # yield to the fiber scheduler, enabling concurrent command execution.
  # When used outside an Async context, behaves like the synchronous client.
  #
  # @example Basic async usage
  #   require "async"
  #
  #   Async do
  #     client = RedisRuby::AsyncClient.new(url: "redis://localhost:6379")
  #     client.set("key", "value")
  #     client.get("key") # => "value"
  #   end
  #
  # @example Concurrent commands
  #   require "async"
  #
  #   Async do |task|
  #     client = RedisRuby::AsyncClient.new(url: "redis://localhost:6379")
  #
  #     # Execute commands concurrently
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
    include Commands::JSON
    include Commands::Search
    include Commands::BloomFilter
    include Commands::TimeSeries
    include Commands::VectorSet

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
    def initialize(url: nil, host: DEFAULT_HOST, port: DEFAULT_PORT, db: DEFAULT_DB,
                   password: nil, timeout: DEFAULT_TIMEOUT)
      if url
        parse_url(url)
      else
        @host = host
        @port = port
        @db = db
        @password = password
      end
      @timeout = timeout
      @connection = nil
      @mutex = Mutex.new
      ensure_connected
    end

    # Execute a Redis command
    #
    # Thread-safe: uses mutex for connection access.
    # Fiber-safe: yields to scheduler during I/O.
    #
    # @param command [String] Command name
    # @param args [Array] Command arguments
    # @return [Object] Command result
    def call(command, *args)
      @mutex.synchronize do
        ensure_connected
        result = @connection.call(command, *args)
        raise result if result.is_a?(CommandError)

        result
      end
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
    # @param nx [Boolean] Only set if key doesn't exist
    # @param xx [Boolean] Only set if key exists
    # @return [String, nil] "OK" or nil
    def set(key, value, ex: nil, px: nil, nx: false, xx: false)
      args = [key, value]
      args.push("EX", ex) if ex
      args.push("PX", px) if px
      args.push("NX") if nx
      args.push("XX") if xx
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
      @mutex.synchronize do
        ensure_connected
        pipeline = Pipeline.new(@connection)
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
      @mutex.synchronize do
        ensure_connected
        transaction = Transaction.new(@connection)
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
      @mutex.synchronize do
        ensure_connected
        result = @connection.call("WATCH", *keys)
        return result unless block

        begin
          yield
        ensure
          @connection.call("UNWATCH")
        end
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
      @mutex.synchronize do
        @connection&.close
        @connection = nil
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

    private

    # Parse Redis URL
    def parse_url(url)
      uri = URI.parse(url)
      @host = uri.host || DEFAULT_HOST
      @port = uri.port || DEFAULT_PORT
      @db = uri.path&.delete_prefix("/")&.to_i || DEFAULT_DB
      @password = uri.password
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
