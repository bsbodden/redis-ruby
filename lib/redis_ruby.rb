# frozen_string_literal: true

require_relative "redis_ruby/version"

module RedisRuby
  class Error < StandardError; end
  class ConnectionError < Error; end
  class CommandError < Error; end
  class TimeoutError < Error; end

  class << self
    # Create a new synchronous Redis client connection
    #
    # @param url [String] Redis URL (redis://host:port/db)
    # @param options [Hash] Connection options
    # @return [RedisRuby::Client]
    def new(url: nil, **)
      Client.new(url: url, **)
    end

    # Create a new asynchronous Redis client connection
    #
    # When used inside an `Async` block, I/O operations automatically
    # yield to the fiber scheduler, enabling concurrent execution.
    #
    # @param url [String] Redis URL (redis://host:port/db)
    # @param options [Hash] Connection options
    # @return [RedisRuby::AsyncClient]
    # @example
    #   require "async"
    #   Async do
    #     client = RedisRuby.async(url: "redis://localhost:6379")
    #     client.set("key", "value")
    #   end
    def async(url: nil, **)
      AsyncClient.new(url: url, **)
    end
  end
end

# Protocol layer
require_relative "redis_ruby/protocol/resp3_encoder"
require_relative "redis_ruby/protocol/resp3_decoder"

# Connection layer
require_relative "redis_ruby/connection/tcp"

# Commands layer (shared by sync/async clients)
require_relative "redis_ruby/commands/strings"
require_relative "redis_ruby/commands/keys"
require_relative "redis_ruby/commands/hashes"
require_relative "redis_ruby/commands/lists"
require_relative "redis_ruby/commands/sets"
require_relative "redis_ruby/commands/sorted_sets"

# Client layer
require_relative "redis_ruby/pipeline"
require_relative "redis_ruby/transaction"
require_relative "redis_ruby/client"
require_relative "redis_ruby/async_client"
