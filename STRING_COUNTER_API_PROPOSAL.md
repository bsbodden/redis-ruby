# String and Counter Idiomatic API Proposal

## Overview

This proposal introduces idiomatic Ruby APIs for Redis String operations, split into two specialized proxies:
- **StringProxy**: For general string operations (configuration, caching, text storage)
- **CounterProxy**: For numeric counter operations (rate limiting, distributed counters, metrics)

This separation provides clearer semantics and better developer experience for the two primary use cases of Redis strings.

## Design Goals

1. **Intuitive Interface**: Ruby-like methods that feel natural to Ruby developers
2. **Type Safety**: Automatic type conversion (strings vs integers/floats)
3. **Chainability**: Support method chaining for fluent APIs
4. **Composite Keys**: Support multi-part keys with automatic ":" joining
5. **Atomic Operations**: Leverage Redis atomic operations for counters
6. **Consistency**: Follow patterns established by HashProxy, SortedSetProxy, etc.

## Entry Points

### String Entry Point

```ruby
# Create a string proxy for general string operations
redis.string(*key_parts) # => StringProxy

# Examples
config = redis.string(:app, :config, :api_key)  # Key: "app:config:api_key"
cache = redis.string(:cache, :user, 123)        # Key: "cache:user:123"
```

### Counter Entry Point

```ruby
# Create a counter proxy for numeric operations
redis.counter(*key_parts) # => CounterProxy

# Examples
views = redis.counter(:page, :views, 123)       # Key: "page:views:123"
rate = redis.counter(:rate_limit, :user, 456)  # Key: "rate_limit:user:456"
```

## StringProxy API

### Get/Set Operations

```ruby
str = redis.string(:config, :api_key)

# Get value
str.get()           # => "secret123" or nil
str.value           # Alias for get()

# Set value
str.set("new_value")    # => self (chainable)
str.value = "new_value" # Alias for set()

# Check existence
str.exists?()       # => true/false
str.empty?()        # => true if nil or empty string
```

### Append Operations

```ruby
log = redis.string(:log, :app)

# Append to end
log.append(" new entry")    # => self
# Note: Redis doesn't have PREPEND command
```

### Length Operations

```ruby
str = redis.string(:data)
str.set("hello world")

str.length()        # => 11
str.size()          # Alias for length()
```

### Range Operations

```ruby
str = redis.string(:text)
str.set("Hello World")

# Get substring
str.getrange(0, 4)          # => "Hello"
str.getrange(-5, -1)        # => "World"

# Set substring
str.setrange(6, "Redis")    # => self
str.get()                   # => "Hello Redis"
```

### Atomic Operations

```ruby
str = redis.string(:lock)

# Set only if not exists
str.setnx("locked")         # => true/false

# Set with expiration
str.setex(60, "temp_value") # => self (expires in 60 seconds)
```

### Expiration

```ruby
cache = redis.string(:cache, :key)

cache.expire(3600)              # Expire in 1 hour => self
cache.expire_at(Time.now + 60)  # Expire at specific time => self
cache.ttl()                     # => seconds remaining
cache.persist()                 # Remove expiration => self
```

### Clear

```ruby
str = redis.string(:temp)

str.delete()        # Delete the key => Integer (0 or 1)
str.clear()         # Alias for delete()
```

## CounterProxy API

### Get/Set Operations

```ruby
counter = redis.counter(:page, :views)

# Get value
counter.get()       # => 42 (as Integer)
counter.value       # Alias for get()
counter.to_i        # Alias for get()

# Set value
counter.set(100)        # => self (chainable)
counter.value = 100     # Alias for set()
```

### Increment/Decrement

```ruby
views = redis.counter(:views)

# Increment
views.increment()       # Increment by 1 => self
views.increment(10)     # Increment by 10 => self
views.incr              # Alias for increment()

# Decrement
views.decrement()       # Decrement by 1 => self
views.decrement(5)      # Decrement by 5 => self
views.decr              # Alias for decrement()
```

### Float Operations

```ruby
score = redis.counter(:user, :score)

# Increment by float
score.increment_float(1.5)      # => self
score.incrbyfloat(2.5)          # Alias
```

### Atomic Operations

```ruby
counter = redis.counter(:lock)

# Set only if not exists
counter.setnx(0)            # => true/false

# Get and set atomically
old_value = counter.getset(100)  # Returns old value, sets new
```

### Existence Checks

```ruby
counter = redis.counter(:visits)

counter.exists?()       # => true/false
counter.zero?()         # => true if value is 0 or doesn't exist
```

### Expiration

```ruby
counter = redis.counter(:rate_limit)

counter.expire(60)              # Expire in 60 seconds => self
counter.expire_at(Time.now + 60)  # Expire at specific time => self
counter.ttl()                   # => seconds remaining
counter.persist()               # Remove expiration => self
```

### Clear

```ruby
counter = redis.counter(:temp)

counter.delete()        # Delete the key => Integer (0 or 1)
counter.clear()         # Alias for delete()
```

## Use Cases

### Configuration Management (StringProxy)

```ruby
api_key = redis.string(:config, :api_key)
api_key.set("sk_live_123456")
api_key.expire(86400)  # Rotate daily

# Later
key = api_key.get()
```

### Caching (StringProxy)

```ruby
cache = redis.string(:cache, :user, user_id)
cache.set(user_data.to_json)
cache.expire(3600)

# Retrieve
cached_data = cache.get()
```

### Rate Limiting (CounterProxy)

```ruby
limit = redis.counter(:rate_limit, :api, user_id)
limit.increment()
limit.expire(60) unless limit.ttl() > 0

if limit.get() > 100
  raise "Rate limit exceeded"
end
```

### Distributed Counters (CounterProxy)

```ruby
views = redis.counter(:page, :views, page_id)
views.increment()

total = views.get()
```

### Page View Tracking (CounterProxy)

```ruby
daily_views = redis.counter(:views, :daily, Date.today.to_s)
daily_views.increment()
daily_views.expire(86400 * 7)  # Keep for 7 days

puts "Today's views: #{daily_views.get()}"
```

## Implementation Details

### Key Building

Both proxies use composite key building:

```ruby
def initialize(redis, *key_parts)
  @redis = redis
  @key = key_parts.map(&:to_s).join(":")
end
```

### Type Conversion

- **StringProxy**: Values are stored and retrieved as strings
- **CounterProxy**: Values are converted to integers/floats automatically

### Chainability

Methods that modify state return `self` for chaining:

```ruby
redis.string(:cache)
  .set("value")
  .expire(60)

redis.counter(:views)
  .increment(10)
  .expire(3600)
```

### Error Handling

- Operations on non-existent keys return `nil` or appropriate defaults
- Type errors are handled gracefully (e.g., incrementing non-numeric values)

## Comparison with Existing Proxies

| Feature | HashProxy | StringProxy | CounterProxy |
|---------|-----------|-------------|--------------|
| Composite Keys | ✓ | ✓ | ✓ |
| Chainability | ✓ | ✓ | ✓ |
| Expiration | ✓ | ✓ | ✓ |
| Type Conversion | Strings | Strings | Integers/Floats |
| Primary Use | Structured data | Text/Config | Numeric counters |

## Testing Strategy

1. **Unit Tests**: Test each method in isolation
2. **Integration Tests**: Test real Redis operations
3. **Workflow Tests**: Test complete use cases (caching, rate limiting, etc.)
4. **Edge Cases**: Empty values, non-existent keys, type conversions
5. **Expiration Tests**: TTL, expire, persist operations

## Migration Path

Existing code using low-level commands can gradually migrate:

```ruby
# Before
redis.set("user:#{id}:name", "John")
redis.expire("user:#{id}:name", 3600)

# After
redis.string(:user, id, :name).set("John").expire(3600)

# Before
redis.incr("page:views:#{id}")

# After
redis.counter(:page, :views, id).increment()
```

