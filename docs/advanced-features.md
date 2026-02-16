---
layout: default
title: Advanced Features
permalink: /advanced-features/
nav_order: 5
has_children: true
---

# Advanced Features

Redis includes powerful capabilities for search, JSON documents, time series data, and probabilistic data structures. The redis-ruby client provides full support for these features.

## Available Features

Redis provides advanced data types and capabilities:

- **[Search & Query](/advanced-features/search/)** - Full-text search, vector search, and aggregations
- **[JSON](/advanced-features/json/)** - Native JSON document storage with JSONPath queries
- **[Time Series](/advanced-features/timeseries/)** - Time series data with automatic downsampling
- **[Probabilistic](/advanced-features/bloom/)** - Probabilistic data structures (Bloom filters, Count-Min Sketch, Top-K)
- **[Vector Sets](/advanced-features/vectorsets/)** - Native vector similarity search data type (Redis 8+)

## Installation and Setup

### Using Docker

**Redis 8.6 (latest stable)**

The easiest way to get started is using Docker:

```bash
# Redis 8.6 (recommended)
docker run -p 6379:6379 -it redis:latest

# Or specify version explicitly
docker run -p 6379:6379 -it redis:8.6

# Alpine variant (smaller image)
docker run -p 6379:6379 -it redis:8.6-alpine
```

For more installation options and module-specific builds, see the [official Redis downloads page](https://redis.io/downloads/).

### Verify Installation

Connect with redis-ruby and test these features:

```ruby
require "redis_ruby"  # Native RR API

redis = RR.new(url: "redis://localhost:6379")

# Test JSON commands
redis.json_set("test", "$", { hello: "world" })

# Test Search commands
redis.ft_create("idx", "SCHEMA", "name", "TEXT")

# Test Time Series commands
redis.ts_create("series")

# Test Probabilistic commands
redis.bf_reserve("filter", 0.01, 1000)
```

## Supported Redis Versions

| Redis Version | Status | Notes |
|:---:|:---:|:---|
| **8.6** | Supported | Latest stable release |
| **8.2** | Supported | Latest features |
| **8.0** | Supported | Full feature support including Vector Sets |
| **7.4** | Supported | All features supported |
| **7.2** | Supported | All features supported |
| **6.2+** | Compatible | Basic commands supported |

## Feature Overview

### Search & Query

Full-text search and secondary indexing with support for:
- Text search with stemming and phonetic matching
- Vector similarity search for AI/ML applications
- Numeric and geo filtering
- Aggregations and grouping
- Auto-complete suggestions

[Learn more about Search & Query →](/advanced-features/search/)

### JSON

Native JSON document storage with:
- JSONPath query support
- Atomic operations on JSON elements
- Efficient memory usage
- Array and object manipulation
- Integration with Search for indexing

[Learn more about JSON →](/advanced-features/json/)

### Time Series

Time series data management with:
- High-volume data ingestion
- Automatic downsampling and compaction
- Range queries with aggregations
- Label-based filtering
- Retention policies

[Learn more about Time Series →](/advanced-features/timeseries/)

### Probabilistic

Probabilistic data structures for:
- Bloom filters - membership testing
- Cuckoo filters - membership with deletion
- Count-Min Sketch - frequency estimation
- Top-K - tracking most frequent items
- t-digest - percentile estimation

[Learn more about Probabilistic →](/advanced-features/bloom/)

### Vector Sets

Native vector similarity search data type (Redis 8+) with:
- Lightweight vector storage and querying
- Quantization options (8-bit, binary, none)
- Dimensionality reduction via random projection
- Attribute-based filtering
- Simple, Redis-friendly API

[Learn more about Vector Sets →](/advanced-features/vectorsets/)

## Quick Start Examples

### Search and JSON Together

```ruby
# Create JSON documents
redis.json_set("product:1", "$", {
  name: "Laptop Pro",
  price: 1299.99,
  category: "electronics",
  tags: ["computer", "portable"]
})

redis.json_set("product:2", "$", {
  name: "Wireless Mouse",
  price: 29.99,
  category: "electronics",
  tags: ["accessory", "wireless"]
})

# Create search index on JSON documents
redis.ft_create("products",
  "ON", "JSON",
  "PREFIX", 1, "product:",
  "SCHEMA",
    "$.name", "AS", "name", "TEXT",
    "$.price", "AS", "price", "NUMERIC", "SORTABLE",
    "$.category", "AS", "category", "TAG")

# Search products
results = redis.ft_search("products", "@name:laptop")
```

### Time Series with Labels

```ruby
# Create time series with labels
redis.ts_create("sensor:temp:1", labels: { location: "office", type: "temperature" })
redis.ts_create("sensor:temp:2", labels: { location: "warehouse", type: "temperature" })

# Add data points
redis.ts_add("sensor:temp:1", "*", 23.5)
redis.ts_add("sensor:temp:2", "*", 18.2)

# Query by labels
results = redis.ts_mrange("-", "+", ["type=temperature"])
```

## Next Steps

- [Search & Query Documentation](/advanced-features/search/) - Full-text and vector search
- [JSON Documentation](/advanced-features/json/) - JSON document operations
- [Time Series Documentation](/advanced-features/timeseries/) - Time series data
- [Probabilistic Documentation](/advanced-features/bloom/) - Probabilistic structures
- [Vector Sets Documentation](/advanced-features/vectorsets/) - Native vector similarity search

## Resources

- [Redis Commands Documentation](https://redis.io/docs/latest/commands/)
- [Redis University](https://university.redis.com/)
- [GitHub Repository](https://github.com/redis/redis-ruby)

