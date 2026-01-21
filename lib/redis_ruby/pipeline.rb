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
      @commands << [command, *args]
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
      call("PING")
    end

    # SET (override to not raise on error in pipeline)
    def set(key, value, ex: nil, px: nil, nx: false, xx: false)
      args = [key, value]
      args.push("EX", ex) if ex
      args.push("PX", px) if px
      args.push("NX") if nx
      args.push("XX") if xx
      call("SET", *args)
    end

    # GET (override to not raise on error in pipeline)
    def get(key)
      call("GET", key)
    end

    # Override commands that do post-processing
    # In a pipeline, we just queue the raw command

    # HGETALL - don't convert to hash
    def hgetall(key)
      call("HGETALL", key)
    end

    # ZSCORE - don't convert to float
    def zscore(key, member)
      call("ZSCORE", key, member)
    end

    # ZMSCORE - don't convert to floats
    def zmscore(key, *members)
      call("ZMSCORE", key, *members)
    end

    # ZRANGE with scores - don't convert
    def zrange(key, start, stop, withscores: false)
      args = ["ZRANGE", key, start, stop]
      args.push("WITHSCORES") if withscores
      call(*args)
    end

    # ZREVRANGE with scores - don't convert
    def zrevrange(key, start, stop, withscores: false)
      args = ["ZREVRANGE", key, start, stop]
      args.push("WITHSCORES") if withscores
      call(*args)
    end

    # ZRANGEBYSCORE - don't convert
    def zrangebyscore(key, min, max, withscores: false, limit: nil)
      args = ["ZRANGEBYSCORE", key, min, max]
      args.push("WITHSCORES") if withscores
      args.push("LIMIT", *limit) if limit
      call(*args)
    end

    # ZREVRANGEBYSCORE - don't convert
    def zrevrangebyscore(key, max, min, withscores: false, limit: nil)
      args = ["ZREVRANGEBYSCORE", key, max, min]
      args.push("WITHSCORES") if withscores
      args.push("LIMIT", *limit) if limit
      call(*args)
    end

    # ZINCRBY - don't convert to float
    def zincrby(key, increment, member)
      call("ZINCRBY", key, increment, member)
    end

    # ZPOPMIN - don't convert
    def zpopmin(key, count = nil)
      count ? call("ZPOPMIN", key, count) : call("ZPOPMIN", key)
    end

    # ZPOPMAX - don't convert
    def zpopmax(key, count = nil)
      count ? call("ZPOPMAX", key, count) : call("ZPOPMAX", key)
    end

    # BZPOPMIN - don't convert
    def bzpopmin(*keys, timeout: 0)
      call("BZPOPMIN", *keys, timeout)
    end

    # BZPOPMAX - don't convert
    def bzpopmax(*keys, timeout: 0)
      call("BZPOPMAX", *keys, timeout)
    end

    # ZSCAN - don't convert
    def zscan(key, cursor, match: nil, count: nil)
      args = ["ZSCAN", key, cursor]
      args.push("MATCH", match) if match
      args.push("COUNT", count) if count
      call(*args)
    end
  end
end
