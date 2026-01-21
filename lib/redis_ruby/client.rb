# frozen_string_literal: true

require "uri"

module RedisRuby
  # The main synchronous Redis client
  #
  # Pure Ruby implementation using RESP3 protocol.
  # This is the foundation - async client will wrap this with Fiber scheduler.
  #
  # @example Basic usage
  #   client = RedisRuby::Client.new(url: "redis://localhost:6379")
  #   client.set("key", "value")
  #   client.get("key") # => "value"
  #
  class Client
    include Commands::Strings
    include Commands::Keys

    attr_reader :host, :port, :db, :timeout

    DEFAULT_HOST = "localhost"
    DEFAULT_PORT = 6379
    DEFAULT_DB = 0
    DEFAULT_TIMEOUT = 5.0

    # Initialize a new Redis client
    #
    # @param url [String, nil] Redis URL (redis://host:port/db)
    # @param host [String] Redis host
    # @param port [Integer] Redis port
    # @param db [Integer] Redis database number
    # @param password [String, nil] Redis password
    # @param timeout [Float] Connection timeout in seconds
    # rubocop:disable Metrics/ParameterLists
    def initialize(url: nil, host: DEFAULT_HOST, port: DEFAULT_PORT, db: DEFAULT_DB,
                   password: nil, timeout: DEFAULT_TIMEOUT)
      # rubocop:enable Metrics/ParameterLists
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
    end

    # Execute a Redis command
    #
    # @param command [String] Command name
    # @param args [Array] Command arguments
    # @return [Object] Command result
    def call(command, *)
      ensure_connected
      result = @connection.call(command, *)
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
    # rubocop:disable Metrics/ParameterLists
    def set(key, value, ex: nil, px: nil, nx: false, xx: false)
      # rubocop:enable Metrics/ParameterLists
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
