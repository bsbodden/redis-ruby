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

## Idiomatic Ruby API

The idiomatic API provides a modern, chainable interface for working with Vector Sets, inspired by popular vector databases like Pinecone and Weaviate.

### Adding Vectors with Metadata

```ruby
# Get a chainable proxy for vector operations
vectors = redis.vectors("products:embeddings")

# Add vectors with method chaining
vectors
  .add("product_1", [0.1, 0.2, 0.3, 0.4], category: "electronics", price: 299.99)
  .add("product_2", [0.2, 0.3, 0.4, 0.5], category: "books", price: 19.99)
  .add("product_3", [0.3, 0.4, 0.5, 0.6], category: "electronics", price: 499.99)

# Add multiple vectors in batch
vectors.add_many([
  { id: "product_4", vector: [0.4, 0.5, 0.6, 0.7], category: "music", price: 9.99 },
  { id: "product_5", vector: [0.5, 0.6, 0.7, 0.8], category: "electronics", price: 149.99 }
])
```

### Similarity Search with Fluent Builder

```ruby
# Basic similarity search
query_vector = [0.15, 0.25, 0.35, 0.45]
results = vectors.search(query_vector)
  .limit(10)
  .execute

# Search with scores
results = vectors.search(query_vector)
  .limit(10)
  .with_scores
  .execute

results.each do |id, score|
  puts "#{id}: #{score}"
end

# Search with metadata
results = vectors.search(query_vector)
  .limit(10)
  .with_metadata
  .execute

# Search with both scores and metadata
results = vectors.search(query_vector)
  .limit(10)
  .with_scores
  .with_metadata
  .execute

results.each do |id, data|
  puts "#{id}: score=#{data['score']}, category=#{data['attributes']['category']}"
end
```

### Filtered Search

```ruby
# Filter by category
electronics = vectors.search(query_vector)
  .filter(".category == 'electronics'")
  .limit(10)
  .with_scores
  .execute

# Filter by price range
affordable = vectors.search(query_vector)
  .where(".price < 300")
  .limit(10)
  .with_scores
  .with_metadata
  .execute

# Complex filters
in_stock_electronics = vectors.search(query_vector)
  .filter(".category == 'electronics' && .in_stock == true")
  .limit(10)
  .execute
```

### Retrieving and Updating Vectors

```ruby
# Get a vector by ID
vector_data = vectors.get("product_1")

# Get metadata
metadata = vectors.metadata("product_1")

# Update metadata
vectors.set_metadata("product_1", price: 249.99, on_sale: true)

# Remove a vector
vectors.remove("product_1")
```

### Vector Set Information

```ruby
# Get vector set statistics
puts "Total vectors: #{vectors.count}"
puts "Dimension: #{vectors.dimension}"

# Get detailed info
info = vectors.info
```

## Low-Level Command API

For advanced use cases, you can use the low-level command API directly.

### Creating and Adding Vectors

```ruby
# Add a vector to a set
redis.vadd("products:embeddings", [0.1, 0.2, 0.3, 0.4], "product:1")

# Add vector with attributes for filtering
redis.vadd("products:embeddings", [0.1, 0.2, 0.3, 0.4], "product:1",
  attributes: { category: "electronics", price: 299.99 })
```

### Similarity Search

```ruby
# Find 10 most similar vectors
query_vector = [0.15, 0.25, 0.35, 0.45]
results = redis.vsim("products:embeddings", query_vector, count: 10)

# Search with scores
results = redis.vsim("products:embeddings", query_vector, count: 10, with_scores: true)

# Search with metadata
results = redis.vsim("products:embeddings", query_vector, count: 10, with_attribs: true)
```

### Filtering Results

```ruby
# Find similar vectors with attribute filtering
results = redis.vsim("products:embeddings", query_vector,
  count: 10,
  filter: '.category == "electronics" && .price < 500')
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

