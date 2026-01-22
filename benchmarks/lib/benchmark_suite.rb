# frozen_string_literal: true

# Comprehensive benchmarking suite for redis-ruby
# Inspired by Lettuce (gold standard), Jedis JMH patterns, and redis-py benchmarks
#
# Features:
# - Consistent benchmark configuration (warmup, measurement, iterations)
# - JSON report generation for CI/CD integration
# - Performance gate verification (from CLAUDE.md)
# - Memory profiling integration
# - Cross-client comparison (vs redis-rb)

require "benchmark/ips"
require "json"
require "time"

module RedisRuby
  module Benchmarks
    # Performance gates from CLAUDE.md - these are the minimum speedup requirements
    PERFORMANCE_GATES = {
      "RESP3 Parser" => { min_speedup: 1.5, description: "Protocol parsing" },
      "Single GET" => { min_speedup: 1.3, description: "Basic GET operation" },
      "Single SET" => { min_speedup: 1.3, description: "Basic SET operation" },
      "Pipeline 10" => { min_speedup: 1.5, description: "10-command pipeline" },
      "Pipeline 100" => { min_speedup: 2.0, description: "100-command pipeline" },
      "Connection Setup" => { min_speedup: 1.0, description: "Connection overhead" },
    }.freeze

    # Default benchmark configuration based on best practices
    # - 2s warmup: Allows YJIT compilation and CPU stabilization
    # - 5s measurement: Produces statistically significant results
    # - Bootstrap confidence intervals for error estimation
    DEFAULT_CONFIG = {
      warmup: 2,
      time: 5,
    }.freeze

    # Suite for running comprehensive benchmarks
    class Suite
      attr_reader :results, :metadata

      def initialize(redis_url: nil)
        @redis_url = redis_url || ENV.fetch("REDIS_URL", "redis://localhost:6379")
        @results = {}
        @metadata = build_metadata
      end

      def build_metadata
        {
          timestamp: Time.now.iso8601,
          ruby_version: RUBY_VERSION,
          ruby_platform: RUBY_PLATFORM,
          yjit_enabled: yjit_enabled?,
          redis_url: @redis_url.gsub(/:[^:@]+@/, ":***@"), # Mask password
        }
      end

      def yjit_enabled?
        defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?
      end

      # Run a comparison benchmark and store results
      def compare(name, redis_rb:, redis_ruby:, config: DEFAULT_CONFIG)
        result = {
          name: name,
          config: config,
          measurements: {},
        }

        Benchmark.ips do |x|
          x.config(**config)

          x.report("redis-rb") { redis_rb.call }
          x.report("redis-ruby") { redis_ruby.call }

          x.compare!

          # Capture results after comparison
          x.entries.each do |entry|
            result[:measurements][entry.label] = {
              ips: entry.stats.central_tendency,
              stddev: entry.stats.error,
              iterations: entry.iterations,
            }
          end
        end

        # Calculate speedup ratio
        redis_rb_ips = result[:measurements]["redis-rb"][:ips]
        redis_ruby_ips = result[:measurements]["redis-ruby"][:ips]
        result[:speedup] = redis_ruby_ips / redis_rb_ips

        @results[name] = result
        result
      end

      # Verify all results against performance gates
      def verify_gates
        failures = []
        passes = []

        PERFORMANCE_GATES.each do |name, gate|
          result = @results[name]
          next unless result

          speedup = result[:speedup]
          if speedup >= gate[:min_speedup]
            passes << {
              name: name,
              speedup: speedup,
              required: gate[:min_speedup],
              status: :pass,
            }
          else
            failures << {
              name: name,
              speedup: speedup,
              required: gate[:min_speedup],
              status: :fail,
            }
          end
        end

        {
          passes: passes,
          failures: failures,
          all_passed: failures.empty?,
        }
      end

      # Generate JSON report
      def to_json(*_args)
        report = {
          metadata: @metadata,
          gates: PERFORMANCE_GATES,
          results: @results,
          verification: verify_gates,
        }
        JSON.pretty_generate(report)
      end

      # Save report to file
      def save_report(path)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, to_json)
        path
      end

      # Print summary to console
      def print_summary
        puts "\n" + "=" * 70
        puts "BENCHMARK SUMMARY"
        puts "=" * 70
        puts "Ruby: #{@metadata[:ruby_version]} | YJIT: #{@metadata[:yjit_enabled]}"
        puts "Timestamp: #{@metadata[:timestamp]}"
        puts "-" * 70

        @results.each do |name, result|
          speedup = result[:speedup]
          gate = PERFORMANCE_GATES[name]
          status = if gate.nil?
                     "[INFO]"
                   elsif speedup >= gate[:min_speedup]
                     "[PASS]"
                   else
                     "[FAIL]"
                   end

          required = gate ? " (need #{gate[:min_speedup]}x)" : ""
          puts format("%-25s %s %.2fx faster%s", name, status, speedup, required)
        end

        puts "-" * 70
        verification = verify_gates
        if verification[:all_passed]
          puts "All performance gates PASSED!"
        else
          puts "WARNING: #{verification[:failures].length} performance gate(s) FAILED"
          verification[:failures].each do |f|
            puts "  - #{f[:name]}: #{f[:speedup].round(2)}x (need #{f[:required]}x)"
          end
        end
        puts "=" * 70
      end
    end

    # Memory profiling utilities
    module Memory
      def self.profile(name, &block)
        require "memory_profiler"

        report = MemoryProfiler.report(&block)

        {
          name: name,
          total_allocated: report.total_allocated,
          total_retained: report.total_retained,
          allocated_memory: report.total_allocated_memsize,
          retained_memory: report.total_retained_memsize,
        }
      end

      def self.compare(name, redis_rb:, redis_ruby:, iterations: 1000)
        rb_report = profile("redis-rb") do
          iterations.times { redis_rb.call }
        end

        ruby_report = profile("redis-ruby") do
          iterations.times { redis_ruby.call }
        end

        {
          name: name,
          iterations: iterations,
          redis_rb: rb_report,
          redis_ruby: ruby_report,
          memory_ratio: rb_report[:allocated_memory].to_f / ruby_report[:allocated_memory],
        }
      end
    end

    # CPU profiling utilities
    module CPU
      def self.profile_stackprof(name, iterations: 10_000, &block)
        require "stackprof"

        profile = StackProf.run(mode: :cpu, interval: 1000, raw: true) do
          iterations.times(&block)
        end

        path = "tmp/stackprof_#{name.downcase.gsub(/\s+/, "_")}.json"
        FileUtils.mkdir_p("tmp")
        File.write(path, JSON.pretty_generate(profile))
        path
      end

      def self.profile_vernier(name, iterations: 10_000, &block)
        require "vernier"

        path = "tmp/vernier_#{name.downcase.gsub(/\s+/, "_")}.json"
        FileUtils.mkdir_p("tmp")

        Vernier.profile(out: path) do
          iterations.times(&block)
        end

        path
      end
    end

    # HTML report generator
    module HTMLReport
      TEMPLATE = <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <title>Redis-Ruby Benchmark Report</title>
          <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 40px; }
            h1 { color: #333; }
            .metadata { background: #f5f5f5; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
            .result { margin: 20px 0; padding: 15px; border: 1px solid #ddd; border-radius: 5px; }
            .pass { border-left: 4px solid #28a745; }
            .fail { border-left: 4px solid #dc3545; }
            .info { border-left: 4px solid #17a2b8; }
            .speedup { font-size: 1.5em; font-weight: bold; }
            .chart-container { max-width: 800px; margin: 40px auto; }
            table { width: 100%%; border-collapse: collapse; }
            th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
            th { background: #f5f5f5; }
          </style>
        </head>
        <body>
          <h1>Redis-Ruby Benchmark Report</h1>
          <div class="metadata">
            <strong>Generated:</strong> %{timestamp}<br>
            <strong>Ruby:</strong> %{ruby_version} | <strong>YJIT:</strong> %{yjit_enabled}
          </div>

          <h2>Performance Gate Summary</h2>
          <table>
            <tr><th>Benchmark</th><th>Speedup</th><th>Required</th><th>Status</th></tr>
            %{gate_rows}
          </table>

          <div class="chart-container">
            <canvas id="speedupChart"></canvas>
          </div>

          <h2>Detailed Results</h2>
          %{result_sections}

          <script>
            const ctx = document.getElementById('speedupChart').getContext('2d');
            new Chart(ctx, {
              type: 'bar',
              data: {
                labels: %{chart_labels},
                datasets: [{
                  label: 'Speedup vs redis-rb',
                  data: %{chart_data},
                  backgroundColor: %{chart_colors},
                  borderWidth: 1
                }]
              },
              options: {
                scales: { y: { beginAtZero: true } },
                plugins: {
                  title: { display: true, text: 'redis-ruby vs redis-rb Performance' }
                }
              }
            });
          </script>
        </body>
        </html>
      HTML

      def self.generate(json_report, output_path)
        data = JSON.parse(json_report)
        metadata = data["metadata"]
        results = data["results"]

        gate_rows = results.map do |name, result|
          gate = PERFORMANCE_GATES[name]
          speedup = result["speedup"]
          status = if gate.nil?
                     "info"
                   elsif speedup >= gate[:min_speedup]
                     "pass"
                   else
                     "fail"
                   end
          required = gate ? "#{gate[:min_speedup]}x" : "N/A"
          status_text = status.upcase

          "<tr class='#{status}'><td>#{name}</td><td>#{speedup.round(2)}x</td>" \
            "<td>#{required}</td><td>#{status_text}</td></tr>"
        end.join("\n")

        result_sections = results.map do |name, result|
          measurements = result["measurements"]
          rb_ips = measurements["redis-rb"]["ips"].round(1)
          ruby_ips = measurements["redis-ruby"]["ips"].round(1)

          <<~SECTION
            <div class="result">
              <h3>#{name}</h3>
              <p><strong>redis-rb:</strong> #{rb_ips} i/s</p>
              <p><strong>redis-ruby:</strong> #{ruby_ips} i/s</p>
              <p class="speedup">Speedup: #{result["speedup"].round(2)}x</p>
            </div>
          SECTION
        end.join("\n")

        chart_labels = results.keys.to_json
        chart_data = results.values.map { |r| r["speedup"].round(2) }.to_json
        chart_colors = results.map do |name, result|
          gate = PERFORMANCE_GATES[name]
          if gate.nil?
            "'rgba(23, 162, 184, 0.6)'"
          elsif result["speedup"] >= gate[:min_speedup]
            "'rgba(40, 167, 69, 0.6)'"
          else
            "'rgba(220, 53, 69, 0.6)'"
          end
        end.to_s

        html = format(TEMPLATE,
                      timestamp: metadata["timestamp"],
                      ruby_version: metadata["ruby_version"],
                      yjit_enabled: metadata["yjit_enabled"],
                      gate_rows: gate_rows,
                      result_sections: result_sections,
                      chart_labels: chart_labels,
                      chart_data: chart_data,
                      chart_colors: chart_colors)

        FileUtils.mkdir_p(File.dirname(output_path))
        File.write(output_path, html)
        output_path
      end
    end
  end
end
