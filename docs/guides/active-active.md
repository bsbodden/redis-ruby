# Active-Active Geo-Distribution with CRDTs

This guide explains how to use redis-ruby with Redis Enterprise Active-Active databases that use Conflict-free Replicated Data Types (CRDTs) for multi-region geo-distributed deployments.

## Table of Contents

- [Overview](#overview)
- [What are CRDTs?](#what-are-crdts)
- [Basic Usage](#basic-usage)
- [Enterprise Features](#enterprise-features)
  - [Health Checks](#health-checks)
  - [Circuit Breaker](#circuit-breaker)
  - [Failure Detection](#failure-detection)
  - [Auto-Fallback](#auto-fallback)
  - [Event System](#event-system)
- [Multi-Region Failover](#multi-region-failover)
- [CRDT Semantics](#crdt-semantics)
- [Best Practices](#best-practices)
- [Comparison with Other Clients](#comparison-with-other-clients)

## Overview

Redis Enterprise Active-Active databases enable geo-distributed writes across multiple regions with automatic conflict resolution using CRDTs. The `ActiveActiveClient` is a **production-ready, enterprise-grade** client that manages connections to multiple regional endpoints with comprehensive monitoring and failover capabilities.

**Key Features:**
- **Multi-region connection management** with weight-based prioritization
- **Automatic failover** across geographic regions
- **Background health checks** with configurable policies
- **Circuit breaker pattern** to prevent cascading failures
- **Failure detection** with sliding window analysis
- **Auto-fallback** to preferred region when healthy
- **Event system** for monitoring failover events
- **Support for all Redis data types** with CRDT semantics
- **SSL/TLS and authentication** support
- **Thread-safe operations**

## What are CRDTs?

Conflict-free Replicated Data Types (CRDTs) are data structures that automatically resolve conflicts in distributed systems. In Redis Enterprise Active-Active databases:

- **Writes to different regions are eventually consistent** - All replicas eventually converge to the same state
- **No conflict resolution needed** - CRDT semantics handle conflicts automatically
- **Order doesn't matter** - Operations are commutative and can be applied in any order

### CRDT Rules for Redis Data Types

**Sets:**
- **Add wins over delete** - If one region adds an element while another deletes it, the add wins
- **Observed remove** - You can only delete elements that your replica has seen

**Counters:**
- **Increments/decrements are commutative** - Operations can be applied in any order
- **Final value is sum of all operations** - All regions converge to the same count

**Strings (Registers):**
- **Last-write-wins with vector clocks** - Conflicts resolved using timestamps and vector clocks

## Basic Usage

### Simple Configuration (Development/Testing)

For development and testing, you can use the simple configuration without enterprise features:

```ruby
require "redis_ruby"

# Connect to multiple regions
client = RR.active_active(
  regions: [
    { host: "redis-us-east.example.com", port: 6379 },
    { host: "redis-eu-west.example.com", port: 6379 },
    { host: "redis-ap-south.example.com", port: 6379 }
  ]
)

# Use like a normal Redis client
client.set("user:1:name", "Alice")
name = client.get("user:1:name")
puts name  # => "Alice"

client.close
```

### Production Configuration (Enterprise Features)

For production deployments, enable all enterprise features for maximum reliability:

```ruby
client = RR.active_active(
  regions: [
    { host: "redis-us.example.com", port: 6380, weight: 1.0 },   # Primary region
    { host: "redis-eu.example.com", port: 6380, weight: 0.8 },   # Secondary region
    { host: "redis-ap.example.com", port: 6380, weight: 0.5 }    # Tertiary region
  ],
  password: "your-password",
  ssl: true,
  ssl_params: {
    verify_mode: OpenSSL::SSL::VERIFY_PEER,
    ca_file: "/path/to/ca.crt"
  },
  # Health check configuration
  health_check_interval: 5.0,        # Check every 5 seconds
  health_check_probes: 3,            # 3 probes per check
  health_check_policy: :majority,    # Majority must pass
  # Circuit breaker configuration
  circuit_breaker_threshold: 5,      # Open after 5 failures
  circuit_breaker_timeout: 60,       # Try half-open after 60 seconds
  # Failure detection configuration
  failure_window_size: 2.0,          # 2 second sliding window
  min_failures: 1000,                # Minimum failures to trigger
  failure_rate_threshold: 0.10,      # 10% failure rate threshold
  # Auto-fallback configuration
  auto_fallback_interval: 30.0       # Try to fallback every 30 seconds
)

# Register event listeners
client.on_failover do |event|
  puts "Failover: #{event.from_region} -> #{event.to_region} (#{event.reason})"
end

client.on_database_failed do |event|
  puts "Database failed: #{event.region} - #{event.error}"
end

client.on_database_recovered do |event|
  puts "Database recovered: #{event.region}"
end
```

## Enterprise Features

### Health Checks

Background health checks proactively monitor database availability:

```ruby
client = RR.active_active(
  regions: regions,
  health_check_interval: 5.0,     # Check every 5 seconds
  health_check_probes: 3,         # Run 3 probes per check
  health_check_probe_delay: 0.1,  # 100ms between probes
  health_check_policy: :majority  # Majority must pass
)

# Available policies:
# :all      - All probes must pass (strict)
# :majority - More than 50% must pass (balanced)
# :any      - At least one must pass (lenient)

# Check health status
status = client.health_status
status.each do |region_id, info|
  puts "Region #{info[:region]}: healthy=#{info[:healthy]}, circuit=#{info[:circuit_state]}"
end
```

### Circuit Breaker

Circuit breaker pattern prevents cascading failures:

```ruby
client = RR.active_active(
  regions: regions,
  circuit_breaker_threshold: 5,   # Open after 5 consecutive failures
  circuit_breaker_timeout: 60     # Try half-open after 60 seconds
)

# Circuit states:
# :closed     - Normal operation (healthy)
# :open       - Rejecting calls (unhealthy)
# :half_open  - Testing recovery (probing)
```

### Failure Detection

Sliding window failure detection triggers failover based on failure rates:

```ruby
client = RR.active_active(
  regions: regions,
  failure_window_size: 2.0,         # 2 second sliding window
  min_failures: 1000,               # Need at least 1000 failures
  failure_rate_threshold: 0.10      # 10% failure rate triggers failover
)

# Failure detection is reactive - monitors actual traffic
# Complements proactive health checks
```

### Auto-Fallback

Automatically return to preferred region when it becomes healthy:

```ruby
client = RR.active_active(
  regions: regions,
  preferred_region: 0,              # Index of preferred region
  auto_fallback_interval: 30.0      # Check every 30 seconds
)

# When enabled, client periodically checks if preferred region is healthy
# and automatically fails back to it
```

### Event System

Monitor failover events in real-time:

```ruby
client = RR.active_active(regions: regions)

# Failover events
client.on_failover do |event|
  logger.warn "Failover from #{event.from_region} to #{event.to_region}"
  logger.warn "Reason: #{event.reason}"  # "automatic", "manual", or "auto_fallback"
  metrics.increment("redis.failover")
end

# Database failure events
client.on_database_failed do |event|
  logger.error "Database #{event.region} failed: #{event.error}"
  alert_ops_team(event)
end

# Database recovery events
client.on_database_recovered do |event|
  logger.info "Database #{event.region} recovered"
  metrics.increment("redis.recovery")
end
```

### Specifying a Preferred Region

```ruby
# Start with the second region (EU)
client = RR.active_active(
  regions: [
    { host: "redis-us.example.com", port: 6379 },
    { host: "redis-eu.example.com", port: 6379 },
    { host: "redis-ap.example.com", port: 6379 }
  ],
  preferred_region: 1  # Index of EU region
)
```

## Multi-Region Failover

The client automatically fails over to the next region when a connection error occurs:

```ruby
client = RR.active_active(
  regions: [
    { host: "redis-us.example.com", port: 6379 },
    { host: "redis-eu.example.com", port: 6379 }
  ]
)

# If US region fails, client automatically tries EU region
begin
  client.set("key", "value")
rescue RR::ConnectionError => e
  # All regions are unavailable
  puts "All regions failed: #{e.message}"
end
```

### Manual Failover

You can manually trigger a failover to the next region:

```ruby
# Check current region
puts client.current_region  # => { host: "redis-us.example.com", port: 6379 }

# Manually failover to next region
client.failover_to_next_region

# Now on EU region
puts client.current_region  # => { host: "redis-eu.example.com", port: 6379 }
```

## CRDT Semantics

### Set Operations

```ruby
# In a true Active-Active setup (not simulated):

# Region US
client_us.sadd("users:active", "alice")
client_us.sadd("users:active", "bob")

# Region EU (concurrent)
client_eu.sadd("users:active", "charlie")
client_eu.srem("users:active", "alice")  # Before seeing US's add

# After synchronization, both regions converge to:
# users:active = ["alice", "bob", "charlie"]
# (Add wins over delete for "alice")
```

### Counter Operations

```ruby
# Region US
client_us.incr("page:views")  # 1
client_us.incr("page:views")  # 2

# Region EU (concurrent)
client_eu.incr("page:views")  # 1
client_eu.incr("page:views")  # 2

# After synchronization:
# page:views = 4 (sum of all increments)
```

## Best Practices

1. **Design for Eventual Consistency**
   - Don't assume immediate consistency across regions
   - Use CRDTs for data that can tolerate eventual consistency
   - Avoid using Active-Active for transactional data (e.g., bank balances)

2. **Choose the Right Data Structures**
   - Use Sets for membership (add-wins semantics work well)
   - Use Counters for metrics and statistics
   - Be careful with Strings/Registers (last-write-wins can lose data)

3. **Handle Network Partitions**
   - Design your application to work when disconnected from some regions
   - Use the `connected?` method to check connection status
   - Implement retry logic for critical operations

4. **Monitor Region Health**
   - Track which region you're connected to
   - Monitor failover events
   - Alert on prolonged disconnections

5. **Test with Simulated Failures**
   - Test your application's behavior when regions fail
   - Verify that failover works as expected
   - Ensure data consistency after network partitions heal

## Comparison with Other Clients

### redis-py (Python) - MultiDatabaseClient

redis-py provides a comprehensive `MultiDatabaseClient` for Active-Active deployments with enterprise features:

**redis-py Features:**
- ✅ Multi-database connection management
- ✅ Background health checks with configurable policies
- ✅ Circuit breaker pattern (CLOSED/OPEN/HALF_OPEN)
- ✅ Failure detection with sliding windows
- ✅ Auto-fallback to preferred database
- ✅ Event system for monitoring
- ✅ Weight-based database selection
- ✅ Pub/Sub re-subscription on failover
- ✅ Lag-aware health checks (Redis Enterprise REST API)

**redis-ruby Implementation:**
- ✅ Multi-region connection management
- ✅ Background health checks with configurable policies (:all, :majority, :any)
- ✅ Circuit breaker pattern (CLOSED/OPEN/HALF_OPEN)
- ✅ Failure detection with sliding windows
- ✅ Auto-fallback to preferred region
- ✅ Event system (on_failover, on_database_failed, on_database_recovered)
- ✅ Weight-based region selection
- ⚠️ Pub/Sub re-subscription (not yet implemented)
- ⚠️ Lag-aware health checks (not yet implemented)

**Verdict:** redis-ruby's Active-Active implementation is **production-ready and enterprise-grade**, matching redis-py's core features. The implementation was designed after redis-py's MultiDatabaseClient but adapted for Ruby idioms.

### Jedis (Java)

Jedis doesn't have built-in Active-Active support. Users must manage multi-region connections manually at the application level.

### Lettuce (Java)

Lettuce doesn't have built-in Active-Active support but provides connection pooling and failover mechanisms that can be adapted for Active-Active databases.

### redis-ruby Advantages

- **Production-ready enterprise features** - Matches redis-py's MultiDatabaseClient
- **Background health monitoring** - Proactive detection of unhealthy regions
- **Circuit breaker pattern** - Prevents cascading failures
- **Failure detection** - Reactive monitoring based on actual traffic
- **Auto-fallback** - Automatically returns to preferred region
- **Event system** - Real-time monitoring of failover events
- **Weight-based failover** - Prioritize regions by configured weights
- **Thread-safe** - Safe to use from multiple threads
- **Simple API** - Same interface as standard Redis client

## Additional Resources

- [Redis Enterprise Active-Active Documentation](https://redis.io/docs/latest/operate/rs/databases/active-active/)
- [Understanding CRDTs](https://redis.io/blog/diving-into-crdts/)
- [Active-Active Geo-Distribution Whitepaper](https://redis.io/docs/latest/operate/rs/databases/active-active/)

