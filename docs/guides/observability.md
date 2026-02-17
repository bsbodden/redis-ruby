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

The `RR::Instrumentation` class provides enterprise-grade observability:
- **Command tracking**: Count, latency, success/error rates for each Redis command
- **Percentile latencies**: Track p50, p95, p99 latencies for performance analysis
- **Connection pool metrics**: Monitor pool health, connection creation, wait times
- **Pipeline/Transaction tracking**: Measure batch operation performance
- **Error tracking**: Count errors by type with detailed breakdown
- **Callbacks**: Hook into command execution lifecycle
- **Metric exporters**: Built-in Prometheus and OpenTelemetry exporters
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
#     "SET" => { count: 1, total_time: 0.001234, errors: 0, success: 1 },
#     "GET" => { count: 1, total_time: 0.000987, errors: 0, success: 1 },
#     "INCR" => { count: 1, total_time: 0.000765, errors: 0, success: 1 }
#   },
#   errors: {},
#   pipelines: { count: 0, total_time: 0.0, avg_time: 0.0, total_commands: 0, avg_commands: 0.0 },
#   transactions: { count: 0, total_time: 0.0, avg_time: 0.0, total_commands: 0, avg_commands: 0.0 },
#   pool: { connection_creates: 1, avg_connection_create_time: 0.005, ... }
# }
```

## Advanced Metrics

### Percentile Latencies

Track latency percentiles for performance analysis:

```ruby
# Enable percentile tracking
instrumentation = RR::Instrumentation.new(
  percentiles: true,
  percentile_window_size: 1000  # Keep last 1000 samples
)

client = RR.new(instrumentation: instrumentation)

# Execute commands
100.times { client.get("key") }

# Get percentile latencies
p50 = instrumentation.percentile_latency("GET", 50)  # Median
p95 = instrumentation.percentile_latency("GET", 95)  # 95th percentile
p99 = instrumentation.percentile_latency("GET", 99)  # 99th percentile

puts "GET latency - p50: #{p50}s, p95: #{p95}s, p99: #{p99}s"
```

### Success and Error Rates

Track success and error rates per command:

```ruby
# Execute some commands with errors
client.set("key1", "value1")
client.set("key2", "value2")
begin
  client.call("INVALID_COMMAND")
rescue RR::CommandError
  # Error tracked automatically
end

# Get rates
success_rate = instrumentation.success_rate("SET")  # => 1.0 (100%)
error_rate = instrumentation.error_rate("INVALID_COMMAND")  # => 1.0 (100%)
```

### Connection Pool Metrics

Monitor connection pool health and performance:

```ruby
# Create pooled client with instrumentation
pooled = RR.pooled(
  instrumentation: instrumentation,
  pool: { size: 10, name: "main-pool" }
)

# Execute commands
pooled.set("key", "value")

# Get pool metrics
pool_stats = instrumentation.pool_snapshot
# => {
#   connection_creates: 1,
#   avg_connection_create_time: 0.005,
#   total_connection_wait_time: 0.001,
#   total_connection_checkout_time: 0.002,
#   connection_closes: { "normal" => 0, "error" => 0 },
#   pool_exhaustions: 0,
#   active_connections: 1,
#   idle_connections: 9,
#   total_connections: 10
# }
```

### Pipeline and Transaction Metrics

Track batch operation performance:

```ruby
# Execute pipeline
client.pipelined do |pipe|
  pipe.set("key1", "value1")
  pipe.set("key2", "value2")
  pipe.get("key1")
end

# Execute transaction
client.multi do |tx|
  tx.incr("counter")
  tx.get("counter")
end

# Get pipeline/transaction metrics
snapshot = instrumentation.snapshot
snapshot[:pipelines]
# => { count: 1, total_time: 0.005, avg_time: 0.005, total_commands: 3, avg_commands: 3.0 }

snapshot[:transactions]
# => { count: 1, total_time: 0.003, avg_time: 0.003, total_commands: 2, avg_commands: 2.0 }
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

## Metric Exporters

### Built-in Prometheus Exporter

Export metrics in Prometheus text format:

```ruby
require 'redis_ruby/instrumentation/prometheus_exporter'

# Create exporter
exporter = RR::Instrumentation::PrometheusExporter.new(
  instrumentation,
  prefix: "myapp_redis"  # Optional custom prefix
)

# Export metrics
puts exporter.export

# Output:
# # HELP myapp_redis_commands_total Total number of Redis commands executed
# # TYPE myapp_redis_commands_total counter
# myapp_redis_commands_total 150
#
# # HELP myapp_redis_command_count Number of times each command was executed
# # TYPE myapp_redis_command_count counter
# myapp_redis_command_count{command="SET"} 50
# myapp_redis_command_count{command="GET"} 100
# ...
```

Serve metrics endpoint:

```ruby
require 'sinatra'
require 'redis_ruby/instrumentation/prometheus_exporter'

# Global instrumentation instance
INSTRUMENTATION = RR::Instrumentation.new
EXPORTER = RR::Instrumentation::PrometheusExporter.new(INSTRUMENTATION)

# Metrics endpoint
get '/metrics' do
  content_type 'text/plain'
  EXPORTER.export
end
```

### Built-in OpenTelemetry Exporter

Export metrics in OpenTelemetry format:

```ruby
require 'redis_ruby/instrumentation/opentelemetry_exporter'

# Create exporter
exporter = RR::Instrumentation::OpenTelemetryExporter.new(
  instrumentation,
  service_name: "my-app",
  service_version: "1.0.0"
)

# Export metrics
metrics = exporter.export

# Returns OpenTelemetry-formatted hash:
# {
#   resource_metrics: [
#     {
#       resource: { attributes: [...] },
#       scope_metrics: [
#         {
#           scope: { name: "redis-ruby-instrumentation", version: "1.0.0" },
#           metrics: [...]
#         }
#       ]
#     }
#   ]
# }
```

### Custom Prometheus Integration

Use callbacks for custom Prometheus integration:

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
- **With instrumentation (basic)**: ~2-5% overhead for metric collection
- **With percentiles enabled**: ~5-10% overhead (sliding window maintenance)
- **Thread-safe**: Uses `MonitorMixin` for synchronization
- **High-resolution timing**: Uses `Process.clock_gettime(Process::CLOCK_MONOTONIC)`

## Production Best Practices

### 1. Use One Instrumentation Instance

Share a single instrumentation instance across all Redis clients:

```ruby
# config/initializers/redis.rb
REDIS_INSTRUMENTATION = RR::Instrumentation.new(
  percentiles: true,
  percentile_window_size: 1000
)

# Use in multiple clients
$redis = RR.new(instrumentation: REDIS_INSTRUMENTATION)
$redis_cache = RR.pooled(
  instrumentation: REDIS_INSTRUMENTATION,
  pool: { size: 20 }
)
```

### 2. Monitor Critical Metrics

Set up alerts for key performance indicators:

```ruby
# Monitor slow commands
instrumentation.after_command do |command, args, duration|
  if duration > 0.1  # 100ms threshold
    logger.warn("Slow Redis command: #{command} took #{duration}s")
    # Send to monitoring system (e.g., Datadog, New Relic)
  end
end

# Monitor error rates
Thread.new do
  loop do
    sleep 60  # Check every minute
    snapshot = instrumentation.snapshot

    snapshot[:commands].each do |cmd, data|
      error_rate = data[:errors].to_f / data[:count]
      if error_rate > 0.01  # 1% error rate threshold
        alert("High error rate for #{cmd}: #{error_rate * 100}%")
      end
    end
  end
end
```

### 3. Monitor Pool Health

Track connection pool metrics to prevent exhaustion:

```ruby
# Periodic pool health check
Thread.new do
  loop do
    sleep 30  # Check every 30 seconds
    pool_stats = instrumentation.pool_snapshot

    # Alert on pool exhaustion
    if pool_stats[:pool_exhaustions] > 0
      alert("Connection pool exhausted #{pool_stats[:pool_exhaustions]} times")
    end

    # Alert on high active connection ratio
    utilization = pool_stats[:active_connections].to_f / pool_stats[:total_connections]
    if utilization > 0.8  # 80% utilization
      alert("High pool utilization: #{utilization * 100}%")
    end
  end
end
```

### 4. Export Metrics Periodically

Push metrics to your monitoring system:

```ruby
require 'redis_ruby/instrumentation/prometheus_exporter'

exporter = RR::Instrumentation::PrometheusExporter.new(instrumentation)

# Export to Prometheus Pushgateway
Thread.new do
  loop do
    sleep 60  # Push every minute

    begin
      metrics = exporter.export
      # Push to Prometheus Pushgateway
      Net::HTTP.post(
        URI("http://pushgateway:9091/metrics/job/redis-ruby"),
        metrics,
        "Content-Type" => "text/plain"
      )
    rescue => e
      logger.error("Failed to push metrics: #{e.message}")
    end
  end
end
```

### 5. Use Percentiles for SLOs

Track percentile latencies for Service Level Objectives:

```ruby
# Check SLO compliance
def check_slo_compliance(instrumentation)
  p95 = instrumentation.percentile_latency("GET", 95)
  p99 = instrumentation.percentile_latency("GET", 99)

  # SLO: 95% of GET requests < 10ms, 99% < 50ms
  if p95 && p95 > 0.010
    alert("GET p95 latency exceeds SLO: #{p95 * 1000}ms")
  end

  if p99 && p99 > 0.050
    alert("GET p99 latency exceeds SLO: #{p99 * 1000}ms")
  end
end

# Run SLO check periodically
Thread.new do
  loop do
    sleep 300  # Check every 5 minutes
    check_slo_compliance(REDIS_INSTRUMENTATION)
  end
end
```

### 6. Reset Metrics Carefully

Only reset metrics during maintenance windows or when necessary:

```ruby
# Reset daily at midnight (for daily aggregations)
Thread.new do
  loop do
    now = Time.now
    midnight = Time.new(now.year, now.month, now.day + 1, 0, 0, 0)
    sleep_duration = midnight - now

    sleep sleep_duration

    # Export final snapshot before reset
    final_snapshot = instrumentation.snapshot
    store_daily_metrics(final_snapshot)

    # Reset for new day
    instrumentation.reset!
  end
end
```

### 7. Optimize Percentile Window Size

Balance memory usage and accuracy:

```ruby
# For high-traffic applications (millions of requests/day)
instrumentation = RR::Instrumentation.new(
  percentiles: true,
  percentile_window_size: 10_000  # Keep last 10k samples
)

# For low-traffic applications
instrumentation = RR::Instrumentation.new(
  percentiles: true,
  percentile_window_size: 1_000  # Keep last 1k samples
)
```

### 8. Monitor Pipeline Efficiency

Track pipeline batch sizes for optimization:

```ruby
# Monitor pipeline efficiency
Thread.new do
  loop do
    sleep 60
    snapshot = instrumentation.snapshot

    avg_commands = snapshot[:pipelines][:avg_commands]
    if avg_commands < 5  # Pipelines should batch multiple commands
      logger.warn("Low pipeline efficiency: avg #{avg_commands} commands/pipeline")
    end
  end
end
```

## Troubleshooting

### High Memory Usage with Percentiles

If percentile tracking uses too much memory:

```ruby
# Reduce window size
instrumentation = RR::Instrumentation.new(
  percentiles: true,
  percentile_window_size: 500  # Smaller window
)

# Or disable percentiles
instrumentation = RR::Instrumentation.new(percentiles: false)
```

### Missing Pool Metrics

Ensure instrumentation is passed to pooled clients:

```ruby
# ✅ Correct
pooled = RR.pooled(
  instrumentation: instrumentation,
  pool: { size: 10 }
)

# ❌ Wrong - pool metrics won't be tracked
pooled = RR.pooled(pool: { size: 10 })
```

### Metrics Not Updating

Verify instrumentation is attached to clients:

```ruby
# Check if instrumentation is working
client = RR.new(instrumentation: instrumentation)
client.ping

puts instrumentation.command_count  # Should be > 0
```

