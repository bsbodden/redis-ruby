# Connection Event Callbacks

Connection event callbacks allow you to monitor and react to connection lifecycle events in your Redis client. This is useful for logging, monitoring, custom reconnection logic, and debugging connection issues.

redis-ruby provides enterprise-grade callback capabilities matching redis-py's production features, including event dispatching, pool-level callbacks, async execution, configurable error handling, and performance metrics.

## Overview

### Connection-Level Events

redis-ruby supports seven types of connection lifecycle events:

- **`:connected`** - Triggered when a new connection is established for the first time
- **`:reconnected`** - Triggered when a connection is re-established after being disconnected
- **`:disconnected`** - Triggered when a connection is closed
- **`:error`** - Triggered when a connection error occurs
- **`:connection_created`** - Triggered before attempting to create a connection (NEW)
- **`:health_check`** - Triggered when a health check is performed (NEW)
- **`:marked_for_reconnect`** - Triggered when a connection is marked for reconnection (e.g., fork detected) (NEW)

### Pool-Level Events

For pooled clients, additional pool lifecycle events are available:

- **`:pool_created`** - Triggered when a connection pool is created
- **`:connection_created`** - Triggered when a new connection is added to the pool
- **`:connection_acquired`** - Triggered when a connection is checked out from the pool
- **`:connection_released`** - Triggered when a connection is returned to the pool
- **`:pool_exhausted`** - Triggered when the pool runs out of available connections
- **`:pool_reset`** - Triggered when the pool is reset

## Basic Usage

### Registering Callbacks

You can register callbacks using the `register_connection_callback` method:

```ruby
require "redis_ruby"

client = RR::Client.new(host: "localhost", port: 6379)

# Register a callback for connection events
client.register_connection_callback(:connected) do |event|
  puts "Connected to #{event[:host]}:#{event[:port]} at #{event[:timestamp]}"
end

client.register_connection_callback(:disconnected) do |event|
  puts "Disconnected from #{event[:host]}:#{event[:port]} at #{event[:timestamp]}"
end

client.register_connection_callback(:reconnected) do |event|
  puts "Reconnected to #{event[:host]}:#{event[:port]} at #{event[:timestamp]}"
end

client.register_connection_callback(:error) do |event|
  puts "Connection error: #{event[:error].message}"
  puts "Timestamp: #{event[:timestamp]}"
end
```

### Event Data Structure

Each callback receives an event hash with the following structure:

**For TCP/SSL connections:**
```ruby
{
  type: :connected,        # Event type
  host: "localhost",       # Redis host
  port: 6379,             # Redis port
  timestamp: Time.now     # Event timestamp
}
```

**For Unix socket connections:**
```ruby
{
  type: :connected,                    # Event type
  path: "/var/run/redis/redis.sock",  # Unix socket path
  timestamp: Time.now                 # Event timestamp
}
```

**For error events:**
```ruby
{
  type: :error,                       # Event type
  host: "localhost",                  # Redis host (or path for Unix)
  port: 6379,                        # Redis port (omitted for Unix)
  error: <StandardError instance>,   # The error that occurred
  timestamp: Time.now                # Event timestamp
}
```

## Advanced Usage

### Multiple Callbacks

You can register multiple callbacks for the same event type:

```ruby
client.register_connection_callback(:connected) do |event|
  logger.info("Connected to Redis")
end

client.register_connection_callback(:connected) do |event|
  metrics.increment("redis.connections")
end
```

All registered callbacks will be invoked in the order they were registered.

### Deregistering Callbacks

You can remove a specific callback using `deregister_connection_callback`:

```ruby
# Store the callback in a variable
callback = ->(event) { puts "Connected!" }

# Register it
client.register_connection_callback(:connected, callback)

# Later, deregister it
client.deregister_connection_callback(:connected, callback)
```

### Error Handling in Callbacks

If a callback raises an error, it will be caught and logged (via `warn`), but it won't prevent other callbacks from running or break the connection:

```ruby
client.register_connection_callback(:connected) do |event|
  raise "This error won't break the connection!"
end

client.register_connection_callback(:connected) do |event|
  puts "This callback will still run"
end
```

## Use Cases

### Logging

```ruby
require "logger"

logger = Logger.new($stdout)

client = RR::Client.new(host: "localhost", port: 6379)

client.register_connection_callback(:connected) do |event|
  logger.info("Redis connected: #{event[:host]}:#{event[:port]}")
end

client.register_connection_callback(:disconnected) do |event|
  logger.warn("Redis disconnected: #{event[:host]}:#{event[:port]}")
end

client.register_connection_callback(:error) do |event|
  logger.error("Redis connection error: #{event[:error].message}")
end
```

### Metrics Collection

```ruby
require "prometheus/client"

prometheus = Prometheus::Client.registry
connections = prometheus.counter(:redis_connections_total, docstring: "Total Redis connections")
errors = prometheus.counter(:redis_connection_errors_total, docstring: "Total Redis connection errors")

client = RR::Client.new(host: "localhost", port: 6379)

client.register_connection_callback(:connected) do |event|
  connections.increment(labels: { host: event[:host], port: event[:port] })
end

client.register_connection_callback(:error) do |event|
  errors.increment(labels: { host: event[:host], error: event[:error].class.name })
end
```

### Custom Reconnection Logic

```ruby
client = RR::Client.new(host: "localhost", port: 6379)

reconnect_count = 0

client.register_connection_callback(:reconnected) do |event|
  reconnect_count += 1
  puts "Reconnected #{reconnect_count} times"
  
  if reconnect_count > 10
    puts "Too many reconnections, alerting operations team"
    # Send alert
  end
end
```

## Enterprise Features

### Event Dispatcher System

The event dispatcher provides a centralized, type-safe event system for connection and pool lifecycle events:

```ruby
require "redis_ruby"

# Create an event dispatcher
dispatcher = RR::EventDispatcher.new

# Subscribe to specific event types
dispatcher.subscribe(RR::ConnectionConnectedEvent) do |event|
  puts "Connected to #{event.host}:#{event.port}"
  puts "First connection: #{event.first_connection}"
end

dispatcher.subscribe(RR::ConnectionErrorEvent) do |event|
  puts "Connection error: #{event.error.message}"
end

dispatcher.subscribe(RR::ConnectionHealthCheckEvent) do |event|
  puts "Health check: #{event.healthy ? 'PASS' : 'FAIL'}"
  puts "Latency: #{event.latency}ms"
end

# Create client with event dispatcher
client = RR::Client.new(
  host: "localhost",
  port: 6379,
  event_dispatcher: dispatcher
)
```

### Pool-Level Callbacks

Monitor connection pool lifecycle events:

```ruby
dispatcher = RR::EventDispatcher.new

# Pool created event
dispatcher.subscribe(RR::PoolCreatedEvent) do |event|
  puts "Pool '#{event.pool_name}' created with size #{event.size}"
end

# Connection acquired from pool
dispatcher.subscribe(RR::PoolConnectionAcquiredEvent) do |event|
  puts "Connection acquired from '#{event.pool_name}'"
  puts "Wait time: #{event.wait_time}s" if event.wait_time
  puts "Active: #{event.active_connections}, Idle: #{event.idle_connections}"
end

# Pool exhausted (no connections available)
dispatcher.subscribe(RR::PoolExhaustedEvent) do |event|
  puts "WARNING: Pool '#{event.pool_name}' exhausted!"
  puts "Pool size: #{event.size}, Timeout: #{event.timeout}s"
  # Alert operations team
end

# Create pooled client with event dispatcher
client = RR.pooled(
  host: "localhost",
  port: 6379,
  pool: {
    size: 10,
    timeout: 5,
    event_dispatcher: dispatcher
  }
)
```

### Async Callback Execution

Execute callbacks asynchronously to avoid blocking connection operations:

```ruby
# Create async callback executor with thread pool
async_executor = RR::AsyncCallbackExecutor.new(
  pool_size: 4,      # Number of worker threads
  queue_size: 100    # Max queued callbacks
)

# Create client with async callbacks
client = RR.pooled(
  host: "localhost",
  port: 6379,
  async_callbacks: async_executor,
  pool: {
    size: 10,
    event_dispatcher: dispatcher
  }
)

# Callbacks are now executed asynchronously
# Connection operations don't wait for callbacks to complete

# Shutdown executor when done
at_exit do
  async_executor.shutdown(timeout: 5.0)
end
```

### Configurable Error Handling

Control how callback errors are handled:

```ruby
# Strategy: :ignore - Silently ignore callback errors
error_handler = RR::CallbackErrorHandler.new(strategy: :ignore)

# Strategy: :log - Log errors with warn (default)
error_handler = RR::CallbackErrorHandler.new(strategy: :log)

# Strategy: :raise - Re-raise errors (useful for testing)
error_handler = RR::CallbackErrorHandler.new(strategy: :raise)

# Create client with error handler
client = RR.pooled(
  host: "localhost",
  port: 6379,
  callback_error_handler: error_handler,
  pool: {
    size: 10,
    event_dispatcher: dispatcher
  }
)
```

### Callback Performance Metrics

Track callback execution time and errors:

```ruby
# Create instrumentation instance
instrumentation = RR::Instrumentation.new

# Create client with instrumentation
client = RR.pooled(
  host: "localhost",
  port: 6379,
  instrumentation: instrumentation,
  pool: {
    size: 10,
    event_dispatcher: dispatcher
  }
)

# Get callback metrics
metrics = instrumentation.all_callback_metrics
metrics.each do |event_type, stats|
  puts "#{event_type}:"
  puts "  Count: #{stats[:count]}"
  puts "  Total time: #{stats[:total_time]}s"
  puts "  Avg time: #{stats[:avg_time]}s"
  puts "  Errors: #{stats[:errors]}"
end

# Get metrics for specific event type
connected_metrics = instrumentation.callback_metrics("connected")
puts "Connected callbacks: #{connected_metrics[:count]}"
puts "Avg execution time: #{connected_metrics[:avg_time]}s"
```

### Health Check Callbacks

Monitor connection health:

```ruby
dispatcher = RR::EventDispatcher.new

dispatcher.subscribe(RR::ConnectionHealthCheckEvent) do |event|
  if event.healthy
    puts "Health check PASSED (#{event.latency}ms)"
  else
    puts "Health check FAILED"
    # Alert monitoring system
  end
end

# Create connection with health checks
conn = RR::Connection::TCP.new(
  host: "localhost",
  port: 6379,
  event_dispatcher: dispatcher
)

# Perform health check
conn.health_check  # Triggers :health_check event
conn.health_check(command: "PING")  # Custom command
```

## Production Best Practices

### 1. Use Event Dispatcher for Type Safety

```ruby
# ✅ GOOD: Type-safe event handling
dispatcher = RR::EventDispatcher.new
dispatcher.subscribe(RR::PoolExhaustedEvent) do |event|
  # event is guaranteed to be PoolExhaustedEvent
  alert_ops_team(pool: event.pool_name, size: event.size)
end

# ❌ AVOID: Legacy callback API (less type-safe)
client.register_connection_callback(:pool_exhausted) do |event|
  # event is just a hash
  alert_ops_team(pool: event[:pool_name], size: event[:size])
end
```

### 2. Use Async Callbacks for Heavy Operations

```ruby
# ✅ GOOD: Async execution for slow operations
async_executor = RR::AsyncCallbackExecutor.new(pool_size: 4)

dispatcher = RR::EventDispatcher.new
dispatcher.subscribe(RR::ConnectionErrorEvent) do |event|
  # This runs in background thread, doesn't block connection
  send_to_error_tracking_service(event.error)
  update_metrics_database(event)
end

client = RR.pooled(
  async_callbacks: async_executor,
  pool: { event_dispatcher: dispatcher }
)

# ❌ AVOID: Synchronous heavy operations
client.register_connection_callback(:error) do |event|
  # This blocks the connection thread!
  send_to_error_tracking_service(event[:error])
end
```

### 3. Monitor Pool Exhaustion

```ruby
dispatcher = RR::EventDispatcher.new

# Alert when pool is exhausted
dispatcher.subscribe(RR::PoolExhaustedEvent) do |event|
  logger.error("Pool exhausted: #{event.pool_name}")
  metrics.increment("redis.pool.exhausted")

  # Consider increasing pool size if this happens frequently
  if pool_exhaustion_count > 10
    alert_ops_team("Consider increasing Redis pool size")
  end
end

client = RR.pooled(
  pool: {
    size: 10,
    timeout: 5,
    event_dispatcher: dispatcher
  }
)
```

### 4. Track Callback Performance

```ruby
instrumentation = RR::Instrumentation.new

client = RR.pooled(
  instrumentation: instrumentation,
  pool: { event_dispatcher: dispatcher }
)

# Periodically check callback performance
Thread.new do
  loop do
    sleep 60

    metrics = instrumentation.all_callback_metrics
    metrics.each do |event_type, stats|
      if stats[:avg_time] > 0.1  # 100ms threshold
        logger.warn("Slow callback: #{event_type} (#{stats[:avg_time]}s)")
      end

      if stats[:errors] > 0
        logger.error("Callback errors: #{event_type} (#{stats[:errors]} errors)")
      end
    end
  end
end
```

### 5. Graceful Shutdown

```ruby
# Create async executor
async_executor = RR::AsyncCallbackExecutor.new

# ... use client ...

# Graceful shutdown
at_exit do
  puts "Shutting down async callback executor..."
  async_executor.shutdown(timeout: 10.0)
  puts "Shutdown complete"
end
```

## Troubleshooting

### Callbacks Not Firing

**Problem**: Callbacks registered but not being invoked.

**Solution**: Ensure you're using the correct event type and that the event dispatcher is passed to the client:

```ruby
# ✅ CORRECT
dispatcher = RR::EventDispatcher.new
dispatcher.subscribe(RR::ConnectionConnectedEvent) { |e| puts "Connected!" }

client = RR::Client.new(
  host: "localhost",
  event_dispatcher: dispatcher  # Don't forget this!
)

# ❌ WRONG - dispatcher not passed to client
dispatcher = RR::EventDispatcher.new
dispatcher.subscribe(RR::ConnectionConnectedEvent) { |e| puts "Connected!" }
client = RR::Client.new(host: "localhost")  # Callbacks won't fire!
```

### Slow Connection Operations

**Problem**: Connection operations are slow when callbacks are registered.

**Solution**: Use async callback execution:

```ruby
# ✅ SOLUTION
async_executor = RR::AsyncCallbackExecutor.new(pool_size: 4)

client = RR.pooled(
  async_callbacks: async_executor,
  pool: { event_dispatcher: dispatcher }
)
```

### Callback Errors Breaking Application

**Problem**: Errors in callbacks are causing application failures.

**Solution**: Use appropriate error handling strategy:

```ruby
# For production: log errors but don't break
error_handler = RR::CallbackErrorHandler.new(strategy: :log)

# For testing: raise errors to catch bugs
error_handler = RR::CallbackErrorHandler.new(strategy: :raise)

client = RR.pooled(
  callback_error_handler: error_handler,
  pool: { event_dispatcher: dispatcher }
)
```

### Memory Leaks from Callbacks

**Problem**: Memory usage grows over time.

**Solution**: Unsubscribe from events when no longer needed:

```ruby
dispatcher = RR::EventDispatcher.new

# Subscribe and keep reference
subscription = dispatcher.subscribe(RR::ConnectionConnectedEvent) do |event|
  puts "Connected!"
end

# Later, unsubscribe
dispatcher.unsubscribe(RR::ConnectionConnectedEvent, subscription)
```

## Best Practices

1. **Use event dispatcher for production** - Provides type safety and better error handling
2. **Use async callbacks for heavy operations** - Avoid blocking connection operations
3. **Monitor callback performance** - Track execution time and errors with instrumentation
4. **Handle pool exhaustion** - Alert when pool runs out of connections
5. **Graceful shutdown** - Always shutdown async executor before exit
6. **Keep callbacks lightweight** - Even with async execution, avoid extremely heavy operations
7. **Use appropriate error handling** - :log for production, :raise for testing
8. **Clean up subscriptions** - Unsubscribe when callbacks are no longer needed

## See Also

- [Observability Guide](observability.md) - For application-level metrics and instrumentation
- [Circuit Breaker Guide](circuit-breaker.md) - For failure protection and health checks
- [Connection Pooling Guide](connection-pooling.md) - For pool configuration and best practices

