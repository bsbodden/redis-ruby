# HyperLogLog Idiomatic API Proposal

## Overview

Create an idiomatic Ruby API for Redis HyperLogLog that provides a fluent interface for probabilistic cardinality estimation. HyperLogLog is perfect for counting unique elements (like unique visitors, unique events) with minimal memory usage (~12KB regardless of set size).

## Design Goals

1. **Probabilistic Counting** - Efficient cardinality estimation with ~0.81% standard error
2. **Chainable Operations** - Fluent API for multiple operations
3. **Composite Keys** - Automatic `:` joining for multi-part keys
4. **Memory Efficient** - ~12KB per HyperLogLog regardless of cardinality
5. **Merge Support** - Combine multiple HyperLogLogs for aggregation
6. **Ruby-esque Interface** - Methods like `count`, `size`, `length`, `empty?`

## API Design

### Entry Point

```ruby
# In lib/redis_ruby/commands/hyperloglog.rb
module RedisRuby
  module Commands
    module HyperLogLog
      # Create a HyperLogLog proxy for idiomatic operations
      #
      # @param key_parts [Array<String, Symbol, Integer>] Key components
      # @return [RedisRuby::DSL::HyperLogLogProxy]
      def hyperloglog(*key_parts)
        DSL::HyperLogLogProxy.new(self, *key_parts)
      end
      
      # Alias for hyperloglog
      alias hll hyperloglog
    end
  end
end
```

### Core API

```ruby
# Basic operations
visitors = redis.hyperloglog(:visitors, :today)
# or use the shorter alias
visitors = redis.hll(:visitors, :today)

# Add elements
visitors.add("user:123")                    # PFADD visitors:today user:123
visitors.add("user:456", "user:789")        # PFADD visitors:today user:456 user:789

# Get cardinality estimate
visitors.count                              # => 3 (PFCOUNT visitors:today)
visitors.size                               # Alias for count
visitors.length                             # Alias for count

# Check existence
visitors.exists?                            # => true (EXISTS visitors:today)
visitors.empty?                             # => false (EXISTS + PFCOUNT check)

# Chainable operations
redis.hll(:visitors, :today)
  .add("user:1", "user:2", "user:3")
  .expire(86400)

# Merge HyperLogLogs
daily = redis.hll(:visitors, :daily)
weekly = redis.hll(:visitors, :weekly)

# Merge other HLLs into current key
weekly.merge("visitors:day1", "visitors:day2", "visitors:day3")

# Merge current and others into a destination
daily.merge_into("visitors:weekly", "visitors:day2", "visitors:day3")

# Clear/delete
visitors.delete                             # DEL visitors:today
visitors.clear                              # Alias for delete

# Expiration
visitors.expire(3600)                       # EXPIRE visitors:today 3600
visitors.expire_at(Time.now + 3600)         # EXPIREAT visitors:today ...
visitors.ttl                                # => 3599 (TTL visitors:today)
visitors.persist                            # PERSIST visitors:today
```

## Use Cases

### 1. Unique Visitor Counting

```ruby
# Track unique visitors per day
today = redis.hll(:visitors, Date.today.to_s)
today.add("user:123", "user:456", "user:789")

puts "Unique visitors today: #{today.count}"

# Merge daily counts into weekly
weekly = redis.hll(:visitors, :weekly)
weekly.merge(
  "visitors:2024-01-01",
  "visitors:2024-01-02",
  "visitors:2024-01-03"
)
puts "Unique visitors this week: #{weekly.count}"
```

### 2. Unique Event Tracking

```ruby
# Track unique events per user
user_events = redis.hll(:events, :user, 123)
user_events.add("page_view", "button_click", "form_submit")

puts "Unique event types: #{user_events.count}"
```

### 3. A/B Testing

```ruby
# Track unique users in each variant
variant_a = redis.hll(:experiment, :checkout, :variant_a)
variant_b = redis.hll(:experiment, :checkout, :variant_b)

variant_a.add("user:1", "user:2", "user:3")
variant_b.add("user:4", "user:5")

puts "Variant A: #{variant_a.count} unique users"
puts "Variant B: #{variant_b.count} unique users"
```

## Implementation Details

### Class Structure

```ruby
module RedisRuby
  module DSL
    class HyperLogLogProxy
      attr_reader :key
      
      def initialize(redis, *key_parts)
        @redis = redis
        @key = key_parts.map(&:to_s).join(":")
      end
      
      # Add elements to HyperLogLog
      def add(*elements)
        return self if elements.empty?
        @redis.pfadd(@key, *elements.map(&:to_s))
        self
      end
      
      # Get cardinality estimate
      def count
        @redis.pfcount(@key)
      end
      
      alias size count
      alias length count
      
      # Merge other HLLs into this one
      def merge(*other_keys)
        return self if other_keys.empty?
        @redis.pfmerge(@key, @key, *other_keys.map(&:to_s))
        self
      end
      
      # Merge this and other HLLs into destination
      def merge_into(destination_key, *other_keys)
        @redis.pfmerge(destination_key.to_s, @key, *other_keys.map(&:to_s))
        self
      end
      
      # ... more methods ...
    end
  end
end
```

### Accuracy

HyperLogLog provides probabilistic cardinality estimation with:
- **Standard Error**: ~0.81%
- **Memory Usage**: ~12KB per HyperLogLog
- **Scalability**: Can estimate cardinalities up to 2^64

This means for 1,000,000 unique elements, the estimate will typically be within ±8,100 of the actual count.

### Redis Commands Used

- `PFADD` - Add elements
- `PFCOUNT` - Get cardinality estimate
- `PFMERGE` - Merge HyperLogLogs
- `DEL` - Delete HyperLogLog
- `EXISTS` - Check if key exists
- `EXPIRE`, `EXPIREAT`, `TTL`, `PERSIST` - Expiration management

