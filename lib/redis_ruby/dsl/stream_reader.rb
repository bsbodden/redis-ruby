# frozen_string_literal: true

module RR
  module DSL
    # Fluent builder for reading from Redis Streams
    #
    # Provides a chainable interface for building stream read queries
    # with support for ranges, blocking, and iteration.
    #
    # @example Read from ID
    #   stream.read.from("0-0").count(10).execute
    #
    # @example Read range
    #   stream.read.range("-", "+").count(100).execute
    #
    # @example Block for new entries
    #   stream.read.from("$").block(5000).execute
    #
    # @example Iterate over entries
    #   stream.read.from("0-0").each do |id, fields|
    #     puts "#{id}: #{fields}"
    #   end
    class StreamReader
      # @param [RR::Client] Redis client
      # @param key [String] Stream key
      def initialize(redis, key)
        @redis = redis
        @key = key
        @start_id = nil
        @range_start = nil
        @range_end = nil
        @reverse = false
        @count_limit = nil
        @block_ms = nil
      end

      # Set the starting ID for reading
      #
      # @param id [String] Starting ID ("0-0" for beginning, "$" for new only)
      # @return [self]
      #
      # @example
      #   reader.from("0-0")
      #   reader.from("$")  # Only new entries
      def from(id)
        @start_id = id.to_s
        self
      end

      # Read a range of entries
      #
      # @param start [String] Start ID ("-" for beginning)
      # @param stop [String] End ID ("+" for end)
      # @return [self]
      #
      # @example
      #   reader.range("-", "+")
      #   reader.range("1000-0", "2000-0")
      def range(start, stop)
        @range_start = start.to_s
        @range_end = stop.to_s
        @reverse = false
        self
      end

      # Read a range in reverse order
      #
      # @param start [String] Start ID ("+" for end)
      # @param stop [String] End ID ("-" for beginning)
      # @return [self]
      #
      # @example
      #   reader.reverse_range("+", "-")
      def reverse_range(start, stop)
        @range_start = start.to_s
        @range_end = stop.to_s
        @reverse = true
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
      #   reader.block(0)     # Block forever
      def block(milliseconds)
        @block_ms = milliseconds
        self
      end

      # Execute the read operation
      #
      # @return [Array, nil] Array of [id, fields] pairs, or nil if timeout
      #
      # @example
      #   entries = reader.from("0-0").count(10).execute
      def execute
        if @range_start && @range_end
          # Range query
          if @reverse
            @redis.xrevrange(@key, @range_start, @range_end, count: @count_limit)
          else
            @redis.xrange(@key, @range_start, @range_end, count: @count_limit)
          end
        elsif @start_id
          # XREAD query
          result = @redis.xread(@key, @start_id, count: @count_limit, block: @block_ms)
          return nil if result.nil?

          # XREAD returns [[stream_key, entries], ...]
          # Extract just the entries for this stream
          result[0][1]
        else
          # Default: read all
          @redis.xrange(@key, "-", "+", count: @count_limit)
        end
      end
      alias results execute
      alias run execute

      # Iterate over entries
      #
      # @yield [id, fields] Block to call for each entry
      # @return [void]
      #
      # @example
      #   reader.from("0-0").each do |id, fields|
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
