# frozen_string_literal: true

require_relative "expirable"

module RR
  module DSL
    # Chainable proxy for Redis Counter operations
    #
    # Provides a fluent, idiomatic Ruby API for working with Redis counters,
    # optimized for rate limiting, distributed counters, and metrics.
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
    #   daily_visits = redis.counter(:visits, :daily, Date.today.to_s)
    #   daily_visits.increment().expire(86400 * 7)
    #
    class CounterProxy
      include Expirable

      attr_reader :key

      # @private
      def initialize(redis, *key_parts)
        @redis = redis
        @key = key_parts.map(&:to_s).join(":")
      end

      # Get the counter value as an integer
      #
      # @return [Integer, nil] The value or nil if key doesn't exist
      #
      # @example
      #   counter.get()  # => 42
      def get
        val = @redis.get(@key)
        val.nil? ? nil : val.to_i
      end
      alias value get
      alias to_i get

      # Set the counter value
      #
      # @param val [Integer] Value to set
      # @return [self] For method chaining
      #
      # @example
      #   counter.set(100)
      def set(val)
        @redis.set(@key, val.to_i)
        self
      end

      # Set the counter value (assignment syntax)
      #
      # @param val [Integer] Value to set
      # @return [Integer] The value that was set
      #
      # @example
      #   counter.value = 100
      def value=(val)
        @redis.set(@key, val.to_i)
        val
      end

      # Increment the counter
      #
      # @param by [Integer] Amount to increment (default: 1)
      # @return [self] For method chaining
      #
      # @example
      #   counter.increment()      # Increment by 1
      #   counter.increment(10)    # Increment by 10
      def increment(by = 1)
        if by == 1
          @redis.incr(@key)
        else
          @redis.incrby(@key, by)
        end
        self
      end
      alias incr increment

      # Decrement the counter
      #
      # @param by [Integer] Amount to decrement (default: 1)
      # @return [self] For method chaining
      #
      # @example
      #   counter.decrement()      # Decrement by 1
      #   counter.decrement(5)     # Decrement by 5
      def decrement(by = 1)
        if by == 1
          @redis.decr(@key)
        else
          @redis.decrby(@key, by)
        end
        self
      end
      alias decr decrement

      # Increment the counter by a float value
      #
      # @param by [Float] Amount to increment
      # @return [self] For method chaining
      #
      # @example
      #   counter.increment_float(1.5)
      def increment_float(by)
        @redis.incrbyfloat(@key, by)
        self
      end
      alias incrbyfloat increment_float

      # Set the value only if the key does not exist
      #
      # @param val [Integer] Value to set
      # @return [Boolean] true if key was set, false if key already existed
      #
      # @example
      #   counter.setnx(0)  # => true
      def setnx(val)
        @redis.setnx(@key, val.to_i)
      end

      # Set the value and return the old value atomically
      #
      # @param val [Integer] New value to set
      # @return [Integer, nil] Old value or nil if key didn't exist
      #
      # @example
      #   old_value = counter.getset(100)
      def getset(val)
        old_val = @redis.getset(@key, val.to_i)
        old_val.nil? ? nil : old_val.to_i
      end

      # Check if the key exists
      #
      # @return [Boolean] true if key exists
      #
      # @example
      #   counter.exists?()  # => true
      def exists?
        @redis.exists(@key) > 0
      end

      # Check if the counter value is zero or doesn't exist
      #
      # @return [Boolean] true if value is 0 or nil
      #
      # @example
      #   counter.zero?()  # => false
      def zero?
        val = get
        val.nil? || val == 0
      end

      # Delete the key
      #
      # @return [Integer] Number of keys deleted (0 or 1)
      #
      # @example
      #   counter.delete()
      def delete
        @redis.del(@key)
      end
      alias clear delete
    end
  end
end


