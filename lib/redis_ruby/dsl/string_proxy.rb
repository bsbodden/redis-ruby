# frozen_string_literal: true

require_relative "expirable"

module RR
  module DSL
    # Chainable proxy for Redis String operations
    #
    # Provides a fluent, idiomatic Ruby API for working with Redis strings,
    # optimized for configuration, caching, and text storage use cases.
    #
    # @example Configuration storage
    #   api_key = redis.string(:config, :api_key)
    #   api_key.set("sk_live_123456").expire(86400)
    #   puts api_key.get()
    #
    # @example Caching
    #   cache = redis.string(:cache, :user, 123)
    #   cache.set(user_data.to_json).expire(3600)
    #   cached = cache.get()
    #
    # @example Text operations
    #   log = redis.string(:log, :app)
    #   log.set("Starting...").append(" initialized").append(" ready")
    #
    class StringProxy
      include Expirable

      attr_reader :key

      # @private
      def initialize(redis, *key_parts)
        @redis = redis
        @key = key_parts.map(&:to_s).join(":")
      end

      # Get the string value
      #
      # @return [String, nil] The value or nil if key doesn't exist
      #
      # @example
      #   str.get()  # => "hello world"
      def get
        @redis.get(@key)
      end
      alias value get

      # Set the string value
      #
      # @param val [String, Integer, Float] Value to set
      # @return [self] For method chaining
      #
      # @example
      #   str.set("hello world")
      def set(val)
        @redis.set(@key, val.to_s)
        self
      end

      # Set the string value (assignment syntax)
      #
      # @param val [String, Integer, Float] Value to set
      # @return [String] The value that was set
      #
      # @example
      #   str.value = "hello"
      def value=(val)
        @redis.set(@key, val.to_s)
      end

      # Append a value to the string
      #
      # @param val [String] Value to append
      # @return [self] For method chaining
      #
      # @example
      #   str.append(" world")
      def append(val)
        @redis.append(@key, val.to_s)
        self
      end

      # Get the length of the string
      #
      # @return [Integer] Length of the string, or 0 if key doesn't exist
      #
      # @example
      #   str.length()  # => 11
      def length
        @redis.strlen(@key)
      end
      alias size length

      # Get a substring of the string
      #
      # @param start_pos [Integer] Start index (0-based, negative for end-relative)
      # @param end_pos [Integer] End index (inclusive)
      # @return [String] Substring
      #
      # @example
      #   str.getrange(0, 4)    # => "hello"
      #   str.getrange(-5, -1)  # => "world"
      def getrange(start_pos, end_pos)
        @redis.getrange(@key, start_pos, end_pos)
      end

      # Overwrite part of the string at the specified offset
      #
      # @param offset [Integer] Offset to start writing
      # @param val [String] Value to write
      # @return [self] For method chaining
      #
      # @example
      #   str.setrange(6, "Redis")
      def setrange(offset, val)
        @redis.setrange(@key, offset, val.to_s)
        self
      end

      # Check if the key exists
      #
      # @return [Boolean] true if key exists
      #
      # @example
      #   str.exists?()  # => true
      def exists?
        @redis.exists(@key).positive?
      end

      # Check if the string is empty or doesn't exist
      #
      # @return [Boolean] true if value is nil or empty string
      #
      # @example
      #   str.empty?()  # => false
      def empty?
        val = get
        val.nil? || val.empty?
      end

      # Set the value only if the key does not exist
      #
      # @param val [String] Value to set
      # @return [Boolean] true if key was set, false if key already existed
      #
      # @example
      #   str.setnx("value")  # => true
      def setnx(val)
        @redis.setnx(@key, val.to_s)
      end

      # Set the value and expiration in seconds
      #
      # @param seconds [Integer] TTL in seconds
      # @param val [String] Value to set
      # @return [self] For method chaining
      #
      # @example
      #   str.setex(60, "temp_value")
      def setex(seconds, val)
        @redis.setex(@key, seconds, val.to_s)
        self
      end

      # Fetch with fallback block (cache-friendly)
      #
      # Returns cached/stored value if it exists, or executes the block
      # to compute and store the value. Works transparently with
      # client-side caching when enabled.
      #
      # @param force [Boolean] Force re-computation even if value exists
      # @yield Block to compute value if not found
      # @return [Object] The value
      #
      # @example
      #   str.fetch { expensive_compute() }
      #   str.fetch(force: true) { recomputed_value() }
      def fetch(force: false, &block)
        unless force
          val = get
          return val unless val.nil?
        end

        return nil unless block

        val = yield
        set(val)
        val
      end

      # Delete the key
      #
      # @return [Integer] Number of keys deleted (0 or 1)
      #
      # @example
      #   str.delete()
      def delete
        @redis.del(@key)
      end
      alias clear delete
    end
  end
end
