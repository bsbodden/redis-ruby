# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :development do
  gem "rake", "~> 13.0"
  gem "rubocop", "~> 1.68"
  gem "rubocop-minitest", "~> 0.36"
  gem "rubocop-rake", "~> 0.6"
  gem "rubocop-performance", "~> 1.22"
  gem "yard", "~> 0.9"
  gem "debug", "~> 1.9"
  gem "benchmark-ips", "~> 2.13"
  gem "redis", "~> 5.0"  # For benchmarking against redis-rb
end

# Code quality tools (similar to Python's mfcqi)
group :quality do
  gem "rubycritic", "~> 4.9"      # Unified quality report (wraps Flog, Flay, Reek)
  gem "flog", "~> 4.8"            # ABC complexity metrics
  gem "flay", "~> 2.13"           # Code duplication detection
  gem "reek", "~> 6.3"            # Code smell detection
  gem "debride", "~> 1.12"        # Find unused methods
  gem "fasterer", "~> 0.11"       # Performance suggestions
end

# Profiling tools
group :profiling do
  gem "stackprof", "~> 0.2"       # Sampling CPU profiler
  gem "vernier", "~> 1.0"         # Modern sampling profiler (YJIT-aware)
  gem "memory_profiler", "~> 1.0" # Memory allocation profiler
  gem "allocation_tracer"         # Object allocation tracking
end

group :test do
  gem "minitest", "~> 5.25"
  gem "minitest-reporters", "~> 1.7"
  gem "testcontainers-core", "~> 0.2"
  gem "testcontainers-redis", "~> 0.2"
  gem "mocha", "~> 2.4"
  gem "simplecov", "~> 0.22", require: false
  gem "base64"  # Required for Ruby 3.4+
end

# Async support (optional, for async client)
group :async do
  gem "async", "~> 2.0"
  gem "async-io", "~> 1.0"
  gem "async-pool", "~> 0.8"  # Fiber-aware connection pooling
end
