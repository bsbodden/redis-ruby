# frozen_string_literal: true

module RR
  module DSL
    # Proxy for Redis Stream consumer operations
    #
    # Provides a fluent interface for consumer operations within
    # a consumer group, including reading, acknowledging, and claiming.
    #
    # @example Basic consumer workflow
    #   consumer = redis.stream(:events).consumer(:mygroup, :worker1)
    #   entries = consumer.read.count(10).execute
    #   consumer.ack(*entries.map(&:first))
    #
    # @example Claiming entries
    #   claimed = consumer.claim(min_idle: 60000, ids: ["1000-0", "1000-1"])
    class ConsumerProxy
      # @param [RR::Client] Redis client
      # @param stream_key [String] Stream key
      # @param group_name [String] Consumer group name
      # @param consumer_name [String] Consumer name
      def initialize(redis, stream_key, group_name, consumer_name)
        @redis = redis
        @stream_key = stream_key
        @group_name = group_name
        @consumer_name = consumer_name
      end

      # Create a reader for this consumer
      #
      # @return [ConsumerReader] Reader builder for consumer
      #
      # @example
      #   consumer.read.count(10).execute
      def read
        require_relative "consumer_reader"
        ConsumerReader.new(@redis, @stream_key, @group_name, @consumer_name)
      end

      # Acknowledge one or more entries
      #
      # @param ids [Array<String>] Entry IDs to acknowledge
      # @return [Integer] Number of entries acknowledged
      #
      # @example
      #   consumer.ack("1000-0", "1000-1", "1000-2")
      def ack(*ids)
        @redis.xack(@stream_key, @group_name, *ids)
      end
      alias acknowledge ack

      # Get pending entries information
      #
      # @param start [String] Start ID ("-" for beginning)
      # @param stop [String] End ID ("+" for end)
      # @param count [Integer] Maximum entries to return
      # @param consumer [String, Symbol] Filter by specific consumer
      # @param idle [Integer] Minimum idle time in milliseconds
      # @return [Array, Hash] Pending entries summary or detailed list
      #
      # @example Get summary
      #   consumer.pending
      #
      # @example Get detailed list
      #   consumer.pending(start: "-", stop: "+", count: 10)
      def pending(start: nil, stop: nil, count: nil, consumer: nil, idle: nil)
        if start && stop
          # Detailed pending list
          @redis.xpending(@stream_key, @group_name, start.to_s, stop.to_s, count, 
                         consumer: consumer&.to_s, idle: idle)
        else
          # Summary
          @redis.xpending(@stream_key, @group_name)
        end
      end

      # Claim entries from other consumers
      #
      # @param min_idle [Integer] Minimum idle time in milliseconds
      # @param ids [Array<String>] Entry IDs to claim
      # @param idle [Integer] Set idle time
      # @param time [Integer] Set last delivery time
      # @param retrycount [Integer] Set delivery count
      # @param force [Boolean] Create entry if not exists
      # @param justid [Boolean] Return only IDs
      # @return [Array] Claimed entries or IDs
      #
      # @example
      #   consumer.claim(min_idle: 60000, ids: ["1000-0", "1000-1"])
      def claim(min_idle:, ids:, idle: nil, time: nil, retrycount: nil, force: false, justid: false)
        @redis.xclaim(@stream_key, @group_name, @consumer_name, min_idle, *ids,
                     idle: idle, time: time, retrycount: retrycount, 
                     force: force, justid: justid)
      end

      # Automatically claim idle entries
      #
      # @param min_idle [Integer] Minimum idle time in milliseconds
      # @param start [String] Start ID to scan from ("0-0" for beginning)
      # @param count [Integer] Maximum entries to claim
      # @param justid [Boolean] Return only IDs
      # @return [Array] [next_start_id, claimed_entries, deleted_ids]
      #
      # @example
      #   next_id, entries, deleted = consumer.autoclaim(min_idle: 60000, start: "0-0", count: 10)
      def autoclaim(min_idle:, start: "0-0", count: nil, justid: false)
        @redis.xautoclaim(@stream_key, @group_name, @consumer_name, min_idle, start.to_s,
                         count: count, justid: justid)
      end

      # Get the stream key
      #
      # @return [String] Stream key
      def stream_key
        @stream_key
      end

      # Get the group name
      #
      # @return [String] Group name
      def group_name
        @group_name
      end

      # Get the consumer name
      #
      # @return [String] Consumer name
      def consumer_name
        @consumer_name
      end
    end
  end
end

