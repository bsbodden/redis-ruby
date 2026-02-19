#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/redis_ruby"

# Connect to Redis
redis = RedisRuby::Client.new
redis.flushdb

puts "=" * 80
puts "Redis Time Series - Idiomatic Ruby API Examples"
puts "=" * 80
puts

# ============================================================================
# Example 1: Creating Time Series with DSL
# ============================================================================
puts "1. Creating Time Series with DSL"
puts "-" * 80

# Old API (still works)
puts "\nOld API:"
puts 'redis.ts_create("temperature:sensor1",'
puts "  retention: 86400000,"
puts '  labels: { sensor: "temp", location: "room1" })'

redis.ts_create("temperature:sensor1",
                retention: 86_400_000,
                labels: { sensor: "temp", location: "room1" })

# New Idiomatic API
puts "\nNew Idiomatic API:"
puts 'redis.time_series("temperature:sensor2") do'
puts "  retention 86400000"
puts '  labels sensor: "temp", location: "room2"'
puts "end"

redis.time_series("temperature:sensor2") do
  retention 86_400_000
  labels sensor: "temp", location: "room2"
end

puts "\n✓ Both time series created successfully"
puts

# ============================================================================
# Example 2: Creating Time Series with Compaction Rules
# ============================================================================
puts "2. Creating Time Series with Multi-Level Aggregation"
puts "-" * 80

# Old API (requires multiple calls)
puts "\nOld API (requires multiple calls):"
puts 'redis.ts_create("metrics:raw", retention: 3600000)'
puts 'redis.ts_create("metrics:hourly", retention: 86400000)'
puts 'redis.ts_create("metrics:daily", retention: 2592000000)'
puts 'redis.ts_createrule("metrics:raw", "metrics:hourly", "avg", 3600000)'
puts 'redis.ts_createrule("metrics:raw", "metrics:daily", "avg", 86400000)'

redis.ts_create("metrics:raw", retention: 3_600_000)
redis.ts_create("metrics:hourly", retention: 86_400_000)
redis.ts_create("metrics:daily", retention: 2_592_000_000)
redis.ts_createrule("metrics:raw", "metrics:hourly", "avg", 3_600_000)
redis.ts_createrule("metrics:raw", "metrics:daily", "avg", 86_400_000)

# New Idiomatic API (single DSL block)
puts "\nNew Idiomatic API (single DSL block):"
puts 'redis.time_series("requests:raw") do'
puts "  retention 3600000  # 1 hour"
puts '  labels resolution: "raw"'
puts "  "
puts '  compact_to "requests:hourly", :avg, 3600000 do'
puts "    retention 86400000  # 24 hours"
puts '    labels resolution: "hourly"'
puts "  end"
puts "  "
puts '  compact_to "requests:daily", :avg, 86400000 do'
puts "    retention 2592000000  # 30 days"
puts '    labels resolution: "daily"'
puts "  end"
puts "end"

redis.time_series("requests:raw") do
  retention 3_600_000
  labels resolution: "raw"

  compact_to "requests:hourly", :avg, 3_600_000 do
    retention 86_400_000
    labels resolution: "hourly"
  end

  compact_to "requests:daily", :avg, 86_400_000 do
    retention 2_592_000_000
    labels resolution: "daily"
  end
end

puts "\n✓ Time series with multi-level aggregation created"
puts

# ============================================================================
# Example 3: Adding Samples with Chainable Proxy
# ============================================================================
puts "3. Adding Samples with Chainable Proxy"
puts "-" * 80

redis.ts_create("cpu:usage")

# Old API
puts "\nOld API:"
puts "now = Time.now.to_i * 1000"
puts 'redis.ts_add("cpu:usage", now, 45.2)'
puts 'redis.ts_add("cpu:usage", now + 1000, 52.1)'
puts 'redis.ts_add("cpu:usage", now + 2000, 48.7)'

now = Time.now.to_i * 1000
redis.ts_add("cpu:usage", now, 45.2)
redis.ts_add("cpu:usage", now + 1000, 52.1)
redis.ts_add("cpu:usage", now + 2000, 48.7)

# New Idiomatic API
puts "\nNew Idiomatic API:"
puts "now = Time.now.to_i * 1000"
puts 'redis.ts("memory:usage")'
puts "  .add(now, 1024)"
puts "  .add(now + 1000, 1156)"
puts "  .add(now + 2000, 1089)"

redis.ts_create("memory:usage")
now = Time.now.to_i * 1000
redis.ts("memory:usage")
  .add(now, 1024)
  .add(now + 1000, 1156)
  .add(now + 2000, 1089)

puts "\n✓ Samples added with method chaining"
puts

# ============================================================================
# Example 4: Increment/Decrement Operations
# ============================================================================
puts "4. Increment/Decrement Operations"
puts "-" * 80

redis.ts_create("counter:requests")
now = Time.now.to_i * 1000
redis.ts_add("counter:requests", now, 100)

# Old API
puts "\nOld API:"
puts 'redis.ts_incrby("counter:requests", 10)'
puts 'redis.ts_decrby("counter:requests", 5)'

redis.ts_incrby("counter:requests", 10)
redis.ts_decrby("counter:requests", 5)

# New Idiomatic API
puts "\nNew Idiomatic API:"
puts 'redis.ts("counter:errors")'
puts "  .increment(10)"
puts "  .decrement(5)"

redis.ts_create("counter:errors")
now = Time.now.to_i * 1000
redis.ts_add("counter:errors", now, 100)
redis.ts("counter:errors")
  .increment(10)
  .decrement(5)

latest = redis.ts("counter:errors").get
puts "\n✓ Counter value: #{latest[1]}"
puts

# ============================================================================
# Example 5: Querying with Fluent Builder
# ============================================================================
puts "5. Querying with Fluent Builder"
puts "-" * 80

# Add some sample data
redis.ts_create("temperature:room1")
now = Time.now.to_i * 1000
10.times do |i|
  redis.ts_add("temperature:room1", now + (i * 60_000), rand(20..24))
end

# Old API
puts "\nOld API:"
puts 'redis.ts_range("temperature:room1", "-", "+",'
puts '  aggregation: "avg", bucket_duration: 300000)'

result = redis.ts_range("temperature:room1", "-", "+",
                        aggregation: "avg", bucket_duration: 300_000)
puts "Result: #{result.length} aggregated samples"

# New Idiomatic API
puts "\nNew Idiomatic API:"
puts 'redis.ts_query("temperature:room1")'
puts '  .from("-")'
puts '  .to("+")'
puts "  .aggregate(:avg, 300000)"
puts "  .execute"

result = redis.ts_query("temperature:room1")
  .from("-")
  .to("+")
  .aggregate(:avg, 300_000)
  .execute

puts "Result: #{result.length} aggregated samples"
puts

# ============================================================================
# Example 6: Multi-Series Queries
# ============================================================================
puts "6. Multi-Series Queries"
puts "-" * 80

# Create multiple series with labels
redis.ts_create("temp:sensor1", labels: { sensor: "temp", location: "room1" })
redis.ts_create("temp:sensor2", labels: { sensor: "temp", location: "room2" })
redis.ts_create("humidity:sensor1", labels: { sensor: "humidity", location: "room1" })

# Add samples
now = Time.now.to_i * 1000
redis.ts_add("temp:sensor1", now, 23.5)
redis.ts_add("temp:sensor2", now, 24.0)
redis.ts_add("humidity:sensor1", now, 60.0)

# Old API
puts "\nOld API:"
puts 'redis.ts_mrange("-", "+", ["sensor=temp"],'
puts "  withlabels: true)"

result = redis.ts_mrange("-", "+", ["sensor=temp"],
                         withlabels: true)
puts "Result: #{result.length} series matched"

# New Idiomatic API
puts "\nNew Idiomatic API:"
puts "redis.ts_query"
puts '  .filter(sensor: "temp")'
puts '  .from("-")'
puts '  .to("+")'
puts "  .with_labels"
puts "  .execute"

result = redis.ts_query
  .filter(sensor: "temp")
  .from("-")
  .to("+")
  .with_labels
  .execute

puts "Result: #{result.length} series matched"
puts

# ============================================================================
# Example 7: Composite Keys with Proxy
# ============================================================================
puts "7. Composite Keys with Proxy"
puts "-" * 80

# Old API
puts "\nOld API:"
puts 'redis.ts_create("metrics:server1:cpu")'
puts "now = Time.now.to_i * 1000"
puts 'redis.ts_add("metrics:server1:cpu", now, 45.2)'

redis.ts_create("metrics:server1:cpu")
now = Time.now.to_i * 1000
redis.ts_add("metrics:server1:cpu", now, 45.2)

# New Idiomatic API (automatic key joining)
puts "\nNew Idiomatic API:"
puts 'redis.ts_create("metrics:server2:cpu")'
puts "now = Time.now.to_i * 1000"
puts "redis.ts(:metrics, :server2, :cpu).add(now, 52.1)"

redis.ts_create("metrics:server2:cpu")
now = Time.now.to_i * 1000
redis.ts(:metrics, :server2, :cpu).add(now, 52.1)

puts "\n✓ Composite keys work seamlessly"
puts

# ============================================================================
# Example 8: Getting Latest Values
# ============================================================================
puts "8. Getting Latest Values"
puts "-" * 80

# Old API
puts "\nOld API:"
puts 'redis.ts_get("temperature:room1")'

result = redis.ts_get("temperature:room1")
puts "Latest: [#{result[0]}, #{result[1]}]"

# New Idiomatic API
puts "\nNew Idiomatic API:"
puts 'redis.ts("temperature:room1").get'

result = redis.ts("temperature:room1").get
puts "Latest: [#{result[0]}, #{result[1]}]"
puts

# ============================================================================
# Summary
# ============================================================================
puts "=" * 80
puts "Summary"
puts "=" * 80
puts
puts "The idiomatic Ruby API provides:"
puts "  ✓ DSL for creating time series with compaction rules"
puts "  ✓ Chainable proxy for fluent operations"
puts "  ✓ Query builder for complex queries"
puts "  ✓ Symbol-based method names"
puts "  ✓ Composite key support"
puts "  ✓ Method chaining for cleaner code"
puts
puts "Both APIs work side-by-side - use whichever fits your style!"
puts "=" * 80

redis.close
