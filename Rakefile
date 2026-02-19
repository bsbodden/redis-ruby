# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"
require "rubocop/rake_task"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
  t.warning = true
end

RuboCop::RakeTask.new

task default: %i[rubocop test]

# Helper to define a standard test task
def define_test_task(name, pattern)
  Rake::TestTask.new(name) do |t|
    t.libs << "test"
    t.libs << "lib"
    t.test_files = FileList[pattern]
    t.warning = true
  end
end

namespace :test do
  desc "Run tests with TestContainers (starts Redis in Docker)"
  task :containers do
    ENV.delete("REDIS_URL")
    Rake::Task["test"].invoke
  end

  desc "Run tests against local Redis"
  task :local do
    ENV["REDIS_URL"] ||= "redis://localhost:6379"
    Rake::Task["test"].invoke
  end

  define_test_task(:unit, "test/unit/**/*_test.rb")
  define_test_task(:cluster, "test/integration/cluster/**/*_test.rb")
  define_test_task(:sentinel, "test/integration/sentinel/**/*_test.rb")

  desc "Run integration tests (standalone Redis, excludes cluster/sentinel/enterprise)"
  Rake::TestTask.new(:integration) do |t|
    t.libs << "test"
    t.libs << "lib"
    t.test_files = FileList["test/integration/**/*_test.rb"]
      .exclude("test/integration/cluster/**/*_test.rb")
      .exclude("test/integration/sentinel/**/*_test.rb")
      .exclude("test/integration/active_active_enterprise_test.rb")
    t.warning = true
  end
end

# Helper to run Jekyll in docs directory
def run_in_docs_dir(*commands)
  Bundler.with_unbundled_env do
    Dir.chdir("docs") do
      commands.each { |cmd| sh cmd }
    end
  end
end

namespace :docs do
  desc "Generate YARD API documentation"
  task :api do
    sh "bundle exec yard doc"
  end

  desc "Build Jekyll documentation site"
  task(:build) { run_in_docs_dir("bundle check || bundle install --quiet", "bundle exec jekyll build") }

  desc "Serve Jekyll documentation site locally"
  task(:serve) { run_in_docs_dir("bundle check || bundle install --quiet", "bundle exec jekyll serve --livereload") }

  desc "Generate all documentation (API + site)"
  task all: %i[api build]

  desc "Clean generated documentation"
  task :clean do
    sh "rm -rf docs/_site"
    sh "rm -rf .yardoc"
  end
end

desc "Generate all documentation"
task docs: "docs:all"

desc "Generate YARD documentation (alias)"
task doc: "docs:api"

desc "Start a console with the library loaded"
task :console do
  sh "bundle exec irb -r redis_ruby"
end

# Helper for quality tasks that report ok/not-ok
def run_quality_tool(tool_name, command)
  puts "\n=== #{tool_name} ==="
  sh command do |ok, _res|
    puts ok ? "No issues detected!" : "See above for details"
  end
end

def define_quality_analysis_tasks
  desc "Run Flog (ABC complexity metrics)"
  task :flog do
    puts "\n=== Flog: ABC Complexity Analysis ==="
    puts "Lower scores are better. Methods > 20 need attention, > 40 are problematic.\n\n"
    sh "bundle exec flog -g lib/**/*.rb"
  end

  desc "Run Flay (code duplication detection)"
  task :flay do
    puts "\n=== Flay: Code Duplication Analysis ==="
    puts "Detects similar code structures that could be refactored.\n\n"
    sh "bundle exec flay lib/**/*.rb"
  end

  desc "Run Reek (code smell detection)"
  task(:reek) { run_quality_tool("Reek: Code Smell Detection", "bundle exec reek lib") }

  desc "Run Debride (find unused methods)"
  task(:debride) { run_quality_tool("Debride: Unused Method Detection", "bundle exec debride lib") }

  desc "Run Fasterer (performance suggestions)"
  task(:fasterer) { run_quality_tool("Fasterer: Performance Suggestions", "bundle exec fasterer") }
end

def define_quality_report_tasks
  desc "Generate HTML quality report"
  task :report do
    sh "bundle exec rubycritic lib --no-browser"
    puts "\nReport generated at tmp/rubycritic/overview.html"
  end

  desc "Quick quality summary (flog totals only)"
  task :summary do
    puts "\n=== Quick Quality Summary ==="
    sh "bundle exec flog -s lib/**/*.rb | head -20"
    puts "\n"
    sh "bundle exec flay -s lib/**/*.rb"
  end
end

# Code Quality Tasks (similar to Python's mfcqi)
namespace :quality do
  desc "Run all code quality checks"
  task all: %i[rubycritic flog flay reek debride fasterer]

  desc "Generate RubyCritic report (unified quality score)"
  task :rubycritic do
    require "rubycritic_small_badge"
    require "rubycritic/rake_task"
    sh "bundle exec rubycritic lib --no-browser --format console"
  rescue LoadError
    sh "bundle exec rubycritic lib --no-browser --format console"
  end

  define_quality_analysis_tasks
  define_quality_report_tasks
end

desc "Run code quality checks"
task quality: "quality:all"

# Helper to run a benchmark with YJIT
def yjit_rubyopt
  "#{ENV.fetch("RUBYOPT", "")} --yjit"
end

def run_benchmark_with_yjit(script)
  sh "RUBYOPT='#{yjit_rubyopt}' bundle exec ruby #{script}"
end

def print_benchmark_header(title)
  puts "\n#{"=" * 70}"
  puts title
  puts "=" * 70
end

def define_benchmark_core_tasks
  desc "Run micro-benchmarks (basic operations: PING, GET, SET, etc.)"
  task :micro do
    print_benchmark_header("MICRO-BENCHMARKS: Basic Redis Operations")
    run_benchmark_with_yjit("benchmarks/compare_basic.rb")
  end

  desc "Run integration benchmarks (pipelines, mixed workloads)"
  task :integration do
    print_benchmark_header("INTEGRATION BENCHMARKS: Pipelines and Mixed Workloads")
    run_benchmark_with_yjit("benchmarks/compare_comprehensive.rb")
  end
end

def define_benchmark_run_tasks
  define_benchmark_core_tasks

  desc "Run RESP3 parser benchmarks (protocol layer)"
  task :resp3 do
    print_benchmark_header("RESP3 PARSER BENCHMARKS")
    run_benchmark_with_yjit("benchmarks/compare_resp3_parser.rb")
  end

  desc "Run async benchmarks (fiber-based async client)"
  task(:async) { run_benchmark_with_yjit("benchmarks/compare_async.rb") }

  desc "Compare redis-ruby vs hiredis directly"
  task(:hiredis) { run_benchmark_with_yjit("benchmarks/compare_vs_hiredis.rb") }
end

def print_gate_info
  puts "Gates from CLAUDE.md:"
  puts "  - Single GET/SET: 1.3x faster than redis-rb"
  puts "  - Pipeline (10 cmds): 1.5x faster"
  puts "  - Pipeline (100 cmds): 2x faster"
  puts "  - Connection setup: Equal or faster"
  puts "=" * 70
end

def define_benchmark_gate_task
  desc "Verify performance gates from CLAUDE.md (CI/CD compatible)"
  task :gates do
    print_benchmark_header("PERFORMANCE GATE VERIFICATION")
    print_gate_info
    run_benchmark_with_yjit("benchmarks/verify_gates.rb")
  end
end

def define_benchmark_profile_tasks
  desc "Run CPU profiler (StackProf) and generate flamegraph data"
  task :profile_cpu do
    print_benchmark_header("CPU PROFILING (StackProf)")
    run_benchmark_with_yjit("benchmarks/profile_hotspots.rb stackprof")
    puts "\nProfile saved to tmp/stackprof_*.json"
    puts "View with: bundle exec stackprof --flamegraph tmp/stackprof_*.json > tmp/flamegraph.html"
  end

  desc "Run memory profiler and show allocation sites"
  task :profile_memory do
    print_benchmark_header("MEMORY PROFILING")
    sh "bundle exec ruby benchmarks/profile_hotspots.rb memory"
    puts "\nProfile saved to tmp/memory_profile.txt"
  end

  desc "Run modern profiler (Vernier) with YJIT awareness"
  task :profile_vernier do
    print_benchmark_header("VERNIER PROFILING (YJIT-aware)")
    run_benchmark_with_yjit("benchmarks/profile_hotspots.rb vernier")
    puts "\nProfile saved to tmp/vernier_*.json"
    puts "View at: https://vernier.prof/ or with: vernier view tmp/vernier_*.json"
  end
end

def define_benchmark_report_tasks
  desc "Generate JSON benchmark report"
  task :report_json do
    print_benchmark_header("GENERATING JSON BENCHMARK REPORT")
    run_benchmark_with_yjit("benchmarks/generate_report.rb json")
    puts "\nReport saved to tmp/benchmark_report.json"
  end

  desc "Generate HTML benchmark report with charts"
  task :report_html do
    print_benchmark_header("GENERATING HTML BENCHMARK REPORT")
    run_benchmark_with_yjit("benchmarks/generate_report.rb html")
    puts "\nReport saved to tmp/benchmark_report.html"
  end

  desc "Generate full benchmark report (JSON + HTML)"
  task report_all: %i[report_json report_html]
end

def define_benchmark_quick_task
  desc "Quick benchmark (fast feedback, reduced iterations)"
  task :quick do
    print_benchmark_header("QUICK BENCHMARK (reduced warmup/iterations for fast feedback)")
    ENV["BENCHMARK_QUICK"] = "1"
    run_benchmark_with_yjit("benchmarks/compare_basic.rb")
  end
end

def define_benchmark_yjit_tasks
  define_benchmark_quick_task

  desc "Run with YJIT explicitly enabled"
  task :yjit do
    print_benchmark_header("YJIT-ENABLED BENCHMARKS")
    sh "RUBYOPT='--yjit' bundle exec ruby benchmarks/compare_comprehensive.rb"
  end

  desc "Run without YJIT (comparison baseline)"
  task :no_yjit do
    print_benchmark_header("NON-YJIT BENCHMARKS (baseline comparison)")
    sh "RUBYOPT='--disable-yjit' bundle exec ruby benchmarks/compare_comprehensive.rb"
  end

  desc "Compare YJIT vs non-YJIT performance"
  task :yjit_comparison do
    print_benchmark_header("YJIT vs NON-YJIT COMPARISON")
    puts "\n--- Running WITHOUT YJIT ---"
    sh "RUBYOPT='--disable-yjit' bundle exec ruby benchmarks/compare_basic.rb 2>&1 | tee tmp/benchmark_no_yjit.txt"
    puts "\n--- Running WITH YJIT ---"
    sh "RUBYOPT='--yjit' bundle exec ruby benchmarks/compare_basic.rb 2>&1 | tee tmp/benchmark_yjit.txt"
    puts "\nResults saved to tmp/benchmark_no_yjit.txt and tmp/benchmark_yjit.txt"
  end
end

# Benchmarking Tasks - Comprehensive performance evaluation framework
# Inspired by Lettuce (gold standard), Jedis JMH patterns, and redis-py benchmarks
namespace :benchmark do
  desc "Run all benchmarks (micro + integration + gates)"
  task all: %i[micro integration gates]

  define_benchmark_run_tasks
  define_benchmark_gate_task
  define_benchmark_profile_tasks
  define_benchmark_report_tasks
  define_benchmark_yjit_tasks
end

desc "Run benchmarks (alias for benchmark:all)"
task benchmark: "benchmark:all"
