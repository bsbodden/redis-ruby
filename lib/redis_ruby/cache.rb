# frozen_string_literal: true

require "monitor"
require_relative "cache/config"
require_relative "cache/key_builder"
require_relative "cache/command_registry"
require_relative "cache/stats"
require_relative "cache/store"

module RR
  # Client-side cache with RESP3 push-based invalidation
  #
  # Provides automatic caching of Redis read command results with server-assisted
  # invalidation using Redis CLIENT TRACKING feature.
  #
  # When enabled, Redis sends invalidation messages when cached keys are
  # modified by any client. This ensures cache consistency without polling.
  #
  # Supports multi-command caching (GET, HGET, ZRANGE, etc.), composite cache
  # keys, pluggable backends, hit/miss/eviction stats, and `cached`/`uncached`
  # block scoping.
  #
  # @example Basic usage
  #   cache = RR::Cache.new(client)
  #   cache.enable!
  #
  #   # First call fetches from Redis and caches
  #   value = cache.get("key")  # => "value" (from Redis)
  #
  #   # Subsequent calls return cached value
  #   value = cache.get("key")  # => "value" (from cache)
  #
  # @example With Config
  #   config = Cache::Config.new(max_entries: 5000, ttl: 300, mode: :optin)
  #   cache = RR::Cache.new(client, config)
  #
  # @example Transparent caching via Client
  #   client = RR::Client.new(cache: true)
  #   client.get("key")  # Automatically cached
  #
  # @example cached/uncached blocks
  #   client.cache.cached { client.get("key") }    # Force cache
  #   client.cache.uncached { client.get("key") }   # Bypass cache
  #
  class Cache
    # Default maximum number of cached entries
    DEFAULT_MAX_ENTRIES = 10_000

    # Default TTL for cached entries (nil = no TTL, rely on invalidation)
    DEFAULT_TTL = nil

    # Keep CacheEntry accessible for backward compatibility with existing tests
    CacheEntry = Store::CacheEntry

    attr_reader :config

    # Initialize a new client-side cache
    #
    # @param client [RR::Client] Redis client (must be RESP3)
    # @param config_or_options [Config, Hash] Cache config or legacy keyword args
    # @param max_entries [Integer] (legacy) Maximum cache size
    # @param ttl [Float, nil] (legacy) Time-to-live for entries in seconds
    # @param mode [Symbol] (legacy) :default, :optin, :optout, or :broadcast
    def initialize(client, config_or_options = nil, max_entries: DEFAULT_MAX_ENTRIES,
                   ttl: DEFAULT_TTL, mode: :default)
      @client = client
      @force_cache = nil

      @config = if config_or_options.is_a?(Config)
                  config_or_options
                elsif config_or_options.is_a?(Hash)
                  Config.new(**config_or_options)
                else
                  Config.new(max_entries: max_entries, ttl: ttl, mode: mode)
                end

      @store = @config.store || Store.new(max_entries: @config.max_entries)
      @stats = Stats.new
      @registry = CommandRegistry.new(
        allow_list: @config.cacheable_commands
      )
      @key_builder = KeyBuilder.new
      @enabled = false
      @tracking_redirect_id = nil
    end

    # Backward-compatible accessors
    def max_entries
      @config.max_entries
    end

    def ttl
      @config.ttl
    end

    def mode
      @config.mode
    end

    # Enable client-side caching
    #
    # Sends CLIENT TRACKING ON to Redis server.
    #
    # @return [Boolean] true if enabled
    def enable!
      return true if @enabled

      args = %w[CLIENT TRACKING ON]

      case @config.mode
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

    # Get a value, using cache if available (legacy API, backward-compatible)
    #
    # @param key [String] Redis key
    # @param cache [Boolean] Force cache behavior (for OPTIN/OPTOUT modes)
    # @return [String, nil] Value or nil
    def get(key, cache: nil)
      use_cache = should_cache?(cache)
      cached = lookup_cached("GET", key) if use_cache && @enabled
      return cached unless cached.nil?

      enable_optin_caching if cache == true
      value = @client.get(key)
      store_if_cacheable("GET", key, value) if use_cache && @enabled
      value
    end

    # Transparent caching for the call path
    #
    # Called by Client#call when cache is enabled. Checks if the command
    # is cacheable, looks up in cache, and stores on miss.
    #
    # @param command [String] Redis command name
    # @param redis_key [String] The Redis key argument
    # @param args [Array] Additional command arguments
    # @yield Block that executes the actual Redis command
    # @return [Object] Cached or fresh value
    def fetch(command, redis_key, *)
      return yield unless @enabled && cacheable?(command, redis_key)

      cache_key = @key_builder.build(command, redis_key, *)
      cached = @store.get(cache_key)

      if cached && cached != Store::IN_PROGRESS
        @stats.hit!
        return cached
      end

      @stats.miss!
      @store.mark_in_progress(cache_key) unless cached == Store::IN_PROGRESS
      value = yield
      @store.set(cache_key, value, ttl: @config.ttl) unless value.nil?
      value
    end

    # Temporarily force caching on for all commands in the block
    #
    # @yield Block where caching is forced on
    # @return [Object] Block return value
    def cached
      prev = @force_cache
      @force_cache = true
      yield
    ensure
      @force_cache = prev
    end

    # Temporarily disable caching for all commands in the block
    #
    # @yield Block where caching is bypassed
    # @return [Object] Block return value
    def uncached
      prev = @force_cache
      @force_cache = false
      yield
    ensure
      @force_cache = prev
    end

    # Check if caching is currently forced on or off
    #
    # @return [Boolean, nil] true=forced on, false=forced off, nil=normal
    def force_cache_state
      @force_cache
    end

    # Invalidate a key from the cache
    #
    # @param key [String] Key to invalidate
    # @return [Boolean] true if key was cached
    def invalidate(key)
      count = @store.delete_by_redis_key(key, @key_builder)
      @stats.invalidate_bulk!(count) if count.positive?
      count.positive?
    end

    # Invalidate multiple keys
    #
    # @param keys [Array<String>] Keys to invalidate
    # @return [Integer] Number of keys invalidated
    def invalidate_all(keys)
      count = 0
      keys.each do |key|
        deleted = @store.delete_by_redis_key(key, @key_builder)
        count += deleted
      end
      @stats.invalidate_bulk!(count) if count.positive?
      count
    end

    # Clear the entire cache
    #
    # @return [Integer] Number of entries cleared
    def clear
      @key_builder.clear
      @store.clear
    end

    # Get the stats tracker object
    #
    # @return [Stats]
    def stats_tracker
      @stats
    end

    # Get cache statistics as a Hash (backward-compatible)
    #
    # @return [Hash] Statistics
    def stats
      {
        size: @store.size,
        max_entries: @config.max_entries,
        enabled: @enabled,
        mode: @config.mode,
        ttl: @config.ttl,
        hits: @stats.hits,
        misses: @stats.misses,
        hit_rate: @stats.hit_rate,
        evictions: @stats.evictions,
        invalidations: @stats.invalidations,
      }
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

      if keys.nil?
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
      cache_key = @key_builder.build("GET", key)
      @store.key?(cache_key)
    end

    # Check if a command is cacheable
    #
    # @param command [String] Redis command
    # @param redis_key [String, nil] The Redis key (for key filtering)
    # @return [Boolean]
    def cacheable?(command, redis_key = nil)
      # Force cache state from cached/uncached blocks
      return true if @force_cache == true
      return false if @force_cache == false
      return false unless @registry.cacheable?(command)
      return false if key_filtered_out?(redis_key)

      @config.mode != :optin
    end

    private

    def key_filtered_out?(redis_key)
      @config.key_filter && redis_key && !@config.key_filter.call(redis_key)
    end

    def lookup_cached(command, key, *)
      cache_key = @key_builder.build(command, key, *)
      result = @store.get(cache_key)
      return nil if result.nil? || result == Store::IN_PROGRESS

      @stats.hit!
      result
    end

    def enable_optin_caching
      @client.call("CLIENT", "CACHING", "YES") if @enabled && @config.mode == :optin
    end

    def store_if_cacheable(command, key, value, *)
      return unless value

      cache_key = @key_builder.build(command, key, *)
      @store.set(cache_key, value, ttl: @config.ttl)
    end

    # Determine if we should use the cache based on mode and explicit flag
    def should_cache?(explicit_cache)
      case @config.mode
      when :optin
        explicit_cache == true
      when :optout
        explicit_cache != false
      else
        true
      end
    end
  end
end
