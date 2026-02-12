# List Idiomatic API Proposal

## Overview

Create an idiomatic Ruby API for Redis Lists that makes working with queues, stacks, and array-like collections feel natural and Ruby-esque.

## Design Goals

1. **Array-Like Interface** - Familiar `[]`, `<<`, `push`, `pop`, `shift`, `unshift` operations
2. **Queue Operations** - Easy FIFO queue implementation
3. **Stack Operations** - Easy LIFO stack implementation
4. **Range Access** - Ruby-style range queries
5. **Blocking Operations** - Support for blocking pop operations
6. **Composite Keys** - Automatic `:` joining for multi-part keys
7. **Symbol/String Flexibility** - Accept both for values

## API Design

### Entry Point

```ruby
# In lib/redis_ruby/commands/lists.rb
module RedisRuby
  module Commands
    module Lists
      # Create a list proxy for idiomatic operations
      #
      # @param key_parts [Array<String, Symbol, Integer>] Key components
      # @return [RedisRuby::DSL::ListProxy]
      def list(*key_parts)
        DSL::ListProxy.new(self, *key_parts)
      end
    end
  end
end
```

### Core API

```ruby
# Basic operations
queue = redis.list(:jobs)

# Array-like push/pop (right side)
queue << "job1"
queue.push("job2", "job3")
queue.pop  # => "job3" (LIFO from right)

# Queue operations (FIFO)
queue.push("job1")      # Add to right (RPUSH)
queue.shift             # Remove from left (LPOP) - FIFO

# Stack operations (LIFO)
queue.unshift("urgent") # Add to left (LPUSH)
queue.shift             # Remove from left (LPOP) - LIFO

# Array-like access
queue[0]                # First element (LINDEX)
queue[-1]               # Last element
queue[0..2]             # Range (LRANGE)
queue[0, 5]             # Start, count

# Assignment
queue[0] = "new_value"  # LSET

# Insertion
queue.insert_before("job2", "new_job")
queue.insert_after("job2", "another_job")

# Removal
queue.remove("job1")           # Remove all occurrences
queue.remove("job1", count: 1) # Remove first occurrence

# Trimming
queue.trim(0..9)        # Keep only first 10 elements
queue.keep(10)          # Keep only first N elements

# Blocking operations
queue.blocking_pop(timeout: 5)       # BLPOP
queue.blocking_shift(timeout: 5)     # BLPOP (alias)
queue.blocking_pop_right(timeout: 5) # BRPOP

# Inspection
queue.length            # LLEN
queue.size              # Alias
queue.count             # Alias
queue.empty?            # length == 0
queue.exists?           # Key exists

# Conversion
queue.to_a              # All elements as array
queue.first             # First element
queue.last              # Last element
queue.first(5)          # First N elements
queue.last(5)           # Last N elements

# Iteration
queue.each { |item| puts item }
queue.each_with_index { |item, i| puts "#{i}: #{item}" }

# Clear
queue.clear             # Delete all elements

# Expiration
queue.expire(3600)
queue.ttl
queue.persist
```

## Use Cases

### Use Case 1: Job Queue (FIFO)

```ruby
jobs = redis.list(:jobs, :pending)

# Producer adds jobs
jobs.push("process_payment", "send_email", "generate_report")

# Consumer processes jobs
loop do
  job = jobs.shift  # FIFO - get oldest job
  break if job.nil?
  process_job(job)
end

# Blocking consumer (waits for jobs)
loop do
  job = jobs.blocking_shift(timeout: 30)
  break if job.nil?
  process_job(job)
end
```

### Use Case 2: Recent Activity Feed

```ruby
feed = redis.list(:user, 123, :activity)

# Add new activity (to front)
feed.unshift("liked post:456")
feed.unshift("commented on post:789")

# Keep only recent 100 activities
feed.keep(100)

# Get recent 10 activities
recent = feed.first(10)
```

### Use Case 3: Undo Stack (LIFO)

```ruby
undo_stack = redis.list(:editor, :undo)

# Push actions
undo_stack.push("typed 'hello'")
undo_stack.push("deleted word")
undo_stack.push("inserted line")

# Undo (pop from right)
last_action = undo_stack.pop  # => "inserted line"
```

### Use Case 4: Circular Buffer

```ruby
buffer = redis.list(:sensor, :readings)

# Add reading and keep only last 1000
buffer.push(reading)
buffer.trim(0..999)

# Or use keep
buffer.push(reading).keep(1000)
```

## Implementation Details

### Class Structure

```ruby
module RedisRuby
  module DSL
    class ListProxy
      def initialize(redis, *key_parts)
        @redis = redis
        @key = build_key(*key_parts)
      end

      # Array-like push (right side)
      def push(*values)
        return self if values.empty?
        @redis.rpush(@key, *values.map(&:to_s))
        self
      end
      alias << push
      alias append push

      # Array-like pop (right side)
      def pop(count = nil)
        if count.nil?
          @redis.rpop(@key)
        else
          @redis.rpop(@key, count)
        end
      end

      # Queue shift (left side)
      def shift(count = nil)
        if count.nil?
          @redis.lpop(@key)
        else
          @redis.lpop(@key, count)
        end
      end

      # Stack unshift (left side)
      def unshift(*values)
        return self if values.empty?
        @redis.lpush(@key, *values.map(&:to_s))
        self
      end
      alias prepend unshift

      # Array-like access
      def [](index_or_range, count = nil)
        if index_or_range.is_a?(Range)
          @redis.lrange(@key, index_or_range.begin, index_or_range.end)
        elsif count
          @redis.lrange(@key, index_or_range, index_or_range + count - 1)
        else
          @redis.lindex(@key, index_or_range)
        end
      end

      # ... more methods ...
    end
  end
end
```


