---
layout: default
title: Idiomatic Ruby API
parent: Guides
nav_order: 1
permalink: /guides/idiomatic-api/
---

# Idiomatic Ruby API
{: .no_toc }

redis-ruby provides both a **low-level API** (direct Redis commands) and an **idiomatic Ruby API** (DSLs and fluent builders) for advanced features.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

The idiomatic Ruby API provides a more Ruby-esque way to work with Redis advanced features, offering:

- **Symbol-based method names** - Use `:text`, `:numeric` instead of strings
- **DSL blocks** - Configure complex structures with clean, declarative syntax
- **Method chaining** - Build queries and operations fluently
- **Composite keys** - Automatic key joining with symbols
- **Ruby conventions** - Keyword arguments, ranges, and familiar patterns

{: .note }
Both APIs work side-by-side - use whichever fits your style! The low-level API remains fully supported.

---

## Search & Query

### Creating Indexes with DSL

The `search_index` method provides a block-based DSL for creating search indexes:

```ruby
redis.search_index("products") do
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

## Benefits

### Readability

**Before (low-level):**
```ruby
redis.ft_create("products",
  "ON", "HASH",
  "PREFIX", 1, "product:",
  "SCHEMA",
    "name", "TEXT", "SORTABLE",
    "price", "NUMERIC", "SORTABLE")
```

**After (idiomatic):**
```ruby
redis.search_index("products") do
  on :hash
  prefix "product:"
  text :name, sortable: true
  numeric :price, sortable: true
end
```

### Discoverability

Method chaining and DSLs make the API more discoverable through IDE autocomplete and documentation.

### Type Safety

Symbol-based method names reduce string typos and make refactoring easier.

### Ruby Conventions

The idiomatic API follows Ruby conventions like keyword arguments, ranges, and blocks, making it feel natural to Ruby developers.

---

## Examples

See the `examples/` directory for complete working examples:

- `examples/idiomatic_search_api.rb` - Search & Query examples
- `examples/idiomatic_json_api.rb` - JSON examples
- `examples/idiomatic_time_series_api.rb` - Time Series examples
- `examples/idiomatic_vector_sets_api.rb` - Vector Sets examples

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

For detailed documentation on each feature:

- [Search & Query](/redis-ruby/advanced-features/search/)
- [JSON](/redis-ruby/advanced-features/json/)
- [Time Series](/redis-ruby/advanced-features/timeseries/)
- [Vector Sets](/redis-ruby/advanced-features/vectorsets/)

