# frozen_string_literal: true

require_relative "expirable"

module RR
  module DSL
    # Chainable proxy for Redis HyperLogLog operations
    #
    # Provides a fluent, idiomatic Ruby API for working with Redis HyperLogLog,
    # a probabilistic data structure for cardinality estimation.
    #
    # HyperLogLog uses ~12KB of memory regardless of the number of unique
    # elements, with a standard error of ~0.81%.
    #
    # @example Unique visitor counting
    #   visitors = redis.hll(:visitors, :today)
    #   visitors.add("user:123", "user:456", "user:789")
    #   puts "Unique visitors: #{visitors.count}"
    #
    # @example Merging daily counts into weekly
    #   weekly = redis.hll(:visitors, :weekly)
    #   weekly.merge("visitors:day1", "visitors:day2", "visitors:day3")
    #   puts "Weekly unique visitors: #{weekly.count}"
    #
    # @example A/B testing
    #   variant_a = redis.hll(:experiment, :variant_a)
    #   variant_a.add("user:1", "user:2", "user:3")
    #   puts "Variant A users: #{variant_a.count}"
    #
    class HyperLogLogProxy
      include Expirable

      attr_reader :key

      # @private
      def initialize(redis, *key_parts)
        @redis = redis
        @key = key_parts.map(&:to_s).join(":")
      end

      # Add one or more elements to the HyperLogLog
      #
      # @param elements [Array<String, Symbol, Integer>] Elements to add
      # @return [self] For method chaining
      #
      # @example
      #   hll.add("user:123")
      #   hll.add("user:456", "user:789", "user:101")
      def add(*elements)
        return self if elements.empty?
        @redis.pfadd(@key, *elements.map(&:to_s))
        self
      end

      # Get the approximate cardinality (number of unique elements)
      #
      # @return [Integer] Approximate count of unique elements
      #
      # @example
      #   hll.count  # => 1523
      def count
        @redis.pfcount(@key)
      end

      # Alias for count (Ruby-esque)
      alias size count
      alias length count

      # Merge other HyperLogLogs into this one
      #
      # The result is stored in the current key. This is useful for
      # aggregating counts from multiple sources.
      #
      # @param other_keys [Array<String, Symbol>] Keys of other HyperLogLogs to merge
      # @return [self] For method chaining
      #
      # @example Merge daily counts into weekly
      #   weekly.merge("visitors:day1", "visitors:day2", "visitors:day3")
      def merge(*other_keys)
        return self if other_keys.empty?
        @redis.pfmerge(@key, @key, *other_keys.map(&:to_s))
        self
      end

      # Merge this HyperLogLog and others into a destination key
      #
      # This is useful when you want to create a new merged HyperLogLog
      # without modifying the current one.
      #
      # @param destination_key [String, Symbol] Destination key for merged result
      # @param other_keys [Array<String, Symbol>] Additional keys to merge
      # @return [self] For method chaining
      #
      # @example Merge into a new key
      #   daily.merge_into("visitors:weekly", "visitors:day2", "visitors:day3")
      def merge_into(destination_key, *other_keys)
        @redis.pfmerge(destination_key.to_s, @key, *other_keys.map(&:to_s))
        self
      end

      # Delete the HyperLogLog
      #
      # @return [Integer] Number of keys deleted (0 or 1)
      #
      # @example
      #   hll.delete
      def delete
        @redis.del(@key)
      end

      # Alias for delete
      alias clear delete

      # Check if the HyperLogLog key exists
      #
      # @return [Boolean] true if key exists, false otherwise
      #
      # @example
      #   hll.exists?  # => true
      def exists?
        @redis.exists(@key) > 0
      end

      # Check if the HyperLogLog is empty
      #
      # A HyperLogLog is considered empty if it doesn't exist or has a count of 0.
      #
      # @return [Boolean] true if empty, false otherwise
      #
      # @example
      #   hll.empty?  # => false
      def empty?
        !exists? || count == 0
      end

    end
  end
end

