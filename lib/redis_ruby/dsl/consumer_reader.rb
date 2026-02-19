# frozen_string_literal: true

module RR
  module DSL
    # Fluent builder for reading from Redis Streams as a consumer
    #
    # Provides a chainable interface for building consumer read queries
    # with support for blocking, count limits, and auto-acknowledgment.
    #
    # @example Read as consumer
    #   consumer.read.count(10).execute
    #
    # @example Read without acknowledgment
    #   consumer.read.count(10).noack.execute
    #
    # @example Block for new entries
    #   consumer.read.block(5000).execute
    class ConsumerReader
      # @param [RR::Client] Redis client
      # @param stream_key [String] Stream key
      # @param group_name [String] Consumer group name
      # @param consumer_name [String] Consumer name
      def initialize(redis, stream_key, group_name, consumer_name)
        @redis = redis
        @stream_key = stream_key
        @group_name = group_name
        @consumer_name = consumer_name
        @start_id = ">" # Default: only new entries
        @count_limit = nil
        @block_ms = nil
        @noack = false
      end

      # Set the starting ID for reading
      #
      # @param id [String] Starting ID (">" for new, "0-0" for pending)
      # @return [self]
      #
      # @example
      #   reader.from(">")     # Only new entries
      #   reader.from("0-0")   # Pending entries
      def from(id)
        @start_id = id.to_s
        self
      end

      # Read only new entries (not yet delivered to any consumer)
      #
      # @return [self]
      #
      # @example
      #   reader.new_only
      def new_only
        @start_id = ">"
        self
      end

      # Read pending entries (already delivered but not acknowledged)
      #
      # @return [self]
      #
      # @example
      #   reader.pending_only
      def pending_only
        @start_id = "0-0"
        self
      end

      # Limit the number of entries returned
      #
      # @param n [Integer] Maximum entries
      # @return [self]
      #
      # @example
      #   reader.count(10)
      def count(num)
        @count_limit = num
        self
      end
      alias limit count

      # Block waiting for new entries
      #
      # @param milliseconds [Integer] Milliseconds to block (0 = forever)
      # @return [self]
      #
      # @example
      #   reader.block(5000)  # Block for 5 seconds
      def block(milliseconds)
        @block_ms = milliseconds
        self
      end

      # Don't add entries to the pending list (auto-acknowledge)
      #
      # @return [self]
      #
      # @example
      #   reader.noack
      def noack
        @noack = true
        self
      end

      # Execute the read operation
      #
      # @return [Array, nil] Array of [id, fields] pairs, or nil if timeout
      #
      # @example
      #   entries = reader.count(10).execute
      def execute
        result = @redis.xreadgroup(@group_name, @consumer_name, @stream_key, @start_id,
                                   count: @count_limit, block: @block_ms, noack: @noack)
        return nil if result.nil?

        # XREADGROUP returns [[stream_key, entries], ...]
        # Extract just the entries for this stream
        result[0][1]
      end
      alias results execute
      alias run execute

      # Iterate over entries
      #
      # @yield [id, fields] Block to call for each entry
      # @return [void]
      #
      # @example
      #   reader.count(10).each do |id, fields|
      #     puts "#{id}: #{fields}"
      #   end
      def each(&)
        entries = execute
        return if entries.nil?

        entries.each(&)
      end
    end
  end
end
