---
layout: default
title: Distributed Locks
parent: Guides
nav_order: 10
---

# Distributed Locks

This guide covers distributed locks in redis-ruby, enabling safe coordination of access to shared resources across multiple processes and servers using the RR::Lock implementation.

## Table of Contents

- [What are Distributed Locks](#what-are-distributed-locks)
- [Why Use Distributed Locks](#why-use-distributed-locks)
- [Basic Lock Usage](#basic-lock-usage)
- [Lock Options](#lock-options)
- [Automatic Lock Renewal](#automatic-lock-renewal)
- [Lock Extension](#lock-extension)
- [Error Handling](#error-handling)
- [Redlock Algorithm](#redlock-algorithm)
- [Best Practices](#best-practices)
- [Common Use Cases](#common-use-cases)
- [Comparison with Other Approaches](#comparison-with-other-approaches)

## What are Distributed Locks

A distributed lock is a mechanism that provides mutual exclusion across multiple processes or servers. Unlike local locks (like Ruby's Mutex), distributed locks work across different machines, ensuring only one process can access a shared resource at a time.

### Key Characteristics

```ruby
# Local lock - only works within a single process
mutex = Mutex.new
mutex.synchronize do
  # Only one thread in THIS process can execute
end

# Distributed lock - works across multiple processes/servers
lock = RR::Lock.new(redis, "resource:1")
lock.synchronize do
  # Only one process ANYWHERE can execute
end
```

### How It Works

1. **Acquire**: Process attempts to set a key with a unique token
2. **Ownership**: Only the process with the matching token owns the lock
3. **Expiration**: Lock automatically expires after TTL to prevent deadlocks
4. **Release**: Lock is deleted only if the process still owns it

## Why Use Distributed Locks

Distributed locks solve critical coordination problems in distributed systems:

### Preventing Race Conditions

```ruby
# ❌ Without lock: Race condition
balance = redis.get("account:123:balance").to_i
if balance >= 100
  # Another process could withdraw here!
  redis.decrby("account:123:balance", 100)
end

# ✅ With lock: Safe
lock = RR::Lock.new(redis, "account:123")
lock.synchronize do
  balance = redis.get("account:123:balance").to_i
  if balance >= 100
    redis.decrby("account:123:balance", 100)
  end
end
```

### Ensuring Single Execution

```ruby
# Ensure only one worker processes a job
lock = RR::Lock.new(redis, "job:#{job_id}")
if lock.acquire(blocking: false)
  begin
    process_job(job_id)
  ensure
    lock.release
  end
else
  # Another worker is already processing this job
  puts "Job already being processed"
end
```

### Resource Coordination

```ruby
# Coordinate access to external API with rate limits
lock = RR::Lock.new(redis, "api:external-service")
lock.synchronize do
  # Only one process calls the API at a time
  response = ExternalAPI.call(params)
end
```

## Basic Lock Usage

### Simple Acquire and Release

```ruby
require "redis_ruby"  # Native RR API

redis = RR.new(host: "localhost")
lock = RR::Lock.new(redis, "my-resource")

# Acquire the lock
if lock.acquire
  begin
    # Critical section - only one process executes this
    puts "Lock acquired, doing work..."
    sleep 2
  ensure
    # Always release the lock
    lock.release
  end
else
  puts "Could not acquire lock"
end
```

### Block Syntax (Recommended)

The `synchronize` method automatically handles acquisition and release:

```ruby
lock = RR::Lock.new(redis, "my-resource")

lock.synchronize do
  # Lock is automatically acquired before block
  puts "Doing critical work..."
  # Lock is automatically released after block
end
```

### Non-Blocking Acquisition

```ruby
lock = RR::Lock.new(redis, "resource")

# Try to acquire, return immediately if unavailable
if lock.acquire(blocking: false)
  begin
    puts "Got the lock!"
  ensure
    lock.release
  end
else
  puts "Lock is held by another process"
end
```

### Blocking with Timeout

```ruby
lock = RR::Lock.new(redis, "resource")

# Wait up to 5 seconds for the lock
if lock.acquire(blocking: true, blocking_timeout: 5)
  begin
    puts "Acquired lock within 5 seconds"
  ensure
    lock.release
  end
else
  puts "Could not acquire lock within 5 seconds"
end
```

### Using synchronize with Options

```ruby
lock = RR::Lock.new(redis, "resource")

begin
  lock.synchronize(blocking: true, blocking_timeout: 10) do
    # Wait up to 10 seconds for lock
    puts "Got the lock, doing work..."
  end
rescue RR::Lock::LockAcquireError
  puts "Failed to acquire lock within timeout"
end
```

## Lock Options

### Timeout (TTL)

The timeout determines how long the lock is held before automatic expiration:

```ruby
# Lock expires after 10 seconds (default)
lock = RR::Lock.new(redis, "resource")

# Lock expires after 30 seconds
lock = RR::Lock.new(redis, "resource", timeout: 30)

# Short-lived lock (1 second)
lock = RR::Lock.new(redis, "quick-task", timeout: 1)
```

**Choosing the right timeout:**
- Too short: Lock may expire before work completes
- Too long: Delays recovery if process crashes
- Rule of thumb: 2-3x expected execution time

### Sleep Interval

Controls polling frequency when waiting for a lock:

```ruby
# Check every 100ms (default)
lock = RR::Lock.new(redis, "resource")

# Check every 10ms (more responsive, more Redis load)
lock = RR::Lock.new(redis, "resource", sleep: 0.01)

# Check every 500ms (less responsive, less Redis load)
lock = RR::Lock.new(redis, "resource", sleep: 0.5)
```

### Thread-Local Tokens

By default, locks use thread-local token storage for thread safety:

```ruby
# Thread-local tokens (default, thread-safe)
lock = RR::Lock.new(redis, "resource", thread_local: true)

# Instance tokens (not thread-safe, but simpler)
lock = RR::Lock.new(redis, "resource", thread_local: false)
```

### Complete Configuration Example

```ruby
lock = RR::Lock.new(
  redis,
  "critical-resource",
  timeout: 30,           # Lock expires after 30 seconds
  sleep: 0.1,            # Poll every 100ms when waiting
  thread_local: true     # Use thread-local token storage
)

lock.synchronize(blocking: true, blocking_timeout: 10) do
  # Wait up to 10 seconds to acquire lock
  # Lock held for up to 30 seconds
  perform_critical_work
end
```

## Automatic Lock Renewal

For long-running operations, you can periodically renew the lock to prevent expiration:

### Manual Renewal with reacquire

```ruby
lock = RR::Lock.new(redis, "long-task", timeout: 10)

lock.synchronize do
  # Do some work (5 seconds)
  process_batch_1

  # Renew the lock (reset TTL to 10 seconds)
  lock.reacquire

  # Do more work (5 seconds)
  process_batch_2

  # Renew again
  lock.reacquire

  # Final work
  process_batch_3
end
```

### Automatic Renewal with Background Thread

```ruby
def with_auto_renewal(lock, interval: 5)
  renewal_thread = Thread.new do
    loop do
      sleep interval
      break unless lock.owned?
      lock.reacquire
    end
  end

  begin
    yield
  ensure
    renewal_thread.kill
  end
end

# Usage
lock = RR::Lock.new(redis, "long-task", timeout: 10)
lock.synchronize do
  with_auto_renewal(lock, interval: 5) do
    # Lock is automatically renewed every 5 seconds
    very_long_running_task
  end
end
```

### Renewal Helper Class

```ruby
class AutoRenewingLock
  def initialize(redis, name, timeout: 10, renewal_interval: nil)
    @lock = RR::Lock.new(redis, name, timeout: timeout)
    @renewal_interval = renewal_interval || (timeout * 0.5)
    @renewal_thread = nil
  end

  def synchronize(blocking: true, blocking_timeout: nil)
    @lock.acquire(blocking: blocking, blocking_timeout: blocking_timeout)
    start_renewal

    begin
      yield
    ensure
      stop_renewal
      @lock.release
    end
  end

  private

  def start_renewal
    @renewal_thread = Thread.new do
      loop do
        sleep @renewal_interval
        break unless @lock.owned?
        @lock.reacquire
      end
    end
  end

  def stop_renewal
    @renewal_thread&.kill
    @renewal_thread = nil
  end
end

# Usage
lock = AutoRenewingLock.new(redis, "task", timeout: 10)
lock.synchronize do
  # Lock automatically renewed every 5 seconds
  process_large_dataset
end
```

## Lock Extension

Extend the lock's TTL without resetting it completely:

### Basic Extension

```ruby
lock = RR::Lock.new(redis, "resource", timeout: 10)

lock.synchronize do
  # Do some work
  process_data

  # Need more time - add 15 seconds to TTL
  lock.extend(additional_time: 15)

  # Continue working
  process_more_data
end
```

### Replace TTL

```ruby
lock = RR::Lock.new(redis, "resource", timeout: 10)

lock.synchronize do
  # Initial work
  quick_task

  # Replace TTL with 30 seconds (not adding to current TTL)
  lock.extend(additional_time: 30, replace_ttl: true)

  # Now have 30 seconds for longer task
  longer_task
end
```

### Conditional Extension

```ruby
lock = RR::Lock.new(redis, "resource", timeout: 10)

lock.synchronize do
  items.each do |item|
    process_item(item)

    # Extend if TTL is getting low
    if lock.ttl && lock.ttl < 3
      lock.extend(additional_time: 10)
    end
  end
end
```

### Checking Lock Status

```ruby
lock = RR::Lock.new(redis, "resource")

lock.synchronize do
  # Check if we own the lock
  puts "Owned: #{lock.owned?}"  # => true

  # Check remaining TTL
  puts "TTL: #{lock.ttl} seconds"  # => 9.8

  # Check if lock exists (owned by anyone)
  puts "Locked: #{lock.locked?}"  # => true
end
```

## Error Handling

### Handling Acquisition Failures

```ruby
lock = RR::Lock.new(redis, "resource")

begin
  lock.synchronize(blocking: false) do
    # This raises if lock cannot be acquired
    perform_work
  end
rescue RR::Lock::LockAcquireError => e
  puts "Could not acquire lock: #{e.message}"
  # Handle gracefully - retry, skip, or queue for later
end
```

### Handling Lock Not Owned Errors

```ruby
lock = RR::Lock.new(redis, "resource")

lock.acquire

begin
  # Lock might expire during long operation
  sleep 15  # Longer than default 10s timeout

  # This will raise LockNotOwnedError
  lock.extend(additional_time: 10)
rescue RR::Lock::LockNotOwnedError => e
  puts "Lost ownership of lock: #{e.message}"
  # Lock expired or was released by another process
end
```

### Safe Lock Operations

```ruby
def safe_lock_operation(redis, resource_name)
  lock = RR::Lock.new(redis, resource_name, timeout: 30)

  begin
    lock.synchronize(blocking: true, blocking_timeout: 5) do
      yield
    end
  rescue RR::Lock::LockAcquireError => e
    # Could not acquire lock
    Rails.logger.warn("Failed to acquire lock for #{resource_name}: #{e.message}")
    false
  rescue RR::Lock::LockNotOwnedError => e
    # Lost lock ownership during operation
    Rails.logger.error("Lost lock ownership for #{resource_name}: #{e.message}")
    false
  rescue StandardError => e
    # Other errors during critical section
    Rails.logger.error("Error in critical section: #{e.message}")
    raise
  end
end

# Usage
safe_lock_operation(redis, "payment:#{order_id}") do
  process_payment(order_id)
end
```

### Retry Logic

```ruby
def with_lock_retry(redis, resource_name, max_attempts: 3, retry_delay: 1)
  lock = RR::Lock.new(redis, resource_name)
  attempts = 0

  begin
    attempts += 1
    lock.synchronize(blocking: true, blocking_timeout: 5) do
      yield
    end
  rescue RR::Lock::LockAcquireError => e
    if attempts < max_attempts
      sleep retry_delay * attempts  # Exponential backoff
      retry
    else
      raise "Failed to acquire lock after #{max_attempts} attempts"
    end
  end
end

# Usage
with_lock_retry(redis, "inventory:#{product_id}") do
  update_inventory(product_id)
end
```

## Redlock Algorithm

The Redlock algorithm provides stronger guarantees by using multiple Redis instances:

### Basic Redlock Concept

```ruby
# Single Redis instance (simple but less reliable)
lock = RR::Lock.new(redis, "resource")

# Redlock with multiple instances (more reliable)
# Note: redis-ruby doesn't include Redlock by default
# This is a conceptual example
class Redlock
  def initialize(redis_instances)
    @instances = redis_instances
    @quorum = (redis_instances.size / 2.0).ceil
  end

  def lock(resource, ttl: 10)
    token = SecureRandom.uuid
    start_time = Time.now

    # Try to acquire lock on all instances
    acquired = @instances.count do |redis|
      lock = RR::Lock.new(redis, resource, timeout: ttl)
      lock.acquire(blocking: false, token: token)
    end

    # Check if we got quorum
    elapsed = Time.now - start_time
    validity_time = ttl - elapsed - 0.1  # Drift compensation

    if acquired >= @quorum && validity_time > 0
      { token: token, validity: validity_time }
    else
      # Failed to get quorum, release acquired locks
      @instances.each do |redis|
        lock = RR::Lock.new(redis, resource)
        lock.release rescue nil
      end
      nil
    end
  end
end

# Usage with multiple Redis instances
redis1 = RR.new(host: "redis1.example.com")
redis2 = RR.new(host: "redis2.example.com")
redis3 = RR.new(host: "redis3.example.com")

redlock = Redlock.new([redis1, redis2, redis3])
if lock_info = redlock.lock("critical-resource", ttl: 30)
  begin
    # Critical section
    perform_critical_work
  ensure
    # Release on all instances
  end
end
```

### When to Use Redlock

**Use Redlock when:**
- Absolute correctness is critical (financial transactions, inventory)
- You can afford multiple Redis instances
- Network partitions are a concern
- Single point of failure is unacceptable

**Use single-instance locks when:**
- Performance is more important than absolute correctness
- Infrastructure is simple
- Occasional race conditions are acceptable
- Cost of multiple Redis instances is prohibitive

## Best Practices

### 1. Always Set Appropriate Timeouts

```ruby
# ❌ Bad: Timeout too short
lock = RR::Lock.new(redis, "resource", timeout: 1)
lock.synchronize do
  sleep 5  # Lock expires before work completes!
end

# ✅ Good: Timeout covers expected duration + buffer
lock = RR::Lock.new(redis, "resource", timeout: 10)
lock.synchronize do
  process_data  # Expected to take 3-5 seconds
end
```

### 2. Use Block Syntax

```ruby
# ❌ Bad: Manual acquire/release (error-prone)
lock = RR::Lock.new(redis, "resource")
lock.acquire
process_data
lock.release  # Might not execute if error occurs!

# ✅ Good: Block syntax ensures release
lock = RR::Lock.new(redis, "resource")
lock.synchronize do
  process_data
end  # Always releases, even on error
```

### 3. Use Descriptive Lock Names

```ruby
# ❌ Bad: Generic names
lock = RR::Lock.new(redis, "lock1")

# ✅ Good: Descriptive, namespaced names
lock = RR::Lock.new(redis, "order:#{order_id}:payment")
lock = RR::Lock.new(redis, "inventory:product:#{product_id}")
lock = RR::Lock.new(redis, "user:#{user_id}:profile:update")
```

### 4. Keep Critical Sections Small

```ruby
# ❌ Bad: Large critical section
lock = RR::Lock.new(redis, "resource")
lock.synchronize do
  data = fetch_from_database  # Slow
  processed = process_data(data)  # Slow
  save_to_database(processed)  # Slow
  send_notifications(processed)  # Slow
end

# ✅ Good: Minimal critical section
data = fetch_from_database
processed = process_data(data)

lock = RR::Lock.new(redis, "resource")
lock.synchronize do
  # Only lock for the critical update
  save_to_database(processed)
end

send_notifications(processed)
```

### 5. Handle Lock Acquisition Failures

```ruby
# ❌ Bad: Assume lock is always acquired
lock = RR::Lock.new(redis, "resource")
lock.synchronize do
  process_data
end

# ✅ Good: Handle acquisition failure
lock = RR::Lock.new(redis, "resource")
begin
  lock.synchronize(blocking: true, blocking_timeout: 5) do
    process_data
  end
rescue RR::Lock::LockAcquireError
  # Queue for retry or handle gracefully
  enqueue_for_later_processing
end
```

### 6. Monitor Lock Metrics

```ruby
class MonitoredLock
  def initialize(redis, name, **options)
    @lock = RR::Lock.new(redis, name, **options)
    @redis = redis
    @name = name
  end

  def synchronize(**options)
    start_time = Time.now
    acquired = false

    begin
      @lock.synchronize(**options) do
        acquired = true
        @redis.hincrby("lock:stats:#{@name}", "acquired", 1)
        yield
      end
    rescue RR::Lock::LockAcquireError
      @redis.hincrby("lock:stats:#{@name}", "failed", 1)
      raise
    ensure
      duration = Time.now - start_time
      @redis.hincrbyfloat("lock:stats:#{@name}", "total_time", duration)

      if acquired
        @redis.hincrbyfloat("lock:stats:#{@name}", "held_time", duration)
      end
    end
  end
end

# Usage
lock = MonitoredLock.new(redis, "critical-resource", timeout: 30)
lock.synchronize do
  perform_work
end

# View stats
stats = redis.hgetall("lock:stats:critical-resource")
# => {"acquired"=>"150", "failed"=>"5", "total_time"=>"45.2", "held_time"=>"42.1"}
```

### 7. Use Non-Blocking for Optional Operations

```ruby
# ✅ Good: Skip if lock unavailable
lock = RR::Lock.new(redis, "cache:refresh")

if lock.acquire(blocking: false)
  begin
    # Nice to have, but not critical
    refresh_cache
  ensure
    lock.release
  end
else
  # Another process is refreshing, skip
  puts "Cache refresh already in progress"
end
```

## Common Use Cases

### Use Case 1: Job Processing

Ensure only one worker processes a job:

```ruby
class JobProcessor
  def initialize(redis)
    @redis = redis
  end

  def process(job_id)
    lock = RR::Lock.new(@redis, "job:#{job_id}", timeout: 300)

    begin
      lock.synchronize(blocking: false) do
        # Fetch job details
        job = fetch_job(job_id)

        # Process the job
        result = perform_job(job)

        # Mark as complete
        mark_complete(job_id, result)
      end
    rescue RR::Lock::LockAcquireError
      # Another worker is processing this job
      Rails.logger.info("Job #{job_id} already being processed")
    end
  end

  private

  def fetch_job(job_id)
    # Fetch from database
  end

  def perform_job(job)
    # Execute job logic
  end

  def mark_complete(job_id, result)
    # Update database
  end
end

# Usage
processor = JobProcessor.new(redis)
processor.process(12345)
```

### Use Case 2: Resource Allocation

Allocate limited resources safely:

```ruby
class ResourceAllocator
  def initialize(redis)
    @redis = redis
  end

  def allocate(resource_type, user_id)
    lock = RR::Lock.new(@redis, "allocate:#{resource_type}", timeout: 10)

    lock.synchronize do
      # Check available resources
      available = @redis.get("resources:#{resource_type}:available").to_i

      if available > 0
        # Allocate resource
        @redis.decr("resources:#{resource_type}:available")
        @redis.sadd("resources:#{resource_type}:allocated", user_id)

        { success: true, remaining: available - 1 }
      else
        { success: false, error: "No resources available" }
      end
    end
  end

  def release(resource_type, user_id)
    lock = RR::Lock.new(@redis, "allocate:#{resource_type}", timeout: 10)

    lock.synchronize do
      if @redis.sismember("resources:#{resource_type}:allocated", user_id)
        @redis.incr("resources:#{resource_type}:available")
        @redis.srem("resources:#{resource_type}:allocated", user_id)
        true
      else
        false
      end
    end
  end
end

# Usage
allocator = ResourceAllocator.new(redis)

# Allocate a server
result = allocator.allocate("server", user_id: 123)
if result[:success]
  puts "Server allocated, #{result[:remaining]} remaining"
else
  puts "Allocation failed: #{result[:error]}"
end

# Release when done
allocator.release("server", user_id: 123)
```

### Use Case 3: Scheduled Task Coordination

Ensure scheduled tasks run only once across multiple servers:

```ruby
class ScheduledTask
  def initialize(redis, task_name)
    @redis = redis
    @task_name = task_name
  end

  def run_if_due
    lock = RR::Lock.new(@redis, "scheduled:#{@task_name}", timeout: 3600)

    # Try to acquire lock (non-blocking)
    if lock.acquire(blocking: false)
      begin
        # Check if task is due
        last_run = @redis.get("scheduled:#{@task_name}:last_run").to_i
        now = Time.now.to_i

        if now - last_run >= interval
          # Run the task
          execute_task

          # Update last run time
          @redis.set("scheduled:#{@task_name}:last_run", now)
        end
      ensure
        lock.release
      end
    else
      # Another server is running the task
      Rails.logger.debug("Task #{@task_name} already running on another server")
    end
  end

  private

  def interval
    3600  # Run every hour
  end

  def execute_task
    # Task implementation
  end
end

# Usage in cron job (runs on all servers)
task = ScheduledTask.new(redis, "daily-report")
task.run_if_due  # Only executes on one server
```

### Use Case 4: Inventory Management

Prevent overselling with distributed locks:

```ruby
class InventoryManager
  def initialize(redis)
    @redis = redis
  end

  def reserve(product_id, quantity)
    lock = RR::Lock.new(@redis, "inventory:#{product_id}", timeout: 30)

    lock.synchronize do
      # Get current stock
      stock = @redis.get("product:#{product_id}:stock").to_i

      if stock >= quantity
        # Reserve inventory
        new_stock = stock - quantity
        @redis.set("product:#{product_id}:stock", new_stock)
        @redis.incrby("product:#{product_id}:reserved", quantity)

        # Create reservation
        reservation_id = SecureRandom.uuid
        @redis.hset(
          "reservation:#{reservation_id}",
          "product_id", product_id,
          "quantity", quantity,
          "created_at", Time.now.to_i
        )
        @redis.expire("reservation:#{reservation_id}", 900)  # 15 min expiry

        { success: true, reservation_id: reservation_id, remaining: new_stock }
      else
        { success: false, error: "Insufficient stock", available: stock }
      end
    end
  end

  def confirm(reservation_id)
    reservation = @redis.hgetall("reservation:#{reservation_id}")
    return false if reservation.empty?

    product_id = reservation["product_id"]
    quantity = reservation["quantity"].to_i

    lock = RR::Lock.new(@redis, "inventory:#{product_id}", timeout: 30)

    lock.synchronize do
      @redis.decrby("product:#{product_id}:reserved", quantity)
      @redis.del("reservation:#{reservation_id}")
      true
    end
  end

  def cancel(reservation_id)
    reservation = @redis.hgetall("reservation:#{reservation_id}")
    return false if reservation.empty?

    product_id = reservation["product_id"]
    quantity = reservation["quantity"].to_i

    lock = RR::Lock.new(@redis, "inventory:#{product_id}", timeout: 30)

    lock.synchronize do
      # Return stock
      @redis.incrby("product:#{product_id}:stock", quantity)
      @redis.decrby("product:#{product_id}:reserved", quantity)
      @redis.del("reservation:#{reservation_id}")
      true
    end
  end
end

# Usage
inventory = InventoryManager.new(redis)

# Reserve inventory
result = inventory.reserve(product_id: 123, quantity: 2)
if result[:success]
  reservation_id = result[:reservation_id]

  # Later: confirm or cancel
  inventory.confirm(reservation_id)
  # or
  inventory.cancel(reservation_id)
end
```

### Use Case 5: Rate Limiting with Locks

Implement distributed rate limiting:

```ruby
class DistributedRateLimiter
  def initialize(redis)
    @redis = redis
  end

  def allow?(key, limit:, window:)
    lock = RR::Lock.new(@redis, "ratelimit:lock:#{key}", timeout: 1)

    lock.synchronize(blocking: true, blocking_timeout: 0.5) do
      current_window = Time.now.to_i / window
      rate_key = "ratelimit:#{key}:#{current_window}"

      # Get current count
      count = @redis.get(rate_key).to_i

      if count < limit
        # Increment and set expiry
        @redis.incr(rate_key)
        @redis.expire(rate_key, window * 2)

        { allowed: true, remaining: limit - count - 1 }
      else
        { allowed: false, remaining: 0, retry_after: window }
      end
    end
  rescue RR::Lock::LockAcquireError
    # Couldn't acquire lock quickly, deny request
    { allowed: false, remaining: 0, error: "Rate limiter busy" }
  end
end

# Usage
limiter = DistributedRateLimiter.new(redis)

result = limiter.allow?("user:123", limit: 100, window: 60)
if result[:allowed]
  # Process request
  puts "Request allowed, #{result[:remaining]} remaining"
else
  puts "Rate limit exceeded, retry after #{result[:retry_after]}s"
end
```

### Use Case 6: Cache Stampede Prevention

Prevent multiple processes from regenerating cache simultaneously:

```ruby
class CacheManager
  def initialize(redis)
    @redis = redis
  end

  def fetch(key, ttl: 3600, lock_timeout: 30)
    # Try to get from cache
    cached = @redis.get("cache:#{key}")
    return cached if cached

    # Cache miss - use lock to prevent stampede
    lock = RR::Lock.new(@redis, "cache:generate:#{key}", timeout: lock_timeout)

    begin
      lock.synchronize(blocking: true, blocking_timeout: 5) do
        # Double-check cache (another process might have generated it)
        cached = @redis.get("cache:#{key}")
        return cached if cached

        # Generate value
        value = yield

        # Store in cache
        @redis.set("cache:#{key}", value, ex: ttl)

        value
      end
    rescue RR::Lock::LockAcquireError
      # Another process is generating, wait and retry
      sleep 0.1
      @redis.get("cache:#{key}") || yield
    end
  end
end

# Usage
cache = CacheManager.new(redis)

# Multiple processes call this simultaneously
result = cache.fetch("expensive:calculation:#{id}", ttl: 3600) do
  # Only one process executes this expensive operation
  perform_expensive_calculation(id)
end
```

## Comparison with Other Approaches

### Distributed Locks vs. Transactions

```ruby
# Transaction (WATCH/MULTI/EXEC)
# ✅ Atomic operations
# ✅ Built into Redis
# ❌ Limited to single Redis instance
# ❌ Requires retry logic for conflicts

redis.watch("counter") do
  current = redis.get("counter").to_i
  redis.multi do |tx|
    tx.set("counter", current + 1)
  end
end

# Distributed Lock
# ✅ Works across processes/servers
# ✅ Explicit ownership
# ✅ Automatic expiration
# ❌ Additional complexity

lock = RR::Lock.new(redis, "counter")
lock.synchronize do
  current = redis.get("counter").to_i
  redis.set("counter", current + 1)
end
```

### Distributed Locks vs. Lua Scripts

```ruby
# Lua Script
# ✅ Atomic execution
# ✅ Server-side logic
# ✅ Single round-trip
# ❌ Limited to single Redis instance
# ❌ Complex logic harder to maintain

script = <<~LUA
  local current = redis.call('GET', KEYS[1])
  if tonumber(current) < tonumber(ARGV[1]) then
    redis.call('SET', KEYS[1], ARGV[1])
    return 1
  end
  return 0
LUA

redis.eval(script, keys: ["counter"], argv: [100])

# Distributed Lock
# ✅ Ruby logic (easier to maintain)
# ✅ Works across processes
# ❌ Multiple round-trips
# ❌ Not atomic without transactions

lock = RR::Lock.new(redis, "counter")
lock.synchronize do
  current = redis.get("counter").to_i
  redis.set("counter", 100) if current < 100
end
```

### Distributed Locks vs. Database Locks

```ruby
# Database Lock (PostgreSQL)
# ✅ ACID guarantees
# ✅ Integrated with transactions
# ❌ Database-specific
# ❌ Can cause connection pool exhaustion
# ❌ Slower than Redis

ActiveRecord::Base.transaction do
  record = Record.lock.find(id)
  record.update(status: "processing")
end

# Distributed Lock (Redis)
# ✅ Fast (in-memory)
# ✅ Independent of database
# ✅ Automatic expiration
# ❌ No ACID guarantees
# ❌ Requires separate infrastructure

lock = RR::Lock.new(redis, "record:#{id}")
lock.synchronize do
  record = Record.find(id)
  record.update(status: "processing")
end
```

### Distributed Locks vs. Message Queues

```ruby
# Message Queue (Sidekiq)
# ✅ Natural serialization
# ✅ Retry logic built-in
# ✅ Job persistence
# ❌ Async only
# ❌ More infrastructure

class ProcessJob
  include Sidekiq::Worker
  sidekiq_options lock: :until_executed

  def perform(resource_id)
    process_resource(resource_id)
  end
end

# Distributed Lock
# ✅ Synchronous or async
# ✅ Fine-grained control
# ✅ Minimal infrastructure
# ❌ Manual retry logic
# ❌ No persistence

lock = RR::Lock.new(redis, "resource:#{resource_id}")
lock.synchronize do
  process_resource(resource_id)
end
```

### When to Use Each Approach

| Approach | Best For | Avoid When |
|----------|----------|------------|
| **Distributed Locks** | Cross-process coordination, resource allocation, preventing duplicate work | Need ACID guarantees, complex transactions |
| **Transactions (WATCH/MULTI)** | Atomic updates, optimistic locking, single Redis instance | Multiple Redis instances, long operations |
| **Lua Scripts** | Complex atomic operations, server-side logic | Need Ruby logic, debugging complexity |
| **Database Locks** | ACID requirements, integrated with DB transactions | High throughput, independent of database |
| **Message Queues** | Async processing, job persistence, retry logic | Synchronous operations, immediate results |

## Advanced Patterns

### Lock with Fallback

```ruby
class LockWithFallback
  def initialize(redis, name, timeout: 10)
    @redis = redis
    @name = name
    @timeout = timeout
  end

  def execute(fallback_value: nil)
    lock = RR::Lock.new(@redis, @name, timeout: @timeout)

    if lock.acquire(blocking: false)
      begin
        yield
      ensure
        lock.release
      end
    else
      # Lock unavailable, return fallback
      fallback_value
    end
  end
end

# Usage
lock_with_fallback = LockWithFallback.new(redis, "cache:refresh")

result = lock_with_fallback.execute(fallback_value: cached_value) do
  # Refresh cache
  fetch_fresh_data
end
```

### Hierarchical Locks

```ruby
class HierarchicalLock
  def initialize(redis, *resources, timeout: 10)
    @redis = redis
    @resources = resources.sort  # Always acquire in same order to prevent deadlock
    @timeout = timeout
    @locks = []
  end

  def synchronize
    acquire_all

    begin
      yield
    ensure
      release_all
    end
  end

  private

  def acquire_all
    @resources.each do |resource|
      lock = RR::Lock.new(@redis, resource, timeout: @timeout)

      unless lock.acquire(blocking: true, blocking_timeout: 5)
        # Failed to acquire, release all and raise
        release_all
        raise RR::Lock::LockAcquireError, "Failed to acquire lock: #{resource}"
      end

      @locks << lock
    end
  end

  def release_all
    @locks.reverse.each(&:release)
    @locks.clear
  end
end

# Usage - transfer between accounts (prevents deadlock)
lock = HierarchicalLock.new(redis, "account:#{from_id}", "account:#{to_id}")
lock.synchronize do
  # Both accounts locked in consistent order
  transfer_funds(from_id, to_id, amount)
end
```

### Lock with Metrics and Alerting

```ruby
class MonitoredLock
  def initialize(redis, name, timeout: 10, alert_threshold: 0.8)
    @redis = redis
    @name = name
    @timeout = timeout
    @alert_threshold = alert_threshold
  end

  def synchronize
    lock = RR::Lock.new(@redis, @name, timeout: @timeout)
    start_time = Time.now

    begin
      lock.synchronize do
        yield

        # Check if we're close to timeout
        elapsed = Time.now - start_time
        if elapsed > (@timeout * @alert_threshold)
          alert_slow_lock(elapsed)
        end
      end
    rescue RR::Lock::LockAcquireError => e
      record_failure
      raise
    end
  end

  private

  def alert_slow_lock(duration)
    # Send alert - lock held for too long
    Rails.logger.warn(
      "Lock #{@name} held for #{duration}s (timeout: #{@timeout}s)"
    )

    # Increment metric
    @redis.hincrby("lock:slow:#{@name}", "count", 1)
    @redis.hset("lock:slow:#{@name}", "last_duration", duration)
  end

  def record_failure
    @redis.hincrby("lock:failures:#{@name}", "count", 1)
    @redis.hset("lock:failures:#{@name}", "last_failure", Time.now.to_i)
  end
end

# Usage
lock = MonitoredLock.new(redis, "critical-operation", timeout: 30, alert_threshold: 0.8)
lock.synchronize do
  # Alerts if operation takes > 24 seconds (80% of 30s timeout)
  perform_operation
end
```

### Reentrant Lock

```ruby
class ReentrantLock
  def initialize(redis, name, timeout: 10)
    @redis = redis
    @name = name
    @timeout = timeout
    @lock = RR::Lock.new(redis, name, timeout: timeout)
    @depth = 0
  end

  def synchronize
    if @depth.zero?
      # First acquisition
      @lock.acquire(blocking: true)
    end

    @depth += 1

    begin
      yield
    ensure
      @depth -= 1

      if @depth.zero?
        # Last release
        @lock.release
      end
    end
  end
end

# Usage - can be called recursively
lock = ReentrantLock.new(redis, "resource")

def process_with_lock(lock, items)
  lock.synchronize do
    items.each do |item|
      if item.has_children?
        # Recursive call - lock is reentrant
        process_with_lock(lock, item.children)
      else
        process_item(item)
      end
    end
  end
end
```

## Troubleshooting

### Lock Not Released (Deadlock)

```ruby
# Problem: Process crashes before releasing lock
lock = RR::Lock.new(redis, "resource", timeout: 10)
lock.acquire
# Process crashes here - lock never released!

# Solution: Always use block syntax or ensure release
lock = RR::Lock.new(redis, "resource", timeout: 10)
lock.synchronize do
  # Lock automatically released even if exception occurs
  perform_work
end
```

### Lock Expires Too Soon

```ruby
# Problem: Operation takes longer than timeout
lock = RR::Lock.new(redis, "resource", timeout: 5)
lock.synchronize do
  sleep 10  # Lock expires after 5 seconds!
  # Lost ownership, another process can acquire
end

# Solution 1: Increase timeout
lock = RR::Lock.new(redis, "resource", timeout: 15)

# Solution 2: Use lock extension
lock = RR::Lock.new(redis, "resource", timeout: 10)
lock.synchronize do
  process_batch_1
  lock.extend(additional_time: 10)  # Add more time
  process_batch_2
end

# Solution 3: Use automatic renewal
lock = AutoRenewingLock.new(redis, "resource", timeout: 10)
lock.synchronize do
  # Lock automatically renewed every 5 seconds
  long_running_operation
end
```

### High Lock Contention

```ruby
# Problem: Many processes competing for same lock
100.times do
  Thread.new do
    lock = RR::Lock.new(redis, "resource")
    lock.synchronize do
      process_data
    end
  end
end

# Solution 1: Reduce critical section size
lock = RR::Lock.new(redis, "resource")
data = prepare_data  # Outside lock

lock.synchronize do
  # Minimal critical section
  save_data(data)
end

# Solution 2: Use sharding
shard = id % 10
lock = RR::Lock.new(redis, "resource:shard:#{shard}")

# Solution 3: Use queue instead of lock
# Push to queue, single worker processes
redis.lpush("work_queue", work_item)
```

### Debugging Lock Issues

```ruby
# Check if lock exists
lock = RR::Lock.new(redis, "resource")
puts "Locked: #{lock.locked?}"

# Check remaining TTL
puts "TTL: #{lock.ttl} seconds"

# Check ownership
lock.acquire
puts "Owned: #{lock.owned?}"

# View all locks
keys = redis.keys("lock:*")
keys.each do |key|
  ttl = redis.ttl(key)
  value = redis.get(key)
  puts "#{key}: TTL=#{ttl}s, Token=#{value}"
end

# Force release (use with caution!)
redis.del("lock:resource")
```

## Performance Considerations

### Lock Acquisition Overhead

```ruby
require "benchmark"

redis = RR.new(host: "localhost")

# Measure lock overhead
time_without_lock = Benchmark.realtime do
  1000.times { redis.incr("counter") }
end

time_with_lock = Benchmark.realtime do
  1000.times do
    lock = RR::Lock.new(redis, "counter")
    lock.synchronize { redis.incr("counter") }
  end
end

puts "Without lock: #{time_without_lock.round(3)}s"
puts "With lock: #{time_with_lock.round(3)}s"
puts "Overhead: #{((time_with_lock / time_without_lock - 1) * 100).round(1)}%"

# Output:
# Without lock: 0.052s
# With lock: 0.156s
# Overhead: 200%
```

### Optimizing Lock Usage

```ruby
# ❌ Bad: Lock per operation
1000.times do |i|
  lock = RR::Lock.new(redis, "batch")
  lock.synchronize do
    redis.lpush("queue", "item:#{i}")
  end
end

# ✅ Good: Single lock for batch
lock = RR::Lock.new(redis, "batch")
lock.synchronize do
  1000.times do |i|
    redis.lpush("queue", "item:#{i}")
  end
end

# ✅ Better: Use pipeline inside lock
lock = RR::Lock.new(redis, "batch")
lock.synchronize do
  redis.pipelined do |pipe|
    1000.times do |i|
      pipe.lpush("queue", "item:#{i}")
    end
  end
end
```

## Next Steps

- [Transactions](/guides/transactions/) - Atomic operations with MULTI/EXEC
- [Lua Scripting](/guides/lua-scripting/) - Server-side atomic operations
- [Connection Pools](/guides/connection-pools/) - Thread-safe connection management
- [Pub/Sub](/guides/pubsub/) - Real-time messaging patterns

## Additional Resources

- [Redis SET Command](https://redis.io/commands/set/) - NX and PX options used for locks
- [Distributed Locks with Redis](https://redis.io/docs/manual/patterns/distributed-locks/) - Official Redis documentation
- [Redlock Algorithm](https://redis.io/docs/manual/patterns/distributed-locks/#the-redlock-algorithm) - Multi-instance locking
- [Martin Kleppmann's Analysis](https://martin.kleppmann.com/2016/02/08/how-to-do-distributed-locking.html) - Critical analysis of distributed locks

