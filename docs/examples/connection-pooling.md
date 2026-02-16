---
layout: default
title: Connection Pooling Example
parent: Examples
nav_order: 2
permalink: /examples/connection-pooling/
---

# Connection Pooling Example

This example demonstrates how to use connection pools for thread-safe, high-performance Redis operations in multi-threaded applications.

## Prerequisites

- Ruby 3.2+ installed
- Redis 6.2+ running on localhost:6379
- redis-ruby gem installed (`gem install redis-ruby`)

## Complete Example

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "redis_ruby"  # Native RR API
require "benchmark"

puts "=== Connection Pooling Example ===\n\n"

# ============================================================================
# Thread-Safe Connection Pool
# ============================================================================

puts "1. Creating a thread-safe connection pool..."

# Create a pooled client with 10 connections
redis = RR.pooled(
  url: "redis://localhost:6379",
  pool: { size: 10, timeout: 5 }
)

puts "   Pool created with size: 10"
puts "   Pool timeout: 5 seconds\n\n"

# ============================================================================
# Multi-Threaded Operations
# ============================================================================

puts "2. Running multi-threaded operations..."

# Simulate 20 concurrent requests with 10 connections
threads = 20.times.map do |i|
  Thread.new do
    # Each thread gets a connection from the pool
    redis.set("user:#{i}:name", "User #{i}")
    redis.incr("request:count")
    redis.get("user:#{i}:name")
  end
end

# Wait for all threads to complete
results = threads.map(&:value)

puts "   Processed #{results.size} requests"
puts "   Total requests: #{redis.get('request:count')}\n\n"

# ============================================================================
# Performance Comparison
# ============================================================================

puts "3. Performance comparison: Single connection vs Pool..."

# Reset counter
redis.set("counter", 0)

# Single connection (unsafe for multi-threading)
single_redis = RR.new(url: "redis://localhost:6379")

time_single = Benchmark.realtime do
  100.times { single_redis.incr("counter") }
end

# Pooled connection
redis.set("counter", 0)

time_pooled = Benchmark.realtime do
  threads = 10.times.map do
    Thread.new do
      10.times { redis.incr("counter") }
    end
  end
  threads.each(&:join)
end

puts "   Single connection (100 ops): #{(time_single * 1000).round(2)}ms"
puts "   Pooled (10 threads x 10 ops): #{(time_pooled * 1000).round(2)}ms"
puts "   Speedup: #{(time_single / time_pooled).round(2)}x\n\n"

# ============================================================================
# Batch Operations with Same Connection
# ============================================================================

puts "4. Batch operations with same connection..."

# Use with_connection to ensure all commands use the same connection
redis.with_connection do |conn|
  conn.call("SET", "key1", "value1")
  conn.call("SET", "key2", "value2")
  conn.call("GET", "key1")
end

puts "   Executed batch operations on same connection\n\n"

# ============================================================================
# Pool Monitoring
# ============================================================================

puts "5. Pool monitoring..."

puts "   Pool size: #{redis.pool_size}"
puts "   Available connections: #{redis.pool_available}"
puts "   In use: #{redis.pool_size - redis.pool_available}\n\n"

# ============================================================================
# Puma/Rails Example
# ============================================================================

puts "6. Puma/Rails configuration example..."

puts <<~EXAMPLE
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
EXAMPLE

puts

# ============================================================================
# Sidekiq Example
# ============================================================================

puts "7. Sidekiq configuration example..."

puts <<~EXAMPLE
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
EXAMPLE

puts


# ============================================================================
# Cleanup
# ============================================================================

puts "8. Cleanup..."

# Delete test keys
redis.del("request:count", "counter", "key1", "key2")
20.times { |i| redis.del("user:#{i}:name") }

# Close pools
redis.close
single_redis.close

puts "   Cleaned up and closed connections\n\n"
```

## Running the Example

Save the code to a file (e.g., `connection_pooling.rb`) and run:

```bash
ruby connection_pooling.rb
```

## Key Takeaways

1. **Thread Safety** - Connection pools prevent race conditions in multi-threaded apps
2. **Performance** - Pools improve throughput by reusing connections
3. **Configuration** - Size pool to match your concurrency level
4. **Monitoring** - Check pool size and availability
5. **Batch Operations** - Use `with_connection` for operations requiring the same connection

## Next Steps

- [Pipelining Example](/examples/pipelining/) - Batch operations for performance
- [Connection Pools Guide](/guides/connection-pools/) - Detailed pooling documentation
- [Getting Started](/getting-started/) - Basic Redis operations
