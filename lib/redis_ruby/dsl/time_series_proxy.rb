# frozen_string_literal: true

module RR
  module DSL
    # Chainable proxy for time series operations
    #
    # Provides a fluent, idiomatic Ruby API for working with a specific time series.
    #
    # @example Add samples with chaining
    #   redis.ts("temperature:sensor1")
    #     .add(Time.now, 23.5)
    #     .add(Time.now + 60, 24.0)
    #     .add(Time.now + 120, 23.8)
    #
    # @example Query with fluent API
    #   redis.ts("temperature:sensor1")
    #     .range(from: 1.hour.ago, to: Time.now)
    #     .aggregate(:avg, 5.minutes)
    class TimeSeriesProxy
      # @private
      def initialize(client, *key_parts)
        @client = client
        @key = key_parts.map(&:to_s).join(":")
      end

      # Add a sample
      # @param timestamp [Integer, Time, String] Timestamp or "*" for auto
      # @param value [Numeric] Sample value
      # @param options [Hash] Additional options
      # @return [TimeSeriesProxy] self for chaining
      def add(timestamp, value, **)
        timestamp = normalize_timestamp(timestamp)
        @client.ts_add(@key, timestamp, value, **)
        self
      end

      # Increment the latest value
      # @param value [Numeric] Value to add
      # @param options [Hash] Additional options
      # @return [TimeSeriesProxy] self for chaining
      def increment(value = 1, **)
        @client.ts_incrby(@key, value, **)
        self
      end
      alias incr increment

      # Decrement the latest value
      # @param value [Numeric] Value to subtract
      # @param options [Hash] Additional options
      # @return [TimeSeriesProxy] self for chaining
      def decrement(value = 1, **)
        @client.ts_decrby(@key, value, **)
        self
      end
      alias decr decrement

      # Get the latest sample
      # @param latest [Boolean] Return latest even if replicated
      # @return [Array] [timestamp, value] or nil
      def get(latest: false)
        @client.ts_get(@key, latest: latest)
      end
      alias latest get

      # Query range with fluent builder
      # @param from [Integer, Time, String] Start timestamp
      # @param to [Integer, Time, String] End timestamp
      # @return [TimeSeriesQueryBuilder] Query builder for chaining
      def range(from: nil, to: nil)
        require_relative "time_series_query_builder"
        builder = TimeSeriesQueryBuilder.new(@client, @key)
        builder.from(from) if from
        builder.to(to) if to
        builder
      end

      # Query range in reverse
      # @param from [Integer, Time, String] Start timestamp
      # @param to [Integer, Time, String] End timestamp
      # @return [TimeSeriesQueryBuilder] Query builder for chaining
      def reverse_range(from: nil, to: nil)
        require_relative "time_series_query_builder"
        builder = TimeSeriesQueryBuilder.new(@client, @key)
        builder.from(from) if from
        builder.to(to) if to
        builder.reverse
      end

      # Get time series information
      # @param debug [Boolean] Include debug info
      # @return [Hash] Time series metadata
      def info(debug: false)
        @client.ts_info(@key, debug: debug)
      end

      # Delete samples in time range
      # @param from [Integer, Time, String] Start timestamp
      # @param to [Integer, Time, String] End timestamp
      # @return [Integer] Number of samples deleted
      def delete(from:, to:)
        from_timestamp = normalize_timestamp(from)
        to_timestamp = normalize_timestamp(to)
        @client.ts_del(@key, from_timestamp, to_timestamp)
      end

      # Alter time series configuration
      # @param options [Hash] Configuration options
      # @return [TimeSeriesProxy] self for chaining
      def alter(**)
        @client.ts_alter(@key, **)
        self
      end

      # Create a compaction rule
      # @param dest_key [String, Symbol] Destination time series
      # @param aggregation [Symbol, String] Aggregation type
      # @param bucket_duration [Integer, ActiveSupport::Duration] Bucket size
      # @return [TimeSeriesProxy] self for chaining
      def compact_to(dest_key, aggregation, bucket_duration)
        dest_key = dest_key.to_s
        aggregation = aggregation.to_s
        bucket_duration = duration_to_ms(bucket_duration)
        @client.ts_createrule(@key, dest_key, aggregation, bucket_duration)
        self
      end
      alias aggregate_to compact_to

      # Delete a compaction rule
      # @param dest_key [String, Symbol] Destination time series
      # @return [TimeSeriesProxy] self for chaining
      def delete_rule(dest_key)
        @client.ts_deleterule(@key, dest_key.to_s)
        self
      end

      # Add multiple samples at once
      # @param samples [Array<Array>] Array of [timestamp, value] pairs
      # @return [TimeSeriesProxy] self for chaining
      def add_many(*samples)
        formatted_samples = samples.map do |timestamp, value|
          [@key, normalize_timestamp(timestamp), value]
        end
        @client.ts_madd(*formatted_samples)
        self
      end

      private

      def normalize_timestamp(timestamp)
        return timestamp if timestamp.is_a?(String) # "*", "-", "+", etc.
        return (timestamp.to_f * 1000).to_i if timestamp.is_a?(Time)

        timestamp
      end

      def duration_to_ms(value)
        return value if value.is_a?(Integer)
        return (value * 1000).to_i if value.respond_to?(:to_i)

        value
      end
    end
  end
end
