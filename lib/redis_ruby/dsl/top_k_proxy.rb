# frozen_string_literal: true

module RR
  module DSL
    # Chainable proxy for Redis Top-K operations
    #
    # Provides a fluent, idiomatic Ruby API for working with Redis Top-K,
    # a probabilistic data structure for tracking the top K most frequent items.
    #
    # Top-K provides:
    # - Track top K items in a stream with constant memory
    # - Approximate frequency counts
    # - Heavy hitter detection
    # - Automatic eviction of less frequent items
    #
    # @example Trending products
    #   trending = redis.top_k(:trending, :products)
    #   trending.reserve(k: 10)
    #   trending.add("product:123", "product:456")
    #   trending.list  # => ["product:123", "product:456", ...]
    #
    # @example Popular items with counts
    #   popular = redis.top_k(:popular, :items)
    #   popular.reserve(k: 5, width: 1000, depth: 5, decay: 0.9)
    #   popular.increment_by("item:1", 10)
    #   popular.list(with_counts: true)  # => [["item:1", 10], ...]
    #
    class TopKProxy
      attr_reader :key

      # @private
      def initialize(redis, *key_parts)
        @redis = redis
        @key = key_parts.map(&:to_s).join(":")
      end

      # Reserve a new Top-K data structure
      #
      # @param k [Integer] Number of top items to keep
      # @param width [Integer, nil] Width of count array
      # @param depth [Integer, nil] Depth of count array
      # @param decay [Float, nil] Decay rate (0 to 1, e.g., 0.9 = 10% decay)
      # @return [self] For method chaining
      #
      # @example
      #   topk.reserve(k: 10)
      #   topk.reserve(k: 100, width: 1000, depth: 5, decay: 0.9)
      def reserve(k:, width: nil, depth: nil, decay: nil)
        @redis.topk_reserve(@key, k, width: width, depth: depth, decay: decay)
        self
      end

      # Add one or more items to Top-K
      #
      # Returns items that were dropped out of the top-K list.
      #
      # @param items [Array<String, Symbol, Integer>] Items to add
      # @return [Array] Items that were dropped (may be empty or contain nils)
      #
      # @example
      #   dropped = topk.add("item1")
      #   dropped = topk.add("item2", "item3")  # => [nil, "old_item"]
      def add(*items)
        return [] if items.empty?
        
        @redis.topk_add(@key, *items.map(&:to_s))
      end

      # Increment count for an item by a specific amount
      #
      # @param item [String, Symbol, Integer] Item to increment
      # @param by [Integer] Amount to increment
      # @return [self] For method chaining
      #
      # @example
      #   topk.increment_by("item1", 5)
      #   topk.increment_by("item2", 10)
      def increment_by(item, by)
        @redis.topk_incrby(@key, item.to_s, by)
        self
      end

      # Check if one or more items are in the top-K
      #
      # @param items [Array<String, Symbol, Integer>] Items to check
      # @return [Boolean, Array<Boolean>] Single boolean for one item, array for multiple
      #
      # @example
      #   topk.query("item1")  # => true
      #   topk.query("item1", "item2")  # => [true, false]
      def query(*items)
        return false if items.empty?
        
        result = @redis.topk_query(@key, *items.map(&:to_s)).map { |r| r == 1 }
        items.size == 1 ? result.first : result
      end

      # Get estimated count for one or more items
      #
      # @param items [Array<String, Symbol, Integer>] Items to count
      # @return [Integer, Array<Integer>] Single count for one item, array for multiple
      #
      # @example
      #   topk.count("item1")  # => 15
      #   topk.count("item1", "item2")  # => [15, 8]
      def count(*items)
        return 0 if items.empty?
        
        result = @redis.topk_count(@key, *items.map(&:to_s))
        items.size == 1 ? result.first : result
      end

      # List the top K items
      #
      # @param with_counts [Boolean] Include counts with items
      # @return [Array] Top K items, optionally with counts
      #
      # @example
      #   topk.list  # => ["item1", "item2", "item3"]
      #   topk.list(with_counts: true)  # => [["item1", 15], ["item2", 8], ...]
      def list(with_counts: false)
        result = @redis.topk_list(@key, withcount: with_counts)
        
        if with_counts
          # Result is flat array: [item1, count1, item2, count2, ...]
          # Convert to nested array: [[item1, count1], [item2, count2], ...]
          result.each_slice(2).to_a
        else
          result
        end
      end

      # Get Top-K information
      #
      # @return [Hash] Top-K information including k, width, depth, decay
      #
      # @example
      #   info = topk.info
      #   puts "K: #{info['k']}"
      #   puts "Width: #{info['width']}"
      #   puts "Depth: #{info['depth']}"
      def info
        @redis.topk_info(@key)
      end

      # Check if the Top-K key exists
      #
      # @return [Boolean] true if key exists, false otherwise
      #
      # @example
      #   topk.key_exists?  # => true
      def key_exists?
        @redis.exists(@key) > 0
      end

      # Delete the Top-K
      #
      # @return [Integer] Number of keys deleted (0 or 1)
      #
      # @example
      #   topk.delete
      def delete
        @redis.del(@key)
      end

      # Alias for delete
      alias clear delete

      # Set expiration time in seconds
      #
      # @param seconds [Integer] Seconds until expiration
      # @return [self] For method chaining
      #
      # @example
      #   topk.expire(3600)  # Expire in 1 hour
      def expire(seconds)
        @redis.expire(@key, seconds)
        self
      end

      # Set expiration time at a specific timestamp
      #
      # @param timestamp [Integer, Time] Unix timestamp or Time object
      # @return [self] For method chaining
      #
      # @example
      #   topk.expire_at(Time.now + 3600)
      def expire_at(timestamp)
        timestamp = timestamp.to_i if timestamp.is_a?(Time)
        @redis.expireat(@key, timestamp)
        self
      end

      # Get time-to-live in seconds
      #
      # @return [Integer] Seconds until expiration (-1 if no expiration, -2 if key doesn't exist)
      #
      # @example
      #   topk.ttl  # => 3599
      def ttl
        @redis.ttl(@key)
      end

      # Remove expiration from the Top-K
      #
      # @return [self] For method chaining
      #
      # @example
      #   topk.persist
      def persist
        @redis.persist(@key)
        self
      end
    end
  end
end

