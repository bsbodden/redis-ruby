---
layout: default
title: Pipelining Example
parent: Examples
nav_order: 3
permalink: /examples/pipelining/
---

# Pipelining Example

This example demonstrates how to use pipelining to batch multiple Redis commands for dramatic performance improvements.

## Prerequisites

- Ruby 3.2+ installed
- Redis 6.2+ running on localhost:6379
- redis-ruby gem installed (`gem install redis-ruby`)

## Complete Example

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "redis_ruby"
require "benchmark"

puts "=== Pipelining Example ===\n\n"

redis = RedisRuby.new(url: "redis://localhost:6379")

# ============================================================================
# Basic Pipelining
# ============================================================================

puts "1. Basic pipelining..."

results = redis.pipelined do |pipe|
  pipe.set("user:1:name", "Alice")
  pipe.set("user:1:email", "alice@example.com")
  pipe.get("user:1:name")
  pipe.get("user:1:email")
end

puts "   Results: #{results.inspect}\n\n"

# ============================================================================
# Performance Comparison
# ============================================================================

puts "2. Performance comparison: Without vs With pipelining..."

# Without pipelining
time_without = Benchmark.realtime do
  100.times { |i| redis.set("key:#{i}", "value:#{i}") }
end

# With pipelining
time_with = Benchmark.realtime do
  redis.pipelined do |pipe|
    100.times { |i| pipe.set("key:#{i}", "value:#{i}") }
  end
end

puts "   Without pipelining (100 SETs): #{(time_without * 1000).round(2)}ms"
puts "   With pipelining (100 SETs): #{(time_with * 1000).round(2)}ms"
puts "   Speedup: #{(time_without / time_with).round(1)}x\n\n"

# ============================================================================
# Bulk Data Import
# ============================================================================

puts "3. Bulk data import..."

users = [
  { id: 1, name: "Alice", email: "alice@example.com", age: 30 },
  { id: 2, name: "Bob", email: "bob@example.com", age: 25 },
  { id: 3, name: "Charlie", email: "charlie@example.com", age: 35 }
]

redis.pipelined do |pipe|
  users.each do |user|
    pipe.hset("user:#{user[:id]}", "name", user[:name], "email", user[:email], "age", user[:age])
    pipe.sadd("users:all", user[:id])
  end
end

puts "   Imported #{users.size} users\n\n"

# ============================================================================
# Bulk Data Retrieval
# ============================================================================

puts "4. Bulk data retrieval..."

user_ids = [1, 2, 3]

profiles = redis.pipelined do |pipe|
  user_ids.each { |id| pipe.hgetall("user:#{id}") }
end

profiles.each_with_index do |profile, i|
  puts "   User #{user_ids[i]}: #{profile.inspect}"
end

puts

# ============================================================================
# Pipeline with Transactions
# ============================================================================

puts "5. Pipeline with transactions..."

results = redis.pipelined do |pipe|
  pipe.multi do |tx|
    tx.set("account:1:balance", 100)
    tx.set("account:2:balance", 200)
  end

  pipe.get("account:1:balance")

  pipe.multi do |tx|
    tx.decrby("account:1:balance", 50)
    tx.incrby("account:2:balance", 50)
  end
end

puts "   Transaction results: #{results.inspect}\n\n"

# ============================================================================
# Batch Deletion
# ============================================================================

puts "6. Batch deletion..."

# Create test keys
100.times { |i| redis.set("temp:#{i}", "value") }

# Delete in batches
(0...100).each_slice(10) do |batch|
  redis.pipelined do |pipe|
    batch.each { |i| pipe.del("temp:#{i}") }
  end
end

puts "   Deleted 100 keys in batches of 10\n\n"

# ============================================================================
# Leaderboard Updates
# ============================================================================

puts "7. Leaderboard updates..."

player_scores = [
  { id: "player1", score: 1500 },
  { id: "player2", score: 2000 },
  { id: "player3", score: 1750 }
]

redis.pipelined do |pipe|
  player_scores.each do |player|
    pipe.zadd("leaderboard:global", player[:score], player[:id])
    pipe.zadd("leaderboard:daily", player[:score], player[:id])
    pipe.zadd("leaderboard:weekly", player[:score], player[:id])
  end
end

puts "   Updated leaderboards for #{player_scores.size} players\n\n"

# ============================================================================
# Cleanup
# ============================================================================

puts "8. Cleanup..."

redis.del("user:1:name", "user:1:email")
redis.del("user:1", "user:2", "user:3", "users:all")
redis.del("account:1:balance", "account:2:balance")
redis.del("leaderboard:global", "leaderboard:daily", "leaderboard:weekly")
100.times { |i| redis.del("key:#{i}") }

redis.close
puts "   Cleaned up and closed connection\n\n"
```

## Running the Example

```bash
ruby pipelining.rb
```

## Key Takeaways

1. **Performance** - Pipelining reduces network round-trips (40-50x faster)
2. **Batch Operations** - Perfect for bulk imports, exports, and updates
3. **Transactions** - Combine pipelines with MULTI/EXEC for atomicity
4. **Batch Size** - Process in chunks (e.g., 1000 commands per pipeline)

## Next Steps

- [Pub/Sub Example](/examples/pubsub/) - Real-time messaging
- [Pipelines Guide](/guides/pipelines/) - Detailed pipelining documentation

