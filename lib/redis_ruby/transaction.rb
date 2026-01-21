# frozen_string_literal: true

module RedisRuby
  # Transaction for atomic command execution
  #
  # Transactions in Redis use MULTI/EXEC to execute multiple commands
  # atomically. All commands are queued and executed together.
  #
  # @example Using a transaction
  #   results = client.multi do |tx|
  #     tx.set("key1", "value1")
  #     tx.incr("counter")
  #   end
  #   # => ["OK", 1]
  #
  # @example With WATCH for optimistic locking
  #   client.watch("counter") do
  #     current = client.get("counter").to_i
  #     client.multi do |tx|
  #       tx.set("counter", current + 1)
  #     end
  #   end
  #
  class Transaction
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
    include Commands::Streams

    def initialize(connection)
      @connection = connection
      @commands = []
    end

    # Queue a command for execution
    #
    # @param command [String] Command name
    # @param args [Array] Command arguments
    # @return [String] "QUEUED"
    def call(command, *args)
      @commands << [command, *args]
      "QUEUED"
    end

    # Execute the transaction
    #
    # @return [Array, nil] Results from all commands, or nil if aborted
    def execute
      # Send MULTI
      @connection.call("MULTI")

      # Queue all commands
      @commands.each do |cmd|
        @connection.call(*cmd)
      end

      # Execute with EXEC
      @connection.call("EXEC")
    end

    # Number of queued commands
    #
    # @return [Integer]
    def size
      @commands.size
    end

    alias length size

    # Check if transaction is empty
    #
    # @return [Boolean]
    def empty?
      @commands.empty?
    end

    # Override commands that do post-processing
    # In a transaction, commands return "QUEUED"

    def ping
      call("PING")
    end

    def set(key, value, ex: nil, px: nil, nx: false, xx: false)
      args = [key, value]
      args.push("EX", ex) if ex
      args.push("PX", px) if px
      args.push("NX") if nx
      args.push("XX") if xx
      call("SET", *args)
    end

    def get(key)
      call("GET", key)
    end

    def hgetall(key)
      call("HGETALL", key)
    end

    def zscore(key, member)
      call("ZSCORE", key, member)
    end

    def zmscore(key, *members)
      call("ZMSCORE", key, *members)
    end

    def zrange(key, start, stop, withscores: false)
      args = ["ZRANGE", key, start, stop]
      args.push("WITHSCORES") if withscores
      call(*args)
    end

    def zrevrange(key, start, stop, withscores: false)
      args = ["ZREVRANGE", key, start, stop]
      args.push("WITHSCORES") if withscores
      call(*args)
    end

    def zrangebyscore(key, min, max, withscores: false, limit: nil)
      args = ["ZRANGEBYSCORE", key, min, max]
      args.push("WITHSCORES") if withscores
      args.push("LIMIT", *limit) if limit
      call(*args)
    end

    def zrevrangebyscore(key, max, min, withscores: false, limit: nil)
      args = ["ZREVRANGEBYSCORE", key, max, min]
      args.push("WITHSCORES") if withscores
      args.push("LIMIT", *limit) if limit
      call(*args)
    end

    def zincrby(key, increment, member)
      call("ZINCRBY", key, increment, member)
    end

    def zpopmin(key, count = nil)
      count ? call("ZPOPMIN", key, count) : call("ZPOPMIN", key)
    end

    def zpopmax(key, count = nil)
      count ? call("ZPOPMAX", key, count) : call("ZPOPMAX", key)
    end

    def zscan(key, cursor, match: nil, count: nil)
      args = ["ZSCAN", key, cursor]
      args.push("MATCH", match) if match
      args.push("COUNT", count) if count
      call(*args)
    end
  end
end
