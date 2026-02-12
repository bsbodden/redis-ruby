# Sorted Set Idiomatic API Proposal

## Overview

Create an idiomatic Ruby API for Redis Sorted Sets that makes working with leaderboards, rankings, and scored collections feel natural and Ruby-esque.

## Design Goals

1. **Leaderboard-Focused** - Optimized for common leaderboard/ranking use cases
2. **Fluent Range Queries** - Chainable methods for range operations
3. **Score-Based Operations** - Easy score manipulation and queries
4. **Set Operations** - Union, intersect, diff with proper chaining
5. **Composite Keys** - Automatic `:` joining for multi-part keys
6. **Symbol/String Flexibility** - Accept both for member names

## API Design

### Entry Point

```ruby
# In lib/redis_ruby/commands/sorted_sets.rb
module RedisRuby
  module Commands
    module SortedSets
      # Create a sorted set proxy for idiomatic operations
      #
      # @param key_parts [Array<String, Symbol, Integer>] Key components
      # @return [RedisRuby::DSL::SortedSetProxy]
      def sorted_set(*key_parts)
        DSL::SortedSetProxy.new(self, *key_parts)
      end
    end
  end
end
```

### Core API

```ruby
# Basic operations
leaderboard = redis.sorted_set(:leaderboard)

# Add members with scores
leaderboard.add(player1: 100, player2: 200, player3: 150)
leaderboard.add(:player4, 175)  # Single member

# Increment scores
leaderboard.increment(:player1, 10)  # => 110
leaderboard.decrement(:player1, 5)   # => 105

# Get score
leaderboard.score(:player1)  # => 105.0

# Get rank (0-based, ascending by default)
leaderboard.rank(:player1)      # => 0 (lowest score)
leaderboard.reverse_rank(:player1)  # => 2 (from highest)

# Range queries - Top/Bottom
leaderboard.top(10)              # Top 10 by score (descending)
leaderboard.bottom(5)            # Bottom 5 by score (ascending)
leaderboard.range(0..9)          # Range by rank (ascending)
leaderboard.reverse_range(0..9)  # Range by rank (descending)

# Score-based ranges
leaderboard.by_score(100..200)   # Members with scores 100-200
leaderboard.by_score(100, :inf)  # Members with scores >= 100

# Chaining with options
leaderboard.top(10)
  .with_scores                   # Include scores
  .limit(5)                      # Limit results

# Iteration
leaderboard.each { |member, score| puts "#{member}: #{score}" }
leaderboard.each_member { |member| puts member }

# Removal
leaderboard.remove(:player1)
leaderboard.remove_by_rank(0..4)      # Remove bottom 5
leaderboard.remove_by_score(0..50)    # Remove scores 0-50

# Count operations
leaderboard.count                     # Total members
leaderboard.count_by_score(100..200)  # Count in score range

# Set operations
redis.sorted_set(:result).union(:set1, :set2)
redis.sorted_set(:result).intersect(:set1, :set2)
redis.sorted_set(:result).diff(:set1, :set2)

# Existence
leaderboard.exists?              # Key exists
leaderboard.member?(:player1)    # Member exists

# Clear
leaderboard.clear                # Remove all members
```

## Use Cases

### Use Case 1: Gaming Leaderboard

```ruby
leaderboard = redis.sorted_set(:game, :leaderboard)

# Add players with scores
leaderboard.add(
  alice: 1500,
  bob: 2000,
  charlie: 1800,
  diana: 2200
)

# Get top 10 players
top_players = leaderboard.top(10).with_scores.execute
top_players.each do |player, score|
  puts "#{player}: #{score} points"
end

# Update score when player wins
leaderboard.increment(:alice, 100)

# Get player's rank
rank = leaderboard.reverse_rank(:alice)  # 0 = 1st place
puts "Alice is rank ##{rank + 1}"

# Get players in score range
mid_tier = leaderboard.by_score(1500..2000).execute
```

### Use Case 2: Time-Based Rankings

```ruby
recent_posts = redis.sorted_set(:posts, :recent)

# Add posts with timestamps as scores
recent_posts.add(
  "post:123" => Time.now.to_i,
  "post:124" => Time.now.to_i - 3600,
  "post:125" => Time.now.to_i - 7200
)

# Get most recent posts
latest = recent_posts.top(10).execute

# Remove old posts (older than 24 hours)
cutoff = Time.now.to_i - 86400
recent_posts.remove_by_score(-Float::INFINITY, cutoff)
```

### Use Case 3: Priority Queue

```ruby
queue = redis.sorted_set(:tasks, :priority)

# Add tasks with priority scores (lower = higher priority)
queue.add(
  "urgent_task" => 1,
  "normal_task" => 5,
  "low_priority" => 10
)

# Get highest priority task
task = queue.bottom(1).execute.first

# Process and remove
queue.remove(task)
```

## Implementation Details

### Class Structure

```ruby
module RedisRuby
  module DSL
    class SortedSetProxy
      def initialize(redis, *key_parts)
        @redis = redis
        @key = build_key(*key_parts)
      end

      # Add members with scores
      def add(*args, **kwargs)
        if args.empty?
          # add(player1: 100, player2: 200)
          add_from_hash(kwargs)
        elsif args.size == 2
          # add(:player1, 100)
          @redis.zadd(@key, args[1], args[0].to_s)
        else
          raise ArgumentError, "Invalid arguments"
        end
        self
      end

      # Get top N members (highest scores)
      def top(n)
        SortedSetRangeBuilder.new(@redis, @key, :top, n)
      end

      # Get bottom N members (lowest scores)
      def bottom(n)
        SortedSetRangeBuilder.new(@redis, @key, :bottom, n)
      end

      # ... more methods ...
    end

    class SortedSetRangeBuilder
      def initialize(redis, key, type, limit)
        @redis = redis
        @key = key
        @type = type
        @limit = limit
        @with_scores = false
      end

      def with_scores
        @with_scores = true
        self
      end

      def execute
        case @type
        when :top
          @redis.zrevrange(@key, 0, @limit - 1, with_scores: @with_scores)
        when :bottom
          @redis.zrange(@key, 0, @limit - 1, with_scores: @with_scores)
        end
      end
    end
  end
end
```


