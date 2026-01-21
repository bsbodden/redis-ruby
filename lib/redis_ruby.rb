# frozen_string_literal: true

require_relative "redis_ruby/version"

module RedisRuby
  class Error < StandardError; end
  class ConnectionError < Error; end
  class CommandError < Error; end
  class TimeoutError < Error; end

  # Sentinel-specific errors
  class SentinelError < Error; end
  class MasterNotFoundError < SentinelError; end
  class ReplicaNotFoundError < SentinelError; end
  class FailoverError < SentinelError; end
  class ReadOnlyError < CommandError; end

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

    # Create a new pooled Redis client connection
    #
    # Thread-safe client with connection pooling. Each command checks out
    # a connection from the pool, executes, and returns it.
    #
    # @param url [String] Redis URL (redis://host:port/db)
    # @param pool [Hash] Pool options (:size, :timeout)
    # @param options [Hash] Connection options
    # @return [RedisRuby::PooledClient]
    # @example
    #   client = RedisRuby.pooled(url: "redis://localhost:6379", pool: { size: 10 })
    #   client.set("key", "value")
    def pooled(url: nil, **)
      PooledClient.new(url: url, **)
    end

    # Create a new async pooled Redis client
    #
    # Fiber-aware client with async-pool for maximum concurrency.
    # Use inside Async blocks for non-blocking operations with pooling.
    #
    # Uses state-of-the-art async-pool gem by Samuel Williams (socketry).
    #
    # @param url [String] Redis URL (redis://host:port/db)
    # @param pool [Hash] Pool options (:limit)
    # @param options [Hash] Connection options
    # @return [RedisRuby::AsyncPooledClient]
    # @example
    #   require "async"
    #   Async do
    #     client = RedisRuby.async_pooled(pool: { limit: 10 })
    #     # 100 concurrent operations with 10 connections
    #     tasks = 100.times.map { |i| task.async { client.get("key:#{i}") } }
    #   end
    def async_pooled(url: nil, **)
      AsyncPooledClient.new(url: url, **)
    end

    # Create a Sentinel-backed Redis client
    #
    # Automatically discovers and connects to the Redis master/replica
    # through Sentinel servers. Handles automatic failover.
    #
    # @param sentinels [Array<Hash>] List of Sentinel servers with :host and :port
    # @param service_name [String] Name of the monitored master
    # @param role [Symbol] :master or :replica (defaults to :master)
    # @param options [Hash] Additional connection options
    # @return [RedisRuby::SentinelClient]
    # @example
    #   client = RedisRuby.sentinel(
    #     sentinels: [{ host: "sentinel1", port: 26379 }],
    #     service_name: "mymaster"
    #   )
    #   client.set("key", "value")
    def sentinel(sentinels:, service_name:, role: :master, **)
      SentinelClient.new(sentinels: sentinels, service_name: service_name, role: role, **)
    end
  end
end

# Protocol layer
require_relative "redis_ruby/protocol/resp3_encoder"
require_relative "redis_ruby/protocol/buffered_io"
require_relative "redis_ruby/protocol/resp3_decoder"

# Connection layer
require_relative "redis_ruby/connection/tcp"
require_relative "redis_ruby/connection/ssl"
require_relative "redis_ruby/connection/unix"
require_relative "redis_ruby/connection/pool"
require_relative "redis_ruby/connection/async_pool"

# Sentinel support
require_relative "redis_ruby/sentinel_manager"

# Commands layer (shared by sync/async clients)
require_relative "redis_ruby/commands/strings"
require_relative "redis_ruby/commands/keys"
require_relative "redis_ruby/commands/hashes"
require_relative "redis_ruby/commands/lists"
require_relative "redis_ruby/commands/sets"
require_relative "redis_ruby/commands/sorted_sets"
require_relative "redis_ruby/commands/geo"
require_relative "redis_ruby/commands/hyperloglog"
require_relative "redis_ruby/commands/bitmap"
require_relative "redis_ruby/commands/scripting"
require_relative "redis_ruby/commands/streams"
require_relative "redis_ruby/commands/json"
require_relative "redis_ruby/commands/search"
require_relative "redis_ruby/commands/probabilistic"
require_relative "redis_ruby/commands/time_series"
require_relative "redis_ruby/commands/vector_set"
require_relative "redis_ruby/commands/sentinel"
require_relative "redis_ruby/commands/pubsub"

# Client layer
require_relative "redis_ruby/pipeline"
require_relative "redis_ruby/transaction"
require_relative "redis_ruby/client"
require_relative "redis_ruby/async_client"
require_relative "redis_ruby/pooled_client"
require_relative "redis_ruby/async_pooled_client"
require_relative "redis_ruby/sentinel_client"
