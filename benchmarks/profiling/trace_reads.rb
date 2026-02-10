#!/usr/bin/env ruby
# frozen_string_literal: true

# Trace read operations to understand the pattern
#
# Usage:
#   RUBYOPT="--yjit" bundle exec ruby benchmarks/trace_reads.rb

require "bundler/setup"
require_relative "../lib/redis_ruby"

REDIS_URL = ENV.fetch("REDIS_URL", "redis://localhost:6379")

puts "=" * 80
puts "Tracing Read Operations for GET"
puts "=" * 80
puts

# Monkey-patch to trace reads
module ReadTracer
  def read_nonblock(*args, **kwargs, &block)
    result = super(*args, **kwargs, &block)
    if result.is_a?(String)
      $stderr.puts "  read_nonblock(#{args[0]}) => #{result.bytesize} bytes: #{result.inspect[0..80]}"
    else
      $stderr.puts "  read_nonblock(#{args[0]}) => #{result.inspect}"
    end
    result
  end

  def fill_buffer(min_bytes)
    $stderr.puts "fill_buffer(#{min_bytes}) called, buffer=#{@buffer.bytesize} bytes, offset=#{@offset}"
    super
  end
end

redis = RedisRuby.new(url: REDIS_URL)
redis.ping

# Get the underlying components
connection = redis.instance_variable_get(:@connection)
socket = connection.instance_variable_get(:@socket)
buffered_io = connection.instance_variable_get(:@buffered_io)

socket.extend(ReadTracer)
buffered_io.extend(ReadTracer)

# Test a simple GET
puts "\n--- Setting value ---"
redis.set("test:trace", "x" * 100)

puts "\n--- Getting value (first time) ---"
result = redis.get("test:trace")
puts "Result: #{result.bytesize} bytes"

puts "\n--- Getting value (second time, should use buffer) ---"
result = redis.get("test:trace")
puts "Result: #{result.bytesize} bytes"

redis.del("test:trace")
redis.close

puts "\n" + "=" * 80
puts "Trace complete!"
puts "=" * 80

