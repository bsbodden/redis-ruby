# frozen_string_literal: true

module RR
  module Concerns
    # Command routing, redirection handling, and retry logic for ClusterClient
    #
    # Provides the core routing infrastructure that maps Redis commands to the
    # correct cluster node based on key hashing, and handles MOVED/ASK/TRYAGAIN
    # redirections transparently.
    #
    # The including class must define:
    # - @read_from: Symbol (:master, :replica, :replica_preferred)
    # - @retry_count: Integer
    # - #node_for_slot(slot, for_read:): node address lookup
    # - #random_master: random master node address
    # - #get_connection(addr): connection for a node address
    # - #translate_host(host): host translation for NAT/Docker
    # - #refresh_slots: refresh cluster slot mapping
    # - MAX_REDIRECTIONS: max redirection count
    module ClusterRouting
      # Commands with no key
      NO_KEY_COMMANDS = %w[PING INFO DBSIZE TIME CLUSTER].freeze

      # List of read-only commands
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

      private

      # Extract the key from a command
      def extract_key(command, args)
        cmd = command.to_s.upcase
        return nil if NO_KEY_COMMANDS.include?(cmd)

        args[0] if args.any?
      end

      # Execute command with retry and redirection handling
      def execute_with_retry(command, args, slot, redirections: 0)
        raise RR::Error, "Too many redirections" if redirections >= self.class::MAX_REDIRECTIONS

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
        max = self.class::MAX_REDIRECTIONS
        raise TryAgainError, "TRYAGAIN after #{max} attempts" if redirections >= max

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
    end
  end
end
