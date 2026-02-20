# frozen_string_literal: true

module RR
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

    # Check if currently inside a MULTI block
    #
    # @return [Boolean]
    def in_multi?
      true
    end

    # Prevent nested MULTI calls (redis-py pattern)
    #
    # @raise [ArgumentError] always, since Transaction already represents a MULTI block
    def multi
      raise ArgumentError, "MULTI calls cannot be nested"
    end

    # Handle arbitrary commands that aren't explicitly defined
    def method_missing(method_name, *, **kwargs)
      # Convert method name to Redis command (e.g., :echo -> "ECHO")
      command = method_name.to_s.upcase
      if kwargs.empty?
        call(command, *)
      else
        # Some commands might have keyword args - pass them as regular args
        call(command, *, **kwargs)
      end
    end

    def respond_to_missing?(_method_name, _include_private = false)
      true
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

    # Fast path methods - delegate to call for transaction compatibility
    # In transaction mode we don't get the fast-path benefit, but commands work correctly
    # @api private
    def call_1arg(command, arg)
      @commands << [command, arg]
      "QUEUED"
    end

    # @api private
    def call_2args(command, arg1, arg2)
      @commands << [command, arg1, arg2]
      "QUEUED"
    end

    # @api private
    def call_3args(command, arg1, arg2, arg3)
      @commands << [command, arg1, arg2, arg3]
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

    def hgetall(key)
      call("HGETALL", key)
    end

    def zscore(key, member)
      call("ZSCORE", key, member)
    end

    def zmscore(key, *members)
      call("ZMSCORE", key, *members)
    end

    def zrange(key, start, stop, withscores: false, with_scores: false)
      use_scores = withscores || with_scores
      args = ["ZRANGE", key, start, stop]
      args.push("WITHSCORES") if use_scores
      call(*args)
    end

    def zrevrange(key, start, stop, withscores: false, with_scores: false)
      use_scores = withscores || with_scores
      args = ["ZREVRANGE", key, start, stop]
      args.push("WITHSCORES") if use_scores
      call(*args)
    end

    def zrangebyscore(key, min, max, withscores: false, with_scores: false, limit: nil)
      use_scores = withscores || with_scores
      args = ["ZRANGEBYSCORE", key, min, max]
      args.push("WITHSCORES") if use_scores
      args.push("LIMIT", *limit) if limit
      call(*args)
    end

    def zrevrangebyscore(key, max, min, withscores: false, with_scores: false, limit: nil)
      use_scores = withscores || with_scores
      args = ["ZREVRANGEBYSCORE", key, max, min]
      args.push("WITHSCORES") if use_scores
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

    # Convenience methods for redis-rb compatibility

    # Add member to set, returns 1 if added, 0 if already exists
    def sadd?(key, *members)
      members = members.flatten
      call("SADD", key, *members)
    end

    # Remove member from set, returns 1 if removed, 0 if not found
    def srem?(key, *members)
      members = members.flatten
      call("SREM", key, *members)
    end

    # Check if key exists, returns count of existing keys
    def exists?(*keys)
      keys = keys.flatten
      call("EXISTS", *keys)
    end

    # Check if member exists in set, returns 1 if exists, 0 if not
    def sismember?(key, member)
      call("SISMEMBER", key, member)
    end

    # Get server info
    def info(section = nil)
      section ? call("INFO", section) : call("INFO")
    end

    # Get multiple keys and return as array (in transaction, cannot return hash)
    def mapped_mget(*keys)
      keys = keys.flatten
      call("MGET", *keys)
    end

    # Get multiple hash fields (in transaction, cannot return hash)
    def mapped_hmget(key, *fields)
      fields = fields.flatten
      call("HMGET", key, *fields)
    end
  end
end
