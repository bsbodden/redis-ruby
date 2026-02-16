---
layout: default
title: Observability & Metrics
parent: Guides
nav_order: 8
---

# Observability & Metrics

redis-ruby provides built-in instrumentation for monitoring Redis operations in production environments.

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

The `RR::Instrumentation` class provides:
- **Command tracking**: Count and latency for each Redis command
- **Error tracking**: Count errors by type
- **Callbacks**: Hook into command execution lifecycle
- **Thread-safe**: Safe for concurrent access
- **Zero overhead**: Only active when explicitly enabled

## Basic Usage

### Enable Instrumentation

```ruby
# Create instrumentation instance
instrumentation = RR::Instrumentation.new

# Pass to client
client = RR.new(instrumentation: instrumentation)

# Or with pooled client
pooled = RR.pooled(instrumentation: instrumentation, pool: { size: 10 })
```

### Collect Metrics

```ruby
# Execute some commands
client.set("user:1", "Alice")
client.get("user:1")
client.incr("counter")

# Get metrics
instrumentation.command_count                    # => 3
instrumentation.command_count_by_name("SET")     # => 1
instrumentation.command_count_by_name("GET")     # => 1
instrumentation.command_latency("SET")           # => 0.001234 (seconds)
instrumentation.average_latency("GET")           # => 0.000987 (seconds)
```

### Get Complete Snapshot

```ruby
snapshot = instrumentation.snapshot
# => {
#   total_commands: 3,
#   total_errors: 0,
#   commands: {
#     "SET" => { count: 1, total_time: 0.001234, errors: 0 },
#     "GET" => { count: 1, total_time: 0.000987, errors: 0 },
#     "INCR" => { count: 1, total_time: 0.000765, errors: 0 }
#   },
#   errors: {}
# }
```

## Error Tracking

```ruby
begin
  client.call("INVALID_COMMAND")
rescue RR::CommandError => e
  # Error is automatically tracked
end

instrumentation.error_count                      # => 1
instrumentation.error_count_by_type("CommandError") # => 1
```

## Callbacks

### Before Command Execution

```ruby
instrumentation.before_command do |command, args|
  puts "Executing: #{command} #{args.inspect}"
end

client.set("key", "value")
# Output: Executing: SET ["key", "value"]
```

### After Command Execution

```ruby
instrumentation.after_command do |command, args, duration|
  puts "Completed: #{command} in #{duration}s"
end

client.get("key")
# Output: Completed: GET in 0.001234s
```

## Integration Examples

### Prometheus Exporter

```ruby
require 'prometheus/client'

# Create Prometheus metrics
registry = Prometheus::Client.registry
commands_total = Prometheus::Client::Counter.new(
  :redis_commands_total,
  docstring: 'Total Redis commands',
  labels: [:command]
)
command_duration = Prometheus::Client::Histogram.new(
  :redis_command_duration_seconds,
  docstring: 'Redis command duration',
  labels: [:command]
)
registry.register(commands_total)
registry.register(command_duration)

# Hook into instrumentation
instrumentation.after_command do |command, args, duration|
  commands_total.increment(labels: { command: command })
  command_duration.observe(duration, labels: { command: command })
end
```

### OpenTelemetry

```ruby
require 'opentelemetry/sdk'

tracer = OpenTelemetry.tracer_provider.tracer('redis-ruby')

instrumentation.before_command do |command, args|
  @span = tracer.start_span("redis.#{command.downcase}")
  @span.set_attribute('db.system', 'redis')
  @span.set_attribute('db.operation', command)
end

instrumentation.after_command do |command, args, duration|
  @span&.finish
  @span = nil
end
```

### Custom Logger

```ruby
require 'logger'

logger = Logger.new(STDOUT)

instrumentation.after_command do |command, args, duration|
  if duration > 0.1  # Log slow commands (>100ms)
    logger.warn("Slow Redis command: #{command} took #{duration}s")
  end
end
```

## Resetting Metrics

```ruby
# Reset all metrics to zero
instrumentation.reset!
```

## Performance Impact

- **Without instrumentation**: Zero overhead (not enabled by default)
- **With instrumentation**: ~5-10% overhead for metric collection
- **Thread-safe**: Uses `MonitorMixin` for synchronization

## Best Practices

1. **Use one instrumentation instance per application**: Share across all clients
2. **Export metrics periodically**: Use callbacks or snapshot for metric export
3. **Monitor slow commands**: Set up alerts for commands exceeding thresholds
4. **Track error rates**: Monitor error counts by type
5. **Reset metrics carefully**: Only reset during maintenance windows

## Future Enhancements

- Connection pool metrics (active/idle connections, wait time)
- Pipeline and transaction command tracking
- Automatic metric export to popular backends

