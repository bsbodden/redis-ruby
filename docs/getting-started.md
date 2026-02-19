---
layout: default
title: Getting Started
nav_order: 2
permalink: /getting-started/
---

# Getting Started with redis-ruby

This guide will help you get started with redis-ruby, from installation to your first Redis commands.

## Prerequisites

- **Ruby 3.2+** (Ruby 3.3+ recommended for YJIT support)
- **Redis 6.2+** (Redis 8.0+ recommended)

## Installation

### Install Redis

**Recommended: Redis 8.6 (latest stable)**

Start a Redis instance via Docker:

```bash
# Redis 8.6 (recommended)
docker run -p 6379:6379 -it redis:latest

# Or specify version explicitly
docker run -p 6379:6379 -it redis:8.6

# Alpine variant (smaller image)
docker run -p 6379:6379 -it redis:8.6-alpine
```

For more installation options, see the [official Redis downloads page](https://redis.io/downloads/).

Or install Redis locally:

```bash
# macOS
brew install redis
brew services start redis

# Ubuntu/Debian
sudo apt-get install redis-server
sudo systemctl start redis-server

# From source
wget https://download.redis.io/redis-stable.tar.gz
tar -xzvf redis-stable.tar.gz
cd redis-stable
make
make install
```

### Install redis-ruby

Add to your Gemfile:

```ruby
gem "redis-ruby"
```

Then run:

```bash
bundle install
```

Or install directly:

```bash
gem install redis-ruby
```

## Basic Usage

### Connecting to Redis

```ruby
require "redis_ruby"  # Native RR API

# Connect to localhost:6379 (default)
redis = RR.new

# Connect with URL
redis = RR.new(url: "redis://localhost:6379")

# Connect with options
redis = RR.new(
  host: "localhost",
  port: 6379,
  db: 0,
  timeout: 5.0
)

# Test connection
redis.ping  # => "PONG"
```

### String Operations

```ruby
# SET and GET
redis.set("user:1:name", "Alice")
redis.get("user:1:name")  # => "Alice"

# SET with expiration
redis.set("session:abc", "data", ex: 3600)  # Expires in 1 hour

# SET with options
redis.set("key", "value", nx: true)  # Only set if not exists
redis.set("key", "value", xx: true)  # Only set if exists

# Multiple SET/GET
redis.mset("k1", "v1", "k2", "v2")
redis.mget("k1", "k2")  # => ["v1", "v2"]

# Increment/Decrement
redis.set("counter", 0)
redis.incr("counter")  # => 1
redis.incrby("counter", 5)  # => 6
redis.decr("counter")  # => 5
```

### Hash Operations

```ruby
# Set hash fields
redis.hset("user:1", "name", "Alice", "age", 30, "city", "NYC")

# Get hash field
redis.hget("user:1", "name")  # => "Alice"

# Get all hash fields
redis.hgetall("user:1")  # => {"name"=>"Alice", "age"=>"30", "city"=>"NYC"}

# Get multiple fields
redis.hmget("user:1", "name", "age")  # => ["Alice", "30"]

# Check if field exists
redis.hexists("user:1", "name")  # => true

# Delete field
redis.hdel("user:1", "city")

# Increment hash field
redis.hincrby("user:1", "age", 1)  # => 31
```

### List Operations

```ruby
# Push to list
redis.lpush("queue", "task1", "task2")  # Push to left
redis.rpush("queue", "task3")  # Push to right

# Pop from list
redis.lpop("queue")  # => "task2" (pop from left)
redis.rpop("queue")  # => "task3" (pop from right)

# Get list range
redis.lrange("queue", 0, -1)  # Get all elements

# List length
redis.llen("queue")  # => 1

# Blocking pop (waits for element)
redis.blpop("queue", timeout: 5)  # => ["queue", "task1"]
```

### Set Operations

```ruby
# Add members to set
redis.sadd("tags", "ruby", "redis", "database")

# Get all members
redis.smembers("tags")  # => ["ruby", "redis", "database"]

# Check membership
redis.sismember("tags", "ruby")  # => true

# Remove member
redis.srem("tags", "database")

# Set operations
redis.sadd("set1", "a", "b", "c")
redis.sadd("set2", "b", "c", "d")

redis.sinter("set1", "set2")  # => ["b", "c"] (intersection)
redis.sunion("set1", "set2")  # => ["a", "b", "c", "d"] (union)
redis.sdiff("set1", "set2")  # => ["a"] (difference)
```

## Next Steps

- [Connection Options](/guides/connections/) - Learn about connection configuration
- [Connection Pools](/guides/connection-pools/) - Use connection pooling for multi-threaded apps
- [Pipelines](/guides/pipelines/) - Batch commands for better performance
- [Pub/Sub](/guides/pubsub/) - Publish/subscribe messaging
- [Transactions](/guides/transactions/) - Atomic operations with MULTI/EXEC
- [Advanced Features](/advanced-features/) - Use JSON, Search, Time Series, and more
- [Examples](/examples/) - More code examples

## Getting Help

- [GitHub Issues](https://github.com/redis-developer/redis-ruby/issues) - Report bugs or request features
- [Redis Documentation](https://redis.io/docs/) - Official Redis documentation
- [Redis University](https://university.redis.com/) - Free Redis courses
- [Redis Community](https://redis.io/community/) - Join the Redis community

