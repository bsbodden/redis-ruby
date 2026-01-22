#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "benchmark/ips"
require "redis"
require_relative "../lib/redis_ruby"

REDIS_URL = ENV.fetch("REDIS_URL", "redis://localhost:6379")

redis_rb = Redis.new(url: REDIS_URL)
redis_ruby = RedisRuby.new(url: REDIS_URL)

# Setup test data
redis_rb.set("benchmark:key", "value")
10.times { |i| redis_rb.set("benchmark:key:#{i}", "value#{i}") }

puts "=" * 60
puts "Performance Comparison: redis-ruby vs redis-rb"
puts "=" * 60
puts "Ruby: #{RUBY_VERSION}"
puts "YJIT: #{defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?}"
puts "=" * 60

puts "\nSingle GET:"
puts "-" * 40
Benchmark.ips do |x|
  x.config(warmup: 2, time: 3)
  x.report("redis-rb") { redis_rb.get("benchmark:key") }
  x.report("redis-ruby") { redis_ruby.get("benchmark:key") }
  x.compare!
end

puts "\nSingle SET:"
puts "-" * 40
Benchmark.ips do |x|
  x.config(warmup: 2, time: 3)
  x.report("redis-rb") { redis_rb.set("benchmark:test", "val") }
  x.report("redis-ruby") { redis_ruby.set("benchmark:test", "val") }
  x.compare!
end

puts "\nPipeline 10:"
puts "-" * 40
Benchmark.ips do |x|
  x.config(warmup: 2, time: 3)
  x.report("redis-rb") { redis_rb.pipelined { |p| 10.times { |i| p.get("benchmark:key:#{i}") } } }
  x.report("redis-ruby") { redis_ruby.pipelined { |p| 10.times { |i| p.get("benchmark:key:#{i}") } } }
  x.compare!
end

puts "\nPipeline 100:"
puts "-" * 40
Benchmark.ips do |x|
  x.config(warmup: 2, time: 3)
  x.report("redis-rb") { redis_rb.pipelined { |p| 100.times { |i| p.get("benchmark:key:#{i % 10}") } } }
  x.report("redis-ruby") { redis_ruby.pipelined { |p| 100.times { |i| p.get("benchmark:key:#{i % 10}") } } }
  x.compare!
end

# Cleanup
redis_rb.del("benchmark:key", "benchmark:test")
10.times { |i| redis_rb.del("benchmark:key:#{i}") }

redis_rb.close
redis_ruby.close
