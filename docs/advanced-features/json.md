---
layout: default
title: JSON
parent: Advanced Features
nav_order: 2
permalink: /advanced-features/json/
---

# JSON

Redis provides native JSON document storage with support for JSONPath queries, atomic operations, and efficient memory usage. It's perfect for storing and manipulating structured data.

## Table of Contents

- [Storing JSON Documents](#storing-json-documents)
- [JSONPath Queries](#jsonpath-queries)
- [Updating JSON](#updating-json)
- [Array Operations](#array-operations)
- [Advanced Features](#advanced-features)

## Storing JSON Documents

### Basic Operations

```ruby
# Set a JSON document
redis.json_set("user:1", "$", {
  name: "Alice Johnson",
  age: 30,
  email: "alice@example.com",
  address: {
    street: "123 Main St",
    city: "New York",
    zip: "10001"
  },
  tags: ["developer", "ruby", "redis"]
})

# Get entire document
user = redis.json_get("user:1")
# => [{"name"=>"Alice Johnson", "age"=>30, ...}]

# Get specific path
name = redis.json_get("user:1", "$.name")
# => ["Alice Johnson"]

# Get multiple paths
data = redis.json_get("user:1", "$.name", "$.email")
# => {"$.name"=>["Alice Johnson"], "$.email"=>["alice@example.com"]}
```

### Conditional Set Operations

```ruby
# Set only if path doesn't exist (NX)
redis.json_set("user:1", "$.phone", "555-1234", nx: true)

# Set only if path exists (XX)
redis.json_set("user:1", "$.age", 31, xx: true)

# Check if set was successful
result = redis.json_set("user:1", "$.new_field", "value", nx: true)
# => "OK" if set, nil if path already exists
```

### Multiple Documents

```ruby
# Get same path from multiple documents
results = redis.json_mget("user:1", "user:2", "user:3", path: "$.name")
# => [["Alice Johnson"], ["Bob Smith"], ["Charlie Brown"]]

# Delete a document
redis.json_del("user:1")

# Delete specific path
redis.json_del("user:1", "$.address.zip")
```

## JSONPath Queries

### Path Syntax

```ruby
# Root path
redis.json_get("user:1", "$")

# Nested object
redis.json_get("user:1", "$.address.city")
# => ["New York"]

# Array element
redis.json_get("user:1", "$.tags[0]")
# => ["developer"]

# Array slice
redis.json_get("user:1", "$.tags[0:2]")
# => [["developer", "ruby"]]

# All array elements
redis.json_get("user:1", "$.tags[*]")
# => ["developer", "ruby", "redis"]

# Recursive descent
redis.json_get("user:1", "$..city")
# => ["New York"]
```

### Type Checking

```ruby
# Get type of value at path
type = redis.json_type("user:1", "$.name")
# => ["string"]

type = redis.json_type("user:1", "$.tags")
# => ["array"]

type = redis.json_type("user:1", "$.address")
# => ["object"]
```

## Updating JSON

### Numeric Operations

```ruby
# Increment numeric value
redis.json_numincrby("user:1", "$.age", 1)
# => [31]

# Decrement (negative increment)
redis.json_numincrby("user:1", "$.age", -1)
# => [30]

# Multiply numeric value
redis.json_nummultby("user:1", "$.age", 2)
# => [60]
```

### String Operations

```ruby
# Append to string
redis.json_strappend("user:1", "$.name", " (Admin)")
# => [20]  # New length

result = redis.json_get("user:1", "$.name")
# => ["Alice Johnson (Admin)"]

# Get string length
length = redis.json_strlen("user:1", "$.name")
# => [20]
```

### Object Operations

```ruby
# Get object keys
keys = redis.json_objkeys("user:1", "$.address")
# => [["street", "city", "zip"]]

# Get object length (number of keys)
length = redis.json_objlen("user:1", "$.address")
# => [3]

# Update nested object
redis.json_set("user:1", "$.address.country", "USA")
```

### Boolean Operations

```ruby
# Set boolean value
redis.json_set("user:1", "$.active", true)

# Toggle boolean
redis.json_toggle("user:1", "$.active")
# => [false]

redis.json_toggle("user:1", "$.active")
# => [true]
```

## Array Operations

### Adding Elements

```ruby
# Append to array
redis.json_arrappend("user:1", "$.tags", "python", "javascript")
# => [5]  # New array length

# Insert at specific position
redis.json_arrinsert("user:1", "$.tags", 1, "golang")
# => [6]  # New array length

# Result: ["developer", "golang", "ruby", "redis", "python", "javascript"]
```

### Removing Elements

```ruby
# Pop from end of array
popped = redis.json_arrpop("user:1", "$.tags")
# => ["javascript"]

# Pop from specific index
popped = redis.json_arrpop("user:1", "$.tags", 0)
# => ["developer"]

# Trim array to range
redis.json_arrtrim("user:1", "$.tags", 0, 2)
# => [3]  # New array length
# Keeps only first 3 elements
```

### Array Queries

```ruby
# Get array length
length = redis.json_arrlen("user:1", "$.tags")
# => [3]

# Find index of element
index = redis.json_arrindex("user:1", "$.tags", "ruby")
# => [1]

# Element not found
index = redis.json_arrindex("user:1", "$.tags", "java")
# => [-1]

# Search with start and stop positions
index = redis.json_arrindex("user:1", "$.tags", "ruby", 0, 5)
# => [1]
```

## Advanced Features

### Clear Values

```ruby
# Clear array (set to empty array)
redis.json_clear("user:1", "$.tags")

# Clear object (set to empty object)
redis.json_clear("user:1", "$.address")

# Clear numeric (set to 0)
redis.json_clear("user:1", "$.age")
```

### Memory Usage

```ruby
# Get memory usage of JSON document
memory = redis.json_debug_memory("user:1")
# => 256  # bytes

# Get memory for specific path
memory = redis.json_debug_memory("user:1", "$.address")
# => 64  # bytes
```

### Complex Document Example

```ruby
# E-commerce order document
redis.json_set("order:1001", "$", {
  order_id: "1001",
  customer: {
    id: "user:1",
    name: "Alice Johnson",
    email: "alice@example.com"
  },
  items: [
    {
      product_id: "prod:101",
      name: "Laptop Pro",
      quantity: 1,
      price: 1299.99
    },
    {
      product_id: "prod:102",
      name: "Wireless Mouse",
      quantity: 2,
      price: 29.99
    }
  ],
  total: 1359.97,
  status: "pending",
  created_at: Time.now.iso8601
})

# Update order status
redis.json_set("order:1001", "$.status", "shipped")

# Add tracking number
redis.json_set("order:1001", "$.tracking", "TRACK123456")

# Update item quantity
redis.json_numincrby("order:1001", "$.items[1].quantity", 1)

# Recalculate total
redis.json_set("order:1001", "$.total", 1389.96)
```

## Integration with RediSearch

### Indexing JSON Documents

```ruby
# Create search index on JSON documents
redis.ft_create("users",
  "ON", "JSON",
  "PREFIX", 1, "user:",
  "SCHEMA",
    "$.name", "AS", "name", "TEXT",
    "$.email", "AS", "email", "TAG",
    "$.age", "AS", "age", "NUMERIC", "SORTABLE",
    "$.address.city", "AS", "city", "TAG",
    "$.tags[*]", "AS", "tags", "TAG")

# Search JSON documents
results = redis.ft_search("users", "@city:{New York}")

# Search by tag
results = redis.ft_search("users", "@tags:{developer}")

# Numeric range search
results = redis.ft_search("users", "@age:[25 35]")
```

### Aggregations on JSON

```ruby
# Group users by city
results = redis.ft_aggregate("users", "*",
  "GROUPBY", 1, "@city",
  "REDUCE", "COUNT", 0, "AS", "count")

# Average age by city
results = redis.ft_aggregate("users", "*",
  "GROUPBY", 1, "@city",
  "REDUCE", "AVG", 1, "@age", "AS", "avg_age")
```

## Common Patterns

### User Profile Management

```ruby
# Create user profile
redis.json_set("user:#{user_id}", "$", {
  id: user_id,
  username: "alice",
  profile: {
    first_name: "Alice",
    last_name: "Johnson",
    bio: "Software developer",
    avatar_url: "https://example.com/avatar.jpg"
  },
  settings: {
    notifications: true,
    theme: "dark",
    language: "en"
  },
  stats: {
    posts: 0,
    followers: 0,
    following: 0
  }
})

# Update setting
redis.json_set("user:#{user_id}", "$.settings.theme", "light")

# Increment post count
redis.json_numincrby("user:#{user_id}", "$.stats.posts", 1)

# Add to profile
redis.json_set("user:#{user_id}", "$.profile.location", "New York")
```

### Configuration Management

```ruby
# Application configuration
redis.json_set("config:app", "$", {
  app_name: "MyApp",
  version: "1.0.0",
  features: {
    search: true,
    analytics: true,
    notifications: false
  },
  limits: {
    max_upload_size: 10485760,  # 10MB
    rate_limit: 1000,
    timeout: 30
  },
  integrations: [
    { name: "stripe", enabled: true, api_key: "sk_test_..." },
    { name: "sendgrid", enabled: true, api_key: "SG..." }
  ]
})

# Toggle feature
redis.json_toggle("config:app", "$.features.notifications")

# Update limit
redis.json_numincrby("config:app", "$.limits.rate_limit", 500)

# Get specific config
timeout = redis.json_get("config:app", "$.limits.timeout")
```

### Session Storage

```ruby
# Store session data
redis.json_set("session:#{session_id}", "$", {
  user_id: "user:1",
  created_at: Time.now.to_i,
  last_activity: Time.now.to_i,
  data: {
    cart: ["item:1", "item:2"],
    preferences: { currency: "USD", language: "en" }
  }
})

# Update last activity
redis.json_set("session:#{session_id}", "$.last_activity", Time.now.to_i)

# Add item to cart
redis.json_arrappend("session:#{session_id}", "$.data.cart", "item:3")

# Set expiration on session
redis.expire("session:#{session_id}", 3600)  # 1 hour
```

## Performance Tips

1. **Use specific paths** - Query specific paths instead of entire documents
2. **Batch operations** - Use pipelines for multiple JSON operations
3. **Index strategically** - Only index JSON fields you need to search
4. **Avoid deep nesting** - Keep document structure relatively flat
5. **Use appropriate data types** - Store numbers as numbers, not strings

## Error Handling

```ruby
begin
  redis.json_set("user:1", "$.invalid.path", "value", xx: true)
rescue RedisRuby::CommandError => e
  puts "Error: #{e.message}"
  # Handle path not found, type mismatch, etc.
end

# Check if path exists before updating
type = redis.json_type("user:1", "$.optional_field")
if type && !type.empty?
  redis.json_set("user:1", "$.optional_field", "new_value")
end
```

## Next Steps

- [Search & Query Documentation](/advanced-features/search/) - Index and search JSON documents
- [RedisJSON Commands Reference](https://redis.io/commands/?group=json)
- [JSONPath Syntax Guide](https://redis.io/docs/stack/json/path/)

## Resources

- [RedisJSON Documentation](https://redis.io/docs/stack/json/)
- [JSONPath Specification](https://goessner.net/articles/JsonPath/)
- [GitHub Examples](https://github.com/redis/redis-ruby/tree/main/examples)

