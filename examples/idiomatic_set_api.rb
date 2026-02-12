#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/redis_ruby"

# Connect to Redis
redis = RedisRuby.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379"))

puts "=" * 80
puts "Redis Sets - Idiomatic Ruby API Examples"
puts "=" * 80

# ============================================================
# Example 1: Tag Management
# ============================================================

puts "\nExample 1: Tag Management"
puts "-" * 80

post_tags = redis.redis_set(:post, 123, :tags)
post_tags.add("ruby", "redis", "tutorial", "database", "performance")

puts "Post tags: #{post_tags.members.join(', ')}"
puts "Has 'ruby' tag? #{post_tags.member?('ruby')}"
puts "Total tags: #{post_tags.size}"

# Remove a tag
post_tags.remove("performance")
puts "After removing 'performance': #{post_tags.members.join(', ')}"

# ============================================================
# Example 2: Unique Visitors Tracking
# ============================================================

puts "\nExample 2: Unique Visitors Tracking"
puts "-" * 80

visitors_today = redis.redis_set(:visitors, :today)
visitors_today.add("user:123", "user:456", "user:789")
visitors_today.add("user:123")  # Duplicate - won't increase count

puts "Unique visitors today: #{visitors_today.size}"
puts "User 123 visited? #{visitors_today.member?('user:123')}"
puts "User 999 visited? #{visitors_today.member?('user:999')}"

# Set to expire at end of day
visitors_today.expire(86400)
puts "Expires in: #{visitors_today.ttl} seconds"

# ============================================================
# Example 3: Set Operations - Union
# ============================================================

puts "\nExample 3: Set Operations - Union"
puts "-" * 80

frontend_devs = redis.redis_set(:skills, :frontend)
backend_devs = redis.redis_set(:skills, :backend)
mobile_devs = redis.redis_set(:skills, :mobile)

frontend_devs.add("alice", "bob", "charlie")
backend_devs.add("bob", "david", "eve")
mobile_devs.add("charlie", "eve", "frank")

# All developers (union)
all_devs = frontend_devs.union("skills:backend", "skills:mobile")
puts "All developers: #{all_devs.sort.join(', ')}"
puts "Total unique developers: #{all_devs.size}"

# ============================================================
# Example 4: Set Operations - Intersection
# ============================================================

puts "\nExample 4: Set Operations - Intersection"
puts "-" * 80

# Full-stack developers (can do both frontend and backend)
fullstack = frontend_devs.intersect("skills:backend")
puts "Full-stack developers: #{fullstack.join(', ')}"

# Developers who can do all three
all_skills = frontend_devs.intersect("skills:backend", "skills:mobile")
puts "Developers with all skills: #{all_skills.join(', ')}"

# ============================================================
# Example 5: Set Operations - Difference
# ============================================================

puts "\nExample 5: Set Operations - Difference"
puts "-" * 80

# Frontend-only developers (not backend)
frontend_only = frontend_devs.difference("skills:backend")
puts "Frontend-only developers: #{frontend_only.join(', ')}"

# Backend developers who don't do mobile
backend_not_mobile = backend_devs.difference("skills:mobile")
puts "Backend (not mobile) developers: #{backend_not_mobile.join(', ')}"

# ============================================================
# Example 6: Random Selection
# ============================================================

puts "\nExample 6: Random Selection"
puts "-" * 80

participants = redis.redis_set(:contest, :participants)
participants.add("alice", "bob", "charlie", "david", "eve", "frank", "grace", "henry")

puts "Total participants: #{participants.size}"

# Pick random participants without removing
sample = participants.random(3)
puts "Random sample (3): #{sample.join(', ')}"
puts "Still #{participants.size} participants"

# Pick winner (removes from set)
winner = participants.pop
puts "Winner: #{winner}"
puts "Remaining participants: #{participants.size}"

# ============================================================
# Example 7: Iteration
# ============================================================

puts "\nExample 7: Iteration"
puts "-" * 80

features = redis.redis_set(:features, :enabled)
features.add("dark_mode", "notifications", "analytics", "export", "api_access")

puts "Enabled features:"
features.each do |feature|
  puts "  ✓ #{feature}"
end

# Using enumerator
uppercase_features = features.each.map(&:upcase)
puts "\nUppercase features: #{uppercase_features.join(', ')}"

# ============================================================
# Example 8: Chainable Operations
# ============================================================

puts "\nExample 8: Chainable Operations"
puts "-" * 80

temp_tags = redis.redis_set(:temp, :tags)
  .add("tag1", "tag2", "tag3", "tag4", "tag5")
  .remove("tag1")
  .expire(300)  # 5 minutes

puts "Temp tags: #{temp_tags.members.join(', ')}"
puts "Size: #{temp_tags.size}"
puts "TTL: #{temp_tags.ttl} seconds"

# ============================================================
# Example 9: Product Categories
# ============================================================

puts "\nExample 9: Product Categories"
puts "-" * 80

electronics = redis.redis_set(:category, :electronics)
electronics.add("laptop", "phone", "tablet", "headphones", "smartwatch")

# Check if product is in category
puts "Is 'laptop' in electronics? #{electronics.include?('laptop')}"
puts "Is 'book' in electronics? #{electronics.include?('book')}"

# Get all products
puts "Electronics products: #{electronics.to_a.join(', ')}"

# Remove discontinued product
electronics.delete("smartwatch")
puts "After removing smartwatch: #{electronics.size} products"

# ============================================================
# Cleanup
# ============================================================

puts "\n" + "=" * 80
puts "Cleaning up..."
redis.del(
  "post:123:tags",
  "visitors:today",
  "skills:frontend",
  "skills:backend",
  "skills:mobile",
  "contest:participants",
  "features:enabled",
  "temp:tags",
  "category:electronics"
)
redis.close
puts "Done!"

