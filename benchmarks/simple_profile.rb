#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple profiling script - memory and stackprof only
#
# Usage:
#   RUBYOPT="--yjit" bundle exec ruby benchmarks/simple_profile.rb

require "bundler/setup"
require_relative "../lib/redis_ruby"
require "fileutils"
require "memory_profiler"
require "stackprof"

FileUtils.mkdir_p("tmp/profiles")

ITERATIONS = 5_000
PIPELINE_SIZE = 100

puts "=" * 70
puts "Redis-Ruby Simple Profiler"
puts "=" * 70
puts "Ruby: #{RUBY_VERSION}"
puts "YJIT: #{defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?}"
puts "=" * 70
puts

# Connect to Redis
redis = RedisRuby.new(host: ENV.fetch("REDIS_HOST", "redis"), port: ENV.fetch("REDIS_PORT", 6379).to_i)
redis.set("profile_key", "x" * 100)

# Warm up
puts "Warming up..."
2000.times { redis.get("profile_key") }
2000.times { redis.set("profile_key", "warmup") }
20.times do
  redis.pipelined do |p|
    PIPELINE_SIZE.times { |i| p.set("pipe_#{i}", "v#{i}") }
  end
end
puts "Warmup complete."

# ============================================================
# 1. Memory Profiler - Single Operations
# ============================================================
puts "\n" + "=" * 70
puts "1. MEMORY - Single GET operations (1000x)"
puts "=" * 70

report = MemoryProfiler.report do
  1000.times { redis.get("profile_key") }
end

puts "\nAllocations by location (redis-ruby only):"
puts "-" * 70
report.allocated_objects_by_location
      .select { |s| s[:data].include?("redis_ruby") }
      .first(15)
      .each do |stat|
        short_path = stat[:data].gsub(%r{.*/lib/}, "")
        puts format("  %-55s %8d", short_path, stat[:count])
      end

# ============================================================
# 2. Memory Profiler - Pipeline Operations
# ============================================================
puts "\n" + "=" * 70
puts "2. MEMORY - Pipeline operations (100 cmds x 50 pipelines)"
puts "=" * 70

report = MemoryProfiler.report do
  50.times do
    redis.pipelined do |p|
      100.times { |i| p.get("pipe_#{i}") }
    end
  end
end

puts "\nAllocations by location (redis-ruby only):"
puts "-" * 70
report.allocated_objects_by_location
      .select { |s| s[:data].include?("redis_ruby") }
      .first(15)
      .each do |stat|
        short_path = stat[:data].gsub(%r{.*/lib/}, "")
        puts format("  %-55s %8d", short_path, stat[:count])
      end

# ============================================================
# 3. StackProf - CPU Profiling
# ============================================================
puts "\n" + "=" * 70
puts "3. STACKPROF - CPU Profiling"
puts "=" * 70

profile = StackProf.run(mode: :cpu, raw: true, interval: 100) do
  ITERATIONS.times do |i|
    redis.get("profile_key")
    redis.set("profile_key", "value_#{i}")
    next unless (i % 20).zero?
    redis.pipelined do |p|
      PIPELINE_SIZE.times { |j| p.get("pipe_#{j}") }
    end
  end
end

File.write("tmp/profiles/stackprof_cpu.json", JSON.generate(profile))

puts "\nTop 25 Methods by CPU Time:"
puts "-" * 70
StackProf::Report.new(profile).print_text(false, 25)

# ============================================================
# 4. Allocation per operation measurement
# ============================================================
puts "\n" + "=" * 70
puts "4. ALLOCATIONS PER OPERATION"
puts "=" * 70

GC.start
before = GC.stat[:total_allocated_objects]
1000.times { redis.get("profile_key") }
after = GC.stat[:total_allocated_objects]
puts format("  GET: %.2f objects/call", (after - before) / 1000.0)

GC.start
before = GC.stat[:total_allocated_objects]
1000.times { |i| redis.set("profile_key", "v#{i}") }
after = GC.stat[:total_allocated_objects]
puts format("  SET: %.2f objects/call (includes string interpolation)", (after - before) / 1000.0)

GC.start
before = GC.stat[:total_allocated_objects]
100.times do
  redis.pipelined do |p|
    100.times { |i| p.get("pipe_#{i}") }
  end
end
after = GC.stat[:total_allocated_objects]
puts format("  PIPELINE (100 cmds): %.2f objects/pipeline", (after - before) / 100.0)

# ============================================================
# 5. YJIT Stats
# ============================================================
if defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?
  puts "\n" + "=" * 70
  puts "5. YJIT STATISTICS"
  puts "=" * 70

  stats = RubyVM::YJIT.runtime_stats

  if stats[:yjit_insns_count] && stats[:vm_insns_count]
    total = stats[:yjit_insns_count] + stats[:vm_insns_count]
    ratio = (stats[:yjit_insns_count].to_f / total * 100).round(2)
    puts format("  Ratio in YJIT: %s%%", ratio)
  end

  if stats[:compiled_iseq_count]
    puts format("  Compiled ISEQs: %d", stats[:compiled_iseq_count])
  end

  if stats[:invalidation_count]
    puts format("  Invalidations: %d", stats[:invalidation_count])
  end
end

redis.close
puts "\n" + "=" * 70
puts "Profiling complete!"
puts "=" * 70
