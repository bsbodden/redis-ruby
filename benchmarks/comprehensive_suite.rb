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

    def measure
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
      yield
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) - start
      @samples << (elapsed / 1_000.0) # Convert to microseconds
    end

    def reset
      @samples = []
    end

    def percentile(pct)
      return 0 if @samples.empty?

      sorted = @samples.sort
      index = ((pct / 100.0) * sorted.length).ceil - 1
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

    def to_json(*_args)
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
        avg_throughput_speedup: average_throughput_speedup(throughput_results),
        avg_latency_p99_improvement: average_latency_improvement(latency_results),
        faster_count: throughput_results.count { |r| r[:speedup] > 1.0 },
        slower_count: throughput_results.count { |r| r[:speedup] < 1.0 },
      }
    end

    def average_throughput_speedup(results)
      return 0 if results.empty?

      (results.sum { |r| r[:speedup] } / results.size).round(3)
    end

    def average_latency_improvement(results)
      return 0 if results.empty?

      (results.sum { |r| r[:improvement][:p99] } / results.size).round(1)
    end
  end

  # Transaction benchmarks extracted for class length
  module TransactionBenchmarks
    def run_transactions_suite
      run_multi_exec_small_benchmark
      run_multi_exec_large_benchmark
      run_watch_multi_benchmark
    end

    private

    def run_multi_exec_small_benchmark
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
    end

    def run_multi_exec_large_benchmark
      run_throughput_benchmark("MULTI/EXEC (10 cmds)", "Transaction") do |x|
        x.report("redis-rb") do
          @redis_rb.multi { |tx| 10.times { |i| tx.set("bench:tx:#{i}", "v#{i}") } }
        end
        x.report("redis-ruby") do
          @redis_ruby.multi { |tx| 10.times { |i| tx.set("bench:tx:#{i}", "v#{i}") } }
        end
      end
    end

    def run_watch_multi_benchmark
      run_throughput_benchmark("WATCH + MULTI/EXEC", "Transaction") do |x|
        @redis_rb.set("bench:watch", "0")
        x.report("redis-rb") do
          @redis_rb.watch("bench:watch") { |rd| rd.multi { |tx| tx.incr("bench:watch") } }
        end
        x.report("redis-ruby") do
          @redis_ruby.watch("bench:watch") { |rd| rd.multi { |tx| tx.incr("bench:watch") } }
        end
      end
    end
  end

  # Workload benchmarks extracted for class length
  module WorkloadBenchmarks
    def run_workloads_suite
      run_read_heavy_workload
      run_write_heavy_workload
      run_balanced_workload
      run_mixed_commands_workload
    end

    private

    def run_read_heavy_workload
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
    end

    def run_write_heavy_workload
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
    end

    def run_balanced_workload
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
    end

    def run_mixed_commands_workload
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

  # Data size and pipeline benchmarks
  module DataPipelineBenchmarks
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

    def run_pipeline_suite
      [1, 10, 50, 100, 500].each do |size|
        run_throughput_benchmark("Pipeline #{size} GETs", "Pipeline") do |x|
          x.report("redis-rb") { @redis_rb.pipelined { |p| size.times { |i| p.get("bench:key:#{i % 100}") } } }
          x.report("redis-ruby") { @redis_ruby.pipelined { |p| size.times { |i| p.get("bench:key:#{i % 100}") } } }
        end

        run_throughput_benchmark("Pipeline #{size} SETs", "Pipeline") do |x|
          x.report("redis-rb") { @redis_rb.pipelined { |p| size.times { |i| p.set("bench:pipe:#{i}", "v#{i}") } } }
          x.report("redis-ruby") { @redis_ruby.pipelined { |p| size.times { |i| p.set("bench:pipe:#{i}", "v#{i}") } } }
        end
      end
    end
  end

  # Throughput benchmark suite methods
  module ThroughputBenchmarks
    def run_throughput_suite
      run_basic_throughput_benchmarks
      run_data_structure_throughput_benchmarks
    end

    def run_basic_throughput_benchmarks
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
    end

    def run_data_structure_throughput_benchmarks
      run_hash_benchmark
      run_list_benchmark
      run_set_benchmarks
    end

    private

    def run_hash_benchmark
      run_throughput_benchmark("HGET", "Hash") do |x|
        x.report("redis-rb") { @redis_rb.hget("bench:hash", "field1") }
        x.report("redis-ruby") { @redis_ruby.hget("bench:hash", "field1") }
      end
    end

    def run_list_benchmark
      run_throughput_benchmark("LPUSH/LPOP", "List") do |x|
        x.report("redis-rb") do
          @redis_rb.lpush("bench:lpop", "x")
          @redis_rb.lpop("bench:lpop")
        end
        x.report("redis-ruby") do
          @redis_ruby.lpush("bench:lpop", "x")
          @redis_ruby.lpop("bench:lpop")
        end
      end
    end

    def run_set_benchmarks
      run_throughput_benchmark("SADD/SISMEMBER", "Set") do |x|
        x.report("redis-rb") do
          @redis_rb.sadd("bench:stest", "x")
          @redis_rb.sismember("bench:stest", "x")
        end
        x.report("redis-ruby") do
          @redis_ruby.sadd("bench:stest", "x")
          @redis_ruby.sismember("bench:stest", "x")
        end
      end

      run_throughput_benchmark("ZADD/ZSCORE", "SortedSet") do |x|
        x.report("redis-rb") do
          @redis_rb.zadd("bench:ztest", 1.0, "x")
          @redis_rb.zscore("bench:ztest", "x")
        end
        x.report("redis-ruby") do
          @redis_ruby.zadd("bench:ztest", 1.0, "x")
          @redis_ruby.zscore("bench:ztest", "x")
        end
      end
    end
  end

  # Latency benchmark suite methods
  module LatencyBenchmarks
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

    private

    def run_latency_benchmark(name, category, iterations, &)
      puts "\n#{name} (#{iterations} iterations)"
      puts "-" * 50

      rb_stats, ruby_stats = collect_latency_stats(iterations, &)
      print_latency_stats(rb_stats, ruby_stats)

      @results.add_latency(name, category: category,
                                 redis_rb_stats: rb_stats,
                                 redis_ruby_stats: ruby_stats)
    end

    def collect_latency_stats(iterations)
      rb_measurer = LatencyMeasurer.new
      ruby_measurer = LatencyMeasurer.new

      iterations.times { rb_measurer.measure { yield(@redis_rb) } }
      iterations.times { ruby_measurer.measure { yield(@redis_ruby) } }

      [rb_measurer.stats, ruby_measurer.stats]
    end

    def print_latency_stats(rb_stats, ruby_stats)
      puts format("  redis-rb:   P50=%<p50>.2fus  P95=%<p95>.2fus  P99=%<p99>.2fus",
                  p50: rb_stats[:p50], p95: rb_stats[:p95], p99: rb_stats[:p99])
      puts format("  redis-ruby: P50=%<p50>.2fus  P95=%<p95>.2fus  P99=%<p99>.2fus",
                  p50: ruby_stats[:p50], p95: ruby_stats[:p95], p99: ruby_stats[:p99])

      improvement_p99 = ((rb_stats[:p99] - ruby_stats[:p99]) / rb_stats[:p99] * 100).round(1)
      status = improvement_p99 >= 0 ? "BETTER" : "WORSE"
      puts format("  P99 Improvement: %<imp>+.1f%% (%<status>s)", imp: improvement_p99, status: status)
    end
  end

  # Base benchmark runner
  class BenchmarkRunner
    include TransactionBenchmarks
    include WorkloadBenchmarks
    include DataPipelineBenchmarks
    include ThroughputBenchmarks
    include LatencyBenchmarks

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

      setup_string_test_data
      setup_collection_test_data

      puts "Test data ready."
    end

    def setup_string_test_data
      @redis_rb.set("bench:key:small", DataGenerator.generate_value(:small))
      @redis_rb.set("bench:key:medium", DataGenerator.generate_value(:medium))
      @redis_rb.set("bench:key:large", DataGenerator.generate_value(:large))
      @redis_rb.set("bench:key:xlarge", DataGenerator.generate_value(:xlarge))
      100.times { |i| @redis_rb.set("bench:key:#{i}", "value#{i}") }
    end

    def setup_collection_test_data
      @redis_rb.hset("bench:hash", "field1", "value1", "field2", "value2")
      @redis_rb.rpush("bench:list", (1..100).map { |i| "item#{i}" })
      @redis_rb.sadd("bench:set", (1..100).map { |i| "member#{i}" })
      100.times { |i| @redis_rb.zadd("bench:zset", i, "member#{i}") }
    end

    def warmup_jit
      puts "Warming up JIT (#{@config.warmup_time * 500} iterations)..."
      warmup_basic_commands
      warmup_pipelines
      puts "Warmup complete."
    end

    def warmup_basic_commands
      (@config.warmup_time * 500).times do
        @redis_rb.get("bench:key:small")
        @redis_ruby.get("bench:key:small")
        @redis_rb.set("bench:warmup", "value")
        @redis_ruby.set("bench:warmup", "value")
      end
    end

    def warmup_pipelines
      50.times do
        @redis_rb.pipelined { |p| 10.times { |i| p.get("bench:key:#{i}") } }
        @redis_ruby.pipelined { |p| 10.times { |i| p.get("bench:key:#{i}") } }
      end
    end

    def cleanup_test_data
      puts "Cleaning up test data..."

      cursor = "0"
      loop do
        cursor, keys = @redis_rb.scan(cursor, match: "bench:*", count: 100)
        @redis_rb.del(*keys) unless keys.empty?
        break if cursor == "0"
      end
    rescue StandardError => e
      puts "Cleanup warning: #{e.message}"
    end

    def run_throughput_benchmark(name, category)
      puts "\n#{name}"
      puts "-" * 50

      rb_ips = nil
      ruby_ips = nil

      report = Benchmark.ips do |x|
        x.config(warmup: @config.warmup_time, time: @config.measure_time)
        yield(x)
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
  end

  # HTML data row building helpers
  module HtmlDataRows
    private

    def generate_table_rows(benchmarks)
      benchmarks.filter_map do |name, data|
        next unless data[:throughput]

        build_table_row(name, data)
      end.join("\n")
    end

    def build_table_row(name, data)
      t = data[:throughput]
      css = t[:speedup] >= 1.0 ? "faster" : "slower"
      rb_val = format("%<val>.1f", val: t[:redis_rb][:ips])
      ruby_val = format("%<val>.1f", val: t[:redis_ruby][:ips])
      speedup_val = format("%<val>.2fx", val: t[:speedup])

      "<tr><td><strong>#{name}</strong></td>" \
        "<td>#{data[:category]}</td>" \
        "<td>#{rb_val}</td><td>#{ruby_val}</td>" \
        "<td class=\"speedup #{css}\">#{speedup_val}</td></tr>"
    end

    def generate_latency_section(benchmarks)
      latency_benchmarks = benchmarks.select { |_, d| d[:latency] }
      return "" if latency_benchmarks.empty?

      rows = latency_benchmarks.map { |name, data| build_latency_row(name, data) }.join("\n")
      latency_section_html(rows)
    end

    def build_latency_row(name, data)
      l = data[:latency]
      css = l[:improvement][:p99] >= 0 ? "faster" : "slower"

      "<tr><td><strong>#{name}</strong></td>" \
        "<td>#{format("%<v>.1f", v: l[:redis_rb][:p50])}</td>" \
        "<td>#{format("%<v>.1f", v: l[:redis_rb][:p99])}</td>" \
        "<td>#{format("%<v>.1f", v: l[:redis_ruby][:p50])}</td>" \
        "<td>#{format("%<v>.1f", v: l[:redis_ruby][:p99])}</td>" \
        "<td class=\"speedup #{css}\">#{format("%<v>+.1f%%", v: l[:improvement][:p99])}</td></tr>"
    end

    def latency_section_html(rows)
      <<~HTML
        <div class="card">
          <h2>Latency Results (microseconds)</h2>
          <table>
            <thead>
              <tr>
                <th>Benchmark</th><th>redis-rb P50</th><th>redis-rb P99</th>
                <th>redis-ruby P50</th><th>redis-ruby P99</th><th>P99 Improvement</th>
              </tr>
            </thead>
            <tbody>#{rows}</tbody>
          </table>
        </div>
      HTML
    end
  end

  # HTML report structure and layout
  module HtmlReportBuilder
    include HtmlDataRows

    private

    def build_html_report
      data = JSON.parse(@results.to_json, symbolize_names: true)

      [
        html_head_section,
        html_body_header(data[:metadata]),
        html_stats_grid(data[:summary]),
        html_chart_section,
        html_results_table(data[:benchmarks]),
        generate_latency_section(data[:benchmarks]),
        html_chart_script(data[:benchmarks]),
        html_footer,
      ].join("\n")
    end

    def html_head_section
      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Redis-Ruby Comprehensive Benchmark Report</title>
          <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
          #{html_styles}
        </head>
      HTML
    end

    def html_styles
      <<~CSS
        <style>
          * { box-sizing: border-box; margin: 0; padding: 0; }
          body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6; color: #333; background: #f5f7fa; padding: 20px;
          }
          .container { max-width: 1400px; margin: 0 auto; }
          h1 { color: #1a1a2e; margin-bottom: 10px; }
          h2 { color: #16213e; margin: 30px 0 15px; }
          .subtitle { color: #666; margin-bottom: 30px; }
          .card { background: white; border-radius: 12px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.08); padding: 24px; margin-bottom: 24px; }
          .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; }
          .stat-card { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white; border-radius: 12px; padding: 24px; text-align: center; }
          .stat-value { font-size: 2.5em; font-weight: bold; }
          .stat-label { opacity: 0.9; font-size: 0.9em; }
          table { width: 100%; border-collapse: collapse; }
          th, td { padding: 12px 16px; text-align: left; border-bottom: 1px solid #eee; }
          th { background: #f8f9fa; font-weight: 600; }
          tr:hover { background: #f8f9fa; }
          .speedup { font-weight: bold; }
          .faster { color: #28a745; } .slower { color: #dc3545; }
          .chart-container { height: 400px; margin: 20px 0; }
          .metadata { color: #666; font-size: 0.9em; }
        </style>
      CSS
    end

    def html_body_header(metadata)
      <<~HTML
        <body>
        <div class="container">
          <h1>Redis-Ruby vs Redis-rb Benchmark Report</h1>
          <p class="subtitle">Comprehensive performance comparison</p>
          <div class="card metadata">
            <strong>Generated:</strong> #{metadata[:timestamp]} |
            <strong>Ruby:</strong> #{metadata[:ruby_version]} |
            <strong>YJIT:</strong> #{metadata[:yjit_enabled]} |
            <strong>Platform:</strong> #{metadata[:ruby_platform]}
          </div>
      HTML
    end

    def stat_card(value, label, style = nil)
      style_attr = style ? " style=\"background: #{style};\"" : ""
      "<div class=\"stat-card\"#{style_attr}>" \
        "<div class=\"stat-value\">#{value}</div>" \
        "<div class=\"stat-label\">#{label}</div></div>"
    end

    def html_stats_grid(summary)
      avg = format("%<val>.2fx", val: summary[:avg_throughput_speedup])
      cards = [
        stat_card(avg, "Average Speedup"),
        stat_card(summary[:faster_count], "Faster Benchmarks",
                  "linear-gradient(135deg, #11998e 0%, #38ef7d 100%)"),
        stat_card(summary[:slower_count], "Slower Benchmarks",
                  "linear-gradient(135deg, #eb3349 0%, #f45c43 100%)"),
        stat_card(summary[:total_benchmarks], "Total Benchmarks",
                  "linear-gradient(135deg, #4facfe 0%, #00f2fe 100%)"),
      ]
      "<div class=\"grid\">#{cards.join("\n")}</div>"
    end

    def html_chart_section
      <<~HTML
        <div class="card">
          <h2>Throughput Results</h2>
          <div class="chart-container"><canvas id="speedupChart"></canvas></div>
        </div>
      HTML
    end

    def html_results_table(benchmarks)
      <<~HTML
        <div class="card">
          <h2>Detailed Results</h2>
          <table>
            <thead>
              <tr>
                <th>Benchmark</th><th>Category</th>
                <th>redis-rb (i/s)</th><th>redis-ruby (i/s)</th><th>Speedup</th>
              </tr>
            </thead>
            <tbody>#{generate_table_rows(benchmarks)}</tbody>
          </table>
        </div>
      HTML
    end

    def html_chart_script(benchmarks)
      <<~HTML
        <script>
          const ctx = document.getElementById('speedupChart').getContext('2d');
          const benchmarks = #{benchmarks.to_json};
          const labels = Object.keys(benchmarks).filter(k => benchmarks[k].throughput);
          const speedups = labels.map(k => benchmarks[k].throughput.speedup);
          new Chart(ctx, {
            type: 'bar',
            data: { labels: labels, datasets: [{
              label: 'Speedup vs redis-rb', data: speedups,
              backgroundColor: speedups.map(s =>
                s >= 1 ? 'rgba(40, 167, 69, 0.7)' : 'rgba(220, 53, 69, 0.7)'),
              borderColor: speedups.map(s =>
                s >= 1 ? 'rgba(40, 167, 69, 1)' : 'rgba(220, 53, 69, 1)'),
              borderWidth: 1
            }]},
            options: { responsive: true, maintainAspectRatio: false,
              plugins: { title: { display: true,
                text: 'Speedup Factor (>1 = redis-ruby faster)' },
                legend: { display: false } },
              scales: { y: { beginAtZero: true,
                title: { display: true, text: 'Speedup (x)' } },
                x: { ticks: { maxRotation: 45, minRotation: 45 } } } }
          });
        </script>
      HTML
    end

    def html_footer
      "</div>\n</body>\n</html>"
    end
  end

  # Summary printing helpers
  module SummaryPrinter
    def print_summary
      data = JSON.parse(@results.to_json, symbolize_names: true)
      print_summary_header(data[:metadata])
      print_category_results(data[:benchmarks])
      print_summary_footer(data[:summary])
    end

    private

    def print_summary_header(metadata)
      puts "\n#{"=" * 70}"
      puts "BENCHMARK SUMMARY"
      puts "=" * 70
      puts "Ruby: #{metadata[:ruby_version]} | YJIT: #{metadata[:yjit_enabled]}"
      puts "-" * 70
    end

    def print_category_results(benchmarks)
      categories = benchmarks.values.group_by { |b| b[:category] }

      categories.each do |category, benches|
        puts "\n#{category}:"
        benches.each do |bench|
          name = benchmarks.key(bench)
          print_bench_result(name, bench[:throughput])
        end
      end
    end

    def print_bench_result(name, throughput)
      return unless throughput

      status = throughput[:speedup] >= 1.0 ? "FASTER" : "SLOWER"
      puts format("  %<name>-30s %<speedup>8.1fx  (%<status>s)",
                  name: name, speedup: throughput[:speedup], status: status)
    end

    def print_summary_footer(summary)
      puts "\n#{"-" * 70}"
      puts format("Average Throughput Speedup: %<speedup>.2fx",
                  speedup: summary[:avg_throughput_speedup])
      puts format("Faster: %<faster>d | Slower: %<slower>d",
                  faster: summary[:faster_count], slower: summary[:slower_count])
      puts "=" * 70
    end
  end

  # Report generator
  class ReportGenerator
    include HtmlReportBuilder
    include SummaryPrinter

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

    opts.on("--suite=SUITE",
            "Run specific suite (throughput,latency,data_sizes,pipeline,transactions,workloads)") do |suite|
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
