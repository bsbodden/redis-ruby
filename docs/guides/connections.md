---
layout: default
title: Connection Options
parent: Guides
nav_order: 1
---

# Connection Options

This guide covers all the ways to connect to Redis using redis-ruby, from basic TCP connections to advanced TLS/SSL configurations.

## Table of Contents

- [Basic TCP Connections](#basic-tcp-connections)
- [Unix Socket Connections](#unix-socket-connections)
- [TLS/SSL Connections](#tlsssl-connections)
- [Connection URLs](#connection-urls)
- [Connection Options](#connection-options)
- [RESP3 Protocol](#resp3-protocol)
- [Authentication](#authentication)
- [Database Selection](#database-selection)
- [Retry and Reconnection](#retry-and-reconnection)

## Basic TCP Connections

The simplest way to connect to Redis is using TCP:

```ruby
require "redis_ruby"

# Connect to localhost:6379 (default)
redis = RedisRuby.new

# Connect to a specific host and port
redis = RedisRuby.new(host: "redis.example.com", port: 6379)

# Test the connection
redis.ping  # => "PONG"
```

### Connection Options

```ruby
redis = RedisRuby.new(
  host: "localhost",
  port: 6379,
  db: 0,                    # Database number (default: 0)
  timeout: 5.0,             # Connection timeout in seconds (default: 5.0)
  password: "secret",       # Redis password (if required)
  username: "default"       # Redis username for ACL (Redis 6+)
)
```

## Unix Socket Connections

For local Redis instances, Unix sockets provide better performance than TCP:

```ruby
# Using path parameter
redis = RedisRuby.new(path: "/var/run/redis/redis.sock")

# Using URL
redis = RedisRuby.new(url: "unix:///var/run/redis/redis.sock")

# With database selection
redis = RedisRuby.new(
  path: "/var/run/redis/redis.sock",
  db: 1
)
```

### Performance Benefits

Unix sockets eliminate TCP/IP overhead and are ideal for:
- Local development
- Same-machine deployments
- High-performance applications
- Reduced latency requirements

## TLS/SSL Connections

For secure connections to Redis (production, Redis Cloud, etc.):

```ruby
# Basic TLS connection
redis = RedisRuby.new(
  host: "redis.example.com",
  port: 6380,
  ssl: true
)

# Using rediss:// URL (note the double 's')
redis = RedisRuby.new(url: "rediss://redis.example.com:6380")
```

### Advanced SSL Configuration

```ruby
require "openssl"

redis = RedisRuby.new(
  host: "redis.example.com",
  port: 6380,
  ssl: true,
  ssl_params: {
    # Verify server certificate
    verify_mode: OpenSSL::SSL::VERIFY_PEER,
    
    # Custom CA certificate
    ca_file: "/path/to/ca-cert.pem",
    
    # Client certificate authentication
    cert: OpenSSL::X509::Certificate.new(File.read("/path/to/client-cert.pem")),
    key: OpenSSL::PKey::RSA.new(File.read("/path/to/client-key.pem")),
    
    # Minimum TLS version
    min_version: OpenSSL::SSL::TLS1_2_VERSION
  }
)
```

### Redis Cloud Example

```ruby
# Redis Cloud with TLS
redis = RedisRuby.new(
  url: "rediss://default:password@redis-12345.cloud.redislabs.com:12345"
)
```

## Connection URLs

Redis URLs provide a convenient way to specify all connection parameters:

```ruby
# Basic TCP
redis = RedisRuby.new(url: "redis://localhost:6379")

# With authentication
redis = RedisRuby.new(url: "redis://:password@localhost:6379")

# With username and password (Redis 6+ ACL)
redis = RedisRuby.new(url: "redis://username:password@localhost:6379")

# With database selection
redis = RedisRuby.new(url: "redis://localhost:6379/2")

# TLS/SSL
redis = RedisRuby.new(url: "rediss://localhost:6380")

# Unix socket
redis = RedisRuby.new(url: "unix:///var/run/redis.sock")
```

### URL Format

```
redis://[username:password@]host[:port][/database]
rediss://[username:password@]host[:port][/database]  # TLS/SSL
unix://[username:password@]/path/to/socket[?db=database]
```

## Connection Options

### Timeout Configuration

```ruby
redis = RedisRuby.new(
  host: "localhost",
  timeout: 10.0  # Connection, read, and write timeout in seconds
)
```

The timeout applies to:
- Initial connection establishment
- Reading responses from Redis
- Writing commands to Redis

### Decode Responses

By default, Redis returns binary strings. Enable automatic decoding:

```ruby
redis = RedisRuby.new(
  host: "localhost",
  decode_responses: true,
  encoding: "UTF-8"  # Default encoding
)

redis.set("key", "value")
redis.get("key")  # => "value" (String, not binary)
```

## RESP3 Protocol

redis-ruby uses RESP3 (Redis Serialization Protocol version 3) by default, which provides:
- Better performance
- Native support for new data types
- Improved type safety

RESP3 is supported on Redis 6.0+.

```ruby
# RESP3 is enabled by default
redis = RedisRuby.new(url: "redis://localhost:6379")

# For compatibility with older Redis versions, use RESP2
redis = RedisRuby.new(
  url: "redis://localhost:6379",
  protocol: 2
)
```

### RESP3 Benefits

- **Better type preservation**: Distinguishes between different numeric types
- **Native maps**: Hash responses are more efficient
- **Streaming**: Better support for large responses
- **Push messages**: Support for Pub/Sub and client-side caching

## Authentication

### Password Authentication

```ruby
# Using password parameter
redis = RedisRuby.new(
  host: "localhost",
  password: "your-redis-password"
)

# Using URL
redis = RedisRuby.new(url: "redis://:your-redis-password@localhost:6379")
```

### ACL Authentication (Redis 6+)

Redis 6+ supports Access Control Lists (ACL) with username/password:

```ruby
# Using username and password
redis = RedisRuby.new(
  host: "localhost",
  username: "myuser",
  password: "mypassword"
)

# Using URL
redis = RedisRuby.new(url: "redis://myuser:mypassword@localhost:6379")
```

## Database Selection

Redis supports multiple databases (0-15 by default):

```ruby
# Select database 0 (default)
redis = RedisRuby.new(db: 0)

# Select database 2
redis = RedisRuby.new(db: 2)

# Using URL
redis = RedisRuby.new(url: "redis://localhost:6379/3")

# Switch database after connection
redis.select(5)
```

**Note**: In Redis Cluster mode, only database 0 is available.

## Retry and Reconnection

redis-ruby includes automatic retry logic for transient failures:

```ruby
# Basic retry configuration
redis = RedisRuby.new(
  host: "localhost",
  reconnect_attempts: 3  # Retry up to 3 times on connection errors
)
```

### Advanced Retry Configuration

```ruby
# Custom retry policy with exponential backoff
retry_policy = RedisRuby::Retry.new(
  retries: 5,
  backoff: RedisRuby::ExponentialWithJitterBackoff.new(
    base: 0.1,   # Start with 100ms
    cap: 2.0     # Max 2 seconds
  ),
  on_retry: ->(error, attempt) {
    puts "Retry attempt #{attempt}: #{error.message}"
  }
)

redis = RedisRuby.new(
  host: "localhost",
  retry_policy: retry_policy
)
```

### Backoff Strategies

```ruby
# No backoff - retry immediately
backoff = RedisRuby::NoBackoff.new

# Constant backoff - always wait the same duration
backoff = RedisRuby::ConstantBackoff.new(0.5)  # 500ms

# Exponential backoff
backoff = RedisRuby::ExponentialBackoff.new(base: 0.1, cap: 10.0)

# Exponential with jitter (recommended)
backoff = RedisRuby::ExponentialWithJitterBackoff.new(base: 0.1, cap: 10.0)

# Equal jitter backoff
backoff = RedisRuby::EqualJitterBackoff.new(base: 0.1, cap: 10.0)
```

## Connection Management

### Checking Connection Status

```ruby
redis = RedisRuby.new(host: "localhost")

# Check if connected
redis.connected?  # => true/false

# Check connection type
redis.ssl?   # => true if using SSL/TLS
redis.unix?  # => true if using Unix socket
```

### Closing Connections

```ruby
# Close the connection
redis.close

# Aliases
redis.disconnect
redis.quit
```

### Reconnecting

```ruby
# Manually reconnect
redis.reconnect

# Connection is automatically established on first command
redis = RedisRuby.new(host: "localhost")
redis.ping  # Connects and sends PING
```

## Best Practices

1. **Use Unix sockets for local connections**: Better performance than TCP
2. **Enable TLS/SSL in production**: Encrypt data in transit
3. **Configure appropriate timeouts**: Prevent hanging connections
4. **Use connection pooling for multi-threaded apps**: See [Connection Pools guide](/guides/connection-pools/)
5. **Enable retry logic**: Handle transient network failures gracefully
6. **Use RESP3 when possible**: Better performance and type safety
7. **Secure your credentials**: Use environment variables, not hardcoded passwords

## Example: Production Configuration

```ruby
redis = RedisRuby.new(
  url: ENV["REDIS_URL"],  # e.g., "rediss://user:pass@host:port/db"
  timeout: 5.0,
  reconnect_attempts: 3,
  decode_responses: true,
  ssl_params: {
    verify_mode: OpenSSL::SSL::VERIFY_PEER,
    ca_file: ENV["REDIS_CA_CERT"]
  }
)
```

## Next Steps

- [Connection Pools](/guides/connection-pools/) - Thread-safe and fiber-safe connection pooling
- [Pipelines](/guides/pipelines/) - Batch commands for better performance
- [Getting Started](/getting-started/) - Basic Redis operations

