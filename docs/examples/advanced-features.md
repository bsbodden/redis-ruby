---
layout: default
title: Advanced Features Example
parent: Examples
nav_order: 5
permalink: /examples/advanced-features/
---

# Advanced Features Example

This example demonstrates how to use Redis advanced features including JSON and Search for powerful use cases.

## Prerequisites

- Ruby 3.2+ installed
- Redis 8.0+ running on localhost:6379
- redis-ruby gem installed (`gem install redis-ruby`)

## Complete Example

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "redis_ruby"  # Native RR API
require "json"

puts "=== Redis Advanced Features Example ===\n\n"

redis = RR.new(url: "redis://localhost:6379")

# ============================================================================
# JSON - Store and Query JSON Documents
# ============================================================================

puts "1. JSON - Store and query JSON documents..."

# Store JSON documents
product1 = {
  id: 1,
  name: "Laptop",
  brand: "TechCorp",
  price: 999.99,
  specs: {
    cpu: "Intel i7",
    ram: "16GB",
    storage: "512GB SSD"
  },
  tags: ["electronics", "computers", "laptops"]
}

product2 = {
  id: 2,
  name: "Wireless Mouse",
  brand: "TechCorp",
  price: 29.99,
  specs: {
    dpi: 1600,
    buttons: 5
  },
  tags: ["electronics", "accessories", "mice"]
}

redis.json_set("product:1", "$", product1.to_json)
redis.json_set("product:2", "$", product2.to_json)

puts "   Stored 2 products as JSON documents"

# Get entire document
product = JSON.parse(redis.json_get("product:1", "$").first)
puts "   Product 1: #{product["name"]} - $#{product["price"]}"

# Get specific fields
name = JSON.parse(redis.json_get("product:1", "$.name").first)
price = JSON.parse(redis.json_get("product:1", "$.price").first)
puts "   Name: #{name}, Price: $#{price}"

# Update specific field
redis.json_set("product:1", "$.price", "899.99")
new_price = JSON.parse(redis.json_get("product:1", "$.price").first)
puts "   Updated price: $#{new_price}"

# Array operations
redis.json_arrappend("product:1", "$.tags", "\"on-sale\"")
tags = JSON.parse(redis.json_get("product:1", "$.tags").first)
puts "   Updated tags: #{tags.inspect}\n\n"

# ============================================================================
# Search - Full-Text Search and Indexing
# ============================================================================

puts "2. Search - Full-text search and indexing..."

# Create search index
begin
  redis.ft_create(
    "products_idx",
    "ON", "JSON",
    "PREFIX", "1", "product:",
    "SCHEMA",
    "$.name", "AS", "name", "TEXT",
    "$.brand", "AS", "brand", "TAG",
    "$.price", "AS", "price", "NUMERIC",
    "$.tags[*]", "AS", "tags", "TAG"
  )
  puts "   Created search index 'products_idx'"
rescue RR::CommandError => e
  puts "   Index already exists (#{e.message})"
end

# Search by text
results = redis.ft_search("products_idx", "laptop")
puts "   Search 'laptop': Found #{results[0]} results"

# Search by tag
results = redis.ft_search("products_idx", "@brand:{TechCorp}")
puts "   Search brand 'TechCorp': Found #{results[0]} results"

# Search by price range
results = redis.ft_search("products_idx", "@price:[0 50]")
puts "   Search price $0-$50: Found #{results[0]} results"

# Complex query
results = redis.ft_search("products_idx", "@tags:{electronics} @price:[0 100]")
puts "   Search electronics under $100: Found #{results[0]} results\n\n"

# ============================================================================
# JSON + Search - Product Catalog
# ============================================================================

puts "3. Product catalog with JSON and Search..."

# Add more products
products = [
  {
    id: 3,
    name: "Mechanical Keyboard",
    brand: "KeyMaster",
    price: 149.99,
    specs: { switches: "Cherry MX Blue", backlight: "RGB" },
    tags: ["electronics", "accessories", "keyboards"]
  },
  {
    id: 4,
    name: "USB-C Hub",
    brand: "TechCorp",
    price: 49.99,
    specs: { ports: 7, power_delivery: "100W" },
    tags: ["electronics", "accessories", "hubs"]
  },
  {
    id: 5,
    name: "Monitor 27\"",
    brand: "DisplayPro",
    price: 399.99,
    specs: { resolution: "2560x1440", refresh_rate: "144Hz" },
    tags: ["electronics", "monitors", "displays"]
  }
]

products.each do |product|
  redis.json_set("product:#{product[:id]}", "$", product.to_json)
end

puts "   Added #{products.size} more products"

# Search and retrieve
results = redis.ft_search("products_idx", "@tags:{accessories}", "LIMIT", "0", "10")
count = results[0]
puts "   Found #{count} accessories"

# Get product details
if count > 0
  # Results format: [count, doc1_key, doc1_fields, doc2_key, doc2_fields, ...]
  (1...results.size).step(2) do |i|
    key = results[i]
    doc = JSON.parse(redis.json_get(key, "$").first)
    puts "     - #{doc["name"]}: $#{doc["price"]}"
  end
end

puts "\n"

# ============================================================================
# Aggregation
# ============================================================================

puts "4. Aggregation queries..."

# Get average price by brand
results = redis.ft_aggregate(
  "products_idx",
  "*",
  "GROUPBY", "1", "@brand",
  "REDUCE", "AVG", "1", "@price", "AS", "avg_price",
  "REDUCE", "COUNT", "0", "AS", "count"
)

puts "   Average price by brand:"
# Results format: [count, [field1, value1, field2, value2], ...]
(1...results.size).each do |i|
  row = results[i]
  brand = row[1]
  avg_price = row[3].to_f.round(2)
  count = row[5]
  puts "     #{brand}: $#{avg_price} (#{count} products)"
end

puts "\n"

# ============================================================================
# Auto-Complete with Search
# ============================================================================

puts "5. Auto-complete suggestions..."

# Create suggestion dictionary
begin
  redis.ft_sugadd("product_names", "Laptop", 10)
  redis.ft_sugadd("product_names", "Wireless Mouse", 8)
  redis.ft_sugadd("product_names", "Mechanical Keyboard", 7)
  redis.ft_sugadd("product_names", "USB-C Hub", 5)
  redis.ft_sugadd("product_names", "Monitor 27\"", 6)
  puts "   Created auto-complete dictionary"
rescue RR::CommandError => e
  puts "   Dictionary already exists"
end

# Get suggestions
suggestions = redis.ft_sugget("product_names", "m")
puts "   Suggestions for 'm': #{suggestions.inspect}\n\n"

# ============================================================================
# Cleanup
# ============================================================================

puts "6. Cleanup..."

# Delete products
(1..5).each { |i| redis.del("product:#{i}") }

# Drop index
begin
  redis.ft_dropindex("products_idx")
  puts "   Dropped search index"
rescue RR::CommandError
  # Index might not exist
end

redis.close
puts "   Cleaned up and closed connection\n\n"
```

## Running the Example

Make sure Redis is running:

```bash
# Redis 8.6 (recommended)
docker run -p 6379:6379 redis:latest
```

Then run the example:

```bash
ruby redis_stack.rb
```

## Key Takeaways

1. **JSON** - Store, query, and update JSON documents efficiently
2. **Search** - Full-text search with indexing and aggregation
3. **Combined Power** - Use JSON storage with Search indexing
4. **Performance** - Fast queries on large datasets
5. **Rich Queries** - Text search, tag filters, numeric ranges, aggregations

## Next Steps

- [JSON Guide](/advanced-features/json/) - Detailed JSON documentation
- [Search Guide](/advanced-features/search/) - Detailed Search documentation
- [Getting Started](/getting-started/) - Basic Redis operations

