#!/usr/bin/env ruby
# frozen_string_literal: true

# Comprehensive benchmark comparing redis-ruby vs redis-rb
#
# Performance Gates from CLAUDE.md:
# - Single GET/SET: 1.3x faster than redis-rb
# - Pipeline (10 cmds): 1.5x faster than redis-rb
# - Pipeline (100 cmds): 2x faster than redis-rb
# - Connection setup: Equal or faster than redis-rb
#
# Usage: RUBYOPT="--yjit" bundle exec ruby benchmarks/compare_comprehensive.rb

require "bundler/setup"
require "benchmark/ips"

# Load both implementations
require "redis" # redis-rb gem
require_relative "../lib/redis_ruby"

REDIS_URL = ENV.fetch("REDIS_URL", "redis://localhost:6379")

puts "=" * 70
puts "Comprehensive Redis Client Benchmark: redis-ruby vs redis-rb"
puts "=" * 70
puts "Ruby version: #{RUBY_VERSION}"
puts "YJIT enabled: #{defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?}"
puts "Redis URL: #{REDIS_URL}"
puts
puts "Performance Gates (from CLAUDE.md):"
puts "  - Single GET/SET: 1.3x faster"
puts "  - Pipeline (10 cmds): 1.5x faster"
puts "  - Pipeline (100 cmds): 2x faster"
puts "  - Connection setup: Equal or faster"
puts "=" * 70
puts

# Initialize clients
redis_rb = Redis.new(url: REDIS_URL)
redis_ruby = RedisRuby.new(url: REDIS_URL)

# Warmup
puts "Warming up..."
100.times do
  redis_rb.set("benchmark:warmup", "value")
  redis_rb.get("benchmark:warmup")
  redis_ruby.set("benchmark:warmup", "value")
  redis_ruby.get("benchmark:warmup")
end
puts

# Setup test data
redis_rb.set("benchmark:key", "value")
redis_rb.set("benchmark:2kb", "x" * 2048)
100.times { |i| redis_rb.set("benchmark:key:#{i}", "value#{i}") }

# ============================================================
# Test 1: Connection Setup
# ============================================================
puts "TEST 1: Connection Setup (Gate: Equal or faster)"
puts "-" * 50

Benchmark.ips do |x|
  x.config(warmup: 1, time: 5)
  x.report("redis-rb") do
    c = Redis.new(url: REDIS_URL)
    c.ping
    c.close
  end
  x.report("redis-ruby") do
    c = RedisRuby.new(url: REDIS_URL)
    c.ping
    c.close
  end
  x.compare!
end
puts

# ============================================================
# Test 2: Single GET
# ============================================================
puts "TEST 2: Single GET (Gate: 1.3x faster)"
puts "-" * 50

Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)
  x.report("redis-rb") { redis_rb.get("benchmark:key") }
  x.report("redis-ruby") { redis_ruby.get("benchmark:key") }
  x.compare!
end
puts

# ============================================================
# Test 3: Single SET
# ============================================================
puts "TEST 3: Single SET (Gate: 1.3x faster)"
puts "-" * 50

Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)
  x.report("redis-rb") { redis_rb.set("benchmark:set_rb", "value") }
  x.report("redis-ruby") { redis_ruby.set("benchmark:set_ruby", "value") }
  x.compare!
end
puts

# ============================================================
# Test 4: Pipeline 10 commands
# ============================================================
puts "TEST 4: Pipeline 10 commands (Gate: 1.5x faster)"
puts "-" * 50

Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)
  x.report("redis-rb") do
    redis_rb.pipelined do |pipe|
      10.times { |i| pipe.get("benchmark:key:#{i}") }
    end
  end
  x.report("redis-ruby") do
    redis_ruby.pipelined do |pipe|
      10.times { |i| pipe.get("benchmark:key:#{i}") }
    end
  end
  x.compare!
end
puts

# ============================================================
# Test 5: Pipeline 100 commands
# ============================================================
puts "TEST 5: Pipeline 100 commands (Gate: 2x faster)"
puts "-" * 50

Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)
  x.report("redis-rb") do
    redis_rb.pipelined do |pipe|
      100.times { |i| pipe.get("benchmark:key:#{i % 100}") }
    end
  end
  x.report("redis-ruby") do
    redis_ruby.pipelined do |pipe|
      100.times { |i| pipe.get("benchmark:key:#{i % 100}") }
    end
  end
  x.compare!
end
puts

# ============================================================
# Test 6: Mixed workload
# ============================================================
puts "TEST 6: Mixed Workload (SET + GET + EXISTS + DEL)"
puts "-" * 50

Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)
  x.report("redis-rb") do
    redis_rb.set("benchmark:mixed_rb", "value")
    redis_rb.get("benchmark:mixed_rb")
    redis_rb.exists("benchmark:mixed_rb")
    redis_rb.del("benchmark:mixed_rb")
  end
  x.report("redis-ruby") do
    redis_ruby.set("benchmark:mixed_ruby", "value")
    redis_ruby.get("benchmark:mixed_ruby")
    redis_ruby.exists("benchmark:mixed_ruby")
    redis_ruby.del("benchmark:mixed_ruby")
  end
  x.compare!
end
puts

# ============================================================
# Test 7: INCR
# ============================================================
puts "TEST 7: INCR Operation"
puts "-" * 50

redis_rb.set("benchmark:counter", "0")

Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)
  x.report("redis-rb") { redis_rb.incr("benchmark:counter") }
  x.report("redis-ruby") { redis_ruby.incr("benchmark:counter") }
  x.compare!
end
puts

# Cleanup
redis_rb.del("benchmark:warmup", "benchmark:key", "benchmark:2kb",
             "benchmark:set_rb", "benchmark:set_ruby",
             "benchmark:mixed_rb", "benchmark:mixed_ruby",
             "benchmark:counter")
100.times { |i| redis_rb.del("benchmark:key:#{i}") }

redis_rb.close
redis_ruby.close

puts "=" * 70
puts "Benchmark complete!"
puts "=" * 70
