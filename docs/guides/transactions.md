---
layout: default
title: Transactions
parent: Guides
nav_order: 4
---

# Transactions

This guide covers Redis transactions in redis-ruby, enabling atomic execution of multiple commands using MULTI/EXEC, optimistic locking with WATCH, and best practices for ensuring data consistency.

## Table of Contents

- [What are Transactions](#what-are-transactions)
- [Basic Transaction Usage](#basic-transaction-usage)
- [WATCH for Optimistic Locking](#watch-for-optimistic-locking)
- [DISCARD to Cancel](#discard-to-cancel)
- [Error Handling](#error-handling)
- [Comparison with Pipelines](#comparison-with-pipelines)
- [Best Practices](#best-practices)
- [Common Use Cases](#common-use-cases)

## What are Transactions

Redis transactions allow you to execute a group of commands atomically using MULTI/EXEC:

- **Atomic execution**: All commands execute together, or none execute
- **Isolation**: No other client commands execute during the transaction
- **Queued execution**: Commands are queued and executed when EXEC is called
- **All-or-nothing**: Either all commands succeed, or the transaction is aborted

### Key Characteristics

```ruby
# Without transaction - other clients can interleave commands
redis.set("counter", 0)
redis.incr("counter")  # Another client could modify counter here
redis.incr("counter")

# With transaction - atomic execution
redis.multi do |tx|
  tx.set("counter", 0)
  tx.incr("counter")
  tx.incr("counter")
end
# All commands execute atomically
```

### How It Works

1. **MULTI**: Starts the transaction, enters queuing mode
2. **Queue commands**: Commands are queued, not executed immediately
3. **EXEC**: Executes all queued commands atomically
4. **Return results**: Returns array of results from all commands

## Basic Transaction Usage

### Simple Transaction

```ruby
require "redis_ruby"  # Native RR API

redis = RR.new(host: "localhost")

# Execute multiple commands atomically
results = redis.multi do |tx|
  tx.set("key1", "value1")
  tx.set("key2", "value2")
  tx.get("key1")
  tx.get("key2")
end

# results => ["OK", "OK", "value1", "value2"]
```

### Counter Example

```ruby
# Atomic counter increment
results = redis.multi do |tx|
  tx.set("counter", 0)
  tx.incr("counter")
  tx.incr("counter")
  tx.incr("counter")
  tx.get("counter")
end

# results => ["OK", 1, 2, 3, "3"]
```

### Account Transfer Example

```ruby
# Transfer money between accounts atomically
def transfer(redis, from_account, to_account, amount)
  redis.multi do |tx|
    tx.decrby("account:#{from_account}:balance", amount)
    tx.incrby("account:#{to_account}:balance", amount)
    tx.set("transfer:last", Time.now.to_i)
  end
end

# Transfer $100 from account 1 to account 2
transfer(redis, 1, 2, 100)
```

### Hash Operations

```ruby
# Atomically update user profile
results = redis.multi do |tx|
  tx.hset("user:123", "name", "Alice", "email", "alice@example.com")
  tx.hset("user:123", "updated_at", Time.now.to_i)
  tx.sadd("users:active", 123)
  tx.hgetall("user:123")
end

# Last result is the complete user hash
user_data = results.last
```

### List Operations

```ruby
# Atomically move item from one list to another
results = redis.multi do |tx|
  tx.rpoplpush("queue:pending", "queue:processing")
  tx.llen("queue:pending")
  tx.llen("queue:processing")
end

item = results[0]
pending_count = results[1]
processing_count = results[2]
```

## WATCH for Optimistic Locking

WATCH provides optimistic locking - the transaction only executes if watched keys haven't changed:

### Basic WATCH Example

```ruby
# Watch a key and execute transaction only if it hasn't changed
result = redis.watch("counter") do
  current = redis.get("counter").to_i
  
  # Transaction only executes if "counter" hasn't changed
  redis.multi do |tx|
    tx.set("counter", current + 1)
  end
end

# result => ["OK"] if successful
# result => nil if counter was modified by another client
```

### Check-and-Set Pattern

```ruby
# Implement check-and-set with retry
def check_and_set(redis, key, expected_value, new_value, max_retries: 3)
  max_retries.times do
    result = redis.watch(key) do
      current = redis.get(key)
      
      if current == expected_value
        redis.multi do |tx|
          tx.set(key, new_value)
        end
      else
        # Value doesn't match, abort
        redis.unwatch
        nil
      end
    end
    
    return true if result  # Transaction succeeded
    
    # Transaction failed, retry
    sleep 0.01
  end
  
  false  # Failed after max retries
end

# Usage
success = check_and_set(redis, "status", "pending", "processing")
```

### Account Balance with WATCH

```ruby
# Safe account withdrawal with balance check
def withdraw(redis, account_id, amount)
  redis.watch("account:#{account_id}:balance") do
    balance = redis.get("account:#{account_id}:balance").to_f
    
    if balance >= amount
      # Sufficient funds - proceed with withdrawal
      redis.multi do |tx|
        tx.decrby("account:#{account_id}:balance", amount)
        tx.lpush("account:#{account_id}:transactions", 
                 "withdrawal:#{amount}:#{Time.now.to_i}")
      end
    else
      # Insufficient funds - abort
      redis.unwatch
      nil
    end
  end
end

# Usage
result = withdraw(redis, 123, 50.0)
if result
  puts "Withdrawal successful"
else
  puts "Insufficient funds or concurrent modification"
end
```

### Inventory Management with WATCH

```ruby
# Reserve inventory item with optimistic locking
def reserve_inventory(redis, product_id, quantity)
  redis.watch("product:#{product_id}:stock") do
    stock = redis.get("product:#{product_id}:stock").to_i

    if stock >= quantity
      redis.multi do |tx|
        tx.decrby("product:#{product_id}:stock", quantity)
        tx.incr("product:#{product_id}:reserved")
        tx.set("product:#{product_id}:last_reservation", Time.now.to_i)
      end
    else
      redis.unwatch
      nil
    end
  end
end

# Usage with retry logic
def reserve_with_retry(redis, product_id, quantity, max_attempts: 5)
  max_attempts.times do |attempt|
    result = reserve_inventory(redis, product_id, quantity)
    return result if result

    puts "Attempt #{attempt + 1} failed, retrying..."
    sleep 0.01 * (2 ** attempt)  # Exponential backoff
  end

  raise "Failed to reserve inventory after #{max_attempts} attempts"
end
```

### Multiple Keys with WATCH

```ruby
# Watch multiple keys
redis.watch("key1", "key2", "key3") do
  val1 = redis.get("key1").to_i
  val2 = redis.get("key2").to_i
  val3 = redis.get("key3").to_i

  # Transaction only executes if none of the watched keys changed
  redis.multi do |tx|
    tx.set("sum", val1 + val2 + val3)
    tx.set("avg", (val1 + val2 + val3) / 3)
  end
end
```

## DISCARD to Cancel

Cancel a transaction before executing:

### Manual DISCARD

```ruby
# In redis-ruby, you can abort by not calling multi
redis.watch("key") do
  value = redis.get("key")

  if value == "abort"
    # Don't start transaction - just unwatch
    redis.unwatch
    nil
  else
    redis.multi do |tx|
      tx.set("key", "new_value")
    end
  end
end
```

### Conditional Transaction

```ruby
def conditional_update(redis, key, condition_proc)
  redis.watch(key) do
    current_value = redis.get(key)

    if condition_proc.call(current_value)
      redis.multi do |tx|
        tx.set(key, yield(current_value))
      end
    else
      redis.unwatch
      nil
    end
  end
end

# Usage
result = conditional_update(redis, "counter", ->(v) { v.to_i < 100 }) do |current|
  current.to_i + 1
end
```

## Error Handling

### Nested MULTI Prevention

Calling `multi` inside a transaction block raises `ArgumentError` immediately, preventing the common mistake of sending a nested `MULTI` to Redis (which Redis itself rejects with an error):

```ruby
redis.multi do |tx|
  tx.set("key", "value")
  tx.multi do |inner_tx|  # => raises ArgumentError: "MULTI calls cannot be nested"
    inner_tx.set("key2", "value2")
  end
end
```

### Aborted Transactions (WatchError)

When a `WATCH`ed key is modified by another client before `EXEC`, the transaction is aborted and `multi` returns `nil`:

```ruby
result = redis.watch("counter") do
  current = redis.get("counter").to_i
  redis.multi do |tx|
    tx.set("counter", current + 1)
  end
end

if result.nil?
  puts "Transaction aborted — another client modified 'counter'"
end
```

### Command Errors in Transactions

```ruby
# Errors during EXEC are raised
begin
  results = redis.multi do |tx|
    tx.set("key", "value")
    tx.incr("key")  # Error: value is not an integer
    tx.get("key")
  end
rescue RR::CommandError => e
  puts "Transaction error: #{e.message}"
  # Error: ERR value is not an integer or out of range
end
```

### Handling Transaction Failures

```ruby
def safe_transaction(redis, max_retries: 3)
  max_retries.times do |attempt|
    begin
      result = yield
      return result if result

      # Transaction aborted (WATCH failed)
      puts "Transaction aborted, retrying (attempt #{attempt + 1})"
      sleep 0.01
    rescue RR::CommandError => e
      puts "Command error: #{e.message}"
      return nil
    end
  end

  nil  # Failed after retries
end

# Usage
result = safe_transaction(redis) do
  redis.watch("counter") do
    current = redis.get("counter").to_i
    redis.multi do |tx|
      tx.set("counter", current + 1)
    end
  end
end
```

### Validation Before Transaction

```ruby
# Validate before starting transaction
def update_with_validation(redis, key, new_value)
  redis.watch(key) do
    current = redis.get(key)

    # Validate current state
    unless valid_transition?(current, new_value)
      redis.unwatch
      raise "Invalid state transition: #{current} -> #{new_value}"
    end

    redis.multi do |tx|
      tx.set(key, new_value)
      tx.lpush("#{key}:history", "#{current}->#{new_value}")
    end
  end
end

def valid_transition?(from, to)
  # Custom validation logic
  from != to
end
```

## Comparison with Pipelines

### Transactions vs. Pipelines

```ruby
# Pipeline: Fast, not atomic
results = redis.pipelined do |pipe|
  pipe.set("key1", "value1")
  pipe.set("key2", "value2")
  pipe.incr("counter")
end
# Other clients can see intermediate states

# Transaction: Atomic, slightly slower
results = redis.multi do |tx|
  tx.set("key1", "value1")
  tx.set("key2", "value2")
  tx.incr("counter")
end
# All commands execute atomically
```

### Pipeline with Transaction

Combine both for atomic execution with batching:

```ruby
# Best of both worlds
results = redis.pipelined do |pipe|
  # First transaction
  pipe.multi do |tx|
    tx.decrby("account:1", 100)
    tx.incrby("account:2", 100)
  end

  # Regular command
  pipe.get("account:1")

  # Second transaction
  pipe.multi do |tx|
    tx.incr("transfer_count")
    tx.set("last_transfer", Time.now.to_i)
  end
end

# results => [["OK", "OK"], "900", ["OK", "OK"]]
```

### When to Use Each

**Use Transactions when:**
- Atomicity is required
- Commands must execute together or not at all
- Preventing race conditions
- Implementing optimistic locking

**Use Pipelines when:**
- Performance is critical
- Commands are independent
- Atomicity is not required
- Batching read operations

**Use Both when:**
- Need atomic operations AND batching
- Multiple independent transactions
- Optimizing atomic operations

## Best Practices

### 1. Keep Transactions Small

```ruby
# ✅ Good: Small, focused transaction
redis.multi do |tx|
  tx.decrby("inventory:#{product_id}", quantity)
  tx.incr("sales_count")
end

# ❌ Bad: Large transaction with many operations
redis.multi do |tx|
  100.times do |i|
    tx.set("key:#{i}", "value:#{i}")
  end
end
```

### 2. Use WATCH for Conditional Updates

```ruby
# ✅ Good: Check before update
redis.watch("balance") do
  balance = redis.get("balance").to_f

  if balance >= amount
    redis.multi do |tx|
      tx.decrby("balance", amount)
    end
  else
    redis.unwatch
    nil
  end
end

# ❌ Bad: Update without checking
redis.multi do |tx|
  tx.decrby("balance", amount)  # Might go negative!
end
```

### 3. Implement Retry Logic

```ruby
# ✅ Good: Retry on WATCH failure
def atomic_increment(redis, key, max_retries: 5)
  max_retries.times do
    result = redis.watch(key) do
      current = redis.get(key).to_i
      redis.multi do |tx|
        tx.set(key, current + 1)
      end
    end

    return result if result
    sleep 0.001
  end

  raise "Failed after #{max_retries} retries"
end

# ❌ Bad: No retry logic
redis.watch(key) do
  current = redis.get(key).to_i
  redis.multi { |tx| tx.set(key, current + 1) }
end
# Fails silently if key was modified
```

### 4. Unwatch When Aborting

```ruby
# ✅ Good: Explicitly unwatch
redis.watch("key") do
  value = redis.get("key")

  if value == "skip"
    redis.unwatch  # Clean up
    nil
  else
    redis.multi { |tx| tx.set("key", "new") }
  end
end

# ❌ Bad: Leaving keys watched
redis.watch("key") do
  value = redis.get("key")

  if value == "skip"
    nil  # Keys still watched!
  else
    redis.multi { |tx| tx.set("key", "new") }
  end
end
```

### 5. Avoid Long-Running Operations in WATCH Block

```ruby
# ✅ Good: Minimal work in WATCH block
redis.watch("key") do
  value = redis.get("key")
  redis.multi do |tx|
    tx.set("key", value.to_i + 1)
  end
end

# ❌ Bad: Expensive operations in WATCH block
redis.watch("key") do
  value = redis.get("key")

  # Don't do this!
  sleep 5
  result = expensive_api_call(value)

  redis.multi do |tx|
    tx.set("key", result)
  end
end
# Higher chance of WATCH failure
```

### 6. Use Lua Scripts for Complex Logic

```ruby
# ✅ Better: Use Lua script for complex atomic operations
script = <<~LUA
  local balance = tonumber(redis.call('GET', KEYS[1]))
  if balance >= tonumber(ARGV[1]) then
    redis.call('DECRBY', KEYS[1], ARGV[1])
    redis.call('LPUSH', KEYS[2], ARGV[2])
    return 1
  else
    return 0
  end
LUA

result = redis.eval(script, 2, "balance", "transactions", amount, transaction_data)

# ❌ Less efficient: Multiple round-trips with WATCH
redis.watch("balance") do
  balance = redis.get("balance").to_f
  if balance >= amount
    redis.multi do |tx|
      tx.decrby("balance", amount)
      tx.lpush("transactions", transaction_data)
    end
  else
    redis.unwatch
    nil
  end
end
```

## Common Use Cases

### Use Case 1: Rate Limiting

```ruby
# Atomic rate limit check and increment
def rate_limit(redis, user_id, limit: 100, window: 60)
  key = "rate_limit:#{user_id}:#{Time.now.to_i / window}"

  redis.watch(key) do
    current = redis.get(key).to_i

    if current < limit
      result = redis.multi do |tx|
        tx.incr(key)
        tx.expire(key, window)
      end

      { allowed: true, remaining: limit - current - 1 }
    else
      redis.unwatch
      { allowed: false, remaining: 0 }
    end
  end
end

# Usage
result = rate_limit(redis, 123)
if result[:allowed]
  # Process request
  puts "Request allowed, #{result[:remaining]} remaining"
else
  puts "Rate limit exceeded"
end
```

### Use Case 2: Distributed Lock

```ruby
# Simple distributed lock with transaction
class DistributedLock
  def initialize(redis, key, ttl: 10)
    @redis = redis
    @key = "lock:#{key}"
    @ttl = ttl
    @token = SecureRandom.uuid
  end

  def acquire
    result = @redis.multi do |tx|
      tx.set(@key, @token, nx: true, ex: @ttl)
    end

    result&.first == "OK"
  end

  def release
    # Use Lua script to ensure we only delete our own lock
    script = <<~LUA
      if redis.call("GET", KEYS[1]) == ARGV[1] then
        return redis.call("DEL", KEYS[1])
      else
        return 0
      end
    LUA

    @redis.eval(script, 1, @key, @token) == 1
  end

  def with_lock
    if acquire
      begin
        yield
      ensure
        release
      end
    else
      raise "Failed to acquire lock"
    end
  end
end

# Usage
lock = DistributedLock.new(redis, "resource:123")
lock.with_lock do
  # Critical section
  puts "Lock acquired, doing work..."
end
```

### Use Case 3: Atomic Counter with Limits

```ruby
# Increment counter with maximum limit
def increment_with_limit(redis, key, max_value)
  redis.watch(key) do
    current = redis.get(key).to_i

    if current < max_value
      redis.multi do |tx|
        tx.incr(key)
      end
    else
      redis.unwatch
      nil
    end
  end
end

# Usage
result = increment_with_limit(redis, "tickets_sold", 1000)
if result
  puts "Ticket sold! Total: #{result.first}"
else
  puts "Sold out!"
end
```

### Use Case 4: Leaderboard Update

```ruby
# Atomically update multiple leaderboards
def update_leaderboards(redis, user_id, score)
  redis.multi do |tx|
    # Global leaderboard
    tx.zadd("leaderboard:global", score, user_id)

    # Daily leaderboard
    tx.zadd("leaderboard:daily:#{Date.today}", score, user_id)

    # Weekly leaderboard
    tx.zadd("leaderboard:weekly:#{Date.today.cweek}", score, user_id)

    # Update user's best score
    tx.set("user:#{user_id}:best_score", score, xx: false, gt: true)

    # Get user's rank
    tx.zrevrank("leaderboard:global", user_id)
  end
end

# Usage
results = update_leaderboards(redis, 123, 9500)
rank = results.last
puts "Updated leaderboards, current rank: #{rank + 1}"
```

### Use Case 5: Shopping Cart Checkout

```ruby
# Atomic checkout process
def checkout(redis, user_id, cart_items)
  cart_key = "cart:#{user_id}"

  # Watch cart and inventory
  watch_keys = [cart_key] + cart_items.map { |item| "inventory:#{item[:id]}" }

  redis.watch(*watch_keys) do
    # Verify cart contents
    cart = redis.hgetall(cart_key)
    return nil if cart.empty?

    # Check inventory for all items
    sufficient_stock = cart_items.all? do |item|
      stock = redis.get("inventory:#{item[:id]}").to_i
      stock >= item[:quantity]
    end

    unless sufficient_stock
      redis.unwatch
      return { success: false, error: "Insufficient stock" }
    end

    # Execute checkout transaction
    result = redis.multi do |tx|
      # Deduct inventory
      cart_items.each do |item|
        tx.decrby("inventory:#{item[:id]}", item[:quantity])
      end

      # Create order
      order_id = SecureRandom.uuid
      tx.hset("order:#{order_id}", "user_id", user_id, "status", "pending")

      # Clear cart
      tx.del(cart_key)

      # Add to user's orders
      tx.sadd("user:#{user_id}:orders", order_id)
    end

    { success: true, order_id: result[-2] }
  end
end

# Usage
result = checkout(redis, 123, [
  { id: "product:1", quantity: 2 },
  { id: "product:2", quantity: 1 }
])

if result[:success]
  puts "Order placed: #{result[:order_id]}"
else
  puts "Checkout failed: #{result[:error]}"
end
```

## Advanced Patterns

### Optimistic Locking with Versioning

```ruby
# Version-based optimistic locking
def update_with_version(redis, key, expected_version)
  version_key = "#{key}:version"

  redis.watch(key, version_key) do
    current_version = redis.get(version_key).to_i

    if current_version == expected_version
      new_value = yield(redis.get(key))

      redis.multi do |tx|
        tx.set(key, new_value)
        tx.incr(version_key)
      end
    else
      redis.unwatch
      nil
    end
  end
end

# Usage
result = update_with_version(redis, "document:123", 5) do |current_content|
  current_content + "\nNew line"
end
```

### Transaction with Rollback Tracking

```ruby
# Track transaction attempts for debugging
class TransactionTracker
  def initialize(redis)
    @redis = redis
  end

  def execute(name, &block)
    attempts = 0
    start_time = Time.now

    result = loop do
      attempts += 1
      result = block.call

      break result if result
      break nil if attempts >= 5

      sleep 0.01 * attempts
    end

    duration = Time.now - start_time

    # Log transaction metrics
    @redis.hincrby("tx:stats:#{name}", "attempts", attempts)
    @redis.hincrbyfloat("tx:stats:#{name}", "total_duration", duration)
    @redis.hincrby("tx:stats:#{name}", result ? "success" : "failure", 1)

    result
  end
end

# Usage
tracker = TransactionTracker.new(redis)

result = tracker.execute("transfer") do
  redis.watch("balance") do
    balance = redis.get("balance").to_f

    if balance >= 100
      redis.multi do |tx|
        tx.decrby("balance", 100)
      end
    else
      redis.unwatch
      nil
    end
  end
end
```

## Next Steps

- [Lua Scripting](/guides/lua-scripting/) - Server-side scripting for complex atomic operations
- [Pipelines](/guides/pipelines/) - Batch commands for better performance
- [Pub/Sub](/guides/pubsub/) - Real-time messaging patterns
- [Connection Pools](/guides/connection-pools/) - Thread-safe connection management

## Additional Resources

- [Redis Transactions](https://redis.io/docs/manual/transactions/) - Official Redis documentation
- [MULTI/EXEC Commands](https://redis.io/commands/?group=transactions) - Command reference
- [Optimistic Locking](https://redis.io/docs/manual/transactions/#optimistic-locking-using-check-and-set) - WATCH pattern details


