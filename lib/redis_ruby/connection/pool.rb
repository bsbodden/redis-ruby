# frozen_string_literal: true

require "connection_pool"

module RR
  module Connection
    # Thread-safe connection pool for Redis connections
    #
    # Uses the connection_pool gem to manage a pool of TCP connections.
    # Connections are created lazily and reused across threads.
    #
    # @example Basic usage
    #   pool = Pool.new(host: "localhost", port: 6379, size: 10)
    #   pool.with do |conn|
    #     conn.call("PING")  # => "PONG"
    #   end
    #
    # @example With timeout
    #   pool = Pool.new(host: "localhost", size: 5, pool_timeout: 10)
    #   pool.with do |conn|
    #     conn.call("GET", "key")
    #   end
    #
    class Pool
      DEFAULT_SIZE = 5
      DEFAULT_TIMEOUT = 5

      attr_reader :size, :timeout

      # Initialize a new connection pool
      #
      # @param host [String] Redis server host
      # @param port [Integer] Redis server port
      # @param size [Integer] Maximum pool size
      # @param pool_timeout [Float] Timeout waiting for connection from pool
      # @param connection_timeout [Float] Connection timeout in seconds
      # @param password [String, nil] Redis password
      # @param db [Integer] Redis database number
      def initialize(host: TCP::DEFAULT_HOST, port: TCP::DEFAULT_PORT,
                     size: DEFAULT_SIZE, pool_timeout: DEFAULT_TIMEOUT,
                     connection_timeout: TCP::DEFAULT_TIMEOUT,
                     password: nil, db: 0)
        @host = host
        @port = port
        @size = size
        @timeout = pool_timeout
        @connection_timeout = connection_timeout
        @password = password
        @db = db

        @pool = ConnectionPool.new(size: size, timeout: pool_timeout) do
          create_connection
        end
      end

      # Execute a block with a connection from the pool
      #
      # The connection is automatically returned to the pool after the block.
      #
      # @yield [TCP] connection from the pool
      # @return [Object] result of the block
      def with(&)
        @pool.with(&)
      end

      # Close all connections in the pool
      def close
        @pool.shutdown(&:close)
      end

      alias shutdown close

      # Number of available connections in the pool
      #
      # @return [Integer]
      def available
        @pool.available
      end

      private

      # Create a new connection
      def create_connection
        conn = TCP.new(host: @host, port: @port, timeout: @connection_timeout)
        authenticate(conn) if @password
        select_db(conn) if @db.positive?
        conn
      end

      # Authenticate with password
      def authenticate(conn)
        result = conn.call("AUTH", @password)
        raise ConnectionError, result.message if result.is_a?(CommandError)
      end

      # Select database
      def select_db(conn)
        result = conn.call("SELECT", @db.to_s)
        raise ConnectionError, result.message if result.is_a?(CommandError)
      end
    end
  end
end
