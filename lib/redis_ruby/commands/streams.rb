# frozen_string_literal: true

module RedisRuby
  module Commands
    # Stream commands for log-like data structures
    #
    # Redis Streams are append-only log data structures that support
    # consumer groups for distributed processing.
    #
    # @example Basic usage
    #   redis.xadd("mystream", { "sensor" => "temp", "value" => "23.5" })
    #   redis.xrange("mystream", "-", "+")
    #
    # @example Consumer groups
    #   redis.xgroup_create("mystream", "mygroup", "$")
    #   redis.xreadgroup("mygroup", "consumer1", "mystream", ">")
    #
    # @see https://redis.io/commands/?group=stream
    module Streams
      # Append an entry to a stream
      #
      # @param key [String] Stream key
      # @param fields [Hash] Field-value pairs
      # @param id [String] Entry ID (default: "*" for auto-generate)
      # @param maxlen [Integer] Maximum stream length
      # @param minid [String] Minimum ID to keep
      # @param approximate [Boolean] Allow approximate trimming (~)
      # @param nomkstream [Boolean] Don't create stream if missing
      # @return [String, nil] Entry ID, or nil if NOMKSTREAM and stream missing
      #
      # @example Auto-generated ID
      #   redis.xadd("stream", { "temp" => "23.5" })
      #
      # @example With explicit ID
      #   redis.xadd("stream", { "temp" => "23.5" }, id: "1000-0")
      #
      # @example With capping
      #   redis.xadd("stream", { "temp" => "23.5" }, maxlen: 1000)
      def xadd(key, fields, id: "*", maxlen: nil, minid: nil, approximate: false, nomkstream: false)
        cmd = ["XADD", key]
        cmd << "NOMKSTREAM" if nomkstream

        if maxlen
          cmd << "MAXLEN"
          cmd << "~" if approximate
          cmd << maxlen
        elsif minid
          cmd << "MINID"
          cmd << "~" if approximate
          cmd << minid
        end

        cmd << id
        fields.each { |k, v| cmd << k << v }

        call(*cmd)
      end

      # Get the number of entries in a stream
      #
      # @param key [String] Stream key
      # @return [Integer] Number of entries
      def xlen(key)
        call("XLEN", key)
      end

      # Get entries from a stream in ascending order
      #
      # @param key [String] Stream key
      # @param start [String] Start ID ("-" for beginning)
      # @param stop [String] End ID ("+" for end)
      # @param count [Integer] Maximum entries to return
      # @return [Array<Array>] Array of [id, {fields}] pairs
      def xrange(key, start, stop, count: nil)
        cmd = ["XRANGE", key, start, stop]
        cmd << "COUNT" << count if count
        parse_entries(call(*cmd))
      end

      # Get entries from a stream in descending order
      #
      # @param key [String] Stream key
      # @param stop [String] End ID ("+" for end)
      # @param start [String] Start ID ("-" for beginning)
      # @param count [Integer] Maximum entries to return
      # @return [Array<Array>] Array of [id, {fields}] pairs
      def xrevrange(key, stop, start, count: nil)
        cmd = ["XREVRANGE", key, stop, start]
        cmd << "COUNT" << count if count
        parse_entries(call(*cmd))
      end

      # Read entries from one or more streams
      #
      # @param streams [String, Hash] Stream key(s) with start IDs
      # @param id [String] Start ID for single stream
      # @param count [Integer] Maximum entries per stream
      # @param block [Integer] Block for N milliseconds (0 = forever)
      # @return [Array, nil] Array of [stream, entries] pairs
      #
      # @example Single stream
      #   redis.xread("mystream", "0-0")
      #
      # @example Multiple streams
      #   redis.xread({ "stream1" => "0-0", "stream2" => "0-0" })
      #
      # @example With blocking
      #   redis.xread("mystream", "$", block: 5000)
      def xread(streams, id = nil, count: nil, block: nil)
        cmd = ["XREAD"]
        cmd << "COUNT" << count if count
        cmd << "BLOCK" << block if block
        cmd << "STREAMS"

        if streams.is_a?(Hash)
          streams.each_key { |k| cmd << k }
          streams.each_value { |v| cmd << v }
        else
          cmd << streams << id
        end

        result = call(*cmd)
        return nil if result.nil?

        result.map { |stream, entries| [stream, parse_entries(entries)] }
      end

      # Create a consumer group
      #
      # @param key [String] Stream key
      # @param group [String] Group name
      # @param id [String] Start ID ("$" for new, "0" for beginning)
      # @param mkstream [Boolean] Create stream if missing
      # @return [String] "OK"
      def xgroup_create(key, group, id, mkstream: false)
        cmd = ["XGROUP", "CREATE", key, group, id]
        cmd << "MKSTREAM" if mkstream
        call(*cmd)
      end

      # Destroy a consumer group
      #
      # @param key [String] Stream key
      # @param group [String] Group name
      # @return [Integer] 1 if destroyed, 0 if not found
      def xgroup_destroy(key, group)
        call("XGROUP", "DESTROY", key, group)
      end

      # Set the last delivered ID for a group
      #
      # @param key [String] Stream key
      # @param group [String] Group name
      # @param id [String] New last delivered ID
      # @return [String] "OK"
      def xgroup_setid(key, group, id)
        call("XGROUP", "SETID", key, group, id)
      end

      # Create a consumer in a group
      #
      # @param key [String] Stream key
      # @param group [String] Group name
      # @param consumer [String] Consumer name
      # @return [Integer] 1 if created, 0 if exists
      def xgroup_createconsumer(key, group, consumer)
        call("XGROUP", "CREATECONSUMER", key, group, consumer)
      end

      # Delete a consumer from a group
      #
      # @param key [String] Stream key
      # @param group [String] Group name
      # @param consumer [String] Consumer name
      # @return [Integer] Number of pending entries deleted
      def xgroup_delconsumer(key, group, consumer)
        call("XGROUP", "DELCONSUMER", key, group, consumer)
      end

      # Read entries from a stream as a consumer group member
      #
      # @param group [String] Group name
      # @param consumer [String] Consumer name
      # @param streams [String, Hash] Stream key(s) with IDs
      # @param id [String] ID for single stream (">" for new, "0" for pending)
      # @param count [Integer] Maximum entries
      # @param block [Integer] Block milliseconds
      # @param noack [Boolean] Don't add to pending list
      # @return [Array, nil] Array of [stream, entries] pairs
      def xreadgroup(group, consumer, streams, id = nil, count: nil, block: nil, noack: false)
        cmd = ["XREADGROUP", "GROUP", group, consumer]
        cmd << "COUNT" << count if count
        cmd << "BLOCK" << block if block
        cmd << "NOACK" if noack
        cmd << "STREAMS"

        if streams.is_a?(Hash)
          streams.each_key { |k| cmd << k }
          streams.each_value { |v| cmd << v }
        else
          cmd << streams << id
        end

        result = call(*cmd)
        return nil if result.nil?

        result.map { |stream, entries| [stream, parse_entries(entries)] }
      end

      # Acknowledge message processing
      #
      # @param key [String] Stream key
      # @param group [String] Group name
      # @param ids [Array<String>] Entry IDs to acknowledge
      # @return [Integer] Number of acknowledged entries
      def xack(key, group, *ids)
        call("XACK", key, group, *ids)
      end

      # Get pending entries for a group
      #
      # @param key [String] Stream key
      # @param group [String] Group name
      # @param start [String] Start ID (optional, for detailed list)
      # @param stop [String] End ID
      # @param count [Integer] Maximum entries
      # @param consumer [String] Filter by consumer
      # @return [Array] Pending summary or detailed list
      def xpending(key, group, start = nil, stop = nil, count = nil, consumer: nil)
        if start && stop && count
          cmd = ["XPENDING", key, group, start, stop, count]
          cmd << consumer if consumer
          call(*cmd)
        else
          call("XPENDING", key, group)
        end
      end

      # Claim pending entries for a consumer
      #
      # @param key [String] Stream key
      # @param group [String] Group name
      # @param consumer [String] New owner
      # @param min_idle_time [Integer] Minimum idle time in ms
      # @param ids [Array<String>] Entry IDs to claim
      # @param idle [Integer] Set idle time
      # @param time [Integer] Set last delivery time
      # @param retrycount [Integer] Set delivery count
      # @param force [Boolean] Create entry if not exists
      # @param justid [Boolean] Return only IDs
      # @return [Array] Claimed entries or IDs
      def xclaim(key, group, consumer, min_idle_time, *ids,
                 idle: nil, time: nil, retrycount: nil, force: false, justid: false)
        cmd = ["XCLAIM", key, group, consumer, min_idle_time, *ids]
        cmd << "IDLE" << idle if idle
        cmd << "TIME" << time if time
        cmd << "RETRYCOUNT" << retrycount if retrycount
        cmd << "FORCE" if force
        cmd << "JUSTID" if justid

        result = call(*cmd)
        justid ? result : parse_entries(result)
      end

      # Get stream info
      #
      # @param key [String] Stream key
      # @param full [Boolean] Get full info
      # @param count [Integer] Limit entries in full output
      # @return [Hash] Stream information
      def xinfo_stream(key, full: false, count: nil)
        cmd = ["XINFO", "STREAM", key]
        if full
          cmd << "FULL"
          cmd << "COUNT" << count if count
        end
        hash_result(call(*cmd))
      end

      # Get consumer groups info
      #
      # @param key [String] Stream key
      # @return [Array<Hash>] Group information
      def xinfo_groups(key)
        call("XINFO", "GROUPS", key).map { |g| hash_result(g) }
      end

      # Get consumers info for a group
      #
      # @param key [String] Stream key
      # @param group [String] Group name
      # @return [Array<Hash>] Consumer information
      def xinfo_consumers(key, group)
        call("XINFO", "CONSUMERS", key, group).map { |c| hash_result(c) }
      end

      # Delete entries from a stream
      #
      # @param key [String] Stream key
      # @param ids [Array<String>] Entry IDs to delete
      # @return [Integer] Number of deleted entries
      def xdel(key, *ids)
        call("XDEL", key, *ids)
      end

      # Trim a stream
      #
      # @param key [String] Stream key
      # @param maxlen [Integer] Maximum length
      # @param minid [String] Minimum ID
      # @param approximate [Boolean] Allow approximate trimming
      # @param limit [Integer] Maximum entries to delete
      # @return [Integer] Number of deleted entries
      def xtrim(key, maxlen: nil, minid: nil, approximate: false, limit: nil)
        cmd = ["XTRIM", key]

        if maxlen
          cmd << "MAXLEN"
          cmd << "~" if approximate
          cmd << maxlen
        elsif minid
          cmd << "MINID"
          cmd << "~" if approximate
          cmd << minid
        else
          raise ArgumentError, "Must specify maxlen or minid"
        end

        cmd << "LIMIT" << limit if limit
        call(*cmd)
      end

      private

      # Parse stream entries from [id, [field, value, ...]] to [id, {field => value}]
      def parse_entries(entries)
        return [] if entries.nil?

        entries.map do |id, fields|
          [id, Hash[*fields]]
        end
      end

      # Convert flat array to hash
      def hash_result(array)
        return {} if array.nil?

        Hash[*array]
      end
    end
  end
end
