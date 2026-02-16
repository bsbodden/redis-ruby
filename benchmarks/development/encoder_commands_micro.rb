#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "benchmark/ips"
require_relative "../../lib/redis_ruby"

# Micro-benchmark: measures pure encoding speed without network I/O
# This shows the true benefit of fast-path optimizations

encoder = RedisRuby::Protocol::RESP3Encoder.new

puts "=" * 70
puts "ENCODER MICRO-BENCHMARK (no network I/O)"
puts "=" * 70
puts "Ruby #{RUBY_VERSION}"
puts "=" * 70

Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)

  # String commands
  x.report("GET") { encoder.encode_command("GET", "mykey") }
  x.report("SET") { encoder.encode_command("SET", "mykey", "myvalue") }

  # Hash commands
  x.report("HGET") { encoder.encode_command("HGET", "myhash", "field1") }
  x.report("HSET") { encoder.encode_command("HSET", "myhash", "field1", "value1") }
  x.report("HDEL") { encoder.encode_command("HDEL", "myhash", "field1") }

  # List commands
  x.report("LPUSH") { encoder.encode_command("LPUSH", "mylist", "item") }
  x.report("RPUSH") { encoder.encode_command("RPUSH", "mylist", "item") }
  x.report("LPOP") { encoder.encode_command("LPOP", "mylist") }
  x.report("RPOP") { encoder.encode_command("RPOP", "mylist") }

  # Key commands
  x.report("EXPIRE") { encoder.encode_command("EXPIRE", "mykey", 3600) }
  x.report("TTL") { encoder.encode_command("TTL", "mykey") }

  # Batch commands
  x.report("MGET 5") { encoder.encode_command("MGET", "k1", "k2", "k3", "k4", "k5") }
  x.report("MSET 5") { encoder.encode_command("MSET", "k1", "v1", "k2", "v2", "k3", "v3", "k4", "v4", "k5", "v5") }

  # Slow path for comparison
  x.report("ZADD (slow)") { encoder.encode_command("ZADD", "myset", 1.0, "member") }

  x.compare!
end

puts "\n#{"=" * 70}"
puts "Fast-path commands should be 2-3x faster than slow-path (ZADD)"
puts "=" * 70
