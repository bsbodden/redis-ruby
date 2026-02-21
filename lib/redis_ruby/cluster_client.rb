# frozen_string_literal: true

require "uri"
require_relative "cluster_topology"
require_relative "concerns/cluster_routing"

module RR
  # Redis Cluster client
  #
  # Provides automatic sharding, failover, and routing for Redis Cluster.
  # Handles MOVED and ASK redirections transparently.
  #
  # @example Basic usage
  #   client = RR::ClusterClient.new(
  #     nodes: ["redis://node1:6379", "redis://node2:6379", "redis://node3:6379"]
  #   )
  #   client.set("key", "value")  # Automatically routes to correct node
  #   client.get("key")
  #
  # @example With read from replicas
  #   client = RR::ClusterClient.new(
  #     nodes: ["redis://node1:6379"],
  #     read_from: :replicas
  #   )
  #
  class ClusterClient
    include Commands::Strings
    include Commands::Keys
    include Commands::Hashes
    include Commands::Lists
    include Commands::Sets
    include Commands::SortedSets
    include Commands::Geo
    include Commands::HyperLogLog
    include Commands::Bitmap
    include Commands::Scripting
    include Commands::JSON
    include Commands::Search
    include Commands::Probabilistic
    include Commands::TimeSeries
    include Commands::VectorSet
    include Commands::Streams
    include Commands::PubSub
    include Commands::Cluster
    include ClusterTopology
    include Concerns::ClusterRouting

    attr_reader :nodes, :timeout, :read_from

    DEFAULT_TIMEOUT = 5.0
    MAX_REDIRECTIONS = 5

    # Initialize a new Cluster client
    #
    # @param nodes [Array<String, Hash>] Seed nodes (URLs or hashes with host and port)
    # @param password [String, nil] Password for all nodes
    # @param timeout [Float] Connection timeout in seconds
    # @param read_from [Symbol] :master (default), :replica, :replica_preferred
    # @param retry_count [Integer] Number of retries on failure
    # @param host_translation [Hash] Map announced IPs to reachable IPs
    def initialize(nodes:, password: nil, timeout: DEFAULT_TIMEOUT,
                   read_from: :master, retry_count: 3, host_translation: nil)
      @seed_nodes = normalize_nodes(nodes)
      @password = password
      @timeout = timeout
      @read_from = read_from
      @retry_count = retry_count
      @host_translation = host_translation || {}

      @slots = Array.new(HASH_SLOTS) # slot -> node mapping
      @nodes = {}                      # "host:port" -> connection
      @masters = []                    # list of master addresses
      @replicas = {}                   # master_id -> [replica addresses]

      @mutex = Mutex.new

      refresh_slots
    end

    # Execute a Redis command
    #
    # Automatically routes to the correct node based on key.
    # Handles MOVED and ASK redirections.
    #
    # @param command [String] Command name
    # @param args [Array] Command arguments
    # @return [Object] Command result
    def call(command, *args)
      key = extract_key(command, args)
      slot = key ? key_slot(key) : nil

      execute_with_retry(command, args, slot)
    end

    # Optimized call methods for fixed argument counts
    # @api private
    def call_1arg(command, arg)
      call(command, arg)
    end

    # @api private
    def call_2args(command, arg1, arg2)
      call(command, arg1, arg2)
    end

    # @api private
    def call_3args(command, arg1, arg2, arg3)
      call(command, arg1, arg2, arg3)
    end

    # Close all connections
    def close
      @mutex.synchronize do
        @nodes.each_value(&:close)
        @nodes.clear
      end
    end

    alias disconnect close
    alias quit close

    # Refresh cluster slot mapping
    # @return [void]
    def refresh_slots
      @mutex.synchronize { refresh_slots_internal }
    end

    # Calculate hash slot for a key
    # @param key [String] Redis key
    # @return [Integer] Hash slot (0-16383)
    def key_slot(key)
      tag_key = extract_hash_tag(key) || key
      crc16(tag_key) % HASH_SLOTS
    end

    # Get the node responsible for a slot
    # @param slot [Integer] Hash slot
    # @param for_read [Boolean] Whether this is for a read operation
    # @return [String] Node address "host:port"
    def node_for_slot(slot, for_read: false)
      @mutex.synchronize do
        node_info = @slots[slot]
        return nil unless node_info

        select_node_for_operation(node_info, for_read)
      end
    end

    # Check if cluster is healthy
    # @return [Boolean]
    def cluster_healthy?
      info = cluster_info_on_any_node
      info && info["cluster_state"] == "ok"
    end

    # Get number of known nodes
    # @return [Integer]
    def node_count
      @mutex.synchronize { @nodes.size }
    end

    # Watch keys for optimistic locking in cluster mode
    #
    # All watched keys must hash to the same slot. WATCH and UNWATCH
    # are sent to the node owning that slot (redis-rb issue #955).
    #
    # @param keys [Array<String>] Keys to watch (must be in same slot)
    # @yield [self] Block to execute while keys are watched
    # @return [Object] Block result, or "OK" without block
    def watch(*keys)
      raise ArgumentError, "WATCH requires at least one key" if keys.empty?

      verify_same_slot!(keys)
      slot = key_slot(keys[0].to_s)
      node_addr = node_for_slot(slot)
      conn = get_connection(node_addr)

      result = conn.call("WATCH", *keys)
      raise result if result.is_a?(CommandError)

      @watched_connection = conn
      if block_given?
        begin
          yield self
        ensure
          conn.call("UNWATCH")
          @watched_connection = nil
        end
      else
        result
      end
    end

    # Cancel WATCH — sent to the same node that received WATCH
    #
    # @return [String] "OK"
    def unwatch
      conn = @watched_connection
      raise RR::Error, "UNWATCH called without a preceding WATCH" unless conn

      result = conn.call("UNWATCH")
      @watched_connection = nil
      raise result if result.is_a?(CommandError)

      result
    end

    # Execute a transaction (MULTI/EXEC) on a specific node
    #
    # All commands in the block must target the same slot.
    #
    # @yield [tx] Transaction object for queuing commands
    # @return [Array, nil] Results or nil if aborted
    def multi
      conn = @watched_connection || random_master_connection
      tx = Transaction.new(conn)
      yield tx
      results = tx.execute
      @watched_connection = nil
      return nil if results.nil?
      raise results if results.is_a?(CommandError)

      results.each { |r| raise r if r.is_a?(CommandError) }
      results
    end

    private

    # Get a connection to a random master
    def random_master_connection
      addr = random_master
      raise ConnectionError, "No master nodes available" unless addr

      get_connection(addr)
    end
  end
end
