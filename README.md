<div align="center">

[![Redis](https://redis.io/wp-content/uploads/2024/04/Logotype.svg?auto=webp&quality=85,75&width=120)](https://redis.io)

# redis-ruby

**A next-generation Redis client for Ruby**

*Pure Ruby RESP3 &bull; 500+ Commands &bull; Full Redis Stack &bull; Production Ready*

[![CI](https://github.com/redis/redis-ruby/actions/workflows/ci.yml/badge.svg)](https://github.com/redis/redis-ruby/actions)
[![codecov](https://codecov.io/gh/redis/redis-ruby/graph/badge.svg)](https://codecov.io/gh/redis/redis-ruby)
[![MIT licensed](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/redis/redis-ruby/blob/main/LICENSE)

[![Gem Version](https://badge.fury.io/rb/redis-ruby.svg)](https://rubygems.org/gems/redis-ruby)
![Gem Downloads](https://img.shields.io/gem/dt/redis-ruby)
![Ruby](https://img.shields.io/badge/Ruby-3.2%2B-red.svg)

[![Code style: RuboCop](https://img.shields.io/badge/code%20style-RuboCop-blue.svg)](https://github.com/rubocop/rubocop)
![Language](https://img.shields.io/github/languages/top/redis/redis-ruby)
![GitHub last commit](https://img.shields.io/github/last-commit/redis/redis-ruby)

[Installation](#installation) &bull; [Usage](#usage) &bull; [Command Reference](#command-reference) &bull; [Advanced Topics](#advanced-topics) &bull; [Contributing](#contributing)

</div>

---

## How do I Redis?

[Learn for free at Redis University](https://redis.io/learn/university)

[Try the Redis Cloud](https://redis.io/try-free/)

[Dive in developer tutorials](https://redis.io/learn)

[Join the Redis community](https://redis.io/community/)

[Work at Redis](https://redis.io/careers/)

## Installation

Install via RubyGems:

```bash
gem install redis-ruby
```

Or add to your Gemfile:

```ruby
gem "redis-ruby"
```

### Docker Setup

To run a local Redis instance with all modules:

```bash
docker run -p 6379:6379 redis/redis-stack
```

## Supported Redis Versions

redis-ruby is tested against the following Redis versions:

| Redis Version | Status | Notes |
|:---:|:---:|:---|
| **8.0** | Supported | Full feature support including Vector Sets |
| **7.4** | Supported | All Redis Stack modules |
| **7.2** | Supported | All Redis Stack modules |
| **6.2+** | Compatible | Core commands; modules require Redis Stack |

## Usage

### Basic Example

```ruby
require "redis_ruby"

redis = RedisRuby.new(url: "redis://localhost:6379")

redis.set("user:1:name", "Alice")
redis.get("user:1:name")  # => "Alice"

redis.close
```

### Connection Options

```ruby
# Standard TCP
redis = RedisRuby.new(url: "redis://localhost:6379")

# TLS (Redis Cloud, production)
redis = RedisRuby.new(url: "rediss://user:pass@host:port")

# Unix socket
redis = RedisRuby.new(path: "/var/run/redis.sock")

# With options
redis = RedisRuby.new(
  url: "redis://localhost:6379",
  db: 0,
  timeout: 5.0,
  reconnect_attempts: 3
)
```

### Connection Pools

```ruby
# Thread-safe pooled client
redis = RedisRuby.pooled(url: "redis://localhost:6379", pool: { size: 10 })

# Async fiber-safe pool
Async do
  redis = RedisRuby.async_pooled(url: "redis://localhost:6379", pool: { limit: 10 })
  redis.set("key", "value")
end
```

### Redis Commands

```ruby
# Strings
redis.set("key", "value", ex: 3600, nx: true)
redis.get("key")
redis.mset("k1", "v1", "k2", "v2")
redis.incr("counter")

# Hashes
redis.hset("user:1", "name", "Alice", "age", 30)
redis.hgetall("user:1")  # => {"name"=>"Alice", "age"=>"30"}

# Lists
redis.lpush("queue", "task1", "task2")
redis.rpop("queue")

# Sets
redis.sadd("tags", "ruby", "redis")
redis.smembers("tags")

# Sorted Sets
redis.zadd("leaderboard", 100, "alice", 95, "bob")
redis.zrange("leaderboard", 0, -1, withscores: true)

# Geo
redis.geoadd("locations", -122.4194, 37.7749, "San Francisco")
redis.geosearch("locations", longitude: -122.4, latitude: 37.8, byradius: 10, unit: "mi")
```

## Advanced Topics

### Pipelines

Batch commands in a single round-trip for dramatically improved throughput:

```ruby
results = redis.pipelined do |pipe|
  pipe.set("key1", "value1")
  pipe.set("key2", "value2")
  pipe.get("key1")
end
# => ["OK", "OK", "value1"]
```

### Transactions

Atomic execution with `MULTI`/`EXEC`:

```ruby
results = redis.multi do |tx|
  tx.incr("counter")
  tx.incr("counter")
end
# => [1, 2]

# Optimistic locking with WATCH
redis.watch("balance") do
  balance = redis.get("balance").to_i
  redis.multi do |tx|
    tx.set("balance", balance + 100)
  end
end
```

### Pub/Sub

```ruby
# Publishing
redis.publish("events", "user:signup")

# Subscribing (blocking)
redis.subscribe("events", "alerts") do |on|
  on.message { |channel, message| puts "#{channel}: #{message}" }
end

# Pattern subscriptions
redis.psubscribe("user:*") do |on|
  on.pmessage { |pattern, channel, message| puts message }
end
```

### Distributed Locks

```ruby
lock = RedisRuby::Lock.new(redis, "resource:1", timeout: 30)

lock.synchronize do
  # Critical section - lock auto-releases
end

# Manual control
if lock.acquire(blocking: true, blocking_timeout: 5)
  begin
    lock.extend(additional_time: 10)
  ensure
    lock.release
  end
end
```

### Streams

```ruby
# Add entries
redis.xadd("events", "*", { type: "click", user: "alice" })

# Read entries
redis.xread("events", "0")

# Consumer groups
redis.xgroup_create("events", "processors", "$", mkstream: true)
redis.xreadgroup("processors", "worker1", "events", ">", count: 10)
redis.xack("events", "processors", message_id)
```

### Lua Scripting & Functions

```ruby
# Register and call scripts
script = redis.register_script("return redis.call('GET', KEYS[1])")
script.call(keys: ["mykey"])

# Redis Functions (Redis 7.0+)
redis.function_load(lua_library_code, replace: true)
redis.fcall("myfunc", keys: ["key1"], args: ["arg1"])
```

### Client-Side Caching

```ruby
cache = RedisRuby::Cache.new(redis, max_entries: 10_000, ttl: 60)
cache.enable!

value = cache.get("frequently:read:key")  # Cached after first read, auto-invalidated via RESP3
```

### Topologies

```ruby
# Sentinel - automatic failover
redis = RedisRuby.sentinel(
  sentinels: [{ host: "sentinel1", port: 26379 }],
  service_name: "mymaster"
)

# Cluster - automatic sharding
redis = RedisRuby.cluster(
  nodes: ["redis://node1:6379", "redis://node2:6379", "redis://node3:6379"]
)

# Async - fiber-aware for concurrent operations
Async do
  redis = RedisRuby.async(url: "redis://localhost:6379")
  redis.set("key", "value")
end
```

## Redis Stack Modules

### RedisJSON

```ruby
redis.json_set("user:1", "$", { name: "Alice", scores: [95, 87, 92] })
redis.json_get("user:1", "$.name")           # => ["Alice"]
redis.json_arrappend("user:1", "$.scores", 88)
redis.json_numincrby("user:1", "$.scores[0]", 5)
```

### RediSearch

```ruby
# Create index
redis.ft_create("idx:products",
  on: :hash, prefix: ["product:"],
  schema: [
    { name: "name", type: :text },
    { name: "price", type: :numeric, sortable: true },
    { name: "embedding", type: :vector, algorithm: :hnsw, dim: 384 }
  ]
)

# Full-text search
results = redis.ft_search("idx:products", "@name:laptop")

# Aggregation
agg = RedisRuby::Search::AggregateQuery.new("*")
  .group_by("@category", reducers: [
    RedisRuby::Search::Reducer.count.as("count"),
    RedisRuby::Search::Reducer.avg("@price").as("avg_price")
  ])
  .sort_by("@count", :desc)

agg.execute(redis, "idx:products")
```

### RedisTimeSeries

```ruby
redis.ts_create("sensor:temp", labels: { location: "office", type: "temperature" })
redis.ts_add("sensor:temp", "*", 23.5)
redis.ts_range("sensor:temp", "-", "+", aggregation: [:avg, 3600000])
redis.ts_mrange("-", "+", filter: ["location=office"])
```

### Probabilistic Data Structures

```ruby
# Bloom Filter
redis.bf_reserve("usernames", 0.01, 10_000)
redis.bf_add("usernames", "alice")
redis.bf_exists("usernames", "alice")  # => true

# Cuckoo Filter
redis.cf_reserve("sessions", 10_000)
redis.cf_add("sessions", "session:abc")

# Count-Min Sketch
redis.cms_initbyprob("pageviews", 0.001, 0.01)
redis.cms_incrby("pageviews", "/home", 1)

# Top-K
redis.topk_reserve("trending", 10)
redis.topk_add("trending", "item1", "item2")
redis.topk_list("trending")

# T-Digest
redis.tdigest_create("latencies")
redis.tdigest_add("latencies", 0.5, 1.2, 0.8, 2.1)
redis.tdigest_quantile("latencies", 0.5, 0.95, 0.99)
```

### Vector Sets (Redis 8+)

```ruby
redis.vadd("embeddings", "doc:1", vector, "{\"title\": \"Document 1\"}")
redis.vsim("embeddings", query_vector, count: 10)
redis.vemb("embeddings", "doc:1")
redis.vdim("embeddings")
redis.vcard("embeddings")
```

## Command Reference

| Category | Commands | Examples |
|----------|----------|----------|
| **Strings** | 20 | `get`, `set`, `incr`, `append`, `mget` |
| **Keys** | 24+ | `del`, `expire`, `scan`, `scan_iter`, `copy` |
| **Hashes** | 26 | `hset`, `hget`, `hgetall`, `hscan_iter` |
| **Lists** | 22 | `lpush`, `rpop`, `lrange`, `blpop` |
| **Sets** | 17 | `sadd`, `smembers`, `sinter`, `sscan_iter` |
| **Sorted Sets** | 35 | `zadd`, `zrange`, `zscan_iter`, `zpopmin` |
| **Streams** | 22 | `xadd`, `xread`, `xgroup_create`, `xreadgroup` |
| **Pub/Sub** | 32 | `publish`, `subscribe`, `psubscribe` |
| **Geo** | 9 | `geoadd`, `geosearch`, `geodist` |
| **HyperLogLog** | 3 | `pfadd`, `pfcount`, `pfmerge` |
| **Bitmap** | 7 | `setbit`, `getbit`, `bitcount`, `bitfield` |
| **JSON** | 20 | `json_set`, `json_get`, `json_arrappend` |
| **Search** | 38 | `ft_create`, `ft_search`, `ft_aggregate` |
| **TimeSeries** | 21 | `ts_create`, `ts_add`, `ts_range` |
| **Probabilistic** | 49 | `bf_add`, `cf_add`, `cms_incrby`, `topk_add` |
| **Vector Set** | 13 | `vadd`, `vsim`, `vdim`, `vemb` |
| **Scripting** | 11 | `eval`, `evalsha`, `register_script` |
| **Functions** | 9 | `fcall`, `function_load`, `function_list` |
| **ACL** | 13 | `acl_setuser`, `acl_getuser`, `acl_list` |
| **Cluster** | 28 | `cluster_info`, `cluster_nodes` |
| **Sentinel** | 17 | `sentinel_masters`, `sentinel_failover` |
| **Server** | 53 | `info`, `config_get`, `client_list` |
| **Total** | **500+** | |

## Performance

redis-ruby is designed for high performance with Ruby 3.3+ YJIT, achieving competitive or better performance than redis-rb without requiring native extensions.

**Benchmark Summary** (Ruby 3.3.0 + YJIT on Apple Silicon):

| Operation | redis-ruby | vs redis-rb (plain) | vs redis-rb (hiredis) |
|-----------|------------|---------------------|----------------------|
| Single GET | 6,534 ops/s | **1.12x faster** ✓ | 0.82x |
| Single SET | 8,415 ops/s | **1.29x faster** ✓ | **1.39x faster** ✓ |
| Pipeline 10 | 7,815 ops/s | **1.57x faster** ✓ | **1.41x faster** ✓ |
| Pipeline 100 | 4,586 ops/s | **1.31x faster** ✓ | **1.28x faster** ✓ |

**Key Highlights:**
- ✅ **1.12-1.57x faster** than redis-rb (plain Ruby driver) with YJIT
- ✅ **Competitive with redis-rb + hiredis** (native extension) on most operations
- ✅ **Especially fast for pipelined operations** (1.28x-1.57x faster)
- ✅ **Pure Ruby implementation** - no native extensions required
- ⚠️ **YJIT required** for optimal performance (Ruby 3.3+)

See [docs/BENCHMARKS.md](docs/BENCHMARKS.md) for comprehensive benchmark reports including:
- Multiple Ruby versions and configurations
- YJIT enabled/disabled comparisons
- Detailed methodology and recommendations
- Instructions for running benchmarks yourself

## Contributing

Bug reports and pull requests are welcome on [GitHub](https://github.com/redis/redis-ruby).

1. Fork the repository
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Write tests for your changes
4. Ensure all tests pass (`bundle exec rake test`)
5. Ensure code style passes (`bundle exec rubocop`)
6. Commit your changes (`git commit -am 'feat: add some feature'`)
7. Push to the branch (`git push origin my-new-feature`)
8. Create a Pull Request

### Development Setup

```bash
git clone https://github.com/redis/redis-ruby.git
cd redis-ruby
bundle install

bundle exec rake test          # All tests
bundle exec rake test:unit     # Unit tests only
bundle exec rake test:integration  # Integration tests (requires Redis)
bundle exec rubocop            # Linting
```

This project includes a devcontainer with Redis Stack pre-configured.
Open in VS Code with the Dev Containers extension and click "Reopen in Container".

## License

Distributed under the [MIT License](LICENSE).

## Author

redis-ruby is developed and maintained by [Redis Inc](https://redis.io). It can be found [here](https://github.com/redis/redis-ruby), or downloaded from [RubyGems](https://rubygems.org/gems/redis-ruby).

[![Redis](https://redis.io/wp-content/uploads/2024/04/Logotype.svg?auto=webp&quality=85,75&width=120)](https://redis.io)
