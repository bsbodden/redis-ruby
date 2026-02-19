---
layout: default
title: Time Series
parent: Advanced Features
nav_order: 3
permalink: /advanced-features/timeseries/
---

# Time Series

Redis provides time series data capabilities with high-performance ingestion, querying, and automatic downsampling. Perfect for metrics, IoT sensor data, financial data, and monitoring.

{: .note }
> **Two API Styles Available**
>
> This library provides both a **low-level API** (direct Redis commands) and an **idiomatic Ruby API** (DSL and fluent builders).
> Both work side-by-side - use whichever fits your style!

## Table of Contents

- [Idiomatic Ruby API (Recommended)](#idiomatic-ruby-api-recommended)
  - [Creating Time Series with DSL](#creating-time-series-with-dsl)
  - [Chainable Operations](#chainable-operations)
  - [Fluent Query Builder](#fluent-query-builder)
- [Low-Level API](#low-level-api)
  - [Creating Time Series](#creating-time-series)
  - [Adding Samples](#adding-samples)
  - [Querying Data](#querying-data)
  - [Aggregations](#aggregations)
  - [Retention Policies](#retention-policies)
  - [Compaction Rules](#compaction-rules)

---

## Idiomatic Ruby API (Recommended)

The idiomatic API provides a more Ruby-esque way to work with time series using DSLs, method chaining, and symbols.

### Creating Time Series with DSL

Use the `time_series` method with a block to create time series with a clean, declarative syntax:

```ruby
# Simple time series with DSL
redis.time_series("temperature:sensor1") do
  retention 86400000  # 24 hours
  labels sensor: "temp", location: "office"
end

# Multi-level aggregation with compaction rules
redis.time_series("metrics:raw") do
  retention 3600000  # 1 hour
  labels resolution: "raw"

  # Automatically create destination series and compaction rules
  compact_to "metrics:hourly", :avg, 3600000 do
    retention 86400000  # 24 hours
    labels resolution: "hourly"
  end

  compact_to "metrics:daily", :avg, 86400000 do
    retention 2592000000  # 30 days
    labels resolution: "daily"
  end
end
```

**Compare with low-level API:**

```ruby
# Low-level API requires multiple calls
redis.ts_create("metrics:raw", retention: 3600000)
redis.ts_create("metrics:hourly", retention: 86400000)
redis.ts_create("metrics:daily", retention: 2592000000)
redis.ts_createrule("metrics:raw", "metrics:hourly", "avg", 3600000)
redis.ts_createrule("metrics:raw", "metrics:daily", "avg", 86400000)
```

### Chainable Operations

Use the `ts` method to get a chainable proxy for fluent operations:

```ruby
# Add samples with method chaining
now = Time.now.to_i * 1000
redis.ts("temperature:sensor1")
  .add(now, 23.5)
  .add(now + 1000, 24.0)
  .add(now + 2000, 23.8)

# Increment/decrement operations
redis.ts("counter:requests")
  .increment(10)
  .decrement(5)

# Get latest value
latest = redis.ts("temperature:sensor1").get
# => [1640000000000, "23.5"]

# Composite keys with automatic joining
redis.ts(:metrics, :server1, :cpu).add(now, 45.2)
# Equivalent to: redis.ts_add("metrics:server1:cpu", now, 45.2)
```

**Available chainable methods:**

- `add(timestamp, value, **options)` - Add a sample
- `increment(value, **options)` / `incr(value, **options)` - Increment by value
- `decrement(value, **options)` / `decr(value, **options)` - Decrement by value
- `get` / `latest` - Get latest sample
- `info` - Get time series information
- `alter(**options)` - Modify time series settings
- `compact_to(dest_key, aggregation, bucket_duration)` - Create compaction rule
- `delete_rule(dest_key)` - Delete compaction rule
- `delete(from:, to:)` - Delete samples in range
- `add_many(*samples)` - Add multiple samples
- `range(from:, to:)` - Get query builder for range
- `reverse_range(from:, to:)` - Get query builder for reverse range

### Fluent Query Builder

Use the `ts_query` method to build complex queries with method chaining:

```ruby
# Single series query
result = redis.ts_query("temperature:sensor1")
  .from("-")
  .to("+")
  .aggregate(:avg, 300000)  # 5 minute buckets
  .limit(100)
  .execute

# Multi-series query with filters
result = redis.ts_query
  .filter(sensor: "temp", location: "office")
  .from(Time.now - 3600)
  .to(Time.now)
  .aggregate(:avg, 60000)  # 1 minute buckets
  .with_labels
  .execute

# Reverse query (latest first)
result = redis.ts_query("temperature:sensor1")
  .from("-")
  .to("+")
  .reverse
  .limit(10)
  .execute

# Group by labels
result = redis.ts_query
  .filter(sensor: "temp")
  .from("-")
  .to("+")
  .aggregate(:avg, 300000)
  .group_by(:location, :avg)
  .execute
```

**Available query builder methods:**

- `from(timestamp)` - Set start timestamp
- `to(timestamp)` - Set end timestamp
- `filter(labels_hash)` / `where(labels_hash)` - Filter by labels (multi-series only)
- `latest` - Use latest sample if timestamp is before series start
- `with_labels` - Include labels in results
- `limit(count)` - Limit number of samples
- `aggregate(type, bucket_duration, bucket_timestamp: nil)` - Aggregate samples
- `group_by(label, reducer)` - Group by label (multi-series only)
- `reverse` - Return results in reverse order
- `execute` - Execute the query

**Aggregation types:** `:avg`, `:sum`, `:min`, `:max`, `:count`, `:first`, `:last`, `:std_p`, `:std_s`, `:var_p`, `:var_s`, `:range`, `:twa`

---

## Low-Level API

The low-level API provides direct access to Redis Time Series commands.

## Creating Time Series

### Basic Time Series

```ruby
# Create a simple time series
redis.ts_create("temperature:sensor1")

# Create with retention (milliseconds)
redis.ts_create("temperature:sensor1",
  retention: 86400000)  # 24 hours

# Create with labels for filtering
redis.ts_create("temperature:sensor1",
  labels: {
    sensor: "temp",
    location: "office",
    floor: "3"
  })
```

### Advanced Options

```ruby
# Create with all options
redis.ts_create("temperature:sensor1",
  retention: 86400000,           # 24 hours retention
  encoding: "COMPRESSED",         # Compress data
  chunk_size: 4096,              # Initial chunk size
  duplicate_policy: "LAST",      # Keep last on duplicate timestamp
  labels: {
    sensor: "temp",
    location: "office",
    unit: "celsius"
  })

# Duplicate policies: BLOCK, FIRST, LAST, MIN, MAX, SUM
```

### Auto-Creation on First Add

```ruby
# Time series will be created automatically
redis.ts_add("temperature:sensor2", "*", 23.5,
  labels: { sensor: "temp", location: "warehouse" })
```

## Adding Samples

### Single Sample

```ruby
# Add with auto timestamp (current time)
timestamp = redis.ts_add("temperature:sensor1", "*", 23.5)
# => 1640000000000  # Returns timestamp in milliseconds

# Add with specific timestamp
redis.ts_add("temperature:sensor1", 1640000000000, 23.5)

# Add with retention override
redis.ts_add("temperature:sensor1", "*", 23.5,
  retention: 3600000)  # 1 hour
```

### Multiple Samples

```ruby
# Add to multiple time series at once
timestamps = redis.ts_madd(
  ["temperature:sensor1", "*", 23.5],
  ["temperature:sensor2", "*", 18.2],
  ["humidity:sensor1", "*", 65.0]
)
# => [1640000000000, 1640000000001, 1640000000002]
```

### Increment/Decrement

```ruby
# Increment value (useful for counters)
redis.ts_incrby("requests:total", 1)

# Decrement value
redis.ts_decrby("active:connections", 1)

# Increment with timestamp
redis.ts_incrby("requests:total", 5, timestamp: "*")
```

## Querying Data

### Get Latest Sample

```ruby
# Get most recent sample
sample = redis.ts_get("temperature:sensor1")
# => [1640000000000, "23.5"]

timestamp, value = sample
puts "Temperature: #{value}°C at #{Time.at(timestamp / 1000)}"
```

### Range Queries

```ruby
# Get all samples
samples = redis.ts_range("temperature:sensor1", "-", "+")

# Get samples in time range
from_ts = (Time.now - 3600).to_i * 1000  # 1 hour ago
to_ts = Time.now.to_i * 1000
samples = redis.ts_range("temperature:sensor1", from_ts, to_ts)

# Limit number of results
samples = redis.ts_range("temperature:sensor1", "-", "+", count: 100)

# Reverse order (newest first)
samples = redis.ts_revrange("temperature:sensor1", "-", "+")
```

### Filter by Value

```ruby
# Get samples within value range
samples = redis.ts_range("temperature:sensor1", "-", "+",
  filter_by_value: [20, 30])  # Only temps between 20-30°C

# Get samples within timestamp range
samples = redis.ts_range("temperature:sensor1", "-", "+",
  filter_by_ts: [from_ts, to_ts])
```

## Aggregations

### Time-Based Aggregations

```ruby
# Average temperature per hour
samples = redis.ts_range("temperature:sensor1", "-", "+",
  aggregation: "avg",
  bucket_duration: 3600000)  # 1 hour in milliseconds

# Supported aggregations:
# avg, sum, min, max, range, count, first, last, std.p, std.s, var.p, var.s
```

### Multiple Aggregation Types

```ruby
# Maximum temperature per day
samples = redis.ts_range("temperature:sensor1", "-", "+",
  aggregation: "max",
  bucket_duration: 86400000)  # 24 hours

# Count samples per 5 minutes
samples = redis.ts_range("temperature:sensor1", "-", "+",
  aggregation: "count",
  bucket_duration: 300000)  # 5 minutes

# Sum of values per hour
samples = redis.ts_range("requests:total", "-", "+",
  aggregation: "sum",
  bucket_duration: 3600000)
```

### Bucket Alignment

```ruby
# Align buckets to specific timestamp
samples = redis.ts_range("temperature:sensor1", "-", "+",
  aggregation: "avg",
  bucket_duration: 3600000,
  bucket_timestamp: "-")  # Align to start of range

# Bucket timestamp options: "-" (start), "+" (end), "~" (middle)
```

## Retention Policies

### Setting Retention

```ruby
# Create with retention
redis.ts_create("metrics:cpu", retention: 604800000)  # 7 days

# Alter existing time series retention
redis.ts_alter("metrics:cpu", retention: 2592000000)  # 30 days

# No retention (keep all data)
redis.ts_create("important:data", retention: 0)
```

### Retention Example

```ruby
# Short-term high-resolution data
redis.ts_create("metrics:cpu:raw",
  retention: 3600000,  # 1 hour
  labels: { type: "raw", metric: "cpu" })

# Long-term aggregated data
redis.ts_create("metrics:cpu:hourly",
  retention: 2592000000,  # 30 days
  labels: { type: "hourly", metric: "cpu" })
```

## Compaction Rules

### Creating Compaction Rules

```ruby
# Create destination time series
redis.ts_create("temperature:hourly")

# Create compaction rule (source -> destination)
redis.ts_createrule("temperature:sensor1", "temperature:hourly",
  "avg", 3600000)  # Average per hour

# Multiple compaction rules
redis.ts_create("temperature:daily")
redis.ts_createrule("temperature:sensor1", "temperature:daily",
  "avg", 86400000)  # Average per day
```

### Multi-Level Aggregation

```ruby
# Raw data (1 hour retention)
redis.ts_create("metrics:requests:raw",
  retention: 3600000,
  labels: { resolution: "raw" })

# Minute aggregation (1 day retention)
redis.ts_create("metrics:requests:1min",
  retention: 86400000,
  labels: { resolution: "1min" })

redis.ts_createrule("metrics:requests:raw", "metrics:requests:1min",
  "sum", 60000)  # Sum per minute

# Hourly aggregation (30 days retention)
redis.ts_create("metrics:requests:1hour",
  retention: 2592000000,
  labels: { resolution: "1hour" })

redis.ts_createrule("metrics:requests:1min", "metrics:requests:1hour",
  "sum", 3600000)  # Sum per hour
```

### Managing Rules

```ruby
# Delete compaction rule
redis.ts_deleterule("temperature:sensor1", "temperature:hourly")

# Get time series info (includes rules)
info = redis.ts_info("temperature:sensor1")
puts info["rules"]
```

## Multi-Series Queries

### Query by Labels

```ruby
# Create multiple sensors with labels
redis.ts_create("temp:office:1", labels: { type: "temp", location: "office" })
redis.ts_create("temp:office:2", labels: { type: "temp", location: "office" })
redis.ts_create("temp:warehouse:1", labels: { type: "temp", location: "warehouse" })

# Add data
redis.ts_add("temp:office:1", "*", 23.5)
redis.ts_add("temp:office:2", "*", 24.0)
redis.ts_add("temp:warehouse:1", "*", 18.0)

# Query all office temperature sensors
results = redis.ts_mrange("-", "+", ["location=office"])
# Returns data from all matching time series

# Query with multiple label filters
results = redis.ts_mrange("-", "+", ["type=temp", "location=office"])
```

### Multi-Get Latest Values

```ruby
# Get latest value from all matching time series
results = redis.ts_mget(["type=temp"])

# Returns: [[key, labels, [timestamp, value]], ...]
results.each do |key, labels, sample|
  timestamp, value = sample
  puts "#{key}: #{value}°C"
end
```

### Multi-Range with Aggregation

```ruby
# Get hourly averages from all sensors
results = redis.ts_mrange("-", "+",
  ["type=temp"],
  aggregation: "avg",
  bucket_duration: 3600000,
  withlabels: true)

# Group by location
results = redis.ts_mrange("-", "+",
  ["type=temp"],
  aggregation: "avg",
  bucket_duration: 3600000,
  groupby: "location",
  reduce: "avg")
```

## Advanced Features

### Label Management

```ruby
# Query time series by labels
keys = redis.ts_queryindex("type=temp")
# => ["temp:office:1", "temp:office:2", "temp:warehouse:1"]

# Query with multiple filters
keys = redis.ts_queryindex("type=temp", "location=office")
# => ["temp:office:1", "temp:office:2"]
```

### Time Series Information

```ruby
# Get detailed info about time series
info = redis.ts_info("temperature:sensor1")

puts "Total samples: #{info['totalSamples']}"
puts "Memory usage: #{info['memoryUsage']} bytes"
puts "First timestamp: #{info['firstTimestamp']}"
puts "Last timestamp: #{info['lastTimestamp']}"
puts "Retention: #{info['retentionTime']} ms"
puts "Labels: #{info['labels']}"
puts "Rules: #{info['rules']}"
```

### Delete Samples

```ruby
# Delete samples in time range
from_ts = (Time.now - 3600).to_i * 1000
to_ts = Time.now.to_i * 1000
deleted = redis.ts_del("temperature:sensor1", from_ts, to_ts)
# => 120  # Number of samples deleted
```

## Common Patterns

### IoT Sensor Monitoring

```ruby
# Setup sensor time series
sensors = ["sensor1", "sensor2", "sensor3"]
sensors.each do |sensor_id|
  redis.ts_create("temp:#{sensor_id}",
    retention: 86400000,  # 24 hours
    labels: {
      sensor_id: sensor_id,
      type: "temperature",
      location: "warehouse",
      unit: "celsius"
    })

  # Create hourly aggregation
  redis.ts_create("temp:#{sensor_id}:hourly",
    retention: 2592000000)  # 30 days

  redis.ts_createrule("temp:#{sensor_id}", "temp:#{sensor_id}:hourly",
    "avg", 3600000)
end

# Ingest sensor data
def record_temperature(sensor_id, temperature)
  redis.ts_add("temp:#{sensor_id}", "*", temperature)
end

# Query all sensors
def get_current_temperatures
  results = redis.ts_mget(["type=temperature", "location=warehouse"])
  results.map do |key, labels, sample|
    {
      sensor: labels.find { |l| l[0] == "sensor_id" }&.last,
      temperature: sample[1].to_f,
      timestamp: Time.at(sample[0] / 1000)
    }
  end
end
```

### Application Metrics

```ruby
# Setup metrics
metrics = {
  "requests:total" => { type: "counter", desc: "Total requests" },
  "requests:errors" => { type: "counter", desc: "Error count" },
  "response:time" => { type: "gauge", desc: "Response time ms" }
}

metrics.each do |key, meta|
  redis.ts_create(key,
    retention: 604800000,  # 7 days
    labels: meta)

  # Create aggregations
  redis.ts_create("#{key}:1min", retention: 86400000)
  redis.ts_createrule(key, "#{key}:1min", "avg", 60000)

  redis.ts_create("#{key}:1hour", retention: 2592000000)
  redis.ts_createrule("#{key}:1min", "#{key}:1hour", "avg", 3600000)
end

# Record metrics
def record_request(success:, response_time:)
  redis.ts_incrby("requests:total", 1)
  redis.ts_incrby("requests:errors", 1) unless success
  redis.ts_add("response:time", "*", response_time)
end

# Get metrics dashboard
def get_metrics(duration: 3600)
  from_ts = (Time.now - duration).to_i * 1000
  to_ts = Time.now.to_i * 1000

  {
    total_requests: redis.ts_range("requests:total", from_ts, to_ts,
      aggregation: "sum", bucket_duration: duration * 1000).first&.last,
    error_rate: calculate_error_rate(from_ts, to_ts),
    avg_response_time: redis.ts_range("response:time", from_ts, to_ts,
      aggregation: "avg", bucket_duration: duration * 1000).first&.last
  }
end
```

### Financial Data

```ruby
# Stock price tracking
redis.ts_create("stock:AAPL:price",
  retention: 31536000000,  # 1 year
  duplicate_policy: "LAST",
  labels: {
    symbol: "AAPL",
    type: "price",
    exchange: "NASDAQ"
  })

# OHLC (Open, High, Low, Close) aggregations
%w[open high low close].each do |metric|
  redis.ts_create("stock:AAPL:daily:#{metric}",
    retention: 157680000000)  # 5 years

  aggregation_type = case metric
                     when "open" then "first"
                     when "high" then "max"
                     when "low" then "min"
                     when "close" then "last"
                     end

  redis.ts_createrule("stock:AAPL:price", "stock:AAPL:daily:#{metric}",
    aggregation_type, 86400000)  # Daily
end

# Record price
redis.ts_add("stock:AAPL:price", "*", 175.50)

# Get daily OHLC
def get_ohlc(symbol, days: 30)
  from_ts = (Time.now - (days * 86400)).to_i * 1000
  to_ts = Time.now.to_i * 1000

  {
    open: redis.ts_range("stock:#{symbol}:daily:open", from_ts, to_ts),
    high: redis.ts_range("stock:#{symbol}:daily:high", from_ts, to_ts),
    low: redis.ts_range("stock:#{symbol}:daily:low", from_ts, to_ts),
    close: redis.ts_range("stock:#{symbol}:daily:close", from_ts, to_ts)
  }
end
```

## Performance Tips

1. **Use labels wisely** - Labels enable powerful filtering but add overhead
2. **Set appropriate retention** - Don't keep data longer than needed
3. **Use compaction rules** - Automatically downsample old data
4. **Batch inserts** - Use `TS.MADD` for multiple samples
5. **Choose right aggregation** - Match aggregation type to your use case
6. **Monitor memory** - Use `TS.INFO` to track memory usage

## Error Handling

```ruby
begin
  redis.ts_add("temperature:sensor1", "*", 23.5)
rescue RR::CommandError => e
  if e.message.include?("key does not exist")
    # Create time series and retry
    redis.ts_create("temperature:sensor1")
    retry
  else
    raise
  end
end

# Check if time series exists
begin
  info = redis.ts_info("temperature:sensor1")
  puts "Time series exists"
rescue RR::CommandError
  puts "Time series does not exist"
end
```

## Next Steps

- [JSON Documentation](/advanced-features/json/) - Combine time series with JSON metadata
- [Search & Query Documentation](/advanced-features/search/) - Index and search time series labels
- [RedisTimeSeries Commands](https://redis.io/commands/?group=timeseries)

## Resources

- [RedisTimeSeries Documentation](https://redis.io/docs/data-types/timeseries/)
- [Time Series Best Practices](https://redis.io/docs/stack/timeseries/quickstart/)
- [GitHub Examples](https://github.com/redis-developer/redis-ruby/tree/main/examples)

