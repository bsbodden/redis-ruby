# Redis Streams Idiomatic Ruby API Proposal

## Overview

Design an idiomatic Ruby API for Redis Streams that makes stream processing feel natural and Ruby-esque, while maintaining full backward compatibility with the existing low-level API.

## Design Principles

1. **Chainable Operations** - Fluent interface for common workflows
2. **Symbol-based Keys** - Use symbols for field names and options
3. **Block-based DSL** - For complex configurations (consumer groups)
4. **Composite Keys** - Automatic key joining with `:` separator
5. **Ruby Conventions** - Use Ruby idioms (each, map, select, etc.)
6. **Backward Compatible** - All existing methods continue to work

## Proposed API Components

### 1. Stream Proxy (`stream` method)

Chainable proxy for stream operations on a single stream.

```ruby
# Create proxy
stream = redis.stream(:events)
stream = redis.stream(:metrics, :temperature)  # => "metrics:temperature"

# Add entries (chainable)
stream.add(sensor: "temp", value: 23.5)
      .add(sensor: "temp", value: 24.0)
      .add(sensor: "temp", value: 23.8)

# Add with options
stream.add({temp: 23.5}, id: "1000-0", maxlen: 1000)

# Trim stream
stream.trim(maxlen: 1000)
stream.trim(minid: "1000-0", approximate: true)

# Get length
stream.length  # or .size, .count

# Delete entries
stream.delete("1000-0", "1000-1")

# Get info
stream.info
stream.info(full: true)
```

### 2. Stream Reader (`read` method)

Fluent builder for reading from streams.

```ruby
# Read from single stream
entries = stream.read
  .from("0-0")          # Start ID
  .count(10)            # Limit
  .execute

# Read with range
entries = stream.read
  .range("-", "+")      # All entries
  .count(100)
  .execute

# Reverse range
entries = stream.read
  .reverse_range("+", "-")
  .count(10)
  .execute

# Block for new entries
entries = stream.read
  .from("$")            # Only new
  .block(5000)          # 5 seconds
  .execute

# Iterate over entries
stream.read.from("0-0").each do |id, fields|
  puts "#{id}: #{fields}"
end
```

### 3. Consumer Group DSL (`consumer_group` method)

Block-based DSL for consumer group operations.

```ruby
# Create consumer group
redis.consumer_group(:events, :processors) do
  create_from "$"                    # Start from new entries
  # or: create_from_beginning
  # or: create_from "1000-0"
end

# Create with mkstream
redis.consumer_group(:new_stream, :workers) do
  create_from "$", mkstream: true
end

# Destroy group
redis.consumer_group(:events, :processors) do
  destroy
end

# Set ID
redis.consumer_group(:events, :processors) do
  set_id "1000-0"
end
```

### 4. Consumer Proxy (`consumer` method)

Chainable proxy for consumer operations within a group.

```ruby
# Get consumer proxy
consumer = redis.stream(:events).consumer(:processors, :worker1)

# Read as consumer
entries = consumer.read
  .count(10)
  .block(5000)
  .execute

# Read without ack
entries = consumer.read
  .count(10)
  .noack
  .execute

# Acknowledge entries
consumer.ack("1000-0", "1000-1", "1000-2")

# Get pending entries
pending = consumer.pending
pending = consumer.pending(count: 10, consumer: :worker1)

# Claim entries
claimed = consumer.claim(min_idle: 60000, ids: ["1000-0", "1000-1"])

# Auto-claim
claimed = consumer.autoclaim(min_idle: 60000, start: "0-0", count: 10)
```

### 5. Multi-Stream Reader (`streams` method)

Read from multiple streams simultaneously.

```ruby
# Read from multiple streams
results = redis.streams(
  events: "0-0",
  metrics: "0-0",
  logs: "$"
).count(10).execute

# Returns: { "events" => [[id, fields], ...], "metrics" => [...], ... }

# With blocking
results = redis.streams(
  events: "$",
  metrics: "$"
).block(5000).execute
```

## Implementation Files

1. **lib/redis_ruby/dsl/stream_proxy.rb** - Stream proxy for single stream operations
2. **lib/redis_ruby/dsl/stream_reader.rb** - Fluent reader builder
3. **lib/redis_ruby/dsl/consumer_group_builder.rb** - DSL for consumer group operations
4. **lib/redis_ruby/dsl/consumer_proxy.rb** - Consumer operations proxy
5. **lib/redis_ruby/dsl/multi_stream_reader.rb** - Multi-stream reader
6. **lib/redis_ruby/commands/streams.rb** - Add idiomatic methods
7. **test/integration/dsl/streams_dsl_test.rb** - Integration tests
8. **examples/idiomatic_streams_api.rb** - Comprehensive examples

## Next Steps

1. Review and approve design
2. Implement core components (StreamProxy, StreamReader)
3. Implement consumer group components
4. Add tests
5. Create examples
6. Update documentation

