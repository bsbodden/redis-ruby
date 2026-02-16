# DNS-Based Load Balancing

redis-ruby provides DNS-based load balancing for Redis connections, allowing you to distribute connections across multiple Redis instances using DNS resolution with multiple A records.

## Overview

DNS-based load balancing is particularly useful for:

- **Redis Enterprise Active-Active databases** with multiple endpoints
- **Load balancing** across multiple Redis instances
- **High availability** with automatic failover to different IPs
- **Dynamic infrastructure** where IPs change frequently

When a hostname resolves to multiple IP addresses (multiple A records), the DNS client can use different strategies to select which IP to connect to, providing automatic load distribution and failover capabilities.

## Basic Usage

### Simple Connection

```ruby
require "redis_ruby"

# Connect to Redis using DNS resolution
client = RR.dns(
  hostname: "redis.example.com",
  port: 6379
)

client.set("key", "value")
value = client.get("key")
puts value  # => "value"

client.close
```

### With Authentication

```ruby
client = RR.dns(
  hostname: "redis.example.com",
  port: 6379,
  password: "your-password"
)
```

### With SSL/TLS

```ruby
client = RR.dns(
  hostname: "redis.example.com",
  port: 6380,
  ssl: true,
  ssl_params: {
    ca_file: "/path/to/ca.crt",
    verify_mode: OpenSSL::SSL::VERIFY_PEER
  }
)
```

## Load Balancing Strategies

### Round-Robin (Default)

Round-robin distributes connections evenly across all resolved IPs in a circular fashion.

```ruby
client = RR.dns(
  hostname: "redis.example.com",
  port: 6379,
  dns_strategy: :round_robin  # Default
)

# If DNS resolves to [10.0.0.1, 10.0.0.2, 10.0.0.3]:
# 1st connection -> 10.0.0.1
# 2nd connection -> 10.0.0.2
# 3rd connection -> 10.0.0.3
# 4th connection -> 10.0.0.1 (wraps around)
```

### Random

Random strategy selects a random IP from the resolved list for each connection.

```ruby
client = RR.dns(
  hostname: "redis.example.com",
  port: 6379,
  dns_strategy: :random
)

# Each connection attempt uses a random IP from the resolved list
```

## Advanced Usage

### Automatic Failover

The DNS client automatically tries different IPs on connection failure:

```ruby
client = RR.dns(
  hostname: "redis.example.com",
  port: 6379,
  reconnect_attempts: 3  # Try up to 3 different IPs on failure
)

# If connection to first IP fails, automatically tries next IP
client.set("key", "value")
```

### Manual DNS Refresh

Force DNS re-resolution to pick up IP changes:

```ruby
client = RR.dns(
  hostname: "redis.example.com",
  port: 6379
)

# ... use client ...

# Force DNS refresh (useful when IPs change)
client.refresh_dns

# Next command will use newly resolved IPs
client.set("key", "value")
```

### Database Selection

```ruby
client = RR.dns(
  hostname: "redis.example.com",
  port: 6379,
  db: 1  # Select database 1
)
```

## How It Works

1. **DNS Resolution**: The client resolves the hostname to one or more IP addresses using Ruby's `Resolv` library
2. **IP Selection**: Based on the strategy (round-robin or random), an IP is selected from the resolved list
3. **Connection**: A connection is established to the selected IP
4. **Failover**: If connection fails, the client tries the next IP in the list (up to `reconnect_attempts` times)
5. **Caching**: Resolved IPs are cached until `refresh_dns` is called or all connections fail

## Best Practices

### 1. Use Round-Robin for Even Distribution

```ruby
# Best for distributing load evenly across all instances
client = RR.dns(
  hostname: "redis.example.com",
  port: 6379,
  dns_strategy: :round_robin
)
```

### 2. Use Random for Stateless Workloads

```ruby
# Best for completely stateless operations
client = RR.dns(
  hostname: "redis.example.com",
  port: 6379,
  dns_strategy: :random
)
```

### 3. Set Appropriate Reconnect Attempts

```ruby
# Set based on number of expected IPs
client = RR.dns(
  hostname: "redis.example.com",
  port: 6379,
  reconnect_attempts: 5  # Try up to 5 different IPs
)
```

### 4. Disable DNS Caching for Dynamic Environments

For environments where IPs change frequently (like Redis Enterprise Active-Active), consider periodically calling `refresh_dns`:

```ruby
client = RR.dns(hostname: "redis.example.com", port: 6379)

# In a background thread or periodic task
Thread.new do
  loop do
    sleep 60  # Refresh every 60 seconds
    client.refresh_dns
  end
end
```

## Comparison with Other Clients

### redis-py (Python)

redis-py doesn't have built-in DNS load balancing. Users typically rely on external load balancers or DNS round-robin at the OS level.

### Jedis (Java)

Jedis recommends disabling JVM DNS caching for Active-Active scenarios:

```java
// Jedis recommendation
java.security.Security.setProperty("networkaddress.cache.ttl", "0");
```

redis-ruby handles this automatically by re-resolving DNS on connection failures.

### Lettuce (Java)

Lettuce supports DNS resolution but doesn't provide built-in load balancing strategies. redis-ruby provides both round-robin and random strategies out of the box.

## See Also

- [Discovery Service Guide](discovery-service.md) - For Redis Enterprise Discovery Service
- [Sentinel Guide](sentinel.md) - For Redis Sentinel high availability
- [Cluster Guide](cluster.md) - For Redis Cluster deployments

