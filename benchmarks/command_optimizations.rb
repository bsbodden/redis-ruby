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
redis_rb.set("bench:key", "value")
redis_rb.hset("bench:hash", "field1", "value1")
redis_rb.lpush("bench:list", ["item1", "item2", "item3"])
10.times { |i| redis_rb.set("bench:key:#{i}", "value#{i}") }

puts "=" * 70
puts "COMMAND OPTIMIZATION BENCHMARK: redis-ruby vs redis-rb"
puts "=" * 70
puts "Ruby #{RUBY_VERSION} | YJIT: #{defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?}"
puts "=" * 70

results = {}

# Helper to run benchmark and store results
def run_benchmark(name, results)
  puts "\n### #{name} ###"
  report = Benchmark.ips do |x|
    x.config(warmup: 2, time: 5)
    yield x
    x.compare!
  end

  rb_entry = report.entries.find { |e| e.label.include?("redis-rb") }
  ruby_entry = report.entries.find { |e| e.label.include?("redis-ruby") }

  if rb_entry && ruby_entry
    results[name] = {
      rb: rb_entry.stats.central_tendency,
      ruby: ruby_entry.stats.central_tendency,
      speedup: ruby_entry.stats.central_tendency / rb_entry.stats.central_tendency
    }
  end
end

# Hash Commands
run_benchmark("HGET", results) do |x|
  x.report("redis-rb HGET") { redis_rb.hget("bench:hash", "field1") }
  x.report("redis-ruby HGET") { redis_ruby.hget("bench:hash", "field1") }
end

run_benchmark("HSET", results) do |x|
  x.report("redis-rb HSET") { redis_rb.hset("bench:hash", "field1", "newval") }
  x.report("redis-ruby HSET") { redis_ruby.hset("bench:hash", "field1", "newval") }
end

run_benchmark("HDEL", results) do |x|
  x.report("redis-rb HDEL") { redis_rb.hdel("bench:hash", "nonexistent") }
  x.report("redis-ruby HDEL") { redis_ruby.hdel("bench:hash", "nonexistent") }
end

# List Commands
run_benchmark("LPUSH", results) do |x|
  x.report("redis-rb LPUSH") { redis_rb.lpush("bench:list", "item") }
  x.report("redis-ruby LPUSH") { redis_ruby.lpush("bench:list", "item") }
end

run_benchmark("RPUSH", results) do |x|
  x.report("redis-rb RPUSH") { redis_rb.rpush("bench:list", "item") }
  x.report("redis-ruby RPUSH") { redis_ruby.rpush("bench:list", "item") }
end

run_benchmark("LPOP", results) do |x|
  # Ensure list has items
  redis_rb.lpush("bench:poplist", "a")
  redis_ruby.lpush("bench:poplist", "a")
  x.report("redis-rb LPOP") { redis_rb.lpush("bench:poplist", "x"); redis_rb.lpop("bench:poplist") }
  x.report("redis-ruby LPOP") { redis_ruby.lpush("bench:poplist", "x"); redis_ruby.lpop("bench:poplist") }
end

run_benchmark("RPOP", results) do |x|
  x.report("redis-rb RPOP") { redis_rb.rpush("bench:poplist", "x"); redis_rb.rpop("bench:poplist") }
  x.report("redis-ruby RPOP") { redis_ruby.rpush("bench:poplist", "x"); redis_ruby.rpop("bench:poplist") }
end

# Key Commands
run_benchmark("EXPIRE", results) do |x|
  x.report("redis-rb EXPIRE") { redis_rb.expire("bench:key", 3600) }
  x.report("redis-ruby EXPIRE") { redis_ruby.expire("bench:key", 3600) }
end

run_benchmark("TTL", results) do |x|
  x.report("redis-rb TTL") { redis_rb.ttl("bench:key") }
  x.report("redis-ruby TTL") { redis_ruby.ttl("bench:key") }
end

# Batch Commands
run_benchmark("MGET (5 keys)", results) do |x|
  keys = (0..4).map { |i| "bench:key:#{i}" }
  x.report("redis-rb MGET") { redis_rb.mget(*keys) }
  x.report("redis-ruby MGET") { redis_ruby.mget(*keys) }
end

run_benchmark("MSET (5 keys)", results) do |x|
  x.report("redis-rb MSET") { redis_rb.mset("k1", "v1", "k2", "v2", "k3", "v3", "k4", "v4", "k5", "v5") }
  x.report("redis-ruby MSET") { redis_ruby.mset("k1", "v1", "k2", "v2", "k3", "v3", "k4", "v4", "k5", "v5") }
end

# Summary
puts "\n" + "=" * 70
puts "SUMMARY"
puts "=" * 70
puts format("%-20s %15s %15s %10s", "Command", "redis-rb", "redis-ruby", "Speedup")
puts "-" * 70

results.each do |name, data|
  speedup_str = format("%.2fx", data[:speedup])
  speedup_str = data[:speedup] >= 1.0 ? speedup_str : speedup_str
  puts format("%-20s %12.1f i/s %12.1f i/s %10s",
              name, data[:rb], data[:ruby], speedup_str)
end

puts "=" * 70

# Cleanup
redis_rb.del("bench:key", "bench:hash", "bench:list", "bench:poplist")
10.times { |i| redis_rb.del("bench:key:#{i}") }
redis_rb.del("k1", "k2", "k3", "k4", "k5")

redis_rb.close
redis_ruby.close
