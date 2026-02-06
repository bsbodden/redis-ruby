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
      # Frozen command constants to avoid string allocations
      CMD_XADD = "XADD"
      CMD_XLEN = "XLEN"
      CMD_XRANGE = "XRANGE"
      CMD_XREVRANGE = "XREVRANGE"
      CMD_XREAD = "XREAD"
      CMD_XGROUP = "XGROUP"
      CMD_XREADGROUP = "XREADGROUP"
      CMD_XACK = "XACK"
      CMD_XPENDING = "XPENDING"
      CMD_XCLAIM = "XCLAIM"
      CMD_XAUTOCLAIM = "XAUTOCLAIM"
      CMD_XINFO = "XINFO"
      CMD_XDEL = "XDEL"
      CMD_XTRIM = "XTRIM"

      # Frozen subcommands and options
      SUBCMD_CREATE = "CREATE"
      SUBCMD_DESTROY = "DESTROY"
      SUBCMD_SETID = "SETID"
      SUBCMD_CREATECONSUMER = "CREATECONSUMER"
      SUBCMD_DELCONSUMER = "DELCONSUMER"
      SUBCMD_STREAM = "STREAM"
      SUBCMD_GROUPS = "GROUPS"
      SUBCMD_CONSUMERS = "CONSUMERS"
      OPT_NOMKSTREAM = "NOMKSTREAM"
      OPT_MAXLEN = "MAXLEN"
      OPT_MINID = "MINID"
      OPT_LIMIT = "LIMIT"
      OPT_COUNT = "COUNT"
      OPT_BLOCK = "BLOCK"
      OPT_STREAMS = "STREAMS"
      OPT_GROUP = "GROUP"
      OPT_NOACK = "NOACK"
      OPT_MKSTREAM = "MKSTREAM"
      OPT_ENTRIESREAD = "ENTRIESREAD"
      OPT_IDLE = "IDLE"
      OPT_TIME = "TIME"
      OPT_RETRYCOUNT = "RETRYCOUNT"
      OPT_FORCE = "FORCE"
      OPT_JUSTID = "JUSTID"
      OPT_FULL = "FULL"
      OPT_APPROX = "~"

      # Append an entry to a stream
      #
      # @param key [String] Stream key
      # @param fields [Hash] Field-value pairs
      # @param id [String] Entry ID (default: "*" for auto-generate)
      # @param maxlen [Integer] Maximum stream length
      # @param minid [String] Minimum ID to keep
      # @param approximate [Boolean] Allow approximate trimming (~)
      # @param nomkstream [Boolean] Don't create stream if missing
      # @param limit [Integer] Maximum entries to delete in a single call (Redis 6.2+)
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
      #
      # @example With approximate trimming and limit
      #   redis.xadd("stream", { "temp" => "23.5" }, maxlen: 1000, approximate: true, limit: 100)
      def xadd(key, fields, id: "*", maxlen: nil, minid: nil, approximate: false, nomkstream: false, limit: nil)
        cmd = [CMD_XADD, key]
        cmd << OPT_NOMKSTREAM if nomkstream

        if maxlen
          cmd << OPT_MAXLEN
          cmd << OPT_APPROX if approximate
          cmd << maxlen
          cmd << OPT_LIMIT << limit if limit && approximate
        elsif minid
          cmd << OPT_MINID
          cmd << OPT_APPROX if approximate
          cmd << minid
          cmd << OPT_LIMIT << limit if limit && approximate
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
        call_1arg(CMD_XLEN, key)
      end

      # Get entries from a stream in ascending order
      #
      # @param key [String] Stream key
      # @param start [String] Start ID ("-" for beginning)
      # @param stop [String] End ID ("+" for end)
      # @param count [Integer] Maximum entries to return
      # @return [Array<Array>] Array of [id, {fields}] pairs
      def xrange(key, start, stop, count: nil)
        # Fast path: no count
        return parse_entries(call_3args(CMD_XRANGE, key, start, stop)) if count.nil?

        cmd = [CMD_XRANGE, key, start, stop]
        cmd << OPT_COUNT << count if count
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
        # Fast path: no count
        return parse_entries(call_3args(CMD_XREVRANGE, key, stop, start)) if count.nil?

        cmd = [CMD_XREVRANGE, key, stop, start]
        cmd << OPT_COUNT << count if count
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
        cmd = [CMD_XREAD]
        cmd << OPT_COUNT << count if count
        cmd << OPT_BLOCK << block if block
        cmd << OPT_STREAMS

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
      # @param entriesread [Integer] Entries read counter for lag tracking (Redis 7.0+)
      # @return [String] "OK"
      def xgroup_create(key, group, id, mkstream: false, entriesread: nil)
        cmd = [CMD_XGROUP, SUBCMD_CREATE, key, group, id]
        cmd << OPT_MKSTREAM if mkstream
        cmd << OPT_ENTRIESREAD << entriesread if entriesread
        call(*cmd)
      end

      # Destroy a consumer group
      #
      # @param key [String] Stream key
      # @param group [String] Group name
      # @return [Integer] 1 if destroyed, 0 if not found
      def xgroup_destroy(key, group)
        call(CMD_XGROUP, SUBCMD_DESTROY, key, group)
      end

      # Set the last delivered ID for a group
      #
      # @param key [String] Stream key
      # @param group [String] Group name
      # @param id [String] New last delivered ID
      # @return [String] "OK"
      def xgroup_setid(key, group, id)
        call(CMD_XGROUP, SUBCMD_SETID, key, group, id)
      end

      # Create a consumer in a group
      #
      # @param key [String] Stream key
      # @param group [String] Group name
      # @param consumer [String] Consumer name
      # @return [Integer] 1 if created, 0 if exists
      def xgroup_createconsumer(key, group, consumer)
        call(CMD_XGROUP, SUBCMD_CREATECONSUMER, key, group, consumer)
      end

      # Delete a consumer from a group
      #
      # @param key [String] Stream key
      # @param group [String] Group name
      # @param consumer [String] Consumer name
      # @return [Integer] Number of pending entries deleted
      def xgroup_delconsumer(key, group, consumer)
        call(CMD_XGROUP, SUBCMD_DELCONSUMER, key, group, consumer)
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
        cmd = [CMD_XREADGROUP, OPT_GROUP, group, consumer]
        cmd << OPT_COUNT << count if count
        cmd << OPT_BLOCK << block if block
        cmd << OPT_NOACK if noack
        cmd << OPT_STREAMS

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
        # Fast path for single ID
        return call(CMD_XACK, key, group, ids[0]) if ids.size == 1

        call(CMD_XACK, key, group, *ids)
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
          cmd = [CMD_XPENDING, key, group, start, stop, count]
          cmd << consumer if consumer
          call(*cmd)
        else
          call(CMD_XPENDING, key, group)
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
        cmd = [CMD_XCLAIM, key, group, consumer, min_idle_time, *ids]
        cmd << OPT_IDLE << idle if idle
        cmd << OPT_TIME << time if time
        cmd << OPT_RETRYCOUNT << retrycount if retrycount
        cmd << OPT_FORCE if force
        cmd << OPT_JUSTID if justid

        result = call(*cmd)
        justid ? result : parse_entries(result)
      end

      # Auto-claim pending entries (Redis 6.2+)
      #
      # Automatically claims entries that have been idle for more than
      # the specified time. More efficient than XPENDING + XCLAIM.
      #
      # @param key [String] Stream key
      # @param group [String] Group name
      # @param consumer [String] New owner
      # @param min_idle_time [Integer] Minimum idle time in ms
      # @param start [String] Start ID to scan from ("0-0" for beginning)
      # @param count [Integer] Maximum entries to claim
      # @param justid [Boolean] Return only IDs
      # @return [Array] [next_start_id, claimed_entries, [deleted_ids]]
      #
      # @example Claim up to 10 idle entries
      #   redis.xautoclaim("stream", "group", "consumer1", 60000, "0-0", count: 10)
      #   # => ["1609459200000-0", [[id, {fields}], ...], []]
      def xautoclaim(key, group, consumer, min_idle_time, start, count: nil, justid: false)
        cmd = [CMD_XAUTOCLAIM, key, group, consumer, min_idle_time, start]
        cmd << OPT_COUNT << count if count
        cmd << OPT_JUSTID if justid

        result = call(*cmd)
        return result if result.nil?

        # Result is [next_start_id, entries, deleted_ids]
        next_id = result[0]
        entries = justid ? result[1] : parse_entries(result[1])
        deleted = result[2] || []

        [next_id, entries, deleted]
      end

      # Get stream info
      #
      # @param key [String] Stream key
      # @param full [Boolean] Get full info
      # @param count [Integer] Limit entries in full output
      # @return [Hash] Stream information
      def xinfo_stream(key, full: false, count: nil)
        cmd = [CMD_XINFO, SUBCMD_STREAM, key]
        if full
          cmd << OPT_FULL
          cmd << OPT_COUNT << count if count
        end
        hash_result(call(*cmd))
      end

      # Get consumer groups info
      #
      # @param key [String] Stream key
      # @return [Array<Hash>] Group information
      def xinfo_groups(key)
        call(CMD_XINFO, SUBCMD_GROUPS, key).map { |g| hash_result(g) }
      end

      # Get consumers info for a group
      #
      # @param key [String] Stream key
      # @param group [String] Group name
      # @return [Array<Hash>] Consumer information
      def xinfo_consumers(key, group)
        call(CMD_XINFO, SUBCMD_CONSUMERS, key, group).map { |c| hash_result(c) }
      end

      # Delete entries from a stream
      #
      # @param key [String] Stream key
      # @param ids [Array<String>] Entry IDs to delete
      # @return [Integer] Number of deleted entries
      def xdel(key, *ids)
        # Fast path for single ID
        return call_2args(CMD_XDEL, key, ids[0]) if ids.size == 1

        call(CMD_XDEL, key, *ids)
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
        cmd = [CMD_XTRIM, key]

        if maxlen
          cmd << OPT_MAXLEN
          cmd << OPT_APPROX if approximate
          cmd << maxlen
        elsif minid
          cmd << OPT_MINID
          cmd << OPT_APPROX if approximate
          cmd << minid
        else
          raise ArgumentError, "Must specify maxlen or minid"
        end

        cmd << OPT_LIMIT << limit if limit
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
