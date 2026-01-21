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
end

desc "Generate YARD documentation"
task :doc do
  sh "yard doc"
end

desc "Start a console with the library loaded"
task :console do
  sh "bundle exec irb -r redis_ruby"
end
