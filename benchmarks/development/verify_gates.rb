#!/usr/bin/env ruby
# frozen_string_literal: true

# Performance Gate Verification Script
#
# This script verifies that redis-ruby meets the minimum performance
# requirements specified in CLAUDE.md. It's designed for CI/CD integration.
#
# Performance Gates:
#   - Single GET/SET: 1.3x faster than redis-rb
#   - Pipeline (10 cmds): 1.5x faster than redis-rb
#   - Pipeline (100 cmds): 2x faster than redis-rb
#   - Connection setup: Equal or faster than redis-rb
#
# Exit codes:
#   0 - All gates passed
#   1 - One or more gates failed
#
# Usage:
#   bundle exec ruby benchmarks/verify_gates.rb
#   RUBYOPT="--yjit" bundle exec ruby benchmarks/verify_gates.rb

require "bundler/setup"
require "benchmark/ips"
require "json"
require "fileutils"

# Load both implementations
require "redis" # redis-rb gem
require_relative "../lib/redis_ruby"

REDIS_URL = ENV.fetch("REDIS_URL", "redis://localhost:6379")

# Performance gates from CLAUDE.md
GATES = {
  "Single GET" => { min_speedup: 1.3 },
  "Single SET" => { min_speedup: 1.3 },
  "Pipeline 10" => { min_speedup: 1.5 },
  "Pipeline 100" => { min_speedup: 2.0 },
  "Connection Setup" => { min_speedup: 1.0 },
}.freeze

# Benchmark configuration
CONFIG = ENV["BENCHMARK_QUICK"] ? { warmup: 1, time: 2 } : { warmup: 2, time: 5 }

class GateVerifier
  attr_reader :results, :failures

  def initialize
    @redis_rb = Redis.new(url: REDIS_URL)
    @redis_ruby = RedisRuby.new(url: REDIS_URL)
    @results = {}
    @failures = []

    setup_test_data
  end

  def setup_test_data
    puts "Setting up test data..."
    @redis_rb.set("benchmark:key", "value")
    100.times { |i| @redis_rb.set("benchmark:key:#{i}", "value#{i}") }
  end

  def run_benchmark(name, redis_rb_block:, redis_ruby_block:)
    puts "\n#{name}"
    puts "-" * 50

    rb_ips = nil
    ruby_ips = nil

    report = Benchmark.ips do |x|
      x.config(**CONFIG)
      x.report("redis-rb") { redis_rb_block.call }
      x.report("redis-ruby") { redis_ruby_block.call }
      x.compare!
    end

    # Capture IPS values from the report
    report.entries.each do |entry|
      case entry.label
      when "redis-rb"
        rb_ips = entry.stats.central_tendency
      when "redis-ruby"
        ruby_ips = entry.stats.central_tendency
      end
    end

    speedup = ruby_ips / rb_ips
    @results[name] = {
      redis_rb_ips: rb_ips,
      redis_ruby_ips: ruby_ips,
      speedup: speedup,
    }

    speedup
  end

  def verify_gate(name, min_speedup)
    result = @results[name]
    return unless result

    if result[:speedup] >= min_speedup
      puts "  [PASS] #{name}: #{result[:speedup].round(2)}x (need #{min_speedup}x)"
      true
    else
      puts "  [FAIL] #{name}: #{result[:speedup].round(2)}x (need #{min_speedup}x)"
      @failures << { name: name, speedup: result[:speedup], required: min_speedup }
      false
    end
  end

  def run_all
    # Single GET
    run_benchmark("Single GET",
                  redis_rb_block: -> { @redis_rb.get("benchmark:key") },
                  redis_ruby_block: -> { @redis_ruby.get("benchmark:key") })

    # Single SET
    run_benchmark("Single SET",
                  redis_rb_block: -> { @redis_rb.set("benchmark:set_rb", "value") },
                  redis_ruby_block: -> { @redis_ruby.set("benchmark:set_ruby", "value") })

    # Pipeline 10 commands
    run_benchmark("Pipeline 10",
                  redis_rb_block: lambda {
                    @redis_rb.pipelined do |pipe|
                      10.times { |i| pipe.get("benchmark:key:#{i}") }
                    end
                  },
                  redis_ruby_block: lambda {
                    @redis_ruby.pipelined do |pipe|
                      10.times { |i| pipe.get("benchmark:key:#{i}") }
                    end
                  })

    # Pipeline 100 commands
    run_benchmark("Pipeline 100",
                  redis_rb_block: lambda {
                    @redis_rb.pipelined do |pipe|
                      100.times { |i| pipe.get("benchmark:key:#{i % 100}") }
                    end
                  },
                  redis_ruby_block: lambda {
                    @redis_ruby.pipelined do |pipe|
                      100.times { |i| pipe.get("benchmark:key:#{i % 100}") }
                    end
                  })

    # Connection Setup
    run_benchmark("Connection Setup",
                  redis_rb_block: lambda {
                    c = Redis.new(url: REDIS_URL)
                    c.ping
                    c.close
                  },
                  redis_ruby_block: lambda {
                    c = RedisRuby.new(url: REDIS_URL)
                    c.ping
                    c.close
                  })
  end

  def verify_all
    puts "\n#{"=" * 70}"
    puts "PERFORMANCE GATE VERIFICATION"
    puts "=" * 70

    GATES.each do |name, gate|
      verify_gate(name, gate[:min_speedup])
    end
  end

  def cleanup
    @redis_rb.del("benchmark:key", "benchmark:set_rb", "benchmark:set_ruby")
    100.times { |i| @redis_rb.del("benchmark:key:#{i}") }
    @redis_rb.close
    @redis_ruby.close
  end

  def save_report
    FileUtils.mkdir_p("tmp")
    report = {
      timestamp: Time.now.iso8601,
      ruby_version: RUBY_VERSION,
      yjit_enabled: defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?,
      redis_url: REDIS_URL.gsub(/:[^:@]+@/, ":***@"),
      gates: GATES,
      results: @results,
      failures: @failures,
      all_passed: @failures.empty?,
    }
    File.write("tmp/gate_verification.json", JSON.pretty_generate(report))
    puts "\nReport saved to tmp/gate_verification.json"
  end

  def success?
    @failures.empty?
  end
end

# Main execution
puts "=" * 70
puts "Redis-Ruby Performance Gate Verification"
puts "=" * 70
puts "Ruby version: #{RUBY_VERSION}"
puts "YJIT enabled: #{defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?}"
puts "Redis URL: #{REDIS_URL}"
puts "Config: warmup=#{CONFIG[:warmup]}s, time=#{CONFIG[:time]}s"
puts "=" * 70

verifier = GateVerifier.new

begin
  verifier.run_all
  verifier.verify_all
  verifier.save_report
ensure
  verifier.cleanup
end

puts "\n#{"=" * 70}"
if verifier.success?
  puts "ALL PERFORMANCE GATES PASSED!"
  puts "=" * 70
  exit 0
else
  puts "PERFORMANCE GATES FAILED!"
  puts "-" * 70
  verifier.failures.each do |f|
    puts "  #{f[:name]}: #{f[:speedup].round(2)}x (need #{f[:required]}x)"
  end
  puts "=" * 70
  exit 1
end
