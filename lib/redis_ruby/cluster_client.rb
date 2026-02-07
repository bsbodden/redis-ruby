# frozen_string_literal: true

require "uri"

module RedisRuby
  # Redis Cluster client
  #
  # Provides automatic sharding, failover, and routing for Redis Cluster.
  # Handles MOVED and ASK redirections transparently.
  #
  # @example Basic usage
  #   client = RedisRuby::ClusterClient.new(
  #     nodes: ["redis://node1:6379", "redis://node2:6379", "redis://node3:6379"]
  #   )
  #   client.set("key", "value")  # Automatically routes to correct node
  #   client.get("key")
  #
  # @example With read from replicas
  #   client = RedisRuby::ClusterClient.new(
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
    include Commands::Streams
    include Commands::Cluster

    # Number of hash slots in Redis Cluster
    HASH_SLOTS = 16_384

    # CRC16 lookup table for hash slot calculation
    CRC16_TABLE = begin
      table = Array.new(256)
      256.times do |i|
        crc = i << 8
        8.times do
          crc = crc.nobits?(0x8000) ? crc << 1 : (crc << 1) ^ 0x1021
        end
        table[i] = crc & 0xFFFF
      end
      table.freeze
    end

    attr_reader :nodes, :timeout, :read_from

    DEFAULT_TIMEOUT = 5.0
    MAX_REDIRECTIONS = 5

    # Initialize a new Cluster client
    #
    # @param nodes [Array<String, Hash>] Seed nodes (URLs or {host:, port:} hashes)
    # @param password [String, nil] Password for all nodes
    # @param timeout [Float] Connection timeout in seconds
    # @param read_from [Symbol] :master (default), :replica, :replica_preferred
    # @param retry_count [Integer] Number of retries on failure
    # @param host_translation [Hash] Map announced IPs to reachable IPs (e.g., {"127.0.0.1" => "192.168.1.1"})
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

      # Initialize cluster topology
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
    # These provide API compatibility with Client; ClusterClient delegates to call()
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
    #
    # @return [void]
    def refresh_slots
      @mutex.synchronize do
        refresh_slots_internal
      end
    end

    # Calculate hash slot for a key
    #
    # @param key [String] Redis key
    # @return [Integer] Hash slot (0-16383)
    def key_slot(key)
      # Extract hash tag if present
      tag_key = extract_hash_tag(key) || key
      crc16(tag_key) % HASH_SLOTS
    end

    # Get the node responsible for a slot
    #
    # @param slot [Integer] Hash slot
    # @param for_read [Boolean] Whether this is for a read operation
    # @return [String] Node address "host:port"
    def node_for_slot(slot, for_read: false)
      @mutex.synchronize do
        node_info = @slots[slot]
        return nil unless node_info

        if for_read && @read_from != :master && node_info[:replicas]&.any?
          case @read_from
          when :replica
            node_info[:replicas].sample
          when :replica_preferred
            node_info[:replicas].sample || node_info[:master]
          else
            node_info[:master]
          end
        else
          node_info[:master]
        end
      end
    end

    # Check if cluster is healthy
    #
    # @return [Boolean]
    def cluster_healthy?
      info = cluster_info_on_any_node
      info && info["cluster_state"] == "ok"
    end

    # Get number of known nodes
    #
    # @return [Integer]
    def node_count
      @mutex.synchronize { @nodes.size }
    end

    private

    # Normalize nodes to [{host:, port:}] format
    def normalize_nodes(nodes)
      nodes.map do |node|
        case node
        when String
          uri = URI.parse(node)
          { host: uri.host || "localhost", port: uri.port || 6379 }
        when Hash
          { host: node[:host] || "localhost", port: node[:port] || 6379 }
        else
          raise ArgumentError, "Invalid node format: #{node.inspect}"
        end
      end
    end

    # Translate host address if translation is configured
    def translate_host(host)
      @host_translation[host] || host
    end

    # Extract hash tag from key (e.g., "foo{bar}baz" -> "bar")
    def extract_hash_tag(key)
      return nil unless key.is_a?(String)

      start_idx = key.index("{")
      return nil unless start_idx

      end_idx = key.index("}", start_idx + 1)
      return nil unless end_idx && end_idx > start_idx + 1

      key[(start_idx + 1)...end_idx]
    end

    # Calculate CRC16 for hash slot
    def crc16(data)
      crc = 0
      data.each_byte do |byte|
        crc = ((crc << 8) ^ CRC16_TABLE[((crc >> 8) ^ byte) & 0xFF]) & 0xFFFF
      end
      crc
    end

    # Extract the key from a command
    def extract_key(command, args)
      cmd = command.to_s.upcase

      # Commands with no key
      return nil if %w[PING INFO DBSIZE TIME CLUSTER].include?(cmd)

      # Commands where key is first argument
      return args[0] if args.any?

      nil
    end

    # Execute command with retry and redirection handling
    def execute_with_retry(command, args, slot, redirections: 0)
      raise RedisRuby::Error, "Too many redirections" if redirections >= MAX_REDIRECTIONS

      retries = 0
      asking = false

      begin
        node_addr = determine_target_node(command, slot)
        raise RedisRuby::ConnectionError, "No node available for slot #{slot}" unless node_addr

        conn = get_connection(node_addr)
        send_asking_if_needed(conn, asking)
        asking = false

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
      if slot
        for_read = read_command?(command)
        node_for_slot(slot, for_read: for_read)
      else
        random_master
      end
    end

    # Send ASKING command if this is an ASK redirect
    def send_asking_if_needed(conn, asking)
      conn.call("ASKING") if asking
    end

    # Handle command result or error
    def handle_result_or_error(result, command, args, slot, redirections)
      if result.is_a?(CommandError)
        handle_command_error(result, command, args, slot, redirections)
      else
        result
      end
    end

    # Check if we should retry with exponential backoff
    def retry_with_backoff?(retries)
      return false if retries > @retry_count

      # Exponential backoff: 0.1s, 0.2s, 0.4s, 0.8s...
      sleep(0.1 * (2**(retries - 1))) if retries > 1
      refresh_slots # Refresh topology and retry
      true
    end

    # Handle command errors including redirections
    def handle_command_error(error, command, args, _slot, redirections)
      message = error.message

      if message.start_with?("MOVED")
        handle_moved_error(message, command, args, redirections)
      elsif message.start_with?("ASK")
        handle_ask_error(message, command, args)
      elsif message.start_with?("CLUSTERDOWN")
        raise RedisRuby::Error, "Cluster is down: #{message}"
      else
        raise error
      end
    end

    # Handle MOVED redirection (topology changed)
    def handle_moved_error(message, command, args, redirections)
      # MOVED <slot> <host>:<port>
      _, new_slot, = message.split
      refresh_slots # Topology changed
      new_slot_int = new_slot.to_i
      execute_with_retry(command, args, new_slot_int, redirections: redirections + 1)
    end

    # Handle ASK redirection (temporary migration)
    def handle_ask_error(message, command, args)
      # ASK <slot> <host>:<port>
      _, _new_slot, new_addr = message.split
      host, port = new_addr.split(":")
      translated_host = translate_host(host)

      # For ASK, we need to send ASKING before the command
      conn = get_connection("#{translated_host}:#{port}")
      conn.call("ASKING")
      result = conn.call(command, *args)
      raise result if result.is_a?(CommandError)

      result
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

    # Get a random master node address
    def random_master
      @mutex.synchronize do
        @masters.sample
      end
    end

    # Get or create connection to a node
    def get_connection(addr)
      @mutex.synchronize do
        @nodes[addr] ||= create_connection(addr)
      end
    end

    # Create a new connection to a node
    def create_connection(addr)
      host, port = addr.split(":")
      conn = Connection::TCP.new(host: host, port: port.to_i, timeout: @timeout)

      # Authenticate if password set
      if @password
        result = conn.call("AUTH", @password)
        raise result if result.is_a?(CommandError)
      end

      conn
    end

    # Refresh cluster slots from any available node
    def refresh_slots_internal
      # Try seed nodes first, then known nodes
      nodes_to_try = @seed_nodes.map { |n| "#{n[:host]}:#{n[:port]}" } + @nodes.keys

      nodes_to_try.uniq.each do |addr|
        conn = get_connection_internal(addr)
        result = conn.call("CLUSTER", "SLOTS")

        next if result.is_a?(CommandError)

        update_slots_from_result(result)
        return # rubocop:disable Lint/NonLocalExitFromIterator
      rescue StandardError
        next
      end

      raise RedisRuby::ConnectionError, "Could not connect to any cluster node"
    end

    # Get connection without mutex (internal use)
    def get_connection_internal(addr)
      @nodes[addr] ||= create_connection(addr)
    end

    # Update slots mapping from CLUSTER SLOTS result
    def update_slots_from_result(slots_data)
      # Clear existing
      @masters.clear
      @replicas.clear

      slots_data.each do |slot_info|
        start_slot, end_slot, master_info, *replica_infos = slot_info

        # Translate host if configured (useful when cluster announces localhost)
        master_host = translate_host(master_info[0])
        master_addr = "#{master_host}:#{master_info[1]}"
        @masters << master_addr unless @masters.include?(master_addr)

        # Parse replica addresses with translation
        replica_addrs = replica_infos.map { |r| "#{translate_host(r[0])}:#{r[1]}" }

        # Update slot mapping
        (start_slot..end_slot).each do |slot|
          @slots[slot] = {
            master: master_addr,
            replicas: replica_addrs,
          }
        end
      end

      @masters.uniq!
    end

    # Get cluster info from any node
    def cluster_info_on_any_node
      addr = random_master || @seed_nodes.first&.then { |n| "#{n[:host]}:#{n[:port]}" }
      return nil unless addr

      conn = get_connection(addr)
      result = conn.call("CLUSTER", "INFO")
      return nil if result.is_a?(CommandError)

      parse_cluster_info_response(result)
    rescue StandardError
      nil
    end

    # Parse CLUSTER INFO response
    def parse_cluster_info_response(info)
      info.split("\r\n").each_with_object({}) do |line, hash|
        key, value = line.split(":")
        next unless key && value

        hash[key] = case value
                    when /^\d+$/
                      value.to_i
                    else
                      value
                    end
      end
    end
  end
end
