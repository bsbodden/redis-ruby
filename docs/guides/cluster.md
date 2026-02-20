---
layout: default
title: Redis Cluster
parent: Guides
nav_order: 8
---

# Redis Cluster

This guide covers Redis Cluster support in redis-ruby, including automatic sharding, failover handling, and best practices for distributed Redis deployments.

## Table of Contents

- [What is Redis Cluster](#what-is-redis-cluster)
- [Connecting to a Cluster](#connecting-to-a-cluster)
- [Cluster Topology](#cluster-topology)
- [Hash Slots and Key Distribution](#hash-slots-and-key-distribution)
- [Multi-Key Operations](#multi-key-operations)
- [Cluster Commands](#cluster-commands)
- [Failover Handling](#failover-handling)
- [Reading from Replicas](#reading-from-replicas)
- [Best Practices](#best-practices)

## What is Redis Cluster

Redis Cluster is Redis's native sharding solution that provides:

- **Automatic Sharding**: Data is automatically distributed across multiple nodes
- **High Availability**: Automatic failover when master nodes fail
- **Horizontal Scaling**: Add nodes to increase capacity
- **No Single Point of Failure**: Distributed architecture with master-replica pairs

### Key Concepts

- **Hash Slots**: Redis Cluster divides the key space into 16,384 hash slots
- **Sharding**: Each master node is responsible for a subset of hash slots
- **Replication**: Each master can have one or more replica nodes
- **Automatic Failover**: Replicas are promoted to masters when failures occur

## Connecting to a Cluster

### Basic Connection

Connect to a Redis Cluster by providing one or more seed nodes:

```ruby
require "redis_ruby"  # Native RR API

# Connect using seed nodes
redis = RR.cluster(
  nodes: [
    "redis://node1.example.com:6379",
    "redis://node2.example.com:6379",
    "redis://node3.example.com:6379"
  ]
)

# The client automatically discovers all cluster nodes
redis.set("mykey", "myvalue")
redis.get("mykey")  # => "myvalue"
```

### Connection with Authentication

```ruby
redis = RR.cluster(
  nodes: ["redis://node1:6379", "redis://node2:6379"],
  password: "your-cluster-password"
)
```

### Connection Options

```ruby
redis = RR.cluster(
  nodes: ["redis://node1:6379"],
  password: nil,              # Cluster password
  timeout: 5.0,               # Connection timeout in seconds
  read_from: :master,         # :master, :replica, or :replica_preferred
  retry_count: 3,             # Number of retries on failure
  host_translation: {}        # Map announced IPs to reachable IPs
)
```

### Using ClusterClient Directly

```ruby
require "redis_ruby/cluster_client"

client = RR::ClusterClient.new(
  nodes: [
    { host: "node1", port: 6379 },
    { host: "node2", port: 6379 }
  ],
  password: "secret"
)

client.set("key", "value")
```

## Cluster Topology

### Understanding the Topology

Redis Cluster automatically manages the topology and slot distribution:

```ruby
# Check cluster health
redis.cluster_info
# => { "cluster_state" => "ok", "cluster_slots_assigned" => 16384, ... }

# Get cluster nodes
redis.cluster_nodes
# Returns information about all nodes in the cluster

# Get slot distribution
redis.cluster_slots
# Returns array of [start_slot, end_slot, master_info, replica_info, ...]
```

### Topology Discovery

The client automatically discovers the cluster topology:

1. Connects to one or more seed nodes
2. Executes `CLUSTER SLOTS` to get the full topology
3. Builds an internal slot-to-node mapping
4. Refreshes topology on `MOVED` errors

```ruby
# Manually refresh cluster topology
redis.refresh_slots

# Check number of known nodes
redis.node_count  # => 6
```

## Hash Slots and Key Distribution

### How Hash Slots Work

Redis Cluster uses CRC16 hashing to distribute keys across 16,384 slots:

```ruby
# Calculate the hash slot for a key
redis.key_slot("mykey")  # => 14687

# Keys are automatically routed to the correct node
redis.set("user:1000", "Alice")  # Routed to node owning slot for "user:1000"
redis.get("user:1000")           # Routed to same node
```

### Hash Tags

Use hash tags to ensure related keys are stored on the same node:

```ruby
# Without hash tags - keys may be on different nodes
redis.set("user:1000:name", "Alice")
redis.set("user:1000:email", "alice@example.com")

# With hash tags - keys guaranteed to be on same node
redis.set("user:{1000}:name", "Alice")
redis.set("user:{1000}:email", "alice@example.com")

# Only the content within {} is hashed
redis.key_slot("user:{1000}:name")   # => 1584
redis.key_slot("user:{1000}:email")  # => 1584 (same slot!)
```

### Multi-Key Operations with Hash Tags

```ruby
# These work because all keys are on the same node
redis.mget("user:{1000}:name", "user:{1000}:email", "user:{1000}:age")

redis.pipelined do |pipe|
  pipe.get("user:{1000}:name")
  pipe.get("user:{1000}:email")
  pipe.incr("user:{1000}:visits")
end
```

## Multi-Key Operations

### Operations on the Same Node

Multi-key operations work when all keys are on the same node:

```ruby
# Using hash tags to ensure same node
redis.mset("product:{100}:name", "Widget", "product:{100}:price", "9.99")
redis.mget("product:{100}:name", "product:{100}:price")
# => ["Widget", "9.99"]

# Set operations with hash tags
redis.sadd("tags:{post:1}", "ruby", "redis", "cluster")
redis.sadd("tags:{post:1}", "performance")
redis.smembers("tags:{post:1}")
# => ["ruby", "redis", "cluster", "performance"]
```

### Cross-Slot Operations

Operations spanning multiple slots will raise `RR::CrossSlotError`:

```ruby
# This will raise CrossSlotError - keys on different nodes
begin
  redis.mget("user:1000", "user:2000", "user:3000")
rescue RR::CrossSlotError => e
  puts e.message  # => "CROSSSLOT Keys in request don't hash to the same slot"
end

# Solution: Use hash tags or fetch individually
values = ["user:1000", "user:2000", "user:3000"].map { |key| redis.get(key) }
```

### WATCH/UNWATCH in Cluster Mode

WATCH and UNWATCH are routed to the node owning the watched keys' slot. All watched keys must hash to the same slot:

```ruby
# Works - all keys use same hash tag
redis.watch("user:{123}:balance", "user:{123}:pending") do
  balance = redis.get("user:{123}:balance").to_i
  redis.multi do |tx|
    tx.set("user:{123}:balance", balance - 100)
  end
end

# Raises CrossSlotError - keys span multiple slots
begin
  redis.watch("user:100", "user:200") do
    # ...
  end
rescue RR::CrossSlotError => e
  puts "Use hash tags: #{e.message}"
end
```

UNWATCH is automatically sent to the same node that received the WATCH command.

### Transactions in Cluster Mode

Transactions only work for keys on the same node:

```ruby
# Works - all keys use same hash tag
redis.multi do |tx|
  tx.set("cart:{user:100}:item:1", "Product A")
  tx.set("cart:{user:100}:item:2", "Product B")
  tx.incr("cart:{user:100}:count")
end

# Fails - keys on different nodes
begin
  redis.multi do |tx|
    tx.set("user:100", "Alice")
    tx.set("user:200", "Bob")  # Different slot!
  end
rescue RR::CrossSlotError => e
  puts "Transaction failed: #{e.message}"
end
```

### Cluster Error Handling

```ruby
begin
  redis.get("key")
rescue RR::CrossSlotError => e
  # Keys in a multi-key operation don't hash to the same slot
rescue RR::TryAgainError => e
  # Temporary error during slot migration (auto-retried by client)
rescue RR::ClusterDownError => e
  # Cluster is unavailable
rescue RR::ClusterError => e
  # Catch-all for cluster-related errors
end
```

## Cluster Commands

### Cluster Information

```ruby
# Get cluster state and statistics
info = redis.cluster_info
puts "Cluster state: #{info['cluster_state']}"
puts "Slots assigned: #{info['cluster_slots_assigned']}"
puts "Known nodes: #{info['cluster_known_nodes']}"

# Get information about all nodes
nodes = redis.cluster_nodes
# Returns string with node information (id, address, flags, slots, etc.)

# Get slot distribution
slots = redis.cluster_slots
# Returns: [[start_slot, end_slot, [master_host, master_port], [replica_host, replica_port]], ...]
```

### Node Management

```ruby
# Get node ID
node_id = redis.cluster_myid
# => "07c37dfeb235213a872192d90877d0cd55635b91"

# Count keys in current node's slots
count = redis.cluster_countkeysinslot(1000)

# Get keys in a specific slot
keys = redis.cluster_getkeysinslot(1000, 10)  # Get up to 10 keys from slot 1000
```

### Slot Management

```ruby
# Find which node owns a slot
node_addr = redis.node_for_slot(1000)
# => "node1.example.com:6379"

# Calculate slot for a key
slot = redis.key_slot("mykey")
# => 14687

# Set slot state (advanced - for cluster management)
redis.cluster_setslot(1000, :importing, node_id)
redis.cluster_setslot(1000, :migrating, node_id)
redis.cluster_setslot(1000, :stable)
redis.cluster_setslot(1000, :node, node_id)
```

## Failover Handling

### Automatic Failover

Redis Cluster automatically handles failover when a master fails:

```ruby
redis = RR.cluster(
  nodes: ["redis://node1:6379"],
  retry_count: 3  # Retry failed operations
)

# If a master fails during this operation:
# 1. Cluster promotes a replica to master
# 2. Client receives MOVED error
# 3. Client refreshes topology
# 4. Client retries on new master
redis.set("key", "value")
```

### Handling MOVED Redirections

The client automatically handles `MOVED` redirections:

```ruby
# Internally, when topology changes:
# 1. Client sends command to node A
# 2. Node A responds: "MOVED 3999 node-b:6379"
# 3. Client refreshes slot mapping
# 4. Client resends command to node B
# 5. Command succeeds

# This is transparent to your application
redis.get("mykey")  # Works even during topology changes
```

### Handling ASK Redirections

The client also handles `ASK` redirections during slot migration:

```ruby
# During slot migration:
# 1. Client sends command to source node
# 2. Source responds: "ASK 3999 target-node:6379"
# 3. Client sends ASKING to target node
# 4. Client resends original command to target node
# 5. Command succeeds

# This is also transparent
redis.get("migrating-key")  # Works during migrations
```

### Manual Topology Refresh

```ruby
# Force a topology refresh
redis.refresh_slots

# Check if cluster is healthy
if redis.cluster_healthy?
  puts "Cluster is operational"
else
  puts "Cluster has issues"
end
```

## Reading from Replicas

### Read Strategies

Configure where read operations are sent:

```ruby
# Read from masters only (default)
redis = RR.cluster(
  nodes: ["redis://node1:6379"],
  read_from: :master
)

# Read from replicas only
redis = RR.cluster(
  nodes: ["redis://node1:6379"],
  read_from: :replica
)

# Prefer replicas, fall back to master if no replica available
redis = RR.cluster(
  nodes: ["redis://node1:6379"],
  read_from: :replica_preferred
)
```

### Read-Only Operations

Only read operations are sent to replicas:

```ruby
redis = RR.cluster(
  nodes: ["redis://node1:6379"],
  read_from: :replica
)

# These go to replicas
redis.get("key")
redis.mget("key1", "key2")
redis.hgetall("hash")
redis.smembers("set")

# These always go to masters
redis.set("key", "value")
redis.incr("counter")
redis.sadd("set", "member")
```

### Benefits of Reading from Replicas

- **Reduced Master Load**: Distribute read traffic across replicas
- **Lower Latency**: Read from geographically closer replicas
- **Higher Throughput**: More nodes handling read requests

**Trade-off**: Eventual consistency - replicas may be slightly behind masters




## Best Practices

### 1. Use Hash Tags for Related Data

Always use hash tags to keep related data on the same node:

```ruby
# Good - related user data on same node
redis.hset("user:{1000}", "name", "Alice")
redis.hset("user:{1000}", "email", "alice@example.com")
redis.sadd("user:{1000}:sessions", "session-abc")

# Bad - data scattered across nodes
redis.hset("user:1000:profile", "name", "Alice")
redis.hset("user:1000:settings", "theme", "dark")
redis.sadd("user:1000:sessions", "session-abc")
```

### 2. Provide Multiple Seed Nodes

Always provide multiple seed nodes for redundancy:

```ruby
# Good - multiple seed nodes
redis = RR.cluster(
  nodes: [
    "redis://node1:6379",
    "redis://node2:6379",
    "redis://node3:6379"
  ]
)

# Acceptable - single seed node (client discovers others)
redis = RR.cluster(
  nodes: ["redis://node1:6379"]
)
```

### 3. Handle Cluster Errors Gracefully

```ruby
begin
  redis.set("key", "value")
rescue RR::ConnectionError => e
  # Cluster node unreachable
  logger.error("Cluster connection failed: #{e.message}")
  # Implement retry logic or fallback
rescue RR::Error => e
  if e.message.include?("CLUSTERDOWN")
    # Cluster is down or reconfiguring
    logger.error("Cluster is down: #{e.message}")
  else
    raise
  end
end
```

### 4. Use Appropriate Retry Settings

```ruby
# For critical operations
redis = RR.cluster(
  nodes: ["redis://node1:6379"],
  retry_count: 5  # More retries for important operations
)

# For non-critical operations
redis = RR.cluster(
  nodes: ["redis://node1:6379"],
  retry_count: 1  # Fail fast
)
```

### 5. Monitor Cluster Health

```ruby
# Periodic health check
def check_cluster_health(redis)
  info = redis.cluster_info

  if info["cluster_state"] != "ok"
    alert("Cluster state is #{info['cluster_state']}")
  end

  if info["cluster_slots_assigned"] < 16384
    alert("Not all slots assigned: #{info['cluster_slots_assigned']}/16384")
  end

  if info["cluster_slots_fail"] > 0
    alert("#{info['cluster_slots_fail']} slots in fail state")
  end
end
```

### 6. Use Host Translation for Docker/NAT

When cluster nodes announce IPs that aren't reachable (e.g., Docker internal IPs):

```ruby
redis = RR.cluster(
  nodes: ["redis://localhost:7000"],
  host_translation: {
    "172.17.0.2" => "localhost",  # Map Docker IP to localhost
    "172.17.0.3" => "localhost",
    "172.17.0.4" => "localhost"
  }
)
```

### 7. Avoid Cross-Slot Operations

```ruby
# Bad - will fail with CROSSSLOT error
begin
  redis.mget("user:1", "user:2", "user:3")
rescue RR::Error => e
  puts "Failed: #{e.message}"
end

# Good - use hash tags
redis.mget("user:{shard1}:1", "user:{shard1}:2", "user:{shard1}:3")

# Or fetch individually
users = [1, 2, 3].map { |id| redis.get("user:#{id}") }
```

### 8. Design Keys for Even Distribution

```ruby
# Good - keys distribute evenly across slots
redis.set("user:#{user_id}", data)
redis.set("session:#{session_id}", data)
redis.set("product:#{product_id}", data)

# Bad - all keys hash to same slot (hotspot)
redis.set("cache:{global}:users", data)
redis.set("cache:{global}:products", data)
redis.set("cache:{global}:sessions", data)
```

### 9. Consider Read Scaling

```ruby
# For read-heavy workloads
redis = RR.cluster(
  nodes: ["redis://node1:6379"],
  read_from: :replica_preferred  # Distribute reads to replicas
)

# For write-heavy or strong consistency needs
redis = RR.cluster(
  nodes: ["redis://node1:6379"],
  read_from: :master  # All operations on masters
)
```

### 10. Test Failover Scenarios

```ruby
# Simulate failover in tests
def test_failover_handling
  redis = RR.cluster(nodes: ["redis://node1:6379"])

  # Set initial value
  redis.set("test-key", "value")

  # Simulate master failure (in test environment)
  # ... trigger failover ...

  # Client should automatically handle failover
  assert_equal "value", redis.get("test-key")
end
```

## Common Patterns

### Session Storage with Cluster

```ruby
class SessionStore
  def initialize
    @redis = RR.cluster(
      nodes: ENV["REDIS_CLUSTER_NODES"].split(","),
      password: ENV["REDIS_PASSWORD"]
    )
  end

  def save_session(session_id, data)
    # Use hash tag to keep session data together
    key = "session:{#{session_id}}"
    @redis.setex(key, 3600, data.to_json)
  end

  def load_session(session_id)
    key = "session:{#{session_id}}"
    data = @redis.get(key)
    data ? JSON.parse(data) : nil
  end
end
```

### Distributed Counter

```ruby
class DistributedCounter
  def initialize(counter_name)
    @redis = RR.cluster(nodes: ["redis://node1:6379"])
    @counter_name = counter_name
  end

  def increment(amount = 1)
    # Counter key - will be on a specific node
    @redis.incrby(@counter_name, amount)
  end

  def value
    @redis.get(@counter_name).to_i
  end
end

# Usage
counter = DistributedCounter.new("page:views")
counter.increment
```

### Sharded Cache

```ruby
class ShardedCache
  def initialize
    @redis = RR.cluster(
      nodes: ["redis://node1:6379"],
      read_from: :replica_preferred
    )
  end

  def fetch(key, ttl: 3600)
    value = @redis.get(key)
    return value if value

    # Cache miss - compute and store
    value = yield
    @redis.setex(key, ttl, value)
    value
  end

  def fetch_multi(keys, ttl: 3600)
    # Group keys by hash tag for efficient multi-get
    keys.map { |key| fetch(key, ttl: ttl) { yield(key) } }
  end
end
```

## Troubleshooting

### CLUSTERDOWN Error

```ruby
# Cluster is not ready or has too many failed slots
# Check cluster status
info = redis.cluster_info
puts "State: #{info['cluster_state']}"
puts "Slots OK: #{info['cluster_slots_ok']}"
puts "Slots Fail: #{info['cluster_slots_fail']}"

# Wait for cluster to recover or fix manually
```

### MOVED Errors

```ruby
# Topology has changed - client automatically handles this
# If you see persistent MOVED errors, refresh topology
redis.refresh_slots
```

### Connection Timeouts

```ruby
# Increase timeout for slow networks
redis = RR.cluster(
  nodes: ["redis://node1:6379"],
  timeout: 10.0  # 10 seconds
)
```

### Cross-Slot Errors

```ruby
# Use hash tags to ensure keys are on same node
# Before: redis.mget("key1", "key2", "key3")  # CROSSSLOT error
# After:  redis.mget("key:{group}:1", "key:{group}:2", "key:{group}:3")
```

## Further Reading

- [Redis Cluster Specification](https://redis.io/docs/reference/cluster-spec/)
- [Redis Cluster Tutorial](https://redis.io/docs/management/scaling/)
- [Connections Guide](connections.md) - Connection options and configuration
- [Pipelines Guide](pipelines.md) - Using pipelines with cluster

