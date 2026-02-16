# frozen_string_literal: true

module RR
  # Cluster topology management for ClusterClient
  #
  # Handles slot mapping, node connections, CRC16 hashing,
  # and topology refresh operations.
  #
  # @api private
  module ClusterTopology
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

    private

    # Calculate CRC16 for hash slot
    def crc16(data)
      crc = 0
      data.each_byte do |byte|
        crc = ((crc << 8) ^ CRC16_TABLE[((crc >> 8) ^ byte) & 0xFF]) & 0xFFFF
      end
      crc
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

    # Translate host address if translation is configured
    def translate_host(host)
      @host_translation[host] || host
    end

    # Normalize nodes to [{host:, port:}] format
    def normalize_nodes(nodes)
      nodes.map { |node| normalize_single_node(node) }
    end

    # Normalize a single node to {host:, port:} format
    def normalize_single_node(node)
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

    # Get a random master node address
    def random_master
      @mutex.synchronize { @masters.sample }
    end

    # Get or create connection to a node
    def get_connection(addr)
      @mutex.synchronize do
        @nodes[addr] ||= create_connection(addr)
      end
    end

    # Get connection without mutex (internal use)
    def get_connection_internal(addr)
      @nodes[addr] ||= create_connection(addr)
    end

    # Create a new connection to a node
    def create_connection(addr)
      host, port = addr.split(":")
      conn = Connection::TCP.new(host: host, port: port.to_i, timeout: @timeout)

      if @password
        result = conn.call("AUTH", @password)
        raise result if result.is_a?(CommandError)
      end

      conn
    end

    # Refresh cluster slots from any available node
    def refresh_slots_internal
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

      raise RR::ConnectionError, "Could not connect to any cluster node"
    end

    # Update slots mapping from CLUSTER SLOTS result
    def update_slots_from_result(slots_data)
      @masters.clear
      @replicas.clear

      slots_data.each do |slot_info|
        update_slot_range(slot_info)
      end

      @masters.uniq!
    end

    # Update a single slot range from CLUSTER SLOTS entry
    def update_slot_range(slot_info)
      start_slot, end_slot, master_info, *replica_infos = slot_info

      master_host = translate_host(master_info[0])
      master_addr = "#{master_host}:#{master_info[1]}"
      @masters << master_addr unless @masters.include?(master_addr)

      replica_addrs = replica_infos.map { |r| "#{translate_host(r[0])}:#{r[1]}" }

      (start_slot..end_slot).each do |slot|
        @slots[slot] = { master: master_addr, replicas: replica_addrs }
      end
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

        hash[key] = value.match?(/^\d+$/) ? value.to_i : value
      end
    end
  end
end
