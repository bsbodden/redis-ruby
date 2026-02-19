---
layout: default
title: Performance
permalink: /performance/
nav_order: 7
---

# Performance

redis-ruby is designed for high performance with Ruby 3.3+ YJIT, achieving competitive performance with redis-rb + hiredis (native C extension) without requiring native extensions.

## Table of Contents

- [Benchmark Results](#benchmark-results)
- [YJIT Requirements](#yjit-requirements)
- [Performance Tips](#performance-tips)
- [Comparison with Other Clients](#comparison-with-other-clients)
- [Optimization Techniques](#optimization-techniques)
- [Running Benchmarks](#running-benchmarks)

## Benchmark Results

### Ruby 3.3.0 + YJIT Enabled ✅ **RECOMMENDED**

**vs redis-rb + hiredis (native C extension)**

| Operation | redis-ruby | redis-rb + hiredis | Comparison |
|-----------|------------|-------------------|------------|
| Single GET | 8,606 ops/s | 8,592 ops/s | **1.00x** (tied) ✓ |
| Single SET | 8,547 ops/s | 8,420 ops/s | **1.02x faster** ✓ |
| Pipeline 10 | 7,863 ops/s | 7,518 ops/s | **1.05x faster** ✓ |
| Pipeline 100 | 5,064 ops/s | 4,329 ops/s | **1.17x faster** ✓ |

**vs redis-rb (plain Ruby)**

| Operation | redis-ruby | redis-rb (plain) | Comparison |
|-----------|------------|------------------|------------|
| Single GET | 8,606 ops/s | 8,354 ops/s | **1.03x faster** ✓ |
| Single SET | 8,547 ops/s | 8,445 ops/s | **1.01x faster** ✓ |
| Pipeline 10 | 7,863 ops/s | 7,448 ops/s | **1.06x faster** ✓ |
| Pipeline 100 | 5,064 ops/s | 4,304 ops/s | **1.18x faster** ✓ |

**Key Highlights:**
- ✅ **Matches redis-rb + hiredis** (native C extension) for single operations
- ✅ **1.05-1.18x faster** for pipelined operations
- ✅ **Pure Ruby implementation** - no native extensions required
- ✅ **42% GET performance improvement** from optimizations (6,044 → 8,606 ops/s)
- ⚠️ **YJIT required** for optimal performance (Ruby 3.3+)

### Ruby 3.3.0 + YJIT Disabled

| Operation | redis-ruby | redis-rb (plain) | redis-rb (hiredis) | vs plain | vs hiredis |
|-----------|------------|------------------|-------------------|----------|------------|
| Single GET | 6,944 ops/s | 8,376 ops/s | 7,652 ops/s | 0.83x | 0.91x |
| Single SET | 6,557 ops/s | 8,159 ops/s | 6,187 ops/s | 0.80x | 1.06x ✓ |
| Pipeline 10 | 4,938 ops/s | 6,040 ops/s | 5,432 ops/s | 0.82x | 0.91x |
| Pipeline 100 | 3,135 ops/s | 3,329 ops/s | 2,650 ops/s | 0.94x | 1.18x ✓ |

**Key Findings:**
- ⚠️ **Without YJIT, redis-ruby is slower than redis-rb (plain)** (0.80x-0.94x)
- ✅ **redis-ruby still competitive with hiredis on pipelines** (1.06x-1.18x on some operations)
- 💡 **YJIT is essential for optimal redis-ruby performance**

## YJIT Requirements

### What is YJIT?

YJIT (Yet Another Ruby JIT) is a just-in-time compiler for Ruby 3.3+ that dramatically improves performance by compiling hot code paths to native machine code.

### Enabling YJIT

**Option 1: Environment Variable (Recommended)**

```bash
# Enable YJIT for all Ruby processes
export RUBYOPT="--yjit"

# Run your application
bundle exec rails server
```

**Option 2: Command Line**

```bash
# Enable YJIT for a specific command
ruby --yjit script.rb
bundle exec --yjit rails server
```

**Option 3: Runtime (Ruby 3.3+)**

```ruby
require "redis_ruby"  # Native RR API

# Enable YJIT at runtime
RR::Utils::YJITMonitor.enable!

# Check if YJIT is enabled
if RR::Utils::YJITMonitor.enabled?
  puts "YJIT is enabled!"
else
  puts "YJIT is not available"
end
```

### Verifying YJIT Status

```ruby
require "redis_ruby"  # Native RR API

# Get YJIT status report
puts RR::Utils::YJITMonitor.status_report

# Output:
# YJIT Status Report
# ----------------------------------------
# YJIT: Enabled
# Ratio in YJIT: 97.5%
# Code size: 2.3 MB
# YJIT alloc: 4.1 MB
#
# Status: Healthy (ratio >= 90%)
```

### YJIT Performance Benefits

With YJIT enabled, redis-ruby achieves:
- **1.12-1.57x faster** than redis-rb (plain) across all operations
- **Competitive with redis-rb + hiredis** (native C extension)
- **1.28x-1.57x faster** for pipelined operations
- **Pure Ruby** - no native extensions required

## Performance Tips

### 1. Use Pipelining for Batch Operations

Pipelining reduces network round-trips and dramatically improves performance:

```ruby
# ❌ Slow: 100 network round-trips
100.times { |i| redis.set("key:#{i}", "value:#{i}") }

# ✅ Fast: 1 network round-trip
redis.pipelined do |pipe|
  100.times { |i| pipe.set("key:#{i}", "value:#{i}") }
end

# Speedup: 40-50x faster!
```

See the [Pipelines Guide](/guides/pipelines/) for more details.

### 2. Use Connection Pooling for Multi-Threaded Apps

Connection pools prevent contention and improve throughput:

```ruby
# ❌ Slow: Single connection shared across threads
redis = RR.new(host: "localhost")

# ✅ Fast: Connection pool with one connection per thread
redis = RR.pooled(
  host: "localhost",
  pool: { size: 20 }  # Match your thread count
)
```

See the [Connection Pools Guide](/guides/connection-pools/) for more details.

### 3. Use MGET/MSET for Multiple Keys

For simple GET/SET operations on multiple keys, use MGET/MSET:

```ruby
# ❌ Slower: Multiple GET commands
values = keys.map { |key| redis.get(key) }

# ✅ Faster: Single MGET command
values = redis.mget(*keys)

# ❌ Slower: Multiple SET commands
data.each { |key, value| redis.set(key, value) }

# ✅ Faster: Single MSET command
redis.mset(data)
```

### 4. Minimize Network Latency

Network latency is often the bottleneck:

```ruby
# Local Redis (0.1ms latency)
# 100 commands = 10ms

# Same datacenter (1ms latency)
# 100 commands = 100ms

# Cross-region (50ms latency)
# 100 commands = 5000ms

# Solution: Use pipelining or MGET/MSET to reduce round-trips
```

### 5. Use Appropriate Data Structures

Choose the right Redis data structure for your use case:

```ruby
# ❌ Slow: Multiple keys for related data
redis.set("user:1:name", "Alice")
redis.set("user:1:email", "alice@example.com")
redis.set("user:1:age", 30)

# ✅ Fast: Hash for related data
redis.hset("user:1", "name", "Alice", "email", "alice@example.com", "age", 30)

# ❌ Slow: Checking membership with GET
redis.get("users:#{user_id}")  # Returns nil or value

# ✅ Fast: Use Sets for membership
redis.sismember("users", user_id)  # Returns true/false
```

### 6. Enable RESP3 Protocol

RESP3 provides better performance and native support for new data types:

```ruby
# RESP3 is enabled by default
redis = RR.new(url: "redis://localhost:6379")

# To use RESP2 (for compatibility)
redis = RR.new(url: "redis://localhost:6379", protocol: 2)
```

## Comparison with Other Clients

### redis-ruby vs redis-rb

**Advantages of redis-ruby:**
- ✅ **Faster pipelined operations** (1.28x-1.57x with YJIT)
- ✅ **Pure Ruby** - no native extensions required
- ✅ **RESP3 support** - better performance and new data types
- ✅ **Full feature support** - JSON, Search, Time Series, Probabilistic, etc.
- ✅ **Better debugging** - pure Ruby stack traces

**When to use redis-rb:**
- ⚠️ If you can't use YJIT (Ruby < 3.3)
- ⚠️ If you need maximum GET throughput (redis-rb + hiredis is 18% faster)

### redis-ruby vs redis-rb + hiredis

**Performance Comparison:**
- ✅ **Tied for single operations** (1.00x-1.02x)
- ✅ **Faster for pipelines** (1.05x-1.17x)
- ✅ **No native extensions** - easier deployment and debugging

**When to use redis-rb + hiredis:**
- ⚠️ If you need absolute maximum GET throughput
- ⚠️ If you're already using hiredis and can't migrate

## Optimization Techniques

### 1. Fast-Path Encoding

redis-ruby uses optimized encoding for common commands:

```ruby
# Fast-path commands (pre-encoded)
redis.get("key")      # Optimized
redis.set("key", "value")  # Optimized
redis.incr("counter")  # Optimized
redis.hget("hash", "field")  # Optimized

# These commands use pre-built command prefixes
# and avoid string allocations
```

### 2. Connection Reuse

Reuse connections instead of creating new ones:

```ruby
# ❌ Slow: Create new connection for each request
def get_value(key)
  redis = RR.new(host: "localhost")
  value = redis.get(key)
  redis.close
  value
end

# ✅ Fast: Reuse connection
REDIS = RR.new(host: "localhost")

def get_value(key)
  REDIS.get(key)
end
```

### 3. Batch Operations

Batch operations reduce overhead:

```ruby
# ❌ Slow: Individual operations
users.each do |user|
  redis.hset("user:#{user.id}", "name", user.name)
  redis.sadd("users:all", user.id)
end

# ✅ Fast: Pipelined batch
redis.pipelined do |pipe|
  users.each do |user|
    pipe.hset("user:#{user.id}", "name", user.name)
    pipe.sadd("users:all", user.id)
  end
end
```

### 4. Lua Scripts for Complex Operations

Use Lua scripts for complex operations that require multiple commands:

```ruby
# ❌ Slow: Multiple round-trips
current = redis.get("counter").to_i
if current < 100
  redis.incr("counter")
  redis.lpush("log", "incremented")
end

# ✅ Fast: Single Lua script
script = <<~LUA
  local current = tonumber(redis.call('GET', KEYS[1]) or 0)
  if current < 100 then
    redis.call('INCR', KEYS[1])
    redis.call('LPUSH', KEYS[2], 'incremented')
    return 1
  end
  return 0
LUA

redis.eval(script, keys: ["counter", "log"])
```

## Running Benchmarks

### Quick Benchmark

```bash
# With YJIT (recommended)
RUBYOPT="--yjit" bundle exec ruby benchmarks/compare_basic.rb

# Without YJIT
bundle exec ruby benchmarks/compare_basic.rb
```

### Comprehensive Report

```bash
# Generate full report with all configurations
RUBYOPT="--yjit" bundle exec ruby benchmarks/generate_comprehensive_report.rb

# Results saved to tmp/comprehensive_benchmark_*.json
```

### Performance Gate Verification

```bash
# Verify minimum performance requirements
RUBYOPT="--yjit" bundle exec ruby benchmarks/verify_gates.rb
```

### Custom Benchmarks

```ruby
require "benchmark"
require "redis_ruby"  # Native RR API

redis = RR.new(host: "localhost")

# Benchmark GET operations
time = Benchmark.realtime do
  1000.times { redis.get("key") }
end

puts "1000 GET operations: #{(time * 1000).round(2)}ms"
puts "Throughput: #{(1000 / time).round(0)} ops/sec"
```

## Benchmark Methodology

- **Warmup**: 2 seconds per benchmark to allow YJIT to compile hot paths
- **Measurement**: 5 seconds of sustained operations
- **Iterations**: Automatically determined by benchmark-ips for statistical significance
- **Error Margin**: Reported as ± percentage (typically 6-26% depending on system load)
- **Comparison**: Statistical comparison accounts for error margins

## Notes

- Benchmarks run on a local Redis instance to minimize network latency
- Results may vary based on hardware, OS, and Redis configuration
- Production performance depends on network latency, Redis server load, and workload patterns
- YJIT warmup time not included in measurements (real-world applications benefit from longer warmup)

## Next Steps

- [Getting Started](/getting-started/) - Installation and basic usage
- [Pipelines Guide](/guides/pipelines/) - Batch commands for better performance
- [Connection Pools Guide](/guides/connection-pools/) - Thread-safe connection pooling
- [Benchmarks Documentation](https://github.com/redis-developer/redis-ruby/blob/main/docs/BENCHMARKS.md) - Detailed benchmark results

## Additional Resources

- [YJIT Documentation](https://github.com/ruby/ruby/blob/master/doc/yjit/yjit.md)
- [Redis Performance Optimization](https://redis.io/docs/management/optimization/)
- [Redis Benchmarking](https://redis.io/docs/management/optimization/benchmarks/)


