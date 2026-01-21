# redis-ruby

A modern, high-performance Redis client for Ruby.

## Features

- Built on `redis-client` for maximum performance
- Full Redis 8+ support including JSON, Search, TimeSeries
- Connection pooling out of the box
- Idiomatic Ruby API
- Comprehensive test suite with TestContainers

## Installation

Add to your Gemfile:

```ruby
gem "redis-ruby"
```

## Quick Start

```ruby
require "redis_ruby"

# Connect to Redis
redis = RedisRuby.new(url: "redis://localhost:6379")

# Basic operations
redis.set("greeting", "Hello, Redis!")
redis.get("greeting")  # => "Hello, Redis!"

# With expiration
redis.set("session", "abc123", ex: 3600)

# Connection pooling
redis = RedisRuby.new(
  url: "redis://localhost:6379",
  pool: { size: 5, timeout: 5 }
)
```

## Development

```bash
# Clone the repository
git clone https://github.com/redis/redis-ruby.git
cd redis-ruby

# Install dependencies
bundle install

# Run tests
bundle exec rake test

# Run linting
bundle exec rubocop
```

### Using the DevContainer

This project includes a devcontainer with Redis Stack pre-configured:

1. Open in VS Code with the Dev Containers extension
2. Click "Reopen in Container"
3. Run `bundle install && bundle exec rake test`

## License

MIT License - see [LICENSE](LICENSE) for details.
