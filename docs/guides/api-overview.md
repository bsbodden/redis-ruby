---
layout: default
title: API Overview
parent: Guides
nav_order: 0
permalink: /guides/api-overview/
---

# API Overview
{: .no_toc }

redis-ruby provides two complementary APIs: a **low-level command API** for direct Redis operations and an **idiomatic Ruby API** for fluent, chainable operations.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Two APIs, One Client

redis-ruby offers flexibility in how you interact with Redis:

### Low-Level Command API

Direct mapping to Redis commands - explicit, predictable, and familiar to Redis users:

```ruby
# Direct Redis commands
redis.set("key", "value")
redis.hset("user:1", "name", "Alice", "age", "30")
redis.zadd("leaderboard", 100, "alice", 85, "bob")
redis.lpush("queue", "job1", "job2")
```

**When to use:**
- You're familiar with Redis commands
- You need explicit control
- You're migrating from another Redis client
- You prefer the official Redis command syntax

### Idiomatic Ruby API

Fluent, chainable interface with Ruby conventions - discoverable, readable, and Ruby-esque:

```ruby
# Idiomatic Ruby API
redis.string("key").set("value")
redis.hash("user:1").set(name: "Alice", age: 30)
redis.sorted_set("leaderboard").add(alice: 100, bob: 85)
redis.list("queue").push("job1", "job2")
```

**When to use:**
- You prefer Ruby conventions (symbols, keyword args, blocks)
- You want method chaining and fluent builders
- You value IDE autocomplete and discoverability
- You're building a Ruby-first application

{: .note }
Both APIs work side-by-side on the same client instance. Mix and match as needed!

---

## Core Data Structures

### Strings

| Low-Level API | Idiomatic API |
|:--------------|:--------------|
| `redis.set("key", "value")` | `redis.string("key").set("value")` |
| `redis.get("key")` | `redis.string("key").get` |
| `redis.incr("counter")` | `redis.counter("counter").increment` |
| `redis.append("key", "text")` | `redis.string("key").append("text")` |

[View String/Counter DSL →](/redis-ruby/guides/idiomatic-api/#strings--counters)

### Hashes

| Low-Level API | Idiomatic API |
|:--------------|:--------------|
| `redis.hset("user:1", "name", "Alice")` | `redis.hash("user:1").set(name: "Alice")` |
| `redis.hget("user:1", "name")` | `redis.hash("user:1").get(:name)` |
| `redis.hincrby("user:1", "age", 1)` | `redis.hash("user:1").increment(:age, 1)` |
| `redis.hgetall("user:1")` | `redis.hash("user:1").get_all` |

[View Hash DSL →](/redis-ruby/guides/idiomatic-api/#hashes)

### Lists

| Low-Level API | Idiomatic API |
|:--------------|:--------------|
| `redis.lpush("queue", "job1")` | `redis.list("queue").push_left("job1")` |
| `redis.rpush("queue", "job1")` | `redis.list("queue").push("job1")` |
| `redis.lpop("queue")` | `redis.list("queue").pop_left` |
| `redis.lrange("queue", 0, -1)` | `redis.list("queue").range(0, -1)` |

[View List DSL →](/redis-ruby/guides/idiomatic-api/#lists)

### Sets

| Low-Level API | Idiomatic API |
|:--------------|:--------------|
| `redis.sadd("tags", "ruby")` | `redis.redis_set("tags").add("ruby")` |
| `redis.smembers("tags")` | `redis.redis_set("tags").members` |
| `redis.sismember("tags", "ruby")` | `redis.redis_set("tags").member?("ruby")` |
| `redis.sunion("set1", "set2")` | `redis.redis_set("set1").union("set2")` |

[View Set DSL →](/redis-ruby/guides/idiomatic-api/#sets)

### Sorted Sets

| Low-Level API | Idiomatic API |
|:--------------|:--------------|
| `redis.zadd("lb", 100, "alice")` | `redis.sorted_set("lb").add(alice: 100)` |
| `redis.zscore("lb", "alice")` | `redis.sorted_set("lb").score(:alice)` |
| `redis.zrange("lb", 0, 9)` | `redis.sorted_set("lb").range(0, 9)` |
| `redis.zincrby("lb", 10, "alice")` | `redis.sorted_set("lb").increment(:alice, 10)` |

[View Sorted Set DSL →](/redis-ruby/guides/idiomatic-api/#sorted-sets)

---

## Geospatial & Specialized

### Geospatial

| Low-Level API | Idiomatic API |
|:--------------|:--------------|
| `redis.geoadd("cities", -122.4, 37.7, "sf")` | `redis.geo("cities").add(sf: [-122.4, 37.7])` |
| `redis.geopos("cities", "sf")` | `redis.geo("cities").position(:sf)` |
| `redis.geodist("cities", "sf", "ny")` | `redis.geo("cities").distance(:sf, :ny)` |
| `redis.georadius("cities", -122, 37, 100, "km")` | `redis.geo("cities").radius(-122, 37, 100, :km)` |

[View Geo DSL →](/redis-ruby/guides/idiomatic-api/#geospatial)

### HyperLogLog

| Low-Level API | Idiomatic API |
|:--------------|:--------------|
| `redis.pfadd("visitors", "user1")` | `redis.hyperloglog("visitors").add("user1")` |
| `redis.pfcount("visitors")` | `redis.hyperloglog("visitors").count` |
| `redis.pfmerge("total", "v1", "v2")` | `redis.hyperloglog("total").merge("v1", "v2")` |

[View HyperLogLog DSL →](/redis-ruby/guides/idiomatic-api/#hyperloglog)

### Bitmaps

| Low-Level API | Idiomatic API |
|:--------------|:--------------|
| `redis.setbit("attendance", 0, 1)` | `redis.bitmap("attendance").set_bit(0, 1)` |
| `redis.getbit("attendance", 0)` | `redis.bitmap("attendance").get_bit(0)` |
| `redis.bitcount("attendance")` | `redis.bitmap("attendance").count` |
| `redis.bitpos("attendance", 1)` | `redis.bitmap("attendance").pos(1)` |

[View Bitmap DSL →](/redis-ruby/guides/idiomatic-api/#bitmaps)

---

## Probabilistic Data Structures

All probabilistic data structures provide idiomatic APIs with method chaining:

### Bloom Filter

```ruby
# Low-level
redis.bf_add("emails", "alice@example.com")
redis.bf_exists("emails", "alice@example.com")

# Idiomatic
redis.bloom("emails").add("alice@example.com")
redis.bloom("emails").exists?("alice@example.com")
```

[View Bloom Filter DSL →](/redis-ruby/guides/idiomatic-api/#bloom-filter)

### Cuckoo Filter

```ruby
# Low-level
redis.cf_add("products", "product:1")
redis.cf_exists("products", "product:1")

# Idiomatic
redis.cuckoo("products").add("product:1")
redis.cuckoo("products").exists?("product:1")
```

[View Cuckoo Filter DSL →](/redis-ruby/guides/idiomatic-api/#cuckoo-filter)

### Count-Min Sketch

```ruby
# Low-level
redis.cms_incrby("views", "page1", 1)
redis.cms_query("views", "page1")

# Idiomatic
redis.cms("views").increment("page1", 1)
redis.cms("views").query("page1")
```

[View Count-Min Sketch DSL →](/redis-ruby/guides/idiomatic-api/#count-min-sketch)

### Top-K

```ruby
# Low-level
redis.topk_add("trending", "product1")
redis.topk_list("trending")

# Idiomatic
redis.topk("trending").add("product1")
redis.topk("trending").list
```

[View Top-K DSL →](/redis-ruby/guides/idiomatic-api/#top-k)

---

## Advanced Features

### Search & Query

```ruby
# Low-level: Complex command syntax
redis.ft_create("products",
  "ON", "HASH",
  "PREFIX", 1, "product:",
  "SCHEMA",
    "name", "TEXT", "SORTABLE",
    "price", "NUMERIC", "SORTABLE")

# Idiomatic: Clean DSL
redis.search_index("products") do
  on :hash
  prefix "product:"
  text :name, sortable: true
  numeric :price, sortable: true
end
```

[View Search DSL →](/redis-ruby/guides/idiomatic-api/#search--query)

### JSON

```ruby
# Low-level
redis.json_set("user:1", "$", { name: "Alice", age: 30 })
redis.json_get("user:1", "$.name")

# Idiomatic: Chainable proxy
redis.json("user:1").set(name: "Alice", age: 30)
redis.json("user:1").get(:name)
```

[View JSON DSL →](/redis-ruby/guides/idiomatic-api/#json)

### Time Series

```ruby
# Low-level: Multiple calls needed
redis.ts_create("metrics:raw", retention: 3600000)
redis.ts_create("metrics:hourly", retention: 86400000)
redis.ts_createrule("metrics:raw", "metrics:hourly", "avg", 3600000)

# Idiomatic: Nested DSL
redis.time_series("metrics:raw") do
  retention 3600000
  compact_to "metrics:hourly", :avg, 3600000 do
    retention 86400000
  end
end
```

[View Time Series DSL →](/redis-ruby/guides/idiomatic-api/#time-series)

### Vector Sets

```ruby
# Low-level
redis.vadd("embeddings", [0.1, 0.2, 0.3], "doc1",
  attributes: { category: "tech" })

# Idiomatic: Fluent builder
redis.vectors("embeddings")
  .add("doc1", [0.1, 0.2, 0.3], category: "tech")
```

[View Vector Sets DSL →](/redis-ruby/guides/idiomatic-api/#vector-sets)

### Streams

```ruby
# Low-level
redis.xadd("events", "*", "event", "login", "user", "alice")
redis.xread("events", "0", count: 10)

# Idiomatic: Chainable proxy
redis.stream("events").add(event: "login", user: "alice")
redis.stream("events").read(count: 10)
```

[View Streams DSL →](/redis-ruby/guides/idiomatic-api/#streams)

### Pub/Sub

```ruby
# Low-level: Callback-based
redis.subscribe("news") do |on|
  on.message { |channel, message| puts message }
end

# Idiomatic: Fluent builder
redis.subscribe
  .to("news")
  .on_message { |channel, message| puts message }
  .start
```

[View Pub/Sub DSL →](/redis-ruby/guides/idiomatic-api/#pubsub)

---

## Key Differences

### Composite Keys

The idiomatic API supports automatic key joining:

```ruby
# Low-level: Manual key construction
redis.hset("user:123", "name", "Alice")

# Idiomatic: Automatic joining
redis.hash(:user, 123).set(name: "Alice")
# Equivalent to: redis.hash("user:123")
```

### Symbol vs String

The idiomatic API accepts both symbols and strings:

```ruby
# Both work the same
redis.hash("user:1").get(:name)
redis.hash("user:1").get("name")

# Symbols are more idiomatic
redis.sorted_set("leaderboard").add(alice: 100)
```

### Method Chaining

The idiomatic API returns `self` for chainable operations:

```ruby
# Low-level: Multiple calls
redis.lpush("queue", "job1")
redis.lpush("queue", "job2")
redis.lpush("queue", "job3")

# Idiomatic: Chained
redis.list("queue")
  .push("job1")
  .push("job2")
  .push("job3")
```

### Keyword Arguments

The idiomatic API uses keyword arguments for options:

```ruby
# Low-level: Positional arguments
redis.set("key", "value", ex: 3600)

# Idiomatic: Keyword arguments
redis.string("key").set("value", ex: 3600)
```

---

## Migration Guide

### From redis-rb

If you're migrating from redis-rb, the low-level API is nearly identical:

```ruby
# redis-rb
redis.set("key", "value")
redis.hgetall("user:1")

# redis-ruby (same syntax)
redis.set("key", "value")
redis.hgetall("user:1")
```

You can gradually adopt the idiomatic API:

```ruby
# Start with low-level
redis.hset("user:1", "name", "Alice")

# Migrate to idiomatic
redis.hash("user:1").set(name: "Alice")
```

### Choosing an API

Use the **low-level API** when:
- Migrating from another client
- You prefer explicit Redis commands
- Working with Redis documentation
- Need maximum control

Use the **idiomatic API** when:
- Building new Ruby applications
- You value readability and discoverability
- Want method chaining and fluent builders
- Prefer Ruby conventions

{: .note }
There's no performance difference - both APIs use the same underlying implementation!

---

## Complete Documentation

- [Idiomatic API Guide](/redis-ruby/guides/idiomatic-api/) - Complete DSL reference
- [Getting Started](/redis-ruby/getting-started/) - Installation and basics
- [Examples](/redis-ruby/examples/) - Runnable code examples
- [Advanced Features](/redis-ruby/advanced-features/) - JSON, Search, Time Series, etc.


