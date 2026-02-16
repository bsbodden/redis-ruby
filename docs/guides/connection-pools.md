---
layout: default
title: Connection Pools
parent: Guides
nav_order: 2
---

# Connection Pools

This guide covers connection pooling in redis-ruby, including thread-safe pools for multi-threaded applications and fiber-safe pools for async applications.

## Table of Contents

- [Why Use Connection Pools](#why-use-connection-pools)
- [Thread-Safe Pools](#thread-safe-pools)
- [Fiber-Safe Pools (Async)](#fiber-safe-pools-async)
- [Pool Configuration](#pool-configuration)
- [Best Practices](#best-practices)
- [Performance Considerations](#performance-considerations)

## Why Use Connection Pools

Redis connections are **not thread-safe**. If you're building a multi-threaded application (e.g., with Puma, Sidekiq, or concurrent workers), you need connection pooling to:

1. **Prevent race conditions**: Multiple threads sharing a single connection can corrupt the protocol
2. **Improve performance**: Reuse connections instead of creating new ones
3. **Limit resource usage**: Control the maximum number of connections
4. **Handle concurrency**: Allow multiple threads/fibers to work simultaneously

### Without Connection Pooling (Unsafe)

```ruby
# ❌ UNSAFE: Single connection shared across threads
redis = RR.new(host: "localhost")

threads = 10.times.map do |i|
  Thread.new do
    redis.set("key:#{i}", "value:#{i}")  # Race condition!
  end
end

threads.each(&:join)
```

### With Connection Pooling (Safe)

```ruby
# ✅ SAFE: Each thread gets its own connection from the pool
redis = RR.pooled(
  host: "localhost",
  pool: { size: 10 }
)

threads = 10.times.map do |i|
  Thread.new do
    redis.set("key:#{i}", "value:#{i}")  # Safe!
  end
end

threads.each(&:join)
```

## Thread-Safe Pools

redis-ruby provides `RR.pooled` for thread-safe connection pooling using the `connection_pool` gem.

### Basic Usage

```ruby
require "redis_ruby"  # Native RR API

# Create a pooled client
redis = RR.pooled(
  url: "redis://localhost:6379",
  pool: { size: 10, timeout: 5 }
)

# Use it like a regular client
redis.set("key", "value")
redis.get("key")  # => "value"

# Each command automatically checks out a connection,
# executes, and returns it to the pool
```

### Pool Configuration

```ruby
redis = RR.pooled(
  url: "redis://localhost:6379",
  pool: {
    size: 10,      # Maximum number of connections (default: 5)
    timeout: 5     # Timeout waiting for a connection (default: 5 seconds)
  }
)
```

### Multi-Threaded Example

```ruby
redis = RR.pooled(
  host: "localhost",
  pool: { size: 20 }
)

# Simulate 100 concurrent requests with 20 connections
threads = 100.times.map do |i|
  Thread.new do
    # Each thread gets a connection from the pool
    redis.set("user:#{i}:name", "User #{i}")
    redis.incr("request:count")
    redis.get("user:#{i}:name")
  end
end

results = threads.map(&:value)
puts "Processed #{results.size} requests"
puts "Total requests: #{redis.get('request:count')}"
```

### Using with Puma (Rails)

```ruby
# config/initializers/redis.rb
REDIS_POOL = RR.pooled(
  url: ENV["REDIS_URL"],
  pool: {
    size: ENV.fetch("RAILS_MAX_THREADS", 5).to_i,
    timeout: 5
  }
)

# In your application code
class MyController < ApplicationController
  def index
    REDIS_POOL.set("key", "value")
    @value = REDIS_POOL.get("key")
  end
end
```

### Using with Sidekiq

```ruby
# config/initializers/sidekiq.rb
Sidekiq.configure_server do |config|
  config.redis = {
    url: ENV["REDIS_URL"],
    pool: { size: 25 }  # Sidekiq concurrency + 5
  }
end

Sidekiq.configure_client do |config|
  config.redis = {
    url: ENV["REDIS_URL"],
    pool: { size: 5 }
  }
end
```

### Batch Operations with Same Connection

Sometimes you need multiple commands to use the same connection:

```ruby
redis = RR.pooled(pool: { size: 10 })

# Use with_connection to ensure all commands use the same connection
redis.with_connection do |conn|
  conn.call("SET", "key1", "value1")
  conn.call("SET", "key2", "value2")
  conn.call("GET", "key1")
end
```

This is useful for:
- Transactions (MULTI/EXEC)
- WATCH operations
- Pub/Sub subscriptions
- Lua scripts with state

## Fiber-Safe Pools (Async)

For async applications using the `async` gem, redis-ruby provides fiber-safe connection pooling with `RR.async_pooled`.

### Why Fiber-Safe Pools?

Traditional thread-safe pools don't work well with fibers because:
- Fibers are cooperative, not preemptive
- Multiple fibers can run in a single thread
- Thread-local storage doesn't work for fibers

### Basic Usage

```ruby
require "async"
require "redis_ruby"  # Native RR API

Async do
  redis = RR.async_pooled(
    url: "redis://localhost:6379",
    pool: { limit: 10 }
  )

  redis.set("key", "value")
  value = redis.get("key")
  puts value  # => "value"
end
```

### Concurrent Fiber Operations

```ruby
require "async"

Async do |task|
  redis = RR.async_pooled(
    host: "localhost",
    pool: { limit: 20 }
  )

  # Run 100 operations concurrently with only 20 connections
  tasks = 100.times.map do |i|
    task.async do
      redis.set("key:#{i}", "value:#{i}")
      redis.get("key:#{i}")
    end
  end

  # Wait for all tasks to complete
  results = tasks.map(&:wait)
  puts "Completed #{results.size} operations"
end
```

### Pool Configuration

```ruby
redis = RR.async_pooled(
  url: "redis://localhost:6379",
  pool: {
    limit: 10  # Maximum number of connections (default: 5)
  }
)
```

**Note**: Async pools use `limit` instead of `size` to match the `async-pool` gem conventions.

### Using with Falcon Web Server

```ruby
# config.ru
require "async"
require "redis_ruby"  # Native RR API

# Create a shared async pool
REDIS = RR.async_pooled(
  url: ENV["REDIS_URL"],
  pool: { limit: 50 }
)

run lambda { |env|
  Async do
    REDIS.incr("requests:count")
    count = REDIS.get("requests:count")

    [200, {"content-type" => "text/plain"}, ["Request count: #{count}"]]
  end.wait
}
```

### Batch Operations

```ruby
Async do
  redis = RR.async_pooled(pool: { limit: 10 })

  # Use with_connection for batch operations
  redis.with_connection do |conn|
    conn.call("SET", "key1", "value1")
    conn.call("SET", "key2", "value2")
    conn.call("GET", "key1")
  end
end
```

## Pool Configuration

### Choosing Pool Size

The optimal pool size depends on your application:

```ruby
# For web applications (Puma, Unicorn)
pool_size = ENV.fetch("RAILS_MAX_THREADS", 5).to_i

# For background job processors (Sidekiq)
pool_size = Sidekiq.options[:concurrency] + 5

# For async applications (Falcon)
pool_size = expected_concurrent_fibers

# General rule of thumb
pool_size = number_of_concurrent_workers + buffer
```

### Pool Timeout

The timeout determines how long to wait for an available connection:

```ruby
redis = RR.pooled(
  pool: {
    size: 10,
    timeout: 5  # Wait up to 5 seconds for a connection
  }
)

# If all connections are busy and timeout expires:
# => ConnectionPool::TimeoutError
```

### Monitoring Pool Usage

```ruby
redis = RR.pooled(pool: { size: 10 })

# Check pool size
redis.pool_size  # => 10

# Check available connections
redis.pool_available  # => 7 (if 3 are in use)
```

For async pools:

```ruby
redis = RR.async_pooled(pool: { limit: 10 })

# Check pool limit
redis.pool_limit  # => 10

# Check if connections are available
redis.pool_available?  # => true/false
```

## Best Practices

### 1. Size Your Pool Correctly

```ruby
# ❌ Too small: Connections will be exhausted
redis = RR.pooled(pool: { size: 2 })  # For 20 threads

# ❌ Too large: Wastes resources
redis = RR.pooled(pool: { size: 1000 })  # For 5 threads

# ✅ Just right: Matches concurrency
redis = RR.pooled(pool: { size: 20 })  # For 20 threads
```

### 2. Use Connection Pools in Multi-Threaded Environments

```ruby
# ❌ Don't share a single connection
redis = RR.new(host: "localhost")

# ✅ Use a connection pool
redis = RR.pooled(host: "localhost", pool: { size: 10 })
```

### 3. Close Pools When Done

```ruby
redis = RR.pooled(pool: { size: 10 })

# Use the pool...

# Close all connections when shutting down
redis.close
```

### 4. Use Async Pools for Async Applications

```ruby
# ❌ Don't use thread pools with async
Async do
  redis = RR.pooled(pool: { size: 10 })  # Wrong!
end

# ✅ Use async pools
Async do
  redis = RR.async_pooled(pool: { limit: 10 })  # Correct!
end
```

### 5. Monitor Pool Exhaustion

```ruby
redis = RR.pooled(pool: { size: 10, timeout: 1 })

begin
  redis.get("key")
rescue ConnectionPool::TimeoutError
  # Pool is exhausted - all connections are busy
  logger.error("Redis pool exhausted! Increase pool size.")
  raise
end
```

## Performance Considerations

### Connection Pool Overhead

Connection pools add minimal overhead:

```ruby
# Single connection (baseline)
redis = RR.new(host: "localhost")
# ~100,000 ops/sec

# Pooled connection
redis = RR.pooled(host: "localhost", pool: { size: 10 })
# ~95,000 ops/sec (5% overhead)
```

The overhead is negligible compared to the benefits of thread-safety.

### Pool Size vs. Performance

```ruby
# Small pool (size: 5) with 20 threads
# - High contention
# - Threads wait for connections
# - Lower throughput

# Optimal pool (size: 20) with 20 threads
# - Low contention
# - Minimal waiting
# - Maximum throughput

# Large pool (size: 100) with 20 threads
# - No contention
# - Wastes connections
# - No performance gain
```

### Async Pool Performance

Async pools are more efficient than thread pools:

```ruby
# Thread pool: 100 threads, 100 connections
threads = 100.times.map do |i|
  Thread.new { redis.get("key:#{i}") }
end
threads.each(&:join)

# Async pool: 100 fibers, 20 connections
Async do |task|
  tasks = 100.times.map do |i|
    task.async { redis.get("key:#{i}") }
  end
  tasks.map(&:wait)
end
```

Async pools can handle more concurrency with fewer connections.

## Common Patterns

### Pattern 1: Global Pool

```ruby
# config/initializers/redis.rb
REDIS = RR.pooled(
  url: ENV["REDIS_URL"],
  pool: { size: 20 }
)

# In your application
class CacheService
  def self.get(key)
    REDIS.get(key)
  end

  def self.set(key, value, ttl: 3600)
    REDIS.set(key, value, ex: ttl)
  end
end
```

### Pattern 2: Per-Request Pool

```ruby
# Middleware that provides a Redis connection per request
class RedisMiddleware
  def initialize(app)
    @app = app
    @pool = RR.pooled(pool: { size: 20 })
  end

  def call(env)
    @pool.with_connection do |redis|
      env["redis"] = redis
      @app.call(env)
    end
  end
end
```

### Pattern 3: Lazy Pool Initialization

```ruby
class RedisService
  def self.pool
    @pool ||= RR.pooled(
      url: ENV["REDIS_URL"],
      pool: { size: 10 }
    )
  end

  def self.get(key)
    pool.get(key)
  end
end
```

### Pattern 4: Multiple Pools

```ruby
# Different pools for different purposes
CACHE_REDIS = RR.pooled(
  url: ENV["CACHE_REDIS_URL"],
  pool: { size: 20 }
)

SESSION_REDIS = RR.pooled(
  url: ENV["SESSION_REDIS_URL"],
  pool: { size: 10 }
)

QUEUE_REDIS = RR.pooled(
  url: ENV["QUEUE_REDIS_URL"],
  pool: { size: 5 }
)
```

## Troubleshooting

### Pool Timeout Errors

```ruby
# Error: ConnectionPool::TimeoutError
# Cause: All connections are busy

# Solution 1: Increase pool size
redis = RR.pooled(pool: { size: 20 })  # Was 10

# Solution 2: Increase timeout
redis = RR.pooled(pool: { size: 10, timeout: 10 })  # Was 5

# Solution 3: Optimize slow operations
redis.with_connection do |conn|
  # Don't hold connections for long operations
  result = conn.get("key")
  # Release connection before processing
end
process_result(result)
```

### Connection Leaks

```ruby
# ❌ Connection leak: Exception prevents return to pool
redis.with_connection do |conn|
  conn.set("key", "value")
  raise "Error!"  # Connection not returned!
end

# ✅ Proper error handling
redis.with_connection do |conn|
  begin
    conn.set("key", "value")
    risky_operation()
  rescue => e
    logger.error("Error: #{e}")
    # Connection is still returned to pool
  end
end
```

### Monitoring Pool Health

```ruby
# Check pool statistics
def check_pool_health(redis)
  {
    size: redis.pool_size,
    available: redis.pool_available,
    in_use: redis.pool_size - redis.pool_available
  }
end

stats = check_pool_health(REDIS)
puts "Pool: #{stats[:in_use]}/#{stats[:size]} connections in use"
```

## Next Steps

- [Connections](/guides/connections/) - Learn about connection options
- [Pipelines](/guides/pipelines/) - Batch commands for better performance
- [Getting Started](/getting-started/) - Basic Redis operations

## Additional Resources

- [connection_pool gem](https://github.com/mperham/connection_pool) - Thread-safe connection pooling
- [async-pool gem](https://github.com/socketry/async-pool) - Fiber-safe connection pooling
- [Puma configuration](https://github.com/puma/puma#configuration) - Multi-threaded web server
- [Sidekiq concurrency](https://github.com/mperham/sidekiq/wiki/Advanced-Options#concurrency) - Background job processing

