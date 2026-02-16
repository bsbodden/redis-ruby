---
layout: default
title: Basic Usage Example
parent: Examples
nav_order: 1
permalink: /examples/basic-usage/
---

# Basic Usage Example

This example demonstrates the fundamentals of using redis-ruby, including connecting to Redis, basic operations, and working with different data types.

## Prerequisites

- Ruby 3.2+ installed
- Redis 6.2+ running on localhost:6379
- redis-ruby gem installed (`gem install redis-ruby`)

## Complete Example

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "redis_ruby"  # Native RR API

# Connect to Redis
redis = RR.new(url: "redis://localhost:6379")

puts "Connected to Redis!"
puts "Redis version: #{redis.info["redis_version"]}"
puts

# ============================================================================
# String Operations
# ============================================================================

puts "=== String Operations ==="

# SET and GET
redis.set("greeting", "Hello, Redis!")
greeting = redis.get("greeting")
puts "GET greeting: #{greeting}"

# SET with expiration (EX = seconds)
redis.set("temp_key", "This will expire", ex: 10)
puts "SET temp_key with 10 second expiration"

# Check TTL (time to live)
ttl = redis.ttl("temp_key")
puts "TTL temp_key: #{ttl} seconds"

# INCR and DECR
redis.set("counter", 0)
redis.incr("counter")
redis.incr("counter")
redis.incrby("counter", 5)
counter = redis.get("counter").to_i
puts "Counter value: #{counter}"  # => 7

# MGET and MSET (multiple keys)
redis.mset("key1", "value1", "key2", "value2", "key3", "value3")
values = redis.mget("key1", "key2", "key3")
puts "MGET result: #{values.inspect}"

puts

# ============================================================================
# Hash Operations
# ============================================================================

puts "=== Hash Operations ==="

# HSET and HGET
redis.hset("user:1", "name", "Alice", "email", "alice@example.com", "age", 30)
name = redis.hget("user:1", "name")
puts "User name: #{name}"

# HGETALL - get all fields
user = redis.hgetall("user:1")
puts "User data: #{user.inspect}"

# HINCRBY - increment hash field
redis.hincrby("user:1", "age", 1)
age = redis.hget("user:1", "age")
puts "User age after increment: #{age}"

# HEXISTS - check if field exists
exists = redis.hexists("user:1", "email")
puts "Email field exists: #{exists}"

puts

# ============================================================================
# List Operations
# ============================================================================

puts "=== List Operations ==="

# LPUSH and RPUSH
redis.lpush("tasks", "task1", "task2", "task3")
redis.rpush("tasks", "task4")

# LRANGE - get range of elements
tasks = redis.lrange("tasks", 0, -1)
puts "All tasks: #{tasks.inspect}"

# LPOP and RPOP
first_task = redis.lpop("tasks")
last_task = redis.rpop("tasks")
puts "First task: #{first_task}, Last task: #{last_task}"

# LLEN - get list length
length = redis.llen("tasks")
puts "Remaining tasks: #{length}"

puts

# ============================================================================
# Set Operations
# ============================================================================

puts "=== Set Operations ==="

# SADD - add members to set
redis.sadd("tags", "ruby", "redis", "database")
redis.sadd("tags", "ruby")  # Duplicate ignored

# SMEMBERS - get all members
tags = redis.smembers("tags")
puts "Tags: #{tags.inspect}"

# SISMEMBER - check membership
is_member = redis.sismember("tags", "ruby")
puts "Is 'ruby' a tag? #{is_member}"

# SCARD - get set size
size = redis.scard("tags")
puts "Number of tags: #{size}"

# Set operations
redis.sadd("set1", "a", "b", "c")
redis.sadd("set2", "b", "c", "d")

# SINTER - intersection
intersection = redis.sinter("set1", "set2")
puts "Intersection: #{intersection.inspect}"

# SUNION - union
union = redis.sunion("set1", "set2")
puts "Union: #{union.inspect}"

# SDIFF - difference
diff = redis.sdiff("set1", "set2")
puts "Difference: #{diff.inspect}"

puts

# ============================================================================
# Sorted Set Operations
# ============================================================================

puts "=== Sorted Set Operations ==="

# ZADD - add members with scores
redis.zadd("leaderboard", 100, "player1", 200, "player2", 150, "player3")

# ZRANGE - get range by rank
top_players = redis.zrange("leaderboard", 0, -1, withscores: true)
puts "Leaderboard (ascending): #{top_players.inspect}"

# ZREVRANGE - get range in reverse order
top_players_desc = redis.zrevrange("leaderboard", 0, 2, withscores: true)
puts "Top 3 players: #{top_players_desc.inspect}"

# ZSCORE - get score of member
score = redis.zscore("leaderboard", "player2")
puts "Player2 score: #{score}"

# ZINCRBY - increment score
redis.zincrby("leaderboard", 50, "player1")
new_score = redis.zscore("leaderboard", "player1")
puts "Player1 new score: #{new_score}"

# ZRANK - get rank of member
rank = redis.zrank("leaderboard", "player1")
puts "Player1 rank: #{rank}"

puts

# ============================================================================
# Key Operations
# ============================================================================

puts "=== Key Operations ==="

# EXISTS - check if key exists
exists = redis.exists("greeting")
puts "Key 'greeting' exists: #{exists}"

# DEL - delete keys
redis.del("temp_key")
puts "Deleted temp_key"

# KEYS - find keys by pattern (use with caution in production)
all_keys = redis.keys("*")
puts "All keys: #{all_keys.inspect}"

# EXPIRE - set expiration
redis.set("session", "abc123")
redis.expire("session", 3600)  # Expire in 1 hour
ttl = redis.ttl("session")
puts "Session TTL: #{ttl} seconds"

# PERSIST - remove expiration
redis.persist("session")
ttl = redis.ttl("session")
puts "Session TTL after persist: #{ttl}"  # => -1 (no expiration)

puts

# ============================================================================
# Error Handling
# ============================================================================

puts "=== Error Handling ==="

begin
  # Try to increment a non-numeric value
  redis.set("text", "hello")
  redis.incr("text")
rescue RR::CommandError => e
  puts "Caught error: #{e.message}"
end

begin
  # Try to connect to invalid host
  bad_redis = RR.new(host: "invalid-host", timeout: 1)
  bad_redis.ping
rescue RR::ConnectionError => e
  puts "Connection error: #{e.message}"
end

puts

# ============================================================================
# Cleanup
# ============================================================================

puts "=== Cleanup ==="

# Delete all test keys
redis.del("greeting", "counter", "key1", "key2", "key3")
redis.del("user:1", "tasks", "tags", "set1", "set2")
redis.del("leaderboard", "session", "text")

puts "Cleaned up test keys"

# Close connection
redis.close
puts "Connection closed"
```

## Running the Example

Save the code to a file (e.g., `basic_usage.rb`) and run:

```bash
ruby basic_usage.rb
```

## Expected Output

```
Connected to Redis!
Redis version: 7.2.0

=== String Operations ===
GET greeting: Hello, Redis!
SET temp_key with 10 second expiration
TTL temp_key: 10 seconds
Counter value: 7
MGET result: ["value1", "value2", "value3"]

=== Hash Operations ===
User name: Alice
User data: {"name"=>"Alice", "email"=>"alice@example.com", "age"=>"30"}
User age after increment: 31
Email field exists: true

=== List Operations ===
All tasks: ["task3", "task2", "task1", "task4"]
First task: task3, Last task: task4
Remaining tasks: 2

=== Set Operations ===
Tags: ["ruby", "redis", "database"]
Is 'ruby' a tag? true
Number of tags: 3
Intersection: ["b", "c"]
Union: ["a", "b", "c", "d"]
Difference: ["a"]

=== Sorted Set Operations ===
Leaderboard (ascending): [["player1", 100.0], ["player3", 150.0], ["player2", 200.0]]
Top 3 players: [["player2", 200.0], ["player3", 150.0], ["player1", 100.0]]
Player2 score: 200.0
Player1 new score: 150.0
Player1 rank: 1

=== Key Operations ===
Key 'greeting' exists: 1
Deleted temp_key
All keys: ["greeting", "counter", "key1", "key2", "key3", "user:1", "tasks", "tags", "set1", "set2", "leaderboard", "session", "text"]
Session TTL: 3600 seconds
Session TTL after persist: -1

=== Error Handling ===
Caught error: ERR value is not an integer or out of range
Connection error: Connection refused - connect(2) for "invalid-host" port 6379

=== Cleanup ===
Cleaned up test keys
Connection closed
```

## Key Takeaways

1. **Connection** - Use `RR.new` to connect to Redis
2. **String Operations** - GET, SET, INCR, MGET, MSET for simple key-value storage
3. **Hashes** - Store structured data with HSET, HGET, HGETALL
4. **Lists** - Ordered collections with LPUSH, RPUSH, LRANGE, LPOP
5. **Sets** - Unique collections with SADD, SMEMBERS, set operations
6. **Sorted Sets** - Scored collections with ZADD, ZRANGE, ZSCORE
7. **Key Management** - EXISTS, DEL, EXPIRE, TTL for key lifecycle
8. **Error Handling** - Catch `RR::CommandError` and `RR::ConnectionError`

## Next Steps

- [Connection Pooling Example](/examples/connection-pooling/) - Thread-safe connection pools
- [Pipelining Example](/examples/pipelining/) - Batch operations for performance
- [Pub/Sub Example](/examples/pubsub/) - Real-time messaging
- [Advanced Features Example](/examples/advanced-features/) - JSON, Search, and more

## Additional Resources

- [Getting Started Guide](/getting-started/) - Detailed installation and setup
- [Redis Commands](https://redis.io/commands/) - Complete command reference
- [Redis Data Types](https://redis.io/docs/data-types/) - Understanding Redis data structures
