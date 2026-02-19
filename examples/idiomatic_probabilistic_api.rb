#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require_relative "../lib/redis_ruby"

# Connect to Redis
redis = RedisRuby.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379"))

puts "=" * 80
puts "Redis Probabilistic Data Structures - Idiomatic Ruby API Examples"
puts "=" * 80
puts "Bloom Filter: Space-efficient membership testing (false positives possible)"
puts "Cuckoo Filter: Like Bloom but with deletion support"
puts "Count-Min Sketch: Frequency estimation (over-estimates, never under-estimates)"
puts "Top-K: Track top K most frequent items"
puts "=" * 80

# ============================================================
# Example 1: Bloom Filter - Spam Email Detection
# ============================================================

puts "\nExample 1: Bloom Filter - Spam Email Detection"
puts "-" * 80

# Create a Bloom Filter for spam detection
spam_filter = redis.bloom_filter(:spam, :emails)
spam_filter.reserve(error_rate: 0.01, capacity: 100_000)

# Add known spam emails
spam_emails = [
  "spam1@example.com",
  "spam2@example.com",
  "phishing@example.com",
  "scam@example.com",
]
spam_filter.add(*spam_emails)

# Check emails
test_emails = [
  "spam1@example.com",      # Known spam
  "legitimate@example.com", # Not spam
  "user@example.com", # Not spam
]

test_emails.each do |email|
  is_spam = spam_filter.exists?(email)
  puts "#{email}: #{is_spam ? "SPAM (probably)" : "NOT SPAM (definitely)"}"
end

# Get filter info
info = spam_filter.info
puts "\nFilter capacity: #{info["Capacity"]}"
puts "Approximate items: #{spam_filter.cardinality}"

# Set to expire in 24 hours
spam_filter.expire(86_400)
puts "Filter expires in: #{spam_filter.ttl} seconds"

# ============================================================
# Example 2: Bloom Filter - Duplicate URL Detection
# ============================================================

puts "\nExample 2: Bloom Filter - Duplicate URL Detection"
puts "-" * 80

# Track processed URLs to avoid re-processing
processed_urls = redis.bloom_filter(:crawler, :processed)
processed_urls.reserve(error_rate: 0.001, capacity: 1_000_000)

urls_to_process = [
  "https://example.com/page1",
  "https://example.com/page2",
  "https://example.com/page1", # Duplicate
  "https://example.com/page3",
]

urls_to_process.each do |url|
  if processed_urls.exists?(url)
    puts "Skipping (already processed): #{url}"
  else
    puts "Processing: #{url}"
    processed_urls.add(url)
    # ... process URL ...
  end
end

# ============================================================
# Example 3: Cuckoo Filter - Session Tracking with Cleanup
# ============================================================

puts "\nExample 3: Cuckoo Filter - Session Tracking with Cleanup"
puts "-" * 80

# Track active sessions (with ability to remove expired ones)
active_sessions = redis.cuckoo_filter(:sessions, :active)
active_sessions.reserve(capacity: 10_000)

# Add active sessions
sessions = ["session:abc123", "session:def456", "session:ghi789"]
active_sessions.add(*sessions)

puts "Active sessions: #{sessions.size}"
sessions.each do |session|
  puts "  #{session}: #{active_sessions.exists?(session) ? "ACTIVE" : "INACTIVE"}"
end

# Simulate session expiration - remove a session
expired_session = "session:abc123"
active_sessions.remove(expired_session)
puts "\nRemoved expired session: #{expired_session}"
puts "Session still active? #{active_sessions.exists?(expired_session)}"

# Check count (approximate)
puts "Session count: #{active_sessions.count("session:def456")}"

# ============================================================
# Example 4: Cuckoo Filter - Cache Admission Control
# ============================================================

puts "\nExample 4: Cuckoo Filter - Cache Admission Control"
puts "-" * 80

# Track which items are admitted to cache
cache_admitted = redis.cuckoo_filter(:cache, :admitted)
cache_admitted.reserve(capacity: 1000, bucket_size: 4)

# Try to admit items (only if not already admitted)
items = ["item:1", "item:2", "item:3", "item:1"] # item:1 appears twice

items.each do |item|
  if cache_admitted.add_nx(item)
    puts "Admitted to cache: #{item}"
  else
    puts "Already in cache: #{item}"
  end
end

# ============================================================
# Example 5: Count-Min Sketch - Page View Counting
# ============================================================

puts "\nExample 5: Count-Min Sketch - Page View Counting"
puts "-" * 80

# Track page view frequencies
pageviews = redis.count_min_sketch(:pageviews, Date.today.to_s)
pageviews.init_by_prob(error_rate: 0.001, probability: 0.01)

# Simulate page views
page_visits = [
  "/home", "/home", "/home", "/home", "/home",
  "/about", "/about", "/about",
  "/contact", "/contact",
  "/products",
]

page_visits.each { |page| pageviews.increment(page) }

# Query page view counts
pages = ["/home", "/about", "/contact", "/products"]
puts "\nPage view counts:"
pages.each do |page|
  count = pageviews.query(page)
  puts "  #{page}: #{count} views"
end

# Get sketch info
info = pageviews.info
puts "\nSketch dimensions: #{info["width"]} x #{info["depth"]}"
puts "Total items counted: #{info["count"]}"

# Set to expire at end of day
pageviews.expire(86_400)

# ============================================================
# Example 6: Count-Min Sketch - Heavy Hitter Detection
# ============================================================

puts "\nExample 6: Count-Min Sketch - Heavy Hitter Detection"
puts "-" * 80

# Track API endpoint usage to find heavy hitters
api_calls = redis.count_min_sketch(:api, :calls)
api_calls.init_by_dim(width: 2000, depth: 5)

# Simulate API calls
endpoints = {
  "/api/users" => 100,
  "/api/products" => 50,
  "/api/orders" => 25,
  "/api/search" => 200,
  "/api/health" => 10,
}

endpoints.each do |endpoint, count|
  api_calls.increment_by(endpoint, count)
end

# Find heavy hitters (endpoints with > 50 calls)
puts "\nHeavy hitters (> 50 calls):"
endpoints.each_key do |endpoint|
  count = api_calls.query(endpoint)
  puts "  #{endpoint}: #{count} calls" if count > 50
end

# ============================================================
# Example 7: Count-Min Sketch - Merging Distributed Counts
# ============================================================

puts "\nExample 7: Count-Min Sketch - Merging Distributed Counts"
puts "-" * 80

# Track page views from multiple servers
server1_views = redis.count_min_sketch(:pageviews, :server1)
server1_views.init_by_dim(width: 2000, depth: 5)
server1_views.increment("/home", "/home")
server1_views.increment("/about")

server2_views = redis.count_min_sketch(:pageviews, :server2)
server2_views.init_by_dim(width: 2000, depth: 5)
server2_views.increment("/home", "/home", "/home")
server2_views.increment("/about", "/about")

puts "Server 1 - /home views: #{server1_views.query("/home")}"
puts "Server 2 - /home views: #{server2_views.query("/home")}"

# Merge into total
total_views = redis.count_min_sketch(:pageviews, :total)
total_views.init_by_dim(width: 2000, depth: 5)
total_views.merge("pageviews:server1", "pageviews:server2")

puts "Total - /home views: #{total_views.query("/home")}"
puts "Total - /about views: #{total_views.query("/about")}"

# ============================================================
# Example 8: Top-K - Trending Products
# ============================================================

puts "\nExample 8: Top-K - Trending Products"
puts "-" * 80

# Track top 5 trending products
trending = redis.top_k(:trending, :products)
trending.reserve(k: 5)

# Simulate product views
products = [
  "product:123", "product:123", "product:123", "product:123", "product:123",
  "product:456", "product:456", "product:456", "product:456",
  "product:789", "product:789", "product:789",
  "product:101", "product:101",
  "product:202",
  "product:303", # This might not make it to top 5
]

products.each { |product| trending.add(product) }

# Get top 5 trending products
top_products = trending.list
puts "\nTop 5 trending products:"
top_products.each_with_index do |product, index|
  puts "  #{index + 1}. #{product}"
end

# Get top products with counts
top_with_counts = trending.list(with_counts: true)
puts "\nTop 5 with view counts:"
top_with_counts.each_with_index do |(product, count), index|
  puts "  #{index + 1}. #{product}: #{count} views"
end

# ============================================================
# Example 9: Top-K - Popular Search Terms
# ============================================================

puts "\nExample 9: Top-K - Popular Search Terms"
puts "-" * 80

# Track top 10 search terms
popular_searches = redis.top_k(:search, :terms)
popular_searches.reserve(k: 10, width: 1000, depth: 5, decay: 0.9)

# Simulate searches
searches = {
  "redis" => 50,
  "ruby" => 40,
  "database" => 30,
  "cache" => 25,
  "nosql" => 20,
  "performance" => 15,
  "scaling" => 10,
  "docker" => 8,
  "kubernetes" => 5,
  "microservices" => 3,
  "serverless" => 2,
}

searches.each do |term, count|
  popular_searches.increment_by(term, count)
end

# Get top 10 search terms
top_searches = popular_searches.list(with_counts: true)
puts "\nTop 10 search terms:"
top_searches.each_with_index do |(term, count), index|
  puts "  #{index + 1}. #{term}: #{count} searches"
end

# Check if specific terms are in top 10
check_terms = %w[redis serverless unknown]
puts "\nAre these in top 10?"
check_terms.each do |term|
  in_top = popular_searches.query(term)
  puts "  #{term}: #{in_top ? "YES" : "NO"}"
end

# ============================================================
# Example 10: Top-K - Real-time Leaderboard
# ============================================================

puts "\nExample 10: Top-K - Real-time Leaderboard"
puts "-" * 80

# Track top 3 players by score
leaderboard = redis.top_k(:game, :leaderboard)
leaderboard.reserve(k: 3)

# Players earn points
players = {
  "player:alice" => 1000,
  "player:bob" => 800,
  "player:charlie" => 600,
  "player:david" => 400,
  "player:eve" => 200,
}

players.each do |player, score|
  leaderboard.increment_by(player, score)
end

# Get top 3 players
top_players = leaderboard.list(with_counts: true)
puts "\nTop 3 Players:"
medals = %w[1st 2nd 3rd].freeze
top_players.each_with_index do |(player, score), index|
  puts "  #{medals[index]} #{player}: #{score} points"
end

# Check if a player is in top 3
puts "\nIs player:david in top 3? #{leaderboard.query("player:david")}"
puts "Is player:alice in top 3? #{leaderboard.query("player:alice")}"

# ============================================================
# Example 11: Chaining Operations
# ============================================================

puts "\nExample 11: Chaining Operations"
puts "-" * 80

# Bloom Filter chaining
puts "Bloom Filter chaining:"
bloom = redis.bloom_filter(:chaining, :bloom)
  .reserve(error_rate: 0.01, capacity: 1000)
  .add("item1", "item2", "item3")
  .expire(3600)

puts "  Items added: 3"
puts "  Exists item1? #{bloom.exists?("item1")}"
puts "  TTL: #{bloom.ttl} seconds"

# Cuckoo Filter chaining
puts "\nCuckoo Filter chaining:"
cuckoo = redis.cuckoo_filter(:chaining, :cuckoo)
  .reserve(capacity: 1000)
  .add("item1", "item2", "item3")
  .remove("item2")
  .expire(3600)

puts "  Items added: 3, removed: 1"
puts "  Exists item1? #{cuckoo.exists?("item1")}"
puts "  Exists item2? #{cuckoo.exists?("item2")}"

# Count-Min Sketch chaining
puts "\nCount-Min Sketch chaining:"
cms = redis.count_min_sketch(:chaining, :cms)
  .init_by_dim(width: 2000, depth: 5)
  .increment("/home", "/about")
  .increment_by("/home", 5)
  .expire(3600)

puts "  /home count: #{cms.query("/home")}"
puts "  /about count: #{cms.query("/about")}"

# Top-K chaining
puts "\nTop-K chaining:"
topk = redis.top_k(:chaining, :topk)
  .reserve(k: 3)
  .increment_by("item1", 10)
  .increment_by("item2", 5)
  .expire(3600)

puts "  Top items: #{topk.list.join(", ")}"

# ============================================================
# Example 12: Comparison - Bloom vs Cuckoo
# ============================================================

puts "\nExample 12: Comparison - Bloom vs Cuckoo"
puts "-" * 80

# Create both filters
bloom_comp = redis.bloom_filter(:comparison, :bloom)
bloom_comp.reserve(error_rate: 0.01, capacity: 1000)

cuckoo_comp = redis.cuckoo_filter(:comparison, :cuckoo)
cuckoo_comp.reserve(capacity: 1000)

# Add same items to both
items = %w[item1 item2 item3]
bloom_comp.add(*items)
cuckoo_comp.add(*items)

puts "Added items: #{items.join(", ")}"
puts "\nBloom Filter:"
puts "  Can check existence: YES"
puts "  Can delete items: NO"
puts "  False positives: Possible"
puts "  item1 exists? #{bloom_comp.exists?("item1")}"

puts "\nCuckoo Filter:"
puts "  Can check existence: YES"
puts "  Can delete items: YES"
puts "  False positives: Possible (lower rate)"
puts "  item1 exists? #{cuckoo_comp.exists?("item1")}"

# Try to delete from both
puts "\nAttempting to delete 'item1':"
cuckoo_comp.remove("item1")
puts "  Cuckoo: item1 exists? #{cuckoo_comp.exists?("item1")} (deleted successfully)"
puts "  Bloom: item1 exists? #{bloom_comp.exists?("item1")} (cannot delete from Bloom)"

# ============================================================
# Cleanup
# ============================================================

puts "\n#{"=" * 80}"
puts "Cleaning up all test data..."
puts "=" * 80

# Clean up all test keys
[
  spam_filter, processed_urls, active_sessions, cache_admitted,
  pageviews, api_calls, server1_views, server2_views, total_views,
  trending, popular_searches, leaderboard,
  bloom, cuckoo, cms, topk,
  bloom_comp, cuckoo_comp,
].each(&:delete)

puts "All test data cleaned up!"
puts "\nExamples completed successfully! 🎉"
