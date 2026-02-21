# frozen_string_literal: true

module RR
  class Cache
    # Thread-safe cache statistics tracking
    #
    # Uses Mutex for thread-safe counter updates.
    #
    # @example
    #   stats = Stats.new
    #   stats.hit!
    #   stats.miss!
    #   stats.to_h  # => { hits: 1, misses: 1, hit_rate: 0.5, ... }
    #
    class Stats
      attr_reader :hits, :misses, :evictions, :invalidations

      def initialize
        @mutex = Mutex.new
        @hits = 0
        @misses = 0
        @evictions = 0
        @invalidations = 0
      end

      # Record a cache hit
      def hit!
        @mutex.synchronize { @hits += 1 }
      end

      # Record a cache miss
      def miss!
        @mutex.synchronize { @misses += 1 }
      end

      # Record an eviction
      def evict!
        @mutex.synchronize { @evictions += 1 }
      end

      # Record an invalidation
      def invalidate!
        @mutex.synchronize { @invalidations += 1 }
      end

      # Record multiple invalidations at once
      #
      # @param count [Integer] Number of invalidations
      def invalidate_bulk!(count)
        @mutex.synchronize { @invalidations += count }
      end

      # Calculate the hit rate
      #
      # @return [Float] Hit rate between 0.0 and 1.0
      def hit_rate
        total = @hits + @misses
        return 0.0 if total.zero?

        @hits.to_f / total
      end

      # Get statistics as a Hash
      #
      # @param size [Integer] Current cache size (passed from store)
      # @return [Hash]
      def to_h(size: 0)
        @mutex.synchronize do
          {
            hits: @hits,
            misses: @misses,
            hit_rate: hit_rate,
            evictions: @evictions,
            invalidations: @invalidations,
            size: size,
          }
        end
      end

      # Reset all counters
      def reset!
        @mutex.synchronize do
          @hits = 0
          @misses = 0
          @evictions = 0
          @invalidations = 0
        end
      end
    end
  end
end
