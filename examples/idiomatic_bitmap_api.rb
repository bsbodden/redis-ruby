#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require_relative "../lib/redis_ruby"

# Connect to Redis
redis = RedisRuby.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379"))

puts "=" * 80
puts "Redis Bitmap - Idiomatic Ruby API Examples"
puts "=" * 80
puts "Bitmaps: Bit-level operations for boolean data"
puts "Memory: 1 bit per element (extremely efficient)"
puts "Use Cases: User activity, feature flags, permissions"
puts "=" * 80

# ============================================================
# Example 1: Daily Active Users (DAU) Tracking
# ============================================================

puts "\nExample 1: Daily Active Users (DAU) Tracking"
puts "-" * 80

# Track which users were active today
today = redis.bitmap(:dau, Date.today.to_s)

# Mark users as active (using array syntax)
[1, 5, 10, 15, 20, 25, 30, 35, 40, 45].each do |user_id|
  today[user_id] = 1
end

puts "Daily Active Users: #{today.count}"
puts "User 10 active? #{today[10] == 1 ? 'Yes' : 'No'}"
puts "User 11 active? #{today[11] == 1 ? 'Yes' : 'No'}"

# Set to expire at end of day (24 hours)
today.expire(86400)
puts "Expires in: #{today.ttl} seconds"

# ============================================================
# Example 2: Feature Flags per User
# ============================================================

puts "\nExample 2: Feature Flags per User"
puts "-" * 80

# Define feature flag positions
FEATURE_SEARCH = 0
FEATURE_EXPORT = 1
FEATURE_API = 2
FEATURE_ADMIN = 3
FEATURE_ANALYTICS = 4

# Configure features for user 123
user_features = redis.bitmap(:features, :user, 123)
user_features[FEATURE_SEARCH] = 1
user_features[FEATURE_EXPORT] = 1
user_features[FEATURE_API] = 0
user_features[FEATURE_ADMIN] = 0
user_features[FEATURE_ANALYTICS] = 1

puts "User 123 features:"
puts "  Search: #{user_features[FEATURE_SEARCH] == 1 ? 'Enabled' : 'Disabled'}"
puts "  Export: #{user_features[FEATURE_EXPORT] == 1 ? 'Enabled' : 'Disabled'}"
puts "  API: #{user_features[FEATURE_API] == 1 ? 'Enabled' : 'Disabled'}"
puts "  Admin: #{user_features[FEATURE_ADMIN] == 1 ? 'Enabled' : 'Disabled'}"
puts "  Analytics: #{user_features[FEATURE_ANALYTICS] == 1 ? 'Enabled' : 'Disabled'}"
puts "Total enabled features: #{user_features.count}"

# ============================================================
# Example 3: Permissions System
# ============================================================

puts "\nExample 3: Permissions System"
puts "-" * 80

# Define permission bits
PERM_READ = 0
PERM_WRITE = 1
PERM_DELETE = 2
PERM_ADMIN = 3
PERM_SUPER_ADMIN = 4

# Set permissions for user 456
user_perms = redis.bitmap(:permissions, :user, 456)
user_perms.set_bit(PERM_READ, 1)
  .set_bit(PERM_WRITE, 1)
  .set_bit(PERM_DELETE, 0)
  .set_bit(PERM_ADMIN, 0)
  .set_bit(PERM_SUPER_ADMIN, 0)

puts "User 456 permissions:"
puts "  Read: #{user_perms[PERM_READ] == 1 ? 'Yes' : 'No'}"
puts "  Write: #{user_perms[PERM_WRITE] == 1 ? 'Yes' : 'No'}"
puts "  Delete: #{user_perms[PERM_DELETE] == 1 ? 'Yes' : 'No'}"
puts "  Admin: #{user_perms[PERM_ADMIN] == 1 ? 'Yes' : 'No'}"
puts "Total permissions: #{user_perms.count}"

# ============================================================
# Example 4: Combining Bitmaps with Bitwise Operations
# ============================================================

puts "\nExample 4: Combining Bitmaps with Bitwise Operations"
puts "-" * 80

# Track users active on different days
day1 = redis.bitmap(:dau, "2024-01-01")
day2 = redis.bitmap(:dau, "2024-01-02")
day3 = redis.bitmap(:dau, "2024-01-03")

# Day 1: users 1, 2, 3, 4, 5
[1, 2, 3, 4, 5].each { |id| day1[id] = 1 }

# Day 2: users 3, 4, 5, 6, 7
[3, 4, 5, 6, 7].each { |id| day2[id] = 1 }

# Day 3: users 5, 6, 7, 8, 9
[5, 6, 7, 8, 9].each { |id| day3[id] = 1 }

puts "Day 1 active users: #{day1.count}"
puts "Day 2 active users: #{day2.count}"
puts "Day 3 active users: #{day3.count}"

# Find users active on ALL three days (AND)
all_days = redis.bitmap(:dau, "all_three_days")
all_days.and("dau:2024-01-01", "dau:2024-01-02")
all_days.and("dau:all_three_days", "dau:2024-01-03")
puts "Active all 3 days: #{all_days.count} users (user 5)"

# Find users active on ANY day (OR)
any_day = redis.bitmap(:dau, "any_day")
any_day.or("dau:2024-01-01", "dau:2024-01-02", "dau:2024-01-03")
puts "Active any day: #{any_day.count} users (users 1-9)"

# Find users active on day 1 XOR day 2 (exclusive)
xor_result = redis.bitmap(:dau, "xor_1_2")
xor_result.xor("dau:2024-01-01", "dau:2024-01-02")
puts "Active day 1 XOR day 2: #{xor_result.count} users (1, 2, 6, 7)"

# ============================================================
# Example 5: Non-Destructive Bitwise Operations
# ============================================================

puts "\nExample 5: Non-Destructive Bitwise Operations"
puts "-" * 80

# Create two bitmaps
bitmap_a = redis.bitmap(:set_a)
bitmap_b = redis.bitmap(:set_b)

[1, 2, 3, 4, 5].each { |id| bitmap_a[id] = 1 }
[4, 5, 6, 7, 8].each { |id| bitmap_b[id] = 1 }

puts "Set A: #{bitmap_a.count} elements"
puts "Set B: #{bitmap_b.count} elements"

# Perform operations without modifying sources
bitmap_a.and_into(:intersection, :set_b)
bitmap_a.or_into(:union, :set_b)
bitmap_a.xor_into(:symmetric_diff, :set_b)

intersection = redis.bitmap(:intersection)
union = redis.bitmap(:union)
symmetric_diff = redis.bitmap(:symmetric_diff)

puts "Intersection (A AND B): #{intersection.count} elements (4, 5)"
puts "Union (A OR B): #{union.count} elements (1-8)"
puts "Symmetric Difference (A XOR B): #{symmetric_diff.count} elements (1, 2, 3, 6, 7, 8)"

# Verify sources are unchanged
puts "Set A still has: #{bitmap_a.count} elements"
puts "Set B still has: #{bitmap_b.count} elements"

# ============================================================
# Example 6: Bitfield Operations - Multiple Counters
# ============================================================

puts "\nExample 6: Bitfield Operations - Multiple Counters"
puts "-" * 80

# Store multiple page view counters in a single bitmap
page_counters = redis.bitmap(:page_counters)

# Set initial view counts for different pages
# Each counter is 16 bits (u16), allowing values 0-65535
page_counters.bitfield
  .set(:u16, 0, 100)     # Page 1: 100 views
  .set(:u16, 16, 250)    # Page 2: 250 views
  .set(:u16, 32, 500)    # Page 3: 500 views
  .set(:u16, 48, 1000)   # Page 4: 1000 views
  .execute

puts "Initial page view counts:"
results = page_counters.bitfield
  .get(:u16, 0)
  .get(:u16, 16)
  .get(:u16, 32)
  .get(:u16, 48)
  .execute

results.each_with_index do |count, idx|
  puts "  Page #{idx + 1}: #{count} views"
end

# Increment page 1 views by 50
page_counters.bitfield.incrby(:u16, 0, 50).execute
puts "\nAfter incrementing page 1 by 50:"
new_count = page_counters.bitfield.get(:u16, 0).execute
puts "  Page 1: #{new_count[0]} views"

# ============================================================
# Example 7: Bitfield with Overflow Control
# ============================================================

puts "\nExample 7: Bitfield with Overflow Control"
puts "-" * 80

# Create a bitmap for small counters (8-bit unsigned)
small_counters = redis.bitmap(:small_counters)

# Set counter to near maximum (255 is max for u8)
small_counters.bitfield.set(:u8, 0, 250).execute

puts "Counter value: 250"

# Try to increment with different overflow modes
puts "\nIncrement by 10 with WRAP (default):"
result = small_counters.bitfield
  .overflow(:wrap)
  .incrby(:u8, 0, 10)
  .execute
puts "  Result: #{result[0]} (wraps around to #{result[0]})"

# Reset and try with SAT (saturate)
small_counters.bitfield.set(:u8, 8, 250).execute
puts "\nIncrement by 10 with SAT (saturate):"
result = small_counters.bitfield
  .overflow(:sat)
  .incrby(:u8, 8, 10)
  .execute
puts "  Result: #{result[0]} (saturates at 255)"

# Reset and try with FAIL
small_counters.bitfield.set(:u8, 16, 250).execute
puts "\nIncrement by 10 with FAIL:"
result = small_counters.bitfield
  .overflow(:fail)
  .incrby(:u8, 16, 10)
  .execute
puts "  Result: #{result[0].nil? ? 'nil (operation failed)' : result[0]}"

# ============================================================
# Example 8: User Activity Heatmap
# ============================================================

puts "\nExample 8: User Activity Heatmap (24-hour tracking)"
puts "-" * 80

# Track when a user was active during the day (24 hours)
user_activity = redis.bitmap(:activity, :user, 789, Date.today.to_s)

# User was active at these hours
active_hours = [0, 6, 8, 9, 12, 13, 14, 18, 20, 22, 23]
active_hours.each { |hour| user_activity[hour] = 1 }

puts "User 789 activity for #{Date.today}:"
puts "Total active hours: #{user_activity.count}"

# Find first active hour
first_active = user_activity.position(1)
puts "First active hour: #{first_active}:00"

# Find first inactive hour
first_inactive = user_activity.position(0)
puts "First inactive hour: #{first_inactive}:00"

# Check specific hours
puts "\nActivity by time of day:"
puts "  Morning (6-11): #{[6, 7, 8, 9, 10, 11].count { |h| user_activity[h] == 1 }} hours"
puts "  Afternoon (12-17): #{[12, 13, 14, 15, 16, 17].count { |h| user_activity[h] == 1 }} hours"
puts "  Evening (18-23): #{[18, 19, 20, 21, 22, 23].count { |h| user_activity[h] == 1 }} hours"
puts "  Night (0-5): #{[0, 1, 2, 3, 4, 5].count { |h| user_activity[h] == 1 }} hours"

# ============================================================
# Example 9: A/B Test Participation Tracking
# ============================================================

puts "\nExample 9: A/B Test Participation Tracking"
puts "-" * 80

# Track which users are in each variant
variant_a = redis.bitmap(:experiment, :checkout_v2, :variant_a)
variant_b = redis.bitmap(:experiment, :checkout_v2, :variant_b)
variant_control = redis.bitmap(:experiment, :checkout_v2, :control)

# Assign users to variants
[1, 2, 3, 4, 5, 10, 11, 12].each { |id| variant_a[id] = 1 }
[6, 7, 8, 9, 13, 14, 15].each { |id| variant_b[id] = 1 }
[16, 17, 18, 19, 20].each { |id| variant_control[id] = 1 }

puts "Experiment: Checkout V2"
puts "  Variant A: #{variant_a.count} users"
puts "  Variant B: #{variant_b.count} users"
puts "  Control: #{variant_control.count} users"

# Calculate total participants
total = redis.bitmap(:experiment, :checkout_v2, :total)
total.or(
  "experiment:checkout_v2:variant_a",
  "experiment:checkout_v2:variant_b",
  "experiment:checkout_v2:control"
)
puts "  Total participants: #{total.count} users"

# Check if specific user is in experiment
user_id = 5
in_a = variant_a[user_id] == 1
in_b = variant_b[user_id] == 1
in_control = variant_control[user_id] == 1

puts "\nUser #{user_id} assignment:"
puts "  Variant A: #{in_a ? 'Yes' : 'No'}"
puts "  Variant B: #{in_b ? 'Yes' : 'No'}"
puts "  Control: #{in_control ? 'Yes' : 'No'}"

# ============================================================
# Example 10: Memory Efficiency Demonstration
# ============================================================

puts "\nExample 10: Memory Efficiency Demonstration"
puts "-" * 80

# Track 1 million users with bitmaps
large_bitmap = redis.bitmap(:large_scale_tracking)

puts "Setting bits for 1,000 users..."
1000.times do |i|
  large_bitmap[i * 1000] = 1  # Sparse bitmap
end

puts "Active users: #{large_bitmap.count}"
puts "Bitmap exists: #{large_bitmap.exists?}"
puts "Memory usage: Extremely efficient (1 bit per user)"
puts "For 1 million users: ~125KB (vs 1MB+ for sets)"

# ============================================================
# Cleanup
# ============================================================

puts "\n" + "=" * 80
puts "Cleaning up..."
redis.del(
  "dau:#{Date.today}",
  "features:user:123",
  "permissions:user:456",
  "dau:2024-01-01",
  "dau:2024-01-02",
  "dau:2024-01-03",
  "dau:all_three_days",
  "dau:any_day",
  "dau:xor_1_2",
  "set_a",
  "set_b",
  "intersection",
  "union",
  "symmetric_diff",
  "page_counters",
  "small_counters",
  "activity:user:789:#{Date.today}",
  "experiment:checkout_v2:variant_a",
  "experiment:checkout_v2:variant_b",
  "experiment:checkout_v2:control",
  "experiment:checkout_v2:total",
  "large_scale_tracking"
)
redis.close
puts "Done!"

