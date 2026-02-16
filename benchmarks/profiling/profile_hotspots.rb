#!/usr/bin/env ruby
# frozen_string_literal: true

# Profile redis-ruby to find performance hotspots
#
# Usage:
#   RUBYOPT="--yjit" bundle exec ruby benchmarks/profile_hotspots.rb
#   RUBYOPT="--yjit" bundle exec ruby benchmarks/profile_hotspots.rb stackprof
#   RUBYOPT="--yjit" bundle exec ruby benchmarks/profile_hotspots.rb vernier
#   RUBYOPT="--yjit" bundle exec ruby benchmarks/profile_hotspots.rb memory

require "bundler/setup"
require_relative "../../lib/redis_ruby"

PROFILE_MODE = ARGV[0] || "stackprof"
ITERATIONS = 10_000
PIPELINE_SIZE = 100

puts "=" * 70
puts "Redis-Ruby Performance Profiler"
puts "=" * 70
puts "Mode: #{PROFILE_MODE}"
puts "Iterations: #{ITERATIONS}"
puts "Pipeline size: #{PIPELINE_SIZE}"
puts "Ruby: #{RUBY_VERSION}"
puts "YJIT: #{defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?}"
puts "=" * 70
puts

# Connect to Redis
redis = RedisRuby.new(host: ENV.fetch("REDIS_HOST", "redis"), port: ENV.fetch("REDIS_PORT", 6379).to_i)
redis.set("profile_key", "profile_value")

# Warm up YJIT
puts "Warming up..."
1000.times { redis.get("profile_key") }
1000.times { redis.set("profile_key", "value") }
10.times do
  redis.pipelined do |p|
    PIPELINE_SIZE.times { |i| p.set("pipe_key_#{i}", "value_#{i}") }
  end
end
puts "Warmup complete."
puts

def run_workload(redis, iterations, pipeline_size)
  # Mix of operations to profile
  iterations.times do |i|
    # Single GET
    redis.get("profile_key")

    # Single SET
    redis.set("profile_key", "value_#{i}")

    # Pipeline every 10th iteration
    next unless (i % 10).zero?

    redis.pipelined do |p|
      pipeline_size.times { |j| p.get("pipe_key_#{j}") }
    end
  end
end

case PROFILE_MODE
when "stackprof"
  require "stackprof"

  puts "Running StackProf CPU profiling..."
  profile = StackProf.run(mode: :cpu, raw: true, interval: 100) do
    run_workload(redis, ITERATIONS, PIPELINE_SIZE)
  end

  puts "\n#{"=" * 70}"
  puts "TOP METHODS BY CPU TIME"
  puts "=" * 70
  StackProf::Report.new(profile).print_text(false, 30)

  # Save flamegraph data
  File.write("tmp/stackprof_cpu.json", JSON.generate(profile))
  puts "\nProfile saved to tmp/stackprof_cpu.json"
  puts "Generate flamegraph: stackprof --flamegraph tmp/stackprof_cpu.json > tmp/flamegraph.html"

when "stackprof_wall"
  require "stackprof"

  puts "Running StackProf wall-clock profiling..."
  profile = StackProf.run(mode: :wall, raw: true, interval: 1000) do
    run_workload(redis, ITERATIONS, PIPELINE_SIZE)
  end

  puts "\n#{"=" * 70}"
  puts "TOP METHODS BY WALL TIME"
  puts "=" * 70
  StackProf::Report.new(profile).print_text(false, 30)

when "vernier"
  require "vernier"

  puts "Running Vernier profiling..."
  FileUtils.mkdir_p("tmp")

  Vernier.profile(out: "tmp/vernier_profile.json") do
    run_workload(redis, ITERATIONS, PIPELINE_SIZE)
  end

  puts "\nProfile saved to tmp/vernier_profile.json"
  puts "View in Firefox Profiler: https://profiler.firefox.com/"
  puts "Or run: vernier view tmp/vernier_profile.json"

when "memory"
  require "memory_profiler"

  puts "Running Memory profiling (reduced iterations)..."
  report = MemoryProfiler.report do
    run_workload(redis, ITERATIONS / 10, PIPELINE_SIZE)
  end

  puts "\n#{"=" * 70}"
  puts "MEMORY ALLOCATION REPORT"
  puts "=" * 70
  report.pretty_print(to_file: "tmp/memory_profile.txt", detailed_report: true, scale_bytes: true)

  puts "\nTop allocated objects:"
  report.pretty_print(detailed_report: false, allocated_strings: 10, retained_strings: 5)
  puts "\nFull report saved to tmp/memory_profile.txt"

when "allocations"
  require "allocation_tracer"

  puts "Running Allocation tracing..."
  ObjectSpace::AllocationTracer.setup(%i[path line type])

  ObjectSpace::AllocationTracer.trace do
    run_workload(redis, ITERATIONS / 10, PIPELINE_SIZE)
  end

  results = ObjectSpace::AllocationTracer.result
  sorted = results.sort_by { |_k, v| -v[0] }.first(30)

  puts "\n#{"=" * 70}"
  puts "TOP ALLOCATION SITES"
  puts "=" * 70
  puts "Location                                                Count  Old Count"
  puts "-" * 70
  sorted.each do |(path, line, type), (count, old_count, *)|
    short_path = path.to_s.gsub(%r{.*/lib/}, "lib/")
    puts format("%-50s %10d %10d", "#{short_path}:#{line} (#{type})", count, old_count)
  end

when "all"
  # Run all profilers in sequence
  system("ruby", __FILE__, "stackprof")
  system("ruby", __FILE__, "memory")
  system("ruby", __FILE__, "allocations")

else
  puts "Unknown mode: #{PROFILE_MODE}"
  puts "Available modes: stackprof, stackprof_wall, vernier, memory, allocations, all"
  exit 1
end

redis.close
puts "\nProfiling complete!"
