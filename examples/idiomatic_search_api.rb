#!/usr/bin/env ruby
# frozen_string_literal: true

# Example demonstrating the new idiomatic Ruby API for Redis Search
#
# This shows the difference between the low-level API and the new
# Ruby-esque DSL and builder patterns.

require "bundler/setup"
require "redis_ruby"

redis = RedisRuby::Client.new(url: "redis://localhost:6379")

puts "=" * 80
puts "Idiomatic Ruby API for Redis Search"
puts "=" * 80
puts

# ============================================================
# Example 1: Index Creation - Old vs New
# ============================================================

puts "1. INDEX CREATION"
puts "-" * 80

# OLD WAY: Flat positional string arguments
puts "\n❌ Old (still works, but not idiomatic):"
puts <<~RUBY
  redis.ft_create("products",
    "ON", "HASH",
    "PREFIX", 1, "product:",
    "SCHEMA",
      "name", "TEXT", "SORTABLE",
      "description", "TEXT",
      "price", "NUMERIC", "SORTABLE",
      "category", "TAG")
RUBY

# NEW WAY: DSL with blocks and symbols
puts "\n✅ New (idiomatic Ruby):"
puts <<~RUBY
  redis.search_index(:products) do
    on :hash
    prefix "product:"
  #{"  "}
    schema do
      text :name, sortable: true, weight: 5.0
      text :description
      numeric :price, sortable: true
      tag :category
    end
  end
RUBY

# Actually create the index using the new API
begin
  redis.ft_dropindex("products", delete_docs: true)
rescue RedisRuby::CommandError
  # Index doesn't exist yet
end

redis.search_index(:products) do
  on :hash
  prefix "product:"

  schema do
    text :name, sortable: true, weight: 5.0
    text :description
    numeric :price, sortable: true
    tag :category
    tag :brand
  end
end

puts "\n✓ Index created successfully!"

# ============================================================
# Example 2: Add Sample Data
# ============================================================

puts "\n2. ADDING SAMPLE DATA"
puts "-" * 80

products = [
  { id: 1, name: "Laptop", description: "High-performance laptop", price: 1200, category: "electronics",
    brand: "TechCo", },
  { id: 2, name: "Mouse", description: "Wireless mouse", price: 25, category: "electronics", brand: "TechCo" },
  { id: 3, name: "Keyboard", description: "Mechanical keyboard", price: 150, category: "electronics",
    brand: "KeyMaster", },
  { id: 4, name: "Desk", description: "Standing desk", price: 500, category: "furniture", brand: "OfficePro" },
  { id: 5, name: "Chair", description: "Ergonomic chair", price: 300, category: "furniture", brand: "OfficePro" },
]

products.each do |product|
  redis.hset("product:#{product[:id]}",
             "name", product[:name],
             "description", product[:description],
             "price", product[:price],
             "category", product[:category],
             "brand", product[:brand])
end

puts "✓ Added #{products.size} products"
sleep 0.1 # Give Redis time to index

# ============================================================
# Example 3: Searching - Old vs New
# ============================================================

puts "\n3. SEARCHING"
puts "-" * 80

# OLD WAY: Keyword arguments (already pretty good)
puts "\n❌ Old (keyword args):"
puts <<~RUBY
  redis.ft_search("products", "@category:{electronics}",
    filter: { price: [0, 1000] },
    sortby: "price",
    sortasc: true,
    limit: [0, 10],
    withscores: true)
RUBY

results = redis.ft_search("products", "@category:{electronics}",
                          filter: { price: [0, 1000] },
                          sortby: "price",
                          sortasc: true,
                          limit: [0, 10])
puts "Found #{results[0]} results"

# NEW WAY: Fluent builder pattern
puts "\n✅ New (fluent builder):"
puts <<~RUBY
  redis.search(:products)
    .query("@category:{electronics}")
    .filter(:price, 0..1000)
    .sort_by(:price, :asc)
    .limit(10)
    .with_scores
    .execute
RUBY

results = redis.search(:products)
  .query("@category:{electronics}")
  .filter(:price, 0..1000)
  .sort_by(:price, :asc)
  .limit(10)
  .execute

puts "Found #{results[0]} results:"
results[1..].each_slice(2) do |key, fields|
  puts "  - #{key}: #{fields[1]} ($#{fields[3]})"
end

# ============================================================
# Example 4: Complex Query
# ============================================================

puts "\n4. COMPLEX QUERY WITH MULTIPLE FILTERS"
puts "-" * 80

results = redis.search(:products)
  .query("*")
  .filter(:price, 100..600)
  .in_fields(:name, :description)
  .sort_by(:price, :desc)
  .limit(5)
  .execute

puts "Products between $100-$600 (sorted by price desc):"
results[1..].each_slice(2) do |_key, fields|
  puts "  - #{fields[1]}: $#{fields[3]}"
end

puts "\n#{"=" * 80}"
puts "✓ All examples completed successfully!"
puts "=" * 80
