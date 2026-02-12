# Redis Sets - Idiomatic Ruby API Proposal

## Overview

This proposal introduces an idiomatic Ruby interface for Redis Sets, following the same design patterns established for Hashes, Sorted Sets, and Lists. The API makes Redis sets feel like native Ruby Set objects while maintaining the power and performance of Redis operations.

## Design Goals

1. **Ruby-esque Interface**: Make Redis sets feel like Ruby's native Set class
2. **Chainable Operations**: Support method chaining for fluent API design
3. **Composite Keys**: Support multi-part keys with automatic ":" joining
4. **Set Operations**: First-class support for union, intersection, and difference
5. **Type Conversion**: Automatic symbol-to-string conversion for consistency
6. **Expiration Support**: Built-in TTL management

## Entry Point

```ruby
# Create a set proxy with composite key support
redis.redis_set(*key_parts) # => RedisRuby::DSL::SetProxy
```

### Examples

```ruby
# Single key part
tags = redis.redis_set(:tags)

# Composite keys
user_tags = redis.redis_set(:user, 123, :tags)  # => "user:123:tags"
post_tags = redis.redis_set(:post, 456, :tags) # => "post:456:tags"
```

## Core API

### Add Operations

```ruby
# Add single or multiple members
tags.add("ruby", "redis", "database")
tags << "performance"  # Alias for add

# Chainable
tags.add("tag1").add("tag2").expire(3600)
```

### Removal Operations

```ruby
# Remove members
tags.remove("old_tag")
tags.remove("tag1", "tag2", "tag3")
tags.delete("tag")  # Alias for remove

# Clear all members
tags.clear
```

### Membership Testing

```ruby
# Check if member exists
tags.member?("ruby")      # => true
tags.include?("python")   # => false (alias)
```

### Inspection

```ruby
# Get all members
tags.members              # => ["ruby", "redis", "database"]
tags.to_a                 # => ["ruby", "redis", "database"] (alias)

# Size operations
tags.size                 # => 3
tags.length               # => 3 (alias)
tags.count                # => 3 (alias)
tags.empty?               # => false
tags.exists?              # => true
```

### Set Operations

```ruby
# Union - members in any set
all_tags = tags.union(:post_tags, :article_tags)

# Intersection - members in all sets
common_tags = tags.intersect(:post_tags, :article_tags)

# Difference - members in first set but not others
unique_tags = tags.difference(:post_tags, :article_tags)
```

### Random Operations

```ruby
# Get random member(s) without removing
tags.random              # => "ruby"
tags.random(3)           # => ["ruby", "redis", "database"]

# Pop random member(s) - removes from set
tags.pop                 # => "ruby"
tags.pop(2)              # => ["redis", "database"]
```

### Iteration

```ruby
# Iterate over members
tags.each { |tag| puts tag }
tags.each_member { |tag| puts tag }  # Alias

# Returns enumerator without block
tags.each.map(&:upcase)
```

### Expiration

```ruby
# Set expiration
tags.expire(3600)                    # Expire in 1 hour
tags.expire_at(Time.now + 3600)      # Expire at timestamp

# Check TTL
tags.ttl                             # => 3599

# Remove expiration
tags.persist
```

## Use Cases

### 1. Tag Management

```ruby
post_tags = redis.redis_set(:post, 123, :tags)
post_tags.add("ruby", "redis", "tutorial")

# Find posts with common tags
common = post_tags.intersect("post:456:tags")
```

### 2. Unique Collections

```ruby
visitors = redis.redis_set(:visitors, :today)
visitors.add("user:123", "user:456", "user:789")
puts "Unique visitors: #{visitors.size}"
```

### 3. Set Operations

```ruby
# Users who like both products
product_a_fans = redis.redis_set(:product, "A", :fans)
product_b_fans = redis.redis_set(:product, "B", :fans)
both = product_a_fans.intersect("product:B:fans")
```

### 4. Random Selection

```ruby
# Pick random winner from participants
participants = redis.redis_set(:contest, :participants)
winner = participants.pop  # Remove and return random member
```

## Implementation Details

### Class Structure

```ruby
module RedisRuby
  module DSL
    class SetProxy
      attr_reader :key
      
      def initialize(redis, *key_parts)
        @redis = redis
        @key = build_key(*key_parts)
      end
      
      private
      
      def build_key(*parts)
        parts.map(&:to_s).join(":")
      end
    end
  end
end
```

### Method Chaining

Methods that modify the set return `self` for chaining:
- `add(*members)`
- `remove(*members)`
- `clear`
- `expire(seconds)`
- `expire_at(timestamp)`
- `persist`

### Type Conversion

All member arguments are converted to strings using `.to_s`:
```ruby
tags.add(:ruby, :redis)  # Converts symbols to strings
tags.member?(:ruby)      # Converts symbol for lookup
```

### Redis Commands Used

- `SADD` - Add members
- `SREM` - Remove members
- `SISMEMBER` - Check membership
- `SMEMBERS` - Get all members
- `SCARD` - Get cardinality
- `SPOP` - Pop random member
- `SRANDMEMBER` - Get random member
- `SUNION` - Union operation
- `SINTER` - Intersection operation
- `SDIFF` - Difference operation
- `SSCAN` - Iterate members
- `DEL` - Clear set
- `EXPIRE`, `EXPIREAT`, `TTL`, `PERSIST` - Expiration management

