#!/usr/bin/env ruby
# frozen_string_literal: true

# Memory Allocation Comparison: redis-ruby vs redis-rb
#
# Compares memory allocations per operation between the two libraries.
# Lower allocations = less GC pressure = better performance.
#
# Usage:
#   bundle exec ruby benchmarks/memory_comparison.rb
#
# Requires: memory_profiler gem

require "bundler/setup"
require "memory_profiler"
require "json"
require "fileutils"

# Load both implementations
require "redis"
require_relative "../lib/redis_ruby"

REDIS_URL = ENV.fetch("REDIS_URL", "redis://localhost:6379")
ITERATIONS = ENV.fetch("ITERATIONS", "1000").to_i

puts "=" * 70
puts "MEMORY ALLOCATION COMPARISON: redis-ruby vs redis-rb"
puts "=" * 70
puts "Ruby: #{RUBY_VERSION}"
puts "YJIT: #{defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?}"
puts "Iterations: #{ITERATIONS}"
puts "=" * 70
puts

# Initialize clients
redis_rb = Redis.new(url: REDIS_URL)
redis_ruby = RedisRuby.new(url: REDIS_URL)

# Setup test data
redis_rb.set("mem:key", "value")
redis_rb.set("mem:2kb", "x" * 2048)
100.times { |i| redis_rb.set("mem:key:#{i}", "value#{i}") }
redis_rb.hset("mem:hash", "field1", "value1", "field2", "value2")

# Warmup
puts "Warming up..."
100.times do
  redis_rb.get("mem:key")
  redis_ruby.get("mem:key")
end
puts

results = {}

def measure_memory(name, iterations, &block)
  # Force GC before measurement
  GC.start(full_mark: true, immediate_sweep: true)

  report = MemoryProfiler.report do
    iterations.times { block.call }
  end

  {
    total_allocated: report.total_allocated,
    total_allocated_memsize: report.total_allocated_memsize,
    total_retained: report.total_retained,
    total_retained_memsize: report.total_retained_memsize,
    per_iteration: {
      objects: (report.total_allocated.to_f / iterations).round(2),
      bytes: (report.total_allocated_memsize.to_f / iterations).round(0),
    },
  }
end

def compare_memory(name, results, iterations, redis_rb_block:, redis_ruby_block:)
  puts "Measuring: #{name}"
  puts "-" * 50

  rb_stats = measure_memory("redis-rb", iterations, &redis_rb_block)
  ruby_stats = measure_memory("redis-ruby", iterations, &redis_ruby_block)

  # Calculate improvement
  obj_improvement = ((rb_stats[:per_iteration][:objects] - ruby_stats[:per_iteration][:objects]) /
                     rb_stats[:per_iteration][:objects] * 100).round(1)
  bytes_improvement = ((rb_stats[:per_iteration][:bytes] - ruby_stats[:per_iteration][:bytes]) /
                       rb_stats[:per_iteration][:bytes].to_f * 100).round(1)

  puts format("  redis-rb:   %.1f objects/op, %d bytes/op",
              rb_stats[:per_iteration][:objects], rb_stats[:per_iteration][:bytes])
  puts format("  redis-ruby: %.1f objects/op, %d bytes/op",
              ruby_stats[:per_iteration][:objects], ruby_stats[:per_iteration][:bytes])
  puts format("  Improvement: %+.1f%% objects, %+.1f%% bytes",
              obj_improvement, bytes_improvement)
  puts

  results[name] = {
    redis_rb: rb_stats,
    redis_ruby: ruby_stats,
    improvement: {
      objects_percent: obj_improvement,
      bytes_percent: bytes_improvement,
    },
  }
end

# Run memory comparisons
compare_memory("GET (small)", results, ITERATIONS,
               redis_rb_block: -> { redis_rb.get("mem:key") },
               redis_ruby_block: -> { redis_ruby.get("mem:key") })

compare_memory("GET (2KB)", results, ITERATIONS,
               redis_rb_block: -> { redis_rb.get("mem:2kb") },
               redis_ruby_block: -> { redis_ruby.get("mem:2kb") })

compare_memory("SET", results, ITERATIONS,
               redis_rb_block: -> { redis_rb.set("mem:set", "value") },
               redis_ruby_block: -> { redis_ruby.set("mem:set", "value") })

compare_memory("INCR", results, ITERATIONS,
               redis_rb_block: -> { redis_rb.incr("mem:counter") },
               redis_ruby_block: -> { redis_ruby.incr("mem:counter") })

compare_memory("HGET", results, ITERATIONS,
               redis_rb_block: -> { redis_rb.hget("mem:hash", "field1") },
               redis_ruby_block: -> { redis_ruby.hget("mem:hash", "field1") })

compare_memory("Pipeline 10", results, ITERATIONS / 10,
               redis_rb_block: -> { redis_rb.pipelined { |p| 10.times { |i| p.get("mem:key:#{i}") } } },
               redis_ruby_block: -> { redis_ruby.pipelined { |p| 10.times { |i| p.get("mem:key:#{i}") } } })

compare_memory("Pipeline 100", results, ITERATIONS / 100,
               redis_rb_block: -> { redis_rb.pipelined { |p| 100.times { |i| p.get("mem:key:#{i % 100}") } } },
               redis_ruby_block: -> { redis_ruby.pipelined { |p| 100.times { |i| p.get("mem:key:#{i % 100}") } } })

compare_memory("MULTI/EXEC (5 cmds)", results, ITERATIONS / 10,
               redis_rb_block: lambda {
                 redis_rb.multi do |tx|
                   tx.set("mem:tx:1", "v1")
                   tx.set("mem:tx:2", "v2")
                   tx.get("mem:tx:1")
                   tx.incr("mem:counter")
                   tx.del("mem:tx:1")
                 end
               },
               redis_ruby_block: lambda {
                 redis_ruby.multi do |tx|
                   tx.set("mem:tx:1", "v1")
                   tx.set("mem:tx:2", "v2")
                   tx.get("mem:tx:1")
                   tx.incr("mem:counter")
                   tx.del("mem:tx:1")
                 end
               })

# Summary
puts "=" * 70
puts "MEMORY COMPARISON SUMMARY"
puts "=" * 70
puts format("%-25s %15s %15s %12s", "Operation", "redis-rb", "redis-ruby", "Improvement")
puts format("%-25s %15s %15s %12s", "", "(obj/op)", "(obj/op)", "")
puts "-" * 70

results.each do |name, data|
  rb_objs = data[:redis_rb][:per_iteration][:objects]
  ruby_objs = data[:redis_ruby][:per_iteration][:objects]
  improvement = data[:improvement][:objects_percent]
  status = improvement >= 0 ? "BETTER" : "WORSE"

  puts format("%-25s %15.1f %15.1f %+10.1f%% (%s)",
              name, rb_objs, ruby_objs, improvement, status)
end

puts "=" * 70

# Calculate averages
avg_obj_improvement = results.values.sum { |r| r[:improvement][:objects_percent] } / results.size
avg_bytes_improvement = results.values.sum { |r| r[:improvement][:bytes_percent] } / results.size

puts format("Average object allocation improvement: %+.1f%%", avg_obj_improvement)
puts format("Average memory allocation improvement: %+.1f%%", avg_bytes_improvement)
puts "=" * 70

# Save JSON report
FileUtils.mkdir_p("tmp")
report = {
  timestamp: Time.now.iso8601,
  ruby_version: RUBY_VERSION,
  yjit_enabled: defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?,
  iterations: ITERATIONS,
  results: results,
  summary: {
    avg_object_improvement: avg_obj_improvement.round(1),
    avg_bytes_improvement: avg_bytes_improvement.round(1),
  },
}

File.write("tmp/memory_comparison.json", JSON.pretty_generate(report))
puts "\nReport saved to: tmp/memory_comparison.json"

# Cleanup
redis_rb.del("mem:key", "mem:2kb", "mem:set", "mem:counter", "mem:hash")
100.times { |i| redis_rb.del("mem:key:#{i}") }
redis_rb.del("mem:tx:1", "mem:tx:2")

redis_rb.close
redis_ruby.close
