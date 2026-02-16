---
layout: default
title: Home
nav_order: 1
description: "High-performance Redis client for Ruby with RESP3 support, connection pooling, and full support for JSON, Search, Time Series, and more."
permalink: /
---

# redis-ruby
{: .fs-9 }

A high-performance, modern Redis client for Ruby with full RESP3 support, connection pooling, and comprehensive support for JSON, Search, Time Series, and all Redis features.
{: .fs-6 .fw-300 }

[Get Started](/redis-ruby/getting-started/){: .btn .btn-primary .fs-5 .mb-4 .mb-md-0 .mr-2 }
[View on GitHub](https://github.com/redis/redis-ruby){: .btn .fs-5 .mb-4 .mb-md-0 }

---

## Features

### 🚀 High Performance
Optimized for speed with RESP3 protocol support, connection pooling, and efficient I/O operations.

### 🔌 Connection Management
Thread-safe and fiber-aware connection pooling with support for TCP, Unix sockets, and TLS.

### 📦 Advanced Features
Full support for Search, JSON, Time Series, Probabilistic data structures, and more.

### 🔄 Advanced Features
Pipelines, transactions, Pub/Sub, Lua scripting, client-side caching, and distributed locks.

### 🌐 Cluster & Sentinel
Native support for Redis Cluster and Redis Sentinel for high availability deployments.

### 🎯 Modern Ruby
Built for Ruby 3.2+ with YJIT support for maximum performance.

---

## Quick Start

### Installation

Add to your Gemfile:

```ruby
gem 'redis-ruby'
```

Or install directly:

```bash
gem install redis-ruby
```

### Basic Usage

```ruby
require 'redis_ruby'

# Create a client
client = RR.new(url: "redis://localhost:6379")

# Basic operations
client.set("key", "value")
value = client.get("key")  # => "value"

# Hash operations
client.hset("user:1", "name", "Alice", "age", "30")
client.hgetall("user:1")  # => {"name" => "Alice", "age" => "30"}

# Lists
client.lpush("queue", "job1", "job2", "job3")
client.lrange("queue", 0, -1)  # => ["job3", "job2", "job1"]
```

### Connection Pooling

```ruby
# Thread-safe connection pool
client = RR.pooled(
  url: "redis://localhost:6379",
  pool: { size: 10, timeout: 5 }
)

# Use in multi-threaded environment
10.times.map do
  Thread.new { client.get("key") }
end.each(&:join)
```

### Async Operations

```ruby
require 'async'

Async do
  client = RR.async(url: "redis://localhost:6379")
  
  # Non-blocking operations
  client.set("key", "value")
  value = client.get("key")
end
```

### Two APIs, One Client

redis-ruby provides both **low-level** (direct Redis commands) and **idiomatic** (fluent Ruby) APIs:

```ruby
# Low-level API - Direct Redis commands
redis.hset("user:1", "name", "Alice", "age", "30")
redis.zadd("leaderboard", 100, "alice", 85, "bob")
redis.geoadd("cities", -122.4, 37.7, "sf")

# Idiomatic API - Fluent, chainable, Ruby-esque
redis.hash("user:1").set(name: "Alice", age: 30)
redis.sset("leaderboard").add(alice: 100, bob: 85)
redis.geo("cities").add(sf: [-122.4, 37.7])

# Advanced features with DSL
redis.index("products") do
  on :hash
  prefix "product:"
  text :name, sortable: true
  numeric :price, sortable: true
end

# JSON with chainable proxy
redis.json("user:1")
  .set(name: "Alice", age: 30)
  .increment(:age, 1)
  .get(:name)  # => "Alice"
```

See the [API Overview](/redis-ruby/guides/api-overview/) and [Idiomatic API Guide](/redis-ruby/guides/idiomatic-api/) for complete examples.

---

## Documentation

- [Getting Started](/redis-ruby/getting-started/) - Installation and basic usage
- [API Overview](/redis-ruby/guides/api-overview/) - Low-level vs Idiomatic APIs
- [Idiomatic API Guide](/redis-ruby/guides/idiomatic-api/) - Complete DSL reference
- [Guides](/redis-ruby/guides/) - In-depth guides for all features
- [Examples](/redis-ruby/examples/) - Runnable code examples
- [Advanced Features](/redis-ruby/advanced-features/) - JSON, Search, Time Series, and more

---

## Performance

redis-ruby is optimized for high performance:

- **42% faster** than redis-rb for GET operations (8,606 vs 6,044 ops/s)
- **Matches hiredis** performance without C extensions
- **RESP3 protocol** for reduced overhead
- **Connection pooling** for concurrent workloads
- **YJIT support** for Ruby 3.3+

See the [Performance Guide](/redis-ruby/performance/) for detailed benchmarks.

---

## Community

- [GitHub Issues](https://github.com/redis/redis-ruby/issues) - Bug reports and feature requests
- [GitHub Discussions](https://github.com/redis/redis-ruby/discussions) - Questions and discussions
- [Contributing Guide](/redis-ruby/contributing/) - How to contribute

---

## License

redis-ruby is released under the [MIT License](https://github.com/redis/redis-ruby/blob/main/LICENSE).

