#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "redis_ruby"

# Connect to Redis
redis = RedisRuby.new

puts "=" * 80
puts "Redis Pub/Sub - Idiomatic Ruby API Examples"
puts "=" * 80
puts

# ============================================================
# Example 1: Publisher Proxy - Simple Publishing
# ============================================================

puts "Example 1: Publisher Proxy - Simple Publishing"
puts "-" * 80

publisher = redis.publisher(:notifications)

# Chainable sends
publisher
  .send("User logged in")
  .send("Profile updated")
  .send("Settings changed")

puts "✓ Published 3 messages to :notifications channel"
puts

# ============================================================
# Example 2: Publisher Proxy - Multiple Channels
# ============================================================

puts "Example 2: Publisher Proxy - Multiple Channels"
puts "-" * 80

redis.publisher
  .to(:news, :sports, :weather)
  .send("Breaking news!")

puts "✓ Broadcast message to 3 channels"
puts

# ============================================================
# Example 3: Publisher Proxy - JSON Encoding
# ============================================================

puts "Example 3: Publisher Proxy - JSON Encoding"
puts "-" * 80

redis.publisher(:events)
  .send(event: "order_created", order_id: 123, amount: 99.99)
  .send(event: "payment_processed", transaction_id: "abc123")

puts "✓ Published JSON-encoded events"
puts

# ============================================================
# Example 4: Publisher Proxy - Subscriber Count
# ============================================================

puts "Example 4: Publisher Proxy - Subscriber Count"
puts "-" * 80

publisher = redis.publisher(:metrics)
counts = publisher.subscriber_count

puts "Subscriber count for :metrics: #{counts['metrics']}"
puts

# ============================================================
# Example 5: Subscriber Builder - Basic Subscription
# ============================================================

puts "Example 5: Subscriber Builder - Basic Subscription"
puts "-" * 80

subscriber = redis.subscriber
  .on(:news, :sports) { |channel, message| puts "  [#{channel}] #{message}" }

# Run in background
thread = subscriber.run_async
sleep 0.1

# Publish some messages
redis.publish(:news, "Stock market update")
redis.publish(:sports, "Game results")
sleep 0.1

subscriber.stop
thread.join

puts "✓ Received messages from multiple channels"
puts

# ============================================================
# Example 6: Subscriber Builder - Pattern Subscription
# ============================================================

puts "Example 6: Subscriber Builder - Pattern Subscription"
puts "-" * 80

subscriber = redis.subscriber
  .on_pattern("user:*") do |pattern, channel, message|
    puts "  [#{pattern}] #{channel}: #{message}"
  end

thread = subscriber.run_async
sleep 0.1

redis.publish("user:123", "Profile updated")
redis.publish("user:456", "Settings changed")
sleep 0.1

subscriber.stop
thread.join

puts "✓ Received messages matching pattern"
puts

# ============================================================
# Example 7: Subscriber Builder - JSON Decoding
# ============================================================

puts "Example 7: Subscriber Builder - JSON Decoding"
puts "-" * 80

subscriber = redis.subscriber
  .on(:events, json: true) do |channel, data|
    puts "  Event: #{data['event']}, Order ID: #{data['order_id']}"
  end

thread = subscriber.run_async
sleep 0.1

redis.publisher(:events)
  .send(event: "order_created", order_id: 789)

sleep 0.1
subscriber.stop
thread.join

puts "✓ Automatically decoded JSON messages"
puts

# ============================================================
# Example 8: Subscriber Builder - Mixed Subscriptions
# ============================================================

puts "Example 8: Subscriber Builder - Mixed Subscriptions"
puts "-" * 80

subscriber = redis.subscriber
  .on(:alerts) { |ch, msg| puts "  ALERT: #{msg}" }
  .on(:logs) { |ch, msg| puts "  LOG: #{msg}" }
  .on_pattern("metrics:*") { |pat, ch, msg| puts "  METRIC [#{ch}]: #{msg}" }

thread = subscriber.run_async
sleep 0.1

redis.publish(:alerts, "High CPU usage")
redis.publish(:logs, "Application started")
redis.publish("metrics:cpu", "85%")
redis.publish("metrics:memory", "2.5GB")
sleep 0.1

subscriber.stop
thread.join

puts "✓ Handled multiple subscription types"
puts

# ============================================================
# Example 9: Broadcaster Module - Wisper-style API
# ============================================================

puts "Example 9: Broadcaster Module - Wisper-style API"
puts "-" * 80

class OrderService
  include RedisRuby::Broadcaster

  def initialize(redis_client)
    self.redis_client = redis_client
  end

  def create_order(order_id, amount)
    # Simulate order creation
    puts "  Creating order #{order_id}..."

    # Broadcast event
    broadcast(:order_created, order_id: order_id, amount: amount)
  end
end

# Subscribe to order events
subscriber = redis.subscriber
  .on("order_service:order_created", json: true) do |channel, data|
    puts "  Order created: ID=#{data['order_id']}, Amount=$#{data['amount']}"
  end

thread = subscriber.run_async
sleep 0.1

# Create orders
service = OrderService.new(redis)
service.create_order(123, 99.99)
service.create_order(456, 149.99)
sleep 0.1

subscriber.stop
thread.join

puts "✓ Wisper-style broadcasting works!"
puts

# ============================================================
# Example 10: Integration - Publisher + Subscriber + JSON
# ============================================================

puts "Example 10: Integration - Publisher + Subscriber + JSON"
puts "-" * 80

# Set up subscriber with JSON decoding
subscriber = redis.subscriber
  .on(:orders, json: true) do |channel, order|
    puts "  Processing order: #{order['id']} - #{order['status']}"
  end

thread = subscriber.run_async
sleep 0.1

# Publish orders with automatic JSON encoding
publisher = redis.publisher(:orders)
publisher
  .send(id: 1, status: "pending", total: 50.00)
  .send(id: 2, status: "processing", total: 75.50)
  .send(id: 3, status: "completed", total: 120.00)

sleep 0.1
subscriber.stop
thread.join

puts "✓ End-to-end JSON encoding/decoding"
puts

# ============================================================
# Example 11: Migration from Wisper
# ============================================================

puts "Example 11: Migration from Wisper"
puts "-" * 80
puts "Before (Wisper):"
puts "  class MyService"
puts "    include Wisper::Publisher"
puts "    def do_something"
puts "      broadcast(:something_happened, data)"
puts "    end"
puts "  end"
puts
puts "After (Redis Pub/Sub):"
puts "  class MyService"
puts "    include RedisRuby::Broadcaster"
puts "    def do_something"
puts "      broadcast(:something_happened, data)"
puts "    end"
puts "  end"
puts
puts "✓ Drop-in replacement for Wisper!"
puts

# ============================================================
# Example 12: Migration from Bunny/RabbitMQ
# ============================================================

puts "Example 12: Migration from Bunny/RabbitMQ"
puts "-" * 80
puts "Before (Bunny):"
puts "  queue = channel.queue('tasks')"
puts "  queue.subscribe do |delivery_info, metadata, payload|"
puts "    process(payload)"
puts "  end"
puts
puts "After (Redis Pub/Sub):"
puts "  redis.subscriber"
puts "    .on(:tasks) { |channel, payload| process(payload) }"
puts "    .run_async"
puts
puts "✓ Familiar API for RabbitMQ users!"
puts

# ============================================================
# Cleanup
# ============================================================

puts "=" * 80
puts "All examples completed successfully!"
puts "=" * 80

redis.close

