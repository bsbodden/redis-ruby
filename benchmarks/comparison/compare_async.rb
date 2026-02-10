#!/usr/bin/env ruby
# frozen_string_literal: true

# Benchmark comparing sync vs async client performance
#
# Usage:
#   REDIS_URL=redis://localhost:6379 bundle exec ruby benchmarks/compare_async.rb

require "bundler/setup"
require "benchmark/ips"
require "redis_ruby"
require "async"

REDIS_URL = ENV.fetch("REDIS_URL", "redis://localhost:6379")

puts "Connecting to #{REDIS_URL}..."
puts

sync_client = RedisRuby.new(url: REDIS_URL)
async_client = RedisRuby.async(url: REDIS_URL)

# Setup test data
sync_client.set("bench:key", "value")

puts "=" * 60
puts "Single GET Operation"
puts "=" * 60

Benchmark.ips do |x|
  x.report("sync: GET") do
    sync_client.get("bench:key")
  end

  x.report("async: GET (no scheduler)") do
    async_client.get("bench:key")
  end

  x.report("async: GET (with scheduler)") do
    Async { async_client.get("bench:key") }
  end

  x.compare!
end

puts
puts "=" * 60
puts "Concurrent GET Operations (10 keys)"
puts "=" * 60

# Setup 10 keys
10.times { |i| sync_client.set("bench:key:#{i}", "value#{i}") }

Benchmark.ips do |x|
  x.report("sync: 10 sequential GETs") do
    10.times { |i| sync_client.get("bench:key:#{i}") }
  end

  x.report("async: 10 concurrent GETs") do
    Async do |task|
      tasks = Array.new(10) { |i| task.async { async_client.get("bench:key:#{i}") } }
      tasks.map(&:wait)
    end
  end

  x.compare!
end

puts
puts "=" * 60
puts "Pipeline vs Async Concurrent (10 commands)"
puts "=" * 60

Benchmark.ips do |x|
  x.report("sync: pipeline 10 GETs") do
    sync_client.pipelined do |pipe|
      10.times { |i| pipe.get("bench:key:#{i}") }
    end
  end

  x.report("async: 10 concurrent GETs") do
    Async do |task|
      tasks = Array.new(10) { |i| task.async { async_client.get("bench:key:#{i}") } }
      tasks.map(&:wait)
    end
  end

  x.compare!
end

# Cleanup
sync_client.del("bench:key")
10.times { |i| sync_client.del("bench:key:#{i}") }

sync_client.close
async_client.close

puts
puts "Benchmark complete!"
