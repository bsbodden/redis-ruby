# Active-Active Geo-Distribution with CRDTs

This guide explains how to use redis-ruby with Redis Enterprise Active-Active databases that use Conflict-free Replicated Data Types (CRDTs) for multi-region geo-distributed deployments.

## Table of Contents

- [Overview](#overview)
- [What are CRDTs?](#what-are-crdts)
- [Basic Usage](#basic-usage)
- [Multi-Region Failover](#multi-region-failover)
- [CRDT Semantics](#crdt-semantics)
- [Best Practices](#best-practices)
- [Comparison with Other Clients](#comparison-with-other-clients)

## Overview

Redis Enterprise Active-Active databases enable geo-distributed writes across multiple regions with automatic conflict resolution using CRDTs. The `ActiveActiveClient` manages connections to multiple regional endpoints and provides automatic failover when a region becomes unavailable.

**Key Features:**
- Multi-region connection management
- Automatic failover across geographic regions
- Support for all Redis data types with CRDT semantics
- SSL/TLS and authentication support
- Thread-safe operations

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

### Creating an Active-Active Client

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

### With Authentication and SSL

```ruby
client = RR.active_active(
  regions: [
    { host: "redis-us.example.com", port: 6380 },
    { host: "redis-eu.example.com", port: 6380 }
  ],
  password: "your-password",
  ssl: true,
  ssl_params: {
    verify_mode: OpenSSL::SSL::VERIFY_PEER,
    ca_file: "/path/to/ca.crt"
  }
)
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

### redis-py (Python)

redis-py doesn't have built-in Active-Active support. Users typically connect to a single endpoint and handle failover at the application level.

### Jedis (Java)

Jedis doesn't have built-in Active-Active support. Similar to redis-py, users manage connections manually.

### Lettuce (Java)

Lettuce doesn't have built-in Active-Active support but provides connection pooling and failover mechanisms that can be used with Active-Active databases.

### redis-ruby Advantages

- **Built-in multi-region support** - Automatic failover across regions
- **Simple API** - Same interface as standard Redis client
- **Thread-safe** - Safe to use from multiple threads
- **Flexible configuration** - Support for SSL, authentication, preferred regions

## Additional Resources

- [Redis Enterprise Active-Active Documentation](https://redis.io/docs/latest/operate/rs/databases/active-active/)
- [Understanding CRDTs](https://redis.io/blog/diving-into-crdts/)
- [Active-Active Geo-Distribution Whitepaper](https://redis.io/docs/latest/operate/rs/databases/active-active/)

