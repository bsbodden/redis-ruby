# Circuit Breaker and Health Checks

Circuit breakers are a resilience pattern that prevents cascading failures in distributed systems. When a service starts failing, the circuit breaker "opens" to prevent further requests, giving the service time to recover.

## Table of Contents

- [Overview](#overview)
- [Basic Usage](#basic-usage)
- [Configuration](#configuration)
- [Circuit States](#circuit-states)
- [Health Checks](#health-checks)
- [Metrics](#metrics)
- [Best Practices](#best-practices)

## Overview

The circuit breaker pattern has three states:

1. **CLOSED** (normal operation): Requests pass through normally
2. **OPEN** (failing): Requests are rejected immediately without attempting the operation
3. **HALF_OPEN** (testing recovery): A limited number of requests are allowed to test if the service has recovered

## Basic Usage

### Creating a Circuit Breaker

```ruby
require "redis_ruby"

# Create a circuit breaker
circuit_breaker = RR::CircuitBreaker.new(
  failure_threshold: 5,        # Open after 5 consecutive failures
  success_threshold: 2,        # Close after 2 consecutive successes in half-open state
  timeout: 60.0,               # Stay open for 60 seconds before trying half-open
  half_open_timeout: 30.0      # Stay half-open for 30 seconds max
)

# Create a client with circuit breaker
client = RR.new(circuit_breaker: circuit_breaker)

# Use normally - circuit breaker protects automatically
client.set("key", "value")
client.get("key")
```

### Standalone Circuit Breaker

You can also use the circuit breaker independently:

```ruby
circuit_breaker = RR::CircuitBreaker.new

# Wrap any operation
result = circuit_breaker.call do
  # Your operation here
  perform_risky_operation
end
```

## Configuration

### Parameters

- **failure_threshold** (default: 5): Number of consecutive failures before opening the circuit
- **success_threshold** (default: 2): Number of consecutive successes in half-open state before closing
- **timeout** (default: 60.0): Seconds to wait in open state before transitioning to half-open
- **half_open_timeout** (default: 30.0): Seconds to wait in half-open state before reopening if no success

### Example Configurations

**Aggressive (fail fast)**:
```ruby
circuit_breaker = RR::CircuitBreaker.new(
  failure_threshold: 3,
  timeout: 30.0
)
```

**Conservative (tolerate more failures)**:
```ruby
circuit_breaker = RR::CircuitBreaker.new(
  failure_threshold: 10,
  timeout: 120.0
)
```

## Circuit States

### CLOSED (Normal Operation)

- All requests pass through
- Failures are counted
- After `failure_threshold` consecutive failures, transitions to OPEN

### OPEN (Failing)

- All requests are rejected immediately with `RR::CircuitBreakerOpenError`
- After `timeout` seconds, transitions to HALF_OPEN

### HALF_OPEN (Testing Recovery)

- Limited requests are allowed through
- After `success_threshold` consecutive successes, transitions to CLOSED
- Any failure transitions back to OPEN

## Health Checks

### Basic Health Check

```ruby
client = RR.new(circuit_breaker: circuit_breaker)

if client.healthy?
  puts "Redis is healthy"
else
  puts "Redis is unhealthy or circuit is open"
end
```

### Custom Health Check Command

```ruby
# Use a different command for health check
if client.health_check(command: "INFO")
  puts "Redis is responding to INFO"
end
```

### Periodic Health Checks

```ruby
Thread.new do
  loop do
    unless client.healthy?
      logger.warn "Redis health check failed"
      alert_ops_team
    end
    sleep 30
  end
end
```

## Metrics

### Getting Circuit Breaker Metrics

```ruby
snapshot = circuit_breaker.snapshot

puts "State: #{snapshot[:state]}"
puts "Failures: #{snapshot[:failure_count]}"
puts "Successes: #{snapshot[:success_count]}"
puts "Opened at: #{snapshot[:opened_at]}" if snapshot[:opened_at]
```

### Monitoring Circuit State

```ruby
# Export to monitoring system
def export_circuit_metrics(circuit_breaker)
  snapshot = circuit_breaker.snapshot
  
  Prometheus.gauge("redis_circuit_state").set(
    snapshot[:state] == :closed ? 0 : (snapshot[:state] == :open ? 2 : 1)
  )
  Prometheus.gauge("redis_circuit_failures").set(snapshot[:failure_count])
  Prometheus.gauge("redis_circuit_successes").set(snapshot[:success_count])
end
```

## Best Practices

### 1. Combine with Retry Policy

```ruby
retry_policy = RR::Retry.new(max_attempts: 3)
circuit_breaker = RR::CircuitBreaker.new

client = RR.new(
  retry_policy: retry_policy,
  circuit_breaker: circuit_breaker
)
```

The retry policy will attempt retries, but if failures persist, the circuit breaker will open to prevent further attempts.

### 2. Monitor Circuit State

Always monitor your circuit breaker state in production:

```ruby
# Log state changes
previous_state = :closed

Thread.new do
  loop do
    current_state = circuit_breaker.snapshot[:state]
    if current_state != previous_state
      logger.warn "Circuit breaker state changed: #{previous_state} -> #{current_state}"
      previous_state = current_state
    end
    sleep 5
  end
end
```

### 3. Tune Thresholds for Your Use Case

- **High-traffic services**: Lower failure threshold (3-5) to fail fast
- **Low-traffic services**: Higher failure threshold (10-20) to avoid false positives
- **Critical services**: Longer timeout (120-300s) to give more recovery time
- **Non-critical services**: Shorter timeout (30-60s) to recover quickly

### 4. Handle CircuitBreakerOpenError

```ruby
begin
  client.get("key")
rescue RR::CircuitBreakerOpenError
  # Circuit is open - use fallback
  logger.warn "Circuit breaker is open, using cached value"
  get_from_cache("key")
end
```

### 5. Use with Connection Pooling

```ruby
circuit_breaker = RR::CircuitBreaker.new

# Circuit breaker protects the entire pool
pooled_client = RR::PooledClient.new(
  pool: { size: 10 },
  circuit_breaker: circuit_breaker
)
```

## Error Handling

### CircuitBreakerOpenError

When the circuit is open, all requests raise `RR::CircuitBreakerOpenError`:

```ruby
begin
  client.set("key", "value")
rescue RR::CircuitBreakerOpenError => e
  puts "Circuit is open: #{e.message}"
  # Use fallback logic
end
```

### Automatic Error Recording

The circuit breaker automatically records failures for any exception raised during command execution. You don't need to manually record failures.

## Advanced Usage

### Manual State Control

```ruby
# Manually reset the circuit breaker
circuit_breaker.reset!

# Check current state
puts circuit_breaker.state  # :closed, :open, or :half_open
```

### Combining with Instrumentation

```ruby
instrumentation = RR::Instrumentation.new
circuit_breaker = RR::CircuitBreaker.new

client = RR.new(
  instrumentation: instrumentation,
  circuit_breaker: circuit_breaker
)

# Monitor both metrics and circuit state
snapshot = {
  metrics: instrumentation.snapshot,
  circuit: circuit_breaker.snapshot
}
```

## Redis Enterprise Features

Circuit breakers are especially important for Redis Enterprise deployments:

- **Multi-region deployments**: Protect against region failures
- **Cluster failovers**: Prevent cascading failures during failover
- **Active-Active**: Handle temporary inconsistencies gracefully
- **Cloud deployments**: Protect against network issues

## See Also

- [Observability Guide](observability.md) - Metrics and monitoring
- [Retry Policies](../README.md#retry-policies) - Automatic retry configuration
- [Connection Pooling](../README.md#connection-pooling) - Thread-safe connection management

