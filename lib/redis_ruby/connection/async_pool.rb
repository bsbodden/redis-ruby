# frozen_string_literal: true

begin
  require "async/pool"
  require "async/pool/controller"
  require "async/pool/resource"
rescue LoadError
  # async-pool not available, that's fine
end

module RedisRuby
  module Connection
    # Fiber-aware connection pool for async Redis operations
    #
    # Uses async-pool gem (by Samuel Williams) for fiber-safe connection management.
    # Each fiber can check out connections independently without blocking others.
    #
    # This is the SOTA (state-of-the-art) approach for Ruby async pooling,
    # used by the socketry ecosystem (Falcon, async-redis, etc.)
    #
    # @example Basic usage with Async
    #   require "async"
    #
    #   Async do
    #     pool = AsyncPool.new(host: "localhost", port: 6379, limit: 10)
    #     pool.acquire do |conn|
    #       conn.call("PING")  # => "PONG"
    #     end
    #   end
    #
    # @see https://github.com/socketry/async-pool
    #
    class AsyncPool
      DEFAULT_LIMIT = 5

      attr_reader :limit

      # Resource wrapper that implements Async::Pool::Resource interface
      # Wraps a TCP connection with the required lifecycle methods
      class PooledConnection
        attr_reader :concurrency, :count

        def initialize(connection)
          @connection = connection
          @concurrency = 1 # Singleplex - one operation at a time
          @count = 0
          @closed = false
        end

        # Delegate call to the underlying connection
        def call(...)
          @count += 1
          @connection.call(...)
        end

        # Fast path for single-argument commands
        # @api private
        def call_1arg(command, arg)
          @count += 1
          @connection.call_1arg(command, arg)
        end

        # Fast path for two-argument commands
        # @api private
        def call_2args(command, arg1, arg2)
          @count += 1
          @connection.call_2args(command, arg1, arg2)
        end

        # Fast path for three-argument commands
        # @api private
        def call_3args(command, arg1, arg2, arg3)
          @count += 1
          @connection.call_3args(command, arg1, arg2, arg3)
        end

        # Delegate pipeline to the underlying connection
        def pipeline(...)
          @count += 1
          @connection.pipeline(...)
        end

        # Check if resource can be acquired
        def viable?
          !@closed && @connection.connected?
        end

        # Check if resource has been closed
        def closed?
          @closed || !@connection.connected?
        end

        # Close the resource
        def close
          @closed = true
          @connection.close
        end

        # Check if resource can be reused
        def reusable?
          viable?
        end
      end

      # Initialize a new fiber-aware connection pool
      #
      # @param host [String] Redis server host
      # @param port [Integer] Redis server port
      # @param limit [Integer] Maximum pool size
      # @param connection_timeout [Float] Connection timeout in seconds
      # @param password [String, nil] Redis password
      # @param db [Integer] Redis database number
      def initialize(host: TCP::DEFAULT_HOST, port: TCP::DEFAULT_PORT,
                     limit: DEFAULT_LIMIT, connection_timeout: TCP::DEFAULT_TIMEOUT,
                     password: nil, db: 0)
        @host = host
        @port = port
        @limit = limit
        @connection_timeout = connection_timeout
        @password = password
        @db = db

        unless defined?(Async::Pool::Controller)
          raise LoadError, "async-pool gem is required for AsyncPool. Add `gem 'async-pool'` to your Gemfile."
        end

        @pool = Async::Pool::Controller.wrap(limit: limit) do
          create_pooled_connection
        end
      end

      # Execute a block with a connection from the pool
      #
      # Fiber-safe: multiple fibers can check out connections concurrently.
      # The connection is automatically returned to the pool after the block.
      #
      # @yield [PooledConnection] connection from the pool
      # @return [Object] result of the block
      def acquire(&)
        @pool.acquire(&)
      end

      alias with acquire

      # Number of connections currently in use
      #
      # @return [Integer]
      def size
        @pool.size
      end

      # Check if any connections are available
      #
      # @return [Boolean]
      def available?
        @pool.available?
      end

      # Close all connections in the pool
      def close
        @pool.close
      end

      alias shutdown close

      private

      # Create a new pooled connection
      def create_pooled_connection
        conn = TCP.new(host: @host, port: @port, timeout: @connection_timeout)
        authenticate(conn) if @password
        select_db(conn) if @db.positive?
        PooledConnection.new(conn)
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
