# Connection Event Callbacks

Connection event callbacks allow you to monitor and react to connection lifecycle events in your Redis client. This is useful for logging, monitoring, custom reconnection logic, and debugging connection issues.

## Overview

redis-ruby supports four types of connection lifecycle events:

- **`:connected`** - Triggered when a new connection is established for the first time
- **`:reconnected`** - Triggered when a connection is re-established after being disconnected
- **`:disconnected`** - Triggered when a connection is closed
- **`:error`** - Triggered when a connection error occurs

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

## Best Practices

1. **Keep callbacks lightweight** - Callbacks are executed synchronously during connection events, so avoid heavy operations
2. **Handle errors gracefully** - While callback errors are caught, it's better to handle them explicitly
3. **Use for monitoring, not business logic** - Callbacks are best for observability, not critical application logic
4. **Clean up callbacks** - Deregister callbacks when they're no longer needed to avoid memory leaks

## See Also

- [Observability Guide](observability.md) - For application-level metrics and instrumentation
- [Circuit Breaker Guide](circuit-breaker.md) - For failure protection and health checks

