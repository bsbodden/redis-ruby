---
layout: default
title: Health Checks
parent: Guides
nav_order: 12
---

# Health Checks
{: .no_toc }

Comprehensive guide to implementing health checks for Redis connections in production environments.
{: .fs-6 .fw-300 }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

Health checks are essential for maintaining reliable Redis connections in production. redis-ruby provides multiple health check strategies to verify connection health and automatically recover from failures.

## Health Check Strategies

### Ping Check

The simplest health check strategy using Redis PING command:

```ruby
require 'redis_ruby'

# Create a ping-based health check
health_check = RR::HealthCheck::Ping.new

# Check connection health
client = RR::Client.new(host: 'localhost', port: 6379)
if health_check.check(client.connection)
  puts "Connection is healthy"
else
  puts "Connection is unhealthy"
end
```

### Info Check

Use Redis INFO command for more detailed health verification:

```ruby
# Basic INFO check
info_check = RR::HealthCheck::Info.new

# INFO check with specific section
server_check = RR::HealthCheck::Info.new(section: "server")

# INFO check with custom validation
loading_check = RR::HealthCheck::Info.new do |info|
  info["loading"] == "0" && info["uptime_in_seconds"].to_i > 60
end

# Check connection
if loading_check.check(client.connection)
  puts "Server is ready and not loading"
end
```

### Custom Check

Create custom health checks for specific requirements:

```ruby
# Check if a specific key exists
key_check = RR::HealthCheck::Custom.new("EXISTS", "health:check:key")

# Check with custom validation
version_check = RR::HealthCheck::Custom.new("GET", "config:version") do |result|
  result == "1.0.0"
end

# Complex custom check with multiple commands
complex_check = RR::HealthCheck::Custom.new do |conn|
  conn.call("PING") == "PONG" &&
    conn.call("DBSIZE").is_a?(Integer) &&
    conn.call("INFO", "memory")["used_memory_rss"].to_i < 1_000_000_000
end
```

## Background Health Monitoring

Use the health check runner for continuous monitoring:

```ruby
# Create health check runner
runner = RR::HealthCheck::Runner.new(
  connection: client.connection,
  health_check: RR::HealthCheck::Ping.new,
  interval: 5.0  # Check every 5 seconds
)

# Start background monitoring
runner.start

# Check current status
if runner.healthy?
  puts "Connection is healthy"
else
  puts "Connection is unhealthy"
end

# Stop monitoring
runner.stop
```

## Connection Pool Health Checks

Integrate health checks with connection pools:

```ruby
# Create pool with automatic health checks
pool = RR::Connection::Pool.new(
  host: 'localhost',
  port: 6379,
  size: 10,
  health_check_interval: 30.0  # Check every 30 seconds
)

# Health checks run automatically before commands
pool.with do |conn|
  conn.call("GET", "mykey")
end
```

## Production Configuration

### High-Availability Setup

```ruby
# Production configuration with health checks
client = RR::PooledClient.new(
  host: 'redis.example.com',
  port: 6379,
  pool: {
    size: 20,
    timeout: 5.0,
    health_check_interval: 10.0
  }
)
```

### Custom Health Check Strategy

```ruby
# Create custom health check for your application
class ApplicationHealthCheck < RR::HealthCheck::Base
  def check(connection)
    return false unless connection.connected?
    
    # Check application-specific requirements
    result = connection.call("GET", "app:status")
    result == "ready"
  rescue StandardError => e
    warn "Health check failed: #{e.message}"
    false
  end
end

# Use custom health check
runner = RR::HealthCheck::Runner.new(
  connection: client.connection,
  health_check: ApplicationHealthCheck.new,
  interval: 5.0
)
runner.start
```

## Best Practices

1. **Choose the Right Strategy**: Use PING for simple checks, INFO for detailed validation, Custom for application-specific requirements
2. **Set Appropriate Intervals**: Balance between responsiveness and overhead (10-30 seconds is typical)
3. **Handle Failures Gracefully**: Combine health checks with circuit breakers and retry logic
4. **Monitor Health Check Metrics**: Track health check success/failure rates
5. **Use Connection Pools**: Enable automatic health checks at the pool level

## Troubleshooting

### Health Checks Failing

```ruby
# Add logging to diagnose issues
health_check = RR::HealthCheck::Info.new do |info|
  puts "Server info: #{info.inspect}"
  info["loading"] == "0"
end
```

### Performance Impact

```ruby
# Reduce health check frequency if needed
pool = RR::Connection::Pool.new(
  host: 'localhost',
  port: 6379,
  health_check_interval: 60.0  # Check every minute
)
```

## See Also

- [Circuit Breaker Guide](circuit-breaker.md)
- [Retry Logic Guide](retry-logic.md)
- [Connection Pooling Guide](connection-pooling.md)

