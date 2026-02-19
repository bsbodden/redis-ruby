#!/usr/bin/env ruby
# frozen_string_literal: true

# Benchmark Report Generator
#
# Generates JSON and HTML reports from benchmark runs.
# Designed for CI/CD integration and historical tracking.
#
# Usage:
#   bundle exec ruby benchmarks/generate_report.rb json   # JSON only
#   bundle exec ruby benchmarks/generate_report.rb html   # HTML only
#   bundle exec ruby benchmarks/generate_report.rb        # Both

require "bundler/setup"
require "benchmark/ips"
require "json"
require "fileutils"
require "erb"

# Load both implementations
require "redis" # redis-rb gem
require_relative "../lib/redis_ruby"

REDIS_URL = ENV.fetch("REDIS_URL", "redis://localhost:6379")
OUTPUT_FORMAT = ARGV[0] || "both"

# Benchmark configuration
CONFIG = ENV["BENCHMARK_QUICK"] ? { warmup: 1, time: 2 } : { warmup: 2, time: 5 }

# Performance gates from CLAUDE.md
GATES = {
  "Single GET" => { min_speedup: 1.3, description: "Basic GET operation" },
  "Single SET" => { min_speedup: 1.3, description: "Basic SET operation" },
  "Pipeline 10" => { min_speedup: 1.5, description: "10-command pipeline" },
  "Pipeline 100" => { min_speedup: 2.0, description: "100-command pipeline" },
  "Connection Setup" => { min_speedup: 1.0, description: "Connection overhead" },
  "INCR" => { min_speedup: 1.3, description: "Counter increment" },
  "Mixed Workload" => { min_speedup: 1.3, description: "SET+GET+EXISTS+DEL" },
}.freeze

# Extracts IPS data from benchmark report entries
module BenchmarkExtractor
  def self.extract_entries(report)
    rb_ips = nil
    rb_stddev = nil
    ruby_ips = nil
    ruby_stddev = nil

    report.entries.each do |entry|
      case entry.label
      when "redis-rb"
        rb_ips = entry.stats.central_tendency
        rb_stddev = entry.stats.error
      when "redis-ruby"
        ruby_ips = entry.stats.central_tendency
        ruby_stddev = entry.stats.error
      end
    end

    { rb_ips: rb_ips, rb_stddev: rb_stddev, ruby_ips: ruby_ips, ruby_stddev: ruby_stddev }
  end
end

# Runs individual benchmarks
module BenchmarkDefinitions
  def run_single_benchmarks
    run_benchmark("Single GET",
                  redis_rb_block: -> { @redis_rb.get("benchmark:key") },
                  redis_ruby_block: -> { @redis_ruby.get("benchmark:key") })

    run_benchmark("Single SET",
                  redis_rb_block: -> { @redis_rb.set("benchmark:set_rb", "value") },
                  redis_ruby_block: -> { @redis_ruby.set("benchmark:set_ruby", "value") })

    run_benchmark("GET 2KB",
                  redis_rb_block: -> { @redis_rb.get("benchmark:2kb") },
                  redis_ruby_block: -> { @redis_ruby.get("benchmark:2kb") })

    run_benchmark("INCR",
                  redis_rb_block: -> { @redis_rb.incr("benchmark:counter") },
                  redis_ruby_block: -> { @redis_ruby.incr("benchmark:counter") })
  end

  def run_mixed_benchmark
    run_benchmark("Mixed Workload",
                  redis_rb_block: lambda {
                    @redis_rb.set("benchmark:mixed_rb", "value")
                    @redis_rb.get("benchmark:mixed_rb")
                    @redis_rb.exists("benchmark:mixed_rb")
                    @redis_rb.del("benchmark:mixed_rb")
                  },
                  redis_ruby_block: lambda {
                    @redis_ruby.set("benchmark:mixed_ruby", "value")
                    @redis_ruby.get("benchmark:mixed_ruby")
                    @redis_ruby.exists("benchmark:mixed_ruby")
                    @redis_ruby.del("benchmark:mixed_ruby")
                  })
  end

  def run_pipeline_benchmarks
    run_benchmark("Pipeline 10",
                  redis_rb_block: lambda {
                    @redis_rb.pipelined { |p| 10.times { |i| p.get("benchmark:key:#{i}") } }
                  },
                  redis_ruby_block: lambda {
                    @redis_ruby.pipelined { |p| 10.times { |i| p.get("benchmark:key:#{i}") } }
                  })

    run_benchmark("Pipeline 100",
                  redis_rb_block: lambda {
                    @redis_rb.pipelined { |p| 100.times { |i| p.get("benchmark:key:#{i % 100}") } }
                  },
                  redis_ruby_block: lambda {
                    @redis_ruby.pipelined { |p| 100.times { |i| p.get("benchmark:key:#{i % 100}") } }
                  })
  end

  def run_connection_and_roundtrip_benchmarks
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

    run_benchmark("SET+GET Round-trip",
                  redis_rb_block: lambda {
                    @redis_rb.set("benchmark:roundtrip_rb", "value")
                    @redis_rb.get("benchmark:roundtrip_rb")
                  },
                  redis_ruby_block: lambda {
                    @redis_ruby.set("benchmark:roundtrip_ruby", "value")
                    @redis_ruby.get("benchmark:roundtrip_ruby")
                  })
  end
end

# Generates HTML report from benchmark results
class HtmlReportBuilder
  def initialize(metadata, results)
    @metadata = metadata
    @results = results
  end

  def generate(path)
    summary = generate_summary
    template = build_template
    erb = ERB.new(template)
    html = erb.result(binding)

    FileUtils.mkdir_p("tmp")
    File.write(path, html)
    puts "\nHTML report saved to #{path}"
    path
  end

  private

  def generate_summary
    passes = @results.count { |_, r| r[:passed] }
    failures = @results.count { |_, r| !r[:passed] && r[:gate] }
    gated_tests = @results.count { |_, r| r[:gate] }

    {
      total_benchmarks: @results.size,
      gated_benchmarks: gated_tests,
      gates_passed: passes,
      gates_failed: failures,
      all_gates_passed: failures.zero?,
      average_speedup: (@results.values.sum { |r| r[:speedup] } / @results.size).round(2),
    }
  end

  def build_template
    head_section + body_open_section + charts_section + scripts_section
  end

  def head_section
    <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Redis-Ruby Benchmark Report</title>
        <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
        #{css_styles}
      </head>
    HTML
  end

  def css_styles
    <<~CSS
      <style>
        * { box-sizing: border-box; }
        body {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
          line-height: 1.6; color: #333; max-width: 1200px; margin: 0 auto;
          padding: 20px; background: #f5f5f5;
        }
        h1 { color: #1a1a1a; border-bottom: 3px solid #dc382c; padding-bottom: 10px; }
        h2 { color: #444; margin-top: 30px; }
        .metadata { background: white; padding: 20px; border-radius: 8px;
          box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-bottom: 20px; }
        .metadata p { margin: 5px 0; }
        .metadata strong { color: #dc382c; }
        .summary-cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
          gap: 20px; margin-bottom: 30px; }
        .card { background: white; padding: 20px; border-radius: 8px;
          box-shadow: 0 2px 4px rgba(0,0,0,0.1); text-align: center; }
        .card.pass { border-top: 4px solid #28a745; }
        .card.fail { border-top: 4px solid #dc3545; }
        .card.info { border-top: 4px solid #17a2b8; }
        .card-value { font-size: 2.5em; font-weight: bold; color: #1a1a1a; }
        .card-label { color: #666; font-size: 0.9em; }
        table { width: 100%; border-collapse: collapse; background: white; border-radius: 8px;
          overflow: hidden; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        th, td { padding: 15px; text-align: left; border-bottom: 1px solid #eee; }
        th { background: #f8f9fa; font-weight: 600; color: #444; }
        .speedup { font-weight: bold; }
        .speedup.good { color: #28a745; }
        .speedup.bad { color: #dc3545; }
        .status { padding: 4px 12px; border-radius: 4px; font-size: 0.85em; font-weight: 500; }
        .status.pass { background: #d4edda; color: #155724; }
        .status.fail { background: #f8d7da; color: #721c24; }
        .status.info { background: #d1ecf1; color: #0c5460; }
        .chart-container { background: white; padding: 20px; border-radius: 8px;
          margin: 30px 0; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .footer { text-align: center; color: #666; margin-top: 40px; font-size: 0.9em; }
      </style>
    CSS
  end

  def body_open_section
    <<~HTML
      <body>
        <h1>Redis-Ruby Benchmark Report</h1>
        <div class="metadata">
          <p><strong>Generated:</strong> <%= @metadata[:timestamp] %></p>
          <p><strong>Ruby:</strong> <%= @metadata[:ruby_version] %> (<%= @metadata[:ruby_platform] %>)</p>
          <p><strong>YJIT:</strong> <%= @metadata[:yjit_enabled] ? 'Enabled' : 'Disabled' %></p>
        </div>
        <div class="summary-cards">
          <div class="card <%= summary[:all_gates_passed] ? 'pass' : 'fail' %>">
            <div class="card-value"><%= summary[:gates_passed] %>/<%= summary[:gated_benchmarks] %></div>
            <div class="card-label">Gates Passed</div>
          </div>
          <div class="card info">
            <div class="card-value"><%= summary[:average_speedup] %>x</div>
            <div class="card-label">Average Speedup</div>
          </div>
        </div>
        <h2>Performance Results</h2>
        <table>
          <thead>
            <tr><th>Benchmark</th><th>redis-rb</th><th>redis-ruby</th><th>Speedup</th><th>Required</th><th>Status</th></tr>
          </thead>
          <tbody>
            <% @results.each do |name, result| %>
            <tr>
              <td><strong><%= name %></strong></td>
              <td><%= result[:redis_rb][:ips].round(1) %></td>
              <td><%= result[:redis_ruby][:ips].round(1) %></td>
              <td class="speedup <%= result[:speedup] >= 1.0 ? 'good' : 'bad' %>"><%= result[:speedup].round(2) %>x</td>
              <td><%= result[:gate] ? result[:gate].to_s + 'x' : 'N/A' %></td>
              <td>
                <% if result[:gate].nil? %>
                  <span class="status info">INFO</span>
                <% elsif result[:passed] %>
                  <span class="status pass">PASS</span>
                <% else %>
                  <span class="status fail">FAIL</span>
                <% end %>
              </td>
            </tr>
            <% end %>
          </tbody>
        </table>
    HTML
  end

  def charts_section
    <<~HTML
      <div class="chart-container"><canvas id="speedupChart"></canvas></div>
      <div class="chart-container"><canvas id="ipsChart"></canvas></div>
      <div class="footer"><p>Generated by redis-ruby benchmark suite</p></div>
    HTML
  end

  def scripts_section
    <<~HTML
        <script>
          const speedupCtx = document.getElementById('speedupChart').getContext('2d');
          new Chart(speedupCtx, {
            type: 'bar',
            data: {
              labels: <%= @results.keys.to_json %>,
              datasets: [{ label: 'Speedup vs redis-rb',
                data: <%= @results.values.map { |r| r[:speedup].round(2) }.to_json %>,
                backgroundColor: <%= bar_colors.to_json %>, borderWidth: 1 }]
            },
            options: { responsive: true,
              plugins: { title: { display: true, text: 'Speedup vs redis-rb' }, legend: { display: false } },
              scales: { y: { beginAtZero: true, title: { display: true, text: 'Speedup Factor' } } } }
          });
          const ipsCtx = document.getElementById('ipsChart').getContext('2d');
          new Chart(ipsCtx, {
            type: 'bar',
            data: {
              labels: <%= @results.keys.to_json %>,
              datasets: [
                { label: 'redis-rb',
                  data: <%= @results.values.map { |r| r[:redis_rb][:ips].round(0) }.to_json %>,
                  backgroundColor: 'rgba(108,117,125,0.7)', borderWidth: 1 },
                { label: 'redis-ruby',
                  data: <%= @results.values.map { |r| r[:redis_ruby][:ips].round(0) }.to_json %>,
                  backgroundColor: 'rgba(220,56,44,0.7)', borderWidth: 1 }
              ]
            },
            options: { responsive: true,
              plugins: { title: { display: true, text: 'Iterations per Second' } },
              scales: { y: { beginAtZero: true } } }
          });
        </script>
      </body>
      </html>
    HTML
  end

  def bar_colors
    @results.values.map do |result|
      if result[:gate].nil?
        "rgba(23, 162, 184, 0.7)"
      elsif result[:passed]
        "rgba(40, 167, 69, 0.7)"
      else
        "rgba(220, 53, 69, 0.7)"
      end
    end
  end
end

class BenchmarkReporter
  include BenchmarkDefinitions

  attr_reader :results

  def initialize
    @redis_rb = Redis.new(url: REDIS_URL)
    @redis_ruby = RedisRuby.new(url: REDIS_URL)
    @results = {}
    @metadata = build_metadata
    setup_test_data
  end

  def build_metadata
    {
      timestamp: Time.now.iso8601,
      ruby_version: RUBY_VERSION,
      ruby_platform: RUBY_PLATFORM,
      yjit_enabled: defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?,
      redis_url: REDIS_URL.gsub(/:[^:@]+@/, ":***@"),
      benchmark_config: CONFIG,
    }
  end

  def setup_test_data
    puts "Setting up test data..."
    @redis_rb.set("benchmark:key", "value")
    @redis_rb.set("benchmark:2kb", "x" * 2048)
    @redis_rb.set("benchmark:counter", "0")
    100.times { |i| @redis_rb.set("benchmark:key:#{i}", "value#{i}") }
  end

  def run_benchmark(name, redis_rb_block:, redis_ruby_block:)
    puts "\nBenchmarking: #{name}"
    puts "-" * 50

    report = Benchmark.ips do |x|
      x.config(**CONFIG)
      x.report("redis-rb") { redis_rb_block.call }
      x.report("redis-ruby") { redis_ruby_block.call }
      x.compare!
    end

    store_result(name, report)
  end

  def run_all_benchmarks
    run_single_benchmarks
    run_mixed_benchmark
    run_pipeline_benchmarks
    run_connection_and_roundtrip_benchmarks
  end

  def generate_json_report
    report = { metadata: @metadata, gates: GATES, results: @results, summary: generate_summary }
    FileUtils.mkdir_p("tmp")
    path = "tmp/benchmark_report.json"
    File.write(path, JSON.pretty_generate(report))
    puts "\nJSON report saved to #{path}"
    path
  end

  def generate_summary
    passes = @results.count { |_, r| r[:passed] }
    failures = @results.count { |_, r| !r[:passed] && r[:gate] }
    gated_tests = @results.count { |_, r| r[:gate] }

    {
      total_benchmarks: @results.size,
      gated_benchmarks: gated_tests,
      gates_passed: passes,
      gates_failed: failures,
      all_gates_passed: failures.zero?,
      average_speedup: (@results.values.sum { |r| r[:speedup] } / @results.size).round(2),
    }
  end

  def generate_html_report
    HtmlReportBuilder.new(@metadata, @results).generate("tmp/benchmark_report.html")
  end

  def cleanup
    @redis_rb.del("benchmark:key", "benchmark:2kb", "benchmark:counter",
                  "benchmark:set_rb", "benchmark:set_ruby",
                  "benchmark:mixed_rb", "benchmark:mixed_ruby",
                  "benchmark:roundtrip_rb", "benchmark:roundtrip_ruby")
    100.times { |i| @redis_rb.del("benchmark:key:#{i}") }
    @redis_rb.close
    @redis_ruby.close
  end

  private

  def store_result(name, report)
    data = BenchmarkExtractor.extract_entries(report)
    speedup = data[:ruby_ips] / data[:rb_ips]
    gate = GATES[name]

    @results[name] = {
      redis_rb: { ips: data[:rb_ips], stddev: data[:rb_stddev] },
      redis_ruby: { ips: data[:ruby_ips], stddev: data[:ruby_stddev] },
      speedup: speedup,
      gate: gate ? gate[:min_speedup] : nil,
      passed: gate.nil? || speedup >= gate[:min_speedup],
      description: gate ? gate[:description] : nil,
    }
    speedup
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  puts "=" * 70
  puts "Redis-Ruby Benchmark Report Generator"
  puts "=" * 70
  puts "Ruby version: #{RUBY_VERSION}"
  puts "YJIT enabled: #{defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?}"
  puts "Redis URL: #{REDIS_URL}"
  puts "Output format: #{OUTPUT_FORMAT}"
  puts "=" * 70

  reporter = BenchmarkReporter.new

  begin
    reporter.run_all_benchmarks

    case OUTPUT_FORMAT
    when "json" then reporter.generate_json_report
    when "html" then reporter.generate_html_report
    else
      reporter.generate_json_report
      reporter.generate_html_report
    end

    summary = reporter.generate_summary
    puts "\n#{"=" * 70}"
    puts "SUMMARY"
    puts "-" * 70
    puts "Total benchmarks: #{summary[:total_benchmarks]}"
    puts "Gates passed: #{summary[:gates_passed]}/#{summary[:gated_benchmarks]}"
    puts "Average speedup: #{summary[:average_speedup]}x"
    puts "=" * 70

    exit(summary[:all_gates_passed] ? 0 : 1)
  ensure
    reporter.cleanup
  end
end
