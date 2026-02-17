# frozen_string_literal: true

require_relative "redis_ruby/version"

module RR
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

  # Cluster-specific errors
  class ClusterError < Error; end
  class ClusterDownError < ClusterError; end
  class MovedError < ClusterError; end
  class AskError < ClusterError; end

  class << self
    # Create a new synchronous Redis client connection
    #
    # @param url [String, nil] Redis URL (redis://host:port/db)
    # @param kwargs [Hash] Connection options (host, port, db, password, etc.)
    # @return [RR::Client]
    def new(url: nil, **kwargs)
      Client.new(url: url, **kwargs)
    end

    # Create a new asynchronous Redis client connection
    #
    # When used inside an `Async` block, I/O operations automatically
    # yield to the fiber scheduler, enabling concurrent execution.
    #
    # @param url [String, nil] Redis URL (redis://host:port/db)
    # @param kwargs [Hash] Connection options (host, port, db, password, etc.)
    # @return [RR::AsyncClient]
    # @example
    #   require "async"
    #   Async do
    #     client = RR.async(url: "redis://localhost:6379")
    #     client.set("key", "value")
    #   end
    def async(url: nil, **kwargs)
      AsyncClient.new(url: url, **kwargs)
    end

    # Create a new pooled Redis client connection
    #
    # Thread-safe client with connection pooling. Each command checks out
    # a connection from the pool, executes, and returns it.
    #
    # @param url [String, nil] Redis URL (redis://host:port/db)
    # @param kwargs [Hash] Connection and pool options (pool hash with size and timeout, host, port, etc.)
    # @return [RR::PooledClient]
    # @example
    #   client = RR.pooled(url: "redis://localhost:6379", pool: { size: 10 })
    #   client.set("key", "value")
    def pooled(url: nil, **kwargs)
      PooledClient.new(url: url, **kwargs)
    end

    # Create a new async pooled Redis client
    #
    # Fiber-aware client with async-pool for maximum concurrency.
    # Use inside Async blocks for non-blocking operations with pooling.
    #
    # Uses state-of-the-art async-pool gem by Samuel Williams (socketry).
    #
    # @param url [String, nil] Redis URL (redis://host:port/db)
    # @param kwargs [Hash] Connection and pool options (pool hash with limit, host, port, etc.)
    # @return [RR::AsyncPooledClient]
    # @example
    #   require "async"
    #   Async do
    #     client = RR.async_pooled(pool: { limit: 10 })
    #     # 100 concurrent operations with 10 connections
    #     tasks = 100.times.map { |i| task.async { client.get("key:#{i}") } }
    #   end
    def async_pooled(url: nil, **kwargs)
      AsyncPooledClient.new(url: url, **kwargs)
    end

    # Create a Sentinel-backed Redis client
    #
    # Automatically discovers and connects to the Redis master/replica
    # through Sentinel servers. Handles automatic failover.
    #
    # @param sentinels [Array<Hash>] List of Sentinel servers with :host and :port
    # @param service_name [String] Name of the monitored master
    # @param role [Symbol] :master or :replica (defaults to :master)
    # @param kwargs [Hash] Additional connection options (password, db, etc.)
    # @return [RR::SentinelClient]
    # @example
    #   client = RR.sentinel(
    #     sentinels: [{ host: "sentinel1", port: 26379 }],
    #     service_name: "mymaster"
    #   )
    #   client.set("key", "value")
    def sentinel(sentinels:, service_name:, role: :master, **kwargs)
      SentinelClient.new(sentinels: sentinels, service_name: service_name, role: role, **kwargs)
    end

    # Create a Redis Cluster client
    #
    # Automatically handles sharding, failover, and routing across
    # a Redis Cluster deployment.
    #
    # @param nodes [Array<String, Hash>] Seed nodes (URLs or hashes with host and port keys)
    # @param kwargs [Hash] Additional connection options (password, read_from, etc.)
    # @return [RR::ClusterClient]
    # @example
    #   client = RR.cluster(
    #     nodes: ["redis://node1:6379", "redis://node2:6379", "redis://node3:6379"]
    #   )
    #   client.set("key", "value")
    #
    # @example Read from replicas
    #   client = RR.cluster(
    #     nodes: ["redis://node1:6379"],
    #     read_from: :replica_preferred
    #   )
    def cluster(nodes:, **kwargs)
      ClusterClient.new(nodes: nodes, **kwargs)
    end

    # Create a Redis Enterprise Discovery Service client
    #
    # Automatically discovers and connects to Redis Enterprise databases
    # through the Discovery Service running on port 8001.
    #
    # @param nodes [Array<Hash>] Discovery service nodes with :host and optional :port
    # @param database_name [String] Name of the database to discover
    # @param kwargs [Hash] Additional connection options (internal, password, db, etc.)
    # @return [RR::DiscoveryServiceClient]
    # @example
    #   client = RR.discovery(
    #     nodes: [
    #       { host: "node1.redis.example.com", port: 8001 },
    #       { host: "node2.redis.example.com", port: 8001 }
    #     ],
    #     database_name: "my-database"
    #   )
    #   client.set("key", "value")
    #
    # @example Internal endpoint
    #   client = RR.discovery(
    #     nodes: [{ host: "node1.redis.example.com" }],
    #     database_name: "my-database",
    #     internal: true
    #   )
    def discovery(nodes:, database_name:, **kwargs)
      DiscoveryServiceClient.new(nodes: nodes, database_name: database_name, **kwargs)
    end

    # Create a DNS-aware Redis client with load balancing
    #
    # Resolves a hostname to multiple IP addresses and uses a load balancing
    # strategy (round-robin or random) to distribute connections.
    #
    # @param hostname [String] Hostname to resolve (must resolve to one or more IPs)
    # @param kwargs [Hash] Additional connection options (port, dns_strategy, password, etc.)
    # @return [RR::DNSClient]
    # @example
    #   client = RR.dns(
    #     hostname: "redis.example.com",
    #     port: 6379
    #   )
    #   client.set("key", "value")
    #
    # @example With custom strategy
    #   client = RR.dns(
    #     hostname: "redis.example.com",
    #     port: 6379,
    #     dns_strategy: :random  # or :round_robin (default)
    #   )
    def dns(hostname:, **kwargs)
      DNSClient.new(hostname: hostname, **kwargs)
    end

    # Create an Active-Active Redis client for multi-region geo-distributed databases
    #
    # Connects to Redis Enterprise Active-Active databases with automatic failover
    # across multiple geographic regions. Active-Active databases use CRDTs
    # (Conflict-free Replicated Data Types) for automatic conflict resolution.
    #
    # @param regions [Array<Hash>] Array of region configurations, each with :host and :port
    # @param kwargs [Hash] Additional connection options (preferred_region, password, ssl, etc.)
    # @return [RR::ActiveActiveClient]
    # @example
    #   client = RR.active_active(
    #     regions: [
    #       { host: "redis-us-east.example.com", port: 6379 },
    #       { host: "redis-eu-west.example.com", port: 6379 },
    #       { host: "redis-ap-south.example.com", port: 6379 }
    #     ]
    #   )
    #   client.set("key", "value")
    #
    # @example With preferred region and authentication
    #   client = RR.active_active(
    #     regions: [
    #       { host: "redis-us.example.com", port: 6380 },
    #       { host: "redis-eu.example.com", port: 6380 }
    #     ],
    #     preferred_region: 0,  # Start with first region
    #     password: "secret",
    #     ssl: true
    #   )
    def active_active(regions:, **kwargs)
      ActiveActiveClient.new(regions: regions, **kwargs)
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

# Utilities
require_relative "redis_ruby/utils/url_parser"
require_relative "redis_ruby/utils/yjit_monitor"
require_relative "redis_ruby/retry"
require_relative "redis_ruby/instrumentation"
require_relative "redis_ruby/circuit_breaker"
require_relative "redis_ruby/failure_detector"
require_relative "redis_ruby/event_dispatcher"
require_relative "redis_ruby/callback_error_handler"
require_relative "redis_ruby/async_callback_executor"
require_relative "redis_ruby/health_check"
require_relative "redis_ruby/discovery_service"
require_relative "redis_ruby/dns_resolver"

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
require_relative "redis_ruby/commands/functions"
require_relative "redis_ruby/commands/acl"
require_relative "redis_ruby/commands/server"
require_relative "redis_ruby/commands/cluster"

# Search utilities
require_relative "redis_ruby/search/query"

# Client layer
require_relative "redis_ruby/script"
require_relative "redis_ruby/pipeline"
require_relative "redis_ruby/transaction"
require_relative "redis_ruby/lock"
require_relative "redis_ruby/cache"
require_relative "redis_ruby/callbacks"
require_relative "redis_ruby/subscriber"
require_relative "redis_ruby/client"
require_relative "redis_ruby/async_client"
require_relative "redis_ruby/pooled_client"
require_relative "redis_ruby/async_pooled_client"
require_relative "redis_ruby/sentinel_client"
require_relative "redis_ruby/cluster_client"
require_relative "redis_ruby/discovery_service_client"
require_relative "redis_ruby/dns_client"
require_relative "redis_ruby/active_active_client"
