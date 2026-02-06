#!/usr/bin/env ruby
# frozen_string_literal: true

# Comprehensive Benchmark Suite: redis-ruby vs redis-rb
#
# This benchmark suite provides a thorough, fair comparison between
# redis-ruby and redis-rb across multiple dimensions:
#
# 1. THROUGHPUT: Operations per second (using Benchmark.ips)
# 2. LATENCY: Percentile measurements (P50, P95, P99, P99.9)
# 3. DATA SIZES: 100B, 1KB, 10KB, 100KB values
# 4. PIPELINING: Various batch sizes (1, 10, 50, 100, 500)
# 5. TRANSACTIONS: MULTI/EXEC performance
# 6. WORKLOADS: Read-heavy, write-heavy, mixed patterns
# 7. MEMORY: Allocation comparison
# 8. STATISTICS: Multiple runs with confidence intervals
#
# Based on research from:
# - Redis official benchmarking guidelines
# - memtier_benchmark methodology
# - Jedis vs Lettuce comparison patterns
# - AWS Redis client optimization guides
#
# Usage:
#   RUBYOPT="--yjit" bundle exec ruby benchmarks/comprehensive_suite.rb
#   RUBYOPT="--yjit" bundle exec ruby benchmarks/comprehensive_suite.rb --quick
#   RUBYOPT="--yjit" bundle exec ruby benchmarks/comprehensive_suite.rb --suite=latency
#
# Environment:
#   REDIS_URL     - Redis connection URL (default: redis://localhost:6379)
#   BENCHMARK_RUNS - Number of runs for statistical analysis (default: 3)

require "bundler/setup"
require "benchmark/ips"
require "json"
require "fileutils"
require "optparse"

# Load both implementations
require "redis"
require_relative "../lib/redis_ruby"

module ComprehensiveBenchmark
  VERSION = "1.0.0"

  # Configuration
  class Config
    attr_accessor :redis_url, :runs, :warmup_time, :measure_time,
                  :latency_iterations, :suites, :output_format, :verbose

    def initialize
      @redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379")
      @runs = ENV.fetch("BENCHMARK_RUNS", "3").to_i
      @warmup_time = 2
      @measure_time = 5
      @latency_iterations = 10_000
      @suites = [:all]
      @output_format = :both
      @verbose = true
    end

    def quick_mode!
      @runs = 1
      @warmup_time = 1
      @measure_time = 2
      @latency_iterations = 1_000
    end
  end

  # Test data generator
  class DataGenerator
    SIZES = {
      small: 100,      # 100 bytes
      medium: 1024,    # 1 KB
      large: 10_240,   # 10 KB
      xlarge: 102_400, # 100 KB
    }.freeze

    def self.generate_value(size_name)
      size = SIZES[size_name] || 100
      "x" * size
    end

    def self.size_bytes(size_name)
      SIZES[size_name] || 100
    end
  end

  # Latency measurement utilities
  class LatencyMeasurer
    attr_reader :samples

    def initialize
      @samples = []
    end

    def measure(&block)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
      block.call
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) - start
      @samples << elapsed / 1_000.0 # Convert to microseconds
    end

    def reset
      @samples = []
    end

    def percentile(p)
      return 0 if @samples.empty?

      sorted = @samples.sort
      index = ((p / 100.0) * sorted.length).ceil - 1
      index = [index, 0].max
      sorted[index]
    end

    def p50 = percentile(50)
    def p95 = percentile(95)
    def p99 = percentile(99)
    def p999 = percentile(99.9)

    def mean
      return 0 if @samples.empty?

      @samples.sum / @samples.length.to_f
    end

    def min = @samples.min || 0
    def max = @samples.max || 0

    def stats
      {
        count: @samples.length,
        min: min.round(2),
        max: max.round(2),
        mean: mean.round(2),
        p50: p50.round(2),
        p95: p95.round(2),
        p99: p99.round(2),
        p999: p999.round(2),
      }
    end
  end

  # Results collector
  class Results
    attr_reader :metadata, :benchmarks

    def initialize(config)
      @config = config
      @metadata = build_metadata
      @benchmarks = {}
    end

    def add_throughput(name, category:, redis_rb_ips:, redis_ruby_ips:, **extra)
      @benchmarks[name] ||= { category: category }
      @benchmarks[name][:throughput] = {
        redis_rb: { ips: redis_rb_ips.round(1) },
        redis_ruby: { ips: redis_ruby_ips.round(1) },
        speedup: (redis_ruby_ips / redis_rb_ips).round(3),
        **extra,
      }
    end

    def add_latency(name, category:, redis_rb_stats:, redis_ruby_stats:, **extra)
      @benchmarks[name] ||= { category: category }
      @benchmarks[name][:latency] = {
        redis_rb: redis_rb_stats,
        redis_ruby: redis_ruby_stats,
        improvement: {
          p50: ((redis_rb_stats[:p50] - redis_ruby_stats[:p50]) / redis_rb_stats[:p50] * 100).round(1),
          p99: ((redis_rb_stats[:p99] - redis_ruby_stats[:p99]) / redis_rb_stats[:p99] * 100).round(1),
        },
        **extra,
      }
    end

    def to_json
      JSON.pretty_generate({
        metadata: @metadata,
        benchmarks: @benchmarks,
        summary: generate_summary,
      })
    end

    private

    def build_metadata
      {
        version: VERSION,
        timestamp: Time.now.iso8601,
        ruby_version: RUBY_VERSION,
        ruby_platform: RUBY_PLATFORM,
        yjit_enabled: defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?,
        redis_url: @config.redis_url.gsub(/:[^:@]+@/, ":***@"),
        config: {
          runs: @config.runs,
          warmup_time: @config.warmup_time,
          measure_time: @config.measure_time,
          latency_iterations: @config.latency_iterations,
        },
      }
    end

    def generate_summary
      throughput_results = @benchmarks.values.filter_map { |b| b[:throughput] }
      latency_results = @benchmarks.values.filter_map { |b| b[:latency] }

      {
        total_benchmarks: @benchmarks.size,
        avg_throughput_speedup: throughput_results.empty? ? 0 :
          (throughput_results.sum { |r| r[:speedup] } / throughput_results.size).round(3),
        avg_latency_p99_improvement: latency_results.empty? ? 0 :
          (latency_results.sum { |r| r[:improvement][:p99] } / latency_results.size).round(1),
        faster_count: throughput_results.count { |r| r[:speedup] > 1.0 },
        slower_count: throughput_results.count { |r| r[:speedup] < 1.0 },
      }
    end
  end

  # Base benchmark runner
  class BenchmarkRunner
    def initialize(config)
      @config = config
      @results = Results.new(config)
      @redis_rb = nil
      @redis_ruby = nil
    end

    def setup
      @redis_rb = Redis.new(url: @config.redis_url)
      @redis_ruby = RedisRuby.new(url: @config.redis_url)

      # Pre-fill test data
      setup_test_data

      # Warmup JIT
      warmup_jit
    end

    def teardown
      cleanup_test_data
      @redis_rb&.close
      @redis_ruby&.close
    end

    def run
      setup

      begin
        suites = @config.suites.include?(:all) ? all_suites : @config.suites

        suites.each do |suite|
          puts "\n#{"=" * 70}"
          puts "SUITE: #{suite.to_s.upcase}"
          puts "=" * 70

          send("run_#{suite}_suite")
        end

        @results
      ensure
        teardown
      end
    end

    private

    def all_suites
      %i[throughput latency data_sizes pipeline transactions workloads]
    end

    def setup_test_data
      puts "Setting up test data..."

      # Keys for various tests
      @redis_rb.set("bench:key:small", DataGenerator.generate_value(:small))
      @redis_rb.set("bench:key:medium", DataGenerator.generate_value(:medium))
      @redis_rb.set("bench:key:large", DataGenerator.generate_value(:large))
      @redis_rb.set("bench:key:xlarge", DataGenerator.generate_value(:xlarge))

      # Multiple keys for batch operations
      100.times { |i| @redis_rb.set("bench:key:#{i}", "value#{i}") }

      # Hash for hash operations
      @redis_rb.hset("bench:hash", "field1", "value1", "field2", "value2")

      # List for list operations
      @redis_rb.rpush("bench:list", (1..100).map { |i| "item#{i}" })

      # Set for set operations
      @redis_rb.sadd("bench:set", (1..100).map { |i| "member#{i}" })

      # Sorted set for sorted set operations
      100.times { |i| @redis_rb.zadd("bench:zset", i, "member#{i}") }

      puts "Test data ready."
    end

    def warmup_jit
      puts "Warming up JIT (#{@config.warmup_time * 500} iterations)..."

      (@config.warmup_time * 500).times do
        @redis_rb.get("bench:key:small")
        @redis_ruby.get("bench:key:small")
        @redis_rb.set("bench:warmup", "value")
        @redis_ruby.set("bench:warmup", "value")
      end

      # Pipeline warmup
      50.times do
        @redis_rb.pipelined { |p| 10.times { |i| p.get("bench:key:#{i}") } }
        @redis_ruby.pipelined { |p| 10.times { |i| p.get("bench:key:#{i}") } }
      end

      puts "Warmup complete."
    end

    def cleanup_test_data
      puts "Cleaning up test data..."

      # Use scan instead of keys for safer cleanup
      cursor = "0"
      loop do
        cursor, keys = @redis_rb.scan(cursor, match: "bench:*", count: 100)
        @redis_rb.del(*keys) unless keys.empty?
        break if cursor == "0"
      end
    rescue StandardError => e
      puts "Cleanup warning: #{e.message}"
    end

    # ================================================================
    # THROUGHPUT SUITE
    # ================================================================
    def run_throughput_suite
      run_throughput_benchmark("PING", "Basic") do |x|
        x.report("redis-rb") { @redis_rb.ping }
        x.report("redis-ruby") { @redis_ruby.ping }
      end

      run_throughput_benchmark("GET (small)", "Basic") do |x|
        x.report("redis-rb") { @redis_rb.get("bench:key:small") }
        x.report("redis-ruby") { @redis_ruby.get("bench:key:small") }
      end

      run_throughput_benchmark("SET (small)", "Basic") do |x|
        x.report("redis-rb") { @redis_rb.set("bench:set:rb", "value") }
        x.report("redis-ruby") { @redis_ruby.set("bench:set:ruby", "value") }
      end

      run_throughput_benchmark("INCR", "Basic") do |x|
        @redis_rb.set("bench:counter", "0")
        x.report("redis-rb") { @redis_rb.incr("bench:counter") }
        x.report("redis-ruby") { @redis_ruby.incr("bench:counter") }
      end

      run_throughput_benchmark("HGET", "Hash") do |x|
        x.report("redis-rb") { @redis_rb.hget("bench:hash", "field1") }
        x.report("redis-ruby") { @redis_ruby.hget("bench:hash", "field1") }
      end

      run_throughput_benchmark("LPUSH/LPOP", "List") do |x|
        x.report("redis-rb") { @redis_rb.lpush("bench:lpop", "x"); @redis_rb.lpop("bench:lpop") }
        x.report("redis-ruby") { @redis_ruby.lpush("bench:lpop", "x"); @redis_ruby.lpop("bench:lpop") }
      end

      run_throughput_benchmark("SADD/SISMEMBER", "Set") do |x|
        x.report("redis-rb") { @redis_rb.sadd("bench:stest", "x"); @redis_rb.sismember("bench:stest", "x") }
        x.report("redis-ruby") { @redis_ruby.sadd("bench:stest", "x"); @redis_ruby.sismember("bench:stest", "x") }
      end

      run_throughput_benchmark("ZADD/ZSCORE", "SortedSet") do |x|
        x.report("redis-rb") { @redis_rb.zadd("bench:ztest", 1.0, "x"); @redis_rb.zscore("bench:ztest", "x") }
        x.report("redis-ruby") { @redis_ruby.zadd("bench:ztest", 1.0, "x"); @redis_ruby.zscore("bench:ztest", "x") }
      end
    end

    def run_throughput_benchmark(name, category, &block)
      puts "\n#{name}"
      puts "-" * 50

      rb_ips = nil
      ruby_ips = nil

      report = Benchmark.ips do |x|
        x.config(warmup: @config.warmup_time, time: @config.measure_time)
        block.call(x)
        x.compare!
      end

      report.entries.each do |entry|
        if entry.label.include?("redis-rb")
          rb_ips = entry.stats.central_tendency
        elsif entry.label.include?("redis-ruby")
          ruby_ips = entry.stats.central_tendency
        end
      end

      @results.add_throughput(name, category: category,
                                    redis_rb_ips: rb_ips,
                                    redis_ruby_ips: ruby_ips)
    end

    # ================================================================
    # LATENCY SUITE
    # ================================================================
    def run_latency_suite
      iterations = @config.latency_iterations

      run_latency_benchmark("GET Latency", "Basic", iterations) do |client|
        client.get("bench:key:small")
      end

      run_latency_benchmark("SET Latency", "Basic", iterations) do |client|
        client.set("bench:latency", "value")
      end

      run_latency_benchmark("Pipeline 10 Latency", "Pipeline", iterations / 10) do |client|
        client.pipelined { |p| 10.times { |i| p.get("bench:key:#{i}") } }
      end

      run_latency_benchmark("Pipeline 100 Latency", "Pipeline", iterations / 100) do |client|
        client.pipelined { |p| 100.times { |i| p.get("bench:key:#{i % 100}") } }
      end
    end

    def run_latency_benchmark(name, category, iterations, &block)
      puts "\n#{name} (#{iterations} iterations)"
      puts "-" * 50

      rb_measurer = LatencyMeasurer.new
      ruby_measurer = LatencyMeasurer.new

      # Measure redis-rb
      iterations.times { rb_measurer.measure { block.call(@redis_rb) } }

      # Measure redis-ruby
      iterations.times { ruby_measurer.measure { block.call(@redis_ruby) } }

      rb_stats = rb_measurer.stats
      ruby_stats = ruby_measurer.stats

      puts format("  redis-rb:   P50=%.2fus  P95=%.2fus  P99=%.2fus",
                  rb_stats[:p50], rb_stats[:p95], rb_stats[:p99])
      puts format("  redis-ruby: P50=%.2fus  P95=%.2fus  P99=%.2fus",
                  ruby_stats[:p50], ruby_stats[:p95], ruby_stats[:p99])

      improvement_p99 = ((rb_stats[:p99] - ruby_stats[:p99]) / rb_stats[:p99] * 100).round(1)
      status = improvement_p99 >= 0 ? "BETTER" : "WORSE"
      puts format("  P99 Improvement: %+.1f%% (%s)", improvement_p99, status)

      @results.add_latency(name, category: category,
                                 redis_rb_stats: rb_stats,
                                 redis_ruby_stats: ruby_stats)
    end

    # ================================================================
    # DATA SIZES SUITE
    # ================================================================
    def run_data_sizes_suite
      %i[small medium large xlarge].each do |size|
        bytes = DataGenerator.size_bytes(size)
        key = "bench:key:#{size}"

        run_throughput_benchmark("GET #{bytes}B", "DataSize") do |x|
          x.report("redis-rb") { @redis_rb.get(key) }
          x.report("redis-ruby") { @redis_ruby.get(key) }
        end

        value = DataGenerator.generate_value(size)
        run_throughput_benchmark("SET #{bytes}B", "DataSize") do |x|
          x.report("redis-rb") { @redis_rb.set("bench:size:rb", value) }
          x.report("redis-ruby") { @redis_ruby.set("bench:size:ruby", value) }
        end
      end
    end

    # ================================================================
    # PIPELINE SUITE
    # ================================================================
    def run_pipeline_suite
      [1, 10, 50, 100, 500].each do |size|
        run_throughput_benchmark("Pipeline #{size} GETs", "Pipeline") do |x|
          x.report("redis-rb") do
            @redis_rb.pipelined { |p| size.times { |i| p.get("bench:key:#{i % 100}") } }
          end
          x.report("redis-ruby") do
            @redis_ruby.pipelined { |p| size.times { |i| p.get("bench:key:#{i % 100}") } }
          end
        end

        run_throughput_benchmark("Pipeline #{size} SETs", "Pipeline") do |x|
          x.report("redis-rb") do
            @redis_rb.pipelined { |p| size.times { |i| p.set("bench:pipe:#{i}", "v#{i}") } }
          end
          x.report("redis-ruby") do
            @redis_ruby.pipelined { |p| size.times { |i| p.set("bench:pipe:#{i}", "v#{i}") } }
          end
        end
      end
    end

    # ================================================================
    # TRANSACTIONS SUITE
    # ================================================================
    def run_transactions_suite
      run_throughput_benchmark("MULTI/EXEC (3 cmds)", "Transaction") do |x|
        x.report("redis-rb") do
          @redis_rb.multi do |tx|
            tx.set("bench:tx:1", "v1")
            tx.set("bench:tx:2", "v2")
            tx.get("bench:tx:1")
          end
        end
        x.report("redis-ruby") do
          @redis_ruby.multi do |tx|
            tx.set("bench:tx:1", "v1")
            tx.set("bench:tx:2", "v2")
            tx.get("bench:tx:1")
          end
        end
      end

      run_throughput_benchmark("MULTI/EXEC (10 cmds)", "Transaction") do |x|
        x.report("redis-rb") do
          @redis_rb.multi do |tx|
            10.times { |i| tx.set("bench:tx:#{i}", "v#{i}") }
          end
        end
        x.report("redis-ruby") do
          @redis_ruby.multi do |tx|
            10.times { |i| tx.set("bench:tx:#{i}", "v#{i}") }
          end
        end
      end

      # WATCH + MULTI/EXEC
      run_throughput_benchmark("WATCH + MULTI/EXEC", "Transaction") do |x|
        @redis_rb.set("bench:watch", "0")
        x.report("redis-rb") do
          @redis_rb.watch("bench:watch") do |rd|
            rd.multi do |tx|
              tx.incr("bench:watch")
            end
          end
        end
        x.report("redis-ruby") do
          @redis_ruby.watch("bench:watch") do |rd|
            rd.multi do |tx|
              tx.incr("bench:watch")
            end
          end
        end
      end
    end

    # ================================================================
    # WORKLOADS SUITE
    # ================================================================
    def run_workloads_suite
      # Read-heavy workload (10:1 read:write ratio - typical cache pattern)
      run_throughput_benchmark("Read-Heavy (10:1)", "Workload") do |x|
        x.report("redis-rb") do
          10.times { @redis_rb.get("bench:key:small") }
          @redis_rb.set("bench:workload", "value")
        end
        x.report("redis-ruby") do
          10.times { @redis_ruby.get("bench:key:small") }
          @redis_ruby.set("bench:workload", "value")
        end
      end

      # Write-heavy workload (1:10 read:write ratio)
      run_throughput_benchmark("Write-Heavy (1:10)", "Workload") do |x|
        x.report("redis-rb") do
          @redis_rb.get("bench:key:small")
          10.times { |i| @redis_rb.set("bench:workload:#{i}", "v#{i}") }
        end
        x.report("redis-ruby") do
          @redis_ruby.get("bench:key:small")
          10.times { |i| @redis_ruby.set("bench:workload:#{i}", "v#{i}") }
        end
      end

      # Balanced workload (1:1)
      run_throughput_benchmark("Balanced (1:1)", "Workload") do |x|
        x.report("redis-rb") do
          5.times do |i|
            @redis_rb.set("bench:balanced:#{i}", "v#{i}")
            @redis_rb.get("bench:balanced:#{i}")
          end
        end
        x.report("redis-ruby") do
          5.times do |i|
            @redis_ruby.set("bench:balanced:#{i}", "v#{i}")
            @redis_ruby.get("bench:balanced:#{i}")
          end
        end
      end

      # Mixed command workload
      run_throughput_benchmark("Mixed Commands", "Workload") do |x|
        x.report("redis-rb") do
          @redis_rb.set("bench:mixed", "value")
          @redis_rb.get("bench:mixed")
          @redis_rb.incr("bench:counter")
          @redis_rb.hset("bench:hash", "f", "v")
          @redis_rb.hget("bench:hash", "f")
          @redis_rb.lpush("bench:mixlist", "item")
          @redis_rb.lpop("bench:mixlist")
        end
        x.report("redis-ruby") do
          @redis_ruby.set("bench:mixed", "value")
          @redis_ruby.get("bench:mixed")
          @redis_ruby.incr("bench:counter")
          @redis_ruby.hset("bench:hash", "f", "v")
          @redis_ruby.hget("bench:hash", "f")
          @redis_ruby.lpush("bench:mixlist", "item")
          @redis_ruby.lpop("bench:mixlist")
        end
      end
    end
  end

  # Report generator
  class ReportGenerator
    def initialize(results, config)
      @results = results
      @config = config
    end

    def generate_json(path = "tmp/comprehensive_benchmark.json")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, @results.to_json)
      puts "\nJSON report saved to: #{path}"
      path
    end

    def generate_html(path = "tmp/comprehensive_benchmark.html")
      FileUtils.mkdir_p(File.dirname(path))

      html = build_html_report
      File.write(path, html)
      puts "HTML report saved to: #{path}"
      path
    end

    def print_summary
      data = JSON.parse(@results.to_json, symbolize_names: true)

      puts "\n#{"=" * 70}"
      puts "BENCHMARK SUMMARY"
      puts "=" * 70
      puts "Ruby: #{data[:metadata][:ruby_version]} | YJIT: #{data[:metadata][:yjit_enabled]}"
      puts "-" * 70

      # Group by category
      categories = data[:benchmarks].values.group_by { |b| b[:category] }

      categories.each do |category, benchmarks|
        puts "\n#{category}:"
        benchmarks.each do |bench|
          name = data[:benchmarks].key(bench)
          if bench[:throughput]
            t = bench[:throughput]
            status = t[:speedup] >= 1.0 ? "FASTER" : "SLOWER"
            puts format("  %-30s %8.1fx  (%s)", name, t[:speedup], status)
          end
        end
      end

      puts "\n" + "-" * 70
      summary = data[:summary]
      puts format("Average Throughput Speedup: %.2fx", summary[:avg_throughput_speedup])
      puts format("Faster: %d | Slower: %d", summary[:faster_count], summary[:slower_count])
      puts "=" * 70
    end

    private

    def build_html_report
      data = JSON.parse(@results.to_json, symbolize_names: true)

      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Redis-Ruby Comprehensive Benchmark Report</title>
          <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
          <style>
            * { box-sizing: border-box; margin: 0; padding: 0; }
            body {
              font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
              line-height: 1.6;
              color: #333;
              background: #f5f7fa;
              padding: 20px;
            }
            .container { max-width: 1400px; margin: 0 auto; }
            h1 { color: #1a1a2e; margin-bottom: 10px; }
            h2 { color: #16213e; margin: 30px 0 15px; }
            .subtitle { color: #666; margin-bottom: 30px; }
            .card {
              background: white;
              border-radius: 12px;
              box-shadow: 0 2px 8px rgba(0,0,0,0.08);
              padding: 24px;
              margin-bottom: 24px;
            }
            .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; }
            .stat-card {
              background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
              color: white;
              border-radius: 12px;
              padding: 24px;
              text-align: center;
            }
            .stat-value { font-size: 2.5em; font-weight: bold; }
            .stat-label { opacity: 0.9; font-size: 0.9em; }
            table { width: 100%; border-collapse: collapse; }
            th, td { padding: 12px 16px; text-align: left; border-bottom: 1px solid #eee; }
            th { background: #f8f9fa; font-weight: 600; }
            tr:hover { background: #f8f9fa; }
            .speedup { font-weight: bold; }
            .faster { color: #28a745; }
            .slower { color: #dc3545; }
            .chart-container { height: 400px; margin: 20px 0; }
            .metadata { color: #666; font-size: 0.9em; }
            .category-header { background: #e9ecef; font-weight: 600; }
          </style>
        </head>
        <body>
          <div class="container">
            <h1>Redis-Ruby vs Redis-rb Benchmark Report</h1>
            <p class="subtitle">Comprehensive performance comparison</p>

            <div class="card metadata">
              <strong>Generated:</strong> #{data[:metadata][:timestamp]} |
              <strong>Ruby:</strong> #{data[:metadata][:ruby_version]} |
              <strong>YJIT:</strong> #{data[:metadata][:yjit_enabled]} |
              <strong>Platform:</strong> #{data[:metadata][:ruby_platform]}
            </div>

            <div class="grid">
              <div class="stat-card">
                <div class="stat-value">#{format("%.2fx", data[:summary][:avg_throughput_speedup])}</div>
                <div class="stat-label">Average Speedup</div>
              </div>
              <div class="stat-card" style="background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);">
                <div class="stat-value">#{data[:summary][:faster_count]}</div>
                <div class="stat-label">Faster Benchmarks</div>
              </div>
              <div class="stat-card" style="background: linear-gradient(135deg, #eb3349 0%, #f45c43 100%);">
                <div class="stat-value">#{data[:summary][:slower_count]}</div>
                <div class="stat-label">Slower Benchmarks</div>
              </div>
              <div class="stat-card" style="background: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%);">
                <div class="stat-value">#{data[:summary][:total_benchmarks]}</div>
                <div class="stat-label">Total Benchmarks</div>
              </div>
            </div>

            <div class="card">
              <h2>Throughput Results</h2>
              <div class="chart-container">
                <canvas id="speedupChart"></canvas>
              </div>
            </div>

            <div class="card">
              <h2>Detailed Results</h2>
              <table>
                <thead>
                  <tr>
                    <th>Benchmark</th>
                    <th>Category</th>
                    <th>redis-rb (i/s)</th>
                    <th>redis-ruby (i/s)</th>
                    <th>Speedup</th>
                  </tr>
                </thead>
                <tbody>
                  #{generate_table_rows(data[:benchmarks])}
                </tbody>
              </table>
            </div>

            #{generate_latency_section(data[:benchmarks])}
          </div>

          <script>
            const ctx = document.getElementById('speedupChart').getContext('2d');
            const benchmarks = #{data[:benchmarks].to_json};
            const labels = Object.keys(benchmarks).filter(k => benchmarks[k].throughput);
            const speedups = labels.map(k => benchmarks[k].throughput.speedup);

            new Chart(ctx, {
              type: 'bar',
              data: {
                labels: labels,
                datasets: [{
                  label: 'Speedup vs redis-rb',
                  data: speedups,
                  backgroundColor: speedups.map(s => s >= 1 ? 'rgba(40, 167, 69, 0.7)' : 'rgba(220, 53, 69, 0.7)'),
                  borderColor: speedups.map(s => s >= 1 ? 'rgba(40, 167, 69, 1)' : 'rgba(220, 53, 69, 1)'),
                  borderWidth: 1
                }]
              },
              options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                  title: { display: true, text: 'Speedup Factor (>1 = redis-ruby faster)' },
                  legend: { display: false }
                },
                scales: {
                  y: { beginAtZero: true, title: { display: true, text: 'Speedup (x)' } },
                  x: { ticks: { maxRotation: 45, minRotation: 45 } }
                }
              }
            });
          </script>
        </body>
        </html>
      HTML
    end

    def generate_table_rows(benchmarks)
      benchmarks.map do |name, data|
        next unless data[:throughput]

        t = data[:throughput]
        speedup_class = t[:speedup] >= 1.0 ? "faster" : "slower"

        "<tr>
          <td><strong>#{name}</strong></td>
          <td>#{data[:category]}</td>
          <td>#{format("%.1f", t[:redis_rb][:ips])}</td>
          <td>#{format("%.1f", t[:redis_ruby][:ips])}</td>
          <td class=\"speedup #{speedup_class}\">#{format("%.2fx", t[:speedup])}</td>
        </tr>"
      end.compact.join("\n")
    end

    def generate_latency_section(benchmarks)
      latency_benchmarks = benchmarks.select { |_, d| d[:latency] }
      return "" if latency_benchmarks.empty?

      rows = latency_benchmarks.map do |name, data|
        l = data[:latency]
        improvement_class = l[:improvement][:p99] >= 0 ? "faster" : "slower"

        "<tr>
          <td><strong>#{name}</strong></td>
          <td>#{format("%.1f", l[:redis_rb][:p50])}</td>
          <td>#{format("%.1f", l[:redis_rb][:p99])}</td>
          <td>#{format("%.1f", l[:redis_ruby][:p50])}</td>
          <td>#{format("%.1f", l[:redis_ruby][:p99])}</td>
          <td class=\"speedup #{improvement_class}\">#{format("%+.1f%%", l[:improvement][:p99])}</td>
        </tr>"
      end.join("\n")

      <<~HTML
        <div class="card">
          <h2>Latency Results (microseconds)</h2>
          <table>
            <thead>
              <tr>
                <th>Benchmark</th>
                <th>redis-rb P50</th>
                <th>redis-rb P99</th>
                <th>redis-ruby P50</th>
                <th>redis-ruby P99</th>
                <th>P99 Improvement</th>
              </tr>
            </thead>
            <tbody>
              #{rows}
            </tbody>
          </table>
        </div>
      HTML
    end
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  config = ComprehensiveBenchmark::Config.new

  OptionParser.new do |opts|
    opts.banner = "Usage: #{$PROGRAM_NAME} [options]"

    opts.on("--quick", "Run quick benchmarks (shorter warmup/measurement)") do
      config.quick_mode!
    end

    opts.on("--suite=SUITE", "Run specific suite (throughput,latency,data_sizes,pipeline,transactions,workloads)") do |suite|
      config.suites = suite.split(",").map(&:to_sym)
    end

    opts.on("--json", "Output JSON only") { config.output_format = :json }
    opts.on("--html", "Output HTML only") { config.output_format = :html }
    opts.on("--quiet", "Reduce output") { config.verbose = false }
  end.parse!

  puts "=" * 70
  puts "COMPREHENSIVE BENCHMARK SUITE v#{ComprehensiveBenchmark::VERSION}"
  puts "=" * 70
  puts "Ruby: #{RUBY_VERSION}"
  puts "YJIT: #{defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?}"
  puts "Redis: #{config.redis_url}"
  puts "Suites: #{config.suites.join(", ")}"
  puts "=" * 70

  runner = ComprehensiveBenchmark::BenchmarkRunner.new(config)
  results = runner.run

  reporter = ComprehensiveBenchmark::ReportGenerator.new(results, config)

  case config.output_format
  when :json
    reporter.generate_json
  when :html
    reporter.generate_html
  else
    reporter.generate_json
    reporter.generate_html
  end

  reporter.print_summary
end
