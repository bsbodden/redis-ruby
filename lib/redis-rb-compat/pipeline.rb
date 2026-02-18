# frozen_string_literal: true

# rubocop:disable Style/ArgumentsForwarding
class Redis
  # Future object for pipeline results (redis-rb compatibility)
  #
  # In redis-rb, pipelined commands return Future objects that
  # hold the result once the pipeline is executed.
  #
  # @example
  #   redis.pipelined do |pipe|
  #     future = pipe.get("key")
  #     future.class  # => Redis::Future
  #   end
  #   future.value  # => "value" (after pipeline executes)
  #
  class Future < ::BasicObject
    def initialize(command)
      @command = command
      @value = nil
      @resolved = false
      @transformation = nil
    end

    attr_reader :command

    # Get the future's value
    #
    # @raise [FutureNotReady] if the pipeline hasn't executed yet
    # @return [Object] the command result
    def value
      ::Kernel.raise ::Redis::FutureNotReady unless @resolved

      @transformation ? @transformation.call(@value) : @value
    end

    # Check if the future has been resolved
    #
    # @return [Boolean]
    def resolved?
      @resolved
    end

    # Set the value (called by pipeline after execution)
    # @api private
    def _set_value(value)
      @value = value
      @resolved = true
    end

    # Transform the result when it becomes available
    #
    # @yield [value] transformation block
    # @return [Future] self
    def then(&block)
      @transformation = block
      self
    end

    # Inspect string
    def inspect
      if @resolved
        "#<Redis::Future @value=#{@value.inspect}>"
      else
        "#<Redis::Future (pending)>"
      end
    end

    def class
      ::Redis::Future
    end

    def is_a?(klass)
      [::Redis::Future, ::BasicObject].include?(klass)
    end

    def instance_of?(klass)
      klass == ::Redis::Future
    end

    def kind_of?(klass)
      is_a?(klass)
    end

    def instance_variable_defined?(name)
      case name
      when :@inner_futures then defined?(@inner_futures)
      when :@command then defined?(@command)
      when :@value then defined?(@value)
      when :@resolved then defined?(@resolved)
      when :@transformation then defined?(@transformation)
      else false
      end
    end

    def instance_variable_get(name)
      case name
      when :@inner_futures then @inner_futures
      when :@command then @command
      when :@value then @value
      when :@resolved then @resolved
      when :@transformation then @transformation
      end
    end

    def instance_variable_set(name, value)
      case name
      when :@inner_futures then @inner_futures = value
      when :@command then @command = value
      when :@value then @value = value
      when :@resolved then @resolved = value
      when :@transformation then @transformation = value
      end
    end
  end

  # Helper for building SET command arguments from keyword options
  #
  # @api private
  module SetCommandHelper
    private

    def build_set_args(key, value, ex:, px:, exat:, pxat:, nx:, xx:, keepttl:, get:)
      args = [key, value]
      append_set_ttl_args(args, ex: ex, px: px, exat: exat, pxat: pxat)
      args.push("NX") if nx
      args.push("XX") if xx
      args.push("KEEPTTL") if keepttl
      args.push("GET") if get
      args
    end

    def set_has_options?(ex:, px:, exat:, pxat:, nx:, xx:, keepttl:, get:)
      set_has_ttl_options?(ex: ex, px: px, exat: exat, pxat: pxat) || nx || xx || keepttl || get
    end

    def set_has_ttl_options?(ex:, px:, exat:, pxat:)
      !ex.nil? || !px.nil? || !exat.nil? || !pxat.nil?
    end

    def append_set_ttl_args(args, ex:, px:, exat:, pxat:)
      args.push("EX", ex) if ex
      args.push("PX", px) if px
      args.push("EXAT", exat) if exat
      args.push("PXAT", pxat) if pxat
    end
  end

  # Shared command methods for PipelinedConnection and MultiConnection
  #
  # This module assumes the including class defines:
  # - call(command, *args)
  # - call_1arg(command, arg)
  # - call_2args(command, arg1, arg2)
  # - call_3args(command, arg1, arg2, arg3)
  #
  module FutureCommands # rubocop:disable Metrics/ModuleLength
    include SetCommandHelper

    # String commands

    def ping
      call("PING")
    end

    def set(key, value, ex: nil, px: nil, exat: nil, pxat: nil, nx: false, xx: false, keepttl: false, get: false)
      unless set_has_options?(ex: ex, px: px, exat: exat, pxat: pxat, nx: nx, xx: xx, keepttl: keepttl, get: get)
        return call_2args("SET", key, value)
      end

      args = build_set_args(key, value, ex: ex, px: px, exat: exat, pxat: pxat, nx: nx, xx: xx, keepttl: keepttl,
                                        get: get)
      call("SET", *args)
    end

    def get(key)
      call_1arg("GET", key)
    end

    def del(*keys)
      keys.length == 1 ? call_1arg("DEL", keys[0]) : call("DEL", *keys)
    end

    def exists(*keys)
      keys.length == 1 ? call_1arg("EXISTS", keys[0]) : call("EXISTS", *keys)
    end

    def exists?(*keys)
      future = keys.length == 1 ? call_1arg("EXISTS", keys[0]) : call("EXISTS", *keys)
      future.then(&:positive?)
    end

    def incr(key)
      call_1arg("INCR", key)
    end

    def decr(key)
      call_1arg("DECR", key)
    end

    def incrby(key, increment)
      call_2args("INCRBY", key, increment)
    end

    def decrby(key, decrement)
      call_2args("DECRBY", key, decrement)
    end

    def incrbyfloat(key, increment)
      call_2args("INCRBYFLOAT", key, increment)
    end

    def mget(*keys)
      keys = keys.flatten
      call("MGET", *keys)
    end

    def mset(*)
      call("MSET", *)
    end

    def msetnx(*)
      future = call("MSETNX", *)
      future.then { |v| v == 1 }
    end

    def setnx(key, value)
      call("SETNX", key, value)
    end

    def setex(key, seconds, value)
      call("SETEX", key, seconds, value)
    end

    def psetex(key, milliseconds, value)
      call("PSETEX", key, milliseconds, value)
    end

    def append(key, value)
      call_2args("APPEND", key, value)
    end

    def strlen(key)
      call_1arg("STRLEN", key)
    end

    def getrange(key, start_pos, end_pos)
      call_3args("GETRANGE", key, start_pos, end_pos)
    end

    def setrange(key, offset, value)
      call_3args("SETRANGE", key, offset, value)
    end

    # Key commands

    def expire(key, seconds)
      call_2args("EXPIRE", key, seconds)
    end

    def pexpire(key, milliseconds)
      call_2args("PEXPIRE", key, milliseconds)
    end

    def expireat(key, timestamp)
      call_2args("EXPIREAT", key, timestamp)
    end

    def pexpireat(key, timestamp)
      call_2args("PEXPIREAT", key, timestamp)
    end

    def ttl(key)
      call_1arg("TTL", key)
    end

    def pttl(key)
      call_1arg("PTTL", key)
    end

    def persist(key)
      call_1arg("PERSIST", key)
    end

    def type(key)
      call_1arg("TYPE", key)
    end

    def rename(key, newkey)
      call_2args("RENAME", key, newkey)
    end

    def renamenx(key, newkey)
      call_2args("RENAMENX", key, newkey)
    end

    # Hash commands

    def hset(key, *field_values)
      if field_values.size == 2
        call_3args("HSET", key, field_values[0],
                   field_values[1])
      else
        call("HSET", key, *field_values)
      end
    end

    def hget(key, field)
      call_2args("HGET", key, field)
    end

    def hsetnx(key, field, value)
      future = call_3args("HSETNX", key, field, value)
      future.then { |v| v == 1 }
    end

    def hmget(key, *fields)
      fields = fields.flatten
      call("HMGET", key, *fields)
    end

    def hmset(key, *field_values)
      call("HMSET", key, *field_values)
    end

    def hdel(key, *fields)
      fields.size == 1 ? call_2args("HDEL", key, fields[0]) : call("HDEL", key, *fields)
    end

    def hexists(key, field)
      future = call_2args("HEXISTS", key, field)
      future.then { |v| v == 1 }
    end

    def hkeys(key)
      call_1arg("HKEYS", key)
    end

    def hvals(key)
      call_1arg("HVALS", key)
    end

    def hlen(key)
      call("HLEN", key)
    end

    def hincrby(key, field, increment)
      call("HINCRBY", key, field, increment)
    end

    def hincrbyfloat(key, field, increment)
      call("HINCRBYFLOAT", key, field, increment)
    end

    def hgetall(key)
      future = call_1arg("HGETALL", key)
      future.then { |result| result.is_a?(Array) ? Hash[*result.flatten] : result }
    end

    # List commands

    def lpush(key, *values)
      call("LPUSH", key, *values)
    end

    def rpush(key, *values)
      call("RPUSH", key, *values)
    end

    def lpop(key, count = nil)
      count ? call_2args("LPOP", key, count) : call_1arg("LPOP", key)
    end

    def rpop(key, count = nil)
      count ? call_2args("RPOP", key, count) : call_1arg("RPOP", key)
    end

    def lrange(key, start, stop)
      call_3args("LRANGE", key, start, stop)
    end

    def llen(key)
      call_1arg("LLEN", key)
    end

    def lindex(key, index)
      call_2args("LINDEX", key, index)
    end

    def lset(key, index, value)
      call_3args("LSET", key, index, value)
    end

    def lrem(key, count, value)
      call_3args("LREM", key, count, value)
    end

    def ltrim(key, start, stop)
      call_3args("LTRIM", key, start, stop)
    end

    # Set commands

    def sadd(key, *members)
      members = members.flatten
      members.size == 1 ? call_2args("SADD", key, members[0]) : call("SADD", key, *members)
    end

    def sadd?(key, *members)
      members = members.flatten
      future = members.size == 1 ? call_2args("SADD", key, members[0]) : call("SADD", key, *members)
      future.then(&:positive?)
    end

    def srem(key, *members)
      members = members.flatten
      members.size == 1 ? call_2args("SREM", key, members[0]) : call("SREM", key, *members)
    end

    def srem?(key, *members)
      members = members.flatten
      future = members.size == 1 ? call_2args("SREM", key, members[0]) : call("SREM", key, *members)
      future.then(&:positive?)
    end

    def sismember(key, member)
      future = call_2args("SISMEMBER", key, member)
      future.then { |v| v == 1 }
    end

    def smembers(key)
      call_1arg("SMEMBERS", key)
    end

    def scard(key)
      call_1arg("SCARD", key)
    end

    def spop(key, count = nil)
      count ? call_2args("SPOP", key, count) : call_1arg("SPOP", key)
    end

    def srandmember(key, count = nil)
      count ? call_2args("SRANDMEMBER", key, count) : call_1arg("SRANDMEMBER", key)
    end

    def smove(source, destination, member)
      future = call_3args("SMOVE", source, destination, member)
      future.then { |v| v == 1 }
    end

    def sinter(*keys)
      call("SINTER", *keys)
    end

    def sinterstore(destination, *keys)
      call("SINTERSTORE", destination, *keys)
    end

    def sunion(*keys)
      call("SUNION", *keys)
    end

    def sunionstore(destination, *keys)
      call("SUNIONSTORE", destination, *keys)
    end

    def sdiff(*keys)
      call("SDIFF", *keys)
    end

    def sdiffstore(destination, *keys)
      call("SDIFFSTORE", destination, *keys)
    end

    # Sorted set commands

    def zadd(key, *score_members, nx: false, xx: false, gt: false, lt: false, ch: false)
      args = ["ZADD", key]
      args.push("NX") if nx
      args.push("XX") if xx
      args.push("GT") if gt
      args.push("LT") if lt
      args.push("CH") if ch
      args.push(*score_members.flatten)
      call(*args)
    end

    def zrem(key, *members)
      members.size == 1 ? call_2args("ZREM", key, members[0]) : call("ZREM", key, *members)
    end

    def zscore(key, member)
      call_2args("ZSCORE", key, member)
    end

    def zrank(key, member)
      call_2args("ZRANK", key, member)
    end

    def zrevrank(key, member)
      call_2args("ZREVRANK", key, member)
    end

    def zcard(key)
      call_1arg("ZCARD", key)
    end

    def zcount(key, min, max)
      call_3args("ZCOUNT", key, min, max)
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
      call_3args("ZINCRBY", key, increment, member)
    end

    def zremrangebyrank(key, start, stop)
      call_3args("ZREMRANGEBYRANK", key, start, stop)
    end

    def zremrangebyscore(key, min, max)
      call_3args("ZREMRANGEBYSCORE", key, min, max)
    end

    def zpopmin(key, count = nil)
      count ? call_2args("ZPOPMIN", key, count) : call_1arg("ZPOPMIN", key)
    end

    def zpopmax(key, count = nil)
      count ? call_2args("ZPOPMAX", key, count) : call_1arg("ZPOPMAX", key)
    end

    # Server commands

    def info(section = nil)
      future = section ? call_1arg("INFO", section) : call("INFO")
      future.then { |result| parse_info(result) }
    end

    def select(db)
      call_1arg("SELECT", db)
    end

    def keys(pattern = "*")
      call_1arg("KEYS", pattern)
    end

    private

    def parse_info(result)
      return result unless result.is_a?(String)

      info = {}
      result.each_line do |line|
        line = line.chomp
        next if line.empty? || line.start_with?("#")

        key, value = line.split(":", 2)
        info[key] = value if key && value
      end
      info
    end
  end

  # Pipeline connection wrapper (redis-rb compatibility)
  #
  # This wraps the RedisRuby Pipeline and returns Future objects
  # instead of immediate values.
  #
  class PipelinedConnection
    include FutureCommands

    def initialize(client, pipeline)
      @client = client
      @pipeline = pipeline
      @futures = []
    end

    # Queue a command and return a Future
    def call(command, *args)
      future = Future.new([command, *args])
      @futures << future
      @pipeline.call(command, *args)
      future
    end

    # Fast path variants
    def call_1arg(command, arg)
      future = Future.new([command, arg])
      @futures << future
      @pipeline.call_1arg(command, arg)
      future
    end

    def call_2args(command, arg1, arg2)
      future = Future.new([command, arg1, arg2])
      @futures << future
      @pipeline.call_2args(command, arg1, arg2)
      future
    end

    def call_3args(command, arg1, arg2, arg3)
      future = Future.new([command, arg1, arg2, arg3])
      @futures << future
      @pipeline.call_3args(command, arg1, arg2, arg3)
      future
    end

    # Resolve all futures with the results
    # @api private
    def _resolve_futures(results)
      @futures.each_with_index do |future, index|
        resolve_single_future(future, results[index])
      end
    end

    # Get transformed values from all futures
    # @api private
    def _get_values
      @futures.map(&:value)
    end

    # PipelinedConnection-specific methods

    def mapped_mget(*keys)
      keys = keys.flatten
      future = mget(*keys)
      # Return a future that transforms the result into a hash
      future.then { |values| keys.zip(values).to_h }
    end

    def mapped_hmget(key, *fields)
      fields = fields.flatten
      future = hmget(key, *fields)
      future.then { |values| fields.zip(values).to_h }
    end

    def zpopmin(key, count = nil)
      future = count ? call_2args("ZPOPMIN", key, count) : call_1arg("ZPOPMIN", key)
      future.then { |result| transform_zpop_result(result, count) }
    end

    def zpopmax(key, count = nil)
      future = count ? call_2args("ZPOPMAX", key, count) : call_1arg("ZPOPMAX", key)
      future.then { |result| transform_zpop_result(result, count) }
    end

    def zincrby(key, increment, member)
      future = call_3args("ZINCRBY", key, increment, member)
      future.then { |result| parse_score(result) }
    end

    def zincryby(key, increment, member)
      # Intentional typo method name - just forward to zincrby
      zincrby(key, increment, member)
    end

    def config(action, *)
      future = call("CONFIG", action.to_s.upcase, *)
      if action.to_s.downcase == "get"
        future.then { |result| result.is_a?(Array) ? Hash[*result] : result }
      else
        future
      end
    end

    def multi
      # Multi inside pipeline - need special handling for futures
      # Commands inside multi return "QUEUED", but users want actual values from EXEC

      # Queue MULTI command
      call("MULTI")

      # Track the futures that should be resolved from EXEC results
      inner_futures = []

      # Create a wrapper that creates new futures for inner commands
      multi_wrapper = PipelineMultiWrapper.new(@pipeline, @futures, inner_futures)

      yield multi_wrapper if block_given?

      # Queue EXEC command
      exec_future = Future.new(["EXEC"])
      @futures << exec_future
      @pipeline.call("EXEC")

      # Set up EXEC to resolve inner futures when it completes
      exec_future.instance_variable_set(:@inner_futures, inner_futures)

      exec_future
    end

    def pipelined
      # Nested pipelining just continues in the same pipeline
      yield self if block_given?
    end

    # Handle arbitrary method calls
    def method_missing(method_name, *, **_kwargs)
      command = method_name.to_s.upcase.tr("_", " ")
      call(command, *)
    end

    def respond_to_missing?(_method_name, _include_private = false)
      true
    end

    private

    def resolve_single_future(future, result)
      if future.instance_variable_defined?(:@inner_futures)
        resolve_inner_futures(future, result)
      else
        future._set_value(result)
      end
    end

    def resolve_inner_futures(future, result)
      inner_futures = future.instance_variable_get(:@inner_futures)
      unless result.is_a?(::Array)
        future._set_value(result)
        return
      end

      inner_futures.each_with_index do |inner_future, inner_idx|
        inner_future._set_value(result[inner_idx]) if inner_idx < result.length
      end
      future._set_value(inner_futures.map(&:value))
    end

    def transform_zpop_result(result, count)
      return nil if result.nil? || (result.is_a?(Array) && result.empty?)

      count.nil? ? transform_zpop_single(result) : transform_zpop_multi(result)
    end

    def transform_zpop_single(result)
      if result.is_a?(Array) && result[0].is_a?(Array)
        [result[0][0], parse_score(result[0][1])]
      elsif result.is_a?(Array) && result.length == 2
        [result[0], parse_score(result[1])]
      else
        result
      end
    end

    def transform_zpop_multi(result)
      result.map { |pair| [pair[0], parse_score(pair[1])] }
    end

    def parse_score(value)
      return nil if value.nil?
      return value if value.is_a?(Float)

      case value.to_s
      when "inf", "+inf"
        Float::INFINITY
      when "-inf"
        -Float::INFINITY
      else
        Float(value)
      end
    end
  end

  # Wrapper for commands inside multi block within a pipeline
  #
  # This class ensures that commands inside pipeline.multi blocks:
  # 1. Get queued in the pipeline (so they're sent to Redis)
  # 2. Return futures that will be resolved from EXEC results (not "QUEUED")
  #
  class PipelineMultiWrapper
    include SetCommandHelper

    def initialize(pipeline, pipeline_futures, inner_futures)
      @pipeline = pipeline
      @pipeline_futures = pipeline_futures
      @inner_futures = inner_futures
    end

    def call(command, *args)
      # Queue the command in the pipeline
      @pipeline.call(command, *args)
      # Create a placeholder future in the pipeline futures list (for "QUEUED")
      queued_future = Future.new([command, *args])
      @pipeline_futures << queued_future
      # Create the user-facing future that will get EXEC results
      user_future = Future.new([command, *args])
      @inner_futures << user_future
      user_future
    end

    def call_1arg(command, arg)
      @pipeline.call_1arg(command, arg)
      queued_future = Future.new([command, arg])
      @pipeline_futures << queued_future
      user_future = Future.new([command, arg])
      @inner_futures << user_future
      user_future
    end

    def call_2args(command, arg1, arg2)
      @pipeline.call_2args(command, arg1, arg2)
      queued_future = Future.new([command, arg1, arg2])
      @pipeline_futures << queued_future
      user_future = Future.new([command, arg1, arg2])
      @inner_futures << user_future
      user_future
    end

    def call_3args(command, arg1, arg2, arg3)
      @pipeline.call_3args(command, arg1, arg2, arg3)
      queued_future = Future.new([command, arg1, arg2, arg3])
      @pipeline_futures << queued_future
      user_future = Future.new([command, arg1, arg2, arg3])
      @inner_futures << user_future
      user_future
    end

    # Common commands
    def set(key, value, ex: nil, px: nil, exat: nil, pxat: nil, nx: false, xx: false, keepttl: false, get: false)
      unless set_has_options?(ex: ex, px: px, exat: exat, pxat: pxat, nx: nx, xx: xx, keepttl: keepttl, get: get)
        return call_2args("SET", key, value)
      end

      args = build_set_args(key, value, ex: ex, px: px, exat: exat, pxat: pxat, nx: nx, xx: xx, keepttl: keepttl,
                                        get: get)
      call("SET", *args)
    end

    def get(key)
      call_1arg("GET", key)
    end

    def del(*keys)
      keys.length == 1 ? call_1arg("DEL", keys[0]) : call("DEL", *keys)
    end

    def incr(key)
      call_1arg("INCR", key)
    end

    def decr(key)
      call_1arg("DECR", key)
    end

    def lpush(key, *values)
      call("LPUSH", key, *values)
    end

    def rpush(key, *values)
      call("RPUSH", key, *values)
    end

    def sadd(key, *members)
      members = members.flatten
      members.size == 1 ? call_2args("SADD", key, members[0]) : call("SADD", key, *members)
    end

    def hset(key, *field_values)
      if field_values.size == 2
        call_3args("HSET", key, field_values[0],
                   field_values[1])
      else
        call("HSET", key, *field_values)
      end
    end

    def hget(key, field)
      call_2args("HGET", key, field)
    end

    def hgetall(key)
      # Queue the command and create a future with transformation
      @pipeline.call_1arg("HGETALL", key)
      queued_future = Future.new(["HGETALL", key])
      @pipeline_futures << queued_future
      user_future = Future.new(["HGETALL", key])
      @inner_futures << user_future
      # Transform the result to a hash when resolved
      user_future.then { |result| result.is_a?(Array) ? Hash[*result.flatten] : result }
    end

    def hmset(key, *field_values)
      call("HMSET", key, *field_values)
    end

    # Handle arbitrary method calls
    def method_missing(method_name, *, **_kwargs)
      command = method_name.to_s.upcase.tr("_", " ")
      call(command, *)
    end

    def respond_to_missing?(_method_name, _include_private = false)
      true
    end
  end

  # Transaction connection wrapper (redis-rb compatibility)
  #
  # This wraps the RedisRuby Transaction and returns Future objects
  # instead of "QUEUED" strings. Futures are resolved after EXEC.
  #
  class MultiConnection
    include FutureCommands

    def initialize(transaction)
      @transaction = transaction
      @futures = []
    end

    # Queue a command and return a Future
    def call(command, *args)
      future = Future.new([command, *args])
      @futures << future
      @transaction.call(command, *args)
      future
    end

    # Fast path variants
    def call_1arg(command, arg)
      future = Future.new([command, arg])
      @futures << future
      @transaction.call_1arg(command, arg)
      future
    end

    def call_2args(command, arg1, arg2)
      future = Future.new([command, arg1, arg2])
      @futures << future
      @transaction.call_2args(command, arg1, arg2)
      future
    end

    def call_3args(command, arg1, arg2, arg3)
      future = Future.new([command, arg1, arg2, arg3])
      @futures << future
      @transaction.call_3args(command, arg1, arg2, arg3)
      future
    end

    # Resolve all futures with the results
    # @api private
    def _resolve_futures(results)
      return if results.nil?

      @futures.each_with_index do |future, index|
        future._set_value(results[index]) if index < results.length
      end
    end

    # Get the futures array
    # @api private
    def _futures
      @futures
    end

    # Handle arbitrary method calls
    def method_missing(method_name, *, **_kwargs)
      command = method_name.to_s.upcase.tr("_", " ")
      call(command, *)
    end

    def respond_to_missing?(_method_name, _include_private = false)
      true
    end
  end
end
# rubocop:enable Style/ArgumentsForwarding
