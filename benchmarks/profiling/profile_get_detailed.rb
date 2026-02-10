#!/usr/bin/env ruby
# frozen_string_literal: true

# Detailed GET profiling to identify micro-optimizations
#
# Usage:
#   RUBYOPT="--yjit" bundle exec ruby benchmarks/profile_get_detailed.rb

require "bundler/setup"
require_relative "../lib/redis_ruby"

REDIS_URL = ENV.fetch("REDIS_URL", "redis://localhost:6379")

puts "=" * 80
puts "Detailed GET Operation Analysis"
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

# Test different value sizes
[10, 50, 100, 500, 1000].each do |size|
  value = "x" * size
  redis.set("profile:test", value)
  
  GC.start
  iterations = 10_000
  start_time = Time.now
  
  iterations.times { redis.get("profile:test") }
  
  duration = Time.now - start_time
  throughput = (iterations / duration).round(0)
  latency = (duration / iterations * 1_000_000).round(2)
  
  puts "Value size #{size.to_s.rjust(4)} bytes: #{throughput.to_s.rjust(6)} ops/s, #{latency.to_s.rjust(7)} μs/op"
end

# Test with stackprof for method-level analysis
begin
  require "stackprof"
  
  puts "\n" + "=" * 80
  puts "Method-level CPU profiling (100-byte value)"
  puts "=" * 80
  
  redis.set("profile:key", "x" * 100)
  GC.start
  
  profile = StackProf.run(mode: :cpu, interval: 100, raw: true) do
    20_000.times { redis.get("profile:key") }
  end
  
  # Print detailed report
  StackProf::Report.new(profile).print_text(false, 40)
  
  # Print method details for hot methods
  puts "\n" + "=" * 80
  puts "Hot method details:"
  puts "=" * 80
  
  report = StackProf::Report.new(profile)
  hot_methods = report.data[:frames].select { |_, f| f[:total_samples] > 10 }
                      .sort_by { |_, f| -f[:total_samples] }
                      .first(10)
  
  hot_methods.each do |frame_id, frame|
    next if frame[:name].start_with?("IO#", "(")
    
    puts "\n#{frame[:name]}"
    puts "  Total: #{frame[:total_samples]} samples (#{(frame[:total_samples] * 100.0 / profile[:samples]).round(1)}%)"
    puts "  Self: #{frame[:samples]} samples (#{(frame[:samples] * 100.0 / profile[:samples]).round(1)}%)"
    puts "  File: #{frame[:file]}:#{frame[:line]}" if frame[:file]
  end
  
rescue LoadError
  puts "\nStackProf not available"
end

redis.del("profile:key", "profile:test")
redis.close

puts "\n" + "=" * 80
puts "Analysis complete!"
puts "=" * 80

