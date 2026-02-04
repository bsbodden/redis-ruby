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

    attr_reader :host, :port, :path, :db, :timeout

    DEFAULT_HOST = "localhost"
    DEFAULT_PORT = 6379
    DEFAULT_DB = 0
    DEFAULT_TIMEOUT = 5.0

    # Frozen command constants to avoid string allocations
    CMD_PING = "PING"
    CMD_WATCH = "WATCH"
    CMD_UNWATCH = "UNWATCH"
    CMD_DISCARD = "DISCARD"
    CMD_AUTH = "AUTH"
    CMD_SELECT = "SELECT"

    # Initialize a new Redis client
    #
    # @param url [String, nil] Redis URL (redis://, rediss://, unix://)
    # @param host [String] Redis host (for TCP/SSL)
    # @param port [Integer] Redis port (for TCP/SSL)
    # @param path [String, nil] Unix socket path
    # @param db [Integer] Redis database number
    # @param password [String, nil] Redis password
    # @param username [String, nil] Redis username (ACL, Redis 6+)
    # @param timeout [Float] Connection timeout in seconds
    # @param ssl [Boolean] Enable SSL/TLS
    # @param ssl_params [Hash] SSL parameters for OpenSSL::SSL::SSLContext
    # @param retry_policy [RedisRuby::Retry, nil] Retry policy for transient failures
    # @param reconnect_attempts [Integer] Shorthand for retry count (creates default policy)
    # @param decode_responses [Boolean] Auto-decode binary responses to the specified encoding
    # @param encoding [String] Encoding for decoded responses (default: "UTF-8")
    def initialize(url: nil, host: DEFAULT_HOST, port: DEFAULT_PORT, path: nil,
                   db: DEFAULT_DB, password: nil, username: nil, timeout: DEFAULT_TIMEOUT,
                   ssl: false, ssl_params: {}, retry_policy: nil, reconnect_attempts: 0,
                   decode_responses: false, encoding: "UTF-8")
      if url
        parse_url(url)
      else
        @host = host
        @port = port
        @path = path
        @db = db
        @password = password
        @username = username
        @ssl = ssl
      end
      @timeout = timeout
      @ssl_params = ssl_params
      @connection = nil
      @retry_policy = retry_policy || build_default_retry_policy(reconnect_attempts)
      @decode_responses = decode_responses
      @encoding = encoding
    end

    # Execute a Redis command
    #
    # Automatically retries on transient connection/timeout errors
    # when a retry policy is configured.
    #
    # @param command [String] Command name
    # @param args [Array] Command arguments
    # @return [Object] Command result
    def call(command, *)
      @retry_policy.call do
        ensure_connected
        result = @connection.call_direct(command, *)
        raise result if result.is_a?(CommandError)

        @decode_responses ? decode_result(result) : result
      end
    end

    # Ping the Redis server
    #
    # @return [String] "PONG"
    def ping
      call(CMD_PING)
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
      result = @connection.call(CMD_WATCH, *keys)
      return result unless block

      begin
        yield
      ensure
        @connection.call(CMD_UNWATCH)
      end
    end

    # Discard a transaction in progress
    #
    # @return [String] "OK"
    def discard
      ensure_connected
      call(CMD_DISCARD)
    end

    # Unwatch all watched keys
    #
    # @return [String] "OK"
    def unwatch
      ensure_connected
      call(CMD_UNWATCH)
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
      @username = uri.user == "" ? nil : uri.user
      # When only password is provided (redis://:password@host), user is empty string
      @username = nil if @username && @password && @username == @password
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
    # Optimized: avoid safe navigation for hot path
    def ensure_connected
      return if @connection && @connection.connected?

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

    # Authenticate with password (and optional username for ACL)
    def authenticate
      if @username
        @connection.call(CMD_AUTH, @username, @password)
      else
        @connection.call(CMD_AUTH, @password)
      end
    end

    # Select database
    def select_db
      @connection.call(CMD_SELECT, @db.to_s)
    end

    # Decode a result to the configured encoding
    def decode_result(result)
      case result
      when String
        if result.frozen?
          result.encode(@encoding)
        else
          result.force_encoding(@encoding)
        end
      when Array
        result.map { |v| decode_result(v) }
      when Hash
        result.each_with_object({}) { |(k, v), h| h[decode_result(k)] = decode_result(v) }
      else
        result
      end
    end

    # Build a default retry policy from reconnect_attempts count
    def build_default_retry_policy(reconnect_attempts)
      if reconnect_attempts.positive?
        Retry.new(
          retries: reconnect_attempts,
          backoff: ExponentialWithJitterBackoff.new(base: 0.025, cap: 2.0),
          on_retry: ->(_error, _attempt) { @connection = nil }
        )
      else
        # No-op retry policy (zero retries, just executes once)
        Retry.new(retries: 0)
      end
    end
  end
end
