# Bitmap Idiomatic API Proposal

## Overview

Create an idiomatic Ruby API for Redis Bitmaps that provides a fluent interface for bit-level operations. Bitmaps are perfect for tracking boolean states (like user activity, feature flags, permissions) with extremely efficient memory usage.

## Design Goals

1. **Bit Operations** - Set, get, and count individual bits efficiently
2. **Bitwise Operations** - AND, OR, XOR, NOT operations on bitmaps
3. **Chainable Operations** - Fluent API for multiple operations
4. **Composite Keys** - Automatic `:` joining for multi-part keys
5. **Memory Efficient** - 1 bit per element (vs 1 byte minimum for other structures)
6. **Ruby-esque Interface** - Methods like `[]`, `[]=`, `empty?`, `count`
7. **Bitfield Support** - Complex bitfield operations via builder pattern

## API Design

### Entry Point

```ruby
# In lib/redis_ruby/commands/bitmap.rb
module RedisRuby
  module Commands
    module Bitmap
      # Create a bitmap proxy for idiomatic operations
      #
      # @param key_parts [Array<String, Symbol, Integer>] Key components
      # @return [RedisRuby::DSL::BitmapProxy]
      def bitmap(*key_parts)
        DSL::BitmapProxy.new(self, *key_parts)
      end
    end
  end
end
```

### Core API

```ruby
# Basic bit operations
activity = redis.bitmap(:user_activity, Date.today.to_s)

# Set bit (two syntaxes)
activity.set_bit(user_id, 1)                # SETBIT user_activity:2024-01-15 123 1
activity[user_id] = 1                       # Same as above

# Get bit (two syntaxes)
activity.get_bit(user_id)                   # => 1 (GETBIT user_activity:2024-01-15 123)
activity[user_id]                           # => 1 (Same as above)

# Count set bits
activity.count                              # => 42 (BITCOUNT user_activity:2024-01-15)
activity.count(0, 10)                       # Count in byte range 0-10

# Find first occurrence of bit
activity.position(1)                        # => 5 (BITPOS - first 1 bit)
activity.position(0, 10)                    # => 15 (first 0 bit starting at byte 10)

# Bitwise operations (destructive - modifies current key)
result = redis.bitmap(:result)
result.and(:bitmap1, :bitmap2)              # BITOP AND result bitmap1 bitmap2
result.or(:bitmap1, :bitmap2, :bitmap3)     # BITOP OR result bitmap1 bitmap2 bitmap3
result.xor(:bitmap1, :bitmap2)              # BITOP XOR result bitmap1 bitmap2
result.not(:bitmap1)                        # BITOP NOT result bitmap1

# Bitwise operations (non-destructive - stores in different key)
bitmap1 = redis.bitmap(:bitmap1)
bitmap1.and_into(:result, :bitmap2)         # BITOP AND result bitmap1 bitmap2
bitmap1.or_into(:result, :bitmap2, :bitmap3)
bitmap1.xor_into(:result, :bitmap2)
bitmap1.not_into(:result)                   # BITOP NOT result bitmap1

# Bitfield operations (complex multi-value storage)
bitmap = redis.bitmap(:counters)
bitmap.bitfield
  .set(:u8, 0, 100)                         # Set 8-bit unsigned int at offset 0
  .incrby(:u8, 0, 10)                       # Increment by 10
  .get(:u8, 0)                              # Get value
  .execute                                  # => [0, 110, 110]

# Chainable operations
redis.bitmap(:flags)
  .set_bit(0, 1)
  .set_bit(1, 1)
  .set_bit(2, 0)
  .expire(3600)

# Existence and cleanup
activity.exists?                            # => true (EXISTS)
activity.empty?                             # => false (EXISTS + BITCOUNT check)
activity.delete                             # DEL
activity.clear                              # Alias for delete

# Expiration
activity.expire(86400)                      # EXPIRE user_activity:2024-01-15 86400
activity.expire_at(Time.now + 86400)        # EXPIREAT
activity.ttl                                # => 86399 (TTL)
activity.persist                            # PERSIST
```

## Use Cases

### 1. Daily Active Users Tracking

```ruby
# Track which users were active today
today = redis.bitmap(:dau, Date.today.to_s)
today[user_id] = 1

# Count daily active users
puts "DAU: #{today.count}"

# Find users active both today and yesterday
result = redis.bitmap(:dau, :both)
result.and("dau:#{Date.today}", "dau:#{Date.today - 1}")
puts "Active both days: #{result.count}"
```

### 2. Feature Flags

```ruby
# Track which features are enabled for a user
features = redis.bitmap(:features, :user, user_id)
features[FEATURE_SEARCH] = 1
features[FEATURE_EXPORT] = 1
features[FEATURE_API] = 0

# Check if feature is enabled
if features[FEATURE_SEARCH] == 1
  # Feature is enabled
end
```

### 3. Permissions System

```ruby
# Track permissions as bits
perms = redis.bitmap(:permissions, :user, user_id)
perms[PERM_READ] = 1
perms[PERM_WRITE] = 1
perms[PERM_DELETE] = 0

# Count total permissions
puts "User has #{perms.count} permissions"
```

### 4. Bitfield for Counters

```ruby
# Store multiple small counters in one bitmap
counters = redis.bitmap(:page_counters)
counters.bitfield
  .set(:u16, 0, 100)      # Page 1 views
  .set(:u16, 16, 200)     # Page 2 views
  .set(:u16, 32, 300)     # Page 3 views
  .execute
```

## Implementation Details

### BitmapProxy Class

```ruby
module RedisRuby
  module DSL
    class BitmapProxy
      attr_reader :key
      
      def initialize(redis, *key_parts)
        @redis = redis
        @key = key_parts.map(&:to_s).join(":")
      end
      
      # Set bit at offset
      def set_bit(offset, value)
        @redis.setbit(@key, offset, value)
        self
      end
      
      # Get bit at offset
      def get_bit(offset)
        @redis.getbit(@key, offset)
      end
      
      # Array-like access
      def []=(offset, value)
        set_bit(offset, value)
        value
      end
      
      def [](offset)
        get_bit(offset)
      end
      
      # Count set bits
      def count(start_byte = 0, end_byte = -1)
        @redis.bitcount(@key, start_byte, end_byte)
      end

      # Bitfield builder
      def bitfield
        BitFieldBuilder.new(@redis, @key)
      end

      # ... more methods ...
    end
  end
end
```

### BitFieldBuilder Class

```ruby
module RedisRuby
  module DSL
    class BitFieldBuilder
      def initialize(redis, key)
        @redis = redis
        @key = key
        @operations = []
      end

      def get(type, offset)
        @operations << ["GET", type.to_s, offset]
        self
      end

      def set(type, offset, value)
        @operations << ["SET", type.to_s, offset, value]
        self
      end

      def incrby(type, offset, increment)
        @operations << ["INCRBY", type.to_s, offset, increment]
        self
      end

      def overflow(mode)
        @operations << ["OVERFLOW", mode.to_s.upcase]
        self
      end

      def execute
        return [] if @operations.empty?
        @redis.bitfield(@key, *@operations.flatten)
      end
    end
  end
end
```

### Memory Efficiency

Bitmaps are extremely memory efficient:
- **1 bit per element** (vs 1 byte minimum for other structures)
- **Example**: 1 million users = 125KB (vs 1MB+ for sets)
- **Sparse bitmaps**: Redis optimizes storage for sparse data

### Redis Commands Used

- `SETBIT` - Set bit value at offset
- `GETBIT` - Get bit value at offset
- `BITCOUNT` - Count set bits (1s)
- `BITPOS` - Find first occurrence of bit (0 or 1)
- `BITOP` - Bitwise operations (AND, OR, XOR, NOT)
- `BITFIELD` - Complex bitfield operations
- `DEL` - Delete bitmap
- `EXISTS` - Check if key exists
- `EXPIRE`, `EXPIREAT`, `TTL`, `PERSIST` - Expiration management

## Testing Strategy

1. **Basic Operations** - Set, get, count bits
2. **Array Syntax** - `[]` and `[]=` operators
3. **Bitwise Operations** - AND, OR, XOR, NOT
4. **Bitfield Operations** - GET, SET, INCRBY with various types
5. **Edge Cases** - Empty bitmaps, large offsets, overflow handling
6. **Integration Tests** - Real-world scenarios (DAU tracking, feature flags)
7. **Chainability** - Verify all mutating methods return `self`

## Performance Considerations

1. **Sparse Bitmaps** - Redis optimizes storage for sparse data
2. **Byte Alignment** - Operations on byte boundaries are faster
3. **Bitfield Batching** - Use bitfield builder to batch multiple operations
4. **Memory Usage** - Monitor memory for very large offsets (creates sparse strings)


