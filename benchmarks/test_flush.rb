#!/usr/bin/env ruby
# frozen_string_literal: true

require 'socket'
require 'benchmark/ips'

# Test write + flush vs write (no flush)
socket = TCPSocket.new('localhost', 6379)
socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)

data = "*3\r\n$3\r\nSET\r\n$3\r\nkey\r\n$5\r\nvalue\r\n"

puts "Testing write strategies..."
puts "=" * 80

Benchmark.ips do |x|
  x.report('write + flush') do
    socket.write(data)
    socket.flush
    socket.read(5) # Read response
  end
  
  x.report('write (no flush)') do
    socket.write(data)
    socket.read(5) # Read response
  end
  
  x.compare!
end

socket.close

