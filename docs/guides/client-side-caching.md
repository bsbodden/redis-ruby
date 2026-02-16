---
layout: default
title: Client-Side Caching
parent: Guides
nav_order: 9
---

# Client-Side Caching

This guide covers client-side caching in redis-ruby using Redis's RESP3 protocol and server-assisted tracking for automatic cache invalidation.

## Table of Contents

- [What is Client-Side Caching](#what-is-client-side-caching)
- [RESP3 Tracking](#resp3-tracking)
- [Cache Invalidation](#cache-invalidation)
- [Configuration](#configuration)
- [Performance Benefits](#performance-benefits)
- [Tracking Modes](#tracking-modes)
- [Best Practices](#best-practices)

## What is Client-Side Caching

Client-side caching stores frequently accessed data in the application's memory, reducing network round-trips to Redis. Redis 6.0+ provides server-assisted invalidation through the CLIENT TRACKING feature.

### How It Works

1. **Client enables tracking**: Sends `CLIENT TRACKING ON` to Redis
2. **Client caches values**: Stores GET results in local memory
3. **Server tracks keys**: Redis remembers which client cached which keys
4. **Server sends invalidations**: When a key changes, Redis notifies the client
5. **Client invalidates cache**: Removes stale entries from local cache

### Benefits

- **Reduced Latency**: No network round-trip for cached values
- **Lower Redis Load**: Fewer requests to Redis server
- **Automatic Invalidation**: Server notifies when data changes
- **Consistency**: Cache stays synchronized with Redis

## RESP3 Tracking

### Enabling Client-Side Caching

```ruby
require "redis_ruby"  # Native RR API

# Create a Redis client (must use RESP3)
redis = RR.new(url: "redis://localhost:6379")

# Create and enable cache
cache = RR::Cache.new(redis)
cache.enable!

# First access - fetches from Redis and caches
value = cache.get("user:1000")  # Network round-trip

# Subsequent accesses - returns from cache
value = cache.get("user:1000")  # No network round-trip!

# If another client modifies the key, cache is automatically invalidated
```

### How Tracking Works

```ruby
cache = RR::Cache.new(redis)
cache.enable!

# Behind the scenes:
# 1. Client sends: CLIENT TRACKING ON
# 2. Client sends: GET user:1000
# 3. Redis tracks: "client X is caching user:1000"
# 4. Client caches: user:1000 => "Alice"

# Later, another client modifies the key:
# other_client.set("user:1000", "Bob")

# Redis sends invalidation message to first client:
# > invalidate ["user:1000"]

# Client automatically removes user:1000 from cache
```

### Cache Statistics

```ruby
cache = RR::Cache.new(redis)
cache.enable!

# Perform some operations
cache.get("key1")
cache.get("key1")  # Cache hit
cache.get("key2")

# Check statistics
stats = cache.stats
puts "Hits: #{stats[:hits]}"
puts "Misses: #{stats[:misses]}"
puts "Hit rate: #{stats[:hit_rate]}%"
puts "Size: #{stats[:size]} entries"
```

## Cache Invalidation

### Automatic Invalidation

Redis automatically sends invalidation messages:

```ruby
cache = RR::Cache.new(redis)
cache.enable!

# Cache a value
cache.get("product:100")  # => "Widget"

# Another client modifies it
other_client = RR.new(url: "redis://localhost:6379")
other_client.set("product:100", "Gadget")

# Cache is automatically invalidated
# Next access fetches fresh value
cache.get("product:100")  # => "Gadget" (from Redis, not cache)
```

### Manual Invalidation

```ruby
cache = RR::Cache.new(redis)
cache.enable!

# Invalidate a specific key
cache.invalidate("user:1000")

# Clear entire cache
cache.clear

# Flush all cached entries
cache.flush
```

### Invalidation Events

```ruby
# Track invalidation events
cache = RR::Cache.new(redis)
cache.enable!

# Get invalidation count


## Performance Benefits

### Latency Reduction

```ruby
require "benchmark"

redis = RR.new(url: "redis://localhost:6379")
cache = RR::Cache.new(redis)
cache.enable!

# Warm up cache
cache.get("benchmark:key")

# Benchmark without cache
time_without_cache = Benchmark.realtime do
  1000.times { redis.get("benchmark:key") }
end

# Benchmark with cache
time_with_cache = Benchmark.realtime do
  1000.times { cache.get("benchmark:key") }
end

puts "Without cache: #{time_without_cache}s"
puts "With cache: #{time_with_cache}s"
puts "Speedup: #{(time_without_cache / time_with_cache).round(2)}x"

# Typical results:
# Without cache: 0.15s (1000 network round-trips)
# With cache: 0.001s (1000 memory lookups)
# Speedup: 150x
```

### Reduced Redis Load

```ruby
# Without caching - 1000 requests to Redis
1000.times { redis.get("popular:key") }

# With caching - 1 request to Redis, 999 from cache
cache.enable!
1000.times { cache.get("popular:key") }

# Check hit rate
stats = cache.stats
puts "Hit rate: #{stats[:hit_rate]}%"  # => 99.9%
```

### Memory vs Network Trade-off

```ruby
# Configure based on your needs
cache = RR::Cache.new(
  redis,
  max_entries: 10_000,  # ~1-10MB depending on value sizes
  ttl: 300              # 5 minute max staleness
)

# Benefits:
# - Saves ~10,000 network round-trips
# - Reduces Redis CPU usage
# - Improves application response time

# Cost:
# - ~1-10MB application memory
# - Potential 5-minute staleness (mitigated by invalidation)
```

## Tracking Modes

### Default Mode

Track all keys accessed with GET:

```ruby
cache = RR::Cache.new(redis, mode: :default)
cache.enable!

# All GET operations are tracked and cached
cache.get("key1")  # Tracked and cached
cache.get("key2")  # Tracked and cached
```

### OPTIN Mode

Only track explicitly requested keys:

```ruby
cache = RR::Cache.new(redis, mode: :optin)
cache.enable!

# Explicitly cache this key
cache.get("important:key", cache: true)  # Tracked and cached

# Don't cache this key
cache.get("temporary:key")  # Not cached

# Or cache this one
cache.get("another:key", cache: true)  # Tracked and cached
```

### OPTOUT Mode

Track all keys except explicitly excluded:

```ruby
cache = RR::Cache.new(redis, mode: :optout)
cache.enable!

# Cache by default
cache.get("key1")  # Tracked and cached

# Explicitly don't cache
cache.get("volatile:key", cache: false)  # Not cached

# Cache again
cache.get("key2")  # Tracked and cached
```

### BROADCAST Mode

Track keys matching a prefix pattern:

```ruby
cache = RR::Cache.new(redis, mode: :broadcast)
cache.enable!

# Configure broadcast prefixes in Redis
# CLIENT TRACKING ON BCAST PREFIX user: PREFIX product:

# Only keys matching prefixes are tracked
cache.get("user:1000")     # Tracked (matches prefix)
cache.get("product:100")   # Tracked (matches prefix)
cache.get("session:abc")   # Not tracked (no prefix match)
```

## Best Practices

### 1. Use for Read-Heavy Workloads

```ruby
# Good - frequently read, rarely written
cache = RR::Cache.new(redis)
cache.enable!

# Product catalog (read often, updated occasionally)
cache.get("product:#{product_id}")

# User profiles (read often, updated occasionally)
cache.get("user:#{user_id}")

# Bad - frequently written data
# Don't cache counters, real-time data, or frequently updated keys
```

### 2. Set Appropriate Cache Size

```ruby
# Estimate based on your data
# Average value size: 1KB
# Desired cache entries: 10,000
# Memory usage: ~10MB

cache = RR::Cache.new(
  redis,
  max_entries: 10_000
)

# Monitor and adjust
stats = cache.stats
if stats[:evictions] > stats[:size] * 0.1
  # High eviction rate - consider increasing max_entries
  puts "Warning: High eviction rate"
end
```

### 3. Use TTL for Safety

```ruby
# Add TTL as safety net against stale data
cache = RR::Cache.new(
  redis,
  ttl: 300  # 5 minutes max staleness
)

# Even if invalidation fails, data refreshes after 5 minutes
```

### 4. Choose the Right Mode

```ruby
# Default mode - simple, cache everything
cache = RR::Cache.new(redis, mode: :default)

# OPTIN mode - fine-grained control, cache only important keys
cache = RR::Cache.new(redis, mode: :optin)
cache.get("critical:key", cache: true)

# OPTOUT mode - cache most things, exclude volatile data
cache = RR::Cache.new(redis, mode: :optout)
cache.get("realtime:data", cache: false)
```

### 5. Monitor Cache Performance

```ruby
class CacheMonitor
  def initialize(cache)
    @cache = cache
  end

  def report
    stats = @cache.stats

    puts "Cache Statistics:"
    puts "  Size: #{stats[:size]}/#{@cache.max_entries}"
    puts "  Hits: #{stats[:hits]}"
    puts "  Misses: #{stats[:misses]}"
    puts "  Hit Rate: #{stats[:hit_rate]}%"
    puts "  Invalidations: #{stats[:invalidations]}"
    puts "  Evictions: #{stats[:evictions]}"

    # Alert on low hit rate
    if stats[:hit_rate] < 50
      puts "WARNING: Low cache hit rate!"
    end
  end
end

# Usage
monitor = CacheMonitor.new(cache)
monitor.report
```

### 6. Handle Cache Failures Gracefully

```ruby
class ResilientCache
  def initialize(redis)
    @redis = redis
    @cache = RR::Cache.new(redis)
    @cache.enable!
  rescue => e
    # Cache initialization failed - continue without caching
    logger.warn("Cache disabled: #{e.message}")
    @cache = nil
  end

  def get(key)
    if @cache
      @cache.get(key)
    else
      @redis.get(key)
    end
  rescue => e
    # Cache failed - fall back to direct Redis access
    logger.warn("Cache error, using Redis directly: #{e.message}")
    @redis.get(key)
  end
end
```

### 7. Use OPTIN for Selective Caching

```ruby
cache = RR::Cache.new(redis, mode: :optin)
cache.enable!

# Cache stable, frequently accessed data
def get_user_profile(user_id)
  cache.get("user:#{user_id}:profile", cache: true)
end

# Don't cache volatile data
def get_user_session(session_id)
  cache.get("session:#{session_id}")  # Not cached
end

# Don't cache large data
def get_large_report(report_id)
  cache.get("report:#{report_id}")  # Not cached
end
```

### 8. Combine with Application-Level Caching

```ruby
class TieredCache
  def initialize(redis)
    @redis_cache = RR::Cache.new(redis, ttl: 300)
    @redis_cache.enable!
    @local_cache = {}
  end

  def get(key)
    # Level 1: Local memory (fastest)
    return @local_cache[key] if @local_cache.key?(key)

    # Level 2: Redis client-side cache (fast)
    value = @redis_cache.get(key)
    @local_cache[key] = value if value
    value
  end

  def set(key, value)
    @local_cache[key] = value
    @redis_cache.set(key, value)
  end
end
```

### 9. Disable for Write-Heavy Operations

```ruby
cache = RR::Cache.new(redis)
cache.enable!

# For bulk writes, temporarily disable caching
def bulk_update(keys_and_values)
  cache.disable!

  keys_and_values.each do |key, value|
    redis.set(key, value)
  end
ensure
  cache.enable!
end
```

### 10. Test Cache Behavior

```ruby
require "minitest/autorun"

class CacheTest < Minitest::Test
  def setup
    @redis = RR.new(url: "redis://localhost:6379")
    @cache = RR::Cache.new(@redis)
    @cache.enable!
  end

  def test_caching
    # First access - cache miss
    value = @cache.get("test:key")
    assert_equal 1, @cache.stats[:misses]

    # Second access - cache hit
    value = @cache.get("test:key")
    assert_equal 1, @cache.stats[:hits]
  end

  def test_invalidation
    # Cache a value
    @cache.get("test:key")
    assert @cache.cached?("test:key")

    # Modify from another client
    other_client = RR.new(url: "redis://localhost:6379")
    other_client.set("test:key", "new value")

    # Give invalidation time to propagate
    sleep 0.1

    # Cache should be invalidated
    refute @cache.cached?("test:key")
  end
end
```

## Common Patterns

### Session Caching

```ruby
class SessionCache
  def initialize
    redis = RR.new(url: "redis://localhost:6379")
    @cache = RR::Cache.new(
      redis,
      max_entries: 10_000,
      ttl: 300  # 5 minute sessions
    )
    @cache.enable!
  end

  def get_session(session_id)
    key = "session:#{session_id}"
    data = @cache.get(key)
    data ? JSON.parse(data) : nil
  end

  def save_session(session_id, data)
    key = "session:#{session_id}"
    @cache.set(key, data.to_json)
  end
end
```

### Product Catalog Caching

```ruby
class ProductCache
  def initialize
    redis = RR.new(url: "redis://localhost:6379")
    @cache = RR::Cache.new(
      redis,
      max_entries: 50_000,  # Large catalog
      ttl: 3600,            # 1 hour
      mode: :optin          # Only cache products
    )
    @cache.enable!
  end

  def get_product(product_id)
    key = "product:#{product_id}"
    data = @cache.get(key, cache: true)
    data ? JSON.parse(data) : nil
  end

  def update_product(product_id, data)
    key = "product:#{product_id}"
    @cache.set(key, data.to_json)
    # Cache automatically invalidated for all clients
  end
end
```

### Configuration Caching

```ruby
class ConfigCache
  def initialize
    redis = RR.new(url: "redis://localhost:6379")
    @cache = RR::Cache.new(
      redis,
      max_entries: 1000,
      ttl: 600  # 10 minutes
    )
    @cache.enable!
  end

  def get_config(key)
    @cache.get("config:#{key}")
  end

  def set_config(key, value)
    @cache.set("config:#{key}", value)
  end
end
```

## Troubleshooting

### Cache Not Working

```ruby
# Verify RESP3 is enabled
redis = RR.new(url: "redis://localhost:6379")
info = redis.call("INFO", "server")
puts info  # Check redis_version >= 6.0

# Verify tracking is enabled
cache = RR::Cache.new(redis)
result = cache.enable!
puts "Tracking enabled: #{result}"  # Should be true
```

### Low Hit Rate

```ruby
stats = cache.stats
puts "Hit rate: #{stats[:hit_rate]}%"

if stats[:hit_rate] < 50
  # Possible causes:
  # 1. Cache size too small (high evictions)
  puts "Evictions: #{stats[:evictions]}"

  # 2. TTL too short
  # Increase TTL or remove it

  # 3. Data is frequently modified
  # Client-side caching may not be suitable

  # 4. Access pattern is random (no locality)
  # Consider different caching strategy
end
```

### Memory Usage Too High

```ruby
# Reduce cache size
cache = RR::Cache.new(
  redis,
  max_entries: 1000  # Reduce from 10,000
)

# Or add/reduce TTL
cache = RR::Cache.new(
  redis,
  max_entries: 10_000,
  ttl: 60  # Entries expire after 1 minute
)
```

### Stale Data

```ruby
# Ensure invalidation is working
cache.get("test:key")
redis.set("test:key", "new value")
sleep 0.1  # Allow invalidation to propagate

if cache.cached?("test:key")
  puts "WARNING: Invalidation not working!"
  # Check Redis version, network, etc.
end

# Add TTL as safety net
cache = RR::Cache.new(redis, ttl: 60)
```

## Further Reading

- [Redis Client-Side Caching](https://redis.io/docs/manual/client-side-caching/)
- [RESP3 Protocol](https://github.com/redis/redis-specifications/blob/master/protocol/RESP3.md)
- [Connections Guide](connections.md) - RESP3 configuration
- [Pipelines Guide](pipelines.md) - Combining caching with pipelines

## Configuration

### Basic Configuration

```ruby
# Default configuration
cache = RR::Cache.new(redis)

# With custom settings
cache = RR::Cache.new(
  redis,
  max_entries: 10_000,  # Maximum cache size (LRU eviction)
  ttl: 60,              # Time-to-live in seconds (nil = no TTL)
  mode: :default        # Tracking mode
)
```

### Maximum Cache Size

```ruby
# Limit cache to 1000 entries
cache = RR::Cache.new(redis, max_entries: 1000)

# When cache is full, least recently used entries are evicted
1001.times { |i| cache.get("key:#{i}") }

# Oldest entry was evicted
cache.cached?("key:0")  # => false
cache.cached?("key:1000")  # => true
```

### Time-to-Live (TTL)

```ruby
# Cache entries expire after 60 seconds
cache = RR::Cache.new(redis, ttl: 60)

cache.get("key")  # Cached

# After 60 seconds
sleep 61
cache.get("key")  # Fetches from Redis again
```


