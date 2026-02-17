---
layout: default
title: Retry Logic
parent: Guides
nav_order: 14
---

# Retry Logic and Backoff Strategies
{: .no_toc }

Comprehensive guide to implementing retry logic with various backoff strategies for resilient Redis connections.
{: .fs-6 .fw-300 }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

Retry logic automatically retries failed operations with configurable backoff strategies. redis-ruby provides multiple backoff strategies to handle transient failures gracefully.

## Backoff Strategies

### No Backoff

Retry immediately without delay:

```ruby
require 'redis_ruby'

# Create retry policy with no backoff
retry_policy = RR::Retry.new(
  retries: 3,
  backoff: RR::Retry::NoBackoff.new
)

client = RR::Client.new(
  host: 'localhost',
  port: 6379,
  retry_policy: retry_policy
)
```

### Constant Backoff

Wait a fixed amount of time between retries:

```ruby
# Wait 1 second between retries
retry_policy = RR::Retry.new(
  retries: 3,
  backoff: RR::Retry::ConstantBackoff.new(1.0)
)
```

### Exponential Backoff

Increase wait time exponentially:

```ruby
# Wait 1s, 2s, 4s, 8s...
retry_policy = RR::Retry.new(
  retries: 5,
  backoff: RR::Retry::ExponentialBackoff.new(
    base: 1.0,
    multiplier: 2.0,
    max_delay: 30.0
  )
)
```

### Exponential Backoff with Jitter

Add randomness to prevent thundering herd:

```ruby
# Exponential backoff with random jitter
retry_policy = RR::Retry.new(
  retries: 5,
  backoff: RR::Retry::ExponentialWithJitterBackoff.new(
    base: 1.0,
    multiplier: 2.0,
    max_delay: 30.0
  )
)
```

### Equal Jitter Backoff

Balanced jitter for optimal distribution:

```ruby
# Equal jitter backoff (recommended for production)
retry_policy = RR::Retry.new(
  retries: 5,
  backoff: RR::Retry::EqualJitterBackoff.new(
    base: 1.0,
    multiplier: 2.0,
    max_delay: 30.0
  )
)
```

## Client Integration

### Basic Client

```ruby
# Client with retry policy
client = RR::Client.new(
  host: 'localhost',
  port: 6379,
  retry_policy: RR::Retry.new(retries: 3)
)

# Commands automatically retry on transient failures
client.get("mykey")
```

### Pooled Client

```ruby
# Pooled client with retry policy
client = RR::PooledClient.new(
  host: 'localhost',
  port: 6379,
  retry_policy: RR::Retry.new(
    retries: 3,
    backoff: RR::Retry::EqualJitterBackoff.new(1.0)
  )
)
```

### Shorthand Configuration

```ruby
# Use reconnect_attempts for simple retry
client = RR::PooledClient.new(
  host: 'localhost',
  port: 6379,
  reconnect_attempts: 3  # Creates default retry policy
)
```

## Production Patterns

### High-Availability Configuration

```ruby
# Production-ready retry configuration
retry_policy = RR::Retry.new(
  retries: 5,
  backoff: RR::Retry::EqualJitterBackoff.new(
    base: 0.5,
    multiplier: 2.0,
    max_delay: 10.0
  )
)

client = RR::PooledClient.new(
  host: 'redis.example.com',
  port: 6379,
  retry_policy: retry_policy,
  pool: {
    size: 20,
    timeout: 5.0,
    health_check_interval: 30.0
  }
)
```

### Combining with Circuit Breaker

```ruby
# Retry + Circuit Breaker for maximum resilience
circuit_breaker = RR::CircuitBreaker.new(
  failure_threshold: 5,
  reset_timeout: 30.0,
  fallback: -> { nil }
)

retry_policy = RR::Retry.new(
  retries: 3,
  backoff: RR::Retry::EqualJitterBackoff.new(1.0)
)

client = RR::Client.new(
  host: 'localhost',
  port: 6379,
  circuit_breaker: circuit_breaker,
  retry_policy: retry_policy
)
```

## Best Practices

1. **Use Equal Jitter Backoff**: Best for production to prevent thundering herd
2. **Set Reasonable Max Delay**: Prevent excessive wait times (10-30 seconds typical)
3. **Limit Retry Count**: 3-5 retries is usually sufficient
4. **Combine with Circuit Breaker**: Prevent retry storms during outages
5. **Monitor Retry Metrics**: Track retry rates and success/failure
6. **Test Failure Scenarios**: Verify retry behavior under load

## See Also

- [Circuit Breaker Guide](circuit-breaker.md)
- [Health Checks Guide](health-checks.md)
- [Connection Pooling Guide](connection-pooling.md)

