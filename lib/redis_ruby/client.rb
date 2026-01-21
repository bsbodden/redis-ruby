# frozen_string_literal: true

require "redis-client"

module RedisRuby
  # The main Redis client class
  #
  # @example Basic usage
  #   client = RedisRuby::Client.new(url: "redis://localhost:6379")
  #   client.set("key", "value")
  #   client.get("key") # => "value"
  #
  # @example With connection pool
  #   client = RedisRuby::Client.new(
  #     url: "redis://localhost:6379",
  #     pool: { size: 5, timeout: 5 }
  #   )
  #
  class Client
    attr_reader :config

    # Initialize a new Redis client
    #
    # @param url [String, nil] Redis URL
    # @param host [String] Redis host (default: "localhost")
    # @param port [Integer] Redis port (default: 6379)
    # @param db [Integer] Redis database number (default: 0)
    # @param password [String, nil] Redis password
    # @param timeout [Float] Connection timeout in seconds
    # @param pool [Hash, nil] Connection pool options
    def initialize(url: nil, host: "localhost", port: 6379, db: 0, password: nil, timeout: 5.0, pool: nil)
      @config = build_config(url: url, host: host, port: port, db: db, password: password, timeout: timeout)
      @pool_config = pool
      @client = create_client
    end

    # Execute a Redis command
    #
    # @param command [Array] Command and arguments
    # @return [Object] Command result
    def call(*command)
      @client.call(*command)
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
      args = ["SET", key, value]
      args.push("EX", ex) if ex
      args.push("PX", px) if px
      args.push("NX") if nx
      args.push("XX") if xx
      call(*args)
    end

    # Get the value of a key
    #
    # @param key [String] The key
    # @return [String, nil] The value or nil
    def get(key)
      call("GET", key)
    end

    # Delete one or more keys
    #
    # @param keys [Array<String>] Keys to delete
    # @return [Integer] Number of keys deleted
    def del(*keys)
      call("DEL", *keys)
    end

    # Check if a key exists
    #
    # @param keys [Array<String>] Keys to check
    # @return [Integer] Number of keys that exist
    def exists(*keys)
      call("EXISTS", *keys)
    end

    # Close the connection
    def close
      @client.close
    end

    alias disconnect close
    alias quit close

    private

    def build_config(url:, host:, port:, db:, password:, timeout:)
      if url
        RedisClient.config(url: url, timeout: timeout)
      else
        RedisClient.config(
          host: host,
          port: port,
          db: db,
          password: password,
          timeout: timeout
        )
      end
    end

    def create_client
      if @pool_config
        @config.new_pool(**@pool_config)
      else
        @config.new_client
      end
    end
  end
end
