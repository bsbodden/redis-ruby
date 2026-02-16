---
layout: default
title: Pub/Sub Example
parent: Examples
nav_order: 4
permalink: /examples/pubsub/
---

# Pub/Sub Example

This example demonstrates how to use Redis Pub/Sub for real-time messaging and event-driven applications.

## Prerequisites

- Ruby 3.2+ installed
- Redis 6.2+ running on localhost:6379
- redis-ruby gem installed (`gem install redis-ruby`)

## Complete Example

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "redis_ruby"  # Native RR API

puts "=== Pub/Sub Example ===\n\n"

# ============================================================================
# Basic Pub/Sub
# ============================================================================

puts "1. Basic Pub/Sub..."

# Create subscriber
subscriber = RR.new(url: "redis://localhost:6379")

# Create publisher
publisher = RR.new(url: "redis://localhost:6379")

# Subscribe in a background thread
messages = []
thread = Thread.new do
  subscriber.subscribe("notifications") do |on|
    on.message do |channel, message|
      puts "   Received on #{channel}: #{message}"
      messages << message
      subscriber.unsubscribe if messages.size >= 3
    end
  end
end

# Give subscriber time to connect
sleep 0.1

# Publish messages
publisher.publish("notifications", "Hello, World!")
publisher.publish("notifications", "Message 2")
publisher.publish("notifications", "Message 3")

# Wait for subscriber to finish
thread.join

puts "   Received #{messages.size} messages\n\n"

# ============================================================================
# Pattern Subscriptions
# ============================================================================

puts "2. Pattern subscriptions..."

subscriber2 = RR.new(url: "redis://localhost:6379")
pattern_messages = []

thread2 = Thread.new do
  subscriber2.psubscribe("user:*:notifications") do |on|
    on.pmessage do |pattern, channel, message|
      puts "   Pattern #{pattern} matched #{channel}: #{message}"
      pattern_messages << { channel: channel, message: message }
      subscriber2.punsubscribe if pattern_messages.size >= 3
    end
  end
end

sleep 0.1

# Publish to different user channels
publisher.publish("user:1:notifications", "User 1 notification")
publisher.publish("user:2:notifications", "User 2 notification")
publisher.publish("user:3:notifications", "User 3 notification")

thread2.join

puts "   Received #{pattern_messages.size} pattern messages\n\n"

# ============================================================================
# Multiple Channels
# ============================================================================

puts "3. Multiple channels..."

subscriber3 = RR.new(url: "redis://localhost:6379")
multi_messages = []

thread3 = Thread.new do
  subscriber3.subscribe("news", "sports", "weather") do |on|
    on.message do |channel, message|
      puts "   [#{channel}] #{message}"
      multi_messages << { channel: channel, message: message }
      subscriber3.unsubscribe if multi_messages.size >= 3
    end
  end
end

sleep 0.1

publisher.publish("news", "Breaking news!")
publisher.publish("sports", "Team wins championship!")
publisher.publish("weather", "Sunny today!")

thread3.join

puts "   Received #{multi_messages.size} messages from multiple channels\n\n"

# ============================================================================
# Real-Time Notification System
# ============================================================================

puts "4. Real-time notification system..."

class NotificationSystem
  def initialize(redis_url)
    @publisher = RR.new(url: redis_url)
  end

  def notify_user(user_id, message)
    @publisher.publish("user:#{user_id}:notifications", message)
  end

  def broadcast(message)
    @publisher.publish("broadcast", message)
  end

  def close
    @publisher.close
  end
end

class NotificationListener
  def initialize(redis_url, user_id)
    @subscriber = RR.new(url: redis_url)
    @user_id = user_id
    @messages = []
  end

  def start
    @thread = Thread.new do
      @subscriber.subscribe("user:#{@user_id}:notifications", "broadcast") do |on|
        on.message do |channel, message|
          @messages << { channel: channel, message: message, time: Time.now }
        end
      end
    end
  end

  def stop
    @subscriber.unsubscribe
    @thread.join
  end

  def messages
    @messages
  end

  def close
    @subscriber.close
  end
end

# Create notification system
notifier = NotificationSystem.new("redis://localhost:6379")

# Create listeners for two users
listener1 = NotificationListener.new("redis://localhost:6379", 1)
listener2 = NotificationListener.new("redis://localhost:6379", 2)

listener1.start
listener2.start

sleep 0.1

# Send notifications
notifier.notify_user(1, "You have a new message")
notifier.notify_user(2, "Your order has shipped")
notifier.broadcast("System maintenance in 1 hour")

sleep 0.1

listener1.stop
listener2.stop

puts "   User 1 received: #{listener1.messages.size} messages"
puts "   User 2 received: #{listener2.messages.size} messages"

listener1.close
listener2.close
notifier.close

puts "\n"

# ============================================================================
# Cleanup
# ============================================================================

puts "5. Cleanup..."

subscriber.close
subscriber2.close
subscriber3.close
publisher.close

puts "   Closed all connections\n\n"
```

## Running the Example

```bash
ruby pubsub.rb
```

## Key Takeaways

1. **Real-Time** - Pub/Sub enables instant message delivery
2. **Patterns** - Use PSUBSCRIBE for wildcard channel matching
3. **Multiple Channels** - Subscribe to multiple channels simultaneously
4. **Dedicated Connection** - Subscribers need dedicated connections
5. **Background Processing** - Run subscribers in background threads

## Next Steps

- [Advanced Features Example](/examples/advanced-features/) - JSON, Search, and more
- [Pub/Sub Guide](/guides/pubsub/) - Detailed Pub/Sub documentation

