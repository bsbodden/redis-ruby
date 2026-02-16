---
layout: default
title: Probabilistic
parent: Advanced Features
nav_order: 4
permalink: /advanced-features/bloom/
---

# Probabilistic

Redis provides probabilistic data structures, enabling memory-efficient approximate computations. Perfect for membership testing, frequency estimation, and tracking top items.

## Table of Contents

- [Bloom Filters](#bloom-filters)
- [Cuckoo Filters](#cuckoo-filters)
- [Count-Min Sketch](#count-min-sketch)
- [Top-K](#top-k)
- [t-digest](#t-digest)

## Bloom Filters

Bloom filters are space-efficient probabilistic data structures for testing set membership. They can have false positives but never false negatives.

### Creating Bloom Filters

```ruby
# Create bloom filter with error rate and capacity
redis.bf_reserve("usernames", 0.01, 10_000)
# 0.01 = 1% error rate, 10,000 expected items

# Create with expansion factor
redis.bf_reserve("emails", 0.001, 100_000,
  expansion: 2)  # Double size when full

# Create non-scaling filter
redis.bf_reserve("fixed", 0.01, 1000,
  nonscaling: true)  # Don't expand when full
```

### Adding Items

```ruby
# Add single item
result = redis.bf_add("usernames", "alice")
# => 1 (newly added) or 0 (already exists)

# Add multiple items
results = redis.bf_madd("usernames", "bob", "charlie", "david")
# => [1, 1, 1]  # All newly added

# Add with auto-creation
results = redis.bf_insert("usernames", "eve", "frank",
  capacity: 10_000,
  error: 0.01)
# Creates filter if it doesn't exist
```

### Checking Membership

```ruby
# Check if item exists
exists = redis.bf_exists("usernames", "alice")
# => 1 (probably exists) or 0 (definitely doesn't exist)

# Check multiple items
results = redis.bf_mexists("usernames", "alice", "bob", "unknown")
# => [1, 1, 0]
```

### Bloom Filter Information

```ruby
# Get filter info
info = redis.bf_info("usernames")
puts "Capacity: #{info['Capacity']}"
puts "Size: #{info['Size']}"
puts "Number of filters: #{info['Number of filters']}"
puts "Expansion rate: #{info['Expansion rate']}"

# Get cardinality (approximate count)
count = redis.bf_card("usernames")
# => 5  # Approximate number of items
```

### Use Cases

```ruby
# Prevent duplicate user registrations
def username_available?(username)
  redis.bf_exists("registered_usernames", username) == 0
end

def register_user(username)
  if username_available?(username)
    redis.bf_add("registered_usernames", username)
    # ... create user account
    true
  else
    false
  end
end

# Cache negative lookups
def user_exists?(user_id)
  # Check bloom filter first
  if redis.bf_exists("existing_users", user_id) == 0
    return false  # Definitely doesn't exist
  end
  
  # Might exist, check database
  User.exists?(id: user_id)
end
```

## Cuckoo Filters

Cuckoo filters are similar to Bloom filters but support deletion and generally have better lookup performance.

### Creating Cuckoo Filters

```ruby
# Create cuckoo filter
redis.cf_reserve("sessions", 10_000)

# Create with options
redis.cf_reserve("tokens", 100_000,
  bucketsize: 4,        # Items per bucket
  maxiterations: 20,    # Max cuckoo kicks
  expansion: 1)         # Expansion factor
```

### Adding and Removing Items

```ruby
# Add item
result = redis.cf_add("sessions", "session:abc123")
# => 1 (added) or 0 (already exists)

# Add only if doesn't exist
result = redis.cf_addnx("sessions", "session:def456")
# => 1 (added) or 0 (already exists)

# Add multiple items with auto-creation
results = redis.cf_insert("sessions",
  "session:1", "session:2", "session:3",
  capacity: 10_000)

# Delete item (unlike Bloom filters!)
result = redis.cf_del("sessions", "session:abc123")
# => 1 (deleted) or 0 (not found)
```

### Checking Membership

```ruby
# Check if item exists
exists = redis.cf_exists("sessions", "session:abc123")
# => 1 (exists) or 0 (doesn't exist)

# Check multiple items
results = redis.cf_mexists("sessions",
  "session:1", "session:2", "session:999")
# => [1, 1, 0]

# Count occurrences
count = redis.cf_count("sessions", "session:abc123")
# => 1 or 0
```

### Use Cases

```ruby
# Active session tracking
def create_session(session_id)
  redis.cf_add("active_sessions", session_id)
  redis.setex("session:#{session_id}", 3600, session_data)
end

def destroy_session(session_id)
  redis.cf_del("active_sessions", session_id)
  redis.del("session:#{session_id}")
end

def session_active?(session_id)
  redis.cf_exists("active_sessions", session_id) == 1
end

# Rate limiting with cleanup
def check_rate_limit(ip_address)
  key = "ratelimit:#{ip_address}:#{Time.now.to_i / 60}"
  
  if redis.cf_exists("rate_limited_ips", key) == 1
    return false  # Rate limited
  end
  
  count = redis.cf_count("rate_limited_ips", key)
  if count >= 100
    true  # Rate limited
  else
    redis.cf_add("rate_limited_ips", key)
    false
  end
end
```

## Count-Min Sketch

Count-Min Sketch provides frequency estimation for items in a stream, useful for finding heavy hitters.

### Creating Count-Min Sketch

```ruby
# Create by dimensions
redis.cms_initbydim("pageviews", 2000, 5)
# width=2000, depth=5

# Create by error probability
redis.cms_initbyprob("events", 0.001, 0.01)
# error=0.001 (0.1%), probability=0.01 (1%)
```

### Incrementing Counts

```ruby
# Increment single item
counts = redis.cms_incrby("pageviews", "/home", 1)
# => [1]

# Increment multiple items
counts = redis.cms_incrby("pageviews",
  "/home", 5,
  "/about", 3,
  "/contact", 2)
# => [5, 3, 2]
```

### Querying Counts

```ruby
# Get estimated count
counts = redis.cms_query("pageviews", "/home", "/about")
# => [150, 75]  # Estimated counts

# Get info
info = redis.cms_info("pageviews")
puts "Width: #{info['width']}"
puts "Depth: #{info['depth']}"
puts "Count: #{info['count']}"
```

### Merging Sketches

```ruby
# Create multiple sketches
redis.cms_initbyprob("pageviews:server1", 0.001, 0.01)
redis.cms_initbyprob("pageviews:server2", 0.001, 0.01)

# Add data to each
redis.cms_incrby("pageviews:server1", "/home", 100)
redis.cms_incrby("pageviews:server2", "/home", 50)

# Merge into combined sketch
redis.cms_merge("pageviews:total",
  "pageviews:server1", "pageviews:server2")

# Query merged data
count = redis.cms_query("pageviews:total", "/home")
# => [150]
```

### Use Cases

```ruby
# Track page views
def track_pageview(url)
  redis.cms_incrby("pageviews", url, 1)
end

def get_pageview_count(url)
  redis.cms_query("pageviews", url).first
end

# Find popular pages
def get_popular_pages(urls)
  counts = redis.cms_query("pageviews", *urls)
  urls.zip(counts).sort_by { |_, count| -count }.take(10)
end

# Track API endpoint usage
def track_api_call(endpoint, user_id)
  redis.cms_incrby("api:calls", endpoint, 1)
  redis.cms_incrby("api:users:#{user_id}", endpoint, 1)
end

def get_endpoint_stats(endpoint)
  total = redis.cms_query("api:calls", endpoint).first
  { endpoint: endpoint, total_calls: total }
end
```

## Top-K

Top-K tracks the K most frequent items in a stream, perfect for finding trending items or heavy hitters.

### Creating Top-K

```ruby
# Create Top-K for top 10 items
redis.topk_reserve("trending", 10)

# Create with custom parameters
redis.topk_reserve("popular_products", 20,
  width: 2000,   # Width of count array
  depth: 5,      # Depth of count array
  decay: 0.9)    # Decay rate
```

### Adding Items

```ruby
# Add single item
dropped = redis.topk_add("trending", "item1")
# => [nil] or ["item_that_was_dropped"]

# Add multiple items
dropped = redis.topk_add("trending",
  "item1", "item2", "item3", "item1", "item2", "item1")
# Returns items that were dropped from top-K

# Increment item count
dropped = redis.topk_incrby("trending",
  "item1", 5,
  "item2", 3)
```

### Querying Top-K

```ruby
# Get top K items
items = redis.topk_list("trending")
# => ["item1", "item2", "item3", ...]

# Get with counts
items = redis.topk_list("trending", withcount: true)
# => [["item1", 10], ["item2", 8], ["item3", 5], ...]

# Check if items are in top-K
results = redis.topk_query("trending", "item1", "item2", "unknown")
# => [1, 1, 0]  # 1 = in top-K, 0 = not in top-K

# Get estimated counts
counts = redis.topk_count("trending", "item1", "item2")
# => [10, 8]
```

### Use Cases

```ruby
# Track trending hashtags
def track_hashtag(hashtag)
  redis.topk_add("trending_hashtags", hashtag)
end

def get_trending_hashtags(limit = 10)
  redis.topk_list("trending_hashtags", withcount: true).take(limit)
end

# Track popular products
def track_product_view(product_id)
  redis.topk_add("popular_products", product_id)
end

def get_popular_products
  product_ids = redis.topk_list("popular_products")
  Product.where(id: product_ids)
end

# Track search queries
def track_search(query)
  redis.topk_add("popular_searches", query.downcase)
end

def get_search_suggestions
  redis.topk_list("popular_searches", withcount: true)
    .map { |query, count| { query: query, popularity: count } }
end
```

## t-digest

t-digest provides accurate percentile estimation for streaming data, useful for monitoring latencies and distributions.

### Creating t-digest

```ruby
# Create t-digest
redis.tdigest_create("latencies")

# Create with compression factor
redis.tdigest_create("response_times", compression: 200)
# Higher compression = more accuracy, more memory
```

### Adding Values

```ruby
# Add single value
redis.tdigest_add("latencies", 45.2)

# Add multiple values
redis.tdigest_add("latencies", 23.1, 45.2, 67.8, 12.3, 89.4)
```

### Querying Percentiles

```ruby
# Get specific percentiles
percentiles = redis.tdigest_quantile("latencies", 0.5, 0.95, 0.99)
# => [45.2, 89.1, 95.3]  # p50, p95, p99

puts "Median (p50): #{percentiles[0]}ms"
puts "p95: #{percentiles[1]}ms"
puts "p99: #{percentiles[2]}ms"

# Get CDF (cumulative distribution function)
cdf = redis.tdigest_cdf("latencies", 50, 100)
# => [0.6, 0.95]  # 60% <= 50ms, 95% <= 100ms
```

### Statistical Functions

```ruby
# Get min/max
min = redis.tdigest_min("latencies")
max = redis.tdigest_max("latencies")

# Get info
info = redis.tdigest_info("latencies")
puts "Compression: #{info['Compression']}"
puts "Capacity: #{info['Capacity']}"
puts "Merged nodes: #{info['Merged nodes']}"
puts "Total compressions: #{info['Total compressions']}"
```

### Merging t-digests

```ruby
# Create multiple digests
redis.tdigest_create("latencies:server1")
redis.tdigest_create("latencies:server2")

# Add data
redis.tdigest_add("latencies:server1", 10, 20, 30)
redis.tdigest_add("latencies:server2", 15, 25, 35)

# Merge into combined digest
redis.tdigest_merge("latencies:total",
  "latencies:server1", "latencies:server2")

# Query merged percentiles
percentiles = redis.tdigest_quantile("latencies:total", 0.5, 0.95, 0.99)
```

### Use Cases

```ruby
# Track API response times
def track_response_time(endpoint, duration_ms)
  redis.tdigest_add("latency:#{endpoint}", duration_ms)
  redis.tdigest_add("latency:all", duration_ms)
end

def get_latency_stats(endpoint)
  key = "latency:#{endpoint}"
  percentiles = redis.tdigest_quantile(key, 0.5, 0.95, 0.99)

  {
    endpoint: endpoint,
    p50: percentiles[0],
    p95: percentiles[1],
    p99: percentiles[2],
    min: redis.tdigest_min(key),
    max: redis.tdigest_max(key)
  }
end

# Monitor database query performance
class QueryMonitor
  def track_query(sql, duration_ms)
    # Track overall
    redis.tdigest_add("db:query:latency", duration_ms)

    # Track by query type
    type = sql.split.first.downcase  # SELECT, INSERT, etc.
    redis.tdigest_add("db:query:#{type}:latency", duration_ms)
  end

  def get_performance_report
    {
      overall: get_percentiles("db:query:latency"),
      select: get_percentiles("db:query:select:latency"),
      insert: get_percentiles("db:query:insert:latency"),
      update: get_percentiles("db:query:update:latency")
    }
  end

  private

  def get_percentiles(key)
    redis.tdigest_quantile(key, 0.5, 0.95, 0.99)
      .zip([50, 95, 99])
      .to_h { |value, percentile| ["p#{percentile}", value] }
  end
end
```

## Common Patterns

### Deduplication Pipeline

```ruby
# Use Bloom filter for fast deduplication
class EventDeduplicator
  def initialize(redis)
    @redis = redis
    @filter_key = "events:seen"

    # Create filter if needed
    begin
      @redis.bf_info(@filter_key)
    rescue RR::CommandError
      @redis.bf_reserve(@filter_key, 0.001, 1_000_000)
    end
  end

  def process_event(event_id, &block)
    # Check if we've seen this event
    if @redis.bf_exists(@filter_key, event_id) == 1
      return :duplicate
    end

    # Mark as seen
    @redis.bf_add(@filter_key, event_id)

    # Process event
    yield if block_given?
    :processed
  end
end
```

### Analytics Dashboard

```ruby
class AnalyticsDashboard
  def initialize(redis)
    @redis = redis
    setup_structures
  end

  def setup_structures
    # Top pages
    @redis.topk_reserve("analytics:top_pages", 100)

    # Page view counts
    @redis.cms_initbyprob("analytics:pageviews", 0.001, 0.01)

    # Response time percentiles
    @redis.tdigest_create("analytics:response_times")

    # Unique visitors (Bloom filter)
    @redis.bf_reserve("analytics:visitors", 0.01, 1_000_000)
  end

  def track_pageview(url, visitor_id, response_time_ms)
    # Track top pages
    @redis.topk_add("analytics:top_pages", url)

    # Count page views
    @redis.cms_incrby("analytics:pageviews", url, 1)

    # Track response times
    @redis.tdigest_add("analytics:response_times", response_time_ms)

    # Track unique visitors
    @redis.bf_add("analytics:visitors", visitor_id)
  end

  def get_dashboard_data
    {
      top_pages: @redis.topk_list("analytics:top_pages", withcount: true).take(10),
      total_pageviews: get_total_pageviews,
      response_time_percentiles: @redis.tdigest_quantile(
        "analytics:response_times", 0.5, 0.95, 0.99
      ),
      approximate_unique_visitors: @redis.bf_card("analytics:visitors")
    }
  end

  private

  def get_total_pageviews
    top_pages = @redis.topk_list("analytics:top_pages")
    counts = @redis.cms_query("analytics:pageviews", *top_pages)
    counts.sum
  end
end
```

## Performance Tips

1. **Choose the right structure** - Each has different trade-offs
2. **Set appropriate error rates** - Lower error = more memory
3. **Size filters correctly** - Estimate expected items accurately
4. **Use batch operations** - Add multiple items at once when possible
5. **Monitor memory usage** - Use INFO commands to track size
6. **Consider false positive rate** - Bloom filters can have false positives

## Comparison Table

| Structure | Use Case | Supports Deletion | Memory Efficiency | Accuracy |
|-----------|----------|-------------------|-------------------|----------|
| Bloom Filter | Membership testing | No | Excellent | Probabilistic |
| Cuckoo Filter | Membership testing | Yes | Very Good | Probabilistic |
| Count-Min Sketch | Frequency counting | No | Excellent | Approximate |
| Top-K | Top items tracking | Automatic | Good | Approximate |
| t-digest | Percentile estimation | No | Good | High |

## Next Steps

- [Search & Query Documentation](/advanced-features/search/) - Combine with search capabilities
- [Time Series Documentation](/advanced-features/timeseries/) - Track metrics over time
- [RedisBloom Commands](https://redis.io/commands/?group=bf)

## Resources

- [RedisBloom Documentation](https://redis.io/docs/data-types/probabilistic/)
- [Bloom Filter Theory](https://en.wikipedia.org/wiki/Bloom_filter)
- [Count-Min Sketch Paper](https://en.wikipedia.org/wiki/Count%E2%80%93min_sketch)
- [GitHub Examples](https://github.com/redis/redis-ruby/tree/main/examples)

