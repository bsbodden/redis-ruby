#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/redis_ruby"

# Connect to Redis
redis = RedisRuby.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379"))

puts "=" * 80
puts "Redis Lists - Idiomatic Ruby API Examples"
puts "=" * 80

# ============================================================
# Example 1: Job Queue (FIFO)
# ============================================================

puts "\nExample 1: Job Queue (FIFO)"
puts "-" * 80

jobs = redis.list(:jobs, :pending)

# Producer adds jobs to the queue
jobs.push("process_payment", "send_email", "generate_report")
puts "Added 3 jobs to queue"
puts "Queue length: #{jobs.length}"

# Consumer processes jobs (FIFO - First In, First Out)
puts "\nProcessing jobs:"
3.times do
  job = jobs.shift # Get oldest job
  puts "  - Processing: #{job}"
end

puts "Queue length after processing: #{jobs.length}"

# ============================================================
# Example 2: Undo Stack (LIFO)
# ============================================================

puts "\nExample 2: Undo Stack (LIFO)"
puts "-" * 80

undo_stack = redis.list(:editor, :undo)

# User performs actions
undo_stack.push("typed 'hello'")
undo_stack.push("deleted word")
undo_stack.push("inserted line")
undo_stack.push("formatted code")

puts "Actions in stack: #{undo_stack.length}"

# Undo last 2 actions (LIFO - Last In, First Out)
puts "\nUndoing actions:"
2.times do
  action = undo_stack.pop # Get most recent action
  puts "  - Undoing: #{action}"
end

puts "Remaining actions: #{undo_stack.length}"

# ============================================================
# Example 3: Recent Activity Feed
# ============================================================

puts "\nExample 3: Recent Activity Feed"
puts "-" * 80

feed = redis.list(:user, 123, :activity)

# Add activities to the front (most recent first)
feed.unshift("commented on post:789")
feed.unshift("liked post:456")
feed.unshift("shared article:321")
feed.unshift("followed user:999")

# Keep only recent 3 activities
feed.keep(3)

puts "Recent activities:"
feed.each_with_index do |activity, index|
  puts "  #{index + 1}. #{activity}"
end

# ============================================================
# Example 4: Array-Like Operations
# ============================================================

puts "\nExample 4: Array-Like Operations"
puts "-" * 80

items = redis.list(:shopping, :cart)

# Add items using different methods
items << "apples"
items.push("bananas", "oranges")
items.unshift("milk") # Add to front

puts "Cart items: #{items.to_a.inspect}"

# Access by index
puts "\nFirst item: #{items.first}"
puts "Last item: #{items.last}"
puts "Item at index 1: #{items[1]}"

# Range access
puts "First 2 items: #{items[0..1].inspect}"

# Update item
items[1] = "green apples"
puts "Updated cart: #{items.to_a.inspect}"

# ============================================================
# Example 5: Priority Inbox
# ============================================================

puts "\nExample 5: Priority Inbox"
puts "-" * 80

inbox = redis.list(:email, :inbox)

# Regular emails go to the back
inbox.push("newsletter", "promotion", "update")

# Urgent emails go to the front
inbox.unshift("urgent: meeting in 5 min")
inbox.unshift("urgent: server down")

puts "Inbox (#{inbox.length} emails):"
inbox.each_with_index do |email, i|
  puts "  #{i + 1}. #{email}"
end

# Process urgent emails first
puts "\nProcessing first 2 emails:"
2.times do
  email = inbox.shift
  puts "  - #{email}"
end

# ============================================================
# Example 6: Circular Buffer (Sensor Readings)
# ============================================================

puts "\nExample 6: Circular Buffer (Sensor Readings)"
puts "-" * 80

readings = redis.list(:sensor, :temperature)

# Simulate sensor readings
10.times do |_i|
  temp = rand(20..24)
  readings.push("#{temp}°C")
  readings.keep(5) # Keep only last 5 readings
end

puts "Last 5 temperature readings:"
readings.each_with_index do |reading, i|
  puts "  #{i + 1}. #{reading}"
end

# ============================================================
# Example 7: Insertion and Removal
# ============================================================

puts "\nExample 7: Insertion and Removal"
puts "-" * 80

playlist = redis.list(:music, :playlist)
playlist.push("song1", "song2", "song3", "song4")

puts "Original playlist: #{playlist.to_a.inspect}"

# Insert a song after song2
playlist.insert_after("song2", "bonus_track")
puts "After insertion: #{playlist.to_a.inspect}"

# Remove a song
playlist.remove("song3")
puts "After removal: #{playlist.to_a.inspect}"

# ============================================================
# Example 8: Chainable Operations
# ============================================================

puts "\nExample 8: Chainable Operations"
puts "-" * 80

session_queue = redis.list(:session, SecureRandom.hex(4))
  .push("task1", "task2", "task3", "task4", "task5")
  .trim(0..2) # Keep only first 3
  .expire(3600) # Expire in 1 hour

puts "Session queue: #{session_queue.to_a.inspect}"
puts "TTL: #{session_queue.ttl} seconds"

# ============================================================
# Cleanup
# ============================================================

puts "\n#{"=" * 80}"
puts "Cleaning up..."
redis.del(
  "jobs:pending",
  "editor:undo",
  "user:123:activity",
  "shopping:cart",
  "email:inbox",
  "sensor:temperature",
  "music:playlist"
)
# Session queue will auto-expire
redis.close
puts "Done!"
