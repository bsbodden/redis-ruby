#!/usr/bin/env ruby
# frozen_string_literal: true

# Comprehensive examples of the idiomatic Ruby API for Redis Streams
#
# This file demonstrates the fluent, chainable interface for working with
# Redis Streams, including stream operations, consumer groups, and multi-stream reading.

require_relative "../lib/redis_ruby"

# Connect to Redis
redis = RedisRuby.new(host: "localhost", port: 6379)

puts "=" * 80
puts "Redis Streams - Idiomatic Ruby API Examples"
puts "=" * 80
puts

# ============================================================
# Example 1: Basic Stream Operations
# ============================================================

puts "Example 1: Basic Stream Operations"
puts "-" * 80

stream = redis.stream(:sensor_data)

# Add entries with chainable syntax
stream.add(sensor: "temperature", value: 23.5, unit: "celsius")
  .add(sensor: "humidity", value: 65, unit: "percent")
  .add(sensor: "pressure", value: 1013, unit: "hPa")

puts "Added 3 entries to stream"
puts "Stream length: #{stream.length}"
puts

# Read all entries
puts "Reading all entries:"
stream.read.range("-", "+").each do |id, fields|
  puts "  #{id}: #{fields}"
end
puts

# Trim stream to keep only last 1000 entries
stream.trim(maxlen: 1000, approximate: true)
puts "Trimmed stream to max 1000 entries"
puts

# ============================================================
# Example 2: Stream Reading with Filters
# ============================================================

puts "Example 2: Stream Reading with Filters"
puts "-" * 80

# Read from specific ID
entries = stream.read.from("0-0").count(2).execute
puts "Read #{entries.length} entries from beginning"
puts

# Read in reverse
entries = stream.read.reverse_range("+", "-").count(2).execute
puts "Read #{entries.length} entries in reverse:"
entries.each { |id, fields| puts "  #{id}: #{fields}" }
puts

# ============================================================
# Example 3: Consumer Groups
# ============================================================

puts "Example 3: Consumer Groups"
puts "-" * 80

# Create consumer group
redis.consumer_group(:sensor_data, :processors) do
  create_from_beginning
end
puts "Created consumer group 'processors'"
puts

# Create multiple consumers
redis.consumer_group(:sensor_data, :processors) do
  create_consumer :worker1
  create_consumer :worker2
end
puts "Created consumers: worker1, worker2"
puts

# ============================================================
# Example 4: Consumer Operations
# ============================================================

puts "Example 4: Consumer Operations"
puts "-" * 80

# Get consumer proxy
consumer = stream.consumer(:processors, :worker1)

# Read as consumer
entries = consumer.read.count(10).execute
puts "Consumer 'worker1' read #{entries.length} entries"

if entries && !entries.empty?
  # Process entries
  entries.each do |id, fields|
    puts "  Processing: #{id} - #{fields}"
  end

  # Acknowledge entries
  ids = entries.map(&:first)
  acked = consumer.ack(*ids)
  puts "Acknowledged #{acked} entries"
end
puts

# ============================================================
# Example 5: Multi-Stream Reading
# ============================================================

puts "Example 5: Multi-Stream Reading"
puts "-" * 80

# Create multiple streams
redis.stream(:events).add(type: "login", user: "alice")
redis.stream(:metrics).add(cpu: 45, memory: 78)
redis.stream(:logs).add(level: "info", message: "Server started")

# Read from multiple streams
results = redis.streams(
  events: "0-0",
  metrics: "0-0",
  logs: "0-0"
).count(10).execute

puts "Read from #{results.keys.length} streams:"
results.each do |stream_key, entries|
  puts "  #{stream_key}: #{entries.length} entries"
end
puts

# Iterate over all entries
puts "All entries:"
redis.streams(events: "0-0", metrics: "0-0", logs: "0-0").each do |stream_key, id, fields|
  puts "  [#{stream_key}] #{id}: #{fields}"
end
puts

# ============================================================
# Example 6: Real-World Workflow
# ============================================================

puts "Example 6: Real-World Workflow - Event Processing"
puts "-" * 80

# Create event stream
events = redis.stream(:user_events)

# Add events
events.add(event: "signup", user_id: 123, email: "alice@example.com")
  .add(event: "login", user_id: 123, ip: "192.168.1.1")
  .add(event: "purchase", user_id: 123, amount: 99.99)

puts "Added 3 user events"
puts

# Create consumer group for event processing
redis.consumer_group(:user_events, :event_processors) do
  create_from_beginning
end

# Process events as a consumer
processor = events.consumer(:event_processors, :processor1)
event_entries = processor.read.count(100).execute

puts "Processing #{event_entries.length} events:"
event_entries.each_value do |fields|
  puts "  Event: #{fields["event"]} for user #{fields["user_id"]}"
end

# Acknowledge processed events
processor.ack(*event_entries.map(&:first))
puts "All events processed and acknowledged"
puts

# ============================================================
# Cleanup
# ============================================================

puts "Cleaning up..."
redis.del(:sensor_data, :events, :metrics, :logs, :user_events)
puts "Done!"

redis.close
