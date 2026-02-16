# frozen_string_literal: true

module RR
  module DSL
    # Chainable proxy for Redis Cuckoo Filter operations
    #
    # Provides a fluent, idiomatic Ruby API for working with Redis Cuckoo Filters,
    # a probabilistic data structure similar to Bloom Filters but with deletion support.
    #
    # Cuckoo Filters provide:
    # - Membership testing with false positives (like Bloom Filters)
    # - Deletion support (unlike Bloom Filters)
    # - Better lookup performance than Bloom Filters
    # - Approximate item counting
    #
    # @example Session tracking with cleanup
    #   sessions = redis.cuckoo_filter(:active, :sessions)
    #   sessions.reserve(capacity: 10_000)
    #   sessions.add("session:abc123")
    #   sessions.exists?("session:abc123")  # => true
    #   sessions.remove("session:abc123")   # Can delete!
    #
    # @example Cache admission control
    #   cache = redis.cuckoo_filter(:cache, :admitted)
    #   cache.reserve(capacity: 100_000, bucket_size: 4)
    #   cache.add_nx(key)  # Add only if not exists
    #
    class CuckooFilterProxy
      attr_reader :key

      # @private
      def initialize(redis, *key_parts)
        @redis = redis
        @key = key_parts.map(&:to_s).join(":")
      end

      # Reserve a new Cuckoo Filter with specified capacity
      #
      # @param capacity [Integer] Expected number of items
      # @param bucket_size [Integer, nil] Items per bucket (default 2)
      # @param max_iterations [Integer, nil] Max cuckoo kicks before failure
      # @param expansion [Integer, nil] Growth factor when filter is full
      # @return [self] For method chaining
      #
      # @example
      #   filter.reserve(capacity: 10_000)
      #   filter.reserve(capacity: 100_000, bucket_size: 4, max_iterations: 20)
      def reserve(capacity:, bucket_size: nil, max_iterations: nil, expansion: nil)
        @redis.cf_reserve(@key, capacity, bucketsize: bucket_size, maxiterations: max_iterations, expansion: expansion)
        self
      end

      # Add one or more items to the Cuckoo Filter
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
          @redis.cf_add(@key, items.first.to_s)
        else
          @redis.cf_insert(@key, *items.map(&:to_s))
        end
        self
      end

      # Add one or more items only if they don't exist
      #
      # @param items [Array<String, Symbol, Integer>] Items to add
      # @return [Boolean, Array<Boolean>] true if added, false if already exists
      #
      # @example
      #   filter.add_nx("item1")  # => true (added)
      #   filter.add_nx("item1")  # => false (already exists)
      def add_nx(*items)
        return false if items.empty?
        
        if items.size == 1
          @redis.cf_addnx(@key, items.first.to_s) == 1
        else
          @redis.cf_insertnx(@key, *items.map(&:to_s)).map { |r| r == 1 }
        end
      end

      # Check if one or more items may exist in the Cuckoo Filter
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
          @redis.cf_exists(@key, items.first.to_s) == 1
        else
          @redis.cf_mexists(@key, *items.map(&:to_s)).map { |r| r == 1 }
        end
      end

      # Remove one or more items from the Cuckoo Filter
      #
      # This is the key difference from Bloom Filters - Cuckoo Filters support deletion!
      #
      # @param items [Array<String, Symbol, Integer>] Items to remove
      # @return [self] For method chaining
      #
      # @example
      #   filter.remove("item1")
      #   filter.remove("item2", "item3")
      def remove(*items)
        return self if items.empty?
        
        items.each do |item|
          @redis.cf_del(@key, item.to_s)
        end
        self
      end
      alias delete_item remove

      # Get approximate count of an item in the filter
      #
      # @param item [String, Symbol, Integer] Item to count
      # @return [Integer] Estimated count
      #
      # @example
      #   filter.count("item1")  # => 2
      def count(item)
        @redis.cf_count(@key, item.to_s)
      end

      # Get Cuckoo Filter information
      #
      # @return [Hash] Filter information including size, buckets, filters, etc.
      #
      # @example
      #   info = filter.info
      #   puts "Size: #{info['Size']}"
      #   puts "Number of buckets: #{info['Number of buckets']}"
      def info
        @redis.cf_info(@key)
      end

      # Check if the Cuckoo Filter key exists
      #
      # @return [Boolean] true if key exists, false otherwise
      #
      # @example
      #   filter.key_exists?  # => true
      def key_exists?
        @redis.exists(@key) > 0
      end

      # Delete the Cuckoo Filter
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

      # Set expiration time in seconds
      #
      # @param seconds [Integer] Seconds until expiration
      # @return [self] For method chaining
      #
      # @example
      #   filter.expire(3600)  # Expire in 1 hour
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
      #   filter.expire_at(Time.now + 3600)
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
      #   filter.ttl  # => 3599
      def ttl
        @redis.ttl(@key)
      end

      # Remove expiration from the Cuckoo Filter
      #
      # @return [self] For method chaining
      #
      # @example
      #   filter.persist
      def persist
        @redis.persist(@key)
        self
      end
    end
  end
end

