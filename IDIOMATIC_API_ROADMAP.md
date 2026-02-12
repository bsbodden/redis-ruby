# Redis Ruby - Idiomatic API Roadmap

## Overview

This document outlines the plan to add idiomatic, Ruby-esque APIs on top of the existing low-level Redis commands. The goal is to provide high-level abstractions that are familiar to Ruby developers while maintaining full backward compatibility with the low-level API.

## Design Principles

### 1. Clear Separation of Concerns
- **Low-Level API**: `RedisRuby::Commands::*` modules - Direct Redis command wrappers
- **High-Level API**: `RedisRuby::DSL::*` classes - Idiomatic Ruby abstractions
- **Entry Points**: Methods on `RedisRuby::Client` that return DSL objects

### 2. Namespace Organization
```ruby
# Low-level commands (existing)
redis.hset("user:123", "name", "John")
redis.zadd("leaderboard", 100, "player1")

# High-level DSL (new)
redis.hash(:user, 123).set(name: "John")
redis.sorted_set(:leaderboard).add(player1: 100)
```

### 3. Backward Compatibility
- All existing low-level APIs remain unchanged
- New DSL methods are additive only
- No breaking changes to existing code

---

## Implementation Status

### ✅ Completed (10 features)

1. **Search** - `RedisRuby::DSL::SearchIndexBuilder`, `SearchQueryBuilder`
2. **JSON** - `RedisRuby::DSL::JsonProxy`
3. **Time Series** - `RedisRuby::DSL::TimeSeriesProxy`, `TimeSeriesQueryBuilder`
4. **Vector Sets** - `RedisRuby::DSL::VectorProxy`, `VectorSearchBuilder`
5. **Streams** - `RedisRuby::DSL::StreamProxy`, `ConsumerProxy`, `StreamReader`
6. **Pub/Sub** - `RedisRuby::DSL::PublisherProxy`, `SubscriberBuilder`, `RedisRuby::Broadcaster`
7. **Hashes** - `RedisRuby::DSL::HashProxy` (Hash-like operations, chainable)
8. **Sorted Sets** - `RedisRuby::DSL::SortedSetProxy` (Leaderboards, rankings)
9. **Lists** - `RedisRuby::DSL::ListProxy` (Queues, stacks, array-like)
10. **Sets** - `RedisRuby::DSL::SetProxy` (Tags, unique collections, set operations)

---

## Priority Queue

### ✅ Priority 1: Hashes (COMPLETED)

**Namespace**: `RedisRuby::DSL::HashProxy`

**Entry Point**:
```ruby
redis.hash(*key_parts)  # Returns HashProxy instance
```

**API Design**:
```ruby
# Chainable operations
redis.hash(:user, 123)
  .set(name: "John", email: "john@example.com")
  .increment(:login_count)
  .expire(3600)

# Hash-like interface
user = redis.hash(:user, 123)
user[:name] = "John"
user[:email] = "john@example.com"
user[:name]  # => "John"
user.keys    # => [:name, :email]
user.values  # => ["John", "john@example.com"]
user.to_h    # => {name: "John", email: "john@example.com"}

# Bulk operations
user.merge(age: 30, city: "SF")
user.slice(:name, :email)
user.delete(:old_field)

# Existence checks
user.key?(:name)  # => true
user.exists?      # => true
```

**Implementation Files**:
- `lib/redis_ruby/dsl/hash_proxy.rb` - Main DSL class
- `lib/redis_ruby/commands/hashes.rb` - Add `hash(*key_parts)` method
- `test/integration/dsl/hash_dsl_test.rb` - Integration tests
- `examples/idiomatic_hash_api.rb` - Usage examples

**Inspiration**: ActiveRecord attributes, Ruby Hash class

---

### ✅ Priority 2: Sorted Sets (COMPLETED)

**Namespace**: `RedisRuby::DSL::SortedSetProxy`

**Entry Point**:
```ruby
redis.sorted_set(*key_parts)  # Returns SortedSetProxy instance
```

**API Design**:
```ruby
# Leaderboard operations
leaderboard = redis.sorted_set(:leaderboard)
  .add(player1: 100, player2: 200, player3: 150)
  .increment(:player1, 10)

# Range queries
leaderboard.top(10)           # Top 10 by score (descending)
leaderboard.bottom(5)         # Bottom 5 by score (ascending)
leaderboard.range(0..9)       # Range by rank
leaderboard.by_score(100..200).limit(10)  # Range by score

# Rank and score
leaderboard.rank_of(:player1)   # => 2
leaderboard.score_of(:player1)  # => 110

# Set operations
redis.sorted_set(:set1).union(:set2, :set3)
redis.sorted_set(:set1).intersect(:set2)
```

**Implementation Files**:
- `lib/redis_ruby/dsl/sorted_set_proxy.rb`
- `lib/redis_ruby/commands/sorted_sets.rb` - Add `sorted_set(*key_parts)` method
- `test/integration/dsl/sorted_set_dsl_test.rb`
- `examples/idiomatic_sorted_set_api.rb`

**Inspiration**: ActiveRecord scopes, Ruby Enumerable

---

### ✅ Priority 3: Lists (COMPLETED)

**Namespace**: `RedisRuby::DSL::ListProxy`

**Entry Point**:
```ruby
redis.list(*key_parts)  # Returns ListProxy instance
```

**API Design**:
```ruby
# Queue operations
queue = redis.list(:jobs)
  .push("job1", "job2")      # Push to right (RPUSH)
  .unshift("urgent")         # Push to left (LPUSH)
  .pop                       # Pop from right (RPOP)
  .shift                     # Pop from left (LPOP)

# Array-like interface
queue << "job3"              # Alias for push
queue[0]                     # Get by index
queue[0..5]                  # Get range
queue.length                 # List length
queue.each { |job| process(job) }

# Blocking operations
queue.blocking_pop(timeout: 5)
queue.blocking_shift(timeout: 5)

# Trim and manipulation
queue.trim(0..99)            # Keep only first 100
queue.insert_before("job2", "new_job")
queue.insert_after("job2", "another_job")
```

**Implementation Files**:
- `lib/redis_ruby/dsl/list_proxy.rb`
- `lib/redis_ruby/commands/lists.rb` - Add `list(*key_parts)` method
- `test/integration/dsl/list_dsl_test.rb`
- `examples/idiomatic_list_api.rb`

**Inspiration**: Ruby Array class, Queue/Stack patterns

---

### ✅ Priority 4: Sets (COMPLETED)

**Namespace**: `RedisRuby::DSL::SetProxy`

**Entry Point**:
```ruby
redis.set(*key_parts)  # Returns SetProxy instance
```

**API Design**:
```ruby
# Set operations
tags = redis.set(:tags)
  .add(:ruby, :redis, :database)
  .remove(:old_tag)
  .member?(:ruby)        # => true
  .members               # => [:ruby, :redis, :database]
  .size                  # => 3

# Set algebra
redis.set(:tags1).union(:tags2, :tags3)
redis.set(:tags1).intersect(:tags2)
redis.set(:tags1).diff(:tags2)
redis.set(:tags1).store_union(:result, :tags2)

# Random operations
tags.random_member
tags.random_members(3)
tags.pop              # Remove and return random member

# Enumerable interface
tags.each { |tag| puts tag }
tags.map(&:upcase)
tags.select { |tag| tag.start_with?('r') }
```

**Implementation Files**:
- `lib/redis_ruby/dsl/set_proxy.rb`
- `lib/redis_ruby/commands/sets.rb` - Add `set(*key_parts)` method
- `test/integration/dsl/set_dsl_test.rb`
- `examples/idiomatic_set_api.rb`

**Inspiration**: Ruby Set class, Enumerable module

---

### 🔥 Priority 5: Strings/Counters (NEXT)

**Namespace**: `RedisRuby::DSL::StringProxy`, `RedisRuby::DSL::CounterProxy`

**Entry Points**:
```ruby
redis.string(*key_parts)   # Returns StringProxy instance
redis.counter(*key_parts)  # Returns CounterProxy instance
```

**API Design**:
```ruby
# String operations
config = redis.string(:config, :api_key)
  .set("secret123")
  .expire(86400)
  .get                   # => "secret123"
  .append("_suffix")
  .length                # => 13

# Atomic operations
lock = redis.string(:lock, :resource_id)
  .set_if_not_exists("locked", ex: 30)
  .get_and_delete

# Counter operations
counter = redis.counter(:page_views)
  .increment(5)
  .decrement(2)
  .value                 # => 3
  .expire(3600)
  .reset                 # Set to 0

# Atomic counter with limits
counter.increment_by(10, max: 100)
counter.decrement_by(5, min: 0)
```

**Implementation Files**:
- `lib/redis_ruby/dsl/string_proxy.rb`
- `lib/redis_ruby/dsl/counter_proxy.rb`
- `lib/redis_ruby/commands/strings.rb` - Add `string(*key_parts)`, `counter(*key_parts)` methods
- `test/integration/dsl/string_dsl_test.rb`
- `test/integration/dsl/counter_dsl_test.rb`
- `examples/idiomatic_string_api.rb`

**Inspiration**: Ruby String class, ActiveSupport::Cache

---

### 🌍 Priority 6: Geo

**Namespace**: `RedisRuby::DSL::GeoProxy`

**Entry Point**:
```ruby
redis.geo(*key_parts)  # Returns GeoProxy instance
```

**API Design**:
```ruby
# Add locations
stores = redis.geo(:stores)
  .add(store1: [-122.4, 37.8], store2: [-122.5, 37.9])
  .add(store3: {longitude: -122.6, latitude: 37.7})

# Proximity search
nearby = stores.near(-122.45, 37.85, radius: 10, unit: :km)
  .with_distance
  .with_coordinates
  .ascending

# Distance calculation
stores.distance(:store1, :store2, unit: :mi)

# Get coordinates
stores.position(:store1)  # => [-122.4, 37.8]
```

**Implementation Files**:
- `lib/redis_ruby/dsl/geo_proxy.rb`
- `lib/redis_ruby/commands/geo.rb` - Add `geo(*key_parts)` method
- `test/integration/dsl/geo_dsl_test.rb`
- `examples/idiomatic_geo_api.rb`

**Inspiration**: Geocoder gem, ActiveRecord spatial queries

---

### 📊 Priority 7: HyperLogLog

**Namespace**: `RedisRuby::DSL::HyperLogLogProxy`

**Entry Point**:
```ruby
redis.hyperloglog(*key_parts)  # Returns HyperLogLogProxy instance
```

**API Design**:
```ruby
# Unique counting
visitors = redis.hyperloglog(:unique_visitors)
  .add(:user1, :user2, :user3)
  .count                 # Approximate count
  .merge(:visitors_2024, :visitors_2023)
```

**Implementation Files**:
- `lib/redis_ruby/dsl/hyperloglog_proxy.rb`
- `lib/redis_ruby/commands/hyperloglog.rb` - Add `hyperloglog(*key_parts)` method
- `test/integration/dsl/hyperloglog_dsl_test.rb`
- `examples/idiomatic_hyperloglog_api.rb`

---

### 🎨 Priority 8: Bitmap

**Namespace**: `RedisRuby::DSL::BitmapProxy`

**Entry Point**:
```ruby
redis.bitmap(*key_parts)  # Returns BitmapProxy instance
```

**API Design**:
```ruby
# Bit operations
activity = redis.bitmap(:user_activity)
  .set_bit(user_id, 1)
  .get_bit(user_id)      # => 1
  .count_set_bits
  .count_in_range(0..100)

# Bitwise operations
redis.bitmap(:result).and(:bitmap1, :bitmap2)
redis.bitmap(:result).or(:bitmap1, :bitmap2)
redis.bitmap(:result).xor(:bitmap1, :bitmap2)
```

**Implementation Files**:
- `lib/redis_ruby/dsl/bitmap_proxy.rb`
- `lib/redis_ruby/commands/bitmap.rb` - Add `bitmap(*key_parts)` method
- `test/integration/dsl/bitmap_dsl_test.rb`
- `examples/idiomatic_bitmap_api.rb`

---

### 🎲 Priority 9: Probabilistic (Bloom Filter, Cuckoo Filter, etc.)

**Namespace**: `RedisRuby::DSL::BloomFilterProxy`, `RedisRuby::DSL::CuckooFilterProxy`

**Entry Points**:
```ruby
redis.bloom_filter(*key_parts)   # Returns BloomFilterProxy instance
redis.cuckoo_filter(*key_parts)  # Returns CuckooFilterProxy instance
```

**API Design**:
```ruby
# Bloom filter
seen = redis.bloom_filter(:seen_items)
  .reserve(capacity: 10000, error_rate: 0.01)
  .add(:item1, :item2)
  .exists?(:item1)       # => true
  .exists?(:item3)       # => false (probably)

# Cuckoo filter
filter = redis.cuckoo_filter(:items)
  .reserve(capacity: 10000)
  .add(:item1)
  .delete(:item1)        # Cuckoo supports deletion
  .exists?(:item1)       # => false
```

**Implementation Files**:
- `lib/redis_ruby/dsl/bloom_filter_proxy.rb`
- `lib/redis_ruby/dsl/cuckoo_filter_proxy.rb`
- `lib/redis_ruby/commands/probabilistic.rb` - Add entry point methods
- `test/integration/dsl/probabilistic_dsl_test.rb`
- `examples/idiomatic_probabilistic_api.rb`

---

## Implementation Guidelines

### File Organization

```
lib/redis_ruby/
├── commands/           # Low-level Redis commands (existing)
│   ├── hashes.rb
│   ├── sorted_sets.rb
│   └── ...
├── dsl/               # High-level idiomatic APIs (new)
│   ├── hash_proxy.rb
│   ├── sorted_set_proxy.rb
│   └── ...
└── client.rb          # Entry points for DSL methods

test/
├── integration/
│   ├── commands/      # Low-level command tests
│   └── dsl/          # High-level DSL tests
└── unit/

examples/
├── idiomatic_hash_api.rb
├── idiomatic_sorted_set_api.rb
└── ...
```

### Naming Conventions

1. **DSL Classes**: `*Proxy` suffix (e.g., `HashProxy`, `SortedSetProxy`)
2. **Entry Methods**: Singular, lowercase (e.g., `hash()`, `sorted_set()`)
3. **Composite Keys**: Support `*key_parts` for automatic `:` joining
4. **Method Names**: Ruby conventions (e.g., `member?`, `exists?`, `to_h`)

### Testing Requirements

1. **Integration Tests**: Test actual Redis operations
2. **Coverage Target**: Maintain >96% line coverage
3. **Test Pattern**: Follow existing DSL test patterns
4. **Examples**: Create runnable examples for each feature

### Documentation

1. **YARD Comments**: Document all public methods
2. **Examples**: Include usage examples in method docs
3. **README**: Update main README with DSL examples
4. **Migration Guides**: Show before/after for common patterns

---

## Success Metrics

- ✅ All existing tests continue to pass
- ✅ New DSL tests achieve >95% coverage
- ✅ Examples run successfully
- ✅ No breaking changes to existing APIs
- ✅ Clear separation between low-level and high-level APIs
- ✅ Idiomatic Ruby patterns throughout


