# frozen_string_literal: true

module RR
  class Cache
    # Builds composite cache keys from (command, key, *args)
    #
    # Handles commands like HGET, ZRANGEBYSCORE that need args as part of
    # the cache key (like redis-py CacheKey).
    #
    # Also maintains a reverse index (Redis key -> set of cache keys)
    # for efficient invalidation.
    #
    # @example
    #   builder = KeyBuilder.new
    #   builder.build("GET", "user:1")          # => "GET:user:1"
    #   builder.build("HGET", "h", "field")     # => "HGET:h:field"
    #   builder.build("ZRANGE", "z", "0", "10") # => "ZRANGE:z:0:10"
    #
    class KeyBuilder
      SEPARATOR = ":"

      def initialize
        # Reverse index: Redis key -> Set of cache keys
        @reverse_index = Hash.new { |h, k| h[k] = [] }
      end

      # Build a cache key from command, Redis key, and optional args
      #
      # @param command [String] Redis command name
      # @param redis_key [String] The Redis key
      # @param args [Array] Additional arguments (e.g., field for HGET)
      # @return [String] Composite cache key
      def build(command, redis_key, *args)
        cache_key = if args.empty?
                      "#{command}#{SEPARATOR}#{redis_key}"
                    else
                      "#{command}#{SEPARATOR}#{redis_key}#{SEPARATOR}#{args.join(SEPARATOR)}"
                    end

        # Track in reverse index
        @reverse_index[redis_key] << cache_key unless @reverse_index[redis_key].include?(cache_key)

        cache_key
      end

      # Get all cache keys associated with a Redis key
      #
      # @param redis_key [String] The Redis key
      # @return [Array<String>] Cache keys referencing this Redis key
      def cache_keys_for(redis_key)
        @reverse_index[redis_key]
      end

      # Remove a cache key from the reverse index
      #
      # @param cache_key [String] The cache key to remove
      # @param redis_key [String] The Redis key it references
      def remove(cache_key, redis_key)
        @reverse_index[redis_key]&.delete(cache_key)
        @reverse_index.delete(redis_key) if @reverse_index[redis_key] && @reverse_index[redis_key].empty?
      end

      # Remove all cache key mappings for a Redis key
      #
      # @param redis_key [String] The Redis key
      # @return [Array<String>] The cache keys that were mapped
      def remove_all_for(redis_key)
        @reverse_index.delete(redis_key) || []
      end

      # Clear the entire reverse index
      def clear
        @reverse_index.clear
      end

      # Number of Redis keys tracked
      #
      # @return [Integer]
      def size
        @reverse_index.size
      end
    end
  end
end
