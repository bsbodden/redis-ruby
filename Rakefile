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

  Rake::TestTask.new(:unit) do |t|
    t.libs << "test"
    t.libs << "lib"
    t.test_files = FileList["test/unit/**/*_test.rb"]
    t.warning = true
  end

  Rake::TestTask.new(:integration) do |t|
    t.libs << "test"
    t.libs << "lib"
    t.test_files = FileList["test/integration/**/*_test.rb"]
    t.warning = true
  end

  Rake::TestTask.new(:cluster) do |t|
    t.libs << "test"
    t.libs << "lib"
    t.test_files = FileList["test/integration/cluster/**/*_test.rb"]
    t.warning = true
  end

  Rake::TestTask.new(:sentinel) do |t|
    t.libs << "test"
    t.libs << "lib"
    t.test_files = FileList["test/integration/sentinel/**/*_test.rb"]
    t.warning = true
  end
end

namespace :docs do
  desc "Generate YARD API documentation"
  task :api do
    sh "bundle exec yard doc"
  end

  desc "Build Jekyll documentation site"
  task :build do
    Bundler.with_unbundled_env do
      Dir.chdir("docs") do
        sh "bundle check || bundle install --quiet"
        sh "bundle exec jekyll build"
      end
    end
  end

  desc "Serve Jekyll documentation site locally"
  task :serve do
    Bundler.with_unbundled_env do
      Dir.chdir("docs") do
        sh "bundle check || bundle install --quiet"
        sh "bundle exec jekyll serve --livereload"
      end
    end
  end

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
  task :reek do
    puts "\n=== Reek: Code Smell Detection ==="
    sh "bundle exec reek lib" do |ok, _res|
      # Reek returns non-zero if smells found, but that's OK for informational purposes
      puts ok ? "No code smells detected!" : "Some code smells found (see above)"
    end
  end

  desc "Run Debride (find unused methods)"
  task :debride do
    puts "\n=== Debride: Unused Method Detection ==="
    sh "bundle exec debride lib" do |ok, _res|
      puts ok ? "No unused methods detected!" : "Review above for potentially unused methods"
    end
  end

  desc "Run Fasterer (performance suggestions)"
  task :fasterer do
    puts "\n=== Fasterer: Performance Suggestions ==="
    sh "bundle exec fasterer" do |ok, _res|
      puts ok ? "No performance improvements suggested!" : "See suggestions above"
    end
  end

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

desc "Run code quality checks"
task quality: "quality:all"

# Benchmarking Tasks - Comprehensive performance evaluation framework
# Inspired by Lettuce (gold standard), Jedis JMH patterns, and redis-py benchmarks
namespace :benchmark do
  desc "Run all benchmarks (micro + integration + gates)"
  task all: %i[micro integration gates]

  desc "Run micro-benchmarks (basic operations: PING, GET, SET, etc.)"
  task :micro do
    puts "\n#{"=" * 70}"
    puts "MICRO-BENCHMARKS: Basic Redis Operations"
    puts "=" * 70
    sh "RUBYOPT='#{ENV.fetch("RUBYOPT", "")} --yjit' bundle exec ruby benchmarks/compare_basic.rb"
  end

  desc "Run integration benchmarks (pipelines, mixed workloads)"
  task :integration do
    puts "\n#{"=" * 70}"
    puts "INTEGRATION BENCHMARKS: Pipelines and Mixed Workloads"
    puts "=" * 70
    sh "RUBYOPT='#{ENV.fetch("RUBYOPT", "")} --yjit' bundle exec ruby benchmarks/compare_comprehensive.rb"
  end

  desc "Run RESP3 parser benchmarks (protocol layer)"
  task :resp3 do
    puts "\n#{"=" * 70}"
    puts "RESP3 PARSER BENCHMARKS"
    puts "=" * 70
    sh "RUBYOPT='#{ENV.fetch("RUBYOPT", "")} --yjit' bundle exec ruby benchmarks/compare_resp3_parser.rb"
  end

  desc "Run async benchmarks (fiber-based async client)"
  task :async do
    puts "\n#{"=" * 70}"
    puts "ASYNC BENCHMARKS"
    puts "=" * 70
    sh "RUBYOPT='#{ENV.fetch("RUBYOPT", "")} --yjit' bundle exec ruby benchmarks/compare_async.rb"
  end

  desc "Compare redis-ruby vs hiredis directly"
  task :hiredis do
    puts "\n#{"=" * 70}"
    puts "HIREDIS COMPARISON BENCHMARKS"
    puts "=" * 70
    sh "RUBYOPT='#{ENV.fetch("RUBYOPT", "")} --yjit' bundle exec ruby benchmarks/compare_vs_hiredis.rb"
  end

  desc "Verify performance gates from CLAUDE.md (CI/CD compatible)"
  task :gates do
    puts "\n#{"=" * 70}"
    puts "PERFORMANCE GATE VERIFICATION"
    puts "Gates from CLAUDE.md:"
    puts "  - Single GET/SET: 1.3x faster than redis-rb"
    puts "  - Pipeline (10 cmds): 1.5x faster"
    puts "  - Pipeline (100 cmds): 2x faster"
    puts "  - Connection setup: Equal or faster"
    puts "=" * 70
    sh "RUBYOPT='#{ENV.fetch("RUBYOPT", "")} --yjit' bundle exec ruby benchmarks/verify_gates.rb"
  end

  desc "Run CPU profiler (StackProf) and generate flamegraph data"
  task :profile_cpu do
    puts "\n#{"=" * 70}"
    puts "CPU PROFILING (StackProf)"
    puts "=" * 70
    sh "RUBYOPT='#{ENV.fetch("RUBYOPT", "")} --yjit' bundle exec ruby benchmarks/profile_hotspots.rb stackprof"
    puts "\nProfile saved to tmp/stackprof_*.json"
    puts "View with: bundle exec stackprof --flamegraph tmp/stackprof_*.json > tmp/flamegraph.html"
  end

  desc "Run memory profiler and show allocation sites"
  task :profile_memory do
    puts "\n#{"=" * 70}"
    puts "MEMORY PROFILING"
    puts "=" * 70
    sh "bundle exec ruby benchmarks/profile_hotspots.rb memory"
    puts "\nProfile saved to tmp/memory_profile.txt"
  end

  desc "Run modern profiler (Vernier) with YJIT awareness"
  task :profile_vernier do
    puts "\n#{"=" * 70}"
    puts "VERNIER PROFILING (YJIT-aware)"
    puts "=" * 70
    sh "RUBYOPT='#{ENV.fetch("RUBYOPT", "")} --yjit' bundle exec ruby benchmarks/profile_hotspots.rb vernier"
    puts "\nProfile saved to tmp/vernier_*.json"
    puts "View at: https://vernier.prof/ or with: vernier view tmp/vernier_*.json"
  end

  desc "Generate JSON benchmark report"
  task :report_json do
    puts "\n#{"=" * 70}"
    puts "GENERATING JSON BENCHMARK REPORT"
    puts "=" * 70
    sh "RUBYOPT='#{ENV.fetch("RUBYOPT", "")} --yjit' bundle exec ruby benchmarks/generate_report.rb json"
    puts "\nReport saved to tmp/benchmark_report.json"
  end

  desc "Generate HTML benchmark report with charts"
  task :report_html do
    puts "\n#{"=" * 70}"
    puts "GENERATING HTML BENCHMARK REPORT"
    puts "=" * 70
    sh "RUBYOPT='#{ENV.fetch("RUBYOPT", "")} --yjit' bundle exec ruby benchmarks/generate_report.rb html"
    puts "\nReport saved to tmp/benchmark_report.html"
  end

  desc "Generate full benchmark report (JSON + HTML)"
  task report: %i[report_json report_html]

  desc "Quick benchmark (fast feedback, reduced iterations)"
  task :quick do
    puts "\n#{"=" * 70}"
    puts "QUICK BENCHMARK (reduced warmup/iterations for fast feedback)"
    puts "=" * 70
    ENV["BENCHMARK_QUICK"] = "1"
    sh "RUBYOPT='#{ENV.fetch("RUBYOPT", "")} --yjit' bundle exec ruby benchmarks/compare_basic.rb"
  end

  desc "Run with YJIT explicitly enabled"
  task :yjit do
    puts "\n#{"=" * 70}"
    puts "YJIT-ENABLED BENCHMARKS"
    puts "=" * 70
    sh "RUBYOPT='--yjit' bundle exec ruby benchmarks/compare_comprehensive.rb"
  end

  desc "Run without YJIT (comparison baseline)"
  task :no_yjit do
    puts "\n#{"=" * 70}"
    puts "NON-YJIT BENCHMARKS (baseline comparison)"
    puts "=" * 70
    sh "RUBYOPT='--disable-yjit' bundle exec ruby benchmarks/compare_comprehensive.rb"
  end

  desc "Compare YJIT vs non-YJIT performance"
  task :yjit_comparison do
    puts "\n#{"=" * 70}"
    puts "YJIT vs NON-YJIT COMPARISON"
    puts "=" * 70
    puts "\n--- Running WITHOUT YJIT ---"
    sh "RUBYOPT='--disable-yjit' bundle exec ruby benchmarks/compare_basic.rb 2>&1 | tee tmp/benchmark_no_yjit.txt"
    puts "\n--- Running WITH YJIT ---"
    sh "RUBYOPT='--yjit' bundle exec ruby benchmarks/compare_basic.rb 2>&1 | tee tmp/benchmark_yjit.txt"
    puts "\nResults saved to tmp/benchmark_no_yjit.txt and tmp/benchmark_yjit.txt"
  end
end

desc "Run benchmarks (alias for benchmark:all)"
task benchmark: "benchmark:all"
