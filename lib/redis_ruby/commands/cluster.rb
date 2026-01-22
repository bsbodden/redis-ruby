# frozen_string_literal: true

module RedisRuby
  module Commands
    # Redis Cluster commands
    #
    # Commands for managing and querying Redis Cluster state.
    #
    # @see https://redis.io/commands/?group=cluster
    module Cluster
      # Get cluster information
      #
      # @return [Hash] Cluster state information
      def cluster_info
        result = call("CLUSTER", "INFO")
        parse_cluster_info(result)
      end

      # Get cluster nodes information
      #
      # @return [Array<Hash>] List of cluster nodes with their details
      def cluster_nodes
        result = call("CLUSTER", "NODES")
        parse_cluster_nodes(result)
      end

      # Get cluster slots mapping
      #
      # @return [Array<Hash>] Slot ranges with node assignments
      def cluster_slots
        result = call("CLUSTER", "SLOTS")
        parse_cluster_slots(result)
      end

      # Get cluster shards (Redis 7+)
      #
      # @return [Array<Hash>] Shard information
      def cluster_shards
        call("CLUSTER", "SHARDS")
      end

      # Get the hash slot for a key
      #
      # @param key [String] Key to check
      # @return [Integer] Hash slot (0-16383)
      def cluster_keyslot(key)
        call("CLUSTER", "KEYSLOT", key)
      end

      # Count keys in a hash slot
      #
      # @param slot [Integer] Hash slot
      # @return [Integer] Number of keys in slot
      def cluster_countkeysinslot(slot)
        call("CLUSTER", "COUNTKEYSINSLOT", slot)
      end

      # Get keys in a hash slot
      #
      # @param slot [Integer] Hash slot
      # @param count [Integer] Maximum keys to return
      # @return [Array<String>] Keys in the slot
      def cluster_getkeysinslot(slot, count)
        call("CLUSTER", "GETKEYSINSLOT", slot, count)
      end

      # Get my node ID
      #
      # @return [String] Current node's ID
      def cluster_myid
        call("CLUSTER", "MYID")
      end

      # Get my shard ID (Redis 7.2+)
      #
      # @return [String] Current node's shard ID
      def cluster_myshardid
        call("CLUSTER", "MYSHARDID")
      end

      # Reconfigure a node as replica of another
      #
      # @param node_id [String] Node ID to replicate
      # @return [String] "OK"
      def cluster_replicate(node_id)
        call("CLUSTER", "REPLICATE", node_id)
      end

      # Add slots to this node
      #
      # @param slots [Array<Integer>] Slots to add
      # @return [String] "OK"
      def cluster_addslots(*slots)
        call("CLUSTER", "ADDSLOTS", *slots)
      end

      # Remove slots from this node
      #
      # @param slots [Array<Integer>] Slots to remove
      # @return [String] "OK"
      def cluster_delslots(*slots)
        call("CLUSTER", "DELSLOTS", *slots)
      end

      # Set slot state
      #
      # @param slot [Integer] Slot number
      # @param state [Symbol] :importing, :migrating, :stable, :node
      # @param node_id [String] Node ID (for :importing, :migrating, :node)
      # @return [String] "OK"
      def cluster_setslot(slot, state, node_id = nil)
        case state
        when :importing
          call("CLUSTER", "SETSLOT", slot, "IMPORTING", node_id)
        when :migrating
          call("CLUSTER", "SETSLOT", slot, "MIGRATING", node_id)
        when :stable
          call("CLUSTER", "SETSLOT", slot, "STABLE")
        when :node
          call("CLUSTER", "SETSLOT", slot, "NODE", node_id)
        else
          raise ArgumentError, "Invalid state: #{state}"
        end
      end

      # Meet another cluster node
      #
      # @param ip [String] Node IP
      # @param port [Integer] Node port
      # @param cluster_bus_port [Integer] Optional cluster bus port
      # @return [String] "OK"
      def cluster_meet(ip, port, cluster_bus_port = nil)
        args = ["CLUSTER", "MEET", ip, port]
        args << cluster_bus_port if cluster_bus_port
        call(*args)
      end

      # Remove a node from the cluster
      #
      # @param node_id [String] Node ID to forget
      # @return [String] "OK"
      def cluster_forget(node_id)
        call("CLUSTER", "FORGET", node_id)
      end

      # Force a failover
      #
      # @param option [Symbol] :force or :takeover (optional)
      # @return [String] "OK"
      def cluster_failover(option = nil)
        case option
        when :force
          call("CLUSTER", "FAILOVER", "FORCE")
        when :takeover
          call("CLUSTER", "FAILOVER", "TAKEOVER")
        when nil
          call("CLUSTER", "FAILOVER")
        else
          raise ArgumentError, "Invalid option: #{option}"
        end
      end

      # Reset the cluster
      #
      # @param hard [Boolean] Hard reset (clears all data)
      # @return [String] "OK"
      def cluster_reset(hard: false)
        if hard
          call("CLUSTER", "RESET", "HARD")
        else
          call("CLUSTER", "RESET", "SOFT")
        end
      end

      # Save cluster config
      #
      # @return [String] "OK"
      def cluster_saveconfig
        call("CLUSTER", "SAVECONFIG")
      end

      # Set cluster config epoch
      #
      # @param epoch [Integer] Config epoch
      # @return [String] "OK"
      def cluster_set_config_epoch(epoch)
        call("CLUSTER", "SET-CONFIG-EPOCH", epoch)
      end

      # Bump the cluster config epoch
      #
      # @return [String] "BUMPED" or "STILL"
      def cluster_bumpepoch
        call("CLUSTER", "BUMPEPOCH")
      end

      # Get cluster replica count
      #
      # @param node_id [String] Node ID
      # @return [Integer] Number of replicas
      def cluster_count_failure_reports(node_id)
        call("CLUSTER", "COUNT-FAILURE-REPORTS", node_id)
      end

      # Perform a read-only query on a replica
      #
      # @return [String] "OK"
      def readonly
        call("READONLY")
      end

      # Disable read-only mode
      #
      # @return [String] "OK"
      def readwrite
        call("READWRITE")
      end

      # Ask for redirection
      #
      # Send ASKING before a command after receiving ASK redirect
      #
      # @return [String] "OK"
      def asking
        call("ASKING")
      end

      private

      # Parse CLUSTER INFO response
      def parse_cluster_info(info)
        info.split("\r\n").each_with_object({}) do |line, hash|
          key, value = line.split(":")
          next unless key && value

          # Convert numeric values
          hash[key] = case value
                      when /^\d+$/
                        value.to_i
                      else
                        value
                      end
        end
      end

      # Parse CLUSTER NODES response
      def parse_cluster_nodes(nodes_str)
        nodes_str.split("\n").filter_map do |line|
          parts = line.split
          next if parts.empty?

          node = {
            id: parts[0],
            address: parts[1],
            flags: parts[2].split(","),
            master_id: parts[3] == "-" ? nil : parts[3],
            ping_sent: parts[4].to_i,
            pong_recv: parts[5].to_i,
            config_epoch: parts[6].to_i,
            link_state: parts[7],
          }

          # Parse slots (remaining parts)
          slots = []
          parts[8..].each do |slot_range|
            if slot_range.include?("-")
              start_slot, end_slot = slot_range.split("-").map(&:to_i)
              slots << (start_slot..end_slot)
            elsif /^\d+$/.match?(slot_range)
              slots << slot_range.to_i
            end
          end
          node[:slots] = slots

          node
        end
      end

      # Parse CLUSTER SLOTS response
      def parse_cluster_slots(slots_data)
        slots_data.map do |slot_info|
          start_slot, end_slot, master, *replicas = slot_info

          {
            start_slot: start_slot,
            end_slot: end_slot,
            master: parse_node_info(master),
            replicas: replicas.map { |r| parse_node_info(r) },
          }
        end
      end

      # Parse node info from CLUSTER SLOTS response
      def parse_node_info(node_data)
        return nil unless node_data

        {
          host: node_data[0],
          port: node_data[1],
          id: node_data[2],
        }
      end
    end
  end
end
