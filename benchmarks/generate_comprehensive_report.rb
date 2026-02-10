#!/usr/bin/env ruby
# frozen_string_literal: true

# Comprehensive Benchmark Report Generator
#
# Generates benchmark reports for all combinations:
# - Ruby versions: 3.3.0, 3.4.x (if available)
# - YJIT: on/off
# - redis-rb: with/without hiredis
#
# Usage:
#   bundle exec ruby benchmarks/generate_comprehensive_report.rb

require "bundler/setup"
require "benchmark/ips"
require "json"
require "fileutils"

# Load both implementations
require "redis" # redis-rb gem
require_relative "../lib/redis_ruby"

REDIS_URL = ENV.fetch("REDIS_URL", "redis://localhost:6379")

class ComprehensiveBenchmark
  def initialize
    @results = {
      metadata: {
        timestamp: Time.now.iso8601,
        hostname: `hostname`.strip,
        ruby_version: RUBY_VERSION,
        ruby_platform: RUBY_PLATFORM,
        yjit_enabled: yjit_enabled?,
        yjit_stats: yjit_stats,
      },
      benchmarks: {},
    }
  end

  def yjit_enabled?
    defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?
  end

  def yjit_stats
    return nil unless yjit_enabled?

    if RubyVM::YJIT.respond_to?(:runtime_stats)
      RubyVM::YJIT.runtime_stats
    else
      {}
    end
  end

  def run_all
    puts "=" * 80
    puts "Comprehensive Benchmark Report"
    puts "=" * 80
    puts "Ruby: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
    puts "YJIT: #{yjit_enabled? ? 'enabled' : 'disabled'}"
    puts "Redis URL: #{REDIS_URL}"
    puts "=" * 80
    puts

    # Test redis-rb configurations
    test_redis_rb_plain
    test_redis_rb_hiredis
    test_redis_ruby

    save_report
    print_summary
  end

  def test_redis_rb_plain
    puts "\n" + "=" * 80
    puts "Testing: redis-rb (plain Ruby driver)"
    puts "=" * 80

    redis = Redis.new(url: REDIS_URL)
    setup_test_data(redis)

    @redis_rb_plain = {
      single_get: benchmark_single_get(redis, "redis-rb (plain)"),
      single_set: benchmark_single_set(redis, "redis-rb (plain)"),
      pipeline_10: benchmark_pipeline_10(redis, "redis-rb (plain)"),
      pipeline_100: benchmark_pipeline_100(redis, "redis-rb (plain)"),
    }

    redis.close
  end

  def test_redis_rb_hiredis
    puts "\n" + "=" * 80
    puts "Testing: redis-rb (with hiredis)"
    puts "=" * 80

    begin
      # Try to load hiredis from system gems
      gem "hiredis"
      require "hiredis"
      redis = Redis.new(url: REDIS_URL, driver: :hiredis)
      setup_test_data(redis)

      @redis_rb_hiredis = {
        single_get: benchmark_single_get(redis, "redis-rb (hiredis)"),
        single_set: benchmark_single_set(redis, "redis-rb (hiredis)"),
        pipeline_10: benchmark_pipeline_10(redis, "redis-rb (hiredis)"),
        pipeline_100: benchmark_pipeline_100(redis, "redis-rb (hiredis)"),
      }

      redis.close
    rescue LoadError, Gem::LoadError => e
      puts "Hiredis not available (#{e.message}), skipping..."
      @redis_rb_hiredis = nil
    end
  end

  def test_redis_ruby
    puts "\n" + "=" * 80
    puts "Testing: redis-ruby"
    puts "=" * 80

    redis = RedisRuby.new(url: REDIS_URL)
    setup_test_data(redis)

    @redis_ruby = {
      single_get: benchmark_single_get(redis, "redis-ruby"),
      single_set: benchmark_single_set(redis, "redis-ruby"),
      pipeline_10: benchmark_pipeline_10(redis, "redis-ruby"),
      pipeline_100: benchmark_pipeline_100(redis, "redis-ruby"),
    }

    redis.close
  end

  def setup_test_data(redis)
    redis.set("bench:key", "value")
    100.times { |i| redis.set("bench:#{i}", "value#{i}") }
  end

  def benchmark_single_get(redis, label)
    puts "\nSingle GET:"
    report = Benchmark.ips do |x|
      x.config(warmup: 2, time: 5)
      x.report(label) { redis.get("bench:key") }
    end
    report.entries.first.stats.central_tendency
  end

  def benchmark_single_set(redis, label)
    puts "\nSingle SET:"
    report = Benchmark.ips do |x|
      x.config(warmup: 2, time: 5)
      x.report(label) { redis.set("bench:set", "value") }
    end
    report.entries.first.stats.central_tendency
  end

  def benchmark_pipeline_10(redis, label)
    puts "\nPipeline 10 commands:"
    report = Benchmark.ips do |x|
      x.config(warmup: 2, time: 5)
      x.report(label) do
        redis.pipelined do |pipe|
          10.times { |i| pipe.get("bench:#{i}") }
        end
      end
    end
    report.entries.first.stats.central_tendency
  end

  def benchmark_pipeline_100(redis, label)
    puts "\nPipeline 100 commands:"
    report = Benchmark.ips do |x|
      x.config(warmup: 2, time: 5)
      x.report(label) do
        redis.pipelined do |pipe|
          100.times { |i| pipe.get("bench:#{i % 100}") }
        end
      end
    end
    report.entries.first.stats.central_tendency
  end

  def save_report
    @results[:benchmarks] = {
      redis_rb_plain: @redis_rb_plain,
      redis_rb_hiredis: @redis_rb_hiredis,
      redis_ruby: @redis_ruby,
    }

    FileUtils.mkdir_p("tmp")
    filename = "tmp/comprehensive_benchmark_#{Time.now.strftime('%Y%m%d_%H%M%S')}.json"
    File.write(filename, JSON.pretty_generate(@results))
    puts "\n" + "=" * 80
    puts "Report saved to: #{filename}"
    puts "=" * 80
  end

  def print_summary
    puts "\n" + "=" * 80
    puts "SUMMARY"
    puts "=" * 80

    if @redis_rb_plain && @redis_ruby
      print_comparison("redis-ruby vs redis-rb (plain)", @redis_ruby, @redis_rb_plain)
    end

    if @redis_rb_hiredis && @redis_ruby
      puts
      print_comparison("redis-ruby vs redis-rb (hiredis)", @redis_ruby, @redis_rb_hiredis)
    end
  end

  def print_comparison(title, ruby_results, rb_results)
    puts "\n#{title}:"
    puts "-" * 80

    [:single_get, :single_set, :pipeline_10, :pipeline_100].each do |bench|
      ruby_ips = ruby_results[bench]
      rb_ips = rb_results[bench]
      next unless ruby_ips && rb_ips

      speedup = ruby_ips / rb_ips
      status = speedup >= 1.0 ? "✓" : "✗"
      puts "  #{status} #{bench.to_s.ljust(20)}: #{speedup.round(2)}x (#{ruby_ips.round(0)} vs #{rb_ips.round(0)} ops/s)"
    end
  end
end

# Run the benchmark
benchmark = ComprehensiveBenchmark.new
benchmark.run_all

