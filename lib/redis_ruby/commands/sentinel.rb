# frozen_string_literal: true

module RedisRuby
  module Commands
    # Redis Sentinel commands
    #
    # Commands for interacting with Redis Sentinel servers for
    # high availability and automatic failover.
    #
    # @see https://redis.io/docs/latest/operate/oss_and_stack/management/sentinel/
    module Sentinel
      # Get list of monitored masters and their state
      #
      # @return [Array<Hash>] List of master info hashes
      def sentinel_masters
        result = call("SENTINEL", "MASTERS")
        result.map { |master| parse_info_reply(master) }
      end

      # Get the state and info of the specified master
      #
      # @param name [String] Master name
      # @return [Hash] Master info
      def sentinel_master(name)
        result = call("SENTINEL", "MASTER", name)
        parse_info_reply(result)
      end

      # Get list of replicas for a master
      #
      # @param name [String] Master name
      # @return [Array<Hash>] List of replica info hashes
      def sentinel_replicas(name)
        result = call("SENTINEL", "REPLICAS", name)
        result.map { |replica| parse_info_reply(replica) }
      end

      # Alias for backward compatibility
      alias sentinel_slaves sentinel_replicas

      # Get list of Sentinel instances for a master
      #
      # @param name [String] Master name
      # @return [Array<Hash>] List of Sentinel info hashes
      def sentinel_sentinels(name)
        result = call("SENTINEL", "SENTINELS", name)
        result.map { |sentinel| parse_info_reply(sentinel) }
      end

      # Get the address of the master by name
      #
      # @param name [String] Master name
      # @return [Array<String>, nil] [host, port] or nil if unknown
      def sentinel_get_master_addr_by_name(name)
        call("SENTINEL", "GET-MASTER-ADDR-BY-NAME", name)
      end

      # Check if the master is in an ODOWN (Objectively Down) state
      #
      # @param host_ip [String] Master IP address
      # @param host_port [Integer] Master port
      # @param current_epoch [Integer] Current epoch
      # @param run_id [String] Run ID
      # @return [Boolean]
      def sentinel_is_master_down_by_addr(host_ip, host_port, current_epoch, run_id)
        call("SENTINEL", "IS-MASTER-DOWN-BY-ADDR", host_ip, host_port, current_epoch, run_id)
      end

      # Reset masters matching a pattern
      #
      # @param pattern [String] Glob-style pattern
      # @return [Integer] Number of masters reset
      def sentinel_reset(pattern)
        call("SENTINEL", "RESET", pattern)
      end

      # Force a failover
      #
      # @param name [String] Master name
      # @return [String] "OK"
      def sentinel_failover(name)
        call("SENTINEL", "FAILOVER", name)
      end

      # Check Sentinel's view of Redis instances
      #
      # @param name [String] Master name
      # @return [Hash] Ckquorum info
      def sentinel_ckquorum(name)
        call("SENTINEL", "CKQUORUM", name)
      end

      # Force Sentinel to flush the config to disk
      #
      # @return [String] "OK"
      def sentinel_flushconfig
        call("SENTINEL", "FLUSHCONFIG")
      end

      # Monitor a new master
      #
      # @param name [String] Master name
      # @param host_ip [String] Master IP
      # @param host_port [Integer] Master port
      # @param quorum [Integer] Number of Sentinels needed to agree
      # @return [String] "OK"
      def sentinel_monitor(name, host_ip, host_port, quorum)
        call("SENTINEL", "MONITOR", name, host_ip, host_port.to_s, quorum.to_s)
      end

      # Remove a master from monitoring
      #
      # @param name [String] Master name
      # @return [String] "OK"
      def sentinel_remove(name)
        call("SENTINEL", "REMOVE", name)
      end

      # Set a master's configuration parameter
      #
      # @param name [String] Master name
      # @param option [String] Option name
      # @param value [String] Option value
      # @return [String] "OK"
      def sentinel_set(name, option, value)
        call("SENTINEL", "SET", name, option, value.to_s)
      end

      # Get Sentinel's own ID
      #
      # @return [String] Sentinel ID
      def sentinel_myid
        call("SENTINEL", "MYID")
      end

      # Ping the Sentinel server
      #
      # @return [String] "PONG"
      def sentinel_ping
        call("PING")
      end

      # Get Sentinel info
      #
      # @param section [String, nil] Optional section name
      # @return [String] Info output
      def sentinel_info(section = nil)
        args = ["INFO"]
        args << section if section
        call(*args)
      end

      private

      # Parse Sentinel info reply (flat array to hash)
      def parse_info_reply(array)
        return {} unless array.is_a?(Array)

        Hash[*array]
      end
    end
  end
end
