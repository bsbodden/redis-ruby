#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require_relative "../lib/redis_ruby"

# Connect to Redis
redis = RedisRuby.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379"))

puts "=" * 80
puts "Redis HyperLogLog - Idiomatic Ruby API Examples"
puts "=" * 80
puts "HyperLogLog: Probabilistic cardinality estimation"
puts "Memory: ~12KB per HLL regardless of set size"
puts "Accuracy: ~0.81% standard error"
puts "=" * 80

# ============================================================
# Example 1: Unique Visitor Counting
# ============================================================

puts "\nExample 1: Unique Visitor Counting"
puts "-" * 80

# Track unique visitors per day
today = redis.hll(:visitors, Date.today.to_s)
today.add("user:123", "user:456", "user:789", "user:101", "user:202")
today.add("user:123", "user:456")  # Duplicates - won't increase count

puts "Unique visitors today: #{today.count}"
puts "Is empty? #{today.empty?}"
puts "Exists? #{today.exists?}"

# Set to expire at end of day (24 hours)
today.expire(86400)
puts "Expires in: #{today.ttl} seconds"

# ============================================================
# Example 2: Unique Event Tracking
# ============================================================

puts "\nExample 2: Unique Event Tracking"
puts "-" * 80

# Track unique event types per user
user_events = redis.hll(:events, :user, 12345)
user_events.add("page_view", "button_click", "form_submit", "download", "share")
user_events.add("page_view", "button_click")  # Duplicate events

puts "Unique event types for user 12345: #{user_events.count}"
puts "Total unique events: #{user_events.size}"  # Alias for count

# Track events for another user
user2_events = redis.hll(:events, :user, 67890)
user2_events.add("page_view", "video_play", "comment", "like")

puts "Unique event types for user 67890: #{user2_events.count}"

# ============================================================
# Example 3: Merging HyperLogLogs (Daily → Weekly → Monthly)
# ============================================================

puts "\nExample 3: Merging HyperLogLogs (Daily → Weekly → Monthly)"
puts "-" * 80

# Track daily unique visitors
day1 = redis.hll(:visitors, "2024", "01", "01")
day1.add("user:1", "user:2", "user:3", "user:4", "user:5")

day2 = redis.hll(:visitors, "2024", "01", "02")
day2.add("user:3", "user:4", "user:5", "user:6", "user:7")

day3 = redis.hll(:visitors, "2024", "01", "03")
day3.add("user:5", "user:6", "user:7", "user:8", "user:9")

puts "Day 1 unique visitors: #{day1.count}"
puts "Day 2 unique visitors: #{day2.count}"
puts "Day 3 unique visitors: #{day3.count}"

# Merge into weekly count
weekly = redis.hll(:visitors, "2024", :week, 1)
weekly.merge(
  "visitors:2024:01:01",
  "visitors:2024:01:02",
  "visitors:2024:01:03"
)

puts "Weekly unique visitors (merged): #{weekly.count}"
puts "Expected: 9 unique users (user:1 through user:9)"

# ============================================================
# Example 4: A/B Testing Unique User Counts
# ============================================================

puts "\nExample 4: A/B Testing Unique User Counts"
puts "-" * 80

# Track unique users in each variant
variant_a = redis.hll(:experiment, :checkout_flow, :variant_a)
variant_b = redis.hll(:experiment, :checkout_flow, :variant_b)
variant_c = redis.hll(:experiment, :checkout_flow, :variant_c)

# Simulate user assignments
variant_a.add("user:1", "user:2", "user:3", "user:4", "user:5", "user:6", "user:7")
variant_b.add("user:8", "user:9", "user:10", "user:11", "user:12")
variant_c.add("user:13", "user:14", "user:15", "user:16")

puts "Variant A unique users: #{variant_a.count}"
puts "Variant B unique users: #{variant_b.count}"
puts "Variant C unique users: #{variant_c.count}"

# Calculate total unique users across all variants
total = redis.hll(:experiment, :checkout_flow, :total)
total.merge(
  "experiment:checkout_flow:variant_a",
  "experiment:checkout_flow:variant_b",
  "experiment:checkout_flow:variant_c"
)

puts "Total unique users in experiment: #{total.count}"

# ============================================================
# Example 5: Merge Into (Preserving Source HLLs)
# ============================================================

puts "\nExample 5: Merge Into (Preserving Source HLLs)"
puts "-" * 80

# Track unique visitors per region
region_us = redis.hll(:visitors, :region, :us)
region_eu = redis.hll(:visitors, :region, :eu)
region_asia = redis.hll(:visitors, :region, :asia)

region_us.add("user:1", "user:2", "user:3", "user:4", "user:5")
region_eu.add("user:6", "user:7", "user:8", "user:9")
region_asia.add("user:10", "user:11", "user:12")

puts "US visitors: #{region_us.count}"
puts "EU visitors: #{region_eu.count}"
puts "Asia visitors: #{region_asia.count}"

# Merge into global count without modifying regional counts
region_us.merge_into(
  "visitors:region:global",
  "visitors:region:eu",
  "visitors:region:asia"
)

global = redis.hll(:visitors, :region, :global)
puts "Global visitors (merged): #{global.count}"

# Verify regional counts are unchanged
puts "US visitors (after merge): #{region_us.count}"
puts "EU visitors (after merge): #{region_eu.count}"
puts "Asia visitors (after merge): #{region_asia.count}"

# ============================================================
# Example 6: Large-Scale Unique IP Tracking
# ============================================================

puts "\nExample 6: Large-Scale Unique IP Tracking"
puts "-" * 80

# Track unique IP addresses
ip_tracker = redis.hll(:unique, :ips, :today)

# Simulate tracking 10,000 unique IPs
puts "Adding 10,000 unique IP addresses..."
10_000.times do |i|
  ip_tracker.add("192.168.#{i / 256}.#{i % 256}")
end

count = ip_tracker.count
error_rate = ((count - 10_000).abs / 10_000.0 * 100).round(2)

puts "Actual unique IPs: 10,000"
puts "HyperLogLog estimate: #{count}"
puts "Error rate: #{error_rate}%"
puts "Memory used: ~12KB (regardless of count!)"

# ============================================================
# Example 7: Multi-Level Time Aggregation
# ============================================================

puts "\nExample 7: Multi-Level Time Aggregation (Hour → Day → Week)"
puts "-" * 80

# Track unique visitors per hour
hour_1 = redis.hll(:visitors, :hour, 1).add("u1", "u2", "u3", "u4")
hour_2 = redis.hll(:visitors, :hour, 2).add("u3", "u4", "u5", "u6")
hour_3 = redis.hll(:visitors, :hour, 3).add("u5", "u6", "u7", "u8")
hour_4 = redis.hll(:visitors, :hour, 4).add("u7", "u8", "u9", "u10")

puts "Hour 1: #{hour_1.count} unique visitors"
puts "Hour 2: #{hour_2.count} unique visitors"
puts "Hour 3: #{hour_3.count} unique visitors"
puts "Hour 4: #{hour_4.count} unique visitors"

# Aggregate into daily count
daily = redis.hll(:visitors, :daily)
daily.merge(
  "visitors:hour:1",
  "visitors:hour:2",
  "visitors:hour:3",
  "visitors:hour:4"
)

puts "Daily total: #{daily.count} unique visitors"

# ============================================================
# Example 8: Chainable Operations
# ============================================================

puts "\nExample 8: Chainable Operations"
puts "-" * 80

# Chain multiple operations together
session_tracker = redis.hll(:sessions, :active)
  .add("session:1", "session:2", "session:3")
  .add("session:4", "session:5")
  .expire(3600)  # Expire in 1 hour

puts "Active sessions: #{session_tracker.count}"
puts "TTL: #{session_tracker.ttl} seconds"

# ============================================================
# Example 9: Feature Usage Tracking
# ============================================================

puts "\nExample 9: Feature Usage Tracking"
puts "-" * 80

# Track unique users who used each feature
feature_search = redis.hll(:feature, :search)
feature_export = redis.hll(:feature, :export)
feature_api = redis.hll(:feature, :api)

feature_search.add("user:1", "user:2", "user:3", "user:4", "user:5", "user:6")
feature_export.add("user:2", "user:4", "user:6", "user:8")
feature_api.add("user:1", "user:3", "user:5", "user:7", "user:9")

puts "Users who used search: #{feature_search.count}"
puts "Users who used export: #{feature_export.count}"
puts "Users who used API: #{feature_api.count}"

# Find total unique users who used any feature
all_features = redis.hll(:feature, :all)
all_features.merge("feature:search", "feature:export", "feature:api")

puts "Total unique users (any feature): #{all_features.count}"

# ============================================================
# Example 10: Clear and Reset
# ============================================================

puts "\nExample 10: Clear and Reset"
puts "-" * 80

temp_tracker = redis.hll(:temp, :tracker)
temp_tracker.add("item:1", "item:2", "item:3")

puts "Before clear: #{temp_tracker.count} items"
puts "Exists? #{temp_tracker.exists?}"

temp_tracker.clear

puts "After clear: #{temp_tracker.count} items"
puts "Exists? #{temp_tracker.exists?}"
puts "Empty? #{temp_tracker.empty?}"

# ============================================================
# Cleanup
# ============================================================

puts "\n" + "=" * 80
puts "Cleaning up..."
redis.del(
  "visitors:#{Date.today}",
  "events:user:12345",
  "events:user:67890",
  "visitors:2024:01:01",
  "visitors:2024:01:02",
  "visitors:2024:01:03",
  "visitors:2024:week:1",
  "experiment:checkout_flow:variant_a",
  "experiment:checkout_flow:variant_b",
  "experiment:checkout_flow:variant_c",
  "experiment:checkout_flow:total",
  "visitors:region:us",
  "visitors:region:eu",
  "visitors:region:asia",
  "visitors:region:global",
  "unique:ips:today",
  "visitors:hour:1",
  "visitors:hour:2",
  "visitors:hour:3",
  "visitors:hour:4",
  "visitors:daily",
  "sessions:active",
  "feature:search",
  "feature:export",
  "feature:api",
  "feature:all",
  "temp:tracker"
)
redis.close
puts "Done!"


