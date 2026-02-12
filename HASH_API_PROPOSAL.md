# Hash Idiomatic API Proposal

## Overview

Create an idiomatic Ruby API for Redis Hashes that feels like working with native Ruby Hash objects while maintaining the power of Redis operations.

## Design Goals

1. **Hash-like Interface** - Support `[]`, `[]=`, `keys`, `values`, `to_h`, etc.
2. **Chainable Operations** - Fluent API for multiple operations
3. **Bulk Operations** - Efficient `merge`, `slice`, `update` methods
4. **Atomic Operations** - Support `increment`, `decrement` with proper atomicity
5. **Composite Keys** - Automatic `:` joining for multi-part keys
6. **Symbol/String Flexibility** - Accept both symbols and strings for field names

## API Design

### Entry Point

```ruby
# In lib/redis_ruby/commands/hashes.rb
module RedisRuby
  module Commands
    module Hashes
      # Create a hash proxy for idiomatic operations
      #
      # @param key_parts [Array<String, Symbol, Integer>] Key components
      # @return [RedisRuby::DSL::HashProxy]
      def hash(*key_parts)
        DSL::HashProxy.new(self, *key_parts)
      end
    end
  end
end
```

### Core API

```ruby
# Basic operations
user = redis.hash(:user, 123)

# Hash-like access
user[:name] = "John"              # HSET user:123 name John
user[:email] = "john@example.com" # HSET user:123 email john@example.com
user[:name]                       # => "John" (HGET user:123 name)
user.fetch(:age, 0)               # => 0 (HGET with default)

# Bulk operations
user.merge(age: 30, city: "SF")   # HSET user:123 age 30 city SF
user.update(age: 31)              # Alias for merge
user.to_h                         # => {name: "John", email: "...", age: "31", city: "SF"}

# Chainable operations
redis.hash(:user, 123)
  .set(name: "John", email: "john@example.com")
  .increment(:login_count)
  .increment(:points, 10)
  .expire(3600)

# Existence and inspection
user.exists?                      # => true (EXISTS user:123)
user.key?(:name)                  # => true (HEXISTS user:123 name)
user.keys                         # => [:name, :email, :age, :city]
user.values                       # => ["John", "john@example.com", "31", "SF"]
user.length                       # => 4 (HLEN user:123)
user.size                         # Alias for length

# Deletion
user.delete(:old_field)           # HDEL user:123 old_field
user.delete(:field1, :field2)     # HDEL user:123 field1 field2
user.clear                        # DEL user:123

# Slicing
user.slice(:name, :email)         # => {name: "John", email: "..."}
user.except(:age)                 # => {name: "John", email: "...", city: "SF"}

# Numeric operations
user.increment(:login_count)      # HINCRBY user:123 login_count 1
user.increment(:points, 10)       # HINCRBY user:123 points 10
user.decrement(:credits)          # HINCRBY user:123 credits -1
user.decrement(:balance, 5)       # HINCRBY user:123 balance -5
user.increment_float(:score, 1.5) # HINCRBYFLOAT user:123 score 1.5

# Iteration
user.each { |key, value| puts "#{key}: #{value}" }
user.each_key { |key| puts key }
user.each_value { |value| puts value }

# Expiration (via key operations)
user.expire(3600)                 # EXPIRE user:123 3600
user.expire_at(Time.now + 3600)   # EXPIREAT user:123 ...
user.ttl                          # => 3599 (TTL user:123)
user.persist                      # PERSIST user:123

# Random field (Redis 6.2+)
user.random_field                 # HRANDFIELD user:123
user.random_fields(3)             # HRANDFIELD user:123 3
user.random_fields(3, with_values: true)  # HRANDFIELD user:123 3 WITHVALUES

# Scanning
user.scan(match: "user:*", count: 100) do |field, value|
  puts "#{field}: #{value}"
end
```

## Implementation Details

### Class Structure

```ruby
module RedisRuby
  module DSL
    class HashProxy
      def initialize(redis, *key_parts)
        @redis = redis
        @key = build_key(*key_parts)
      end

      # Hash-like access
      def [](field)
        @redis.hget(@key, field.to_s)
      end

      def []=(field, value)
        @redis.hset(@key, field.to_s, value)
        value
      end

      # Bulk operations
      def set(**fields)
        return self if fields.empty?
        @redis.hset(@key, fields.transform_keys(&:to_s))
        self
      end

      alias_method :merge, :set
      alias_method :update, :set

      def to_h
        result = @redis.hgetall(@key)
        result.transform_keys(&:to_sym)
      end

      # Existence
      def exists?
        @redis.exists(@key) > 0
      end

      def key?(field)
        @redis.hexists(@key, field.to_s)
      end

      # Inspection
      def keys
        @redis.hkeys(@key).map(&:to_sym)
      end

      def values
        @redis.hvals(@key)
      end

      def length
        @redis.hlen(@key)
      end

      alias_method :size, :length

      # ... more methods ...

      private

      def build_key(*parts)
        parts.map(&:to_s).join(":")
      end
    end
  end
end
```

## Examples

### Example 1: User Profile Management

```ruby
# Create/update user profile
user = redis.hash(:user, 123)
  .set(name: "John Doe", email: "john@example.com", age: 30)
  .increment(:login_count)
  .expire(86400)

# Read user data
puts user[:name]           # => "John Doe"
puts user.to_h             # => {name: "John Doe", email: "...", age: "30", login_count: "1"}

# Update specific fields
user[:age] = 31
user.increment(:login_count)
```

### Example 2: Session Storage

```ruby
session = redis.hash(:session, session_id)
  .set(user_id: 123, ip: "192.168.1.1", created_at: Time.now.to_i)
  .expire(1800)  # 30 minutes

# Check session
if session.exists?
  puts "User: #{session[:user_id]}"
  puts "TTL: #{session.ttl} seconds"
end
```

### Example 3: Feature Flags

```ruby
flags = redis.hash(:features, :production)
  .set(new_ui: "true", beta_api: "false", dark_mode: "true")

# Check flag
if flags[:new_ui] == "true"
  render_new_ui
end

# Bulk update
flags.merge(beta_api: "true", experimental: "false")
```


