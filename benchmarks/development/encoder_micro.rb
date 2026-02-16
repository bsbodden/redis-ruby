#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "benchmark/ips"
require_relative "../../lib/redis_ruby"

encoder = RedisRuby::Protocol::RESP3Encoder.new

puts "=" * 60
puts "Encoder Micro-benchmark (no Redis required)"
puts "=" * 60

Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)

  # Normal GET/SET - should not trigger buffer reset
  x.report("encode GET") { encoder.encode_command("GET", "key") }
  x.report("encode SET") { encoder.encode_command("SET", "key", "value") }

  x.compare!
end

puts
puts "Buffer cutoff test complete. Normal operations should be unaffected."
