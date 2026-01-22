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
redis_rb.set("bench:key", "hello world this is a test value")

puts "=" * 70
puts "REDIS-RUBY vs REDIS-RB: Single Operation Comparison"
puts "=" * 70
puts "Ruby #{RUBY_VERSION} | YJIT: #{defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?}"
puts "=" * 70

puts "\n### GET (single key) ###"
get_report = Benchmark.ips do |x|
  x.config(warmup: 3, time: 10)
  x.report("redis-rb GET") { redis_rb.get("bench:key") }
  x.report("redis-ruby GET") { redis_ruby.get("bench:key") }
  x.compare!
end

rb_get = get_report.entries.find { |e| e.label == "redis-rb GET" }
ruby_get = get_report.entries.find { |e| e.label == "redis-ruby GET" }

puts "\n### SET (key + value) ###"
set_report = Benchmark.ips do |x|
  x.config(warmup: 3, time: 10)
  x.report("redis-rb SET") { redis_rb.set("bench:test", "value123") }
  x.report("redis-ruby SET") { redis_ruby.set("bench:test", "value123") }
  x.compare!
end

rb_set = set_report.entries.find { |e| e.label == "redis-rb SET" }
ruby_set = set_report.entries.find { |e| e.label == "redis-ruby SET" }

puts "\n" + "=" * 70
puts "DETAILED RESULTS"
puts "=" * 70

rb_get_ips = rb_get.stats.central_tendency
ruby_get_ips = ruby_get.stats.central_tendency
rb_set_ips = rb_set.stats.central_tendency
ruby_set_ips = ruby_set.stats.central_tendency

puts
puts "GET Operation:"
puts "  redis-rb:    #{format('%10.1f', rb_get_ips)} iterations/sec  (#{format('%6.2f', 1_000_000.0 / rb_get_ips)} μs/op)"
puts "  redis-ruby:  #{format('%10.1f', ruby_get_ips)} iterations/sec  (#{format('%6.2f', 1_000_000.0 / ruby_get_ips)} μs/op)"
puts "  Speedup:     #{format('%.2f', ruby_get_ips / rb_get_ips)}x"
puts
puts "SET Operation:"
puts "  redis-rb:    #{format('%10.1f', rb_set_ips)} iterations/sec  (#{format('%6.2f', 1_000_000.0 / rb_set_ips)} μs/op)"
puts "  redis-ruby:  #{format('%10.1f', ruby_set_ips)} iterations/sec  (#{format('%6.2f', 1_000_000.0 / ruby_set_ips)} μs/op)"
puts "  Speedup:     #{format('%.2f', ruby_set_ips / rb_set_ips)}x"
puts
puts "=" * 70

# Cleanup
redis_rb.del("bench:key", "bench:test")
redis_rb.close
redis_ruby.close
