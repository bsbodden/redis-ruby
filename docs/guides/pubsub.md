---
layout: default
title: Pub/Sub Messaging
parent: Guides
nav_order: 5
---

# Pub/Sub Messaging

This guide covers Redis Pub/Sub (Publish/Subscribe) messaging in redis-ruby, a powerful pattern for building real-time applications, chat systems, notifications, and event-driven architectures.

## Table of Contents

- [What is Pub/Sub](#what-is-pubsub)
- [Publishing Messages](#publishing-messages)
- [Subscribing to Channels](#subscribing-to-channels)
- [Pattern Subscriptions](#pattern-subscriptions)
- [Unsubscribing](#unsubscribing)
- [Message Handling](#message-handling)
- [Background Subscriptions](#background-subscriptions)
- [Shard Channels (Redis 7.0+)](#shard-channels-redis-70)
- [Best Practices](#best-practices)
- [Use Cases](#use-cases)

## What is Pub/Sub

Redis Pub/Sub implements the publish/subscribe messaging paradigm where:

- **Publishers** send messages to channels without knowing who will receive them
- **Subscribers** express interest in channels and receive messages without knowing who sent them
- Messages are **fire-and-forget** - not stored, only delivered to active subscribers

### Key Characteristics

- **Real-time delivery**: Messages are delivered immediately to active subscribers
- **No persistence**: Messages are not stored; offline subscribers miss messages
- **Decoupling**: Publishers and subscribers don't need to know about each other
- **Fan-out**: One message can be delivered to multiple subscribers
- **Blocking operation**: Subscription blocks the connection until unsubscribed

## Publishing Messages

Publishing is simple and non-blocking:

```ruby
require "redis_ruby"

redis = RedisRuby.new(host: "localhost")

# Publish a message to a channel
# Returns the number of subscribers that received the message
count = redis.publish("news", "Breaking news!")
# => 3 (if 3 clients are subscribed to "news")

# Publish to multiple channels
redis.publish("events", "user:signup")
redis.publish("notifications", "New message from Alice")
redis.publish("chat:room1", "Hello everyone!")
```

### Publishing JSON Data

```ruby
require "json"

# Publish structured data
event = {
  type: "user_signup",
  user_id: 123,
  email: "alice@example.com",
  timestamp: Time.now.to_i
}

redis.publish("events", event.to_json)
```

### Check Subscriber Count

```ruby
# Check how many subscribers are on a channel
count = redis.publish("news", "Test message")

if count.zero?
  puts "No subscribers listening"
else
  puts "Message delivered to #{count} subscribers"
end
```

## Subscribing to Channels

Subscribing blocks the connection and enters subscription mode:

```ruby
redis = RedisRuby.new(host: "localhost")

# Subscribe to one or more channels
redis.subscribe("news", "events") do |on|
  # Called when subscription is confirmed
  on.subscribe do |channel, subscriptions|
    puts "Subscribed to #{channel} (#{subscriptions} total subscriptions)"
  end

  # Called when a message is received
  on.message do |channel, message|
    puts "Received on #{channel}: #{message}"
  end

  # Called when unsubscribed
  on.unsubscribe do |channel, subscriptions|
    puts "Unsubscribed from #{channel} (#{subscriptions} remaining)"
  end
end
```

### Basic Example

```ruby
# In one terminal/process - Subscriber
redis = RedisRuby.new(host: "localhost")

redis.subscribe("chat") do |on|
  on.message do |channel, message|
    puts "#{channel}: #{message}"
  end
end

# In another terminal/process - Publisher
redis = RedisRuby.new(host: "localhost")
redis.publish("chat", "Hello, World!")
# Subscriber sees: "chat: Hello, World!"
```

### Multiple Channels

```ruby
redis.subscribe("news", "sports", "weather") do |on|
  on.message do |channel, message|
    case channel
    when "news"
      puts "NEWS: #{message}"
    when "sports"
      puts "SPORTS: #{message}"
    when "weather"
      puts "WEATHER: #{message}"
    end
  end
end
```

### Subscription with Timeout

```ruby
# Subscribe for 30 seconds, then automatically unsubscribe
redis.subscribe_with_timeout(30, "events") do |on|
  on.message do |channel, message|
    puts "#{channel}: #{message}"
  end
end

puts "Subscription ended after timeout"
```

## Pattern Subscriptions

Subscribe to multiple channels using glob-style patterns:

```ruby
# Subscribe to all channels matching a pattern
redis.psubscribe("news.*", "events.*") do |on|
  # Called when pattern subscription is confirmed
  on.psubscribe do |pattern, subscriptions|
    puts "Subscribed to pattern #{pattern}"
  end

  # Called when a message matches the pattern
  on.pmessage do |pattern, channel, message|
    puts "Pattern #{pattern} matched #{channel}: #{message}"
  end

  # Called when unsubscribed from pattern
  on.punsubscribe do |pattern, subscriptions|
    puts "Unsubscribed from pattern #{pattern}"
  end
end
```

### Pattern Examples

```ruby
# Match all user channels
redis.psubscribe("user:*") do |on|
  on.pmessage do |pattern, channel, message|
    # Matches: user:123, user:456, user:alice, etc.
    user_id = channel.split(":").last
    puts "User #{user_id}: #{message}"
  end
end

# Match specific patterns
redis.psubscribe("order:*:completed", "payment:*:success") do |on|
  on.pmessage do |pattern, channel, message|
    puts "Event: #{channel} - #{message}"
  end
end

# Match with character classes
redis.psubscribe("log:[0-9]*") do |on|
  on.pmessage do |pattern, channel, message|
    # Matches: log:1, log:2, log:123, etc.
    puts "Log: #{message}"
  end
end
```

### Pattern Syntax

Redis patterns support glob-style matching:
- `*` - Matches any characters (including none)
- `?` - Matches exactly one character
- `[abc]` - Matches one character from the set
- `[a-z]` - Matches one character from the range

## Unsubscribing

### Unsubscribe from Specific Channels

```ruby
redis.subscribe("news", "sports", "weather") do |on|
  on.message do |channel, message|
    puts "#{channel}: #{message}"

    # Unsubscribe from specific channel
    if message == "quit"
      redis.unsubscribe("news")
    end
  end

  on.unsubscribe do |channel, subscriptions|
    puts "Unsubscribed from #{channel}"
    # Exit when all subscriptions are gone
    break if subscriptions.zero?
  end
end
```

### Unsubscribe from All Channels

```ruby
redis.subscribe("news", "sports") do |on|
  on.message do |channel, message|
    if message == "exit"
      # Unsubscribe from all channels
      redis.unsubscribe
    end
  end
end
```

### Pattern Unsubscribe

```ruby
redis.psubscribe("news.*", "sports.*") do |on|
  on.pmessage do |pattern, channel, message|
    if message == "stop"
      # Unsubscribe from specific pattern
      redis.punsubscribe("news.*")

      # Or unsubscribe from all patterns
      # redis.punsubscribe
    end
  end
end
```

## Message Handling

### Processing JSON Messages

```ruby
require "json"

redis.subscribe("events") do |on|
  on.message do |channel, message|
    begin
      event = JSON.parse(message)

      case event["type"]
      when "user_signup"
        puts "New user: #{event['email']}"
      when "order_placed"
        puts "Order ##{event['order_id']} placed"
      when "payment_received"
        puts "Payment: $#{event['amount']}"
      end
    rescue JSON::ParserError => e
      puts "Invalid JSON: #{e.message}"
    end
  end
end
```

### Error Handling

```ruby
redis.subscribe("events") do |on|
  on.message do |channel, message|
    begin
      process_message(message)
    rescue StandardError => e
      # Log error but keep subscription alive
      puts "Error processing message: #{e.message}"
      # Optionally publish to error channel
      redis_publisher = RedisRuby.new(host: "localhost")
      redis_publisher.publish("errors", "#{channel}: #{e.message}")
    end
  end
end
```

### Message Filtering

```ruby
redis.subscribe("events") do |on|
  on.message do |channel, message|
    # Only process messages matching criteria
    next unless message.include?("important")

    puts "Important event: #{message}"
  end
end
```

## Background Subscriptions

For non-blocking subscriptions, use the `Subscriber` class to run subscriptions in a background thread:

```ruby
require "redis_ruby"

# Create a subscriber with a dedicated connection
client = RedisRuby.new(host: "localhost")
subscriber = RedisRuby::Subscriber.new(client)

# Register callbacks
subscriber.on_message do |channel, message|
  puts "Received: #{message} on #{channel}"
end

subscriber.on_subscribe do |channel, count|
  puts "Subscribed to #{channel}"
end

subscriber.on_unsubscribe do |channel, count|
  puts "Unsubscribed from #{channel}"
end

# Subscribe to channels
subscriber.subscribe("news", "events")

# Run in background thread
thread = subscriber.run_in_thread

# Main thread is free to do other work
puts "Subscriber running in background..."
sleep 1

# Publish from main thread
publisher = RedisRuby.new(host: "localhost")
publisher.publish("news", "Breaking news!")
publisher.publish("events", "Important event!")

sleep 1

# Stop the subscriber
subscriber.stop
thread.join

puts "Subscriber stopped"
```

### Pattern Subscriptions in Background

```ruby
subscriber = RedisRuby::Subscriber.new(client)

subscriber.on_pmessage do |pattern, channel, message|
  puts "#{pattern} -> #{channel}: #{message}"
end

subscriber.psubscribe("user:*", "order:*")
thread = subscriber.run_in_thread

# ... do other work ...

subscriber.stop
thread.join
```

### Error Handling in Background Subscriptions

```ruby
subscriber = RedisRuby::Subscriber.new(client)

subscriber.on_message do |channel, message|
  # Process message
  process_message(message)
end

subscriber.on_error do |error|
  # Handle errors in callbacks
  puts "Subscription error: #{error.message}"
  # Optionally log to error tracking service
end

subscriber.subscribe("events")
subscriber.run_in_thread
```

## Shard Channels (Redis 7.0+)

Redis 7.0 introduced shard channels for better scalability in cluster mode:

```ruby
# Shard channels are distributed across cluster nodes
redis.ssubscribe("user:{123}:updates") do |on|
  on.ssubscribe do |channel, count|
    puts "Subscribed to shard channel #{channel}"
  end

  on.smessage do |channel, message|
    puts "#{channel}: #{message}"
  end

  on.sunsubscribe do |channel, count|
    puts "Unsubscribed from #{channel}"
  end
end

# Publish to shard channel
redis.spublish("user:{123}:updates", "Profile updated")
```

### Benefits of Shard Channels

- **Better scalability**: Messages only sent to relevant cluster nodes
- **Reduced overhead**: No need to broadcast to all nodes
- **Cluster-aware**: Automatically routed to correct shard
- **Hash tag support**: Use `{tag}` to control shard placement

## Best Practices

### 1. Use Separate Connections

Always use separate Redis connections for publishing and subscribing:

```ruby
# ✅ Good: Separate connections
subscriber = RedisRuby.new(host: "localhost")
publisher = RedisRuby.new(host: "localhost")

Thread.new do
  subscriber.subscribe("events") do |on|
    on.message { |ch, msg| puts msg }
  end
end

publisher.publish("events", "Hello!")
```

```ruby
# ❌ Bad: Same connection for both
redis = RedisRuby.new(host: "localhost")

# This won't work - connection is blocked in subscription mode
redis.subscribe("events") do |on|
  on.message do |ch, msg|
    redis.publish("other", msg)  # Error: connection in subscription mode
  end
end
```

### 2. Handle Connection Failures

```ruby
def subscribe_with_retry(redis, channel)
  loop do
    begin
      redis.subscribe(channel) do |on|
        on.message { |ch, msg| process_message(msg) }
      end
    rescue RedisRuby::ConnectionError => e
      puts "Connection lost: #{e.message}"
      sleep 5
      puts "Reconnecting..."
      retry
    end
  end
end
```

### 3. Use Patterns Wisely

```ruby
# ✅ Good: Specific patterns
redis.psubscribe("user:*:notifications")

# ❌ Bad: Too broad, matches everything
redis.psubscribe("*")
```

### 4. Implement Timeouts

```ruby
# Prevent infinite blocking
redis.subscribe_with_timeout(300, "events") do |on|
  on.message { |ch, msg| process_message(msg) }
end

# Reconnect after timeout
```

### 5. Monitor Subscriber Count

```ruby
# Check if anyone is listening before publishing
count = redis.publish("notifications", "Important message")

if count.zero?
  # No subscribers - maybe queue the message instead
  redis.lpush("notification_queue", "Important message")
end
```

### 6. Use Background Threads for Long-Running Subscriptions

```ruby
# ✅ Good: Non-blocking subscription
subscriber = RedisRuby::Subscriber.new(client)
subscriber.on_message { |ch, msg| process_message(msg) }
subscriber.subscribe("events")
thread = subscriber.run_in_thread

# Main thread continues...

# ❌ Bad: Blocks main thread
redis.subscribe("events") do |on|
  on.message { |ch, msg| process_message(msg) }
end
# Code here never executes
```

## Use Cases

### Use Case 1: Real-Time Notifications

```ruby
# Notification service
class NotificationService
  def initialize
    @subscriber = RedisRuby::Subscriber.new(RedisRuby.new)
    @publisher = RedisRuby.new
  end

  def start
    @subscriber.on_message do |channel, message|
      user_id = channel.split(":").last
      send_notification(user_id, message)
    end

    @subscriber.psubscribe("notifications:*")
    @subscriber.run_in_thread
  end

  def notify_user(user_id, message)
    @publisher.publish("notifications:#{user_id}", message)
  end

  private

  def send_notification(user_id, message)
    # Send push notification, email, SMS, etc.
    puts "Notifying user #{user_id}: #{message}"
  end
end

# Usage
service = NotificationService.new
service.start
service.notify_user(123, "You have a new message!")
```

### Use Case 2: Chat Application

```ruby
# Chat room implementation
class ChatRoom
  def initialize(room_id)
    @room_id = room_id
    @channel = "chat:#{room_id}"
    @subscriber = RedisRuby.new
    @publisher = RedisRuby.new
  end

  def join(username)
    Thread.new do
      @subscriber.subscribe(@channel) do |on|
        on.subscribe do
          @publisher.publish(@channel, "#{username} joined the room")
        end

        on.message do |_, message|
          puts message
        end
      end
    end
  end

  def send_message(username, message)
    @publisher.publish(@channel, "#{username}: #{message}")
  end

  def leave(username)
    @publisher.publish(@channel, "#{username} left the room")
    @subscriber.unsubscribe(@channel)
  end
end

# Usage
room = ChatRoom.new("general")
room.join("Alice")
room.send_message("Alice", "Hello everyone!")
```

### Use Case 3: Event-Driven Architecture

```ruby
# Event bus for microservices
class EventBus
  def initialize
    @publisher = RedisRuby.new
    @subscriber = RedisRuby::Subscriber.new(RedisRuby.new)
    @handlers = {}
  end

  def publish(event_type, data)
    event = {
      type: event_type,
      data: data,
      timestamp: Time.now.to_i
    }
    @publisher.publish("events:#{event_type}", event.to_json)
  end

  def subscribe(event_type, &handler)
    @handlers[event_type] = handler
    @subscriber.subscribe("events:#{event_type}")
  end

  def start
    @subscriber.on_message do |channel, message|
      event_type = channel.split(":").last
      event = JSON.parse(message)
      @handlers[event_type]&.call(event)
    end

    @subscriber.run_in_thread
  end
end

# Usage
bus = EventBus.new

bus.subscribe("user_signup") do |event|
  puts "New user: #{event['data']['email']}"
  # Send welcome email, create profile, etc.
end

bus.subscribe("order_placed") do |event|
  puts "Order placed: #{event['data']['order_id']}"
  # Process order, send confirmation, etc.
end

bus.start

# Publish events
bus.publish("user_signup", { email: "alice@example.com" })
bus.publish("order_placed", { order_id: 12345, amount: 99.99 })
```

### Use Case 4: Cache Invalidation

```ruby
# Distributed cache invalidation
class CacheInvalidator
  def initialize
    @cache = {}
    @subscriber = RedisRuby::Subscriber.new(RedisRuby.new)
    @publisher = RedisRuby.new
  end

  def start
    @subscriber.on_message do |channel, key|
      invalidate_local_cache(key)
    end

    @subscriber.subscribe("cache:invalidate")
    @subscriber.run_in_thread
  end

  def get(key)
    @cache[key] ||= fetch_from_database(key)
  end

  def set(key, value)
    @cache[key] = value
    save_to_database(key, value)
    # Notify all instances to invalidate
    @publisher.publish("cache:invalidate", key)
  end

  private

  def invalidate_local_cache(key)
    @cache.delete(key)
    puts "Invalidated cache for: #{key}"
  end

  def fetch_from_database(key)
    # Fetch from database
  end

  def save_to_database(key, value)
    # Save to database
  end
end
```

### Use Case 5: Live Updates Dashboard

```ruby
# Real-time metrics dashboard
class MetricsDashboard
  def initialize
    @subscriber = RedisRuby::Subscriber.new(RedisRuby.new)
    @publisher = RedisRuby.new
  end

  def start
    @subscriber.on_pmessage do |pattern, channel, message|
      metric_type = channel.split(":")[1]
      update_dashboard(metric_type, message)
    end

    @subscriber.psubscribe("metrics:*")
    @subscriber.run_in_thread
  end

  def publish_metric(type, value)
    @publisher.publish("metrics:#{type}", value.to_json)
  end

  private

  def update_dashboard(metric_type, data)
    # Update UI, send to websocket, etc.
    puts "#{metric_type}: #{data}"
  end
end

# Usage
dashboard = MetricsDashboard.new
dashboard.start

# Publish metrics from various services
dashboard.publish_metric("cpu", { value: 45.2, unit: "%" })
dashboard.publish_metric("memory", { value: 2.1, unit: "GB" })
dashboard.publish_metric("requests", { value: 1523, unit: "req/s" })
```

## Comparison with Other Patterns

### Pub/Sub vs. Lists (Queues)

```ruby
# Pub/Sub: Fire-and-forget, real-time
redis.publish("events", "message")  # Lost if no subscribers

# Lists: Persistent, guaranteed delivery
redis.lpush("queue", "message")  # Stored until consumed
message = redis.brpop("queue", timeout: 5)
```

**Use Pub/Sub when:**
- Real-time delivery is more important than guaranteed delivery
- Multiple consumers need the same message
- Messages are transient (notifications, live updates)

**Use Lists when:**
- Messages must not be lost
- Single consumer per message (work queue)
- Messages need to be processed later

### Pub/Sub vs. Streams

```ruby
# Pub/Sub: Simple, no history
redis.publish("events", "message")

# Streams: Persistent, with history
redis.xadd("events", "*", "message", "data")
messages = redis.xread("events", "0")
```

**Use Pub/Sub when:**
- No message history needed
- Simple fan-out messaging
- Minimal overhead required

**Use Streams when:**
- Message history is important
- Consumer groups needed
- Acknowledgment required

## Troubleshooting

### No Messages Received

```ruby
# Check if publisher and subscriber are on same channel
# Publisher
redis.publish("news", "test")  # Returns 0 if no subscribers

# Subscriber - make sure channel name matches exactly
redis.subscribe("news") do |on|  # Not "News" or "news "
  on.message { |ch, msg| puts msg }
end
```

### Connection Blocked

```ruby
# ❌ This blocks forever
redis.subscribe("events") do |on|
  on.message { |ch, msg| puts msg }
end
# Never reaches here

# ✅ Use background thread
Thread.new do
  redis.subscribe("events") do |on|
    on.message { |ch, msg| puts msg }
  end
end
# Continues immediately
```

### Pattern Not Matching

```ruby
# Pattern matching is case-sensitive and exact
redis.psubscribe("user:*")  # Matches user:123, user:alice
# Does NOT match: User:123, users:123, user:123:profile
```

## Next Steps

- [Transactions](/guides/transactions/) - Atomic operations with MULTI/EXEC
- [Lua Scripting](/guides/lua-scripting/) - Server-side scripting for complex operations
- [Pipelines](/guides/pipelines/) - Batch commands for better performance
- [Connection Pools](/guides/connection-pools/) - Thread-safe connection management

## Additional Resources

- [Redis Pub/Sub](https://redis.io/docs/manual/pubsub/) - Official Redis documentation
- [Pub/Sub Commands](https://redis.io/commands/?group=pubsub) - Command reference
- [Redis Streams](https://redis.io/docs/data-types/streams/) - Alternative to Pub/Sub with persistence


