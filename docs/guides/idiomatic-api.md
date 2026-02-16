---
layout: default
title: Idiomatic Ruby API
parent: Guides
nav_order: 1
permalink: /guides/idiomatic-api/
---

# Idiomatic Ruby API
{: .no_toc }

redis-ruby provides both a **low-level API** (direct Redis commands) and an **idiomatic Ruby API** (DSLs and fluent builders) for all Redis data structures and features.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

The idiomatic Ruby API provides a more Ruby-esque way to work with Redis, offering:

- **Symbol-based method names** - Use `:name`, `:score` instead of strings
- **DSL blocks** - Configure complex structures with clean, declarative syntax
- **Method chaining** - Build queries and operations fluently
- **Composite keys** - Automatic key joining with symbols (e.g., `redis.hash(:user, 123)` → `"user:123"`)
- **Ruby conventions** - Keyword arguments, ranges, and familiar patterns
- **Unified interface** - Consistent API across all data structures

{: .note }
Both APIs work side-by-side - use whichever fits your style! The low-level API remains fully supported.

---

## Core Data Structures

### Hashes

The `hash` method returns a chainable proxy for hash operations:

```ruby
# Create/update hash with keyword arguments
user = redis.hash("user:1")
user.set(name: "Alice", age: 30, email: "alice@example.com")

# Composite keys with automatic joining
user = redis.hash(:user, 123)
# Equivalent to: redis.hash("user:123")

# Get fields (symbols or strings)
user.get(:name)           # => "Alice"
user.get(:name, :email)   # => ["Alice", "alice@example.com"]
user.get_all              # => { "name" => "Alice", "age" => "30", ... }

# Increment/decrement numeric fields
user.increment(:age, 1)   # => 31
user.decrement(:age, 1)   # => 30

# Check existence
user.exists?(:name)       # => true
user.exists?(:missing)    # => false

# Delete fields
user.delete(:email)
user.delete(:name, :age)

# Get all keys/values
user.keys                 # => ["name", "age", "email"]
user.values               # => ["Alice", "30", "alice@example.com"]
user.length               # => 3

# Scan through large hashes
user.scan(match: "addr:*", count: 100) do |field, value|
  puts "#{field}: #{value}"
end
```

**Compare with low-level API:**
```ruby
# Low-level
redis.hset("user:1", "name", "Alice", "age", "30")
redis.hget("user:1", "name")
redis.hincrby("user:1", "age", 1)

# Idiomatic
redis.hash("user:1").set(name: "Alice", age: 30)
redis.hash("user:1").get(:name)
redis.hash("user:1").increment(:age, 1)
```

### Sorted Sets

The `sset` method returns a chainable proxy for sorted set operations:

```ruby
leaderboard = redis.sset("game:leaderboard")

# Add members with scores
leaderboard.add(alice: 100, bob: 85, charlie: 92)
leaderboard.add(:david, 88)

# Get scores
leaderboard.score(:alice)         # => 100.0
leaderboard.scores(:alice, :bob)  # => [100.0, 85.0]

# Increment scores
leaderboard.increment(:alice, 10) # => 110.0

# Range queries (by rank)
leaderboard.range(0, 2)                    # Top 3: ["alice", "charlie", "david"]
leaderboard.range(0, 2, with_scores: true) # => [["alice", 110.0], ...]
leaderboard.reverse_range(0, 2)            # Bottom 3

# Range queries (by score)
leaderboard.range_by_score(90, 100)
leaderboard.range_by_score(90, Float::INFINITY)
leaderboard.reverse_range_by_score(100, 90)

# Count operations
leaderboard.count                    # => 4
leaderboard.count_by_score(90, 100)  # => 2

# Rank operations
leaderboard.rank(:alice)             # => 0 (highest)
leaderboard.reverse_rank(:alice)     # => 3 (from bottom)

# Pop operations
leaderboard.pop_max                  # => ["alice", 110.0]
leaderboard.pop_min                  # => ["bob", 85.0]
leaderboard.pop_max(2)               # Pop top 2

# Remove members
leaderboard.remove(:charlie)
leaderboard.remove_by_rank(0, 1)     # Remove top 2
leaderboard.remove_by_score(0, 50)   # Remove low scores

# Scan through large sets
leaderboard.scan(match: "user:*", count: 100) do |member, score|
  puts "#{member}: #{score}"
end
```

### Lists

The `list` method returns a chainable proxy for list operations:

```ruby
queue = redis.list("queue:jobs")

# Push operations (chainable)
queue.push("job1", "job2", "job3")           # Push to right
queue.push_left("urgent")                     # Push to left
queue.push("job4").push("job5")              # Method chaining

# Pop operations
queue.pop                                     # => "job5" (from right)
queue.pop_left                                # => "urgent" (from left)
queue.pop(2)                                  # Pop 2 elements

# Blocking operations
queue.blocking_pop(timeout: 5)                # Block up to 5 seconds
queue.blocking_pop_left(timeout: 0)           # Block indefinitely

# Access by index
queue[0]                                      # First element
queue[-1]                                     # Last element
queue[1..3]                                   # Range of elements

# Set by index
queue[0] = "new_job"

# Insert operations
queue.insert_before("job2", "new_job")
queue.insert_after("job2", "another_job")

# Range operations
queue.range(0, -1)                            # All elements
queue.range(0, 9)                             # First 10 elements

# Trim list
queue.trim(0, 99)                             # Keep first 100 elements

# Remove elements
queue.remove("job1", count: 1)                # Remove first occurrence
queue.remove("job2", count: -1)               # Remove last occurrence
queue.remove("job3", count: 0)                # Remove all occurrences

# List info
queue.length                                  # => 5
queue.empty?                                  # => false
```

### Sets

The `redis_set` method returns a chainable proxy for set operations:

```ruby
tags = redis.redis_set("article:tags")

# Add members (chainable)
tags.add("ruby", "redis", "database")
tags.add("nosql").add("performance")

# Check membership
tags.member?("ruby")                          # => true
tags.members?("ruby", "python")               # => [true, false]

# Get all members
tags.members                                  # => ["ruby", "redis", "database", ...]
tags.to_a                                     # Alias for members

# Random members
tags.random                                   # => "redis"
tags.random(2)                                # => ["ruby", "nosql"]

# Pop random members
tags.pop                                      # => "database"
tags.pop(2)                                   # => ["ruby", "redis"]

# Remove members
tags.remove("nosql")
tags.remove("ruby", "redis")

# Set operations
other_tags = redis.redis_set("other:tags")
tags.union(other_tags)                        # Union of sets
tags.intersect(other_tags)                    # Intersection
tags.diff(other_tags)                         # Difference

# Store results
tags.union_store("result", other_tags)
tags.intersect_store("result", other_tags)
tags.diff_store("result", other_tags)

# Move between sets
tags.move("ruby", other_tags)

# Set info
tags.size                                     # => 3
tags.empty?                                   # => false

# Scan through large sets
tags.scan(match: "ruby:*", count: 100) do |member|
  puts member
end
```

### Strings & Counters

The `string` and `counter` methods provide specialized interfaces:

```ruby
# String operations
cache = redis.string("cache:user:1")

# Set with options
cache.set("data", ex: 3600)                   # Expire in 1 hour
cache.set("data", px: 60000)                  # Expire in 60 seconds
cache.set("data", nx: true)                   # Only if not exists
cache.set("data", xx: true)                   # Only if exists

# Get operations
cache.get                                     # => "data"
cache.get_set("new_data")                     # Get old, set new
cache.get_delete                              # Get and delete

# String operations
cache.append(" more")                         # Append to string
cache.length                                  # String length
cache.substring(0, 4)                         # Get substring
cache.set_range(0, "new")                     # Overwrite part

# Counter operations
counter = redis.counter("stats:views")

# Increment/decrement
counter.increment                             # => 1
counter.increment(10)                         # => 11
counter.decrement                             # => 10
counter.decrement(5)                          # => 5

# Get value
counter.value                                 # => 5
counter.to_i                                  # => 5

# Set value
counter.set(100)                              # => 100

# Atomic operations
counter.get_set(0)                            # Get old value, set to 0
counter.increment_by_float(1.5)               # => 1.5
```

---

## Geospatial

The `geo` method returns a chainable proxy for geospatial operations:

```ruby
locations = redis.geo("cities")

# Add locations with coordinates
locations.add(
  san_francisco: [-122.4194, 37.7749],
  new_york: [-74.0060, 40.7128],
  london: [-0.1276, 51.5074]
)

# Add single location
locations.add(:tokyo, [139.6917, 35.6895])

# Get coordinates
locations.position(:san_francisco)            # => [-122.4194, 37.7749]
locations.positions(:san_francisco, :tokyo)   # => [[-122.4194, 37.7749], ...]

# Calculate distance
locations.distance(:san_francisco, :new_york)              # => 4129.06 (km)
locations.distance(:san_francisco, :new_york, unit: :mi)   # => 2565.88 (miles)
locations.distance(:london, :tokyo, unit: :m)              # => 9561229.45 (meters)

# Search by radius (from point)
results = locations.radius(-122.4, 37.8, 100, :km)
# => ["san_francisco"]

results = locations.radius(-122.4, 37.8, 100, :km,
  with_dist: true,
  with_coord: true,
  count: 10
)
# => [["san_francisco", 5.23, [-122.4194, 37.7749]], ...]

# Search by radius (from member)
results = locations.radius_by_member(:san_francisco, 5000, :km)
# => ["san_francisco", "new_york"]

# Get geohash
locations.hash(:san_francisco)                # => "9q8yyk8yuv0"
locations.hashes(:san_francisco, :tokyo)      # => ["9q8yyk8yuv0", ...]

# Search with options
results = locations.search(-122.4, 37.8, 100, :km,
  with_dist: true,
  with_coord: true,
  with_hash: true,
  count: 10,
  sort: :asc
)
```

## HyperLogLog

The `hll` method returns a chainable proxy for HyperLogLog operations:

```ruby
visitors = redis.hll("page:visitors")

# Add elements (chainable)
visitors.add("user1", "user2", "user3")
visitors.add("user4").add("user5")

# Count unique elements
visitors.count                                # => 5

# Merge multiple HyperLogLogs
page1 = redis.hll("page1:visitors")
page2 = redis.hll("page2:visitors")
total = redis.hll("total:visitors")

page1.add("user1", "user2")
page2.add("user2", "user3")
total.merge(page1, page2)
total.count                                   # => 3 (user1, user2, user3)
```

## Bitmaps

The `bitmap` method returns a chainable proxy for bitmap operations:

```ruby
attendance = redis.bitmap("attendance:2024-01")

# Set bits (chainable)
attendance.set_bit(0, 1)                      # User 0 attended
attendance.set_bit(1, 1)                      # User 1 attended
attendance.set_bit(2, 0)                      # User 2 didn't attend

# Get bits
attendance.get_bit(0)                         # => 1
attendance.get_bit(2)                         # => 0

# Count set bits
attendance.count                              # => 2
attendance.count(0, 10)                       # Count in byte range

# Find first bit
attendance.pos(1)                             # First set bit
attendance.pos(0)                             # First unset bit
attendance.pos(1, start: 5)                   # First set bit after position 5

# Bitwise operations
jan = redis.bitmap("attendance:2024-01")
feb = redis.bitmap("attendance:2024-02")
q1 = redis.bitmap("attendance:2024-q1")

# AND, OR, XOR, NOT operations
q1.bit_op(:or, jan, feb)                      # Union of attendance
q1.bit_op(:and, jan, feb)                     # Intersection
q1.bit_op(:xor, jan, feb)                     # Symmetric difference
q1.bit_op(:not, jan)                          # Complement

# Get/set bit field values
attendance.bitfield do |bf|
  bf.set(:u8, 0, 255)                         # Set 8-bit unsigned at offset 0
  bf.get(:u8, 0)                              # Get 8-bit unsigned at offset 0
  bf.incrby(:u8, 0, 1)                        # Increment by 1
end
```

## Probabilistic Data Structures

### Bloom Filter

The `bloom` method returns a chainable proxy for Bloom filter operations:

```ruby
filter = redis.bloom("emails:seen")

# Reserve with custom parameters
filter.reserve(error_rate: 0.01, capacity: 10000)

# Add items (chainable)
filter.add("alice@example.com")
filter.add("bob@example.com").add("charlie@example.com")

# Add multiple items
filter.add_many("dave@example.com", "eve@example.com")

# Check existence
filter.exists?("alice@example.com")           # => true
filter.exists?("unknown@example.com")         # => false

# Check multiple items
filter.exists_many?("alice@example.com", "bob@example.com")
# => [true, true]

# Get info
info = filter.info
# => { capacity: 10000, size: 3, ... }
```

### Cuckoo Filter

The `cuckoo` method returns a chainable proxy for Cuckoo filter operations:

```ruby
filter = redis.cuckoo("products:viewed")

# Reserve with custom parameters
filter.reserve(capacity: 10000, bucket_size: 2, max_iterations: 20)

# Add items (chainable)
filter.add("product:1")
filter.add("product:2").add("product:3")

# Add if not exists
filter.add_nx("product:1")                    # => false (already exists)
filter.add_nx("product:4")                    # => true

# Check existence
filter.exists?("product:1")                   # => true

# Delete items
filter.delete("product:1")                    # => true
filter.delete("product:999")                  # => false

# Count occurrences
filter.count("product:2")                     # => 1

# Get info
info = filter.info
```

### Count-Min Sketch

The `cms` method returns a chainable proxy for Count-Min Sketch operations:

```ruby
sketch = redis.cms("page:views")

# Initialize with dimensions
sketch.init(width: 2000, depth: 5)

# Increment counters (chainable)
sketch.increment("page1", 1)
sketch.increment("page2", 5).increment("page3", 10)

# Increment multiple items
sketch.increment_many({ "page1" => 2, "page2" => 3 })

# Query counts
sketch.query("page1")                         # => 3
sketch.query_many("page1", "page2", "page3")  # => [3, 8, 10]

# Merge sketches
sketch1 = redis.cms("sketch1")
sketch2 = redis.cms("sketch2")
sketch1.merge(sketch2)

# Get info
info = sketch.info
```

### Top-K

The `topk` method returns a chainable proxy for Top-K operations:

```ruby
topk = redis.topk("trending:products")

# Reserve with parameters
topk.reserve(k: 10, width: 2000, depth: 5, decay: 0.9)

# Add items (chainable)
topk.add("product1")
topk.add("product2").add("product3")

# Add multiple items
topk.add_many("product1", "product2", "product3")

# Increment items
topk.increment("product1", 5)
topk.increment_many({ "product1" => 2, "product2" => 3 })

# Query top-k items
topk.list                                     # => ["product1", "product2", ...]
topk.list_with_count                          # => [["product1", 7], ...]

# Check if in top-k
topk.query("product1")                        # => true
topk.query_many("product1", "product999")     # => [true, false]

# Get info
info = topk.info
```

---

## Advanced Features

### Search & Query

### Creating Indexes with DSL

The `index` method provides a block-based DSL for creating search indexes:

```ruby
redis.index("products") do
  on :hash
  prefix "product:"
  
  text :name, sortable: true
  text :description
  numeric :price, sortable: true
  tag :category
  vector :embedding, algorithm: :hnsw, dim: 384
end
```

**Compare with low-level API:**

```ruby
redis.ft_create("products",
  "ON", "HASH",
  "PREFIX", 1, "product:",
  "SCHEMA",
    "name", "TEXT", "SORTABLE",
    "description", "TEXT",
    "price", "NUMERIC", "SORTABLE",
    "category", "TAG",
    "embedding", "VECTOR", "HNSW", 6, "DIM", 384)
```

### Fluent Query Builder

The `search` method returns a chainable query builder:

```ruby
# Simple query
results = redis.search("products")
  .query("laptop")
  .execute

# Complex query with filters
results = redis.search("products")
  .query("laptop")
  .filter(:price, 500..1500)
  .filter(:category, "electronics")
  .sort_by(:price, :asc)
  .limit(0, 10)
  .return(:name, :price)
  .execute

# Vector similarity search
results = redis.search("products")
  .vector_filter(:embedding, query_vector, k: 10)
  .execute
```

**Available methods:**

- `query(text)` - Set query text
- `filter(field, value_or_range)` - Add numeric or tag filter
- `vector_filter(field, vector, k:)` - Vector similarity search
- `sort_by(field, direction)` - Sort results
- `limit(offset, count)` - Limit results
- `return(*fields)` - Specify fields to return
- `execute` - Execute the query

---

## JSON

### Chainable Proxy

The `json` method returns a chainable proxy for JSON operations:

```ruby
# Set document with keyword arguments
redis.json("user:1").set(name: "Alice", age: 30, scores: [95, 87, 92])

# Composite keys with automatic joining
redis.json(:user, 1).set(name: "Alice")
# Equivalent to: redis.json_set("user:1", "$", { name: "Alice" })

# Symbol-based paths
redis.json("user:1").get(:name)  # => "Alice"
redis.json("user:1").get("$.user.profile.email")  # JSONPath

# Method chaining
redis.json("user:1")
  .increment(:age, 1)
  .append(:scores, 88)
  .get(:scores)  # => [95, 87, 92, 88]
```

### Array Operations

```ruby
# Ruby ranges for array operations
redis.json("user:1").array_trim(:scores, 0..2)
redis.json("user:1").array_pop(:scores, -1)  # Pop from end

# Array methods
redis.json("user:1").array_length(:scores)
redis.json("user:1").array_index(:scores, 95)
redis.json("user:1").array_insert(:scores, 1, 90, 91)
```

### Numeric Operations

```ruby
redis.json("user:1").increment(:age, 1)
redis.json("user:1").decrement(:age, 1)
redis.json("user:1").multiply(:score, 1.5)
```

**Available methods:**

- `set(path_or_hash, value = nil)` - Set JSON value
- `get(path = "$")` - Get JSON value
- `delete(path)` - Delete JSON value
- `increment(path, value)` - Increment numeric value
- `decrement(path, value)` - Decrement numeric value
- `multiply(path, value)` - Multiply numeric value
- `append(path, *values)` - Append to array
- `array_length(path)` - Get array length
- `array_index(path, value)` - Find index of value
- `array_insert(path, index, *values)` - Insert into array
- `array_pop(path, index = -1)` - Pop from array
- `array_trim(path, start_or_range, stop = nil)` - Trim array
- `keys(path = "$")` - Get object keys
- `object_length(path = "$")` - Get object length
- `type(path = "$")` - Get value type
- `clear(path = "$")` - Clear value
- `toggle(path)` - Toggle boolean
- `exists?(path)` - Check if path exists

---

## Time Series

### Creating Time Series with DSL

The `time_series` method provides a block-based DSL for creating time series with compaction rules:

```ruby
# Simple time series
redis.time_series("temperature:sensor1") do
  retention 86400000  # 24 hours
  labels sensor: "temp", location: "office"
end

# Multi-level aggregation with automatic compaction
redis.time_series("metrics:raw") do
  retention 3600000  # 1 hour
  labels resolution: "raw"

  # Automatically create destination series and compaction rules
  compact_to "metrics:hourly", :avg, 3600000 do
    retention 86400000  # 24 hours
    labels resolution: "hourly"
  end

  compact_to "metrics:daily", :avg, 86400000 do
    retention 2592000000  # 30 days
    labels resolution: "daily"
  end
end
```

**Compare with low-level API:**

```ruby
# Low-level API requires multiple calls
redis.ts_create("metrics:raw", retention: 3600000)
redis.ts_create("metrics:hourly", retention: 86400000)
redis.ts_create("metrics:daily", retention: 2592000000)
redis.ts_createrule("metrics:raw", "metrics:hourly", "avg", 3600000)
redis.ts_createrule("metrics:raw", "metrics:daily", "avg", 86400000)
```

### Chainable Operations

The `ts` method returns a chainable proxy for time series operations:

```ruby
# Add samples with method chaining
now = Time.now.to_i * 1000
redis.ts("temperature:sensor1")
  .add(now, 23.5)
  .add(now + 1000, 24.0)
  .add(now + 2000, 23.8)

# Increment/decrement operations
redis.ts("counter:requests")
  .increment(10)
  .decrement(5)

# Get latest value
latest = redis.ts("temperature:sensor1").get
# => [1640000000000, "23.5"]

# Composite keys with automatic joining
redis.ts(:metrics, :server1, :cpu).add(now, 45.2)
# Equivalent to: redis.ts_add("metrics:server1:cpu", now, 45.2)

# Alter time series settings
redis.ts("temperature:sensor1").alter(retention: 172800000)

# Create compaction rule
redis.ts("metrics:raw").compact_to("metrics:hourly", :avg, 3600000)

# Delete samples in range
redis.ts("temperature:sensor1").delete(from: start_ts, to: end_ts)
```

**Available methods:**

- `add(timestamp, value, **options)` - Add a sample
- `increment(value, **options)` / `incr(value, **options)` - Increment by value
- `decrement(value, **options)` / `decr(value, **options)` - Decrement by value
- `get` / `latest` - Get latest sample
- `info` - Get time series information
- `alter(**options)` - Modify time series settings
- `compact_to(dest_key, aggregation, bucket_duration)` - Create compaction rule
- `delete_rule(dest_key)` - Delete compaction rule
- `delete(from:, to:)` - Delete samples in range
- `add_many(*samples)` - Add multiple samples
- `range(from:, to:)` - Get query builder for range
- `reverse_range(from:, to:)` - Get query builder for reverse range

### Fluent Query Builder

The `ts_query` method returns a chainable query builder:

```ruby
# Single series query
result = redis.ts_query("temperature:sensor1")
  .from("-")
  .to("+")
  .aggregate(:avg, 300000)  # 5 minute buckets
  .limit(100)
  .execute

# Multi-series query with filters
result = redis.ts_query
  .filter(sensor: "temp", location: "office")
  .from(Time.now - 3600)
  .to(Time.now)
  .aggregate(:avg, 60000)  # 1 minute buckets
  .with_labels
  .execute

# Reverse query (latest first)
result = redis.ts_query("temperature:sensor1")
  .from("-")
  .to("+")
  .reverse
  .limit(10)
  .execute

# Group by labels
result = redis.ts_query
  .filter(sensor: "temp")
  .from("-")
  .to("+")
  .aggregate(:avg, 300000)
  .group_by(:location, :avg)
  .execute
```

**Available methods:**

- `from(timestamp)` - Set start timestamp
- `to(timestamp)` - Set end timestamp
- `filter(labels_hash)` / `where(labels_hash)` - Filter by labels (multi-series only)
- `latest` - Use latest sample if timestamp is before series start
- `with_labels` - Include labels in results
- `limit(count)` - Limit number of samples
- `aggregate(type, bucket_duration, bucket_timestamp: nil)` - Aggregate samples
- `group_by(label, reducer)` - Group by label (multi-series only)
- `reverse` - Return results in reverse order
- `execute` - Execute the query

**Aggregation types:** `:avg`, `:sum`, `:min`, `:max`, `:count`, `:first`, `:last`, `:std_p`, `:std_s`, `:var_p`, `:var_s`, `:range`, `:twa`

---

## Pub/Sub

redis-ruby provides three Pub/Sub APIs: low-level, fluent builder, and broadcaster.

### Fluent Subscriber Builder

The `subscribe` method returns a fluent builder for subscriptions:

```ruby
# Subscribe to channels
redis.subscribe
  .to("news", "sports")
  .on_message { |channel, message| puts "#{channel}: #{message}" }
  .on_subscribe { |channel, count| puts "Subscribed to #{channel}" }
  .on_unsubscribe { |channel, count| puts "Unsubscribed from #{channel}" }
  .start

# Subscribe to patterns
redis.subscribe
  .to_pattern("news:*", "sports:*")
  .on_message { |pattern, channel, message| puts "#{channel}: #{message}" }
  .start

# Mixed subscriptions
redis.subscribe
  .to("general")
  .to_pattern("news:*")
  .on_message { |channel, message| puts message }
  .start
```

### Publisher Proxy

The `publisher` method returns a chainable proxy for publishing:

```ruby
pub = redis.publisher

# Publish to channels (chainable)
pub.publish("news", "Breaking news!")
   .publish("sports", "Game update!")

# Publish to multiple channels
pub.publish_many(
  "news" => "Story 1",
  "sports" => "Score update"
)

# Get subscriber count
pub.subscribers("news")                       # => 5
pub.subscribers("news", "sports")             # => [5, 3]
```

### Broadcaster Module

The `broadcaster` provides a Wisper-style API for event broadcasting:

```ruby
class UserService
  include RedisRuby::DSL::Broadcaster

  def create_user(name)
    user = User.create(name: name)
    broadcast(:user_created, user.to_json)
    user
  end
end

# Subscribe to events
service = UserService.new
service.on(:user_created) do |data|
  puts "User created: #{data}"
end

service.create_user("Alice")
# => Broadcasts to "user_created" channel
```

---

## Streams

The `stream` method returns a chainable proxy for stream operations:

```ruby
events = redis.stream("events:log")

# Add entries (chainable)
events.add(event: "login", user: "alice", timestamp: Time.now.to_i)
events.add({ event: "logout", user: "bob" }, id: "*")

# Read entries
entries = events.read(count: 10)
entries = events.read(start: "0", count: 100)

# Read latest
latest = events.read_latest(count: 5)

# Range queries
entries = events.range("-", "+")              # All entries
entries = events.range("1234567890-0", "+")   # From ID onwards

# Reverse range
entries = events.reverse_range("+", "-", count: 10)

# Trim stream
events.trim(maxlen: 1000)                     # Keep last 1000 entries
events.trim(minid: "1234567890-0")            # Remove entries before ID

# Delete entries
events.delete("1234567890-0", "1234567891-0")

# Stream info
events.length                                 # => 1000
info = events.info                            # Detailed info
```

### Consumer Groups

The `consumer_group` method provides consumer group operations:

```ruby
group = redis.consumer_group("events:log", "processors")

# Create group
group.create(id: "0")                         # Start from beginning
group.create(id: "$")                         # Start from latest

# Read as consumer
entries = group.read_as("worker1", count: 10)
entries = group.read_as("worker1", block: 5000)  # Block for 5 seconds

# Acknowledge messages
group.ack("1234567890-0", "1234567891-0")

# Claim pending messages
claimed = group.claim("worker1", min_idle: 60000, ids: ["1234567890-0"])

# Auto-claim pending messages
claimed = group.auto_claim("worker1", min_idle: 60000, start: "0")

# Get pending messages
pending = group.pending
pending = group.pending(consumer: "worker1")

# Consumer info
consumers = group.consumers
group.delete_consumer("worker1")

# Destroy group
group.destroy
```

### Multi-Stream Reading

The `streams` method provides multi-stream reading:

```ruby
# Read from multiple streams
results = redis.streams
  .from("stream1", "stream2", "stream3")
  .starting_at("0", "0", "0")
  .count(10)
  .execute

# Block until data available
results = redis.streams
  .from("stream1", "stream2")
  .starting_at(">", ">")
  .block(5000)
  .execute
```

---

## Benefits

### Readability

**Before (low-level):**
```ruby
redis.hset("user:1", "name", "Alice", "age", "30")
redis.zadd("leaderboard", 100, "alice", 85, "bob")
redis.geoadd("cities", -122.4194, 37.7749, "san_francisco")
```

**After (idiomatic):**
```ruby
redis.hash("user:1").set(name: "Alice", age: 30)
redis.sset("leaderboard").add(alice: 100, bob: 85)
redis.geo("cities").add(san_francisco: [-122.4194, 37.7749])
```

### Discoverability

Method chaining and DSLs make the API more discoverable through IDE autocomplete and documentation.

### Type Safety

Symbol-based method names reduce string typos and make refactoring easier.

### Ruby Conventions

The idiomatic API follows Ruby conventions like keyword arguments, ranges, and blocks, making it feel natural to Ruby developers.

### Consistency

All data structures follow the same patterns:
- Composite keys with automatic joining
- Symbol or string field/member names
- Method chaining for fluent operations
- Keyword arguments for options

---

## API Coverage

### Core Data Structures
- ✅ **Hashes** - `redis.hash(key)`
- ✅ **Sorted Sets** - `redis.sset(key)`
- ✅ **Lists** - `redis.list(key)`
- ✅ **Sets** - `redis.redis_set(key)`
- ✅ **Strings** - `redis.string(key)`
- ✅ **Counters** - `redis.counter(key)`

### Geospatial & Specialized
- ✅ **Geo** - `redis.geo(key)`
- ✅ **HyperLogLog** - `redis.hll(key)`
- ✅ **Bitmaps** - `redis.bitmap(key)`

### Probabilistic
- ✅ **Bloom Filter** - `redis.bloom(key)`
- ✅ **Cuckoo Filter** - `redis.cuckoo(key)`
- ✅ **Count-Min Sketch** - `redis.cms(key)`
- ✅ **Top-K** - `redis.topk(key)`

### Advanced Features
- ✅ **Search** - `redis.index(name)`, `redis.search(index)`
- ✅ **JSON** - `redis.json(key)`
- ✅ **Time Series** - `redis.time_series(key)`, `redis.ts(key)`, `redis.ts_query`
- ✅ **Vector Sets** - `redis.vectors(key)`
- ✅ **Streams** - `redis.stream(key)`, `redis.consumer_group`, `redis.streams`
- ✅ **Pub/Sub** - `redis.subscribe`, `redis.publisher`, `RedisRuby::DSL::Broadcaster`

---

## Examples

See the `examples/` directory for complete working examples:

**Core Data Structures:**
- `examples/idiomatic_hash_api.rb` - Hash examples
- `examples/idiomatic_sorted_set_api.rb` - Sorted Set examples
- `examples/idiomatic_list_api.rb` - List examples
- `examples/idiomatic_set_api.rb` - Set examples
- `examples/idiomatic_string_api.rb` - String & Counter examples

**Geospatial & Specialized:**
- `examples/idiomatic_geo_api.rb` - Geospatial examples
- `examples/idiomatic_hyperloglog_api.rb` - HyperLogLog examples
- `examples/idiomatic_bitmap_api.rb` - Bitmap examples

**Probabilistic:**
- `examples/idiomatic_bloom_api.rb` - Bloom Filter examples
- `examples/idiomatic_cuckoo_api.rb` - Cuckoo Filter examples
- `examples/idiomatic_cms_api.rb` - Count-Min Sketch examples
- `examples/idiomatic_topk_api.rb` - Top-K examples

**Advanced Features:**
- `examples/idiomatic_search_api.rb` - Search & Query examples
- `examples/idiomatic_json_api.rb` - JSON examples
- `examples/idiomatic_time_series_api.rb` - Time Series examples
- `examples/idiomatic_vector_sets_api.rb` - Vector Sets examples
- `examples/idiomatic_streams_api.rb` - Streams examples
- `examples/idiomatic_pubsub_api.rb` - Pub/Sub examples

---

## Vector Sets

Vector Sets provide efficient vector similarity search for AI and machine learning applications.

### Adding Vectors with Metadata

The `vectors` method returns a chainable proxy for vector operations:

```ruby
vectors = redis.vectors("product:embeddings")

# Add vectors with method chaining
vectors
  .add("product_1", [0.1, 0.2, 0.3, 0.4], category: "electronics", price: 299.99)
  .add("product_2", [0.2, 0.3, 0.4, 0.5], category: "books", price: 19.99)

# Add multiple vectors in batch
vectors.add_many([
  { id: "product_3", vector: [0.3, 0.4, 0.5, 0.6], category: "music", price: 9.99 },
  { id: "product_4", vector: [0.4, 0.5, 0.6, 0.7], category: "electronics", price: 149.99 }
])
```

**Low-level equivalent:**
```ruby
redis.vadd("product:embeddings", [0.1, 0.2, 0.3, 0.4], "product_1",
  attributes: { category: "electronics", price: 299.99 })
```

### Similarity Search with Fluent Builder

Build complex vector search queries with a chainable interface:

```ruby
query_vector = [0.15, 0.25, 0.35, 0.45]

# Basic search
results = vectors.search(query_vector)
  .limit(10)
  .execute

# Search with scores
results = vectors.search(query_vector)
  .limit(10)
  .with_scores
  .execute

# Search with metadata filtering
electronics = vectors.search(query_vector)
  .filter(".category == 'electronics'")
  .limit(10)
  .with_scores
  .with_metadata
  .execute

# Complex filters
affordable = vectors.search(query_vector)
  .where(".price < 300 && .in_stock == true")
  .limit(10)
  .execute
```

**Low-level equivalent:**
```ruby
redis.vsim("product:embeddings", query_vector,
  count: 10,
  with_scores: true,
  with_attribs: true,
  filter: ".category == 'electronics'")
```

### Vector Operations

```ruby
# Get a vector by ID
vector_data = vectors.get("product_1")

# Get metadata
metadata = vectors.metadata("product_1")

# Update metadata
vectors.set_metadata("product_1", price: 249.99, on_sale: true)

# Remove a vector
vectors.remove("product_1")

# Get statistics
puts "Total vectors: #{vectors.count}"
puts "Dimension: #{vectors.dimension}"
```

### Method Reference

**VectorProxy Methods:**
- `add(id, vector, **metadata)` - Add a vector with metadata
- `add_many(vectors)` - Add multiple vectors in batch
- `get(id, raw: false)` - Get vector by ID
- `metadata(id)` - Get metadata for a vector
- `set_metadata(id, **attributes)` - Update metadata
- `remove(id)` - Remove a vector
- `count` / `size` / `cardinality` - Get number of vectors
- `dimension` / `dim` - Get vector dimension
- `info` - Get detailed vector set information
- `search(query_vector)` - Create a search builder

**VectorSearchBuilder Methods:**
- `limit(n)` / `top_k(n)` - Set maximum number of results
- `with_scores` - Include similarity scores
- `with_metadata` / `with_attributes` - Include metadata
- `filter(expression)` / `where(expression)` - Add filter expression
- `exploration_factor(value)` / `ef(value)` - Set exploration factor
- `threshold(value)` / `epsilon(value)` - Set distance threshold
- `execute` / `run` / `results` - Execute the search

---

## Documentation

For detailed documentation on advanced features:

- [Search & Query](/redis-ruby/advanced-features/search/)
- [JSON](/redis-ruby/advanced-features/json/)
- [Time Series](/redis-ruby/advanced-features/timeseries/)
- [Vector Sets](/redis-ruby/advanced-features/vectorsets/)
- [Bloom Filters](/redis-ruby/advanced-features/bloom/)

For core Redis commands and low-level API:

- [Getting Started](/redis-ruby/getting-started/)
- [Connections](/redis-ruby/guides/connections/)
- [Pipelines](/redis-ruby/guides/pipelines/)
- [Transactions](/redis-ruby/guides/transactions/)
- [Pub/Sub](/redis-ruby/guides/pubsub/)
- [Cluster](/redis-ruby/guides/cluster/)
- [Sentinel](/redis-ruby/guides/sentinel/)

