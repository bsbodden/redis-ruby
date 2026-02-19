# frozen_string_literal: true

require_relative "expirable"

module RR
  module DSL
    # Chainable proxy for Redis Bloom Filter operations
    #
    # Provides a fluent, idiomatic Ruby API for working with Redis Bloom Filters,
    # a probabilistic data structure for space-efficient membership testing.
    #
    # Bloom Filters can test if an element may exist in a set with:
    # - False positives possible (may say "yes" when answer is "no")
    # - False negatives impossible (if it says "no", definitely not in set)
    # - Extremely memory efficient (~10 bits per element at 1% error rate)
    #
    # @example Spam detection
    #   spam = redis.bloom_filter(:spam, :emails)
    #   spam.reserve(error_rate: 0.01, capacity: 100_000)
    #   spam.add("spam@example.com", "bad@example.com")
    #   spam.exists?("spam@example.com")  # => true (probably exists)
    #   spam.exists?("unknown@example.com")  # => false (definitely not)
    #
    # @example Duplicate detection
    #   seen = redis.bloom_filter(:processed, :urls)
    #   seen.reserve(error_rate: 0.001, capacity: 1_000_000)
    #   seen.add(url) unless seen.exists?(url)
    #
    class BloomFilterProxy
      include Expirable

      attr_reader :key

      # @private
      def initialize(redis, *key_parts)
        @redis = redis
        @key = key_parts.map(&:to_s).join(":")
      end

      # Reserve a new Bloom Filter with specified error rate and capacity
      #
      # @param error_rate [Float] Desired false positive rate (0 to 1, e.g., 0.01 = 1%)
      # @param capacity [Integer] Expected number of items
      # @param expansion [Integer, nil] Expansion factor when filter is full
      # @param nonscaling [Boolean] Don't allow filter to scale
      # @return [self] For method chaining
      #
      # @example
      #   filter.reserve(error_rate: 0.01, capacity: 10_000)
      #   filter.reserve(error_rate: 0.001, capacity: 1_000_000, expansion: 2)
      def reserve(error_rate:, capacity:, expansion: nil, nonscaling: false)
        @redis.bf_reserve(@key, error_rate, capacity, expansion: expansion, nonscaling: nonscaling)
        self
      end

      # Add one or more items to the Bloom Filter
      #
      # @param items [Array<String, Symbol, Integer>] Items to add
      # @return [self] For method chaining
      #
      # @example
      #   filter.add("item1")
      #   filter.add("item2", "item3", "item4")
      def add(*items)
        return self if items.empty?

        if items.size == 1
          @redis.bf_add(@key, items.first.to_s)
        else
          @redis.bf_madd(@key, *items.map(&:to_s))
        end
        self
      end

      # Check if one or more items may exist in the Bloom Filter
      #
      # @param items [Array<String, Symbol, Integer>] Items to check
      # @return [Boolean, Array<Boolean>] Single boolean for one item, array for multiple
      #
      # @example
      #   filter.exists?("item1")  # => true (may exist)
      #   filter.exists?("item1", "item2")  # => [true, false]
      def exists?(*items)
        return false if items.empty?

        if items.size == 1
          @redis.bf_exists(@key, items.first.to_s) == 1
        else
          @redis.bf_mexists(@key, *items.map(&:to_s)).map { |r| r == 1 }
        end
      end

      # Get Bloom Filter information
      #
      # @return [Hash] Filter information including capacity, size, number of filters, etc.
      #
      # @example
      #   info = filter.info
      #   puts "Capacity: #{info['Capacity']}"
      #   puts "Size: #{info['Size']}"
      def info
        @redis.bf_info(@key)
      end

      # Get estimated cardinality (number of items added)
      #
      # @return [Integer] Approximate number of items in the filter
      #
      # @example
      #   filter.cardinality  # => 1523
      def cardinality
        @redis.bf_card(@key)
      end
      alias card cardinality
      alias count cardinality

      # Check if the Bloom Filter key exists
      #
      # @return [Boolean] true if key exists, false otherwise
      #
      # @example
      #   filter.key_exists?  # => true
      def key_exists?
        @redis.exists(@key).positive?
      end

      # Delete the Bloom Filter
      #
      # @return [Integer] Number of keys deleted (0 or 1)
      #
      # @example
      #   filter.delete
      def delete
        @redis.del(@key)
      end

      # Alias for delete
      alias clear delete
    end
  end
end
