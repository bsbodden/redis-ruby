---
layout: default
title: Vector Sets
parent: Advanced Features
nav_order: 5
permalink: /advanced-features/vectorsets/
---

# Vector Sets

Vector Sets is a new native Redis data type introduced in Redis 8 for efficient vector similarity search. Inspired by sorted sets, Vector Sets provide a lightweight, Redis-friendly way to store and query high-dimensional vector embeddings for AI and machine learning applications.

## Overview

Vector Sets extend the concept of sorted sets by associating string elements with vectors instead of scores. They are optimized for:

- **Vector similarity search** - Find the most similar items to a query vector
- **Quantization** - Efficient storage with 8-bit, binary, or no quantization
- **Dimensionality reduction** - Random projection to reduce vector dimensions
- **Filtering** - Attribute-based filtering using JSON expressions

## Basic Operations

### Creating and Adding Vectors

```ruby
# Add a vector to a set
redis.vadd("products:embeddings", "product:1", [0.1, 0.2, 0.3, 0.4])

# Add multiple vectors
redis.vadd("products:embeddings",
  "product:1", [0.1, 0.2, 0.3, 0.4],
  "product:2", [0.2, 0.3, 0.4, 0.5],
  "product:3", [0.3, 0.4, 0.5, 0.6])

# Add vector with attributes for filtering
redis.vadd("products:embeddings", "product:1", [0.1, 0.2, 0.3, 0.4],
  ATTR: '{"category": "electronics", "price": 299.99}')
```

### Similarity Search

```ruby
# Find 10 most similar vectors
query_vector = [0.15, 0.25, 0.35, 0.45]
results = redis.vsim("products:embeddings", query_vector, COUNT: 10)

# Results format: [[element, score], [element, score], ...]
results.each do |element, score|
  puts "#{element}: similarity score #{score}"
end
```

### Filtering Results

```ruby
# Find similar vectors with attribute filtering
results = redis.vsim("products:embeddings", query_vector,
  COUNT: 10,
  FILTER: '@.category == "electronics" && @.price < 500')
```

## Quantization Options

Vector Sets support different quantization methods to optimize storage:

```ruby
# 8-bit quantization (default)
redis.vadd("vectors:8bit", "item1", vector)

# Binary quantization for maximum compression
redis.vadd("vectors:binary", "item1", vector, QUANTIZATION: "BINARY")

# No quantization for maximum precision
redis.vadd("vectors:full", "item1", vector, QUANTIZATION: "NONE")
```

## Dimensionality Reduction

Reduce vector dimensions using random projection:

```ruby
# Reduce 768-dimensional vectors to 256 dimensions
redis.vadd("vectors:reduced", "item1", vector_768d,
  REDUCE_DIMS: 256)
```

## Managing Attributes

```ruby
# Set attributes for an existing element
redis.vsetattr("products:embeddings", "product:1",
  '{"category": "electronics", "price": 299.99, "in_stock": true}')

# Get attributes
attrs = redis.vgetattr("products:embeddings", "product:1")
```

## Vector Set Information

```ruby
# Get number of elements
count = redis.vcard("products:embeddings")

# Check if element exists
exists = redis.vexists("products:embeddings", "product:1")

# Remove elements
redis.vrem("products:embeddings", "product:1", "product:2")
```

## Use Cases

### Semantic Search

```ruby
# Store document embeddings
documents.each do |doc|
  embedding = generate_embedding(doc.content)
  redis.vadd("docs:embeddings", "doc:#{doc.id}", embedding,
    ATTR: {title: doc.title, category: doc.category}.to_json)
end

# Search for similar documents
query_embedding = generate_embedding(user_query)
results = redis.vsim("docs:embeddings", query_embedding,
  COUNT: 5,
  FILTER: '@.category == "technical"')
```

### Product Recommendations

```ruby
# Store product embeddings
products.each do |product|
  redis.vadd("products:vectors", "product:#{product.id}",
    product.embedding,
    ATTR: {
      name: product.name,
      category: product.category,
      price: product.price
    }.to_json)
end

# Find similar products
similar = redis.vsim("products:vectors", current_product_embedding,
  COUNT: 10,
  FILTER: '@.price < 100')
```

## Vector Sets vs. Search & Query

Redis offers two complementary approaches for vector similarity:

**Vector Sets** - Best for:
- Lightweight vector similarity use cases
- Simple API with minimal complexity
- Applications focused primarily on vector search
- Smaller datasets that don't require horizontal scaling

**Search & Query (Redis Query Engine)** - Best for:
- Comprehensive search needs (full-text, numerical, geospatial)
- Hybrid queries combining vector similarity with other search types
- Large-scale datasets requiring horizontal scaling
- Enterprise-grade features and ecosystem integrations

## Next Steps

- [Search & Query Documentation](/advanced-features/search/) - Full-text and hybrid search
- [JSON Documentation](/advanced-features/json/) - JSON document operations
- [Vector Sets Commands](https://redis.io/docs/latest/commands/?group=vectorset) - Complete command reference
- [Redis 8 Release Notes](https://redis.io/blog/redis-8-brings-vector-sets-and-is-now-in-preview-on-redis-cloud-essentials/)

