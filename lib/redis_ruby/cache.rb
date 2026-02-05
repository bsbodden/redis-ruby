# frozen_string_literal: true

require "monitor"

module RedisRuby
  # Client-side cache with RESP3 push-based invalidation
  #
  # Provides automatic caching of Redis GET results with server-assisted
  # invalidation using Redis CLIENT TRACKING feature.
  #
  # When enabled, Redis sends invalidation messages when cached keys are
  # modified by any client. This ensures cache consistency without polling.
  #
  # @example Basic usage
  #   cache = RedisRuby::Cache.new(client)
  #   cache.enable!
  #
  #   # First call fetches from Redis and caches
  #   value = cache.get("key")  # => "value" (from Redis)
  #
  #   # Subsequent calls return cached value
  #   value = cache.get("key")  # => "value" (from cache)
  #
  #   # If another client modifies "key", cache is automatically invalidated
  #
  # @example With TTL
  #   cache = RedisRuby::Cache.new(client, ttl: 60)  # 60 second max TTL
  #
  # @example OPTIN mode (only cache explicitly requested keys)
  #   cache = RedisRuby::Cache.new(client, mode: :optin)
  #   cache.enable!
  #   cache.get("key", cache: true)  # Cache this key
  #   cache.get("other")             # Don't cache this key
  #
  class Cache
    # Default maximum number of cached entries
    DEFAULT_MAX_ENTRIES = 10_000

    # Default TTL for cached entries (nil = no TTL, rely on invalidation)
    DEFAULT_TTL = nil

    # Cache entry with value and expiration
    CacheEntry = Struct.new(:value, :expires_at) do
      def expired?
        expires_at && Time.now > expires_at
      end
    end

    attr_reader :max_entries, :ttl, :mode

    # Initialize a new client-side cache
    #
    # @param client [RedisRuby::Client] Redis client (must be RESP3)
    # @param max_entries [Integer] Maximum cache size (LRU eviction)
    # @param ttl [Float, nil] Time-to-live for entries in seconds
    # @param mode [Symbol] :default, :optin, :optout, or :broadcast
    def initialize(client, max_entries: DEFAULT_MAX_ENTRIES, ttl: DEFAULT_TTL, mode: :default)
      @client = client
      @max_entries = max_entries
      @ttl = ttl
      @mode = mode
      @cache = {}
      @access_order = []  # LRU tracking
      @monitor = Monitor.new
      @enabled = false
      @tracking_redirect_id = nil
    end

    # Enable client-side caching
    #
    # Sends CLIENT TRACKING ON to Redis server.
    #
    # @return [Boolean] true if enabled
    def enable!
      return true if @enabled

      # Enable tracking with appropriate mode
      args = ["CLIENT", "TRACKING", "ON"]

      case @mode
      when :optin
        args << "OPTIN"
      when :optout
        args << "OPTOUT"
      when :broadcast
        args << "BCAST"
      end

      result = @client.call(*args)
      @enabled = result == "OK"
      @enabled
    end

    # Disable client-side caching
    #
    # @return [Boolean] true if disabled
    def disable!
      return true unless @enabled

      result = @client.call("CLIENT", "TRACKING", "OFF")
      @enabled = false
      clear
      result == "OK"
    end

    # Check if caching is enabled
    #
    # @return [Boolean]
    def enabled?
      @enabled
    end

    # Get a value, using cache if available
    #
    # @param key [String] Redis key
    # @param cache [Boolean] Force cache behavior (for OPTIN/OPTOUT modes)
    # @return [String, nil] Value or nil
    def get(key, cache: nil)
      # Check if we should use the cache
      use_cache = should_cache?(cache)

      if use_cache && @enabled
        @monitor.synchronize do
          entry = @cache[key]
          if entry && !entry.expired?
            touch_lru(key)
            return entry.value
          end
        end
      end

      # Send CACHING YES if in OPTIN mode and cache requested
      if @enabled && @mode == :optin && cache == true
        @client.call("CLIENT", "CACHING", "YES")
      end

      # Fetch from Redis
      value = @client.get(key)

      # Cache the result
      if use_cache && @enabled && value
        @monitor.synchronize do
          store(key, value)
        end
      end

      value
    end

    # Invalidate a key from the cache
    #
    # Called automatically when Redis sends invalidation messages.
    #
    # @param key [String] Key to invalidate
    # @return [Boolean] true if key was cached
    def invalidate(key)
      @monitor.synchronize do
        if @cache.delete(key)
          @access_order.delete(key)
          true
        else
          false
        end
      end
    end

    # Invalidate multiple keys
    #
    # @param keys [Array<String>] Keys to invalidate
    # @return [Integer] Number of keys invalidated
    def invalidate_all(keys)
      count = 0
      @monitor.synchronize do
        keys.each do |key|
          if @cache.delete(key)
            @access_order.delete(key)
            count += 1
          end
        end
      end
      count
    end

    # Clear the entire cache
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

    # Get cache statistics
    #
    # @return [Hash] Statistics
    def stats
      @monitor.synchronize do
        {
          size: @cache.size,
          max_entries: @max_entries,
          enabled: @enabled,
          mode: @mode,
          ttl: @ttl
        }
      end
    end

    # Process an invalidation message from Redis
    #
    # Called by the connection when a push message is received.
    #
    # @param message [Array] Push message from Redis
    # @return [Boolean] true if message was processed
    def process_invalidation(message)
      return false unless message.is_a?(Array)
      return false unless message[0] == "invalidate"

      keys = message[1]
      return false unless keys

      if keys.nil?
        # Full flush requested
        clear
      else
        invalidate_all(keys)
      end

      true
    end

    # Check if a key is currently cached
    #
    # @param key [String] Key to check
    # @return [Boolean]
    def cached?(key)
      @monitor.synchronize do
        entry = @cache[key]
        entry && !entry.expired?
      end
    end

    private

    # Determine if we should use the cache based on mode and explicit flag
    def should_cache?(explicit_cache)
      case @mode
      when :optin
        explicit_cache == true
      when :optout
        explicit_cache != false
      else
        true
      end
    end

    # Store a value in the cache
    def store(key, value)
      # Remove oldest entry if at capacity
      evict_lru if @cache.size >= @max_entries && !@cache.key?(key)

      expires_at = @ttl ? Time.now + @ttl : nil
      @cache[key] = CacheEntry.new(value, expires_at)
      touch_lru(key)
    end

    # Update LRU order for a key
    def touch_lru(key)
      @access_order.delete(key)
      @access_order.push(key)
    end

    # Evict the least recently used entry
    def evict_lru
      return if @access_order.empty?

      oldest_key = @access_order.shift
      @cache.delete(oldest_key)
    end
  end
end
