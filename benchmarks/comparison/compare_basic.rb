#!/usr/bin/env ruby
# frozen_string_literal: true

# Benchmark comparing redis-ruby vs redis-rb performance
#
# Usage: bundle exec ruby benchmarks/compare_basic.rb
#
# Requires REDIS_URL environment variable or defaults to localhost:6379

require "bundler/setup"
require "benchmark/ips"

# Load both implementations
require "redis" # redis-rb gem
require_relative "../../lib/redis_ruby"

REDIS_URL = ENV.fetch("REDIS_URL", "redis://localhost:6379")

puts "=" * 60
puts "Redis Client Benchmark: redis-ruby vs redis-rb"
puts "=" * 60
puts "Ruby version: #{RUBY_VERSION}"
puts "YJIT enabled: #{defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?}"
puts "Redis URL: #{REDIS_URL}"
puts "=" * 60
puts

# Initialize clients
redis_rb = Redis.new(url: REDIS_URL)
redis_ruby = RedisRuby.new(url: REDIS_URL)

# Warmup
puts "Warming up..."
10.times do
  redis_rb.set("benchmark:warmup", "value")
  redis_rb.get("benchmark:warmup")
  redis_ruby.set("benchmark:warmup", "value")
  redis_ruby.get("benchmark:warmup")
end

# Setup test data
redis_rb.set("benchmark:key", "value")
redis_rb.set("benchmark:2kb", "x" * 2048)

puts
puts "Benchmark: PING"
puts "-" * 40
Benchmark.ips do |x|
  x.report("redis-rb") { redis_rb.ping }
  x.report("redis-ruby") { redis_ruby.ping }
  x.compare!
end

puts
puts "Benchmark: GET (small value)"
puts "-" * 40
Benchmark.ips do |x|
  x.report("redis-rb") { redis_rb.get("benchmark:key") }
  x.report("redis-ruby") { redis_ruby.get("benchmark:key") }
  x.compare!
end

puts
puts "Benchmark: GET (2KB value)"
puts "-" * 40
Benchmark.ips do |x|
  x.report("redis-rb") { redis_rb.get("benchmark:2kb") }
  x.report("redis-ruby") { redis_ruby.get("benchmark:2kb") }
  x.compare!
end

puts
puts "Benchmark: SET"
puts "-" * 40
Benchmark.ips do |x|
  x.report("redis-rb") { redis_rb.set("benchmark:set_rb", "value") }
  x.report("redis-ruby") { redis_ruby.set("benchmark:set_ruby", "value") }
  x.compare!
end

puts
puts "Benchmark: SET + GET round-trip"
puts "-" * 40
Benchmark.ips do |x|
  x.report("redis-rb") do
    redis_rb.set("benchmark:roundtrip_rb", "value")
    redis_rb.get("benchmark:roundtrip_rb")
  end
  x.report("redis-ruby") do
    redis_ruby.set("benchmark:roundtrip_ruby", "value")
    redis_ruby.get("benchmark:roundtrip_ruby")
  end
  x.compare!
end

puts
puts "Benchmark: EXISTS"
puts "-" * 40
Benchmark.ips do |x|
  x.report("redis-rb") { redis_rb.exists("benchmark:key") }
  x.report("redis-ruby") { redis_ruby.exists("benchmark:key") }
  x.compare!
end

puts
puts "Benchmark: DEL (non-existent)"
puts "-" * 40
Benchmark.ips do |x|
  x.report("redis-rb") { redis_rb.del("benchmark:nonexistent") }
  x.report("redis-ruby") { redis_ruby.del("benchmark:nonexistent") }
  x.compare!
end

# Cleanup
redis_rb.del("benchmark:warmup", "benchmark:key", "benchmark:2kb",
             "benchmark:set_rb", "benchmark:set_ruby",
             "benchmark:roundtrip_rb", "benchmark:roundtrip_ruby")

redis_rb.close
redis_ruby.close

puts
puts "=" * 60
puts "Benchmark complete!"
puts "=" * 60
