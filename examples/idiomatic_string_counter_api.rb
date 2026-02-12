#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require_relative "../lib/redis_ruby"

# Connect to Redis
redis = RedisRuby.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379"))

puts "=" * 80
puts "Redis Strings & Counters - Idiomatic Ruby API Examples"
puts "=" * 80

# ============================================================
# Example 1: Configuration Management (StringProxy)
# ============================================================

puts "\nExample 1: Configuration Management"
puts "-" * 80

api_key = redis.string(:config, :api_key)
api_key.set("sk_live_123456789").expire(86400)  # Rotate daily

puts "API Key: #{api_key.get()}"
puts "TTL: #{api_key.ttl()} seconds"

# ============================================================
# Example 2: Caching (StringProxy)
# ============================================================

puts "\nExample 2: Caching"
puts "-" * 80

user_data = '{"id":123,"name":"John Doe","email":"john@example.com"}'
cache = redis.string(:cache, :user, 123)
cache.set(user_data).expire(3600)  # Cache for 1 hour

puts "Cached data: #{cache.get()}"
puts "Cache TTL: #{cache.ttl()} seconds"
puts "Cache exists? #{cache.exists?()}"

# ============================================================
# Example 3: Rate Limiting (CounterProxy)
# ============================================================

puts "\nExample 3: Rate Limiting"
puts "-" * 80

user_id = 456
limit = redis.counter(:rate_limit, :api, user_id)

# Initialize counter if it doesn't exist
limit.setnx(0)

# Set expiration for sliding window (60 seconds)
limit.expire(60) if limit.ttl() == -1

# Simulate API calls
5.times do
  limit.increment()
  puts "API call #{limit.get()}"
end

max_requests = 100
if limit.get() > max_requests
  puts "❌ Rate limit exceeded!"
else
  puts "✓ Within rate limit (#{limit.get()}/#{max_requests})"
end

# ============================================================
# Example 4: Distributed Counters (CounterProxy)
# ============================================================

puts "\nExample 4: Distributed Counters"
puts "-" * 80

page_id = 789
views = redis.counter(:page, :views, page_id)

# Simulate multiple processes incrementing
views.increment()
views.increment(5)
views.increment(10)

puts "Total page views: #{views.get()}"

# ============================================================
# Example 5: Page View Tracking (CounterProxy)
# ============================================================

puts "\nExample 5: Daily Page View Tracking"
puts "-" * 80

today = Date.today.to_s
daily_views = redis.counter(:views, :daily, today)

# Track views
10.times { daily_views.increment() }

# Keep for 7 days
daily_views.expire(86400 * 7)

puts "Today's views (#{today}): #{daily_views.get()}"
puts "Data retention: #{daily_views.ttl() / 86400} days"

# ============================================================
# Example 6: Log Aggregation (StringProxy)
# ============================================================

puts "\nExample 6: Log Aggregation"
puts "-" * 80

log = redis.string(:log, :app, Date.today.to_s)
log.set("[#{Time.now}] Application started")
log.append("\n[#{Time.now}] Database connected")
log.append("\n[#{Time.now}] Ready to accept connections")

puts "Application log:"
puts log.get()
puts "\nLog size: #{log.length()} bytes"

# ============================================================
# Example 7: Atomic Operations (CounterProxy)
# ============================================================

puts "\nExample 7: Atomic Operations"
puts "-" * 80

counter = redis.counter(:atomic, :test)

# Set only if not exists
if counter.setnx(0)
  puts "Counter initialized to 0"
else
  puts "Counter already exists with value: #{counter.get()}"
end

# Get and set atomically
old_value = counter.getset(100)
puts "Old value: #{old_value.inspect}, New value: #{counter.get()}"

# ============================================================
# Example 8: Text Manipulation (StringProxy)
# ============================================================

puts "\nExample 8: Text Manipulation"
puts "-" * 80

text = redis.string(:document, :draft)
text.set("Hello World")

puts "Original: #{text.get()}"
puts "Length: #{text.length()}"
puts "First word: #{text.getrange(0, 4)}"
puts "Last word: #{text.getrange(-5, -1)}"

# Replace "World" with "Redis"
text.setrange(6, "Redis")
puts "Modified: #{text.get()}"

# ============================================================
# Example 9: Metrics Collection (CounterProxy)
# ============================================================

puts "\nExample 9: Metrics Collection"
puts "-" * 80

requests = redis.counter(:metrics, :requests, :total)
errors = redis.counter(:metrics, :errors, :total)
successes = redis.counter(:metrics, :successes, :total)

# Simulate traffic
20.times { requests.increment() }
3.times { errors.increment() }
17.times { successes.increment() }

puts "Total requests: #{requests.get()}"
puts "Errors: #{errors.get()}"
puts "Successes: #{successes.get()}"
puts "Error rate: #{(errors.get().to_f / requests.get() * 100).round(2)}%"
puts "Success rate: #{(successes.get().to_f / requests.get() * 100).round(2)}%"

# ============================================================
# Example 10: Chainable Operations
# ============================================================

puts "\nExample 10: Chainable Operations"
puts "-" * 80

# String chaining
session = redis.string(:session, "abc123")
  .set("user_id:789")
  .expire(1800)

puts "Session: #{session.get()}"
puts "Session TTL: #{session.ttl()} seconds"

# Counter chaining
stats = redis.counter(:stats, :daily)
  .set(0)
  .increment(100)
  .increment(50)
  .expire(86400)

puts "Daily stats: #{stats.get()}"
puts "Stats TTL: #{stats.ttl()} seconds"

# ============================================================
# Cleanup
# ============================================================

puts "\n" + "=" * 80
puts "Cleaning up..."
redis.del(
  "config:api_key",
  "cache:user:123",
  "rate_limit:api:456",
  "page:views:789",
  "views:daily:#{Date.today}",
  "log:app:#{Date.today}",
  "atomic:test",
  "document:draft",
  "metrics:requests:total",
  "metrics:errors:total",
  "metrics:successes:total",
  "session:abc123",
  "stats:daily"
)
redis.close
puts "Done!"


