# frozen_string_literal: true

require_relative "expirable"

module RR
  module DSL
    # Chainable proxy for Redis Count-Min Sketch operations
    #
    # Provides a fluent, idiomatic Ruby API for working with Redis Count-Min Sketch,
    # a probabilistic data structure for frequency estimation in streaming data.
    #
    # Count-Min Sketch provides:
    # - Frequency counting with over-estimation (never under-estimates)
    # - Constant memory usage regardless of stream size
    # - Mergeable sketches for distributed counting
    # - Heavy hitter detection
    #
    # @example Page view counting
    #   pageviews = redis.count_min_sketch(:pageviews)
    #   pageviews.init_by_prob(error_rate: 0.001, probability: 0.01)
    #   pageviews.increment("/home", "/about", "/contact")
    #   pageviews.query("/home")  # => 1
    #
    # @example Heavy hitter detection
    #   events = redis.count_min_sketch(:events)
    #   events.init_by_dim(width: 2000, depth: 5)
    #   events.increment_by("event:login", 100)
    #   events.query("event:login")  # => 100 (or slightly more)
    #
    class CountMinSketchProxy
      include Expirable

      attr_reader :key

      # @private
      def initialize(redis, *key_parts)
        @redis = redis
        @key = key_parts.map(&:to_s).join(":")
      end

      # Initialize Count-Min Sketch by dimensions
      #
      # @param width [Integer] Number of counters in each array
      # @param depth [Integer] Number of counter arrays
      # @return [self] For method chaining
      #
      # @example
      #   sketch.init_by_dim(width: 2000, depth: 5)
      def init_by_dim(width:, depth:)
        @redis.cms_initbydim(@key, width, depth)
        self
      end

      # Initialize Count-Min Sketch by error rate and probability
      #
      # @param error_rate [Float] Error rate (0 to 1, e.g., 0.001 = 0.1%)
      # @param probability [Float] Probability of error (0 to 1, e.g., 0.01 = 1%)
      # @return [self] For method chaining
      #
      # @example
      #   sketch.init_by_prob(error_rate: 0.001, probability: 0.01)
      def init_by_prob(error_rate:, probability:)
        @redis.cms_initbyprob(@key, error_rate, probability)
        self
      end

      # Increment count for one or more items by 1
      #
      # @param items [Array<String, Symbol, Integer>] Items to increment
      # @return [self] For method chaining
      #
      # @example
      #   sketch.increment("/home")
      #   sketch.increment("/about", "/contact")
      def increment(*items)
        return self if items.empty?

        # Build pairs of [item, 1] for each item
        pairs = items.flat_map { |item| [item.to_s, 1] }
        @redis.cms_incrby(@key, *pairs)
        self
      end

      # Increment count for an item by a specific amount
      #
      # @param item [String, Symbol, Integer] Item to increment
      # @param by [Integer] Amount to increment
      # @return [self] For method chaining
      #
      # @example
      #   sketch.increment_by("/home", 5)
      #   sketch.increment_by("/about", 10)
      def increment_by(item, by)
        @redis.cms_incrby(@key, item.to_s, by)
        self
      end

      # Query estimated count for one or more items
      #
      # @param items [Array<String, Symbol, Integer>] Items to query
      # @return [Integer, Array<Integer>] Single count for one item, array for multiple
      #
      # @example
      #   sketch.query("/home")  # => 15
      #   sketch.query("/home", "/about")  # => [15, 8]
      def query(*items)
        return 0 if items.empty?

        result = @redis.cms_query(@key, *items.map(&:to_s))
        items.size == 1 ? result.first : result
      end

      # Merge other Count-Min Sketches into this one
      #
      # All sketches must have the same dimensions.
      #
      # @param other_keys [Array<String, Symbol>] Keys of other sketches to merge
      # @return [self] For method chaining
      #
      # @example
      #   sketch.merge("pageviews:server1", "pageviews:server2")
      def merge(*other_keys)
        return self if other_keys.empty?

        @redis.cms_merge(@key, @key, *other_keys.map(&:to_s))
        self
      end

      # Merge this sketch and others into a destination key
      #
      # @param destination_key [String, Symbol] Destination key for merged result
      # @param other_keys [Array<String, Symbol>] Additional keys to merge
      # @return [self] For method chaining
      #
      # @example
      #   sketch.merge_into("pageviews:total", "pageviews:server2")
      def merge_into(destination_key, *other_keys)
        @redis.cms_merge(destination_key.to_s, @key, *other_keys.map(&:to_s))
        self
      end

      # Get Count-Min Sketch information
      #
      # @return [Hash] Sketch information including width, depth, count
      #
      # @example
      #   info = sketch.info
      #   puts "Width: #{info['width']}"
      #   puts "Depth: #{info['depth']}"
      #   puts "Count: #{info['count']}"
      def info
        @redis.cms_info(@key)
      end

      # Check if the Count-Min Sketch key exists
      #
      # @return [Boolean] true if key exists, false otherwise
      #
      # @example
      #   sketch.key_exists?  # => true
      def key_exists?
        @redis.exists(@key).positive?
      end

      # Delete the Count-Min Sketch
      #
      # @return [Integer] Number of keys deleted (0 or 1)
      #
      # @example
      #   sketch.delete
      def delete
        @redis.del(@key)
      end

      # Alias for delete
      alias clear delete
    end
  end
end
