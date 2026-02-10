---
layout: default
title: Search & Query
parent: Advanced Features
nav_order: 1
permalink: /advanced-features/search/
---

# Search & Query

Redis provides powerful full-text search and secondary indexing capabilities. It offers rich querying features including full-text search, vector similarity search, aggregations, and more.

## Table of Contents

- [Creating Indexes](#creating-indexes)
- [Full-Text Search](#full-text-search)
- [Vector Search](#vector-search)
- [Aggregations](#aggregations)
- [Query Syntax](#query-syntax)
- [Advanced Features](#advanced-features)

## Creating Indexes

### Basic Index on Hash Documents

```ruby
# Create an index on hash documents
redis.ft_create("products",
  "ON", "HASH",
  "PREFIX", 1, "product:",
  "SCHEMA",
    "name", "TEXT", "SORTABLE",
    "description", "TEXT",
    "price", "NUMERIC", "SORTABLE",
    "category", "TAG",
    "stock", "NUMERIC")

# Add documents
redis.hset("product:1", "name", "Laptop Pro", "price", 1299, "category", "electronics", "stock", 50)
redis.hset("product:2", "name", "Wireless Mouse", "price", 29, "category", "electronics", "stock", 200)
redis.hset("product:3", "name", "Office Chair", "price", 299, "category", "furniture", "stock", 25)
```

### Index on JSON Documents

```ruby
# Create an index on JSON documents
redis.ft_create("users",
  "ON", "JSON",
  "PREFIX", 1, "user:",
  "SCHEMA",
    "$.name", "AS", "name", "TEXT",
    "$.email", "AS", "email", "TAG",
    "$.age", "AS", "age", "NUMERIC", "SORTABLE",
    "$.city", "AS", "city", "TAG")

# Add JSON documents
redis.json_set("user:1", "$", {
  name: "Alice Johnson",
  email: "alice@example.com",
  age: 30,
  city: "New York"
})

redis.json_set("user:2", "$", {
  name: "Bob Smith",
  email: "bob@example.com",
  age: 25,
  city: "San Francisco"
})
```

### Vector Index for Similarity Search

```ruby
# Create index with vector field for embeddings
redis.ft_create("documents",
  "ON", "HASH",
  "PREFIX", 1, "doc:",
  "SCHEMA",
    "title", "TEXT",
    "content", "TEXT",
    "embedding", "VECTOR", "HNSW", "6",
      "TYPE", "FLOAT32",
      "DIM", "384",
      "DISTANCE_METRIC", "COSINE")

# Add document with embedding
embedding = [0.1, 0.2, 0.3] * 128  # 384-dimensional vector
redis.hset("doc:1",
  "title", "Introduction to Redis",
  "content", "Redis is an in-memory data structure store...",
  "embedding", embedding.pack("f*"))
```

## Full-Text Search

### Basic Search

```ruby
# Simple text search
results = redis.ft_search("products", "laptop")
# Returns: [total_count, doc_id, fields, doc_id, fields, ...]

# Search with multiple terms
results = redis.ft_search("products", "wireless mouse")

# Exact phrase search
results = redis.ft_search("products", '"laptop pro"')
```

### Search with Filters

```ruby
# Numeric filter
results = redis.ft_search("products", "*",
  filter: { price: [0, 100] })

# Tag filter
results = redis.ft_search("products", "@category:{electronics}")

# Combined filters
results = redis.ft_search("products", "@category:{electronics}",
  filter: { price: [0, 500] })
```

### Search with Options

```ruby
# Return specific fields
results = redis.ft_search("products", "laptop",
  return: ["name", "price"])

# Sort results
results = redis.ft_search("products", "*",
  sortby: "price",
  sortasc: true,
  limit: [0, 10])

# Include scores
results = redis.ft_search("products", "laptop",
  withscores: true)

# Highlighting
results = redis.ft_search("products", "laptop",
  highlight: { fields: ["name", "description"], tags: ["<b>", "</b>"] })
```

### Using Query Builder

```ruby
require "redis_ruby/search/query"

# Build complex query
query = RedisRuby::Search::Query.new("laptop")
  .filter("price", 500, 2000)
  .filter("category", "electronics")
  .sort_by("price", :asc)
  .limit(0, 20)
  .highlight(fields: ["name", "description"])

results = redis.ft_search("products", query.to_s, **query.options)
```

## Vector Search

### Similarity Search with Vectors

```ruby
# Create query vector (same dimensions as indexed vectors)
query_vector = [0.15, 0.25, 0.35] * 128  # 384-dimensional

# Vector similarity search
query = "*=>[KNN 10 @embedding $vec AS score]"
results = redis.ft_search("documents", query,
  params: { vec: query_vector.pack("f*") },
  sortby: "score",
  dialect: 2)
```

### Hybrid Search (Text + Vector)

```ruby
# Combine text search with vector similarity
query = "@title:redis =>[KNN 5 @embedding $vec AS score]"
results = redis.ft_search("documents", query,
  params: { vec: query_vector.pack("f*") },
  sortby: "score",
  dialect: 2)
```

## Aggregations

### Basic Aggregation

```ruby
# Group by category and count
results = redis.ft_aggregate("products", "*",
  "GROUPBY", 1, "@category",
  "REDUCE", "COUNT", 0, "AS", "count")
```

### Advanced Aggregation with Query Builder

```ruby
require "redis_ruby/search/query"

# Build aggregation query
agg = RedisRuby::Search::AggregateQuery.new("*")
  .group_by("@category", reducers: [
    RedisRuby::Search::Reducer.count.as("count"),
    RedisRuby::Search::Reducer.avg("@price").as("avg_price"),
    RedisRuby::Search::Reducer.sum("@stock").as("total_stock")
  ])
  .sort_by("@count", :desc)
  .limit(0, 10)

results = agg.execute(redis, "products")
```

### Aggregation with Filters

```ruby
# Aggregate with filtering
agg = RedisRuby::Search::AggregateQuery.new("@category:{electronics}")
  .group_by("@category", reducers: [
    RedisRuby::Search::Reducer.count.as("count"),
    RedisRuby::Search::Reducer.min("@price").as("min_price"),
    RedisRuby::Search::Reducer.max("@price").as("max_price")
  ])

results = agg.execute(redis, "products")
```

## Query Syntax

### Search Operators

```ruby
# AND operator (implicit)
redis.ft_search("products", "laptop pro")

# OR operator
redis.ft_search("products", "laptop | mouse")

# NOT operator
redis.ft_search("products", "laptop -wireless")

# Field-specific search
redis.ft_search("products", "@name:laptop")

# Prefix search
redis.ft_search("products", "lap*")

# Fuzzy search (Levenshtein distance)
redis.ft_search("products", "%laptap%")
```

### Numeric and Tag Filters

```ruby
# Numeric range
redis.ft_search("products", "@price:[100 500]")

# Numeric comparison
redis.ft_search("products", "@stock:[(50 +inf]")  # stock > 50

# Tag filter
redis.ft_search("products", "@category:{electronics}")

# Multiple tags
redis.ft_search("products", "@category:{electronics | furniture}")
```

## Advanced Features

### Auto-Complete Suggestions

```ruby
# Add suggestions
redis.ft_sugadd("autocomplete", "laptop", 100)
redis.ft_sugadd("autocomplete", "laptop pro", 90)
redis.ft_sugadd("autocomplete", "laptop stand", 80)

# Get suggestions
suggestions = redis.ft_sugget("autocomplete", "lap")
# => ["laptop", "laptop pro", "laptop stand"]

# With scores and fuzzy matching
suggestions = redis.ft_sugget("autocomplete", "lap",
  fuzzy: true,
  withscores: true,
  max: 5)
```

### Spell Checking

```ruby
# Add terms to dictionary
redis.ft_dictadd("slang", "lol", "brb", "omg")

# Check spelling
results = redis.ft_spellcheck("products", "laptap",
  distance: 1)
# Returns suggestions for misspelled terms
```

### Synonyms

```ruby
# Create synonym group
redis.ft_synupdate("products", "group1", "laptop", "notebook", "computer")

# Search will now match synonyms
results = redis.ft_search("products", "notebook")
# Will also find documents containing "laptop" or "computer"
```

### Index Management

```ruby
# Get index info
info = redis.ft_info("products")
puts info.inspect

# Drop index (keep documents)
redis.ft_dropindex("products")

# Drop index and delete documents
redis.ft_dropindex("products", delete_docs: true)

# Alter index (add field)
redis.ft_alter("products",
  "SCHEMA", "ADD",
  "brand", "TAG")
```

### Query Dialects

**Important:** redis-ruby uses dialect version 2 by default for better query parsing.

```ruby
# Default dialect 2
results = redis.ft_search("products", "@name:laptop pro")

# Explicit dialect 1 (legacy)
results = redis.ft_search("products", "@name:laptop pro", dialect: 1)

# Dialect 3 (if available)
results = redis.ft_search("products", "@name:laptop pro", dialect: 3)
```

## Performance Tips

1. **Use prefixes** - Organize keys with prefixes for efficient indexing
2. **Index only what you search** - Don't index fields you won't query
3. **Use SORTABLE sparingly** - Only mark fields as SORTABLE if needed
4. **Leverage tags** - Use TAG fields for exact-match categorical data
5. **Batch operations** - Use pipelines for bulk indexing
6. **Monitor index size** - Use `FT.INFO` to track memory usage

## Common Patterns

### E-commerce Product Search

```ruby
# Create comprehensive product index
redis.ft_create("products",
  "ON", "HASH",
  "PREFIX", 1, "product:",
  "SCHEMA",
    "name", "TEXT", "WEIGHT", 5.0, "SORTABLE",
    "description", "TEXT",
    "brand", "TAG", "SORTABLE",
    "category", "TAG",
    "price", "NUMERIC", "SORTABLE",
    "rating", "NUMERIC", "SORTABLE",
    "in_stock", "TAG")

# Search with multiple filters
results = redis.ft_search("products",
  "@category:{electronics} @brand:{apple|samsung}",
  filter: { price: [0, 1000], rating: [4, 5] },
  sortby: "rating",
  sortasc: false,
  limit: [0, 20])
```

### Document Search with Embeddings

```ruby
# Index documents with text and vectors
redis.ft_create("docs",
  "ON", "JSON",
  "PREFIX", 1, "doc:",
  "SCHEMA",
    "$.title", "AS", "title", "TEXT",
    "$.content", "AS", "content", "TEXT",
    "$.embedding", "AS", "embedding", "VECTOR", "HNSW", "6",
      "TYPE", "FLOAT32",
      "DIM", "768",
      "DISTANCE_METRIC", "COSINE")

# Hybrid search
query_vector = generate_embedding("machine learning")
results = redis.ft_search("docs",
  "(@title|content:machine learning) =>[KNN 10 @embedding $vec AS score]",
  params: { vec: query_vector.pack("f*") },
  dialect: 2)
```

## Error Handling

```ruby
begin
  redis.ft_create("products", "SCHEMA", "name", "TEXT")
rescue RedisRuby::CommandError => e
  if e.message.include?("Index already exists")
    puts "Index already exists, skipping creation"
  else
    raise
  end
end
```

## Next Steps

- [JSON Documentation](/advanced-features/json/) - Combine search with JSON documents
- [Query Syntax Reference](https://redis.io/docs/interact/search-and-query/query/)
- [Aggregation Pipeline](https://redis.io/docs/interact/search-and-query/advanced-concepts/aggregations/)
- [Vector Similarity](https://redis.io/docs/interact/search-and-query/search/vectors/)

## Resources

- [RediSearch Documentation](https://redis.io/docs/interact/search-and-query/)
- [Query Dialect Guide](https://redis.io/docs/latest/develop/interact/search-and-query/advanced-concepts/dialects/)
- [GitHub Examples](https://github.com/redis/redis-ruby/tree/main/examples)

