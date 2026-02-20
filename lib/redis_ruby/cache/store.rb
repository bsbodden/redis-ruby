# frozen_string_literal: true

require "monitor"

module RR
  class Cache
    # Pluggable LRU+TTL cache store with IN_PROGRESS sentinel
    #
    # Thread-safe storage backend for client-side caching.
    # Uses LRU eviction and optional TTL expiration.
    #
    # The IN_PROGRESS sentinel prevents thundering herd when multiple
    # threads try to fetch the same uncached key simultaneously.
    #
    # @example
    #   store = Store.new(max_entries: 1000)
    #   store.set("GET:user:1", "value", ttl: 300)
    #   store.get("GET:user:1")  # => "value"
    #
    class Store
      # Sentinel value indicating a cache entry is being fetched
      IN_PROGRESS = :in_progress

      # Cache entry with value and expiration
      CacheEntry = Struct.new(:value, :expires_at) do
        def expired?
          expires_at && Process.clock_gettime(Process::CLOCK_MONOTONIC) > expires_at
        end
      end

      attr_reader :max_entries

      # @param max_entries [Integer] Maximum number of cached entries
      def initialize(max_entries: Cache::DEFAULT_MAX_ENTRIES)
        @max_entries = max_entries
        @cache = {}
        @access_order = {} # LRU tracking (Hash preserves insertion order)
        @monitor = Monitor.new
        @eviction_count = 0
      end

      # Get a cached value
      #
      # @param cache_key [String] The cache key
      # @return [Object, :in_progress, nil] The value, IN_PROGRESS, or nil
      def get(cache_key)
        @monitor.synchronize do
          entry = @cache[cache_key]
          return nil unless entry

          if entry.value == IN_PROGRESS
            return IN_PROGRESS
          end

          if entry.expired?
            delete_entry(cache_key)
            return nil
          end

          touch_lru(cache_key)
          entry.value
        end
      end

      # Store a value in the cache
      #
      # @param cache_key [String] The cache key
      # @param value [Object] The value to cache
      # @param ttl [Float, nil] TTL in seconds (nil = no expiry)
      # @return [Object] The stored value
      def set(cache_key, value, ttl: nil)
        @monitor.synchronize do
          evict_lru if @cache.size >= @max_entries && !@cache.key?(cache_key)

          expires_at = ttl ? Process.clock_gettime(Process::CLOCK_MONOTONIC) + ttl : nil
          @cache[cache_key] = CacheEntry.new(value, expires_at)
          touch_lru(cache_key)
          value
        end
      end

      # Mark a cache key as in-progress (prevents thundering herd)
      #
      # @param cache_key [String] The cache key
      def mark_in_progress(cache_key)
        @monitor.synchronize do
          @cache[cache_key] = CacheEntry.new(IN_PROGRESS, nil)
        end
      end

      # Delete a single cache key
      #
      # @param cache_key [String] The cache key
      # @return [Boolean] true if key existed
      def delete(cache_key)
        @monitor.synchronize do
          delete_entry(cache_key)
        end
      end

      # Delete all cache entries for a Redis key using the key builder's reverse index
      #
      # @param redis_key [String] The Redis key
      # @param key_builder [KeyBuilder] The key builder with reverse index
      # @return [Integer] Number of entries deleted
      def delete_by_redis_key(redis_key, key_builder)
        @monitor.synchronize do
          cache_keys = key_builder.remove_all_for(redis_key)
          count = 0
          cache_keys.each do |ck|
            if delete_entry(ck)
              count += 1
            end
          end
          count
        end
      end

      # Clear the entire store
      #
      # @return [Integer] Number of entries cleared
      def clear
        @monitor.synchronize do
          count = @cache.size
          @cache.clear
          @access_order.clear
          count
        end
      end

      # Current number of entries
      #
      # @return [Integer]
      def size
        @monitor.synchronize { @cache.size }
      end

      # Check if a key exists and is not expired
      #
      # @param cache_key [String] The cache key
      # @return [Boolean]
      def key?(cache_key)
        @monitor.synchronize do
          entry = @cache[cache_key]
          entry && !entry.expired? && entry.value != IN_PROGRESS
        end
      end

      # Total evictions since creation
      #
      # @return [Integer]
      def eviction_count
        @eviction_count
      end

      private

      def delete_entry(cache_key)
        if @cache.delete(cache_key)
          @access_order.delete(cache_key)
          true
        else
          false
        end
      end

      def touch_lru(cache_key)
        @access_order.delete(cache_key)
        @access_order[cache_key] = true
      end

      def evict_lru
        return if @access_order.empty?

        oldest_key, = @access_order.first
        @access_order.delete(oldest_key)
        @cache.delete(oldest_key)
        @eviction_count += 1
      end
    end
  end
end
