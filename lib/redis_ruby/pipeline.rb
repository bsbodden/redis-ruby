# frozen_string_literal: true

module RedisRuby
  # Pipeline for batching multiple commands
  #
  # Pipelines reduce network round-trips by sending multiple commands
  # at once and receiving all responses together.
  #
  # @example Using a pipeline
  #   results = client.pipelined do |pipe|
  #     pipe.set("key1", "value1")
  #     pipe.set("key2", "value2")
  #     pipe.get("key1")
  #     pipe.get("key2")
  #   end
  #   # => ["OK", "OK", "value1", "value2"]
  #
  class Pipeline
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

    # Frozen command constants for pipeline-specific commands
    CMD_PING = "PING"
    CMD_HGETALL = "HGETALL"
    CMD_ZSCORE = "ZSCORE"
    CMD_ZMSCORE = "ZMSCORE"
    CMD_ZRANGE = "ZRANGE"
    CMD_ZREVRANGE = "ZREVRANGE"
    CMD_ZRANGEBYSCORE = "ZRANGEBYSCORE"
    CMD_ZREVRANGEBYSCORE = "ZREVRANGEBYSCORE"
    CMD_ZINCRBY = "ZINCRBY"
    CMD_ZPOPMIN = "ZPOPMIN"
    CMD_ZPOPMAX = "ZPOPMAX"
    CMD_BZPOPMIN = "BZPOPMIN"
    CMD_BZPOPMAX = "BZPOPMAX"
    CMD_ZSCAN = "ZSCAN"
    OPT_WITHSCORES = "WITHSCORES"
    OPT_LIMIT = "LIMIT"
    OPT_MATCH = "MATCH"
    OPT_COUNT = "COUNT"

    def initialize(connection)
      @connection = connection
      @commands = []
    end

    # Queue a command for execution
    #
    # @param command [String] Command name
    # @param args [Array] Command arguments
    # @return [Pipeline] self for chaining
    def call(command, *args)
      # Reuse args array to avoid allocation
      args.unshift(command)
      @commands << args
      self
    end

    # Fast path methods - delegate to call for pipeline compatibility
    # In pipeline mode we don't get the fast-path benefit, but commands work correctly
    # @api private
    def call_1arg(command, arg)
      @commands << [command, arg]
      self
    end

    # @api private
    def call_2args(command, arg1, arg2)
      @commands << [command, arg1, arg2]
      self
    end

    # @api private
    def call_3args(command, arg1, arg2, arg3)
      @commands << [command, arg1, arg2, arg3]
      self
    end

    # Execute all queued commands
    #
    # @return [Array] Results from all commands
    def execute
      return [] if @commands.empty?

      @connection.pipeline(@commands)
    end

    # Number of queued commands
    #
    # @return [Integer]
    def size
      @commands.size
    end

    alias length size

    # Check if pipeline is empty
    #
    # @return [Boolean]
    def empty?
      @commands.empty?
    end

    # Ping (override to not raise on error in pipeline)
    def ping
      call(CMD_PING)
    end

    # Override commands that do post-processing
    # In a pipeline, we just queue the raw command

    # HGETALL - don't convert to hash
    def hgetall(key)
      call(CMD_HGETALL, key)
    end

    # ZSCORE - don't convert to float
    def zscore(key, member)
      call(CMD_ZSCORE, key, member)
    end

    # ZMSCORE - don't convert to floats
    def zmscore(key, *members)
      call(CMD_ZMSCORE, key, *members)
    end

    # ZRANGE with scores - don't convert
    def zrange(key, start, stop, withscores: false)
      args = [CMD_ZRANGE, key, start, stop]
      args.push(OPT_WITHSCORES) if withscores
      call(*args)
    end

    # ZREVRANGE with scores - don't convert
    def zrevrange(key, start, stop, withscores: false)
      args = [CMD_ZREVRANGE, key, start, stop]
      args.push(OPT_WITHSCORES) if withscores
      call(*args)
    end

    # ZRANGEBYSCORE - don't convert
    def zrangebyscore(key, min, max, withscores: false, limit: nil)
      args = [CMD_ZRANGEBYSCORE, key, min, max]
      args.push(OPT_WITHSCORES) if withscores
      args.push(OPT_LIMIT, *limit) if limit
      call(*args)
    end

    # ZREVRANGEBYSCORE - don't convert
    def zrevrangebyscore(key, max, min, withscores: false, limit: nil)
      args = [CMD_ZREVRANGEBYSCORE, key, max, min]
      args.push(OPT_WITHSCORES) if withscores
      args.push(OPT_LIMIT, *limit) if limit
      call(*args)
    end

    # ZINCRBY - don't convert to float
    def zincrby(key, increment, member)
      call(CMD_ZINCRBY, key, increment, member)
    end

    # ZPOPMIN - don't convert
    def zpopmin(key, count = nil)
      count ? call(CMD_ZPOPMIN, key, count) : call(CMD_ZPOPMIN, key)
    end

    # ZPOPMAX - don't convert
    def zpopmax(key, count = nil)
      count ? call(CMD_ZPOPMAX, key, count) : call(CMD_ZPOPMAX, key)
    end

    # BZPOPMIN - don't convert
    def bzpopmin(*keys, timeout: 0)
      call(CMD_BZPOPMIN, *keys, timeout)
    end

    # BZPOPMAX - don't convert
    def bzpopmax(*keys, timeout: 0)
      call(CMD_BZPOPMAX, *keys, timeout)
    end

    # ZSCAN - don't convert
    def zscan(key, cursor, match: nil, count: nil)
      args = [CMD_ZSCAN, key, cursor]
      args.push(OPT_MATCH, match) if match
      args.push(OPT_COUNT, count) if count
      call(*args)
    end
  end
end
