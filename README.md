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

**Note:** redis-ruby requires Ruby 3.2+ for full functionality. Ruby 3.3+ is recommended for optimal performance with YJIT support.

---

## How do I Redis?

[Learn for free at Redis University](https://redis.io/learn/university)

[Try the Redis Cloud](https://redis.io/try-free/)

[Dive in developer tutorials](https://redis.io/learn)

[Join the Redis community](https://redis.io/community/)

[Work at Redis](https://redis.io/careers/)

## Installation

Start a Redis instance via Docker:

```bash
# For Redis versions >= 8.0
docker run -p 6379:6379 -it redis:latest

# For Redis versions < 8.0 with Redis Stack modules
docker run -p 6379:6379 -it redis/redis-stack:latest
```

To install redis-ruby, simply:

```bash
gem install redis-ruby
```

Or add to your Gemfile:

```ruby
gem "redis-ruby"
```

## Supported Redis Versions

The most recent version of this library supports Redis version [7.2](https://github.com/redis/redis/blob/7.2/00-RELEASENOTES), [7.4](https://github.com/redis/redis/blob/7.4/00-RELEASENOTES), [8.0](https://github.com/redis/redis/blob/8.0/00-RELEASENOTES) and [8.2](https://github.com/redis/redis/blob/8.2/00-RELEASENOTES).

The table below highlights version compatibility of the most-recent library versions and Redis versions:

| Library version | Supported Redis versions |
|-----------------|--------------------------|
| >= 1.0.0 | Version 6.2 to current |

redis-ruby is tested against the following Redis versions:

| Redis Version | Status | Notes |
|:---:|:---:|:---|
| **8.2** | Supported | Latest features |
| **8.0** | Supported | Full feature support including Vector Sets |
| **7.4** | Supported | All Redis Stack modules |
| **7.2** | Supported | All Redis Stack modules |
| **6.2+** | Compatible | Core commands; modules require Redis Stack |

## Usage

### Basic Example

```ruby
require "redis_ruby"  # Native RR API

redis = RR.new(url: "redis://localhost:6379")

redis.set("foo", "bar")
redis.get("foo")  # => "bar"

redis.close
```

All responses are returned as strings by default. To receive decoded strings with proper encoding, the client handles UTF-8 encoding automatically. For more connection options, see the [Connection Options](#connection-options) section below.

#### RESP3 Support

redis-ruby uses RESP3 (Redis Serialization Protocol version 3) by default, which provides improved performance and native support for new data types. RESP3 is supported on Redis 6.0+.

```ruby
# RESP3 is enabled by default
redis = RR.new(url: "redis://localhost:6379")

# To use RESP2 (for compatibility with older Redis versions)
redis = RR.new(url: "redis://localhost:6379", protocol: 2)
```

### Connection Options

```ruby
# Standard TCP
redis = RR.new(url: "redis://localhost:6379")

# TLS (Redis Cloud, production)
redis = RR.new(url: "rediss://user:pass@host:port")

# Unix socket
redis = RR.new(path: "/var/run/redis.sock")

# With options
redis = RR.new(
  url: "redis://localhost:6379",
  db: 0,
  timeout: 5.0,
  reconnect_attempts: 3
)
```

### Connection Pools

By default, redis-ruby uses a connection pool to manage connections. Each instance of a RR class receives its own connection pool. You can however define your own connection pool:

```ruby
# Thread-safe pooled client
redis = RR.pooled(url: "redis://localhost:6379", pool: { size: 10 })

# Async fiber-safe pool
Async do
  redis = RR.async_pooled(url: "redis://localhost:6379", pool: { limit: 10 })
  redis.set("key", "value")
end
```

Alternatively, you might want to look at [Async connections](#topologies), or [Cluster connections](#topologies), or even Async Cluster connections.

### Observability & Metrics

redis-ruby provides built-in instrumentation for monitoring Redis operations in production:

```ruby
# Create instrumentation instance
instrumentation = RR::Instrumentation.new

# Pass to client
redis = RR.new(instrumentation: instrumentation)

# Execute commands
redis.set("user:1", "Alice")
redis.get("user:1")

# Get metrics
instrumentation.command_count                    # => 2
instrumentation.command_count_by_name("SET")     # => 1
instrumentation.average_latency("GET")           # => 0.001234 (seconds)

# Export metrics snapshot
snapshot = instrumentation.snapshot
# => { total_commands: 2, total_errors: 0, commands: {...}, errors: {} }

# Hook into command lifecycle
instrumentation.after_command do |command, args, duration|
  logger.warn("Slow command: #{command}") if duration > 0.1
end
```

**Features:**
- Command count and latency tracking
- Error tracking by type
- Before/after command callbacks
- Thread-safe metrics collection
- Zero overhead when disabled
- Prometheus/OpenTelemetry integration examples

See [docs/guides/observability.md](https://redis.github.io/redis-ruby/guides/observability.html) for complete documentation.

### Circuit Breaker and Health Checks

Prevent cascading failures with built-in circuit breaker support:

```ruby
# Create a circuit breaker
circuit_breaker = RR::CircuitBreaker.new(
  failure_threshold: 5,        # Open after 5 consecutive failures
  success_threshold: 2,        # Close after 2 consecutive successes
  timeout: 60.0,               # Stay open for 60 seconds
  half_open_timeout: 30.0      # Test recovery after 30 seconds
)

# Use with client
redis = RR.new(circuit_breaker: circuit_breaker)

# Health checks
if redis.healthy?
  puts "Redis is healthy"
else
  puts "Redis is unhealthy or circuit is open"
end

# Handle circuit breaker errors
begin
  redis.get("key")
rescue RR::CircuitBreakerOpenError
  # Circuit is open - use fallback
  get_from_cache("key")
end
```

**Features:**
- Three states: CLOSED (normal), OPEN (failing), HALF_OPEN (testing recovery)
- Automatic state transitions based on failures/successes
- Health check methods with custom commands
- Metrics and monitoring support
- Works with both Client and PooledClient

See [docs/guides/circuit-breaker.md](https://redis.github.io/redis-ruby/guides/circuit-breaker.html) for complete documentation.

### Connection Event Callbacks

Monitor and react to connection lifecycle events for logging, monitoring, and debugging:

```ruby
client = RR::Client.new(host: "localhost", port: 6379)

# Register callbacks for connection events
client.register_connection_callback(:connected) do |event|
  puts "Connected to #{event[:host]}:#{event[:port]}"
end

client.register_connection_callback(:disconnected) do |event|
  puts "Disconnected from #{event[:host]}:#{event[:port]}"
end

client.register_connection_callback(:reconnected) do |event|
  puts "Reconnected to #{event[:host]}:#{event[:port]}"
end

client.register_connection_callback(:error) do |event|
  puts "Connection error: #{event[:error].message}"
end
```

**Features:**
- Four event types: `:connected`, `:disconnected`, `:reconnected`, `:error`
- Multiple callbacks per event type
- Event data includes host, port, timestamp, and error details
- Error-safe: callback errors don't break connections
- Works with TCP, SSL, and Unix socket connections

See [docs/guides/connection-callbacks.md](https://redis.github.io/redis-ruby/guides/connection-callbacks.html) for complete documentation.

### Redis Commands

There is built-in support for all of the [out-of-the-box Redis commands](https://redis.io/commands). They are exposed using the raw Redis command names (`HSET`, `HGETALL`, etc.) in lowercase, except where a word (i.e. `del`) would conflict with Ruby keywords. The complete set of commands can be found in the [Command Reference](#command-reference) section.

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

The [official Redis command documentation](https://redis.io/commands) does a great job of explaining each command in detail. redis-ruby attempts to adhere to the official command syntax. There are a few exceptions:

- **MULTI/EXEC**: These are implemented as part of the transaction support. Transactions are wrapped with the MULTI and EXEC statements by default when executed. See more about [Transactions](#transactions) below.

- **SUBSCRIBE/LISTEN**: Similar to pipelines, PubSub is implemented as a separate interface as it places the underlying connection in a state where it can't execute non-pubsub commands. Calling the `subscribe` or `psubscribe` methods will enter PubSub mode. You can only call `publish` from the regular Redis client. See more about [Pub/Sub](#pubsub) below.

### Pipelines

The following is a basic example of a [Redis pipeline](https://redis.io/docs/manual/pipelining/), a method to optimize round-trip calls, by batching Redis commands, and receiving their results as a list:

```ruby
results = redis.pipelined do |pipe|
  pipe.set("foo", 5)
  pipe.set("bar", 18.5)
  pipe.set("blee", "hello world!")
end
# => ["OK", "OK", "OK"]
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

### PubSub

The following example shows how to utilize [Redis Pub/Sub](https://redis.io/docs/manual/pubsub/) to subscribe to specific channels:

```ruby
# Publishing
redis.publish("events", "user:signup")

# Subscribing (blocking)
redis.subscribe("my-first-channel", "my-second-channel") do |on|
  on.message { |channel, message| puts "#{channel}: #{message}" }
end

# Pattern subscriptions
redis.psubscribe("user:*") do |on|
  on.pmessage { |pattern, channel, message| puts message }
end
```

### Distributed Locks

```ruby
lock = RR::Lock.new(redis, "resource:1", timeout: 30)

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
cache = RR::Cache.new(redis, max_entries: 10_000, ttl: 60)
cache.enable!

value = cache.get("frequently:read:key")  # Cached after first read, auto-invalidated via RESP3
```

### Topologies

```ruby
# Sentinel - automatic failover
redis = RR.sentinel(
  sentinels: [{ host: "sentinel1", port: 26379 }],
  service_name: "mymaster"
)

# Cluster - automatic sharding
redis = RR.cluster(
  nodes: ["redis://node1:6379", "redis://node2:6379", "redis://node3:6379"]
)

# Redis Enterprise Discovery Service - automatic endpoint discovery
redis = RR.discovery(
  nodes: [{ host: "node1.redis.example.com", port: 8001 }],
  database_name: "my-database"
)

# DNS-based load balancing - multiple A records with round-robin
redis = RR.dns(
  hostname: "redis.example.com",
  port: 6379,
  dns_strategy: :round_robin  # or :random
)

# Async - fiber-aware for concurrent operations
Async do
  redis = RR.async(url: "redis://localhost:6379")
  redis.set("key", "value")
end
```

## Idiomatic Ruby API

redis-ruby provides both a **low-level API** (direct Redis commands) and an **idiomatic Ruby API** (DSLs and fluent builders) for all Redis data structures and features. The idiomatic API offers:

- **Symbol-based method names** - Use `:name`, `:score` instead of strings
- **DSL blocks** - Configure complex structures with clean, declarative syntax
- **Method chaining** - Build queries and operations fluently
- **Composite keys** - Automatic key joining with symbols (e.g., `redis.hash(:user, 123)` → `"user:123"`)
- **Ruby conventions** - Keyword arguments, ranges, and familiar patterns
- **Unified interface** - Consistent API across all data structures

Both APIs work side-by-side - use whichever fits your style!

### Core Data Structures (Idiomatic)

```ruby
# Hashes - Chainable proxy with keyword arguments
redis.hash("user:1").set(name: "Alice", age: 30)
redis.hash("user:1").get(:name)                    # => "Alice"
redis.hash("user:1").increment(:age, 1)            # => 31

# Sorted Sets - Symbol-based members
redis.sset("leaderboard").add(alice: 100, bob: 85)
redis.sset("leaderboard").score(:alice)      # => 100.0
redis.sset("leaderboard").range(0, 2)        # Top 3

# Lists - Fluent operations
redis.list("queue").push("job1", "job2", "job3")
redis.list("queue").pop                            # => "job3"
redis.list("queue")[0]                             # First element

# Sets - Chainable operations
redis.redis_set("tags").add("ruby", "redis")
redis.redis_set("tags").member?("ruby")            # => true
redis.redis_set("tags").random(2)                  # Random 2 members

# Strings & Counters - Specialized interfaces
redis.string("cache").set("data", ex: 3600)
redis.counter("views").increment(10)               # => 10
redis.counter("views").value                       # => 10

# Geo - Symbol-based locations
redis.geo("cities").add(sf: [-122.4, 37.7], nyc: [-74.0, 40.7])
redis.geo("cities").distance(:sf, :nyc, unit: :mi) # => 2565.88

# HyperLogLog - Chainable operations
redis.hll("visitors").add("user1", "user2")
redis.hll("visitors").count                # => 2

# Bitmaps - Fluent bit operations
redis.bitmap("attendance").set_bit(0, 1).set_bit(1, 1)
redis.bitmap("attendance").count                   # => 2

# Probabilistic - Bloom, Cuckoo, CMS, Top-K
redis.bloom("emails").add("alice@example.com")
redis.bloom("emails").exists?("alice@example.com") # => true
redis.topk("trending").add("product1")
redis.topk("trending").list                        # Top-K items
```

See the [API Overview](https://redis.github.io/redis-ruby/guides/api-overview/) for a complete comparison of low-level vs idiomatic APIs.

### Search & Query (Idiomatic)

```ruby
# Create index with DSL
redis.index("products") do
  on :hash
  prefix "product:"

  text :name, sortable: true
  text :description
  numeric :price, sortable: true
  tag :category
  vector :embedding, algorithm: :hnsw, dim: 384
end

# Fluent query builder
results = redis.search("products")
  .query("laptop")
  .filter(:price, 500..1500)
  .sort_by(:price, :asc)
  .limit(0, 10)
  .execute
```

**Compare with low-level API:**

```ruby
# Low-level API (still works!)
redis.ft_create("products",
  "ON", "HASH",
  "PREFIX", 1, "product:",
  "SCHEMA",
    "name", "TEXT", "SORTABLE",
    "description", "TEXT",
    "price", "NUMERIC", "SORTABLE",
    "category", "TAG")
```

### JSON (Idiomatic)

```ruby
# Chainable proxy with composite keys
redis.json(:user, 1)
  .set(name: "Alice", age: 30, scores: [95, 87, 92])

# Symbol-based paths
redis.json("user:1").get(:name)  # => "Alice"

# Method chaining
redis.json("user:1")
  .increment(:age, 1)
  .append(:scores, 88)
  .get(:scores)  # => [95, 87, 92, 88]

# Ruby ranges for array operations
redis.json("user:1").array_trim(:scores, 0..2)
```

### Time Series (Idiomatic)

```ruby
# Create with DSL and automatic compaction rules
redis.time_series("metrics:raw") do
  retention 3600000  # 1 hour
  labels resolution: "raw"

  compact_to "metrics:hourly", :avg, 3600000 do
    retention 86400000  # 24 hours
    labels resolution: "hourly"
  end
end

# Chainable operations
redis.ts("temperature:sensor1")
  .add(Time.now.to_i * 1000, 23.5)
  .add(Time.now.to_i * 1000 + 1000, 24.0)

# Fluent query builder
results = redis.ts_query("temperature:sensor1")
  .from("-")
  .to("+")
  .aggregate(:avg, 300000)  # 5 minute buckets
  .execute
```

### Vector Sets (Idiomatic)

```ruby
# Chainable proxy for vector operations
vectors = redis.vectors("product:embeddings")

# Add vectors with metadata
vectors
  .add("product_1", [0.1, 0.2, 0.3, 0.4], category: "electronics", price: 299.99)
  .add("product_2", [0.2, 0.3, 0.4, 0.5], category: "books", price: 19.99)

# Fluent search builder with filtering
query_vector = [0.15, 0.25, 0.35, 0.45]
results = vectors.search(query_vector)
  .filter(".category == 'electronics'")
  .limit(10)
  .with_scores
  .with_metadata
  .execute

# Vector operations
vectors.get("product_1")                    # Get vector
vectors.metadata("product_1")               # Get metadata
vectors.set_metadata("product_1", on_sale: true)  # Update metadata
vectors.count                               # Total vectors
```

**See the [full documentation](https://redis.github.io/redis-ruby/) for complete API reference and examples.**

## Redis Stack Modules

### RedisJSON

```ruby
redis.json_set("user:1", "$", { name: "Alice", scores: [95, 87, 92] })
redis.json_get("user:1", "$.name")           # => ["Alice"]
redis.json_arrappend("user:1", "$.scores", 88)
redis.json_numincrby("user:1", "$.scores[0]", 5)
```

### RediSearch

**Note:** redis-ruby uses a client-side default dialect for Redis' search and query capabilities. By default, the client uses dialect version 2, automatically appending `DIALECT 2` to commands like `FT.AGGREGATE` and `FT.SEARCH`.

**Important**: Be aware that the query dialect may impact the results returned. If needed, you can specify a different dialect version in your queries.

```ruby
# Create index
redis.ft_create("idx:products",
  on: :hash, prefix: ["product:"],
  schema: [
    { name: "name", type: :text },
    { name: "lastname", type: :text },
    { name: "price", type: :numeric, sortable: true },
    { name: "embedding", type: :vector, algorithm: :hnsw, dim: 384 }
  ]
)

redis.hset("product:1", "name", "Laptop")
redis.hset("product:1", "lastname", "Pro")

# Full-text search with default DIALECT 2
query = "@name: Laptop Pro"
results = redis.ft_search("idx:products", query)

# Query with explicit DIALECT 1 (if needed)
results = redis.ft_search("idx:products", query, dialect: 1)

# Aggregation
agg = RR::Search::AggregateQuery.new("*")
  .group_by("@category", reducers: [
    RR::Search::Reducer.count.as("count"),
    RR::Search::Reducer.avg("@price").as("avg_price")
  ])
  .sort_by("@count", :desc)

agg.execute(redis, "idx:products")
```

You can find further details in the [query dialect documentation](https://redis.io/docs/latest/develop/interact/search-and-query/advanced-concepts/dialects/).

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

redis-ruby is designed for high performance with Ruby 3.3+ YJIT, achieving competitive performance with redis-rb + hiredis (native C extension) without requiring native extensions.

**Benchmark Summary** (Ruby 3.3.0 + YJIT on Apple Silicon):

### vs redis-rb + hiredis (native C extension)

| Operation | redis-ruby | redis-rb + hiredis | Comparison |
|-----------|------------|-------------------|------------|
| Single GET | 8,606 ops/s | 8,592 ops/s | **1.00x** (tied) ✓ |
| Single SET | 8,547 ops/s | 8,420 ops/s | **1.02x faster** ✓ |
| Pipeline 10 | 7,863 ops/s | 7,518 ops/s | **1.05x faster** ✓ |
| Pipeline 100 | 5,064 ops/s | 4,329 ops/s | **1.17x faster** ✓ |

### vs redis-rb (plain Ruby)

| Operation | redis-ruby | redis-rb (plain) | Comparison |
|-----------|------------|------------------|------------|
| Single GET | 8,606 ops/s | 8,354 ops/s | **1.03x faster** ✓ |
| Single SET | 8,547 ops/s | 8,445 ops/s | **1.01x faster** ✓ |
| Pipeline 10 | 7,863 ops/s | 7,448 ops/s | **1.06x faster** ✓ |
| Pipeline 100 | 5,064 ops/s | 4,304 ops/s | **1.18x faster** ✓ |

**Key Highlights:**
- ✅ **Matches redis-rb + hiredis** (native C extension) for single operations
- ✅ **1.05-1.18x faster** for pipelined operations
- ✅ **Pure Ruby implementation** - no native extensions required
- ✅ **42% GET performance improvement** from optimizations (6,044 → 8,606 ops/s)
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
