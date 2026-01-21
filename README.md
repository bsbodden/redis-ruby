# redis-ruby

A next-generation Redis client for Ruby, designed to be the most complete, performant, and developer-friendly Redis library available.

## Highlights

- **Pure Ruby RESP3** - No native extensions, works everywhere Ruby runs
- **2x Faster** than redis-rb with hiredis for pipelined operations
- **Full Redis Stack** - JSON, Search, TimeSeries, BloomFilter, VectorSet
- **All Client Types** - Sync, Async (Fibers), Pooled, Sentinel
- **Production Ready** - Comprehensive test suite, battle-tested

## Performance

```
Pipeline 100 commands: redis-ruby is 2.11x faster than redis-rb
Pipeline 10 commands:  redis-ruby is 1.33x faster than redis-rb
Memory allocations:    49% fewer allocations than baseline
```

Benchmarked with Ruby 3.4 + YJIT against redis-rb with hiredis.

## Installation

Add to your Gemfile:

```ruby
gem "redis-ruby"
```

## Quick Start

```ruby
require "redis_ruby"

# Simple connection
redis = RedisRuby.new(host: "localhost", port: 6379)

# Or use a URL
redis = RedisRuby.new(url: "redis://localhost:6379/0")

# Basic operations
redis.set("greeting", "Hello, Redis!")
redis.get("greeting")  # => "Hello, Redis!"

# With expiration
redis.set("session", "abc123", ex: 3600)

# Close when done
redis.close
```

## Connection Types

```ruby
# TCP (default)
redis = RedisRuby.new(host: "localhost", port: 6379)

# SSL/TLS
redis = RedisRuby.new(url: "rediss://secure.redis.example.com:6379")

# Unix socket
redis = RedisRuby.new(url: "unix:///var/run/redis/redis.sock")

# With authentication
redis = RedisRuby.new(url: "redis://:password@localhost:6379")
```

## Client Variants

```ruby
# Synchronous (default)
redis = RedisRuby::Client.new(host: "localhost")

# Thread-safe with connection pooling
redis = RedisRuby::PooledClient.new(
  host: "localhost",
  pool_size: 10,
  pool_timeout: 5.0
)

# Async with Fiber Scheduler (Ruby 3.0+)
Async do
  redis = RedisRuby::AsyncClient.new(host: "localhost")
  redis.set("key", "value")
end

# Sentinel with automatic failover
redis = RedisRuby::SentinelClient.new(
  master_name: "mymaster",
  sentinels: [
    { host: "sentinel1", port: 26379 },
    { host: "sentinel2", port: 26379 },
    { host: "sentinel3", port: 26379 }
  ]
)
```

## Pipelines & Transactions

```ruby
# Pipeline - batch commands for efficiency
results = redis.pipelined do |pipe|
  pipe.set("key1", "value1")
  pipe.set("key2", "value2")
  pipe.get("key1")
  pipe.get("key2")
end
# => ["OK", "OK", "value1", "value2"]

# Transaction - atomic operations
results = redis.multi do |tx|
  tx.incr("counter")
  tx.incr("counter")
  tx.get("counter")
end
# => [1, 2, "2"]

# With optimistic locking
redis.watch("balance") do
  current = redis.get("balance").to_i
  redis.multi do |tx|
    tx.set("balance", current + 100)
  end
end
```

## Redis Stack Modules

### RedisJSON

```ruby
redis.json_set("user:1", "$", { name: "Alice", age: 30 })
redis.json_get("user:1", "$.name")  # => ["Alice"]
redis.json_numincrby("user:1", "$.age", 1)
```

### RediSearch

```ruby
# Create index
redis.ft_create("idx:users",
  "ON", "JSON",
  "PREFIX", 1, "user:",
  "SCHEMA",
    "$.name", "AS", "name", "TEXT",
    "$.age", "AS", "age", "NUMERIC"
)

# Search
redis.ft_search("idx:users", "@name:Alice")
```

### RedisTimeSeries

```ruby
redis.ts_create("sensor:temp", labels: { location: "office" })
redis.ts_add("sensor:temp", "*", 23.5)
redis.ts_range("sensor:temp", "-", "+")
```

### RedisBloom

```ruby
redis.bf_reserve("usernames", 0.01, 1000)
redis.bf_add("usernames", "alice")
redis.bf_exists("usernames", "alice")  # => true
```

### VectorSet (Redis 8+)

```ruby
redis.vs_create("embeddings", dim: 384, m: 16, ef: 200)
redis.vs_add("embeddings", "doc:1", [0.1, 0.2, ...])
redis.vs_search("embeddings", [0.15, 0.25, ...], count: 10)
```

## Sentinel

```ruby
redis = RedisRuby::SentinelClient.new(
  master_name: "mymaster",
  sentinels: [
    { host: "sentinel1", port: 26379 },
    { host: "sentinel2", port: 26379 }
  ],
  role: :master,  # or :replica for read replicas
  timeout: 5.0
)

# Automatic failover handling - client reconnects transparently
redis.set("key", "value")  # Works even after master changes
```

## Command Coverage

| Category | Commands | Status |
|----------|----------|--------|
| Strings | 18 | ✅ |
| Keys | 23 | ✅ |
| Hashes | 16 | ✅ |
| Lists | 21 | ✅ |
| Sets | 17 | ✅ |
| Sorted Sets | 22 | ✅ |
| JSON | 20 | ✅ |
| Search | 28 | ✅ |
| TimeSeries | 17 | ✅ |
| BloomFilter | 49 | ✅ |
| VectorSet | 13 | ✅ |
| Sentinel | 17 | ✅ |
| **Total** | **261+** | |

## Coming Soon

- Redis Cluster support
- Pub/Sub
- Streams
- Lua scripting
- Geo, HyperLogLog, Bitmap commands

See [DEVELOPMENT_PLAN.md](DEVELOPMENT_PLAN.md) for the full roadmap.

## Development

```bash
# Clone the repository
git clone https://github.com/yourusername/redis-ruby.git
cd redis-ruby

# Install dependencies
bundle install

# Run tests (requires Redis on localhost:6379 or use devcontainer)
bundle exec rake test

# Run benchmarks
RUBYOPT="--yjit" bundle exec ruby benchmarks/compare_comprehensive.rb

# Run linting
bundle exec rubocop
```

### Using DevContainer

This project includes a devcontainer with Redis Stack pre-configured:

1. Open in VS Code with Dev Containers extension
2. Click "Reopen in Container"
3. Run `bundle exec rake test`

## Requirements

- Ruby 3.1+ (3.4+ recommended for best performance with YJIT)
- Redis 6.0+ (Redis Stack 7.2+ for module commands)

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

Inspired by [Lettuce](https://github.com/redis/lettuce), [redis-py](https://github.com/redis/redis-py), and [async-redis](https://github.com/socketry/async-redis).
