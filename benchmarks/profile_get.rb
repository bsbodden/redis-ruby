#!/usr/bin/env ruby
# frozen_string_literal: true

# Profile GET operation to identify bottlenecks
#
# Usage:
#   RUBYOPT="--yjit" bundle exec ruby benchmarks/profile_get.rb

require "bundler/setup"
require_relative "../lib/redis_ruby"

# Enable allocation tracing
require "objspace"
ObjectSpace.trace_object_allocations_start

REDIS_URL = ENV.fetch("REDIS_URL", "redis://localhost:6379")

puts "=" * 80
puts "GET Operation Profiling"
puts "=" * 80
puts "Ruby: #{RUBY_VERSION}"
puts "YJIT: #{defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?}"
puts "=" * 80
puts

# Setup
redis = RedisRuby.new(url: REDIS_URL)
redis.set("profile:key", "x" * 100)

# Warmup
1000.times { redis.get("profile:key") }

# Profile allocations
GC.start
ObjectSpace.trace_object_allocations_clear

iterations = 10_000
start_time = Time.now

iterations.times do
  redis.get("profile:key")
end

end_time = Time.now
duration = end_time - start_time

puts "\nPerformance:"
puts "  Iterations: #{iterations}"
puts "  Duration: #{duration.round(3)}s"
puts "  Throughput: #{(iterations / duration).round(0)} ops/s"
puts "  Latency: #{(duration / iterations * 1_000_000).round(2)} μs/op"

# Analyze allocations
allocations = []
ObjectSpace.each_object do |obj|
  next unless ObjectSpace.allocation_sourcefile(obj)

  file = ObjectSpace.allocation_sourcefile(obj)
  next unless file&.include?("redis_ruby")

  allocations << {
    class: obj.class.name,
    file: file.gsub(Dir.pwd + "/", ""),
    line: ObjectSpace.allocation_sourceline(obj),
    size: ObjectSpace.memsize_of(obj),
  }
end

puts "\nAllocations by class:"
allocations.group_by { |a| a[:class] }.sort_by { |_, v| -v.size }.first(10).each do |klass, allocs|
  total_size = allocs.sum { |a| a[:size] }
  puts "  #{klass.ljust(30)}: #{allocs.size.to_s.rjust(8)} objects, #{(total_size / 1024.0).round(1).to_s.rjust(8)} KB"
end

puts "\nAllocations by location:"
allocations.group_by { |a| "#{a[:file]}:#{a[:line]}" }.sort_by { |_, v| -v.size }.first(15).each do |loc, allocs|
  total_size = allocs.sum { |a| a[:size] }
  puts "  #{loc.ljust(60)}: #{allocs.size.to_s.rjust(6)} objects, #{(total_size / 1024.0).round(1).to_s.rjust(6)} KB"
end

# Method profiling with stackprof if available
begin
  require "stackprof"
  
  puts "\n" + "=" * 80
  puts "StackProf Analysis (CPU time)"
  puts "=" * 80
  
  GC.start
  profile = StackProf.run(mode: :cpu, interval: 100) do
    10_000.times { redis.get("profile:key") }
  end
  
  # Print top methods
  puts "\nTop methods by total time:"
  StackProf::Report.new(profile).print_text(false, 30)
  
rescue LoadError
  puts "\nStackProf not available. Install with: gem install stackprof"
end

redis.del("profile:key")
redis.close

puts "\n" + "=" * 80
puts "Profiling complete!"
puts "=" * 80

