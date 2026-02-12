# Redis Pub/Sub - Idiomatic Ruby API Proposal

## Goal

Make it easy to replace popular Ruby pub/sub libraries (Wisper, Bunny/RabbitMQ, Sidekiq) with Redis Pub/Sub with **minimal cognitive load**.

## Inspiration

### 1. **Wisper** (Ruby Pub/Sub Gem)
- Simple `broadcast(event, *args)` API
- Chainable `on(event) { }` subscriptions
- Global and scoped listeners
- Async support

### 2. **Bunny** (RabbitMQ Ruby Client)
- Queue/Exchange/Binding model
- Block-based subscription with `subscribe { |delivery_info, metadata, payload| }`
- Chainable operations

### 3. **Existing Redis Pub/Sub**
- Already has good block-based API with `subscribe(*channels) { |on| }`
- Background subscriber with `Subscriber` class
- Pattern subscriptions with `psubscribe`

## Proposed API

### 1. **Publisher Proxy** - Chainable Publishing

Inspired by Wisper's simplicity and Bunny's chainable operations.

```ruby
# Simple publishing
redis.publisher(:notifications)
  .send("User logged in")
  .send("Profile updated")

# With metadata
redis.publisher(:events)
  .send("order_created", order_id: 123, amount: 99.99)
  .send("payment_processed", transaction_id: "abc123")

# Broadcast to multiple channels
redis.publisher
  .to(:news, :sports, :weather)
  .send("Breaking news!")

# Shard publishing (Redis 7.0+)
redis.shard_publisher("user:{123}:updates")
  .send("profile_updated")
```

**Key Features:**
- Chainable `send()` method for multiple publishes
- Automatic JSON encoding for hashes
- Support for both regular and sharded pub/sub
- Composite key support with automatic `:` joining

---

### 2. **Enhanced Subscriber Builder** - Fluent Subscriptions

Inspired by Wisper's `on()` method and existing Redis API.

```ruby
# Fluent subscription builder
redis.subscriber
  .on(:news, :sports) { |channel, message| puts "#{channel}: #{message}" }
  .on_pattern("user:*") { |pattern, channel, msg| notify_user(channel, msg) }
  .on_shard("order:{123}:*") { |channel, msg| process_order(msg) }
  .run  # Blocking

# Or run in background
subscriber = redis.subscriber
  .on(:events) { |ch, msg| EventProcessor.process(msg) }
  .on_pattern("metrics:*") { |pattern, ch, msg| MetricsCollector.collect(msg) }

thread = subscriber.run_async
# ... do other work ...
subscriber.stop
```

**Key Features:**
- Chainable `on()` for channel subscriptions
- Chainable `on_pattern()` for pattern subscriptions
- Chainable `on_shard()` for shard subscriptions (Redis 7.0+)
- `run` for blocking, `run_async` for background thread
- Automatic unsubscribe on `stop`

---

### 3. **Broadcast Helper** - Wisper-style API

For applications migrating from Wisper, provide a familiar API.

```ruby
# Wisper-style broadcasting
class OrderService
  include RedisRuby::Broadcaster
  
  def create_order(params)
    order = Order.create(params)
    
    if order.persisted?
      broadcast(:order_created, order.to_json)
    else
      broadcast(:order_failed, order.errors.to_json)
    end
  end
end

# Subscribe to broadcasts
service = OrderService.new
service.on(:order_created) { |data| puts "Order created: #{data}" }
service.on(:order_failed) { |data| puts "Order failed: #{data}" }
```

**Key Features:**
- Mixin module for Wisper-style API
- `broadcast(event, *args)` method
- `on(event, &block)` for subscriptions
- Automatic channel naming based on class/event

---

### 4. **Message Queue Pattern** - Bunny-style API

For applications migrating from RabbitMQ/Bunny, provide familiar patterns.

```ruby
# Queue-like subscription (using consumer groups under the hood)
redis.queue(:tasks)
  .subscribe(ack: true) do |message|
    process_task(message)
    # Auto-ack on success, nack on exception
  end

# Multiple workers on same queue
redis.queue(:tasks)
  .worker(:worker1)
  .subscribe { |msg| process(msg) }

redis.queue(:tasks)
  .worker(:worker2)
  .subscribe { |msg| process(msg) }
```

**Key Features:**
- Queue abstraction using Redis Streams consumer groups
- Automatic acknowledgment handling
- Multiple workers for load distribution
- Familiar API for Bunny/RabbitMQ users

---

## Implementation Plan

### Phase 1: Publisher Proxy
1. Create `PublisherProxy` class
2. Implement `send()` method with chaining
3. Implement `to()` for multi-channel publishing
4. Add JSON encoding support
5. Add tests

### Phase 2: Enhanced Subscriber
6. Create `SubscriberBuilder` class
7. Implement `on()`, `on_pattern()`, `on_shard()` methods
8. Implement `run()` and `run_async()` methods
9. Add tests

### Phase 3: Broadcaster Mixin (Optional)
10. Create `Broadcaster` module
11. Implement `broadcast()` and `on()` methods
12. Add tests

### Phase 4: Queue Pattern (Future - uses Streams)
13. Create `QueueProxy` class using Streams consumer groups
14. Implement `subscribe()` with ack support
15. Add tests

---

## Migration Examples

### From Wisper

**Before (Wisper):**
```ruby
class OrderService
  include Wisper::Publisher
  
  def create_order
    broadcast(:order_created, order_id)
  end
end

service = OrderService.new
service.on(:order_created) { |id| puts id }
```

**After (Redis Pub/Sub):**
```ruby
class OrderService
  include RedisRuby::Broadcaster
  
  def create_order
    broadcast(:order_created, order_id)
  end
end

service = OrderService.new
service.on(:order_created) { |id| puts id }
```

### From Bunny/RabbitMQ

**Before (Bunny):**
```ruby
queue = channel.queue("tasks")
queue.subscribe do |delivery_info, metadata, payload|
  process(payload)
end
```

**After (Redis Pub/Sub):**
```ruby
redis.subscriber
  .on(:tasks) { |channel, payload| process(payload) }
  .run_async
```

---

## Benefits

1. **Minimal Cognitive Load** - Familiar APIs for Wisper and Bunny users
2. **Gradual Migration** - Can replace one component at a time
3. **Backward Compatible** - Existing low-level API still works
4. **Modern Ruby** - Chainable, fluent, block-based
5. **Redis Native** - Leverages Redis Pub/Sub and Streams features

