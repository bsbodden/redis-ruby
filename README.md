<div align="center">

# redis-ruby

**A next-generation Redis client for Ruby**

*Pure Ruby • RESP3 Protocol • Full Redis Stack • Production Ready*

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ruby](https://img.shields.io/badge/Ruby-3.1%2B-red.svg)](https://www.ruby-lang.org/)
[![Redis](https://img.shields.io/badge/Redis-6.0%2B-dc382d.svg)](https://redis.io/)

[Getting Started](#getting-started) • [Documentation](#documentation) • [API Reference](#command-reference) • [Contributing](#contributing)

</div>

---

## Why redis-ruby?

| **Performance** | **Complete** | **Modern** |
|:---:|:---:|:---:|
| 2x faster pipelines than redis-rb | 500+ commands across all Redis modules | Pure Ruby RESP3, no native extensions |
| 49% fewer memory allocations | JSON, Search, TimeSeries, Vector, Bloom | Async/Fibers, Connection Pooling |
| YJIT optimized for Ruby 3.4+ | Cluster, Sentinel, Pub/Sub, Streams | Distributed Locks, Client Caching |

---

## Getting Started

### Installation

Add to your Gemfile:

```ruby
gem "redis-ruby"
```

Or install directly:

```bash
gem install redis-ruby
```

### Quick Example

```ruby
require "redis_ruby"

# Connect to Redis
redis = RedisRuby.new(url: "redis://localhost:6379")

# Basic operations
redis.set("user:1:name", "Alice")
redis.get("user:1:name")  # => "Alice"

# JSON documents
redis.json_set("user:1", "$", { name: "Alice", age: 30, tags: ["admin"] })
redis.json_get("user:1", "$.name")  # => ["Alice"]

# Full-text search
redis.ft_search("idx:users", "@name:Alice")

# Vector similarity
redis.vadd("embeddings", "doc:1", embedding_vector, "{\"title\": \"Hello\"}")
redis.vsim("embeddings", embedding_vector, count: 10)

redis.close
```

### Redis Setup

redis-ruby works with any Redis deployment:

| Deployment | Connection |
|------------|------------|
| **Local Redis** | `redis://localhost:6379` |
| **Redis Cloud** | `rediss://user:pass@host:port` |
| **Docker** | `docker run -p 6379:6379 redis/redis-stack` |
| **Sentinel** | Use `RedisRuby.sentinel(...)` |
| **Cluster** | Use `RedisRuby.cluster(...)` |

---

## Features

### Client Types

```ruby
# Synchronous - simple, blocking operations
redis = RedisRuby.new(url: "redis://localhost:6379")

# Pooled - thread-safe with connection pooling
redis = RedisRuby.pooled(url: "redis://localhost:6379", pool: { size: 10 })

# Async - fiber-aware for concurrent operations
Async do
  redis = RedisRuby.async(url: "redis://localhost:6379")
  redis.set("key", "value")
end

# Async Pooled - fiber-safe pooling for maximum concurrency
Async do
  redis = RedisRuby.async_pooled(url: "redis://localhost:6379", pool: { limit: 10 })
end

# Sentinel - automatic failover
redis = RedisRuby.sentinel(
  sentinels: [{ host: "sentinel1", port: 26379 }],
  service_name: "mymaster"
)

# Cluster - automatic sharding
redis = RedisRuby.cluster(
  nodes: ["redis://node1:6379", "redis://node2:6379", "redis://node3:6379"]
)
```

### Pipelines & Transactions

```ruby
# Pipeline - batch commands, single round-trip
results = redis.pipelined do |pipe|
  pipe.set("key1", "value1")
  pipe.set("key2", "value2")
  pipe.get("key1")
end
# => ["OK", "OK", "value1"]

# Transaction - atomic execution with MULTI/EXEC
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

### Distributed Locking

```ruby
lock = RedisRuby::Lock.new(redis, "resource:1", timeout: 30)

# Block syntax - automatically releases
lock.synchronize do
  # Critical section
end

# Manual control
if lock.acquire(blocking: true, blocking_timeout: 5)
  begin
    # Do work
    lock.extend(additional_time: 10)  # Extend if needed
  ensure
    lock.release
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

# Background subscriber (non-blocking)
subscriber = RedisRuby::Subscriber.new(redis)
subscriber.on_message { |channel, msg| process(msg) }
subscriber.subscribe("events")
thread = subscriber.run_in_thread

# Pattern subscriptions
redis.psubscribe("user:*") do |on|
  on.pmessage { |pattern, channel, message| puts message }
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

# Cached reads - automatic invalidation via RESP3
value = cache.get("frequently:read:key")  # From cache after first read
```

---

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

# Search with query builder
query = RedisRuby::Search::Query.new("laptop")
  .filter_numeric("price", 500, 1500)
  .sort_by("price", :asc)
  .limit(0, 10)
  .highlight(fields: ["name"])

results = query.execute(redis, "idx:products")

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

---

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

---

## Performance

Benchmarked with Ruby 3.4 + YJIT against redis-rb with hiredis:

```
Pipeline 100 commands:  redis-ruby is 2.11x faster
Pipeline 10 commands:   redis-ruby is 1.33x faster
Single operations:      redis-ruby is 1.15x faster
Memory allocations:     49% fewer than redis-rb
```

### YJIT Optimization

redis-ruby is optimized for YJIT with consistent object shapes:

```ruby
# Check YJIT status
RedisRuby::Utils::YJITMonitor.enabled?       # => true
RedisRuby::Utils::YJITMonitor.ratio_in_yjit  # => 97.5
RedisRuby::Utils::YJITMonitor.status_report  # Detailed report
```

---

## Requirements

- **Ruby** 3.1+ (3.4+ recommended for YJIT)
- **Redis** 6.0+ (Redis Stack 7.2+ for modules, Redis 8+ for Vector Sets)

### Optional Dependencies

```ruby
gem "async"       # For AsyncClient
gem "async-pool"  # For AsyncPooledClient
```

---

## Development

```bash
# Clone and setup
git clone https://github.com/yourname/redis-ruby.git
cd redis-ruby
bundle install

# Run tests
bundle exec rake test          # All tests
bundle exec rake test:unit     # Unit tests only
bundle exec rake test:integration  # Integration tests

# Run benchmarks
RUBYOPT="--yjit" bundle exec rake benchmark

# Linting
bundle exec rubocop -A
```

### DevContainer

This project includes a devcontainer with Redis Stack:

1. Open in VS Code with Dev Containers extension
2. Click "Reopen in Container"
3. Run `bundle exec rake test`

---

## Contributing

Bug reports and pull requests are welcome on GitHub. This project is intended to be a safe, welcoming space for collaboration.

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

---

## License

The gem is available as open source under the terms of the [MIT License](LICENSE).

---

## Acknowledgments

Inspired by [Lettuce](https://github.com/redis/lettuce), [redis-py](https://github.com/redis/redis-py), [Jedis](https://github.com/redis/jedis), and [async-redis](https://github.com/socketry/async-redis).

