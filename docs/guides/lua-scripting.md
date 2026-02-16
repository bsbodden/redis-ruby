---
layout: default
title: Lua Scripting
parent: Guides
nav_order: 6
---

# Lua Scripting

This guide covers Redis Lua scripting in redis-ruby, enabling you to execute complex atomic operations on the server side, implement custom commands, and achieve maximum performance for data-intensive operations.

## Table of Contents

- [Why Use Lua Scripts](#why-use-lua-scripts)
- [EVAL vs EVALSHA](#eval-vs-evalsha)
- [Script Caching](#script-caching)
- [Passing Arguments](#passing-arguments)
- [Return Values](#return-values)
- [Atomic Operations](#atomic-operations)
- [Common Patterns](#common-patterns)
- [Best Practices](#best-practices)
- [Advanced Techniques](#advanced-techniques)

## Why Use Lua Scripts

Lua scripts in Redis provide several key benefits:

### Atomicity

Scripts execute atomically - no other commands run during script execution:

```ruby
# Without Lua: Race condition possible
balance = redis.get("balance").to_i
if balance >= 100
  # Another client could modify balance here!
  redis.decrby("balance", 100)
end

# With Lua: Atomic execution
script = <<~LUA
  local balance = tonumber(redis.call('GET', KEYS[1]))
  if balance >= tonumber(ARGV[1]) then
    redis.call('DECRBY', KEYS[1], ARGV[1])
    return 1
  else
    return 0
  end
LUA

result = redis.eval(script, 1, "balance", 100)
```

### Performance

Reduce network round-trips by executing logic on the server:

```ruby
# Without Lua: 3 round-trips
value1 = redis.get("key1")
value2 = redis.get("key2")
redis.set("sum", value1.to_i + value2.to_i)

# With Lua: 1 round-trip
script = <<~LUA
  local v1 = tonumber(redis.call('GET', KEYS[1]))
  local v2 = tonumber(redis.call('GET', KEYS[2]))
  redis.call('SET', KEYS[3], v1 + v2)
  return v1 + v2
LUA

result = redis.eval(script, 3, "key1", "key2", "sum")
```

### Complex Logic

Implement conditional logic and loops on the server:

```ruby
# Complex server-side logic
script = <<~LUA
  local items = redis.call('LRANGE', KEYS[1], 0, -1)
  local sum = 0
  local count = 0
  
  for i, item in ipairs(items) do
    local value = tonumber(item)
    if value > tonumber(ARGV[1]) then
      sum = sum + value
      count = count + 1
    end
  end
  
  return {sum, count}
LUA

result = redis.eval(script, 1, "numbers", 10)
# Returns [sum, count] of numbers > 10
```

### Reusability

Create custom commands for your application:

```ruby
# Register a reusable script
increment_if_exists = redis.register_script(<<~LUA)
  if redis.call('EXISTS', KEYS[1]) == 1 then
    return redis.call('INCR', KEYS[1])
  else
    return nil
  end
LUA

# Use like a custom command
result = increment_if_exists.call(keys: ["counter"])
```

## EVAL vs EVALSHA

### EVAL - Execute Script Directly

```ruby
# EVAL sends the full script every time
script = "return redis.call('GET', KEYS[1])"

result = redis.eval(script, 1, "mykey")
# Sends entire script to Redis
```

**Pros:**
- Simple to use
- No caching needed
- Good for one-off scripts

**Cons:**
- Sends full script every time
- Higher bandwidth usage
- Slower for repeated execution

### EVALSHA - Execute Cached Script

```ruby
# EVALSHA uses script hash (more efficient)
script = "return redis.call('GET', KEYS[1])"

# Load script and get SHA
sha = redis.script_load(script)
# => "a42059b356c875f0717db19a51f6aaa9161e77a2"

# Execute by SHA
result = redis.evalsha(sha, 1, "mykey")
# Only sends SHA, not full script
```

**Pros:**
- Faster execution
- Lower bandwidth
- Cached on server

**Cons:**
- Requires loading first
- Need to handle NOSCRIPT errors
- SHA management overhead

### Automatic Fallback

redis-ruby provides automatic EVALSHA/EVAL fallback:

```ruby
# Tries EVALSHA first, falls back to EVAL if not cached
result = redis.evalsha_or_eval(script, ["key1"], ["arg1"])

# Or use register_script for automatic handling
script_obj = redis.register_script(script)
result = script_obj.call(keys: ["key1"], args: ["arg1"])
```

## Script Caching

### Loading Scripts

```ruby
# Load script into Redis cache
script = <<~LUA
  return redis.call('INCR', KEYS[1])
LUA

sha = redis.script_load(script)
# => "c8b5e7e3b3e3e3e3e3e3e3e3e3e3e3e3e3e3e3e3"

# Execute cached script
result = redis.evalsha(sha, 1, "counter")
```

### Checking Script Existence

```ruby
# Check if scripts are cached
sha1 = redis.script_load("return 1")
sha2 = "0000000000000000000000000000000000000000"

exists = redis.script_exists(sha1, sha2)
# => [true, false]
```

### Flushing Script Cache

```ruby
# Clear all cached scripts
redis.script_flush

# Async flush (Redis 6.2+)
redis.script_flush(:async)
```

### Handling NOSCRIPT Errors

```ruby
# Manual error handling
begin
  result = redis.evalsha(sha, 1, "key")
rescue RR::CommandError => e
  if e.message.include?("NOSCRIPT")
    # Script not cached, use EVAL
    result = redis.eval(script, 1, "key")
  else
    raise
  end
end

# Or use automatic fallback
result = redis.evalsha_or_eval(script, ["key"])
```

## Passing Arguments

### KEYS and ARGV

Lua scripts receive two types of arguments:

- **KEYS**: Key names (for Redis Cluster routing)
- **ARGV**: Other arguments (values, options, etc.)

```ruby
script = <<~LUA
  -- KEYS[1], KEYS[2], ... are key names
  -- ARGV[1], ARGV[2], ... are other arguments
  
  local key1 = KEYS[1]
  local key2 = KEYS[2]
  local value = ARGV[1]
  local ttl = ARGV[2]
  
  redis.call('SET', key1, value)
  redis.call('EXPIRE', key1, ttl)
  return redis.call('GET', key1)
LUA

# eval(script, num_keys, key1, key2, ..., arg1, arg2, ...)
result = redis.eval(script, 2, "mykey", "otherkey", "myvalue", 3600)
```

### Why Separate KEYS and ARGV?

Redis Cluster uses KEYS to determine which node should execute the script:

```ruby
# ✅ Good: Keys in KEYS array
script = "return redis.call('GET', KEYS[1])"
redis.eval(script, 1, "user:123")  # Cluster can route correctly

# ❌ Bad: Keys in ARGV
script = "return redis.call('GET', ARGV[1])"
redis.eval(script, 0, "user:123")  # Cluster can't route!
```

### Passing Multiple Arguments

```ruby
script = <<~LUA
  local key = KEYS[1]
  local field1 = ARGV[1]
  local value1 = ARGV[2]
  local field2 = ARGV[3]
  local value2 = ARGV[4]

  redis.call('HSET', key, field1, value1, field2, value2)
  return redis.call('HGETALL', key)
LUA

result = redis.eval(script, 1, "user:123", "name", "Alice", "age", "30")
```

### Using register_script

```ruby
script = redis.register_script(<<~LUA)
  return redis.call('SET', KEYS[1], ARGV[1])
LUA

# Call with named parameters
result = script.call(keys: ["mykey"], args: ["myvalue"])

# Multiple keys and args
result = script.call(
  keys: ["key1", "key2"],
  args: ["value1", "value2", "value3"]
)
```

## Return Values

### Basic Types

```ruby
# Return number
script = "return 42"
result = redis.eval(script, 0)
# => 42

# Return string
script = "return 'hello'"
result = redis.eval(script, 0)
# => "hello"

# Return boolean (converted to 1/0)
script = "return true"
result = redis.eval(script, 0)
# => 1

# Return nil
script = "return nil"
result = redis.eval(script, 0)
# => nil
```

### Arrays

```ruby
# Return array
script = "return {1, 2, 3, 'four', 5}"
result = redis.eval(script, 0)
# => [1, 2, 3, "four", 5]

# Return nested arrays
script = "return {1, {2, 3}, {4, {5, 6}}}"
result = redis.eval(script, 0)
# => [1, [2, 3], [4, [5, 6]]]
```

### Redis Command Results

```ruby
# Return Redis command result
script = <<~LUA
  redis.call('SET', KEYS[1], ARGV[1])
  return redis.call('GET', KEYS[1])
LUA

result = redis.eval(script, 1, "mykey", "myvalue")
# => "myvalue"

# Return multiple command results
script = <<~LUA
  local v1 = redis.call('GET', KEYS[1])
  local v2 = redis.call('GET', KEYS[2])
  return {v1, v2}
LUA

result = redis.eval(script, 2, "key1", "key2")
# => ["value1", "value2"]
```

### Error Handling

```ruby
# Return error
script = <<~LUA
  if tonumber(ARGV[1]) < 0 then
    return redis.error_reply("Value must be positive")
  end
  return redis.call('SET', KEYS[1], ARGV[1])
LUA

begin
  redis.eval(script, 1, "key", -5)
rescue RR::CommandError => e
  puts e.message  # => "Value must be positive"
end
```

### Status Replies

```ruby
# Return status (like "OK")
script = <<~LUA
  redis.call('SET', KEYS[1], ARGV[1])
  return redis.status_reply("OK")
LUA

result = redis.eval(script, 1, "key", "value")
# => "OK"
```

## Atomic Operations

### Compare-and-Set

```ruby
# Atomic compare-and-set
cas_script = redis.register_script(<<~LUA)
  local current = redis.call('GET', KEYS[1])
  if current == ARGV[1] then
    redis.call('SET', KEYS[1], ARGV[2])
    return 1
  else
    return 0
  end
LUA

# Usage
success = cas_script.call(
  keys: ["status"],
  args: ["pending", "processing"]
)

if success == 1
  puts "Status updated"
else
  puts "Status was already changed"
end
```

### Increment with Maximum

```ruby
# Increment but don't exceed maximum
incr_max_script = redis.register_script(<<~LUA)
  local current = tonumber(redis.call('GET', KEYS[1]) or 0)
  local max = tonumber(ARGV[1])

  if current < max then
    return redis.call('INCR', KEYS[1])
  else
    return current
  end
LUA

result = incr_max_script.call(keys: ["counter"], args: [100])
```

### Conditional Delete

```ruby
# Delete only if value matches
delete_if_script = redis.register_script(<<~LUA)
  if redis.call('GET', KEYS[1]) == ARGV[1] then
    return redis.call('DEL', KEYS[1])
  else
    return 0
  end
LUA

deleted = delete_if_script.call(keys: ["lock"], args: ["my-token"])
```

### Rate Limiting

```ruby
# Sliding window rate limiter
rate_limit_script = redis.register_script(<<~LUA)
  local key = KEYS[1]
  local limit = tonumber(ARGV[1])
  local window = tonumber(ARGV[2])
  local now = tonumber(ARGV[3])

  -- Remove old entries
  redis.call('ZREMRANGEBYSCORE', key, 0, now - window)

  -- Count current entries
  local current = redis.call('ZCARD', key)

  if current < limit then
    -- Add new entry
    redis.call('ZADD', key, now, now)
    redis.call('EXPIRE', key, window)
    return {1, limit - current - 1}
  else
    return {0, 0}
  end
LUA

# Usage
result = rate_limit_script.call(
  keys: ["rate:user:123"],
  args: [100, 60, Time.now.to_i]
)

allowed, remaining = result
if allowed == 1
  puts "Request allowed, #{remaining} remaining"
else
  puts "Rate limit exceeded"
end
```

## Common Patterns

### Pattern 1: Get and Delete

```ruby
# Atomically get value and delete key
getdel_script = redis.register_script(<<~LUA)
  local value = redis.call('GET', KEYS[1])
  if value then
    redis.call('DEL', KEYS[1])
  end
  return value
LUA

value = getdel_script.call(keys: ["temp_key"])
```

### Pattern 2: Set with Minimum TTL

```ruby
# Set value only if it doesn't exist or has less TTL
setmin_ttl_script = redis.register_script(<<~LUA)
  local key = KEYS[1]
  local value = ARGV[1]
  local ttl = tonumber(ARGV[2])

  local current_ttl = redis.call('TTL', key)

  if current_ttl == -2 or current_ttl < ttl then
    redis.call('SETEX', key, ttl, value)
    return 1
  else
    return 0
  end
LUA

result = setmin_ttl_script.call(
  keys: ["cache_key"],
  args: ["value", 3600]
)
```

### Pattern 3: List Rotate

```ruby
# Rotate list: move item from end to beginning
rotate_script = redis.register_script(<<~LUA)
  local item = redis.call('RPOP', KEYS[1])
  if item then
    redis.call('LPUSH', KEYS[1], item)
    return item
  else
    return nil
  end
LUA

item = rotate_script.call(keys: ["queue"])
```

### Pattern 4: Conditional Hash Update

```ruby
# Update hash field only if condition met
hash_update_script = redis.register_script(<<~LUA)
  local key = KEYS[1]
  local check_field = ARGV[1]
  local check_value = ARGV[2]
  local update_field = ARGV[3]
  local update_value = ARGV[4]

  local current = redis.call('HGET', key, check_field)

  if current == check_value then
    redis.call('HSET', key, update_field, update_value)
    return 1
  else
    return 0
  end
LUA

success = hash_update_script.call(
  keys: ["user:123"],
  args: ["status", "pending", "status", "active"]
)
```

### Pattern 5: Bulk Operations with Filtering

```ruby
# Get multiple keys, filter out nil values
mget_filter_script = redis.register_script(<<~LUA)
  local result = {}
  for i, key in ipairs(KEYS) do
    local value = redis.call('GET', key)
    if value then
      table.insert(result, {key, value})
    end
  end
  return result
LUA

# Get values for keys that exist
result = mget_filter_script.call(
  keys: ["key1", "key2", "key3", "key4"]
)
# => [["key1", "value1"], ["key3", "value3"]]
```

### Pattern 6: Distributed Lock

```ruby
# Acquire distributed lock with timeout
lock_script = redis.register_script(<<~LUA)
  local key = KEYS[1]
  local token = ARGV[1]
  local ttl = tonumber(ARGV[2])

  local result = redis.call('SET', key, token, 'NX', 'EX', ttl)
  if result then
    return 1
  else
    return 0
  end
LUA

# Release lock (only if we own it)
unlock_script = redis.register_script(<<~LUA)
  local key = KEYS[1]
  local token = ARGV[1]

  if redis.call('GET', key) == token then
    return redis.call('DEL', key)
  else
    return 0
  end
LUA

# Usage
token = SecureRandom.uuid
if lock_script.call(keys: ["lock:resource"], args: [token, 10]) == 1
  begin
    # Critical section
    puts "Lock acquired"
  ensure
    unlock_script.call(keys: ["lock:resource"], args: [token])
  end
end
```

## Best Practices

### 1. Keep Scripts Small and Focused

```ruby
# ✅ Good: Small, focused script
script = <<~LUA
  local value = redis.call('GET', KEYS[1])
  return tonumber(value) or 0
LUA

# ❌ Bad: Large, complex script
script = <<~LUA
  -- 200 lines of complex logic
  -- Hard to debug and maintain
LUA
```

### 2. Use KEYS for All Key Names

```ruby
# ✅ Good: Keys in KEYS array
script = <<~LUA
  return redis.call('GET', KEYS[1])
LUA
redis.eval(script, 1, "mykey")

# ❌ Bad: Keys in ARGV or hardcoded
script = <<~LUA
  return redis.call('GET', ARGV[1])  -- Won't work in cluster
LUA
redis.eval(script, 0, "mykey")
```

### 3. Handle Nil Values

```ruby
# ✅ Good: Check for nil
script = <<~LUA
  local value = redis.call('GET', KEYS[1])
  if value then
    return tonumber(value) + 1
  else
    return 1
  end
LUA

# ❌ Bad: Assume value exists
script = <<~LUA
  local value = redis.call('GET', KEYS[1])
  return tonumber(value) + 1  -- Error if value is nil
LUA
```

### 4. Use Type Conversion

```ruby
# ✅ Good: Explicit type conversion
script = <<~LUA
  local num = tonumber(ARGV[1])
  if num then
    return num * 2
  else
    return redis.error_reply("Invalid number")
  end
LUA

# ❌ Bad: No type checking
script = <<~LUA
  return ARGV[1] * 2  -- May fail or give unexpected results
LUA
```

### 5. Cache Scripts with register_script

```ruby
# ✅ Good: Register for reuse
increment_script = redis.register_script(<<~LUA)
  return redis.call('INCR', KEYS[1])
LUA

100.times { increment_script.call(keys: ["counter"]) }

# ❌ Bad: Eval every time
100.times do
  redis.eval("return redis.call('INCR', KEYS[1])", 1, "counter")
end
```

### 6. Return Meaningful Values

```ruby
# ✅ Good: Return useful information
script = <<~LUA
  local deleted = redis.call('DEL', KEYS[1])
  local remaining = redis.call('DBSIZE')
  return {deleted, remaining}
LUA

# ❌ Bad: Return nothing useful
script = <<~LUA
  redis.call('DEL', KEYS[1])
  return 1  -- Always returns 1, not helpful
LUA
```

### 7. Use Local Variables

```ruby
# ✅ Good: Use local variables
script = <<~LUA
  local key = KEYS[1]
  local value = ARGV[1]
  local ttl = tonumber(ARGV[2])

  redis.call('SET', key, value)
  redis.call('EXPIRE', key, ttl)
LUA

# ❌ Bad: Repeat KEYS[1], ARGV[1]
script = <<~LUA
  redis.call('SET', KEYS[1], ARGV[1])
  redis.call('EXPIRE', KEYS[1], tonumber(ARGV[2]))
LUA
```

### 8. Add Comments

```ruby
# ✅ Good: Well-commented
script = <<~LUA
  -- Get current balance
  local balance = tonumber(redis.call('GET', KEYS[1]) or 0)
  local amount = tonumber(ARGV[1])

  -- Check if sufficient funds
  if balance >= amount then
    -- Deduct amount
    redis.call('DECRBY', KEYS[1], amount)
    return 1
  else
    -- Insufficient funds
    return 0
  end
LUA

# ❌ Bad: No comments
script = <<~LUA
  local b = tonumber(redis.call('GET', KEYS[1]) or 0)
  if b >= tonumber(ARGV[1]) then
    redis.call('DECRBY', KEYS[1], ARGV[1])
    return 1
  else
    return 0
  end
LUA
```

## Advanced Techniques

### Debugging Scripts

```ruby
# Use redis.log for debugging
script = <<~LUA
  redis.log(redis.LOG_WARNING, "Processing key: " .. KEYS[1])
  redis.log(redis.LOG_WARNING, "Value: " .. ARGV[1])

  local result = redis.call('SET', KEYS[1], ARGV[1])
  redis.log(redis.LOG_WARNING, "Result: " .. tostring(result))

  return result
LUA

# Check Redis logs for debug output
redis.eval(script, 1, "mykey", "myvalue")
```

### Script Versioning

```ruby
# Version your scripts for safe updates
class ScriptManager
  def initialize(redis)
    @redis = redis
    @scripts = {}
  end

  def register(name, version, script)
    key = "#{name}:v#{version}"
    @scripts[key] = @redis.register_script(script)
  end

  def call(name, version, keys: [], args: [])
    key = "#{name}:v#{version}"
    script = @scripts[key] or raise "Script not found: #{key}"
    script.call(keys: keys, args: args)
  end
end

# Usage
manager = ScriptManager.new(redis)

manager.register("increment", 1, <<~LUA)
  return redis.call('INCR', KEYS[1])
LUA

manager.register("increment", 2, <<~LUA)
  local result = redis.call('INCR', KEYS[1])
  redis.call('SET', KEYS[2], result)
  return result
LUA

# Call specific version
manager.call("increment", 2, keys: ["counter", "last_value"])
```

### Performance Optimization

```ruby
# Batch operations in Lua for better performance
batch_set_script = redis.register_script(<<~LUA)
  for i = 1, #KEYS do
    redis.call('SET', KEYS[i], ARGV[i])
  end
  return #KEYS
LUA

# Set 1000 keys in one script call
keys = 1000.times.map { |i| "key:#{i}" }
values = 1000.times.map { |i| "value:#{i}" }

batch_set_script.call(keys: keys, args: values)
```

### Error Recovery

```ruby
# Graceful error handling in scripts
safe_script = redis.register_script(<<~LUA)
  local success, result = pcall(function()
    return redis.call('INCR', KEYS[1])
  end)

  if success then
    return {1, result}
  else
    redis.log(redis.LOG_WARNING, "Error: " .. tostring(result))
    return {0, nil}
  end
LUA

success, value = safe_script.call(keys: ["counter"])
if success == 1
  puts "Incremented to #{value}"
else
  puts "Operation failed"
end
```

### Complex Data Structures

```ruby
# Work with complex data in Lua
leaderboard_script = redis.register_script(<<~LUA)
  local key = KEYS[1]
  local user_id = ARGV[1]
  local score = tonumber(ARGV[2])

  -- Add to sorted set
  redis.call('ZADD', key, score, user_id)

  -- Get rank (0-based)
  local rank = redis.call('ZREVRANK', key, user_id)

  -- Get total count
  local total = redis.call('ZCARD', key)

  -- Get top 3
  local top3 = redis.call('ZREVRANGE', key, 0, 2, 'WITHSCORES')

  return {rank + 1, total, top3}
LUA

rank, total, top3 = leaderboard_script.call(
  keys: ["leaderboard"],
  args: [123, 9500]
)

puts "Rank: #{rank} out of #{total}"
puts "Top 3: #{top3.inspect}"
```

## Real-World Examples

### Example 1: Session Management

```ruby
# Atomic session creation with expiry
create_session_script = redis.register_script(<<~LUA)
  local session_key = KEYS[1]
  local user_sessions_key = KEYS[2]
  local session_id = ARGV[1]
  local user_id = ARGV[2]
  local session_data = ARGV[3]
  local ttl = tonumber(ARGV[4])

  -- Store session data
  redis.call('SETEX', session_key, ttl, session_data)

  -- Add to user's session set
  redis.call('SADD', user_sessions_key, session_id)
  redis.call('EXPIRE', user_sessions_key, ttl)

  -- Return session info
  return {session_id, ttl}
LUA

session_id = SecureRandom.uuid
session_data = { user_id: 123, ip: "1.2.3.4" }.to_json

result = create_session_script.call(
  keys: ["session:#{session_id}", "user:123:sessions"],
  args: [session_id, 123, session_data, 3600]
)
```

### Example 2: Inventory Management

```ruby
# Reserve inventory with atomic check
reserve_inventory_script = redis.register_script(<<~LUA)
  local stock_key = KEYS[1]
  local reserved_key = KEYS[2]
  local product_id = ARGV[1]
  local quantity = tonumber(ARGV[2])
  local order_id = ARGV[3]

  -- Get current stock
  local stock = tonumber(redis.call('GET', stock_key) or 0)

  if stock >= quantity then
    -- Deduct from stock
    redis.call('DECRBY', stock_key, quantity)

    -- Add to reserved
    redis.call('HINCRBY', reserved_key, order_id, quantity)

    -- Return success with remaining stock
    return {1, stock - quantity}
  else
    -- Insufficient stock
    return {0, stock}
  end
LUA

success, remaining = reserve_inventory_script.call(
  keys: ["product:123:stock", "product:123:reserved"],
  args: ["product:123", 5, "order:456"]
)

if success == 1
  puts "Reserved 5 units, #{remaining} remaining"
else
  puts "Only #{remaining} units available"
end
```

### Example 3: Feature Flags

```ruby
# Check feature flag with user targeting
check_feature_script = redis.register_script(<<~LUA)
  local flag_key = KEYS[1]
  local user_id = ARGV[1]

  -- Get flag configuration
  local config = redis.call('HGETALL', flag_key)
  if #config == 0 then
    return 0  -- Flag doesn't exist
  end

  -- Convert to table
  local flag = {}
  for i = 1, #config, 2 do
    flag[config[i]] = config[i + 1]
  end

  -- Check if enabled globally
  if flag.enabled ~= "true" then
    return 0
  end

  -- Check if user is in whitelist
  local whitelist = redis.call('SISMEMBER', flag_key .. ':whitelist', user_id)
  if whitelist == 1 then
    return 1
  end

  -- Check rollout percentage
  local rollout = tonumber(flag.rollout or 0)
  if rollout > 0 then
    local hash = tonumber(string.sub(user_id, 1, 8), 16)
    local bucket = hash % 100
    if bucket < rollout then
      return 1
    end
  end

  return 0
LUA

enabled = check_feature_script.call(
  keys: ["feature:new_ui"],
  args: ["user:123"]
)

if enabled == 1
  puts "Feature enabled for user"
else
  puts "Feature disabled for user"
end
```

## Next Steps

- [Transactions](/guides/transactions/) - Atomic operations with MULTI/EXEC
- [Pub/Sub](/guides/pubsub/) - Real-time messaging patterns
- [Pipelines](/guides/pipelines/) - Batch commands for better performance
- [Getting Started](/getting-started/) - Basic Redis operations

## Additional Resources

- [Redis Lua Scripting](https://redis.io/docs/manual/programmability/) - Official Redis documentation
- [Lua 5.1 Reference](https://www.lua.org/manual/5.1/) - Lua language reference
- [EVAL Command](https://redis.io/commands/eval/) - EVAL command documentation
- [Script Commands](https://redis.io/commands/?group=scripting) - All scripting commands


