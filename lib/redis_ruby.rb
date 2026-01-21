# frozen_string_literal: true

require_relative "redis_ruby/version"

module RedisRuby
  class Error < StandardError; end
  class ConnectionError < Error; end
  class CommandError < Error; end
  class TimeoutError < Error; end

  class << self
    # Create a new Redis client connection
    #
    # @param url [String] Redis URL (redis://host:port/db)
    # @param options [Hash] Connection options
    # @return [RedisRuby::Client]
    def new(url: nil, **options)
      Client.new(url: url, **options)
    end
  end
end

# Autoload components
require_relative "redis_ruby/protocol/resp3_encoder"
require_relative "redis_ruby/client"
