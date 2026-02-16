# frozen_string_literal: true

require "uri"
require "redis_ruby"
require_relative "redis-rb-compat/errors"
require_relative "redis-rb-compat/commands"
require_relative "redis-rb-compat/pipeline"

# Redis compatibility layer for redis-rb
#
# This class provides a drop-in replacement API for redis-rb,
# allowing users to switch from `require "redis"` to using
# redis-ruby by simply changing their require statement.
#
# @example Basic usage
#   require "redis"  # or require "redis_ruby/compat" for explicit
#
#   redis = Redis.new(url: "redis://localhost:6379")
#   redis.set("key", "value")
#   redis.get("key")  # => "value"
#
# @example With mapped commands
#   redis.mapped_mset("k1" => "v1", "k2" => "v2")
#   redis.mapped_mget("k1", "k2")  # => {"k1"=>"v1", "k2"=>"v2"}
#
# @example Pipeline with futures
#   redis.pipelined do |pipe|
#     f = pipe.get("key")
#     f.class  # => Redis::Future
#   end
#   f.value  # => "value"
#
class Redis # rubocop:disable Metrics/ClassLength
  include Commands

  # VERSION from redis-ruby
  VERSION = ::RR::VERSION

  # Default connection options
  DEFAULT_OPTIONS = {
    host: "localhost",
    port: 6379,
    db: 0,
    timeout: 5.0,
  }.freeze

  attr_reader :options

  # Initialize a new Redis client
  #
  # @param options [Hash] Connection options
  # @option options [String] :url Redis URL (redis://host:port/db)
  # @option options [String] :host Redis host (default: localhost)
  # @option options [Integer] :port Redis port (default: 6379)
  # @option options [String] :path Unix socket path
  # @option options [Integer] :db Database number (default: 0)
  # @option options [String] :password Redis password
  # @option options [String] :username Redis username (ACL, Redis 6+)
  # @option options [Float] :timeout Connection timeout
  # @option options [Float] :connect_timeout Connect timeout (alias for timeout)
  # @option options [Float] :read_timeout Read timeout
  # @option options [Float] :write_timeout Write timeout
  # @option options [Integer] :reconnect_attempts Number of reconnect attempts
  # @option options [Boolean] :ssl Enable SSL/TLS
  # @option options [Hash] :ssl_params SSL parameters
  # @option options [String] :id Client ID (stored for connection info)
  # @option options [Symbol] :driver Ignored (always uses pure Ruby)
  # @option options [Array<Hash>] :sentinels Sentinel configuration
  # @option options [String] :name Sentinel master name
  # @option options [Symbol] :role Sentinel role (:master or :replica)
  #
  def initialize(options = {})
    @options = normalize_options(options)
    @client = create_client
    @id = @options[:id]
  end

  # Ping the Redis server
  #
  # @param message [String, nil] optional message to echo
  # @return [String] "PONG" or the echoed message
  def ping(message = nil)
    with_error_translation do
      message ? @client.call("PING", message) : @client.ping
    end
  end

  # Echo a message
  #
  # @param message [String] message to echo
  # @return [String] the echoed message
  def echo(message)
    with_error_translation { @client.call("ECHO", message) }
  end

  # Select a database
  #
  # @param db [Integer] database number
  # @return [String] "OK"
  def select(db)
    with_error_translation { @client.call("SELECT", db) }
  end

  # Quit the connection
  #
  # @return [String] "OK"
  def quit
    @client.close
    "OK"
  end

  # Close the connection
  def close
    @client.close
  end

  # For redis-rb compatibility tests
  def _client
    @client
  end

  alias disconnect! close

  # Check if connected
  #
  # @return [Boolean]
  def connected?
    @client.connected?
  end

  # Get connection information
  #
  # @return [Hash] connection info
  def connection
    {
      host: @options[:host],
      port: @options[:port],
      db: @options[:db],
      id: @id,
      location: @options[:path] || "#{@options[:host]}:#{@options[:port]}",
    }
  end

  # Execute a raw Redis command
  #
  # @param command [Array] command and arguments
  # @return [Object] command result
  def call(*command)
    with_error_translation { @client.call(*command) }
  end

  # Execute commands in a pipeline
  #
  # In redis-rb, pipelined returns Future objects that hold
  # the results once the pipeline is executed.
  #
  # @param exception [Boolean] raise exceptions on command errors
  # @yield [pipe] pipeline connection
  # @return [Array] results from all commands
  #
  # @example
  #   redis.pipelined do |pipe|
  #     future = pipe.get("key")
  #     pipe.set("key", "value")
  #   end
  #   future.value  # => "old_value"
  #
  def pipelined(exception: true)
    with_error_translation do
      pipeline = ::RR::Pipeline.new(get_connection)
      pipelined_connection = PipelinedConnection.new(@client, pipeline)

      yield pipelined_connection

      results = pipeline.execute

      # Check for errors first if exception mode is enabled
      if exception
        first_error = results.find { |r| r.is_a?(::RR::CommandError) }
        if first_error
          # Don't resolve any futures when there's an error in exception mode
          raise ErrorTranslation.translate(first_error)
        end
      end

      # Resolve all futures (only reached if no error or exception: false)
      pipelined_connection._resolve_futures(results)

      # Return transformed values (via future.value) to support mapped_* methods
      pipelined_connection._get_values
    end
  end

  # Execute commands in a transaction
  #
  # @yield [tx] transaction (MultiConnection wrapper that returns Futures)
  # @return [Array, nil] results or nil if aborted
  def multi
    with_error_translation do
      transaction = build_transaction
      multi_connection = MultiConnection.new(transaction)

      yield multi_connection

      results = transaction.execute
      return nil if results.nil?
      raise ErrorTranslation.translate(results) if results.is_a?(::RR::CommandError)

      resolve_multi_futures(multi_connection._futures, results)
    end
  end

  # Watch keys for changes
  #
  # @param keys [Array<String>] keys to watch
  # @yield [redis] optional block, yields self (the Redis wrapper)
  # @return [Object] result of block or "OK"
  def watch(*keys)
    keys = keys.flatten
    with_error_translation do
      if block_given?
        # Wrap the block to yield self (the Redis wrapper) instead of the client
        @client.watch(*keys) { yield self }
      else
        @client.watch(*keys)
      end
    end
  end

  # Unwatch all watched keys
  #
  # @return [String] "OK"
  def unwatch
    with_error_translation { @client.unwatch }
  end

  # Delegate string commands
  def set(key, value, ex: nil, px: nil, exat: nil, pxat: nil, nx: false, xx: false, keepttl: false, get: false)
    with_error_translation do
      @client.set(key, value, ex: ex, px: px, exat: exat, pxat: pxat, nx: nx, xx: xx, keepttl: keepttl, get: get)
    end
  end

  def get(key)
    with_error_translation { @client.get(key) }
  end

  def incr(key)
    with_error_translation { @client.incr(key) }
  end

  def decr(key)
    with_error_translation { @client.decr(key) }
  end

  def incrby(key, increment)
    with_error_translation { @client.incrby(key, increment) }
  end

  def decrby(key, decrement)
    with_error_translation { @client.decrby(key, decrement) }
  end

  def incrbyfloat(key, increment)
    with_error_translation { @client.incrbyfloat(key, increment) }
  end

  def append(key, value)
    with_error_translation { @client.append(key, value) }
  end

  def strlen(key)
    with_error_translation { @client.strlen(key) }
  end

  def getrange(key, start_pos, end_pos)
    with_error_translation { @client.getrange(key, start_pos, end_pos) }
  end

  def setrange(key, offset, value)
    with_error_translation { @client.setrange(key, offset, value) }
  end

  def mget(*keys)
    keys = keys.flatten
    with_error_translation { @client.mget(*keys) }
  end

  def mset(*args)
    with_error_translation { @client.mset(*args) }
  end

  def msetnx(*args)
    result = with_error_translation { @client.msetnx(*args) }
    result == 1
  end

  def setnx(key, value)
    with_error_translation { @client.setnx(key, value) }
  end

  def setex(key, seconds, value)
    with_error_translation { @client.setex(key, seconds, value) }
  end

  def psetex(key, milliseconds, value)
    with_error_translation { @client.psetex(key, milliseconds, value) }
  end

  def getset(key, value)
    with_error_translation { @client.getset(key, value) }
  end

  def getdel(key)
    with_error_translation { @client.getdel(key) }
  end

  def getex(key, ex: nil, px: nil, exat: nil, pxat: nil, persist: false)
    with_error_translation { @client.getex(key, ex: ex, px: px, exat: exat, pxat: pxat, persist: persist) }
  end

  # Delegate key commands
  def del(*keys)
    with_error_translation { @client.del(*keys) }
  end

  alias delete del

  def exists(*keys)
    with_error_translation { @client.exists(*keys) }
  end

  def expire(key, seconds, nx: false, xx: false, gt: false, lt: false)
    with_error_translation { @client.expire(key, seconds, nx: nx, xx: xx, gt: gt, lt: lt) }
  end

  def pexpire(key, milliseconds, nx: false, xx: false, gt: false, lt: false)
    with_error_translation { @client.pexpire(key, milliseconds, nx: nx, xx: xx, gt: gt, lt: lt) }
  end

  def expireat(key, timestamp, nx: false, xx: false, gt: false, lt: false)
    with_error_translation { @client.expireat(key, timestamp, nx: nx, xx: xx, gt: gt, lt: lt) }
  end

  def pexpireat(key, timestamp, nx: false, xx: false, gt: false, lt: false)
    with_error_translation { @client.pexpireat(key, timestamp, nx: nx, xx: xx, gt: gt, lt: lt) }
  end

  def ttl(key)
    with_error_translation { @client.ttl(key) }
  end

  def pttl(key)
    with_error_translation { @client.pttl(key) }
  end

  def persist(key)
    with_error_translation { @client.persist(key) }
  end

  def expiretime(key)
    with_error_translation { @client.expiretime(key) }
  end

  def pexpiretime(key)
    with_error_translation { @client.pexpiretime(key) }
  end

  def keys(pattern)
    with_error_translation { @client.keys(pattern) }
  end

  def scan(cursor, match: nil, count: nil, type: nil)
    with_error_translation { @client.scan(cursor, match: match, count: count, type: type) }
  end

  def scan_iter(match: "*", count: 10, type: nil)
    @client.scan_iter(match: match, count: count, type: type)
  end

  def type(key)
    with_error_translation { @client.type(key) }
  end

  def rename(key, newkey)
    with_error_translation { @client.rename(key, newkey) }
  end

  def renamenx(key, newkey)
    with_error_translation { @client.renamenx(key, newkey) }
  end

  def randomkey
    with_error_translation { @client.randomkey }
  end

  def unlink(*keys)
    with_error_translation { @client.unlink(*keys) }
  end

  def dump(key)
    with_error_translation { @client.dump(key) }
  end

  def restore(key, ttl, serialized_value, replace: false)
    with_error_translation { @client.restore(key, ttl, serialized_value, replace: replace) }
  end

  def touch(*keys)
    with_error_translation { @client.touch(*keys) }
  end

  def memory_usage(key)
    with_error_translation { @client.memory_usage(key) }
  end

  def copy(source, destination, db: nil, replace: false)
    with_error_translation { @client.copy(source, destination, db: db, replace: replace) }
  end

  # Delegate hash commands
  def hset(key, *field_values)
    with_error_translation { @client.hset(key, *field_values) }
  end

  def hget(key, field)
    with_error_translation { @client.hget(key, field) }
  end

  def hsetnx(key, field, value)
    result = with_error_translation { @client.hsetnx(key, field, value) }
    result == 1
  end

  def hmget(key, *fields)
    with_error_translation { @client.hmget(key, *fields) }
  end

  def hmset(key, *field_values)
    with_error_translation { @client.hmset(key, *field_values) }
  end

  def hgetall(key)
    with_error_translation { @client.hgetall(key) }
  end

  def hdel(key, *fields)
    fields = fields.flatten
    with_error_translation { @client.hdel(key, *fields) }
  end

  def hexists(key, field)
    result = with_error_translation { @client.hexists(key, field) }
    result == 1
  end

  def hkeys(key)
    with_error_translation { @client.hkeys(key) }
  end

  def hvals(key)
    with_error_translation { @client.hvals(key) }
  end

  def hlen(key)
    with_error_translation { @client.hlen(key) }
  end

  def hstrlen(key, field)
    with_error_translation { @client.hstrlen(key, field) }
  end

  def hincrby(key, field, increment)
    with_error_translation { @client.hincrby(key, field, increment) }
  end

  def hincrbyfloat(key, field, increment)
    with_error_translation { @client.hincrbyfloat(key, field, increment) }
  end

  def hscan(key, cursor, match: nil, count: nil)
    with_error_translation { @client.hscan(key, cursor, match: match, count: count) }
  end

  def hscan_iter(key, match: "*", count: 10)
    @client.hscan_iter(key, match: match, count: count)
  end

  def hrandfield(key, count = nil, with_values: false)
    raise ArgumentError, "count argument must be specified" if with_values && count.nil?

    with_error_translation { @client.hrandfield(key, count: count, withvalues: with_values) }
  end

  # Hash field expiration commands (Redis 7.4+)
  def hexpire(key, seconds, *fields, nx: false, xx: false, gt: false, lt: false)
    fields = fields.flatten
    with_error_translation { @client.hexpire(key, seconds, *fields, nx: nx, xx: xx, gt: gt, lt: lt) }
  end

  def hpexpire(key, milliseconds, *fields, nx: false, xx: false, gt: false, lt: false)
    fields = fields.flatten
    with_error_translation { @client.hpexpire(key, milliseconds, *fields, nx: nx, xx: xx, gt: gt, lt: lt) }
  end

  def hexpireat(key, unix_time, *fields, nx: false, xx: false, gt: false, lt: false)
    fields = fields.flatten
    with_error_translation { @client.hexpireat(key, unix_time, *fields, nx: nx, xx: xx, gt: gt, lt: lt) }
  end

  def hpexpireat(key, unix_time_ms, *fields, nx: false, xx: false, gt: false, lt: false)
    fields = fields.flatten
    with_error_translation { @client.hpexpireat(key, unix_time_ms, *fields, nx: nx, xx: xx, gt: gt, lt: lt) }
  end

  def httl(key, *fields)
    fields = fields.flatten
    with_error_translation { @client.httl(key, *fields) }
  end

  def hpttl(key, *fields)
    fields = fields.flatten
    with_error_translation { @client.hpttl(key, *fields) }
  end

  def hexpiretime(key, *fields)
    fields = fields.flatten
    with_error_translation { @client.hexpiretime(key, *fields) }
  end

  def hpexpiretime(key, *fields)
    fields = fields.flatten
    with_error_translation { @client.hpexpiretime(key, *fields) }
  end

  def hpersist(key, *fields)
    fields = fields.flatten
    with_error_translation { @client.hpersist(key, *fields) }
  end

  # Delegate list commands
  def lpush(key, *values)
    values = values.flatten
    with_error_translation { @client.lpush(key, *values) }
  end

  def rpush(key, *values)
    values = values.flatten
    with_error_translation { @client.rpush(key, *values) }
  end

  def lpushx(key, *values)
    values = values.flatten
    with_error_translation { @client.lpushx(key, *values) }
  end

  def rpushx(key, *values)
    values = values.flatten
    with_error_translation { @client.rpushx(key, *values) }
  end

  def lpop(key, count = nil)
    with_error_translation { @client.lpop(key, count) }
  end

  def rpop(key, count = nil)
    with_error_translation { @client.rpop(key, count) }
  end

  def lrange(key, start, stop)
    with_error_translation { @client.lrange(key, start, stop) }
  end

  def llen(key)
    with_error_translation { @client.llen(key) }
  end

  def lindex(key, index)
    with_error_translation { @client.lindex(key, index) }
  end

  def lset(key, index, value)
    with_error_translation { @client.lset(key, index, value) }
  end

  def lrem(key, count, value)
    with_error_translation { @client.lrem(key, count, value) }
  end

  def ltrim(key, start, stop)
    with_error_translation { @client.ltrim(key, start, stop) }
  end

  def linsert(key, where, pivot, value)
    with_error_translation { @client.linsert(key, where, pivot, value) }
  end

  def rpoplpush(source, destination)
    with_error_translation { @client.rpoplpush(source, destination) }
  end

  def lmove(source, destination, wherefrom, whereto)
    raise ArgumentError, "where_source must be 'LEFT' or 'RIGHT'" unless %w[LEFT RIGHT].include?(wherefrom.to_s.upcase)
    raise ArgumentError, "where_destination must be 'LEFT' or 'RIGHT'" unless %w[LEFT
                                                                                 RIGHT].include?(whereto.to_s.upcase)

    with_error_translation { @client.lmove(source, destination, wherefrom, whereto) }
  end

  def blpop(*keys, timeout: 0)
    with_error_translation { @client.blpop(*keys, timeout: timeout) }
  end

  def brpop(*keys, timeout: 0)
    with_error_translation { @client.brpop(*keys, timeout: timeout) }
  end

  def brpoplpush(source, destination, timeout: 0)
    with_error_translation { @client.brpoplpush(source, destination, timeout: timeout) }
  end

  def blmove(source, destination, wherefrom, whereto, timeout: 0)
    with_error_translation { @client.blmove(source, destination, wherefrom, whereto, timeout: timeout) }
  end

  def lmpop(*keys, modifier: "LEFT", count: nil)
    direction = modifier.to_s.downcase.to_sym
    with_error_translation { @client.lmpop(*keys, direction: direction, count: count) }
  end

  def blmpop(timeout, *keys, modifier: "LEFT", count: nil)
    direction = modifier.to_s.downcase.to_sym
    with_error_translation { @client.blmpop(timeout, *keys, direction: direction, count: count) }
  end

  # Delegate set commands
  def sadd(key, *members)
    members = members.flatten
    with_error_translation { @client.sadd(key, *members) }
  end

  def srem(key, *members)
    members = members.flatten
    with_error_translation { @client.srem(key, *members) }
  end

  def sismember(key, member)
    result = with_error_translation { @client.sismember(key, member) }
    result == 1
  end

  def smismember(key, *members)
    result = with_error_translation { @client.smismember(key, *members) }
    result.map { |v| v == 1 }
  end

  def smembers(key)
    with_error_translation { @client.smembers(key) }
  end

  def scard(key)
    with_error_translation { @client.scard(key) }
  end

  def spop(key, count = nil)
    with_error_translation { @client.spop(key, count) }
  end

  def srandmember(key, count = nil)
    with_error_translation { @client.srandmember(key, count) }
  end

  def smove(source, destination, member)
    result = with_error_translation { @client.smove(source, destination, member) }
    result == 1
  end

  def sinter(*keys)
    with_error_translation { @client.sinter(*keys) }
  end

  def sinterstore(destination, *keys)
    with_error_translation { @client.sinterstore(destination, *keys) }
  end

  def sintercard(*keys, limit: nil)
    with_error_translation { @client.sintercard(*keys, limit: limit) }
  end

  def sunion(*keys)
    with_error_translation { @client.sunion(*keys) }
  end

  def sunionstore(destination, *keys)
    with_error_translation { @client.sunionstore(destination, *keys) }
  end

  def sdiff(*keys)
    with_error_translation { @client.sdiff(*keys) }
  end

  def sdiffstore(destination, *keys)
    with_error_translation { @client.sdiffstore(destination, *keys) }
  end

  def sscan(key, cursor, match: nil, count: nil)
    with_error_translation { @client.sscan(key, cursor, match: match, count: count) }
  end

  def sscan_iter(key, match: "*", count: 10)
    @client.sscan_iter(key, match: match, count: count)
  end

  # Delegate sorted set commands
  def zadd(key, *args, nx: false, xx: false, gt: false, lt: false, ch: false, incr: false)
    score_members = normalize_zadd_args(args)
    return 0 if score_members.nil?

    result = with_error_translation do
      @client.zadd(key, *score_members, nx: nx, xx: xx, gt: gt, lt: lt, ch: ch, incr: incr)
    end

    format_zadd_result(result, args, incr: incr)
  end

  def zrem(key, *members)
    members = members.flatten
    return 0 if members.empty?

    result = with_error_translation { @client.zrem(key, *members) }
    # Return boolean for single member, count for multiple
    members.length == 1 ? result.positive? : result
  end

  def zscore(key, member)
    result = with_error_translation { @client.zscore(key, member) }
    parse_float(result)
  end

  def zmscore(key, *members)
    result = with_error_translation { @client.zmscore(key, *members) }
    result.map { |v| parse_float(v) }
  end

  def zrank(key, member, with_score: false, withscore: false)
    use_score = with_score || withscore
    result = with_error_translation { @client.zrank(key, member, withscore: use_score) }
    use_score && result ? [result[0], parse_float(result[1])] : result
  end

  def zrevrank(key, member, with_score: false, withscore: false)
    use_score = with_score || withscore
    result = with_error_translation { @client.zrevrank(key, member, withscore: use_score) }
    use_score && result ? [result[0], parse_float(result[1])] : result
  end

  def zcard(key)
    with_error_translation { @client.zcard(key) }
  end

  def zcount(key, min, max)
    with_error_translation { @client.zcount(key, min, max) }
  end

  def zrange(key, start, stop, byscore: false, bylex: false, rev: false, limit: nil, withscores: false,
             with_scores: false)
    use_scores = withscores || with_scores
    result = with_error_translation do
      @client.zrange(key, start, stop, byscore: byscore, bylex: bylex, rev: rev, limit: limit, withscores: use_scores)
    end
    use_scores ? transform_scores(result) : result
  end

  def zrangestore(destination, key, start, stop, byscore: false, by_score: false, bylex: false, by_lex: false,
                  rev: false, limit: nil)
    use_byscore = byscore || by_score
    use_bylex = bylex || by_lex
    with_error_translation do
      @client.zrangestore(destination, key, start, stop, byscore: use_byscore, bylex: use_bylex, rev: rev, limit: limit)
    end
  end

  def zrevrange(key, start, stop, withscores: false, with_scores: false)
    use_scores = withscores || with_scores
    result = with_error_translation { @client.zrevrange(key, start, stop, withscores: use_scores) }
    use_scores ? transform_scores(result) : result
  end

  def zrangebyscore(key, min, max, withscores: false, with_scores: false, limit: nil)
    use_scores = withscores || with_scores
    result = with_error_translation { @client.zrangebyscore(key, min, max, withscores: use_scores, limit: limit) }
    use_scores ? transform_scores(result) : result
  end

  def zrevrangebyscore(key, max, min, withscores: false, with_scores: false, limit: nil)
    use_scores = withscores || with_scores
    result = with_error_translation { @client.zrevrangebyscore(key, max, min, withscores: use_scores, limit: limit) }
    use_scores ? transform_scores(result) : result
  end

  def zincrby(key, increment, member)
    result = with_error_translation { @client.zincrby(key, increment, member) }
    parse_float(result)
  end

  def zremrangebyrank(key, start, stop)
    with_error_translation { @client.zremrangebyrank(key, start, stop) }
  end

  def zremrangebyscore(key, min, max)
    with_error_translation { @client.zremrangebyscore(key, min, max) }
  end

  def zpopmin(key, count = nil)
    with_error_translation { @client.zpopmin(key, count) }
  end

  def zpopmax(key, count = nil)
    with_error_translation { @client.zpopmax(key, count) }
  end

  def bzpopmin(*keys, timeout: 0)
    with_error_translation { @client.bzpopmin(*keys, timeout: timeout) }
  end

  def bzpopmax(*keys, timeout: 0)
    with_error_translation { @client.bzpopmax(*keys, timeout: timeout) }
  end

  def zscan(key, cursor, match: nil, count: nil)
    with_error_translation { @client.zscan(key, cursor, match: match, count: count) }
  end

  def zscan_iter(key, match: "*", count: 10)
    @client.zscan_iter(key, match: match, count: count)
  end

  def zinterstore(destination, keys, weights: nil, aggregate: nil)
    with_error_translation { @client.zinterstore(destination, keys, weights: weights, aggregate: aggregate) }
  end

  def zunionstore(destination, keys, weights: nil, aggregate: nil)
    with_error_translation { @client.zunionstore(destination, keys, weights: weights, aggregate: aggregate) }
  end

  def zunion(*keys, weights: nil, aggregate: nil, withscores: false, with_scores: false)
    use_scores = withscores || with_scores
    result = with_error_translation do
      @client.zunion(keys, weights: weights, aggregate: aggregate, withscores: use_scores)
    end
    use_scores ? transform_scores(result) : result
  end

  def zinter(*keys, weights: nil, aggregate: nil, withscores: false, with_scores: false)
    use_scores = withscores || with_scores
    result = with_error_translation do
      @client.zinter(keys, weights: weights, aggregate: aggregate, withscores: use_scores)
    end
    use_scores ? transform_scores(result) : result
  end

  def zdiff(*keys, withscores: false, with_scores: false)
    use_scores = withscores || with_scores
    result = with_error_translation { @client.zdiff(keys, withscores: use_scores) }
    use_scores ? transform_scores(result) : result
  end

  def zdiffstore(destination, keys)
    with_error_translation { @client.zdiffstore(destination, keys) }
  end

  def zintercard(*keys, limit: nil)
    with_error_translation { @client.zintercard(*keys, limit: limit) }
  end

  def zlexcount(key, min, max)
    with_error_translation { @client.zlexcount(key, min, max) }
  end

  def zrangebylex(key, min, max, limit: nil)
    with_error_translation { @client.zrangebylex(key, min, max, limit: limit) }
  end

  def zrevrangebylex(key, max, min, limit: nil)
    with_error_translation { @client.zrevrangebylex(key, max, min, limit: limit) }
  end

  def zremrangebylex(key, min, max)
    with_error_translation { @client.zremrangebylex(key, min, max) }
  end

  def zrandmember(key, count = nil, withscores: false, with_scores: false)
    use_scores = withscores || with_scores
    result = with_error_translation { @client.zrandmember(key, count, withscores: use_scores) }
    use_scores && result.is_a?(Array) ? transform_scores(result) : result
  end

  def zmpop(*keys, modifier: "MIN", count: nil)
    mod = modifier.to_s.downcase.to_sym
    result = with_error_translation { @client.zmpop(*keys, modifier: mod, count: count) }
    return nil if result.nil?

    # Transform [[member, score], ...] to have proper floats
    [result[0], transform_scores(result[1])]
  end

  def bzmpop(timeout, *keys, modifier: "MIN", count: nil)
    mod = modifier.to_s.downcase.to_sym
    result = with_error_translation { @client.bzmpop(timeout, *keys, modifier: mod, count: count) }
    return nil if result.nil?

    # Transform [[member, score], ...] to have proper floats
    [result[0], transform_scores(result[1])]
  end

  private

  # Transform flat array [m1, s1, m2, s2] or nested [[m1, s1], ...] to [[m1, s1], ...]
  def transform_scores(result)
    return result unless result.is_a?(Array) && result.any?

    if result[0].is_a?(Array)
      # Already nested
      result.map { |pair| [pair[0], parse_float(pair[1])] }
    else
      # Flat array - convert to pairs
      result.each_slice(2).map { |m, s| [m, parse_float(s)] }
    end
  end

  def parse_float(value)
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

  # Build a Transaction object from the current connection
  def build_transaction
    @client.send(:ensure_connected)
    connection = @client.instance_variable_get(:@connection)
    ::RR::Transaction.new(connection)
  end

  # Resolve futures from a multi/transaction, raising on first command error
  def resolve_multi_futures(futures, results)
    first_error = nil
    results.each_with_index do |result, index|
      if result.is_a?(::RR::CommandError)
        first_error ||= result
      elsif index < futures.length
        futures[index]._set_value(result)
      end
    end
    raise ErrorTranslation.translate(first_error) if first_error

    futures.map(&:value)
  end

  # Normalize zadd argument formats into a flat score-member array
  #
  # Returns nil if the input is an empty array (caller should return 0).
  def normalize_zadd_args(args)
    if args.length == 1 && args[0].is_a?(Array)
      normalize_zadd_array_arg(args[0])
    elsif args.length == 2
      args
    else
      args.flatten
    end
  end

  # Handle the single-array form of zadd args
  def normalize_zadd_array_arg(arr)
    return nil if arr.empty?

    arr[0].is_a?(Array) ? arr.flatten : arr
  end

  # Format zadd result based on input format and incr flag
  def format_zadd_result(result, args, incr:)
    if incr
      parse_float(result)
    elsif args.length == 2 && !args[0].is_a?(Array)
      result.positive?
    else
      result
    end
  end

  public

  # Delegate scripting commands
  def eval(*args, keys: nil, argv: nil)
    # Support both positional and keyword arguments
    # redis-rb: eval(script, keys, argv) or eval(script, keys: [...], argv: [...])
    case args.length
    when 1
      script = args[0]
      keys ||= []
      argv ||= []
    when 3
      script, keys, argv = args
    when 2
      script, keys = args
      argv ||= []
    else
      raise ArgumentError, "wrong number of arguments"
    end
    keys = Array(keys)
    argv = Array(argv)
    numkeys = keys.size
    with_error_translation { @client.eval(script, numkeys, *keys, *argv) }
  end

  def evalsha(*args, keys: nil, argv: nil)
    # Support both positional and keyword arguments
    case args.length
    when 1
      sha = args[0]
      keys ||= []
      argv ||= []
    when 3
      sha, keys, argv = args
    when 2
      sha, keys = args
      argv ||= []
    else
      raise ArgumentError, "wrong number of arguments"
    end
    keys = Array(keys)
    argv = Array(argv)
    numkeys = keys.size
    with_error_translation { @client.evalsha(sha, numkeys, *keys, *argv) }
  end

  def script(subcommand, *args)
    case subcommand.to_s.downcase
    when "load"
      script_load(*args)
    when "exists"
      script_exists(*args)
    when "flush"
      script_flush
    when "kill"
      script_kill
    else
      with_error_translation { @client.call("SCRIPT", subcommand.to_s.upcase, *args) }
    end
  end

  def script_load(script)
    with_error_translation { @client.script_load(script) }
  end

  TRUTHY_SCRIPT_VALUES = [1, true].freeze
  private_constant :TRUTHY_SCRIPT_VALUES

  def script_exists(*shas)
    # Check if first arg is an array (explicit array argument)
    if shas.length == 1 && shas[0].is_a?(Array)
      # Called with array: script(:exists, [a, b]) -> returns array
      shas = shas[0]
      result = with_error_translation { @client.script_exists(*shas) }
      result.map { |v| TRUTHY_SCRIPT_VALUES.include?(v) }
    elsif shas.length == 1
      # Called with single SHA: script(:exists, sha) -> returns single boolean
      result = with_error_translation { @client.script_exists(shas[0]) }
      result.map { |v| TRUTHY_SCRIPT_VALUES.include?(v) }.first
    else
      # Called with multiple SHAs as varargs
      result = with_error_translation { @client.script_exists(*shas) }
      result.map { |v| TRUTHY_SCRIPT_VALUES.include?(v) }
    end
  end

  def script_flush(mode = nil)
    with_error_translation { @client.script_flush(mode) }
  end

  def script_kill
    with_error_translation { @client.script_kill }
  end

  # Delegate HyperLogLog commands
  def pfadd(key, *elements)
    result = with_error_translation { @client.pfadd(key, *elements) }
    result == 1
  end

  def pfcount(*keys)
    with_error_translation { @client.pfcount(*keys) }
  end

  def pfmerge(destination, *sources)
    with_error_translation { @client.pfmerge(destination, *sources) }
  end

  # Delegate Geo commands
  def geoadd(key, *args, nx: false, xx: false, ch: false)
    with_error_translation { @client.geoadd(key, *args, nx: nx, xx: xx, ch: ch) }
  end

  def geopos(key, *members)
    with_error_translation { @client.geopos(key, *members) }
  end

  def geodist(key, member1, member2, unit: nil)
    with_error_translation { @client.geodist(key, member1, member2, unit: unit) }
  end

  def geohash(key, *members)
    with_error_translation { @client.geohash(key, *members) }
  end

  def geosearch(key, **options)
    with_error_translation { @client.geosearch(key, **options) }
  end

  def geosearchstore(destination, source, **options)
    with_error_translation { @client.geosearchstore(destination, source, **options) }
  end

  # Delegate bitmap commands
  def setbit(key, offset, value)
    with_error_translation { @client.setbit(key, offset, value) }
  end

  def getbit(key, offset)
    with_error_translation { @client.getbit(key, offset) }
  end

  def bitcount(key, start_pos = nil, end_pos = nil, scale: nil)
    # redis-rb uses :scale keyword, redis-ruby uses positional mode argument
    mode = scale&.to_s&.upcase
    with_error_translation { @client.bitcount(key, start_pos, end_pos, mode) }
  end

  def bitpos(key, bit, start_pos = nil, end_pos = nil, scale: nil)
    # redis-rb uses :scale keyword, redis-ruby uses positional mode argument
    mode = scale&.to_s&.upcase
    with_error_translation { @client.bitpos(key, bit, start_pos, end_pos, mode) }
  end

  def bitop(operation, destkey, *keys)
    keys = keys.flatten
    with_error_translation { @client.bitop(operation, destkey, *keys) }
  end

  def bitfield(key, *args)
    with_error_translation { @client.bitfield(key, *args) }
  end

  def bitfield_ro(key, *args)
    with_error_translation { @client.bitfield_ro(key, *args) }
  end

  # Server commands
  def info(section = nil)
    result = with_error_translation { @client.info(section) }
    parse_info(result)
  end

  def dbsize
    with_error_translation { @client.dbsize }
  end

  def flushdb(async: false)
    with_error_translation { @client.flushdb(async: async) }
  end

  def flushall(async: false)
    with_error_translation { @client.flushall(async: async) }
  end

  def save
    with_error_translation { @client.save }
  end

  def bgsave
    with_error_translation { @client.bgsave }
  end

  def bgrewriteaof
    with_error_translation { @client.bgrewriteaof }
  end

  def lastsave
    with_error_translation { @client.lastsave }
  end

  def time
    with_error_translation { @client.time }
  end

  def config(action, *args)
    case action.to_s.downcase
    when "get"
      config_get(*args)
    when "set"
      config_set(*args)
    when "rewrite"
      config_rewrite
    when "resetstat"
      config_resetstat
    else
      with_error_translation { @client.call("CONFIG", action.to_s.upcase, *args) }
    end
  end

  def config_get(parameter)
    result = with_error_translation { @client.config_get(parameter) }
    # Convert array to hash
    result.is_a?(Array) ? Hash[*result] : result
  end

  def config_set(parameter, value)
    with_error_translation { @client.config_set(parameter, value) }
  end

  def config_rewrite
    with_error_translation { @client.config_rewrite }
  end

  def config_resetstat
    with_error_translation { @client.config_resetstat }
  end

  def client_list
    with_error_translation { @client.client_list }
  end

  def client_getname
    with_error_translation { @client.client_getname }
  end

  def client_setname(name)
    with_error_translation { @client.client_setname(name) }
  end

  def client_kill(**filters)
    with_error_translation { @client.client_kill(**filters) }
  end

  def debug_object(key)
    with_error_translation { @client.debug_object(key) }
  end

  def slowlog(subcommand, *args)
    with_error_translation { @client.slowlog(subcommand, *args) }
  end

  private

  # Normalize redis-rb options to redis-ruby options
  def normalize_options(options)
    opts = DEFAULT_OPTIONS.dup.merge(options)
    parse_url_if_provided(opts)
    normalize_timeout_options(opts)
    opts.delete(:driver) # driver option is ignored (we always use pure Ruby)
    opts
  end

  # Parse URL into host/port/db/auth options
  def parse_url_if_provided(opts)
    return unless opts[:url]

    uri = URI.parse(opts[:url])
    case uri.scheme
    when "redis", "rediss"
      parse_redis_url(uri, opts)
    when "unix"
      opts[:path] = uri.path
    end
  end

  # Parse redis:// or rediss:// URL
  def parse_redis_url(uri, opts)
    opts[:host] = uri.host if uri.host
    opts[:port] = uri.port if uri.port
    parse_url_db(uri, opts)
    opts[:password] = uri.password if uri.password
    parse_url_username(uri, opts)
    opts[:ssl] = (uri.scheme == "rediss")
  end

  # Extract database number from URL path
  def parse_url_db(uri, opts)
    return unless uri.path && !uri.path.empty? && uri.path != "/"

    opts[:db] = uri.path.delete_prefix("/").to_i
  end

  # Extract username from URL (if distinct from password)
  def parse_url_username(uri, opts)
    return unless uri.user && uri.user != "" && uri.user != uri.password

    opts[:username] = uri.user
  end

  # Normalize various timeout option aliases
  def normalize_timeout_options(opts)
    # Handle connect_timeout as alias for timeout
    opts[:timeout] = opts.delete(:connect_timeout) if opts.key?(:connect_timeout)

    # read_timeout and write_timeout are not yet supported, use timeout
    opts[:timeout] ||= opts.delete(:read_timeout) if opts.key?(:read_timeout)
    opts[:timeout] ||= opts.delete(:write_timeout) if opts.key?(:write_timeout)
  end

  # Create the underlying client
  def create_client
    # Handle Sentinel configuration
    return create_sentinel_client if @options[:sentinels] && @options[:name]

    # Create standard client
    ::RR::Client.new(
      url: @options[:url],
      host: @options[:host],
      port: @options[:port],
      path: @options[:path],
      db: @options[:db],
      password: @options[:password],
      username: @options[:username],
      timeout: @options[:timeout],
      ssl: @options[:ssl],
      ssl_params: @options[:ssl_params] || {},
      reconnect_attempts: @options[:reconnect_attempts] || 0
    )
  end

  # Create a Sentinel client
  def create_sentinel_client
    sentinels = @options[:sentinels].map do |s|
      { host: s[:host], port: s[:port] }
    end

    ::RR.sentinel(
      sentinels: sentinels,
      service_name: @options[:name],
      role: @options[:role] || :master,
      password: @options[:password],
      username: @options[:username],
      timeout: @options[:timeout]
    )
  end

  # Get the underlying connection (for pipeline)
  def get_connection # rubocop:disable Naming/AccessorMethodName
    @client.send(:ensure_connected)
    @client.instance_variable_get(:@connection)
  end

  # Translate errors from RedisRuby to Redis
  def with_error_translation
    yield
  rescue ::RR::Error => e
    raise ErrorTranslation.translate(e)
  end

  # Parse INFO command output into a hash
  #
  # @param info_string [String] raw INFO output
  # @return [Hash] parsed info
  def parse_info(info_string)
    result = {}
    info_string.each_line do |line|
      line = line.chomp
      next if line.empty? || line.start_with?("#")

      key, value = line.split(":", 2)
      next unless key && value

      result[key] = value
    end
    result
  end
end
