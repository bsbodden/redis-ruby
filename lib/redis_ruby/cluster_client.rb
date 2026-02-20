# frozen_string_literal: true

require "uri"
require_relative "cluster_topology"

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

      if block_given?
        @watched_connection = conn
        begin
          yield self
        ensure
          conn.call("UNWATCH")
          @watched_connection = nil
        end
      else
        @watched_connection = conn
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

    # Verify all keys hash to the same slot
    def verify_same_slot!(keys)
      return if keys.size <= 1

      first_slot = key_slot(keys[0].to_s)
      keys[1..].each do |key|
        slot = key_slot(key.to_s)
        next if slot == first_slot

        raise CrossSlotError,
              "CROSSSLOT All watched keys must hash to the same slot (use hash tags)"
      end
    end

    # Select the appropriate node based on read/write and read_from config
    def select_node_for_operation(node_info, for_read)
      return node_info[:master] unless for_read && use_replicas?(node_info)

      select_replica_node(node_info)
    end

    # Check if replicas should be used for this operation
    def use_replicas?(node_info)
      @read_from != :master && node_info[:replicas]&.any?
    end

    # Select a replica node based on read_from policy
    def select_replica_node(node_info)
      case @read_from
      when :replica
        node_info[:replicas].sample
      when :replica_preferred
        node_info[:replicas].sample || node_info[:master]
      else
        node_info[:master]
      end
    end

    # Extract the key from a command
    def extract_key(command, args)
      cmd = command.to_s.upcase
      return nil if NO_KEY_COMMANDS.include?(cmd)

      args[0] if args.any?
    end

    # Commands with no key
    NO_KEY_COMMANDS = %w[PING INFO DBSIZE TIME CLUSTER].freeze # rubocop:disable Lint/UselessConstantScoping

    # Execute command with retry and redirection handling
    def execute_with_retry(command, args, slot, redirections: 0)
      raise RR::Error, "Too many redirections" if redirections >= MAX_REDIRECTIONS

      retries = 0

      begin
        node_addr = determine_target_node(command, slot)
        raise RR::ConnectionError, "No node available for slot #{slot}" unless node_addr

        conn = get_connection(node_addr)
        result = conn.call(command, *args)
        handle_result_or_error(result, command, args, slot, redirections)
      rescue ConnectionError
        retries += 1
        retry if retry_with_backoff?(retries)
        raise
      end
    end

    # Determine which node to send command to
    def determine_target_node(command, slot)
      slot ? node_for_slot(slot, for_read: read_command?(command)) : random_master
    end

    # Handle command result or error
    def handle_result_or_error(result, command, args, slot, redirections)
      result.is_a?(CommandError) ? handle_command_error(result, command, args, slot, redirections) : result
    end

    # Check if we should retry with exponential backoff
    def retry_with_backoff?(retries)
      return false if retries > @retry_count

      sleep(0.1 * (2**(retries - 1))) if retries > 1
      refresh_slots
      true
    end

    # Handle command errors including redirections
    # rubocop:disable Metrics/CyclomaticComplexity
    def handle_command_error(error, command, args, slot, redirections)
      message = error.message

      if message.start_with?("MOVED")
        handle_moved_error(message, command, args, redirections)
      elsif message.start_with?("ASK")
        handle_ask_error(message, command, args)
      elsif message.start_with?("CLUSTERDOWN")
        raise ClusterDownError, message
      elsif message.start_with?("CROSSSLOT")
        raise CrossSlotError, message
      elsif message.start_with?("TRYAGAIN")
        handle_tryagain_error(command, args, slot, redirections)
      else
        raise error
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity

    # Handle MOVED redirection (topology changed)
    def handle_moved_error(message, command, args, redirections)
      _, new_slot, = message.split
      refresh_slots
      execute_with_retry(command, args, new_slot.to_i, redirections: redirections + 1)
    end

    # Handle ASK redirection (temporary migration)
    def handle_ask_error(message, command, args)
      _, _new_slot, new_addr = message.split
      host, port = new_addr.split(":")
      translated_host = translate_host(host)

      conn = get_connection("#{translated_host}:#{port}")
      conn.call("ASKING")
      result = conn.call(command, *args)
      raise result if result.is_a?(CommandError)

      result
    end

    # Handle TRYAGAIN error (retry after brief delay)
    def handle_tryagain_error(command, args, slot, redirections)
      raise TryAgainError, "TRYAGAIN after #{MAX_REDIRECTIONS} attempts" if redirections >= MAX_REDIRECTIONS

      sleep(0.1)
      execute_with_retry(command, args, slot, redirections: redirections + 1)
    rescue RR::Error => e
      raise TryAgainError, e.message if e.message.include?("Too many redirections")

      raise
    end

    # Check if command is a read command
    def read_command?(command)
      READ_COMMANDS.include?(command.to_s.upcase)
    end

    # List of read-only commands
    # rubocop:disable Lint/UselessConstantScoping
    READ_COMMANDS = %w[
      GET MGET GETEX GETDEL STRLEN GETRANGE GETBIT
      HGET HMGET HGETALL HLEN HKEYS HVALS HEXISTS HSCAN HRANDFIELD
      LRANGE LINDEX LLEN LPOS
      SMEMBERS SISMEMBER SMISMEMBER SCARD SRANDMEMBER SSCAN SINTER SUNION SDIFF
      ZRANGE ZREVRANGE ZRANGEBYSCORE ZREVRANGEBYSCORE ZRANK ZREVRANK
      ZSCORE ZCARD ZCOUNT ZLEXCOUNT ZRANGEBYLEX ZREVRANGEBYLEX ZSCAN ZRANDMEMBER
      EXISTS TYPE TTL PTTL EXPIRETIME PEXPIRETIME OBJECT SCAN RANDOMKEY KEYS
      PFCOUNT
      XLEN XRANGE XREVRANGE XREAD XINFO XPENDING
      BITCOUNT BITPOS GETBIT
      GEORADIUS GEORADIUSBYMEMBER GEOPOS GEODIST GEOHASH GEOSEARCH
    ].freeze
    # rubocop:enable Lint/UselessConstantScoping
  end
end
