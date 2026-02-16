#!/usr/bin/env ruby
# frozen_string_literal: true

# Protocol Layer Benchmark - Compare redis-ruby vs redis-client RESP3 parsing
#
# This isolates the protocol layer performance without network latency.
# Performance Gate: RESP3 Parser should be 1.5x faster than redis-rb's parser
#
# Usage: RUBYOPT="--yjit" bundle exec ruby benchmarks/protocol_comparison.rb

require "bundler/setup"
require "benchmark/ips"
require "stringio"

# Load redis-ruby protocol
require_relative "../../lib/redis_ruby"

# Load redis-client RESP3 for comparison
require "redis-client"

puts "=" * 70
puts "Protocol Layer Benchmark: redis-ruby vs redis-client RESP3"
puts "=" * 70
puts "Ruby version: #{RUBY_VERSION}"
puts "YJIT enabled: #{defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?}"
puts
puts "Performance Gate: redis-ruby should be 1.5x faster"
puts "=" * 70
puts

# Test data - pre-encoded RESP3 responses
ENCODED_SIMPLE = "+OK\r\n"
ENCODED_BULK = "$11\r\nHello World\r\n"
ENCODED_LARGE_BULK = "$2048\r\n#{"x" * 2048}\r\n".freeze
ENCODED_INTEGER = ":12345\r\n"
ENCODED_ARRAY_SMALL = "*3\r\n$3\r\nfoo\r\n$3\r\nbar\r\n$3\r\nbaz\r\n"
ENCODED_ARRAY_100 = "*100\r\n" + (1..100).map { |i| "$#{"item#{i}".length}\r\nitem#{i}\r\n" }.join

# Command encoding test data
SIMPLE_CMD = ["PING"].freeze
SET_CMD = %w[SET key value].freeze
LARGE_CMD = ["SET", "key", "x" * 2048].freeze

# redis-client encoder/decoder
redis_client_encoder = ->(cmd) { RedisClient::RESP3.dump(cmd) }

# redis-ruby encoder
redis_ruby_encoder = RedisRuby::Protocol::RESP3Encoder.new

# Create a buffered IO wrapper for redis-client that matches its expectations
class RedisClientTestIO
  EOL = "\r\n".b.freeze
  EOL_SIZE = EOL.bytesize

  def initialize(data)
    @data = data.b
    @offset = 0
  end

  def reset(data = nil)
    @data = data.b if data
    @offset = 0
  end

  def getbyte
    byte = @data.getbyte(@offset)
    @offset += 1 if byte
    byte
  end

  def gets_chomp
    eol_index = @data.index(EOL, @offset)
    return nil unless eol_index

    line = @data.byteslice(@offset, eol_index - @offset)
    @offset = eol_index + EOL_SIZE
    line
  end

  def gets_integer
    int = 0
    loop do
      chr = @data.getbyte(@offset)
      break unless chr

      if chr == 13 # "\r".ord
        @offset += 2
        break
      else
        int = (int * 10) + chr - 48
      end
      @offset += 1
    end
    int
  end

  def read_chomp(bytes)
    str = @data.byteslice(@offset, bytes)
    @offset += bytes + EOL_SIZE
    str
  end

  def skip(offset)
    @offset += offset
    nil
  end
end

# Create a mock socket for testing BufferedIO
# This simulates a socket that returns data from read_nonblock
class MockSocket
  def initialize(data)
    @data = data.b
    @offset = 0
  end

  def reset(data = nil)
    @data = data.b if data
    @offset = 0
  end

  def read_nonblock(size, _buffer = nil, exception: true)
    return nil if @offset >= @data.bytesize

    chunk = @data.byteslice(@offset, size)
    @offset += chunk.bytesize
    chunk
  end

  def wait_readable(_timeout)
    true
  end

  def wait_writable(_timeout)
    true
  end

  def closed?
    false
  end
end

puts "=" * 70
puts "ENCODING BENCHMARKS"
puts "=" * 70
puts

puts "1. Encode Simple Command (PING)"
puts "-" * 50
Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)
  x.report("redis-client") { redis_client_encoder.call(SIMPLE_CMD) }
  x.report("redis-ruby") { redis_ruby_encoder.encode_command(*SIMPLE_CMD) }
  x.compare!
end
puts

puts "2. Encode SET Command"
puts "-" * 50
Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)
  x.report("redis-client") { redis_client_encoder.call(SET_CMD) }
  x.report("redis-ruby") { redis_ruby_encoder.encode_command(*SET_CMD) }
  x.compare!
end
puts

puts "3. Encode Large Value (2KB)"
puts "-" * 50
Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)
  x.report("redis-client") { redis_client_encoder.call(LARGE_CMD) }
  x.report("redis-ruby") { redis_ruby_encoder.encode_command(*LARGE_CMD) }
  x.compare!
end
puts

puts "=" * 70
puts "DECODING BENCHMARKS (with optimized BufferedIO)"
puts "=" * 70
puts

# Create IO wrappers
rc_io = RedisClientTestIO.new(ENCODED_SIMPLE)
mock_socket = MockSocket.new(ENCODED_SIMPLE)

puts "4. Decode Simple String (+OK)"
puts "-" * 50
Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)
  x.report("redis-client") do
    rc_io.reset(ENCODED_SIMPLE)
    RedisClient::RESP3.load(rc_io)
  end
  x.report("redis-ruby") do
    mock_socket.reset(ENCODED_SIMPLE)
    bio = RedisRuby::Protocol::BufferedIO.new(mock_socket, read_timeout: 5.0, write_timeout: 5.0)
    decoder = RedisRuby::Protocol::RESP3Decoder.new(bio)
    decoder.decode
  end
  x.compare!
end
puts

puts "5. Decode Bulk String"
puts "-" * 50
Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)
  x.report("redis-client") do
    rc_io.reset(ENCODED_BULK)
    RedisClient::RESP3.load(rc_io)
  end
  x.report("redis-ruby") do
    mock_socket.reset(ENCODED_BULK)
    bio = RedisRuby::Protocol::BufferedIO.new(mock_socket, read_timeout: 5.0, write_timeout: 5.0)
    decoder = RedisRuby::Protocol::RESP3Decoder.new(bio)
    decoder.decode
  end
  x.compare!
end
puts

puts "6. Decode Large Bulk String (2KB)"
puts "-" * 50
Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)
  x.report("redis-client") do
    rc_io.reset(ENCODED_LARGE_BULK)
    RedisClient::RESP3.load(rc_io)
  end
  x.report("redis-ruby") do
    mock_socket.reset(ENCODED_LARGE_BULK)
    bio = RedisRuby::Protocol::BufferedIO.new(mock_socket, read_timeout: 5.0, write_timeout: 5.0)
    decoder = RedisRuby::Protocol::RESP3Decoder.new(bio)
    decoder.decode
  end
  x.compare!
end
puts

puts "7. Decode Integer"
puts "-" * 50
Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)
  x.report("redis-client") do
    rc_io.reset(ENCODED_INTEGER)
    RedisClient::RESP3.load(rc_io)
  end
  x.report("redis-ruby") do
    mock_socket.reset(ENCODED_INTEGER)
    bio = RedisRuby::Protocol::BufferedIO.new(mock_socket, read_timeout: 5.0, write_timeout: 5.0)
    decoder = RedisRuby::Protocol::RESP3Decoder.new(bio)
    decoder.decode
  end
  x.compare!
end
puts

puts "8. Decode Small Array (3 elements)"
puts "-" * 50
Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)
  x.report("redis-client") do
    rc_io.reset(ENCODED_ARRAY_SMALL)
    RedisClient::RESP3.load(rc_io)
  end
  x.report("redis-ruby") do
    mock_socket.reset(ENCODED_ARRAY_SMALL)
    bio = RedisRuby::Protocol::BufferedIO.new(mock_socket, read_timeout: 5.0, write_timeout: 5.0)
    decoder = RedisRuby::Protocol::RESP3Decoder.new(bio)
    decoder.decode
  end
  x.compare!
end
puts

puts "9. Decode Large Array (100 elements)"
puts "-" * 50
Benchmark.ips do |x|
  x.config(warmup: 2, time: 5)
  x.report("redis-client") do
    rc_io.reset(ENCODED_ARRAY_100)
    RedisClient::RESP3.load(rc_io)
  end
  x.report("redis-ruby") do
    mock_socket.reset(ENCODED_ARRAY_100)
    bio = RedisRuby::Protocol::BufferedIO.new(mock_socket, read_timeout: 5.0, write_timeout: 5.0)
    decoder = RedisRuby::Protocol::RESP3Decoder.new(bio)
    decoder.decode
  end
  x.compare!
end
puts

puts "=" * 70
puts "Benchmark complete!"
puts "=" * 70
