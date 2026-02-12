# frozen_string_literal: true

require_relative "../dsl/string_proxy"
require_relative "../dsl/counter_proxy"

module RedisRuby
  module Commands
    # String commands
    #
    # @see https://redis.io/commands/?group=string
    module Strings
      # Frozen command constants to avoid string allocations
      CMD_SET = "SET"
      CMD_GET = "GET"
      CMD_INCR = "INCR"
      CMD_DECR = "DECR"
      CMD_INCRBY = "INCRBY"
      CMD_DECRBY = "DECRBY"
      CMD_INCRBYFLOAT = "INCRBYFLOAT"
      CMD_APPEND = "APPEND"
      CMD_STRLEN = "STRLEN"
      CMD_GETRANGE = "GETRANGE"
      CMD_SETRANGE = "SETRANGE"
      CMD_MGET = "MGET"
      CMD_MSET = "MSET"
      CMD_MSETNX = "MSETNX"
      CMD_SETNX = "SETNX"
      CMD_SETEX = "SETEX"
      CMD_PSETEX = "PSETEX"
      CMD_GETSET = "GETSET"
      CMD_GETDEL = "GETDEL"
      CMD_GETEX = "GETEX"

      # Frozen option strings
      OPT_EX = "EX"
      OPT_PX = "PX"
      OPT_EXAT = "EXAT"
      OPT_PXAT = "PXAT"
      OPT_NX = "NX"
      OPT_XX = "XX"
      OPT_KEEPTTL = "KEEPTTL"
      OPT_GET = "GET"
      OPT_PERSIST = "PERSIST"

      # ============================================================
      # Idiomatic Ruby API
      # ============================================================

      # Create a string proxy for idiomatic string operations
      #
      # Provides a fluent, Ruby-esque interface for working with Redis strings.
      # Supports composite keys with automatic ":" joining.
      # Optimized for configuration, caching, and text storage use cases.
      #
      # @param key_parts [Array<String, Symbol, Integer>] Key components
      # @return [RedisRuby::DSL::StringProxy] String proxy instance
      #
      # @example Basic usage
      #   api_key = redis.string(:config, :api_key)
      #   api_key.set("sk_live_123456")
      #   puts api_key.get()
      #
      # @example Chainable operations
      #   redis.string(:cache, :user, 123)
      #     .set(user_data.to_json)
      #     .expire(3600)
      #
      # @example Text operations
      #   log = redis.string(:log, :app)
      #   log.append(" new entry")
      def string(*key_parts)
        DSL::StringProxy.new(self, *key_parts)
      end

      # Create a counter proxy for idiomatic counter operations
      #
      # Provides a fluent, Ruby-esque interface for working with Redis counters.
      # Supports composite keys with automatic ":" joining.
      # Optimized for rate limiting, distributed counters, and metrics.
      #
      # @param key_parts [Array<String, Symbol, Integer>] Key components
      # @return [RedisRuby::DSL::CounterProxy] Counter proxy instance
      #
      # @example Page view counter
      #   views = redis.counter(:page, :views, 123)
      #   views.increment()
      #   puts "Total views: #{views.get()}"
      #
      # @example Rate limiting
      #   limit = redis.counter(:rate_limit, :api, user_id)
      #   limit.increment().expire(60)
      #   raise "Rate limit exceeded" if limit.get() > 100
      #
      # @example Distributed counter
      #   daily = redis.counter(:visits, :daily, Date.today.to_s)
      #   daily.increment().expire(86400 * 7)
      def counter(*key_parts)
        DSL::CounterProxy.new(self, *key_parts)
      end

      # ============================================================
      # Low-Level Commands
      # ============================================================

      # Set the value of a key with optional expiration and conditions
      #
      # @param key [String] The key
      # @param value [String] The value
      # @param ex [Integer, nil] Expiration in seconds
      # @param px [Integer, nil] Expiration in milliseconds
      # @param exat [Integer, nil] Absolute Unix timestamp in seconds (Redis 6.2+)
      # @param pxat [Integer, nil] Absolute Unix timestamp in milliseconds (Redis 6.2+)
      # @param nx [Boolean] Only set if key doesn't exist
      # @param xx [Boolean] Only set if key exists
      # @param keepttl [Boolean] Keep existing TTL (Redis 6.0+)
      # @param get [Boolean] Return old value (Redis 6.2+)
      # @return [String, nil] "OK" or nil (or old value if get: true)
      def set(key, value, ex: nil, px: nil, exat: nil, pxat: nil, nx: false, xx: false, keepttl: false, get: false)
        # Fast path: simple SET key value (most common case)
        return call_2args(CMD_SET, key, value) if set_simple?(ex, px, exat, pxat, nx, xx, keepttl, get)

        # Slow path: SET with options
        args = [key, value]
        append_set_expiration(args, ex: ex, px: px, exat: exat, pxat: pxat)
        append_set_flags(args, nx: nx, xx: xx, keepttl: keepttl, get: get)
        call(CMD_SET, *args)
      end

      # Get the value of a key
      #
      # @param key [String] The key
      # @return [String, nil] The value or nil
      def get(key)
        call_1arg(CMD_GET, key)
      end

      # Increment the integer value of a key by one
      #
      # @param key [String]
      # @return [Integer] value after increment
      def incr(key)
        call_1arg(CMD_INCR, key)
      end

      # Decrement the integer value of a key by one
      #
      # @param key [String]
      # @return [Integer] value after decrement
      def decr(key)
        call_1arg(CMD_DECR, key)
      end

      # Increment the integer value of a key by the given amount
      #
      # @param key [String]
      # @param increment [Integer]
      # @return [Integer] value after increment
      def incrby(key, increment)
        call_2args(CMD_INCRBY, key, increment)
      end

      # Decrement the integer value of a key by the given amount
      #
      # @param key [String]
      # @param decrement [Integer]
      # @return [Integer] value after decrement
      def decrby(key, decrement)
        call_2args(CMD_DECRBY, key, decrement)
      end

      # Increment the float value of a key by the given amount
      #
      # @param key [String]
      # @param increment [Float]
      # @return [Float] value after increment
      def incrbyfloat(key, increment)
        result = call_2args(CMD_INCRBYFLOAT, key, increment)
        result.is_a?(String) ? Float(result) : result
      end

      # Append a value to a key
      #
      # @param key [String]
      # @param value [String]
      # @return [Integer] length of string after append
      def append(key, value)
        call_2args(CMD_APPEND, key, value)
      end

      # Get the length of the value stored at key
      #
      # @param key [String]
      # @return [Integer] length of string, or 0 if key doesn't exist
      def strlen(key)
        call_1arg(CMD_STRLEN, key)
      end

      # Get a substring of the string stored at key
      #
      # @param key [String]
      # @param start_pos [Integer] start index (0-based, negative for end-relative)
      # @param end_pos [Integer] end index (inclusive)
      # @return [String] substring
      def getrange(key, start_pos, end_pos)
        call_3args(CMD_GETRANGE, key, start_pos, end_pos)
      end

      # Overwrite part of a string at key starting at the specified offset
      #
      # @param key [String]
      # @param offset [Integer]
      # @param value [String]
      # @return [Integer] length of string after modification
      def setrange(key, offset, value)
        call_3args(CMD_SETRANGE, key, offset, value)
      end

      # Get the values of multiple keys
      #
      # @param keys [Array<String>]
      # @return [Array<String, nil>] values (nil for missing keys)
      def mget(*keys)
        call(CMD_MGET, *keys)
      end

      # Set multiple keys to multiple values
      #
      # @param key_value_pairs [Array] key-value pairs (key1, value1, key2, value2, ...)
      # @return [String] "OK"
      def mset(*key_value_pairs)
        call(CMD_MSET, *key_value_pairs)
      end

      # Set multiple keys to multiple values, only if none of the keys exist
      #
      # @param key_value_pairs [Array] key-value pairs
      # @return [Integer] 1 if all keys were set, 0 if no keys were set
      def msetnx(*key_value_pairs)
        call(CMD_MSETNX, *key_value_pairs)
      end

      # Set the value of a key, only if the key does not exist
      #
      # @param key [String]
      # @param value [String]
      # @return [Boolean] true if key was set, false if key already existed
      def setnx(key, value)
        call(CMD_SETNX, key, value) == 1
      end

      # Set the value and expiration of a key (seconds)
      #
      # @param key [String]
      # @param seconds [Integer] TTL in seconds
      # @param value [String]
      # @return [String] "OK"
      def setex(key, seconds, value)
        call(CMD_SETEX, key, seconds, value)
      end

      # Set the value and expiration of a key (milliseconds)
      #
      # @param key [String]
      # @param milliseconds [Integer] TTL in milliseconds
      # @param value [String]
      # @return [String] "OK"
      def psetex(key, milliseconds, value)
        call(CMD_PSETEX, key, milliseconds, value)
      end

      # Set the value of a key and return its old value
      #
      # @param key [String]
      # @param value [String]
      # @return [String, nil] old value, or nil if key didn't exist
      def getset(key, value)
        call(CMD_GETSET, key, value)
      end

      # Get the value of a key and delete it
      #
      # @param key [String]
      # @return [String, nil] value, or nil if key didn't exist
      def getdel(key)
        call(CMD_GETDEL, key)
      end

      # Get the value of a key and optionally set its expiration
      #
      # @param key [String]
      # @param ex [Integer, nil] expiration in seconds
      # @param px [Integer, nil] expiration in milliseconds
      # @param exat [Integer, nil] absolute Unix timestamp in seconds
      # @param pxat [Integer, nil] absolute Unix timestamp in milliseconds
      # @param persist [Boolean] remove TTL
      # @return [String, nil] value
      def getex(key, ex: nil, px: nil, exat: nil, pxat: nil, persist: false)
        args = [CMD_GETEX, key]
        args.push(OPT_EX, ex) if ex
        args.push(OPT_PX, px) if px
        args.push(OPT_EXAT, exat) if exat
        args.push(OPT_PXAT, pxat) if pxat
        args.push(OPT_PERSIST) if persist
        call(*args)
      end

      private

      def set_simple?(ex, px, exat, pxat, nx, xx, keepttl, get)
        no_expiration?(ex, px, exat, pxat) && !nx && !xx && !keepttl && !get
      end

      def no_expiration?(ex, px, exat, pxat)
        ex.nil? && px.nil? && exat.nil? && pxat.nil?
      end

      def append_set_expiration(args, ex:, px:, exat:, pxat:)
        args.push(OPT_EX, ex) if ex
        args.push(OPT_PX, px) if px
        args.push(OPT_EXAT, exat) if exat
        args.push(OPT_PXAT, pxat) if pxat
      end

      def append_set_flags(args, nx:, xx:, keepttl:, get:)
        args.push(OPT_NX) if nx
        args.push(OPT_XX) if xx
        args.push(OPT_KEEPTTL) if keepttl
        args.push(OPT_GET) if get
      end
    end
  end
end
