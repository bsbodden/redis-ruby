# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :development do
  gem "benchmark-ips", "~> 2.13"
  gem "debug", "~> 1.9"
  gem "hiredis", "~> 0.6" # For benchmarking redis-rb with hiredis
  gem "rake", "~> 13.0"
  gem "redis", "~> 5.0" # For benchmarking against redis-rb
  gem "rubocop", "~> 1.68"
  gem "rubocop-minitest", "~> 0.36"
  gem "rubocop-performance", "~> 1.22"
  gem "rubocop-rake", "~> 0.6"
  gem "yard", "~> 0.9"
end

# Code quality tools (similar to Python's mfcqi)
group :quality do
  gem "debride", "~> 1.12"        # Find unused methods
  gem "fasterer", "~> 0.11"       # Performance suggestions
  gem "flay", "~> 2.13"           # Code duplication detection
  gem "flog", "~> 4.8"            # ABC complexity metrics
  gem "reek", "~> 6.3"            # Code smell detection
  gem "rubycritic", "~> 4.9"      # Unified quality report (wraps Flog, Flay, Reek)
end

# Profiling tools
group :profiling do
  gem "allocation_tracer"         # Object allocation tracking
  gem "memory_profiler", "~> 1.0" # Memory allocation profiler
  gem "stackprof", "~> 0.2"       # Sampling CPU profiler
  gem "vernier", "~> 1.0"         # Modern sampling profiler (YJIT-aware)
end

group :test do
  gem "base64" # Required for Ruby 3.4+
  gem "minitest", "~> 5.25"
  gem "minitest-reporters", "~> 1.7"
  gem "mocha", "~> 2.4"
  gem "simplecov", "~> 0.22", require: false
  gem "testcontainers-core", "~> 0.2"
  gem "testcontainers-redis", "~> 0.2"
  gem "webmock", "~> 3.24"
end

# Async support (optional, for async client)
group :async do
  gem "async", "~> 2.0"
  gem "async-io", "~> 1.0"
  gem "async-pool", "~> 0.11" # Fiber-aware connection pooling
end
