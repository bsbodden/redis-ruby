#!/usr/bin/env ruby
# frozen_string_literal: true

# Deep profiling script for redis-ruby
#
# Runs multiple profiling tools to identify every optimization opportunity:
# - memory_profiler: allocation analysis
# - stackprof: CPU profiling
# - ObjectSpace: object allocation tracing
# - GC: garbage collection analysis
#
# Usage:
#   RUBYOPT="--yjit" bundle exec ruby benchmarks/deep_profile.rb

require "bundler/setup"
require_relative "../lib/redis_ruby"
require "fileutils"

FileUtils.mkdir_p("tmp/profiles")

ITERATIONS = 5_000
PIPELINE_SIZE = 100

puts "=" * 70
puts "Redis-Ruby Deep Profiler"
puts "=" * 70
puts "Ruby: #{RUBY_VERSION}"
puts "YJIT: #{defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?}"
puts "Iterations: #{ITERATIONS}"
puts "=" * 70
puts

# Connect to Redis
redis = RedisRuby.new(host: ENV.fetch("REDIS_HOST", "redis"), port: ENV.fetch("REDIS_PORT", 6379).to_i)
redis.set("profile_key", "x" * 100)

# Warm up
puts "Warming up YJIT..."
2000.times { redis.get("profile_key") }
2000.times { redis.set("profile_key", "warmup") }
20.times do
  redis.pipelined do |p|
    PIPELINE_SIZE.times { |i| p.set("pipe_#{i}", "v#{i}") }
  end
end
puts "Warmup complete."
puts

# Define workloads
def workload_single_ops(redis, iterations)
  iterations.times do |i|
    redis.get("profile_key")
    redis.set("profile_key", "value_#{i}")
  end
end

def workload_pipeline(redis, iterations, pipeline_size)
  (iterations / 10).times do
    redis.pipelined do |p|
      pipeline_size.times { |j| p.get("pipe_#{j}") }
    end
    redis.pipelined do |p|
      pipeline_size.times { |j| p.set("pipe_#{j}", "val_#{j}") }
    end
  end
end

def workload_mixed(redis, iterations, pipeline_size)
  iterations.times do |i|
    redis.get("profile_key")
    redis.set("profile_key", "value_#{i}")

    next unless (i % 20).zero?
    redis.pipelined do |p|
      pipeline_size.times { |j| p.get("pipe_#{j}") }
    end
  end
end

# ============================================================
# 1. Memory Profiler - Allocation Analysis
# ============================================================
puts "\n" + "=" * 70
puts "1. MEMORY PROFILER - Allocation Analysis"
puts "=" * 70

require "memory_profiler"

report = MemoryProfiler.report do
  workload_mixed(redis, ITERATIONS / 5, PIPELINE_SIZE)
end

report.pretty_print(to_file: "tmp/profiles/memory_report.txt", detailed_report: true)

puts "\nTop 15 Allocated Memory by Gem/File:"
puts "-" * 70
report.allocated_memory_by_gem.first(15).each do |stat|
  puts format("  %-50s %10s bytes", stat[:data], stat[:count])
end

puts "\nTop 15 Allocated Objects by Location:"
puts "-" * 70
report.allocated_objects_by_location.first(15).each do |stat|
  puts format("  %-55s %8d", stat[:data], stat[:count])
end

puts "\nTop 10 Retained Objects by Location:"
puts "-" * 70
report.retained_objects_by_location.first(10).each do |stat|
  puts format("  %-55s %8d", stat[:data], stat[:count])
end

# Note: String analysis removed - format varies by memory_profiler version

puts "\nFull report saved to: tmp/profiles/memory_report.txt"

# ============================================================
# 2. StackProf - CPU Profiling
# ============================================================
puts "\n" + "=" * 70
puts "2. STACKPROF - CPU Profiling"
puts "=" * 70

require "stackprof"

profile = StackProf.run(mode: :cpu, raw: true, interval: 100) do
  workload_mixed(redis, ITERATIONS, PIPELINE_SIZE)
end

File.write("tmp/profiles/stackprof_cpu.json", JSON.generate(profile))

puts "\nTop 20 Methods by CPU Time:"
puts "-" * 70
StackProf::Report.new(profile).print_text(false, 20)

puts "\nProfile saved to: tmp/profiles/stackprof_cpu.json"
puts "Generate flamegraph: stackprof --d3-flamegraph tmp/profiles/stackprof_cpu.json > tmp/profiles/flamegraph.html"

# ============================================================
# 3. Object Allocation Tracing
# ============================================================
puts "\n" + "=" * 70
puts "3. OBJECT ALLOCATION TRACING"
puts "=" * 70

require "allocation_tracer"

ObjectSpace::AllocationTracer.setup(%i[path line type])

result = ObjectSpace::AllocationTracer.trace do
  workload_mixed(redis, ITERATIONS / 10, PIPELINE_SIZE)
end

# Sort by allocation count
sorted = result.sort_by { |_k, v| -v[0] }
           .first(30)
           .select { |(path, _, _), _| path.to_s.include?("redis_ruby") }

puts "\nTop Allocation Sites in redis-ruby:"
puts "-" * 70
puts format("%-50s %10s %10s", "Location", "Count", "Old GC")
puts "-" * 70
sorted.first(20).each do |(path, line, type), (count, old_count, *)|
  short_path = path.to_s.gsub(%r{.*/lib/}, "")
  puts format("%-50s %10d %10d", "#{short_path}:#{line} (#{type})", count, old_count)
end

# ============================================================
# 4. GC Analysis
# ============================================================
puts "\n" + "=" * 70
puts "4. GC ANALYSIS"
puts "=" * 70

GC.start(full_mark: true, immediate_sweep: true)
gc_before = GC.stat.dup

workload_mixed(redis, ITERATIONS, PIPELINE_SIZE)

gc_after = GC.stat

puts "\nGC Statistics During Workload:"
puts "-" * 70
%i[count minor_gc_count major_gc_count total_allocated_objects total_freed_objects
   heap_live_slots heap_free_slots malloc_increase_bytes oldmalloc_increase_bytes].each do |key|
  before = gc_before[key] || 0
  after = gc_after[key] || 0
  diff = after - before
  puts format("  %-35s %15d (delta: %+d)", key, after, diff)
end

# ============================================================
# 5. YJIT Statistics (if available)
# ============================================================
if defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?
  puts "\n" + "=" * 70
  puts "5. YJIT STATISTICS"
  puts "=" * 70

  stats = RubyVM::YJIT.runtime_stats

  puts "\nKey YJIT Metrics:"
  puts "-" * 70

  relevant_stats = %i[
    inline_code_size outlined_code_size
    yjit_alloc_size code_region_size
    live_iseq_count compiled_iseq_count
    compiled_block_count invalidation_count
    side_exit_count avg_len_in_yjit
  ]

  relevant_stats.each do |key|
    value = stats[key]
    next unless value

    formatted = if key.to_s.include?("size")
                  "#{(value / 1024.0).round(2)} KB"
                elsif value.is_a?(Float)
                  value.round(4)
                else
                  value
                end
    puts format("  %-35s %s", key, formatted)
  end

  # Calculate ratio_in_yjit if available
  if stats[:yjit_insns_count] && stats[:vm_insns_count]
    total = stats[:yjit_insns_count] + stats[:vm_insns_count]
    ratio = (stats[:yjit_insns_count].to_f / total * 100).round(2)
    puts format("  %-35s %s%%", "ratio_in_yjit", ratio)
  end
end

# ============================================================
# 6. Encoder/Decoder Micro-profiling
# ============================================================
puts "\n" + "=" * 70
puts "6. ENCODER/DECODER MICRO-PROFILE"
puts "=" * 70

encoder = RedisRuby::Protocol::RESP3Encoder.new

# Profile encoding
puts "\nEncoding 10,000 GET commands..."
gc_stat_before = GC.stat[:total_allocated_objects]
t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

10_000.times do |i|
  encoder.encode_command("GET", "key_#{i}")
end

t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
gc_stat_after = GC.stat[:total_allocated_objects]

puts format("  Time: %.4f seconds", t2 - t1)
puts format("  Objects allocated: %d", gc_stat_after - gc_stat_before)
puts format("  Objects per encode: %.2f", (gc_stat_after - gc_stat_before) / 10_000.0)

# Profile pipeline encoding
puts "\nEncoding 100 pipelines of 100 commands each..."
commands = Array.new(100) { |i| ["GET", "key_#{i}"] }

gc_stat_before = GC.stat[:total_allocated_objects]
t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

100.times do
  encoder.encode_pipeline(commands)
end

t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
gc_stat_after = GC.stat[:total_allocated_objects]

puts format("  Time: %.4f seconds", t2 - t1)
puts format("  Objects allocated: %d", gc_stat_after - gc_stat_before)
puts format("  Objects per pipeline: %.2f", (gc_stat_after - gc_stat_before) / 100.0)

redis.close
puts "\n" + "=" * 70
puts "Profiling complete! Check tmp/profiles/ for detailed reports."
puts "=" * 70
