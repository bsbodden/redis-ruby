# Redis Enterprise Discovery Service

The Discovery Service is a Redis Enterprise/Redis Software feature that provides IP-based connection management for databases. It uses the Redis Sentinel API to discover which node hosts a database endpoint, making it easy to connect to databases without hardcoding IP addresses.

## Overview

The Discovery Service:
- Runs on **port 8001** on each node of a Redis Enterprise cluster
- Uses the **Sentinel-compatible API** for service discovery
- Provides automatic endpoint discovery for databases
- Handles topology changes (node failures, failovers, etc.)
- Supports both **external** and **internal** endpoints

## Basic Usage

### Connect to a Database

```ruby
require "redis_ruby"

client = RR.discovery(
  nodes: [
    { host: "node1.redis.example.com", port: 8001 },
    { host: "node2.redis.example.com", port: 8001 },
    { host: "node3.redis.example.com", port: 8001 }
  ],
  database_name: "my-database"
)

client.set("key", "value")
value = client.get("key")

client.close
```

### Connect to Internal Endpoint

For applications running inside the Redis Enterprise cluster network:

```ruby
client = RR.discovery(
  nodes: [{ host: "node1.redis.example.com" }],
  database_name: "my-database",
  internal: true  # Discovers internal endpoint
)
```

### With Authentication

```ruby
client = RR.discovery(
  nodes: [{ host: "node1.redis.example.com" }],
  database_name: "my-database",
  password: "your-password"
)
```

### With SSL/TLS

```ruby
client = RR.discovery(
  nodes: [{ host: "node1.redis.example.com" }],
  database_name: "my-database",
  ssl: true,
  ssl_params: {
    ca_file: "/path/to/ca.crt",
    verify_mode: OpenSSL::SSL::VERIFY_PEER
  }
)
```

## Advanced Usage

### Multiple Discovery Nodes

For high availability, provide multiple discovery service nodes:

```ruby
client = RR.discovery(
  nodes: [
    { host: "node1.redis.example.com", port: 8001 },
    { host: "node2.redis.example.com", port: 8001 },
    { host: "node3.redis.example.com", port: 8001 }
  ],
  database_name: "my-database"
)
```

The client will try each node in order until one succeeds.

### Custom Timeout

```ruby
client = RR.discovery(
  nodes: [{ host: "node1.redis.example.com" }],
  database_name: "my-database",
  timeout: 10.0  # 10 seconds
)
```

### Reconnection Handling

The client automatically handles reconnections when the database endpoint changes:

```ruby
client = RR.discovery(
  nodes: [{ host: "node1.redis.example.com" }],
  database_name: "my-database",
  reconnect_attempts: 5  # Retry up to 5 times
)

# Client automatically discovers new endpoint on failover
client.set("key", "value")
```

## How It Works

1. **Discovery**: Client queries the Discovery Service on port 8001 using the Sentinel API
2. **Endpoint Resolution**: Discovery Service returns the current host and port for the database
3. **Connection**: Client connects to the discovered endpoint
4. **Automatic Failover**: On connection failure, client re-queries Discovery Service for updated endpoint

### Discovery Service API

The Discovery Service uses the Redis Sentinel API:

```
SENTINEL get-master-addr-by-name <database-name>
```

Returns:
```
1) "10.0.0.45"    # Host
2) "12000"        # Port
```

For internal endpoints, append `@internal` to the database name:
```
SENTINEL get-master-addr-by-name my-database@internal
```

## Best Practices

### 1. Use Multiple Discovery Nodes

Always provide multiple discovery service nodes for high availability:

```ruby
nodes: [
  { host: "node1.redis.example.com", port: 8001 },
  { host: "node2.redis.example.com", port: 8001 },
  { host: "node3.redis.example.com", port: 8001 }
]
```

### 2. Choose the Right Endpoint Type

- **External endpoints**: For applications outside the cluster network
- **Internal endpoints**: For applications inside the cluster network (better performance)

### 3. Handle Connection Errors

```ruby
begin
  client = RR.discovery(
    nodes: [{ host: "node1.redis.example.com" }],
    database_name: "my-database"
  )
  client.set("key", "value")
rescue RR::DiscoveryServiceError => e
  puts "Failed to discover database: #{e.message}"
rescue RR::ConnectionError => e
  puts "Connection failed: #{e.message}"
end
```

## Comparison with Other Clients

### redis-py (Python)
```python
from redis.sentinel import Sentinel

sentinel = Sentinel([('node1', 8001)], socket_timeout=0.1)
master = sentinel.master_for('my-database', socket_timeout=0.1)
```

### Jedis (Java)
```java
Set<String> sentinels = new HashSet<>();
sentinels.add("node1:8001");
JedisSentinelPool pool = new JedisSentinelPool("my-database", sentinels);
```

### redis-ruby
```ruby
client = RR.discovery(
  nodes: [{ host: "node1", port: 8001 }],
  database_name: "my-database"
)
```

## See Also

- [Redis Enterprise Discovery Service Documentation](https://redis.io/docs/latest/operate/rs/databases/durability-ha/discovery-service/)
- [Sentinel Client Guide](sentinel.md)
- [Connection Management](connection-management.md)

