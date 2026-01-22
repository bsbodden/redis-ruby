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

desc "Generate YARD documentation"
task :doc do
  sh "yard doc"
end

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
