# frozen_string_literal: true

module RR
  module DSL
    # Fluent query builder for time series range queries
    #
    # Provides a chainable, idiomatic Ruby API for querying time series data.
    #
    # @example Query with aggregation
    #   redis.ts_query("temperature:sensor1")
    #     .from(1.hour.ago)
    #     .to(Time.now)
    #     .aggregate(:avg, 5.minutes)
    #     .execute
    #
    # @example Query multiple series
    #   redis.ts_query
    #     .filter(sensor: "temp", location: "room1")
    #     .from("-")
    #     .to("+")
    #     .with_labels
    #     .execute
    class TimeSeriesQueryBuilder
      # @private
      def initialize(client, key = nil)
        @client = client
        @key = key
        @from_ts = nil
        @to_ts = nil
        @filters = []
        @latest = false
        @filter_by_ts = nil
        @filter_by_value = nil
        @withlabels = false
        @selected_labels = nil
        @count = nil
        @align = nil
        @aggregation = nil
        @bucket_duration = nil
        @bucket_timestamp = nil
        @empty = false
        @groupby = nil
        @reduce = nil
        @reverse = false
      end

      # Set start timestamp
      # @param timestamp [Integer, Time, String] Start timestamp
      def from(timestamp)
        @from_ts = normalize_timestamp(timestamp)
        self
      end

      # Set end timestamp
      # @param timestamp [Integer, Time, String] End timestamp
      def to(timestamp)
        @to_ts = normalize_timestamp(timestamp)
        self
      end

      # Add label filters (for multi-series queries)
      # @param filters_hash [Hash] Label filters as key-value pairs
      def filter(**filters_hash)
        filters_hash.each do |key, value|
          @filters << "#{key}=#{value}"
        end
        self
      end

      # Add raw filter strings
      # @param filter_strings [Array<String>] Filter strings
      def where(*filter_strings)
        @filters.concat(filter_strings)
        self
      end

      # Return latest values even if replicated
      def latest
        @latest = true
        self
      end

      # Filter by specific timestamps
      # @param timestamps [Array<Integer>] Timestamps to include
      def filter_by_timestamps(*timestamps)
        @filter_by_ts = timestamps
        self
      end

      # Filter by value range
      # @param min [Numeric] Minimum value
      # @param max [Numeric] Maximum value
      def filter_by_value(min, max)
        @filter_by_value = [min, max]
        self
      end

      # Include all labels in results
      def with_labels
        @withlabels = true
        self
      end

      # Include specific labels in results
      # @param labels [Array<Symbol, String>] Label names to include
      def select_labels(*labels)
        @selected_labels = labels.map(&:to_s)
        self
      end

      # Limit number of results
      # @param n [Integer] Maximum number of samples
      def limit(n)
        @count = n
        self
      end

      # Align timestamps
      # @param timestamp [Integer, Time, String] Alignment timestamp
      def align(timestamp)
        @align = normalize_timestamp(timestamp)
        self
      end

      # Add aggregation
      # @param type [Symbol, String] Aggregation type (:avg, :sum, :min, :max, etc.)
      # @param bucket_duration [Integer, ActiveSupport::Duration] Bucket size
      # @param bucket_timestamp [Symbol] Bucket timestamp (:start, :end, :mid)
      def aggregate(type, bucket_duration, bucket_timestamp: nil)
        @aggregation = type.to_s
        @bucket_duration = duration_to_ms(bucket_duration)
        @bucket_timestamp = bucket_timestamp.to_s if bucket_timestamp
        self
      end

      # Include empty buckets in aggregation
      def include_empty
        @empty = true
        self
      end

      # Group by label
      # @param label [Symbol, String] Label to group by
      # @param reduce_func [Symbol, String] Reduce function (:sum, :min, :max, etc.)
      def group_by(label, reduce_func)
        @groupby = label.to_s
        @reduce = reduce_func.to_s
        self
      end

      # Reverse the order of results
      def reverse
        @reverse = true
        self
      end

      # Execute the query
      # @return [Array] Query results
      def execute
        raise ArgumentError, "from timestamp is required" unless @from_ts
        raise ArgumentError, "to timestamp is required" unless @to_ts

        if @key
          # Single series query
          execute_single_series
        else
          # Multi-series query
          raise ArgumentError, "filters are required for multi-series query" if @filters.empty?
          execute_multi_series
        end
      end

      private

      def execute_single_series
        method = @reverse ? :ts_revrange : :ts_range
        
        @client.send(
          method,
          @key,
          @from_ts,
          @to_ts,
          latest: @latest,
          filter_by_ts: @filter_by_ts,
          filter_by_value: @filter_by_value,
          count: @count,
          align: @align,
          aggregation: @aggregation,
          bucket_duration: @bucket_duration,
          bucket_timestamp: @bucket_timestamp,
          empty: @empty
        )
      end

      def execute_multi_series
        method = @reverse ? :ts_mrevrange : :ts_mrange
        
        @client.send(
          method,
          @from_ts,
          @to_ts,
          @filters,
          latest: @latest,
          filter_by_ts: @filter_by_ts,
          filter_by_value: @filter_by_value,
          withlabels: @withlabels,
          selected_labels: @selected_labels,
          count: @count,
          align: @align,
          aggregation: @aggregation,
          bucket_duration: @bucket_duration,
          bucket_timestamp: @bucket_timestamp,
          empty: @empty,
          groupby: @groupby,
          reduce: @reduce
        )
      end

      def normalize_timestamp(timestamp)
        return timestamp if timestamp.is_a?(String) # "-", "+", etc.
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

