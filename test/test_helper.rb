# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/test/"
  enable_coverage :branch
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "redis_ruby"

require "minitest/autorun"
require "minitest/reporters"
require "mocha/minitest"

Minitest::Reporters.use! [Minitest::Reporters::DefaultReporter.new(color: true)]

# Suppress async-pool warnings about mutex unlocking
# These are harmless warnings from the async-pool gem's internal cleanup
begin
  require "async"
  require "console"
  Console.logger.level = :error
rescue LoadError
  # Async not available, skip
end

# TestContainers support
require "testcontainers"
require "testcontainers/redis"

module TestContainerSupport
  class << self
    attr_reader :redis_container, :redis_url

    def start!
      return if @started

      puts "Starting Redis container..."
      # Use Redis 8 with all modules (JSON, Search, TimeSeries, Bloom, Vector Sets)
      @redis_container = Testcontainers::DockerContainer.new("redis:8")
      @redis_container.with_exposed_port(6379)

      # Connect to devcontainer network for connectivity within the devcontainer
      devcontainer_network = ENV.fetch("COMPOSE_PROJECT_NAME", nil)
      if devcontainer_network
        network_name = "#{devcontainer_network}_redis-rb-dev"
        begin
          @redis_container.with_network(network_name)
        rescue StandardError
          # Network might not exist outside devcontainer
        end
      end

      @redis_container.start
      @redis_container.wait_for_tcp_port(6379, timeout: 60)

      @redis_url = "redis://#{@redis_container.host}:#{@redis_container.mapped_port(6379)}"
      puts "Redis container started at #{@redis_url}"
      @started = true
    end

    def stop!
      return unless @started

      puts "Stopping Redis container..."
      @redis_container&.stop
      @started = false
    end

    def started?
      @started
    end
  end
end

# Base test class with TestContainers support
class RedisRubyTestCase < Minitest::Test
  class << self
    def use_testcontainers!
      @use_testcontainers = true
    end

    def use_testcontainers?
      @use_testcontainers
    end
  end

  def setup
    if self.class.use_testcontainers? && !ENV["REDIS_URL"]
      TestContainerSupport.start!
      @redis_url = TestContainerSupport.redis_url
    else
      @redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379")
    end

    @redis = RR::Client.new(url: @redis_url, reconnect_attempts: 3)
  end

  def teardown
    @redis&.close
  end

  attr_reader :redis
end

# Clean up containers at exit
Minitest.after_run do
  TestContainerSupport.stop! if TestContainerSupport.started?
end
