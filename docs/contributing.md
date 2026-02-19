---
layout: default
title: Contributing
permalink: /contributing/
nav_order: 6
---

# Contributing to redis-ruby

Thank you for your interest in contributing to redis-ruby! This guide will help you get started with development, testing, and submitting contributions.

## Table of Contents

- [How to Contribute](#how-to-contribute)
- [Development Setup](#development-setup)
- [Running Tests](#running-tests)
- [Code Style Guidelines](#code-style-guidelines)
- [Pull Request Process](#pull-request-process)
- [Reporting Issues](#reporting-issues)
- [Community](#community)

## How to Contribute

We welcome contributions of all kinds:

- 🐛 **Bug reports** - Help us identify and fix issues
- 💡 **Feature requests** - Suggest new features or improvements
- 📝 **Documentation** - Improve guides, examples, and API docs
- 🧪 **Tests** - Add test coverage for edge cases
- 🔧 **Code** - Fix bugs or implement new features
- 🎨 **Examples** - Share real-world usage examples

## Development Setup

### Prerequisites

- **Ruby 3.2+** (Ruby 3.3+ recommended for YJIT support)
- **Redis 6.2+** (Redis 7.2+ recommended)
- **Git**
- **Bundler**

### Clone the Repository

```bash
git clone https://github.com/redis-developer/redis-ruby.git
cd redis-ruby
```

### Install Dependencies

```bash
bundle install
```

### Start Redis

**Option 1: Docker (Recommended)**

```bash
# For Redis versions >= 8.0
docker run -p 6379:6379 -it redis:latest

# For Redis versions < 8.0
docker run -p 6379:6379 -it redis:7.4
```

**Option 2: Local Installation**

```bash
# macOS
brew install redis
brew services start redis

# Ubuntu/Debian
sudo apt-get install redis-server
sudo systemctl start redis-server
```

### Using the Devcontainer

This project includes a devcontainer with Redis pre-configured:

1. Install [VS Code](https://code.visualstudio.com/) and the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
2. Open the project in VS Code
3. Click "Reopen in Container" when prompted
4. Redis will be automatically started and configured

## Running Tests

### All Tests

```bash
bundle exec rake test
```

### Unit Tests Only

```bash
bundle exec rake test:unit
```

### Integration Tests Only

Integration tests require a running Redis instance:

```bash
# Make sure Redis is running on localhost:6379
bundle exec rake test:integration
```

### Specific Test File

```bash
bundle exec ruby test/integration/commands/strings_test.rb
```

### With YJIT Enabled

```bash
RUBYOPT="--yjit" bundle exec rake test
```

### Test Coverage

```bash
# Run tests with coverage report
bundle exec rake test

# View coverage report
open coverage/index.html
```

## Code Style Guidelines

redis-ruby follows the [RuboCop](https://rubocop.org/) style guide with some project-specific customizations.

### Running RuboCop

```bash
# Check code style
bundle exec rubocop

# Auto-fix issues
bundle exec rubocop -a

# Auto-fix unsafe issues (use with caution)
bundle exec rubocop -A
```

### Style Rules

**String Literals**

```ruby
# ✅ Use double quotes
redis.set("key", "value")

# ❌ Don't use single quotes (unless avoiding escapes)
redis.set('key', 'value')
```

**Frozen String Literals**

```ruby
# ✅ Always include at the top of files
# frozen_string_literal: true

module RR
  # ...
end
```

**Line Length**

```ruby
# ✅ Keep lines under 120 characters
redis.ft_create("idx", "ON", "HASH", "PREFIX", 1, "product:",
                "SCHEMA", "name", "TEXT", "price", "NUMERIC")

# ❌ Don't exceed 120 characters
redis.ft_create("idx", "ON", "HASH", "PREFIX", 1, "product:", "SCHEMA", "name", "TEXT", "price", "NUMERIC", "category", "TAG")
```

**Method Naming**

```ruby
# ✅ Use snake_case for methods
def json_set(key, path, value)
  # ...
end

# ❌ Don't use camelCase
def jsonSet(key, path, value)
  # ...
end
```

**Documentation**

```ruby
# ✅ Document public methods
# Get value from Redis
#
# @param key [String] Redis key
# @return [String, nil] Value or nil if key doesn't exist
def get(key)
  call("GET", key)
end
```

### Code Quality Tools

```bash
# Run all quality checks
bundle exec rake quality:all

# Individual tools
bundle exec rake quality:flog       # ABC complexity
bundle exec rake quality:flay       # Code duplication
bundle exec rake quality:reek       # Code smells
bundle exec rake quality:rubycritic # Unified quality report
```

## Pull Request Process

### 1. Fork the Repository

Click the "Fork" button on GitHub to create your own copy.

### 2. Create a Feature Branch

```bash
git checkout -b my-new-feature
```

Use descriptive branch names:
- `fix/issue-123-connection-leak`
- `feat/add-redis-stack-support`
- `docs/improve-pipeline-guide`

### 3. Make Your Changes

- Write clear, concise code
- Add tests for new functionality
- Update documentation as needed
- Follow the code style guidelines

### 4. Run Tests and Linting

```bash
# Run all tests
bundle exec rake test

# Check code style
bundle exec rubocop

# Run quality checks
bundle exec rake quality:all
```

### 5. Commit Your Changes

Use [Conventional Commits](https://www.conventionalcommits.org/) format:

```bash
# Feature
git commit -am 'feat: add support for Redis Streams'

# Bug fix
git commit -am 'fix: resolve connection leak in pooled client'

# Documentation
git commit -am 'docs: improve pipeline examples'

# Tests
git commit -am 'test: add coverage for ZADD options'

# Refactoring
git commit -am 'refactor: simplify RESP3 encoder'
```

**Commit Message Format:**

```
<type>: <description>

[optional body]

[optional footer]
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `test`: Adding or updating tests
- `refactor`: Code refactoring
- `perf`: Performance improvements
- `chore`: Maintenance tasks

### 6. Push to Your Fork

```bash
git push origin my-new-feature
```

### 7. Create a Pull Request

1. Go to the [redis-ruby repository](https://github.com/redis-developer/redis-ruby)
2. Click "New Pull Request"
3. Select your fork and branch
4. Fill out the PR template with:
   - **Description** - What does this PR do?
   - **Motivation** - Why is this change needed?
   - **Testing** - How was this tested?
   - **Related Issues** - Link to related issues

### 8. Code Review

- Respond to feedback promptly
- Make requested changes
- Push updates to your branch (PR will update automatically)
- Be patient and respectful

### 9. Merge

Once approved, a maintainer will merge your PR. Thank you for contributing! 🎉

## Reporting Issues

### Before Reporting

1. **Search existing issues** - Your issue may already be reported
2. **Check documentation** - Make sure it's not a usage question
3. **Test with latest version** - Update to the latest redis-ruby version

### Creating an Issue

Include the following information:

**Bug Reports:**

```markdown
## Description
Brief description of the bug

## Steps to Reproduce
1. Step 1
2. Step 2
3. Step 3

## Expected Behavior
What should happen

## Actual Behavior
What actually happens

## Environment
- redis-ruby version: 1.0.0
- Ruby version: 3.3.0
- Redis version: 7.2.0
- OS: macOS 14.0

## Additional Context
Any other relevant information
```

**Feature Requests:**

```markdown
## Feature Description
Brief description of the feature

## Use Case
Why is this feature needed?

## Proposed Solution
How should this work?

## Alternatives Considered
Other approaches you've considered

## Additional Context
Any other relevant information
```

## Community

### Getting Help

- 📖 **Documentation** - [https://redis.github.io/redis-ruby](https://redis.github.io/redis-ruby)
- 💬 **GitHub Discussions** - [Ask questions and share ideas](https://github.com/redis-developer/redis-ruby/discussions)
- 🐛 **GitHub Issues** - [Report bugs and request features](https://github.com/redis-developer/redis-ruby/issues)
- 🌐 **Redis Community** - [Join the Redis community](https://redis.io/community/)

### Code of Conduct

We follow the [Contributor Covenant Code of Conduct](https://www.contributor-covenant.org/version/2/1/code_of_conduct/).

Be respectful, inclusive, and professional in all interactions.

## Development Tips

### Running Benchmarks

```bash
# Quick benchmark
RUBYOPT="--yjit" bundle exec ruby benchmarks/compare_basic.rb

# Comprehensive report
RUBYOPT="--yjit" bundle exec ruby benchmarks/generate_comprehensive_report.rb
```

### Debugging

```ruby
# Enable debug logging
redis = RR.new(url: "redis://localhost:6379", logger: Logger.new($stdout))

# Use pry for debugging
require "pry"
binding.pry
```

### Testing Against Different Redis Versions

```bash
# Redis 8.6 (recommended)
docker run -p 6379:6379 redis:latest

# Redis 8.0
docker run -p 6379:6379 redis:8.0

# Redis 7.2
docker run -p 6379:6379 redis:7.2
```

### Working with Advanced Features

```bash
# Start Redis 8.6
docker run -p 6379:6379 redis:latest

# Test JSON commands
bundle exec ruby test/integration/commands/json_test.rb

# Test Search commands
bundle exec ruby test/integration/commands/search_test.rb
```

## Priority Contributions Wanted

We're especially interested in contributions for:

1. **Redis Cluster implementation** - Full cluster support
2. **Pub/Sub enhancements** - Pattern subscriptions, shard channels
3. **Streams implementation** - Consumer groups, XREAD, XADD
4. **Documentation** - More examples and guides
5. **Performance optimizations** - YJIT improvements, encoding optimizations
6. **Test coverage** - Edge cases, error handling, core commands

## License

By contributing to redis-ruby, you agree that your contributions will be licensed under the [MIT License](https://github.com/redis-developer/redis-ruby/blob/main/LICENSE).

## Thank You!

Thank you for contributing to redis-ruby! Your contributions help make Redis better for the Ruby community. 🙏

## Links

- [GitHub Repository](https://github.com/redis-developer/redis-ruby)
- [Issue Tracker](https://github.com/redis-developer/redis-ruby/issues)
- [Pull Requests](https://github.com/redis-developer/redis-ruby/pulls)
- [Discussions](https://github.com/redis-developer/redis-ruby/discussions)
- [Documentation](https://redis.github.io/redis-ruby)
- [Redis Documentation](https://redis.io/docs/)


