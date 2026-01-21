# frozen_string_literal: true

require "uri"

module RedisRuby
  # The main synchronous Redis client
  #
  # Pure Ruby implementation using RESP3 protocol.
  # Supports TCP, SSL/TLS, and Unix socket connections.
  #
  # @example Basic TCP usage
  #   client = RedisRuby::Client.new(url: "redis://localhost:6379")
  #   client.set("key", "value")
  #   client.get("key") # => "value"
  #
  # @example SSL/TLS connection
  #   client = RedisRuby::Client.new(url: "rediss://redis.example.com:6379")
  #
  # @example Unix socket connection
  #   client = RedisRuby::Client.new(url: "unix:///var/run/redis/redis.sock")
  #
  # @example SSL with custom parameters
  #   client = RedisRuby::Client.new(
  #     url: "rediss://redis.example.com:6379",
  #     ssl_params: {
  #       ca_file: "/path/to/ca.crt",
  #       verify_mode: OpenSSL::SSL::VERIFY_PEER
  #     }
  #   )
  #
  class Client
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

    attr_reader :host, :port, :path, :db, :timeout

    DEFAULT_HOST = "localhost"
    DEFAULT_PORT = 6379
    DEFAULT_DB = 0
    DEFAULT_TIMEOUT = 5.0

    # Initialize a new Redis client
    #
    # @param url [String, nil] Redis URL (redis://, rediss://, unix://)
    # @param host [String] Redis host (for TCP/SSL)
    # @param port [Integer] Redis port (for TCP/SSL)
    # @param path [String, nil] Unix socket path
    # @param db [Integer] Redis database number
    # @param password [String, nil] Redis password
    # @param timeout [Float] Connection timeout in seconds
    # @param ssl [Boolean] Enable SSL/TLS
    # @param ssl_params [Hash] SSL parameters for OpenSSL::SSL::SSLContext
    def initialize(url: nil, host: DEFAULT_HOST, port: DEFAULT_PORT, path: nil,
                   db: DEFAULT_DB, password: nil, timeout: DEFAULT_TIMEOUT,
                   ssl: false, ssl_params: {})
      if url
        parse_url(url)
      else
        @host = host
        @port = port
        @path = path
        @db = db
        @password = password
        @ssl = ssl
      end
      @timeout = timeout
      @ssl_params = ssl_params
      @connection = nil
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
    # @example
    #   results = client.pipelined do |pipe|
    #     pipe.set("key1", "value1")
    #     pipe.get("key1")
    #   end
    def pipelined
      ensure_connected
      pipeline = Pipeline.new(@connection)
      yield pipeline
      results = pipeline.execute
      # Raise any errors that occurred (most pipelines have no errors)
      results.each { |r| raise r if r.is_a?(CommandError) }
      results
    end

    # Execute commands in a transaction (MULTI/EXEC)
    #
    # @yield [Transaction] transaction object to queue commands
    # @return [Array, nil] results from all commands, or nil if aborted
    # @example
    #   results = client.multi do |tx|
    #     tx.set("key1", "value1")
    #     tx.incr("counter")
    #   end
    def multi
      ensure_connected
      transaction = Transaction.new(@connection)
      yield transaction
      results = transaction.execute
      return nil if results.nil?

      # Raise any errors in results (most transactions have no errors)
      results.each { |r| raise r if r.is_a?(CommandError) }
      results
    end

    # Watch keys for changes (optimistic locking)
    #
    # If any watched key is modified before EXEC, the transaction aborts.
    #
    # @param keys [Array<String>] keys to watch
    # @yield [optional] block to execute while watching
    # @return [Object] result of block, or "OK" if no block
    # @example With block (auto-unwatch)
    #   client.watch("counter") do
    #     current = client.get("counter").to_i
    #     client.multi do |tx|
    #       tx.set("counter", current + 1)
    #     end
    #   end
    # @example Without block (manual unwatch)
    #   client.watch("counter")
    #   current = client.get("counter").to_i
    #   client.multi { |tx| tx.set("counter", current + 1) }
    #   client.unwatch
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

    # Discard a transaction in progress
    #
    # @return [String] "OK"
    def discard
      ensure_connected
      call("DISCARD")
    end

    # Unwatch all watched keys
    #
    # @return [String] "OK"
    def unwatch
      ensure_connected
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

    # Check if using SSL/TLS
    #
    # @return [Boolean]
    def ssl?
      @ssl || false
    end

    # Check if using Unix socket
    #
    # @return [Boolean]
    def unix?
      !@path.nil?
    end

    private

    # Parse Redis URL
    # Supports: redis://, rediss://, unix://
    def parse_url(url)
      uri = URI.parse(url)

      case uri.scheme
      when "redis"
        parse_tcp_url(uri)
        @ssl = false
      when "rediss"
        parse_tcp_url(uri)
        @ssl = true
      when "unix"
        parse_unix_url(uri)
      else
        raise ArgumentError, "Unsupported URL scheme: #{uri.scheme}. Use redis://, rediss://, or unix://"
      end
    end

    # Parse TCP/SSL URL
    def parse_tcp_url(uri)
      @host = uri.host || DEFAULT_HOST
      @port = uri.port || DEFAULT_PORT
      @db = uri.path&.delete_prefix("/")&.to_i || DEFAULT_DB
      @password = uri.password
      @path = nil
    end

    # Parse Unix socket URL
    def parse_unix_url(uri)
      @path = uri.path
      @host = nil
      @port = nil

      # Parse query string for db
      if uri.query
        params = URI.decode_www_form(uri.query).to_h
        @db = params["db"]&.to_i || DEFAULT_DB
      else
        @db = DEFAULT_DB
      end

      @password = uri.user # unix://password@/path/to/socket
    end

    # Ensure connection is established
    def ensure_connected
      return if @connection&.connected?

      @connection = create_connection
      authenticate if @password
      select_db if @db.positive?
    end

    # Create appropriate connection based on configuration
    def create_connection
      if @path
        Connection::Unix.new(path: @path, timeout: @timeout)
      elsif @ssl
        Connection::SSL.new(host: @host, port: @port, timeout: @timeout, ssl_params: @ssl_params)
      else
        Connection::TCP.new(host: @host, port: @port, timeout: @timeout)
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
  end
end
