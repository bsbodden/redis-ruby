# frozen_string_literal: true

module RR
  module DSL
    # Fluent builder for reading from multiple Redis Streams
    #
    # Provides a chainable interface for reading from multiple streams
    # simultaneously with support for blocking and count limits.
    #
    # @example Read from multiple streams
    #   redis.streams(events: "0-0", metrics: "0-0").count(10).execute
    #
    # @example Block for new entries
    #   redis.streams(events: "$", logs: "$").block(5000).execute
    class MultiStreamReader
      # @param [RR::Client] Redis client
      # @param streams [Hash] Hash of stream_key => start_id pairs
      def initialize(redis, streams)
        @redis = redis
        @streams = normalize_streams(streams)
        @count_limit = nil
        @block_ms = nil
      end

      # Limit the number of entries per stream
      #
      # @param n [Integer] Maximum entries per stream
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

      # Execute the read operation
      #
      # @return [Hash, nil] Hash of stream_key => entries, or nil if timeout
      #
      # @example
      #   results = reader.execute
      #   # => { "events" => [[id, fields], ...], "metrics" => [...] }
      def execute
        result = @redis.xread(@streams, count: @count_limit, block: @block_ms)
        return nil if result.nil?

        # Convert array result to hash
        # XREAD returns [[stream_key, entries], ...]
        result.to_h
      end
      alias results execute
      alias run execute

      # Iterate over all entries from all streams
      #
      # @yield [stream_key, id, fields] Block to call for each entry
      # @return [void]
      #
      # @example
      #   reader.each do |stream, id, fields|
      #     puts "#{stream} - #{id}: #{fields}"
      #   end
      def each
        results = execute
        return if results.nil?

        results.each do |stream_key, entries|
          entries.each do |id, fields|
            yield(stream_key, id, fields)
          end
        end
      end

      # Iterate over entries grouped by stream
      #
      # @yield [stream_key, entries] Block to call for each stream
      # @return [void]
      #
      # @example
      #   reader.each_stream do |stream, entries|
      #     puts "#{stream}: #{entries.length} entries"
      #   end
      def each_stream(&)
        results = execute
        return if results.nil?

        results.each(&)
      end

      private

      # Normalize streams hash to ensure string keys and values
      #
      # @param streams [Hash] Hash of stream_key => start_id
      # @return [Hash] Normalized hash
      def normalize_streams(streams)
        streams.transform_keys(&:to_s).transform_values(&:to_s)
      end
    end
  end
end
