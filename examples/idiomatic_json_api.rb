#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/redis_ruby"

# Connect to Redis
redis = RedisRuby::Client.new(host: "localhost", port: 6379)

puts "=" * 80
puts "Idiomatic Ruby API for JSON Operations"
puts "=" * 80
puts

# ============================================================
# Example 1: Basic Set and Get
# ============================================================
puts "Example 1: Basic Set and Get"
puts "-" * 40

# Old way (still works)
redis.json_set("user:old", "$", { name: "Alice", age: 30 })
result = redis.json_get("user:old", "$.name")
puts "Old API: #{result.inspect}"

# New idiomatic way
redis.json(:user, :new).set(name: "Alice", age: 30)
result = redis.json(:user, :new).get(:name)
puts "New API: #{result.inspect}"

puts

# ============================================================
# Example 2: Chaining Operations
# ============================================================
puts "Example 2: Chaining Operations"
puts "-" * 40

# Create a user and perform multiple operations in a chain
redis.json(:user, 1)
  .set(name: "Bob", age: 25, score: 100, active: true)
  .increment(:age, 1)
  .increment(:score, 50)

puts "Name: #{redis.json(:user, 1).get(:name)}"
puts "Age: #{redis.json(:user, 1).get(:age)}"
puts "Score: #{redis.json(:user, 1).get(:score)}"

puts

# ============================================================
# Example 3: Symbol-Based Paths
# ============================================================
puts "Example 3: Symbol-Based Paths"
puts "-" * 40

redis.json(:product, 123).set(
  name: "Laptop",
  price: 999.99,
  stock: 50,
  tags: %w[electronics computers]
)

# Access using symbols (more Ruby-esque)
puts "Product: #{redis.json(:product, 123).get(:name)}"
puts "Price: $#{redis.json(:product, 123).get(:price)}"
puts "Stock: #{redis.json(:product, 123).get(:stock)}"
puts "Tags: #{redis.json(:product, 123).get(:tags).inspect}"

puts

# ============================================================
# Example 4: Array Operations
# ============================================================
puts "Example 4: Array Operations"
puts "-" * 40

redis.json(:post, 1).set(
  title: "Redis JSON Tutorial",
  tags: %w[redis json]
)

# Append to array
redis.json(:post, 1).append(:tags, "ruby", "tutorial")
puts "Tags after append: #{redis.json(:post, 1).get(:tags).inspect}"

# Array operations
puts "Array length: #{redis.json(:post, 1).array_length(:tags)}"
puts "Index of 'ruby': #{redis.json(:post, 1).array_index(:tags, "ruby")}"

# Pop from array
popped = redis.json(:post, 1).array_pop(:tags)
puts "Popped: #{popped}"
puts "Tags after pop: #{redis.json(:post, 1).get(:tags).inspect}"

puts

# ============================================================
# Example 5: Numeric Operations
# ============================================================
puts "Example 5: Numeric Operations"
puts "-" * 40

redis.json(:counter, :stats).set(
  views: 100,
  likes: 50,
  multiplier: 2
)

# Increment
redis.json(:counter, :stats).increment(:views, 10)
puts "Views after increment: #{redis.json(:counter, :stats).get(:views)}"

# Decrement
redis.json(:counter, :stats).decrement(:likes, 5)
puts "Likes after decrement: #{redis.json(:counter, :stats).get(:likes)}"

# Multiply
redis.json(:counter, :stats).multiply(:multiplier, 3)
puts "Multiplier after multiply: #{redis.json(:counter, :stats).get(:multiplier)}"

puts

# ============================================================
# Example 6: Object Operations
# ============================================================
puts "Example 6: Object Operations"
puts "-" * 40

redis.json(:config, :app).set(
  database: { host: "localhost", port: 5432 },
  cache: { ttl: 3600, enabled: true }
)

# Get object keys
keys = redis.json(:config, :app).keys(:database)
puts "Database config keys: #{keys.inspect}"

# Get object length
length = redis.json(:config, :app).object_length(:cache)
puts "Cache config has #{length} keys"

puts

# ============================================================
# Example 7: Type Checking
# ============================================================
puts "Example 7: Type Checking"
puts "-" * 40

redis.json(:data, :types).set(
  string_val: "hello",
  number_val: 42,
  array_val: [1, 2, 3],
  object_val: { key: "value" },
  bool_val: true
)

puts "string_val type: #{redis.json(:data, :types).type(:string_val)}"
puts "number_val type: #{redis.json(:data, :types).type(:number_val)}"
puts "array_val type: #{redis.json(:data, :types).type(:array_val)}"
puts "object_val type: #{redis.json(:data, :types).type(:object_val)}"
puts "bool_val type: #{redis.json(:data, :types).type(:bool_val)}"

puts

# ============================================================
# Example 8: Boolean Toggle
# ============================================================
puts "Example 8: Boolean Toggle"
puts "-" * 40

redis.json(:feature, :flags).set(dark_mode: true, notifications: false)

puts "Dark mode: #{redis.json(:feature, :flags).get(:dark_mode)}"
redis.json(:feature, :flags).toggle(:dark_mode)
puts "Dark mode after toggle: #{redis.json(:feature, :flags).get(:dark_mode)}"

puts

# ============================================================
# Cleanup
# ============================================================
puts "Cleaning up..."
redis.del("user:old", "user:new", "user:1", "product:123", "post:1",
          "counter:stats", "config:app", "data:types", "feature:flags")

puts "Done!"
