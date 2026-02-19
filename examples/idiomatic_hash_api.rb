#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/redis_ruby"

# Connect to Redis
redis = RedisRuby.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379"))

puts "=" * 80
puts "Redis Hashes - Idiomatic Ruby API Examples"
puts "=" * 80

# ============================================================
# Example 1: Hash-like Access
# ============================================================

puts "\nExample 1: Hash-like Access"
puts "-" * 80

user = redis.hash(:user, 123)
user[:name] = "John Doe"
user[:email] = "john@example.com"
user[:age] = 30

puts "Name: #{user[:name]}"
puts "Email: #{user[:email]}"
puts "Age: #{user[:age]}"

# ============================================================
# Example 2: Bulk Operations
# ============================================================

puts "\nExample 2: Bulk Operations"
puts "-" * 80

profile = redis.hash(:profile, 456)
profile.set(
  name: "Alice Smith",
  email: "alice@example.com",
  city: "San Francisco",
  country: "USA"
)

puts "Profile data:"
profile.to_h.each do |key, value|
  puts "  #{key}: #{value}"
end

# ============================================================
# Example 3: Chainable Operations
# ============================================================

puts "\nExample 3: Chainable Operations"
puts "-" * 80

session = redis.hash(:session, "abc123")
  .set(user_id: 789, ip: "192.168.1.1", created_at: Time.now.to_i)
  .increment(:page_views)
  .expire(1800) # 30 minutes

puts "Session created with TTL: #{session.ttl} seconds"
puts "Page views: #{session[:page_views]}"

# ============================================================
# Example 4: Numeric Operations
# ============================================================

puts "\nExample 4: Numeric Operations"
puts "-" * 80

stats = redis.hash(:stats, :daily)
stats[:visitors] = 0
stats[:revenue] = "0.0"

# Increment counters
stats.increment(:visitors, 10)
stats.increment(:visitors, 5)
stats.increment_float(:revenue, 99.99)
stats.increment_float(:revenue, 49.99)

puts "Total visitors: #{stats[:visitors]}"
puts "Total revenue: $#{stats[:revenue]}"

# ============================================================
# Example 5: Inspection and Iteration
# ============================================================

puts "\nExample 5: Inspection and Iteration"
puts "-" * 80

config = redis.hash(:config, :app)
config.merge(
  api_key: "secret123",
  max_connections: 100,
  timeout: 30,
  debug: "false"
)

puts "Configuration keys: #{config.keys.join(", ")}"
puts "Number of settings: #{config.length}"
puts "\nAll settings:"
config.each do |key, value|
  puts "  #{key} = #{value}"
end

# ============================================================
# Example 6: Slice and Except
# ============================================================

puts "\nExample 6: Slice and Except"
puts "-" * 80

user_data = redis.hash(:user, 999)
user_data.set(
  name: "Bob",
  email: "bob@example.com",
  password: "hashed_password",
  age: 25,
  city: "NYC"
)

# Get only specific fields
public_data = user_data.slice(:name, :email, :city)
puts "Public data: #{public_data}"

# Get all except sensitive fields
safe_data = user_data.except(:password)
puts "Safe data: #{safe_data}"

# ============================================================
# Example 7: Existence Checks
# ============================================================

puts "\nExample 7: Existence Checks"
puts "-" * 80

temp_data = redis.hash(:temp, SecureRandom.hex(4))
temp_data[:value] = "test"

puts "Hash exists? #{temp_data.exists?}"
puts "Has 'value' field? #{temp_data.key?(:value)}"
puts "Has 'missing' field? #{temp_data.key?(:missing)}"
puts "Is empty? #{temp_data.empty?}"

temp_data.clear
puts "After clear - exists? #{temp_data.exists?}"

# ============================================================
# Example 8: Expiration Management
# ============================================================

puts "\nExample 8: Expiration Management"
puts "-" * 80

cache = redis.hash(:cache, :api_response)
cache.set(data: "cached_value", timestamp: Time.now.to_i)
cache.expire(60) # Expire in 60 seconds

puts "Cache TTL: #{cache.ttl} seconds"

# Remove expiration
cache.persist
puts "After persist - TTL: #{cache.ttl} (#{cache.ttl == -1 ? "no expiration" : "has expiration"})"

# Set expiration at specific time
cache.expire_at(Time.now + 120)
puts "Expires at specific time - TTL: #{cache.ttl} seconds"

# ============================================================
# Example 9: Feature Flags
# ============================================================

puts "\nExample 9: Feature Flags"
puts "-" * 80

flags = redis.hash(:features, :production)
flags.merge(
  new_ui: "true",
  beta_api: "false",
  dark_mode: "true",
  experimental_search: "false"
)

puts "Feature flags:"
flags.each do |feature, enabled|
  puts "  #{feature}: #{enabled == "true" ? "✓ enabled" : "✗ disabled"}"
end

# Toggle a flag
flags[:beta_api] = "true"
puts "\nBeta API enabled: #{flags[:beta_api]}"

# ============================================================
# Cleanup
# ============================================================

puts "\n#{"=" * 80}"
puts "Cleaning up..."
redis.del("user:123", "profile:456", "session:abc123", "stats:daily",
          "config:app", "user:999", "cache:api_response", "features:production")
redis.close
puts "Done!"
