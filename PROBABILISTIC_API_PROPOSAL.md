# Probabilistic Data Structures - Idiomatic Ruby API Proposal

## Overview

This proposal defines idiomatic Ruby APIs for Redis Stack's probabilistic data structures:
- **Bloom Filter** - Space-efficient membership testing (false positives possible)
- **Cuckoo Filter** - Similar to Bloom with deletion support
- **Count-Min Sketch** - Frequency estimation for streaming data
- **Top-K** - Track top K most frequent items

These structures trade perfect accuracy for massive space savings and constant-time operations.

## Design Principles

1. **Fluent, chainable API** - All mutating methods return `self`
2. **Composite keys** - Support `redis.bloom_filter(:spam, :detector, user_id)` → `"spam:detector:#{user_id}"`
3. **Ruby-esque naming** - `exists?` instead of `bf_exists`, `add` instead of `bf_add`
4. **Consistent patterns** - Same expiration methods across all structures
5. **Probabilistic transparency** - Document accuracy trade-offs clearly

## 1. Bloom Filter API

### Purpose
Test if an element **may exist** in a set. False positives possible, false negatives impossible.

### Use Cases
- Spam detection (check if email seen before)
- Duplicate detection (prevent re-processing)
- Cache negative lookups (avoid expensive DB queries)
- Username availability checks

### API Design

```ruby
# Entry point
filter = redis.bloom_filter(:spam, :emails)
# Alias
filter = redis.bloom(:spam, :emails)

# Reserve with error rate and capacity
filter.reserve(error_rate: 0.01, capacity: 100_000)

# Add items (returns self for chaining)
filter.add("spam@example.com")
filter.add("bad@example.com", "evil@example.com")

# Check existence (returns boolean for single, array for multiple)
filter.exists?("spam@example.com")  # => true (probably)
filter.exists?("unknown@example.com")  # => false (definitely not)
filter.exists?("spam@example.com", "unknown@example.com")  # => [true, false]

# Get filter information
info = filter.info  # => { "Capacity" => 100000, "Size" => ..., ... }

# Expiration
filter.expire(3600)
filter.expire_at(Time.now + 3600)
filter.ttl  # => seconds remaining
filter.persist

# Clear
filter.delete
filter.clear  # alias
```

### Accuracy Trade-offs
- **Error rate**: 0.01 = 1% false positive rate
- **Memory**: ~10 bits per element at 1% error rate
- **No false negatives**: If `exists?` returns false, item definitely not in set
- **No deletion**: Once added, cannot remove (use Cuckoo Filter for deletion)

## 2. Cuckoo Filter API

### Purpose
Similar to Bloom Filter but supports **deletion** and generally better lookup performance.

### Use Cases
- Cache admission control with eviction
- Session tracking with cleanup
- Rate limiting with expiration
- Temporary blacklists

### API Design

```ruby
# Entry point
filter = redis.cuckoo_filter(:sessions)
# Alias
filter = redis.cuckoo(:sessions)

# Reserve with capacity and options
filter.reserve(capacity: 10_000, bucket_size: 4, max_iterations: 20, expansion: 1)

# Add items
filter.add("session:abc123")
filter.add("session:def456", "session:ghi789")

# Add only if not exists
filter.add_nx("session:abc123")  # => false (already exists)

# Check existence
filter.exists?("session:abc123")  # => true
filter.exists?("session:abc123", "session:unknown")  # => [true, false]

# Remove items (key difference from Bloom Filter!)
filter.remove("session:abc123")
filter.remove("session:def456", "session:ghi789")

# Count occurrences (approximate)
filter.count("session:abc123")  # => 1

# Get filter information
info = filter.info

# Expiration and cleanup
filter.expire(3600)
filter.delete
```

### Accuracy Trade-offs
- **False positives**: Possible but rare
- **False negatives**: Possible after many deletions
- **Deletion support**: Unlike Bloom Filter
- **Memory**: Slightly more than Bloom Filter

## 3. Count-Min Sketch API

### Purpose
Estimate **frequency** of items in a stream. Over-estimates but never under-estimates.

### Use Cases
- Page view counting
- Heavy hitter detection
- Frequency analysis
- Real-time analytics

### API Design

```ruby
# Entry point
sketch = redis.count_min_sketch(:pageviews)
# Alias
sketch = redis.cms(:pageviews)

# Initialize by dimensions (width × depth)
sketch.init_by_dim(width: 2000, depth: 5)

# Initialize by error probability
sketch.init_by_prob(error_rate: 0.001, probability: 0.01)

# Increment counts
sketch.increment("/home", "/about", "/contact")
sketch.increment_by("/home", 5)  # Increment by specific amount

# Query counts
sketch.query("/home")  # => 6
sketch.query("/home", "/about")  # => [6, 1]

# Merge sketches (combine multiple servers)
sketch.merge("pageviews:server1", "pageviews:server2")

# Get sketch information
info = sketch.info  # => { "width" => 2000, "depth" => 5, "count" => 8 }

# Expiration and cleanup
sketch.expire(86400)
sketch.delete
```

### Accuracy Trade-offs
- **Over-estimation**: May over-count, never under-counts
- **Error bound**: Actual count ≤ Estimated count ≤ Actual count + (ε × N)
  - ε = error rate (e.g., 0.001)
  - N = total items processed
- **Memory**: width × depth × 8 bytes
- **Probability**: Confidence level (e.g., 0.01 = 99% confidence)

## 4. Top-K API

### Purpose
Track the **top K most frequent** items in a stream.

### Use Cases
- Trending topics
- Popular products
- Heavy hitters
- Leaderboards

### API Design

```ruby
# Entry point
topk = redis.top_k(:trending, :products)

# Reserve with K and optional parameters
topk.reserve(k: 10, width: 1000, depth: 5, decay: 0.9)

# Add items (returns items that were dropped out of top-K)
dropped = topk.add("product:123")
dropped = topk.add("product:456", "product:789")  # => ["product:old"] or []

# Increment by specific amount
topk.increment_by("product:123", 5)

# Check if items are in top-K
topk.query("product:123")  # => true
topk.query("product:123", "product:999")  # => [true, false]

# Get counts
topk.count("product:123")  # => 15
topk.count("product:123", "product:456")  # => [15, 8]

# List top K items with counts
topk.list  # => ["product:123", "product:456", ...]
topk.list(with_counts: true)  # => [["product:123", 15], ["product:456", 8], ...]

# Get Top-K information
info = topk.info

# Expiration and cleanup
topk.expire(3600)
topk.delete
```

### Accuracy Trade-offs
- **Approximate counts**: Counts are estimates, not exact
- **Decay factor**: 0.9 = older items decay by 10% over time
- **Memory**: O(K) space regardless of stream size
- **Heavy hitters**: Guaranteed to track items in top K

## Implementation Notes

### Common Patterns

All proxies follow these patterns:

1. **Initialization**: `initialize(redis, *key_parts)`
2. **Key composition**: `@key = key_parts.map(&:to_s).join(":")`
3. **Chainable mutations**: Return `self` from mutating methods
4. **Expiration methods**: `expire(seconds)`, `expire_at(timestamp)`, `ttl`, `persist`
5. **Cleanup**: `delete`, `clear` (alias)

### Error Handling

- Gracefully handle missing Redis Stack modules
- Provide clear error messages for invalid parameters
- Document probabilistic nature in errors

### Testing Strategy

- Unit tests for each proxy method
- Integration tests for real-world scenarios
- Performance tests for large datasets
- Accuracy tests to verify error bounds

## Migration Path

Existing low-level commands remain unchanged:
- `redis.bf_reserve(...)` - Still available
- `redis.cf_add(...)` - Still available
- `redis.cms_incrby(...)` - Still available
- `redis.topk_query(...)` - Still available

New idiomatic API provides higher-level abstraction:
- `redis.bloom_filter(...).reserve(...).add(...)`
- `redis.cuckoo_filter(...).add(...).remove(...)`
- `redis.count_min_sketch(...).increment(...).query(...)`
- `redis.top_k(...).add(...).list(...)`

