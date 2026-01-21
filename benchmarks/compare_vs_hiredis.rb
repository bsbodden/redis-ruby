#!/usr/bin/env ruby
# frozen_string_literal: true

# Benchmark comparing redis-ruby vs redis-rb with hiredis driver
#
# This is the critical benchmark - we need to beat hiredis which is the
# performance baseline everyone uses.
#
# Usage: RUBYOPT="--yjit" bundle exec ruby benchmarks/compare_vs_hiredis.rb

require "bundler/setup"
require "benchmark/ips"

# Load implementations
require "redis"
require "redis-client"
begin
  require "hiredis-client"
  HIREDIS_AVAILABLE = true
rescue LoadError
  HIREDIS_AVAILABLE = false
end
require_relative "../lib/redis_ruby"

REDIS_URL = ENV.fetch("REDIS_URL", "redis://localhost:6379")

puts "=" * 70
puts "Redis Client Benchmark: redis-ruby vs redis-rb vs hiredis"
puts "=" * 70
puts "Ruby version: #{RUBY_VERSION}"
puts "YJIT enabled: #{defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?}"
puts "hiredis available: #{HIREDIS_AVAILABLE}"
puts "Redis URL: #{REDIS_URL}"
puts "=" * 70
puts

# Parse URL for redis-client
uri = URI.parse(REDIS_URL)

# Initialize clients
redis_rb = Redis.new(url: REDIS_URL)  # Uses redis-client internally (pure Ruby by default)
redis_ruby = RedisRuby.new(url: REDIS_URL)

# Create hiredis client if available
if HIREDIS_AVAILABLE
  # redis-client with hiredis driver
  hiredis_config = RedisClient.config(
    host: uri.host || "localhost",
    port: uri.port || 6379,
    driver: :hiredis
  )
  hiredis_client = hiredis_config.new_client
end

# Warmup
puts "Warming up..."
100.times do
  redis_rb.set("benchmark:warmup", "value")
  redis_rb.get("benchmark:warmup")
  redis_ruby.set("benchmark:warmup", "value")
  redis_ruby.get("benchmark:warmup")
  if HIREDIS_AVAILABLE
    hiredis_client.call("SET", "benchmark:warmup", "value")
    hiredis_client.call("GET", "benchmark:warmup")
  end
end
puts

# Setup test data
redis_rb.set("benchmark:key", "value")
100.times { |i| redis_rb.set("benchmark:key:#{i}", "value#{i}") }

# ============================================================
# Test 1: Single GET
# ============================================================
puts "TEST 1: Single GET"
puts "-" * 50

Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)
  x.report("redis-rb (pure ruby)") { redis_rb.get("benchmark:key") }
  x.report("redis-ruby") { redis_ruby.get("benchmark:key") }
  if HIREDIS_AVAILABLE
    x.report("hiredis-client") { hiredis_client.call("GET", "benchmark:key") }
  end
  x.compare!
end
puts

# ============================================================
# Test 2: Single SET
# ============================================================
puts "TEST 2: Single SET"
puts "-" * 50

Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)
  x.report("redis-rb (pure ruby)") { redis_rb.set("benchmark:set", "value") }
  x.report("redis-ruby") { redis_ruby.set("benchmark:set2", "value") }
  if HIREDIS_AVAILABLE
    x.report("hiredis-client") { hiredis_client.call("SET", "benchmark:set3", "value") }
  end
  x.compare!
end
puts

# ============================================================
# Test 3: Pipeline 10 commands
# ============================================================
puts "TEST 3: Pipeline 10 GETs"
puts "-" * 50

Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)
  x.report("redis-rb (pure ruby)") do
    redis_rb.pipelined do |pipe|
      10.times { |i| pipe.get("benchmark:key:#{i}") }
    end
  end
  x.report("redis-ruby") do
    redis_ruby.pipelined do |pipe|
      10.times { |i| pipe.get("benchmark:key:#{i}") }
    end
  end
  if HIREDIS_AVAILABLE
    x.report("hiredis-client") do
      hiredis_client.pipelined do |pipe|
        10.times { |i| pipe.call("GET", "benchmark:key:#{i}") }
      end
    end
  end
  x.compare!
end
puts

# ============================================================
# Test 4: Pipeline 100 commands
# ============================================================
puts "TEST 4: Pipeline 100 GETs"
puts "-" * 50

Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)
  x.report("redis-rb (pure ruby)") do
    redis_rb.pipelined do |pipe|
      100.times { |i| pipe.get("benchmark:key:#{i % 100}") }
    end
  end
  x.report("redis-ruby") do
    redis_ruby.pipelined do |pipe|
      100.times { |i| pipe.get("benchmark:key:#{i % 100}") }
    end
  end
  if HIREDIS_AVAILABLE
    x.report("hiredis-client") do
      hiredis_client.pipelined do |pipe|
        100.times { |i| pipe.call("GET", "benchmark:key:#{i % 100}") }
      end
    end
  end
  x.compare!
end
puts

# ============================================================
# Test 5: INCR (fast operation)
# ============================================================
puts "TEST 5: INCR"
puts "-" * 50

redis_rb.set("benchmark:counter", "0")

Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)
  x.report("redis-rb (pure ruby)") { redis_rb.incr("benchmark:counter") }
  x.report("redis-ruby") { redis_ruby.incr("benchmark:counter") }
  if HIREDIS_AVAILABLE
    x.report("hiredis-client") { hiredis_client.call("INCR", "benchmark:counter") }
  end
  x.compare!
end
puts

# Cleanup
redis_rb.del("benchmark:warmup", "benchmark:key", "benchmark:set",
             "benchmark:set2", "benchmark:set3", "benchmark:counter")
100.times { |i| redis_rb.del("benchmark:key:#{i}") }

redis_rb.close
redis_ruby.close
hiredis_client.close if HIREDIS_AVAILABLE

puts "=" * 70
puts "Benchmark complete!"
puts "=" * 70
