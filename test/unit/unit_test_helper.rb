# frozen_string_literal: true

# Lightweight test helper for unit tests - no TestContainers needed
# Use this for fast, isolated tests that don't require a real Redis server

require "simplecov"
SimpleCov.start do
  add_filter "/test/"
  enable_coverage :branch
end

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "redis_ruby"

require "minitest/autorun"
require "minitest/reporters"
require "mocha/minitest"

Minitest::Reporters.use! [Minitest::Reporters::DefaultReporter.new(color: true)]
