---
layout: default
title: Pipelining
parent: Guides
nav_order: 3
---

# Pipelining

This guide covers Redis pipelining in redis-ruby, a powerful technique for batching multiple commands and dramatically improving performance.

## Table of Contents

- [What Are Pipelines](#what-are-pipelines)
- [Performance Benefits](#performance-benefits)
- [Basic Pipeline Usage](#basic-pipeline-usage)
- [Pipeline with Transactions](#pipeline-with-transactions)
- [Error Handling](#error-handling)
- [Best Practices](#best-practices)
- [Benchmarks](#benchmarks)

## What Are Pipelines

A pipeline allows you to send multiple Redis commands in a single network round-trip, instead of waiting for each command's response before sending the next one.

### Without Pipelining

```ruby
redis = RR.new(host: "localhost")

# Each command requires a network round-trip
redis.set("key1", "value1")  # Round-trip 1
redis.set("key2", "value2")  # Round-trip 2
redis.set("key3", "value3")  # Round-trip 3
# Total: 3 round-trips
```

### With Pipelining

```ruby
redis = RR.new(host: "localhost")

# All commands sent in one round-trip
results = redis.pipelined do |pipe|
  pipe.set("key1", "value1")
  pipe.set("key2", "value2")
  pipe.set("key3", "value3")
end
# Total: 1 round-trip
# results => ["OK", "OK", "OK"]
```

### How It Works

1. **Queue commands**: Commands are queued locally without sending
2. **Send batch**: All commands are sent to Redis at once
3. **Receive responses**: All responses are received together
4. **Return results**: Results are returned as an array

## Performance Benefits

Pipelining dramatically reduces network latency overhead:

```ruby
# Network latency: 1ms per round-trip
# Command execution: 0.01ms per command

# Without pipelining (100 commands)
# Time = 100 * (1ms + 0.01ms) = 101ms

# With pipelining (100 commands)
# Time = 1ms + (100 * 0.01ms) = 2ms

# Speedup: 50x faster!
```

### Real-World Performance

```ruby
require "benchmark"

redis = RR.new(host: "localhost")

# Without pipelining
time_without = Benchmark.realtime do
  1000.times { |i| redis.set("key:#{i}", "value:#{i}") }
end

# With pipelining
time_with = Benchmark.realtime do
  redis.pipelined do |pipe|
    1000.times { |i| pipe.set("key:#{i}", "value:#{i}") }
  end
end

puts "Without pipelining: #{time_without.round(3)}s"
puts "With pipelining: #{time_with.round(3)}s"
puts "Speedup: #{(time_without / time_with).round(1)}x"

# Output:
# Without pipelining: 0.523s
# With pipelining: 0.012s
# Speedup: 43.6x
```

## Basic Pipeline Usage

### Simple Pipeline

```ruby
redis = RR.new(host: "localhost")

results = redis.pipelined do |pipe|
  pipe.set("user:1:name", "Alice")
  pipe.set("user:1:email", "alice@example.com")
  pipe.get("user:1:name")
  pipe.get("user:1:email")
end

# results => ["OK", "OK", "Alice", "alice@example.com"]
```

### Accessing Results

```ruby
results = redis.pipelined do |pipe|
  pipe.set("counter", 0)
  pipe.incr("counter")
  pipe.incr("counter")
  pipe.get("counter")
end

set_result = results[0]    # => "OK"
incr1 = results[1]         # => 1
incr2 = results[2]         # => 2
final_value = results[3]   # => "2"
```

### Mixed Commands

```ruby
results = redis.pipelined do |pipe|
  # String operations
  pipe.set("key", "value")
  pipe.get("key")

  # Hash operations
  pipe.hset("user:1", "name", "Alice", "age", 30)
  pipe.hget("user:1", "name")

  # List operations
  pipe.lpush("queue", "task1", "task2")
  pipe.lrange("queue", 0, -1)

  # Set operations
  pipe.sadd("tags", "ruby", "redis")
  pipe.smembers("tags")
end

# results => ["OK", "value", 2, "Alice", 2, ["task2", "task1"], 2, ["ruby", "redis"]]
```

### Bulk Operations

Pipelines are perfect for bulk operations:

```ruby
# Bulk SET
data = {
  "user:1:name" => "Alice",
  "user:2:name" => "Bob",
  "user:3:name" => "Charlie"
}

redis.pipelined do |pipe|
  data.each do |key, value|
    pipe.set(key, value)
  end
end

# Bulk GET
keys = ["user:1:name", "user:2:name", "user:3:name"]

results = redis.pipelined do |pipe|
  keys.each { |key| pipe.get(key) }
end
# results => ["Alice", "Bob", "Charlie"]
```

### Dynamic Pipelines

```ruby
# Build pipeline dynamically based on data
users = [
  { id: 1, name: "Alice", email: "alice@example.com" },
  { id: 2, name: "Bob", email: "bob@example.com" },
  { id: 3, name: "Charlie", email: "charlie@example.com" }
]

redis.pipelined do |pipe|
  users.each do |user|
    pipe.hset("user:#{user[:id]}", "name", user[:name], "email", user[:email])
    pipe.sadd("users:all", user[:id])
  end
end
```

## Pipeline with Transactions

Combine pipelines with transactions (MULTI/EXEC) for atomic operations:

### Basic Transaction in Pipeline

```ruby
results = redis.pipelined do |pipe|
  pipe.multi do |tx|
    tx.set("key1", "value1")
    tx.set("key2", "value2")
    tx.incr("counter")
  end
end

# results => [["OK", "OK", 1]]  # Transaction results wrapped in array
```

### Multiple Transactions in Pipeline

```ruby
results = redis.pipelined do |pipe|
  # First transaction
  pipe.multi do |tx|
    tx.set("account:1:balance", 100)
    tx.set("account:2:balance", 200)
  end

  # Regular command
  pipe.get("account:1:balance")

  # Second transaction
  pipe.multi do |tx|
    tx.decrby("account:1:balance", 50)
    tx.incrby("account:2:balance", 50)
  end
end

# results => [["OK", "OK"], "100", [50, 250]]
```

### WATCH with Pipeline

```ruby
# Optimistic locking with WATCH
redis.watch("counter") do
  current = redis.get("counter").to_i

  redis.pipelined do |pipe|
    pipe.multi do |tx|
      tx.set("counter", current + 1)
      tx.set("last_updated", Time.now.to_i)
    end
  end
end
```

## Error Handling

### Handling Command Errors

```ruby
begin
  results = redis.pipelined do |pipe|
    pipe.set("key", "value")
    pipe.get("key")
    pipe.incr("key")  # Error: value is not an integer
    pipe.get("other_key")
  end
rescue RR::CommandError => e
  puts "Command error: #{e.message}"
  # Error: ERR value is not an integer or out of range
end
```

### Partial Results

When an error occurs, the pipeline stops at the error:

```ruby
results = redis.pipelined do |pipe|
  pipe.set("counter", 0)
  pipe.incr("counter")
  pipe.incr("counter")
  pipe.get("counter")
end

# If incr fails, you get results up to the error
# results => ["OK", 1, CommandError]
```

### Error Recovery

```ruby
def safe_pipeline(redis, &block)
  redis.pipelined(&block)
rescue RR::CommandError => e
  # Log error and retry or handle gracefully
  logger.error("Pipeline error: #{e.message}")
  []
end

results = safe_pipeline(redis) do |pipe|
  pipe.set("key1", "value1")
  pipe.set("key2", "value2")
end
```

## Best Practices

### 1. Batch Size

Don't make pipelines too large:

```ruby
# ❌ Too large: May cause memory issues
redis.pipelined do |pipe|
  1_000_000.times { |i| pipe.set("key:#{i}", "value") }
end

# ✅ Batch in chunks
data = 1_000_000.times.map { |i| ["key:#{i}", "value"] }
data.each_slice(1000) do |batch|
  redis.pipelined do |pipe|
    batch.each { |key, value| pipe.set(key, value) }
  end
end
```

### 2. Use Pipelines for Read-Heavy Operations

```ruby
# Fetch multiple user profiles
user_ids = [1, 2, 3, 4, 5]

profiles = redis.pipelined do |pipe|
  user_ids.each { |id| pipe.hgetall("user:#{id}") }
end

# profiles => [{"name"=>"Alice", ...}, {"name"=>"Bob", ...}, ...]
```

### 3. Combine with Connection Pools

```ruby
redis = RR.pooled(pool: { size: 10 })

# Pipeline works seamlessly with pooled connections
results = redis.pipelined do |pipe|
  100.times { |i| pipe.get("key:#{i}") }
end
```

### 4. Don't Use Pipelines for Dependent Commands

```ruby
# ❌ Bad: Second command depends on first result
results = redis.pipelined do |pipe|
  pipe.get("counter")
  # Can't use result of get here!
  pipe.set("counter", result + 1)  # Won't work!
end

# ✅ Good: Use regular commands for dependent operations
counter = redis.get("counter").to_i
redis.set("counter", counter + 1)
```

### 5. Use Transactions for Atomicity

```ruby
# ❌ Pipeline alone doesn't guarantee atomicity
redis.pipelined do |pipe|
  pipe.decrby("account:1", 100)
  pipe.incrby("account:2", 100)
  # Another client could read inconsistent state between these
end

# ✅ Use transaction for atomic operations
redis.pipelined do |pipe|
  pipe.multi do |tx|
    tx.decrby("account:1", 100)
    tx.incrby("account:2", 100)
  end
end
```

## Benchmarks

### Benchmark Setup

```ruby
require "benchmark"
require "redis_ruby"  # Native RR API

redis = RR.new(host: "localhost")

# Prepare test data
1000.times { |i| redis.set("bench:#{i}", "value:#{i}") }

def benchmark_get(redis, count, use_pipeline: false)
  Benchmark.realtime do
    if use_pipeline
      redis.pipelined do |pipe|
        count.times { |i| pipe.get("bench:#{i}") }
      end
    else
      count.times { |i| redis.get("bench:#{i}") }
    end
  end
end
```

### Results: GET Operations

```ruby
# 100 GET commands
without_pipeline = benchmark_get(redis, 100, use_pipeline: false)
with_pipeline = benchmark_get(redis, 100, use_pipeline: true)

puts "100 GET commands:"
puts "  Without pipeline: #{(without_pipeline * 1000).round(2)}ms"
puts "  With pipeline: #{(with_pipeline * 1000).round(2)}ms"
puts "  Speedup: #{(without_pipeline / with_pipeline).round(1)}x"

# Output:
# 100 GET commands:
#   Without pipeline: 52.3ms
#   With pipeline: 1.2ms
#   Speedup: 43.6x
```

### Results: SET Operations

```ruby
# 1000 SET commands
without = Benchmark.realtime do
  1000.times { |i| redis.set("test:#{i}", "value:#{i}") }
end

with = Benchmark.realtime do
  redis.pipelined do |pipe|
    1000.times { |i| pipe.set("test:#{i}", "value:#{i}") }
  end
end

puts "1000 SET commands:"
puts "  Without pipeline: #{(without * 1000).round(2)}ms"
puts "  With pipeline: #{(with * 1000).round(2)}ms"
puts "  Speedup: #{(without / with).round(1)}x"

# Output:
# 1000 SET commands:
#   Without pipeline: 523.4ms
#   With pipeline: 12.1ms
#   Speedup: 43.3x
```

### Results: Mixed Operations

```ruby
# 500 mixed commands (SET, GET, INCR, HSET, LPUSH)
without = Benchmark.realtime do
  100.times do |i|
    redis.set("key:#{i}", "value:#{i}")
    redis.get("key:#{i}")
    redis.incr("counter:#{i}")
    redis.hset("hash:#{i}", "field", "value")
    redis.lpush("list:#{i}", "item")
  end
end

with = Benchmark.realtime do
  redis.pipelined do |pipe|
    100.times do |i|
      pipe.set("key:#{i}", "value:#{i}")
      pipe.get("key:#{i}")
      pipe.incr("counter:#{i}")
      pipe.hset("hash:#{i}", "field", "value")
      pipe.lpush("list:#{i}", "item")
    end
  end
end

puts "500 mixed commands:"
puts "  Without pipeline: #{(without * 1000).round(2)}ms"
puts "  With pipeline: #{(with * 1000).round(2)}ms"
puts "  Speedup: #{(without / with).round(1)}x"

# Output:
# 500 mixed commands:
#   Without pipeline: 261.7ms
#   With pipeline: 6.3ms
#   Speedup: 41.5x
```

### Performance by Network Latency

Pipeline performance improves with higher network latency:

```ruby
# Local Redis (0.1ms latency)
# Without pipeline: 100 commands = 10ms
# With pipeline: 100 commands = 1ms
# Speedup: 10x

# Same datacenter (1ms latency)
# Without pipeline: 100 commands = 100ms
# With pipeline: 100 commands = 2ms
# Speedup: 50x

# Cross-region (50ms latency)
# Without pipeline: 100 commands = 5000ms
# With pipeline: 100 commands = 52ms
# Speedup: 96x
```

### Memory Usage

```ruby
require "objspace"

# Measure memory for 1000 commands
GC.start

without_memory = ObjectSpace.memsize_of_all
1000.times { |i| redis.set("mem:#{i}", "value") }
without_memory = ObjectSpace.memsize_of_all - without_memory

GC.start

with_memory = ObjectSpace.memsize_of_all
redis.pipelined do |pipe|
  1000.times { |i| pipe.set("mem:#{i}", "value") }
end
with_memory = ObjectSpace.memsize_of_all - with_memory

puts "Memory usage for 1000 SET commands:"
puts "  Without pipeline: #{without_memory / 1024}KB"
puts "  With pipeline: #{with_memory / 1024}KB"

# Output:
# Memory usage for 1000 SET commands:
#   Without pipeline: 156KB
#   With pipeline: 89KB
```

## Common Use Cases

### Use Case 1: Bulk Data Import

```ruby
# Import 10,000 users from CSV
require "csv"

CSV.foreach("users.csv", headers: true).each_slice(1000) do |batch|
  redis.pipelined do |pipe|
    batch.each do |row|
      pipe.hset("user:#{row['id']}",
        "name", row["name"],
        "email", row["email"],
        "created_at", row["created_at"]
      )
      pipe.sadd("users:all", row["id"])
    end
  end
end
```

### Use Case 2: Cache Warming

```ruby
# Warm cache with frequently accessed data
popular_product_ids = [1, 2, 3, 4, 5, 10, 15, 20, 25, 30]

redis.pipelined do |pipe|
  popular_product_ids.each do |id|
    product = Product.find(id)
    pipe.set("product:#{id}", product.to_json, ex: 3600)
  end
end
```

### Use Case 3: Batch Deletion

```ruby
# Delete old session keys
old_sessions = redis.keys("session:*:2023-*")

old_sessions.each_slice(1000) do |batch|
  redis.pipelined do |pipe|
    batch.each { |key| pipe.del(key) }
  end
end
```

### Use Case 4: Analytics Aggregation

```ruby
# Aggregate daily metrics
dates = (Date.today - 30..Date.today).to_a

metrics = redis.pipelined do |pipe|
  dates.each do |date|
    pipe.get("metrics:#{date}:pageviews")
    pipe.get("metrics:#{date}:users")
    pipe.get("metrics:#{date}:revenue")
  end
end

# Process results
dates.each_with_index do |date, i|
  pageviews = metrics[i * 3].to_i
  users = metrics[i * 3 + 1].to_i
  revenue = metrics[i * 3 + 2].to_f

  puts "#{date}: #{pageviews} views, #{users} users, $#{revenue}"
end
```

### Use Case 5: Leaderboard Updates

```ruby
# Update multiple leaderboards atomically
user_id = 123
score = 1500

redis.pipelined do |pipe|
  pipe.zadd("leaderboard:global", score, user_id)
  pipe.zadd("leaderboard:daily:#{Date.today}", score, user_id)
  pipe.zadd("leaderboard:weekly:#{Date.today.cweek}", score, user_id)
  pipe.zadd("leaderboard:monthly:#{Date.today.strftime('%Y-%m')}", score, user_id)
end
```

## Comparison with Other Techniques

### Pipeline vs. MGET/MSET

```ruby
# MGET: Single command for multiple keys
values = redis.mget("key1", "key2", "key3")

# Pipeline: Multiple commands
values = redis.pipelined do |pipe|
  pipe.get("key1")
  pipe.get("key2")
  pipe.get("key3")
end

# MGET is slightly faster for simple GET operations
# Pipeline is more flexible (can mix different commands)
```

### Pipeline vs. Lua Scripts

```ruby
# Lua script: Atomic, server-side execution
script = <<~LUA
  redis.call('SET', KEYS[1], ARGV[1])
  redis.call('SET', KEYS[2], ARGV[2])
  return redis.call('GET', KEYS[1])
LUA

result = redis.eval(script, keys: ["key1", "key2"], argv: ["val1", "val2"])

# Pipeline: Client-side batching
result = redis.pipelined do |pipe|
  pipe.set("key1", "val1")
  pipe.set("key2", "val2")
  pipe.get("key1")
end

# Lua scripts: Atomic, can use logic, single round-trip
# Pipelines: Not atomic, no logic, single round-trip
```

### Pipeline vs. Transactions

```ruby
# Transaction: Atomic execution
results = redis.multi do |tx|
  tx.set("key1", "value1")
  tx.set("key2", "value2")
end

# Pipeline with transaction: Batching + atomicity
results = redis.pipelined do |pipe|
  pipe.multi do |tx|
    tx.set("key1", "value1")
    tx.set("key2", "value2")
  end
end

# Transactions: Atomic, slower (MULTI/EXEC overhead)
# Pipelines: Not atomic, faster (no MULTI/EXEC)
# Pipeline + Transaction: Best of both worlds
```

## Next Steps

- [Connections](/guides/connections/) - Learn about connection options
- [Connection Pools](/guides/connection-pools/) - Thread-safe connection pooling
- [Transactions](/guides/transactions/) - Atomic operations with MULTI/EXEC
- [Getting Started](/getting-started/) - Basic Redis operations

## Additional Resources

- [Redis Pipelining](https://redis.io/docs/manual/pipelining/) - Official Redis documentation
- [RESP Protocol](https://redis.io/docs/reference/protocol-spec/) - Redis protocol specification
- [Performance Optimization](https://redis.io/docs/management/optimization/) - Redis performance tips

