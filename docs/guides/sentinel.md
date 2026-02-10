---
layout: default
title: Redis Sentinel
parent: Guides
nav_order: 7
---

# Redis Sentinel

This guide covers Redis Sentinel support in redis-ruby, including automatic master discovery, failover handling, and best practices for highly available Redis deployments.

## Table of Contents

- [What is Redis Sentinel](#what-is-redis-sentinel)
- [Connecting to Sentinel](#connecting-to-sentinel)
- [Master Discovery](#master-discovery)
- [Automatic Failover](#automatic-failover)
- [Sentinel Configuration](#sentinel-configuration)
- [Monitoring](#monitoring)
- [Sentinel Commands](#sentinel-commands)
- [Best Practices](#best-practices)

## What is Redis Sentinel

Redis Sentinel provides high availability for Redis through:

- **Monitoring**: Continuously checks if master and replica instances are working
- **Notification**: Alerts administrators or applications about failures
- **Automatic Failover**: Promotes a replica to master when the master fails
- **Configuration Provider**: Clients discover the current master address

### Key Concepts

- **Sentinel Nodes**: Independent processes that monitor Redis instances
- **Quorum**: Minimum number of Sentinels that must agree a master is down
- **Master Discovery**: Clients query Sentinels to find the current master
- **Failover**: Automatic promotion of replica to master when master fails

## Connecting to Sentinel

### Basic Connection

Connect to Redis through Sentinel by providing Sentinel addresses and service name:

```ruby
require "redis_ruby"

# Connect to master through Sentinel
redis = RedisRuby.sentinel(
  sentinels: [
    { host: "sentinel1.example.com", port: 26379 },
    { host: "sentinel2.example.com", port: 26379 },
    { host: "sentinel3.example.com", port: 26379 }
  ],
  service_name: "mymaster"
)

# Client automatically discovers and connects to current master
redis.set("key", "value")
redis.get("key")  # => "value"
```

### Connection with Authentication

```ruby
# Redis password
redis = RedisRuby.sentinel(
  sentinels: [{ host: "sentinel1", port: 26379 }],
  service_name: "mymaster",
  password: "redis-password"
)

# Sentinel password (if Sentinels require authentication)
redis = RedisRuby.sentinel(
  sentinels: [{ host: "sentinel1", port: 26379 }],
  service_name: "mymaster",
  password: "redis-password",
  sentinel_password: "sentinel-password"
)
```

### Connection Options

```ruby
redis = RedisRuby.sentinel(
  sentinels: [{ host: "sentinel1", port: 26379 }],
  service_name: "mymaster",
  role: :master,                    # :master or :replica
  password: nil,                    # Redis password
  sentinel_password: nil,           # Sentinel password
  db: 0,                            # Database number
  timeout: 5.0,                     # Connection timeout
  ssl: false,                       # Enable SSL/TLS
  ssl_params: {},                   # SSL parameters
  reconnect_attempts: 3,            # Retry attempts on failure
  min_other_sentinels: 0            # Minimum peer sentinels required
)
```

### Using SentinelClient Directly

```ruby
require "redis_ruby/sentinel_client"

client = RedisRuby::SentinelClient.new(
  sentinels: [
    { host: "sentinel1", port: 26379 },
    { host: "sentinel2", port: 26379 }
  ],
  service_name: "mymaster",
  role: :master
)

client.set("key", "value")
```

## Master Discovery

### How Master Discovery Works

The client discovers the current master through Sentinels:

1. Client connects to first available Sentinel
2. Queries Sentinel for master address: `SENTINEL GET-MASTER-ADDR-BY-NAME mymaster`
3. Validates master state using `SENTINEL MASTERS`
4. Connects to discovered master
5. Verifies role with `ROLE` command

```ruby
redis = RedisRuby.sentinel(
  sentinels: [
    { host: "sentinel1", port: 26379 },
    { host: "sentinel2", port: 26379 }
  ],
  service_name: "mymaster"
)

# Client automatically discovers master
# No need to know master address in advance
redis.ping  # => "PONG"
```

### Sentinel Failover

If the first Sentinel is unavailable, the client tries the next:

```ruby
# Even if sentinel1 is down, client will try sentinel2 and sentinel3
redis = RedisRuby.sentinel(
  sentinels: [
    { host: "sentinel1", port: 26379 },  # Down
    { host: "sentinel2", port: 26379 },  # Will try this
    { host: "sentinel3", port: 26379 }   # Or this
  ],
  service_name: "mymaster"
)
```

## Automatic Failover

### How Failover Works

When a master fails, Sentinel automatically promotes a replica:

1. Sentinels detect master is down (quorum agreement)
2. Sentinels elect a leader to perform failover
3. Leader promotes best replica to master
4. Other replicas reconfigured to replicate from new master
5. Clients detect failover and reconnect to new master

### Client Failover Handling

The client automatically handles failover:

```ruby
redis = RedisRuby.sentinel(
  sentinels: [{ host: "sentinel1", port: 26379 }],
  service_name: "mymaster",
  reconnect_attempts: 3
)

# During failover:
# 1. Master goes down
# 2. Client gets connection error
# 3. Client queries Sentinel for new master
# 4. Client connects to new master
# 5. Operation retries automatically

redis.set("key", "value")  # Succeeds even during failover
```

### Handling READONLY Errors

When connected to a replica that gets promoted:

```ruby
# Client connected to replica
# Replica gets promoted to master
# Client receives READONLY error
# Client automatically:
# 1. Detects failover via READONLY error
# 2. Queries Sentinel for new master
# 3. Reconnects to new master
# 4. Retries operation

redis.set("key", "value")  # Works transparently
```

### Manual Reconnection

Force reconnection to discover new master:

```ruby
# Check current connection
puts "Connected to: #{redis.current_address.inspect}"
# => { host: "master1", port: 6379 }

# Force reconnection (e.g., after known failover)
redis.reconnect

# Now connected to new master
puts "Connected to: #{redis.current_address.inspect}"
# => { host: "master2", port: 6379 }
```

### Failover Detection

```ruby
# Check if connected to master or replica
if redis.master?
  puts "Connected to master"
else
  puts "Connected to replica"
end

# Get current connection address
address = redis.current_address
puts "Connected to #{address[:host]}:#{address[:port]}"
```

## Sentinel Configuration

### Minimum Sentinel Setup

For production, use at least 3 Sentinels:

```ruby
# Minimum recommended setup
redis = RedisRuby.sentinel(
  sentinels: [
    { host: "sentinel1", port: 26379 },
    { host: "sentinel2", port: 26379 },
    { host: "sentinel3", port: 26379 }
  ],
  service_name: "mymaster"
)
```

### Quorum Configuration

Ensure Sentinel quorum is configured correctly:

```conf
# sentinel.conf
sentinel monitor mymaster 127.0.0.1 6379 2  # Quorum of 2

# With 3 Sentinels and quorum of 2:
# - 2 Sentinels must agree master is down
# - Tolerates 1 Sentinel failure
```

### Sentinel Discovery

The client automatically discovers other Sentinels:

```ruby
# Provide just one Sentinel
redis = RedisRuby.sentinel(
  sentinels: [{ host: "sentinel1", port: 26379 }],
  service_name: "mymaster"
)

# Client queries sentinel1 for other Sentinels
# Builds complete Sentinel list automatically
```

### Minimum Other Sentinels

Require minimum number of peer Sentinels:

```ruby
redis = RedisRuby.sentinel(
  sentinels: [{ host: "sentinel1", port: 26379 }],
  service_name: "mymaster",
  min_other_sentinels: 2  # Require at least 2 other Sentinels
)

# Raises error if fewer than 2 peer Sentinels are found
```

## Monitoring

### Sentinel Health Checks

Monitor Sentinel health:

```ruby
# Connect directly to Sentinel
sentinel = RedisRuby::Client.new(host: "sentinel1", port: 26379)

# Ping Sentinel
sentinel.call("PING")  # => "PONG"

# Get Sentinel info
info = sentinel.call("SENTINEL", "MASTERS")
# Returns array of master information
```

### Master Health

Check master health through Sentinel:

```ruby
sentinel = RedisRuby::Client.new(host: "sentinel1", port: 26379)

# Get master address
address = sentinel.call("SENTINEL", "GET-MASTER-ADDR-BY-NAME", "mymaster")
# => ["127.0.0.1", "6379"]

# Get detailed master info
masters = sentinel.call("SENTINEL", "MASTERS")
master_info = masters.first

puts "Master: #{master_info['name']}"
puts "Status: #{master_info['flags']}"
puts "Quorum: #{master_info['quorum']}"
puts "Replicas: #{master_info['num-slaves']}"
```

### Replica Health

Check replica status:

```ruby
sentinel = RedisRuby::Client.new(host: "sentinel1", port: 26379)

# Get all replicas for a master
replicas = sentinel.call("SENTINEL", "REPLICAS", "mymaster")

replicas.each do |replica|
  puts "Replica: #{replica['name']}"
  puts "Status: #{replica['flags']}"
  puts "Lag: #{replica['master-link-down-time']}"
end
```

### Monitoring Failovers

```ruby
# Subscribe to Sentinel events (requires pub/sub)
sentinel = RedisRuby::Client.new(host: "sentinel1", port: 26379)

sentinel.subscribe("+switch-master", "+sdown", "+odown") do |event, data|
  case event
  when "+switch-master"
    puts "Failover completed: #{data}"
  when "+sdown"
    puts "Subjectively down: #{data}"
  when "+odown"
    puts "Objectively down: #{data}"
  end
end
```

## Sentinel Commands

### Master Information

```ruby
sentinel = RedisRuby::Client.new(host: "sentinel1", port: 26379)

# Get all monitored masters
masters = sentinel.call("SENTINEL", "MASTERS")

# Get specific master info
master = sentinel.call("SENTINEL", "MASTER", "mymaster")

# Get master address
address = sentinel.call("SENTINEL", "GET-MASTER-ADDR-BY-NAME", "mymaster")
# => ["127.0.0.1", "6379"]
```

### Replica Information

```ruby
# Get all replicas for a master
replicas = sentinel.call("SENTINEL", "REPLICAS", "mymaster")

# Each replica includes:
# - name, ip, port
# - flags (e.g., "slave", "s_down", "o_down")
# - master-link-status
# - master-link-down-time
```

### Sentinel Information

```ruby
# Get other Sentinels monitoring this master
sentinels = sentinel.call("SENTINEL", "SENTINELS", "mymaster")

# Get Sentinel's own ID
sentinel_id = sentinel.call("SENTINEL", "MYID")
# => "a1b2c3d4e5f6..."
```

### Manual Failover

```ruby
# Force a failover (for testing or maintenance)
sentinel.call("SENTINEL", "FAILOVER", "mymaster")
# => "OK"

# Sentinel will:
# 1. Select best replica
# 2. Promote it to master
# 3. Reconfigure other replicas
```

### Check Quorum

```ruby
# Verify quorum configuration
result = sentinel.call("SENTINEL", "CKQUORUM", "mymaster")
# => "OK 3 usable Sentinels. Quorum and failover authorization can be reached"
```


## Best Practices

### 1. Use Multiple Sentinels

Always deploy at least 3 Sentinels for production:

```ruby
# Good - 3 Sentinels for high availability
redis = RedisRuby.sentinel(
  sentinels: [
    { host: "sentinel1", port: 26379 },
    { host: "sentinel2", port: 26379 },
    { host: "sentinel3", port: 26379 }
  ],
  service_name: "mymaster"
)

# Bad - single Sentinel (single point of failure)
redis = RedisRuby.sentinel(
  sentinels: [{ host: "sentinel1", port: 26379 }],
  service_name: "mymaster"
)
```

### 2. Configure Appropriate Quorum

Set quorum to majority of Sentinels:

```conf
# For 3 Sentinels, use quorum of 2
sentinel monitor mymaster 127.0.0.1 6379 2

# For 5 Sentinels, use quorum of 3
sentinel monitor mymaster 127.0.0.1 6379 3
```

### 3. Handle Failover Gracefully

```ruby
redis = RedisRuby.sentinel(
  sentinels: [{ host: "sentinel1", port: 26379 }],
  service_name: "mymaster",
  reconnect_attempts: 3  # Retry during failover
)

begin
  redis.set("key", "value")
rescue RedisRuby::ConnectionError => e
  # Failover in progress
  logger.warn("Connection failed during failover: #{e.message}")
  # Client will retry automatically
rescue RedisRuby::Error => e
  logger.error("Redis error: #{e.message}")
  raise
end
```

### 4. Monitor Sentinel Health

```ruby
def check_sentinel_health(sentinels)
  sentinels.each do |sentinel_config|
    begin
      sentinel = RedisRuby::Client.new(
        host: sentinel_config[:host],
        port: sentinel_config[:port],
        timeout: 1.0
      )

      # Check Sentinel is responsive
      sentinel.call("PING")

      # Check it knows about the master
      address = sentinel.call("SENTINEL", "GET-MASTER-ADDR-BY-NAME", "mymaster")

      puts "✓ Sentinel #{sentinel_config[:host]} is healthy"
      puts "  Master: #{address.join(':')}"
    rescue => e
      puts "✗ Sentinel #{sentinel_config[:host]} is down: #{e.message}"
    ensure
      sentinel&.close
    end
  end
end
```

### 5. Use Appropriate Timeouts

```ruby
# For local network
redis = RedisRuby.sentinel(
  sentinels: [{ host: "sentinel1", port: 26379 }],
  service_name: "mymaster",
  timeout: 1.0  # 1 second
)

# For remote/slow network
redis = RedisRuby.sentinel(
  sentinels: [{ host: "sentinel1", port: 26379 }],
  service_name: "mymaster",
  timeout: 5.0  # 5 seconds
)
```

### 6. Separate Sentinel and Redis Networks

Deploy Sentinels on different network segments than Redis:

```ruby
# Sentinels on management network
# Redis on data network
redis = RedisRuby.sentinel(
  sentinels: [
    { host: "mgmt-sentinel1.example.com", port: 26379 },
    { host: "mgmt-sentinel2.example.com", port: 26379 },
    { host: "mgmt-sentinel3.example.com", port: 26379 }
  ],
  service_name: "mymaster"
)
```

### 7. Test Failover Regularly

```ruby
# Automated failover test
def test_failover
  redis = RedisRuby.sentinel(
    sentinels: [{ host: "sentinel1", port: 26379 }],
    service_name: "mymaster"
  )

  # Get current master
  original_master = redis.current_address

  # Trigger failover
  sentinel = RedisRuby::Client.new(host: "sentinel1", port: 26379)
  sentinel.call("SENTINEL", "FAILOVER", "mymaster")

  # Wait for failover
  sleep 5

  # Verify new master
  redis.reconnect
  new_master = redis.current_address

  assert new_master != original_master, "Failover did not occur"
  assert redis.ping == "PONG", "New master not responding"
end
```

### 8. Use Read Replicas for Scaling

```ruby
# Write to master
writer = RedisRuby.sentinel(
  sentinels: [{ host: "sentinel1", port: 26379 }],
  service_name: "mymaster",
  role: :master
)

# Read from replica
reader = RedisRuby.sentinel(
  sentinels: [{ host: "sentinel1", port: 26379 }],
  service_name: "mymaster",
  role: :replica
)

# Write operations
writer.set("key", "value")

# Read operations (may be slightly stale)
reader.get("key")
```

### 9. Configure Sentinel Properly

```conf
# sentinel.conf

# Monitor master
sentinel monitor mymaster 127.0.0.1 6379 2

# Authentication
sentinel auth-pass mymaster your-redis-password

# Timeouts
sentinel down-after-milliseconds mymaster 5000
sentinel failover-timeout mymaster 60000

# Parallel syncs
sentinel parallel-syncs mymaster 1

# Notification scripts
sentinel notification-script mymaster /path/to/notify.sh
sentinel client-reconfig-script mymaster /path/to/reconfig.sh
```

### 10. Log and Alert on Failovers

```ruby
class SentinelMonitor
  def initialize(sentinels, service_name)
    @sentinel = RedisRuby::Client.new(
      host: sentinels.first[:host],
      port: sentinels.first[:port]
    )
    @service_name = service_name
  end

  def monitor_failovers
    @sentinel.subscribe("+switch-master") do |event, data|
      # data format: "mymaster 127.0.0.1 6379 127.0.0.1 6380"
      parts = data.split
      old_master = "#{parts[1]}:#{parts[2]}"
      new_master = "#{parts[3]}:#{parts[4]}"

      alert_failover(old_master, new_master)
    end
  end

  def alert_failover(old_master, new_master)
    message = "Failover: #{@service_name} from #{old_master} to #{new_master}"
    logger.warn(message)
    # Send to monitoring system
    # send_to_pagerduty(message)
    # send_to_slack(message)
  end
end
```

## Common Patterns

### High Availability Setup

```ruby
class RedisConnection
  def self.create
    RedisRuby.sentinel(
      sentinels: ENV["REDIS_SENTINELS"].split(",").map do |s|
        host, port = s.split(":")
        { host: host, port: port.to_i }
      end,
      service_name: ENV["REDIS_SERVICE_NAME"],
      password: ENV["REDIS_PASSWORD"],
      reconnect_attempts: 3
    )
  end
end

# Usage
redis = RedisConnection.create
```

### Read/Write Splitting

```ruby
class RedisPool
  def initialize
    @writer = RedisRuby.sentinel(
      sentinels: sentinels,
      service_name: "mymaster",
      role: :master
    )

    @reader = RedisRuby.sentinel(
      sentinels: sentinels,
      service_name: "mymaster",
      role: :replica
    )
  end

  def write(&block)
    block.call(@writer)
  end

  def read(&block)
    block.call(@reader)
  end

  private

  def sentinels
    [
      { host: "sentinel1", port: 26379 },
      { host: "sentinel2", port: 26379 },
      { host: "sentinel3", port: 26379 }
    ]
  end
end

# Usage
pool = RedisPool.new
pool.write { |redis| redis.set("key", "value") }
pool.read { |redis| redis.get("key") }
```

### Graceful Degradation

```ruby
class CacheWithFallback
  def initialize
    @redis = RedisRuby.sentinel(
      sentinels: [{ host: "sentinel1", port: 26379 }],
      service_name: "mymaster",
      reconnect_attempts: 2
    )
    @local_cache = {}
  end

  def get(key)
    @redis.get(key)
  rescue RedisRuby::Error => e
    logger.warn("Redis unavailable, using local cache: #{e.message}")
    @local_cache[key]
  end

  def set(key, value)
    @redis.set(key, value)
    @local_cache[key] = value
  rescue RedisRuby::Error => e
    logger.warn("Redis unavailable, storing in local cache: #{e.message}")
    @local_cache[key] = value
  end
end
```

## Troubleshooting

### Master Not Found

```ruby
# Error: "No master found for 'mymaster'"

# Check Sentinels are running
sentinel = RedisRuby::Client.new(host: "sentinel1", port: 26379)
sentinel.call("PING")  # Should return "PONG"

# Check master is configured
masters = sentinel.call("SENTINEL", "MASTERS")
puts masters.inspect

# Check master address
address = sentinel.call("SENTINEL", "GET-MASTER-ADDR-BY-NAME", "mymaster")
puts address.inspect
```

### Connection Timeouts

```ruby
# Increase timeout
redis = RedisRuby.sentinel(
  sentinels: [{ host: "sentinel1", port: 26379 }],
  service_name: "mymaster",
  timeout: 10.0  # Increase from default 5.0
)
```

### Frequent Failovers

```conf
# Increase down-after-milliseconds in sentinel.conf
sentinel down-after-milliseconds mymaster 10000  # 10 seconds instead of 5

# Increase failover timeout
sentinel failover-timeout mymaster 120000  # 2 minutes
```

### READONLY Errors

```ruby
# Client connected to replica but trying to write
# Solution: Ensure role is :master for write operations
redis = RedisRuby.sentinel(
  sentinels: [{ host: "sentinel1", port: 26379 }],
  service_name: "mymaster",
  role: :master  # Not :replica
)
```

## Further Reading

- [Redis Sentinel Documentation](https://redis.io/docs/management/sentinel/)
- [Sentinel Configuration](https://redis.io/docs/management/sentinel/#configuring-sentinel)
- [Connections Guide](connections.md) - Connection options and configuration
- [Cluster Guide](cluster.md) - Alternative scaling solution



