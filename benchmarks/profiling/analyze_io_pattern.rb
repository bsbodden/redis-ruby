#!/usr/bin/env ruby
# frozen_string_literal: true

# Analyze I/O patterns for GET operation
#
# Usage:
#   RUBYOPT="--yjit" bundle exec ruby benchmarks/analyze_io_pattern.rb

require "bundler/setup"
require_relative "../../lib/redis_ruby"

REDIS_URL = ENV.fetch("REDIS_URL", "redis://localhost:6379")

puts "=" * 80
puts "I/O Pattern Analysis for GET Operation"
puts "=" * 80
puts

# Monkey-patch to count I/O operations
module IOCounter
  attr_accessor :read_count, :write_count, :flush_count, :wait_count

  def read_nonblock(...)
    @read_count ||= 0
    @read_count += 1
    super
  end

  def write(...)
    @write_count ||= 0
    @write_count += 1
    super
  end

  def flush(...)
    @flush_count ||= 0
    @flush_count += 1
    super
  end

  def wait_readable(...)
    @wait_count ||= 0
    @wait_count += 1
    super
  end
end

redis = RedisRuby.new(url: REDIS_URL)

# Ensure connection is established
redis.ping

# Get the underlying socket (RedisRuby.new returns a Client directly)
connection = redis.instance_variable_get(:@connection)
socket = connection.instance_variable_get(:@socket)
socket.extend(IOCounter)

# Initialize counters
socket.read_count = 0
socket.write_count = 0
socket.flush_count = 0
socket.wait_count = 0

# Test different value sizes
[10, 100, 1000].each do |size|
  value = "x" * size
  redis.set("test:io", value)

  # Reset counters
  socket.read_count = 0
  socket.write_count = 0
  socket.flush_count = 0
  socket.wait_count = 0

  # Perform 100 GETs
  100.times { redis.get("test:io") }

  puts "Value size: #{size} bytes"
  puts "  Reads per GET:  #{(socket.read_count / 100.0).round(2)}"
  puts "  Writes per GET: #{(socket.write_count / 100.0).round(2)}"
  puts "  Flushes per GET: #{(socket.flush_count / 100.0).round(2)}"
  puts "  Waits per GET:  #{(socket.wait_count / 100.0).round(2)}"
  puts
end

redis.del("test:io")
redis.close

puts "=" * 80
puts "Analysis complete!"
puts "=" * 80
