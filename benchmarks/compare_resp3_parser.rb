#!/usr/bin/env ruby
# frozen_string_literal: true

# RESP3 Parser Benchmark - Protocol Layer Performance
#
# This benchmark isolates the RESP3 encoding/decoding performance
# without network latency to measure pure parsing speed.
#
# Performance Gate from CLAUDE.md:
# - RESP3 Parser: 1.5x faster than redis-rb's parser
#
# Usage: RUBYOPT="--yjit" bundle exec ruby benchmarks/compare_resp3_parser.rb

require "bundler/setup"
require "benchmark/ips"
require "stringio"

# Load redis-ruby protocol
require_relative "../lib/redis_ruby"

puts "=" * 70
puts "RESP3 Parser Benchmark: Encoding/Decoding Performance"
puts "=" * 70
puts "Ruby version: #{RUBY_VERSION}"
puts "YJIT enabled: #{defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?}"
puts
puts "Performance Gate: RESP3 Parser should be 1.5x faster than redis-rb"
puts "=" * 70
puts

# Test data
SIMPLE_STRING = "OK"
BULK_STRING = "Hello World"
LARGE_BULK_STRING = "x" * 2048
INTEGER_VALUE = 12345
ARRAY_SMALL = %w[foo bar baz]
ARRAY_LARGE = (1..100).map { |i| "item#{i}" }
NESTED_ARRAY = [["a", "b"], ["c", "d"], [1, 2, 3]]

# Pre-encode test responses (simulating what Redis sends back)
ENCODED_SIMPLE = "+OK\r\n"
ENCODED_BULK = "$11\r\nHello World\r\n"
ENCODED_LARGE_BULK = "$2048\r\n#{"x" * 2048}\r\n"
ENCODED_INTEGER = ":12345\r\n"
ENCODED_ARRAY_SMALL = "*3\r\n$3\r\nfoo\r\n$3\r\nbar\r\n$3\r\nbaz\r\n"
ENCODED_ARRAY_100 = "*100\r\n" + (1..100).map { |i| "$#{("item#{i}").length}\r\nitem#{i}\r\n" }.join

# redis-ruby encoder/decoder
encoder = RedisRuby::Protocol::RESP3Encoder.new

puts "=" * 70
puts "ENCODING BENCHMARKS"
puts "=" * 70
puts

puts "1. Encode Simple Command (PING)"
puts "-" * 50
Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)
  x.report("redis-ruby") { encoder.encode_command("PING") }
  x.compare!
end
puts

puts "2. Encode SET Command (with value)"
puts "-" * 50
Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)
  x.report("redis-ruby") { encoder.encode_command("SET", "key", "value") }
  x.compare!
end
puts

puts "3. Encode Large Value (2KB)"
puts "-" * 50
Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)
  x.report("redis-ruby") { encoder.encode_command("SET", "key", LARGE_BULK_STRING) }
  x.compare!
end
puts

puts "4. Encode Pipeline (10 commands)"
puts "-" * 50
Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)
  x.report("redis-ruby") do
    10.times { |i| encoder.encode_command("GET", "key:#{i}") }
  end
  x.compare!
end
puts

puts "=" * 70
puts "DECODING BENCHMARKS"
puts "=" * 70
puts

puts "5. Decode Simple String"
puts "-" * 50
Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)
  x.report("redis-ruby") do
    io = StringIO.new(ENCODED_SIMPLE)
    decoder = RedisRuby::Protocol::RESP3Decoder.new(io)
    decoder.decode
  end
  x.compare!
end
puts

puts "6. Decode Bulk String"
puts "-" * 50
Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)
  x.report("redis-ruby") do
    io = StringIO.new(ENCODED_BULK)
    decoder = RedisRuby::Protocol::RESP3Decoder.new(io)
    decoder.decode
  end
  x.compare!
end
puts

puts "7. Decode Large Bulk String (2KB)"
puts "-" * 50
Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)
  x.report("redis-ruby") do
    io = StringIO.new(ENCODED_LARGE_BULK)
    decoder = RedisRuby::Protocol::RESP3Decoder.new(io)
    decoder.decode
  end
  x.compare!
end
puts

puts "8. Decode Integer"
puts "-" * 50
Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)
  x.report("redis-ruby") do
    io = StringIO.new(ENCODED_INTEGER)
    decoder = RedisRuby::Protocol::RESP3Decoder.new(io)
    decoder.decode
  end
  x.compare!
end
puts

puts "9. Decode Small Array (3 elements)"
puts "-" * 50
Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)
  x.report("redis-ruby") do
    io = StringIO.new(ENCODED_ARRAY_SMALL)
    decoder = RedisRuby::Protocol::RESP3Decoder.new(io)
    decoder.decode
  end
  x.compare!
end
puts

puts "10. Decode Large Array (100 elements)"
puts "-" * 50
Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)
  x.report("redis-ruby") do
    io = StringIO.new(ENCODED_ARRAY_100)
    decoder = RedisRuby::Protocol::RESP3Decoder.new(io)
    decoder.decode
  end
  x.compare!
end
puts

puts "=" * 70
puts "ROUND-TRIP BENCHMARKS (encode + decode)"
puts "=" * 70
puts

puts "11. Round-trip: Simple command"
puts "-" * 50
Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)
  x.report("redis-ruby") do
    # Encode
    encoded = encoder.encode_command("GET", "key")
    # Simulate response decode
    io = StringIO.new(ENCODED_BULK)
    decoder = RedisRuby::Protocol::RESP3Decoder.new(io)
    decoder.decode
  end
  x.compare!
end
puts

puts "=" * 70
puts "Benchmark complete!"
puts "=" * 70
