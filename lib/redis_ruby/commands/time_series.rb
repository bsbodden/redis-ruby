# frozen_string_literal: true

require_relative "../dsl/time_series_builder"
require_relative "../dsl/time_series_proxy"
require_relative "../dsl/time_series_query_builder"

module RR
  module Commands
    # Redis TimeSeries commands module
    #
    # Provides time series data capabilities:
    # - High-volume data ingestion
    # - Aggregation and downsampling
    # - Range queries with aggregations
    # - Compaction rules
    #
    # @see https://redis.io/docs/data-types/timeseries/
    module TimeSeries
      # Frozen command constants to avoid string allocations
      CMD_TS_CREATE = "TS.CREATE"
      CMD_TS_DEL = "TS.DEL"
      CMD_TS_ALTER = "TS.ALTER"
      CMD_TS_ADD = "TS.ADD"
      CMD_TS_MADD = "TS.MADD"
      CMD_TS_INCRBY = "TS.INCRBY"
      CMD_TS_DECRBY = "TS.DECRBY"
      CMD_TS_CREATERULE = "TS.CREATERULE"
      CMD_TS_DELETERULE = "TS.DELETERULE"
      CMD_TS_RANGE = "TS.RANGE"
      CMD_TS_REVRANGE = "TS.REVRANGE"
      CMD_TS_MRANGE = "TS.MRANGE"
      CMD_TS_MREVRANGE = "TS.MREVRANGE"
      CMD_TS_GET = "TS.GET"
      CMD_TS_MGET = "TS.MGET"
      CMD_TS_INFO = "TS.INFO"
      CMD_TS_QUERYINDEX = "TS.QUERYINDEX"

      # Frozen options
      OPT_RETENTION = "RETENTION"
      OPT_ENCODING = "ENCODING"
      OPT_CHUNK_SIZE = "CHUNK_SIZE"
      OPT_DUPLICATE_POLICY = "DUPLICATE_POLICY"
      OPT_ON_DUPLICATE = "ON_DUPLICATE"
      OPT_LABELS = "LABELS"
      OPT_IGNORE = "IGNORE"
      OPT_AGGREGATION = "AGGREGATION"
      OPT_LATEST = "LATEST"
      OPT_WITHLABELS = "WITHLABELS"
      OPT_SELECTED_LABELS = "SELECTED_LABELS"
      OPT_FILTER = "FILTER"
      OPT_FILTER_BY_TS = "FILTER_BY_TS"
      OPT_FILTER_BY_VALUE = "FILTER_BY_VALUE"
      OPT_COUNT = "COUNT"
      OPT_ALIGN = "ALIGN"
      OPT_BUCKETTIMESTAMP = "BUCKETTIMESTAMP"
      OPT_EMPTY = "EMPTY"
      OPT_GROUPBY = "GROUPBY"
      OPT_REDUCE = "REDUCE"
      OPT_TIMESTAMP = "TIMESTAMP"
      OPT_DEBUG = "DEBUG"
      # Create a new time series
      #
      # @param key [String] Time series key
      # @param retention [Integer] Max retention in milliseconds
      # @param encoding [String] "COMPRESSED" or "UNCOMPRESSED"
      # @param chunk_size [Integer] Initial allocation size in bytes
      # @param duplicate_policy [String] Policy on duplicate timestamps
      # @param labels [Hash] Key-value labels for filtering
      # @return [String] "OK"
      #
      # @example Create time series with labels
      #   redis.ts_create("temp:sensor1",
      #     retention: 86400000,
      #     labels: { sensor: "temp", location: "room1" })
      def ts_create(key, retention: nil, encoding: nil, chunk_size: nil,
                    duplicate_policy: nil, labels: nil, ignore_max_time_diff: nil,
                    ignore_max_val_diff: nil)
        args = [key]
        append_ts_create_options(args, retention: retention, encoding: encoding,
                                       chunk_size: chunk_size,
                                       duplicate_policy: duplicate_policy)
        build_ts_ignore_and_labels(args,
                                   ignore_max_time_diff: ignore_max_time_diff,
                                   ignore_max_val_diff: ignore_max_val_diff,
                                   labels: labels)
        call(CMD_TS_CREATE, *args)
      end

      # Delete a time series
      #
      # @param key [String] Time series key
      # @param from_ts [Integer] Start timestamp
      # @param to_ts [Integer] End timestamp
      # @return [Integer] Number of samples deleted
      def ts_del(key, from_ts, to_ts)
        call_3args(CMD_TS_DEL, key, from_ts, to_ts)
      end

      # Alter a time series
      #
      # @param key [String] Time series key
      # @param retention [Integer] New retention
      # @param chunk_size [Integer] New chunk size
      # @param duplicate_policy [String] New duplicate policy
      # @param labels [Hash] New labels (replaces existing)
      # @return [String] "OK"
      def ts_alter(key, retention: nil, chunk_size: nil, duplicate_policy: nil, labels: nil,
                   ignore_max_time_diff: nil, ignore_max_val_diff: nil)
        args = [key]
        args.push(OPT_RETENTION, retention) if retention
        args.push(OPT_CHUNK_SIZE, chunk_size) if chunk_size
        args.push(OPT_DUPLICATE_POLICY, duplicate_policy) if duplicate_policy
        build_ts_ignore_and_labels(args,
                                   ignore_max_time_diff: ignore_max_time_diff,
                                   ignore_max_val_diff: ignore_max_val_diff,
                                   labels: labels)
        call(CMD_TS_ALTER, *args)
      end

      # Add a sample to time series
      #
      # @param key [String] Time series key
      # @param timestamp [Integer, String] Timestamp (milliseconds) or "*" for auto
      # @param value [Float] Sample value
      # @param retention [Integer] Override retention
      # @param encoding [String] Override encoding
      # @param chunk_size [Integer] Override chunk size
      # @param on_duplicate [String] Override duplicate policy
      # @param labels [Hash] Labels (creates series if needed)
      # @return [Integer] Timestamp of added sample
      #
      # @example Add sample with auto timestamp
      #   redis.ts_add("temp:sensor1", "*", 23.5)
      #
      # @example Add sample with specific timestamp
      #   redis.ts_add("temp:sensor1", 1640000000000, 23.5)
      def ts_add(key, timestamp, value, retention: nil, encoding: nil,
                 chunk_size: nil, on_duplicate: nil, labels: nil,
                 ignore_max_time_diff: nil, ignore_max_val_diff: nil)
        args = [key, timestamp, value]
        append_ts_add_options(args, retention: retention, encoding: encoding,
                                    chunk_size: chunk_size, on_duplicate: on_duplicate)
        build_ts_ignore_and_labels(args,
                                   ignore_max_time_diff: ignore_max_time_diff,
                                   ignore_max_val_diff: ignore_max_val_diff,
                                   labels: labels)
        call(CMD_TS_ADD, *args)
      end

      # Add multiple samples atomically
      #
      # @param samples [Array<Array>] Array of [key, timestamp, value] triples
      # @return [Array<Integer>] Timestamps of added samples
      #
      # @example Add multiple samples
      #   redis.ts_madd(
      #     ["temp:1", "*", 23.5],
      #     ["temp:2", "*", 24.0],
      #     ["temp:3", "*", 22.8]
      #   )
      def ts_madd(*samples)
        args = samples.flatten
        call(CMD_TS_MADD, *args)
      end

      # Increment the latest value
      #
      # @param key [String] Time series key
      # @param value [Float] Value to add
      # @param timestamp [Integer, String] Timestamp or "*"
      # @param retention [Integer] Override retention
      # @param labels [Hash] Labels
      # @return [Integer] Timestamp of sample
      def ts_incrby(key, value, timestamp: nil, retention: nil, labels: nil,
                    chunk_size: nil, ignore_max_time_diff: nil, ignore_max_val_diff: nil)
        # Fast path: no options
        if timestamp.nil? && retention.nil? && labels.nil? && chunk_size.nil? &&
           ignore_max_time_diff.nil? && ignore_max_val_diff.nil?
          return call_2args(CMD_TS_INCRBY, key, value)
        end

        args = build_ts_incrby_decrby_args(key, value,
                                           timestamp: timestamp, retention: retention,
                                           chunk_size: chunk_size,
                                           ignore_max_time_diff: ignore_max_time_diff,
                                           ignore_max_val_diff: ignore_max_val_diff,
                                           labels: labels)
        call(CMD_TS_INCRBY, *args)
      end

      # Decrement the latest value
      #
      # @param key [String] Time series key
      # @param value [Float] Value to subtract
      # @param timestamp [Integer, String] Timestamp or "*"
      # @param retention [Integer] Override retention
      # @param labels [Hash] Labels
      # @return [Integer] Timestamp of sample
      def ts_decrby(key, value, timestamp: nil, retention: nil, labels: nil,
                    chunk_size: nil, ignore_max_time_diff: nil, ignore_max_val_diff: nil)
        # Fast path: no options
        if timestamp.nil? && retention.nil? && labels.nil? && chunk_size.nil? &&
           ignore_max_time_diff.nil? && ignore_max_val_diff.nil?
          return call_2args(CMD_TS_DECRBY, key, value)
        end

        args = build_ts_incrby_decrby_args(key, value,
                                           timestamp: timestamp, retention: retention,
                                           chunk_size: chunk_size,
                                           ignore_max_time_diff: ignore_max_time_diff,
                                           ignore_max_val_diff: ignore_max_val_diff,
                                           labels: labels)
        call(CMD_TS_DECRBY, *args)
      end

      # Create a compaction rule
      #
      # @param source_key [String] Source time series
      # @param dest_key [String] Destination time series
      # @param aggregation [String] Aggregation type
      # @param bucket_duration [Integer] Bucket size in milliseconds
      # @param align_timestamp [Integer] Alignment timestamp
      # @return [String] "OK"
      #
      # @example Create hourly average compaction
      #   redis.ts_createrule("temp:raw", "temp:hourly", "avg", 3600000)
      def ts_createrule(source_key, dest_key, aggregation, bucket_duration, align_timestamp: nil)
        args = [source_key, dest_key, OPT_AGGREGATION, aggregation, bucket_duration]
        args.push(align_timestamp) if align_timestamp
        call(CMD_TS_CREATERULE, *args)
      end

      # Delete a compaction rule
      #
      # @param source_key [String] Source time series
      # @param dest_key [String] Destination time series
      # @return [String] "OK"
      def ts_deleterule(source_key, dest_key)
        call_2args(CMD_TS_DELETERULE, source_key, dest_key)
      end

      # Query a range of samples
      #
      # @param key [String] Time series key
      # @param from_ts [Integer, String] Start timestamp or "-" for oldest
      # @param to_ts [Integer, String] End timestamp or "+" for newest
      # @param latest [Boolean] Report latest samples
      # @param filter_by_ts [Array<Integer>] Filter by timestamps
      # @param filter_by_value [Array<Float>] Filter by value range [min, max]
      # @param count [Integer] Max samples to return
      # @param align [Integer, String] Bucket alignment
      # @param aggregation [String] Aggregation type
      # @param bucket_duration [Integer] Bucket size
      # @param bucket_timestamp [String] "start", "end", or "mid"
      # @param empty [Boolean] Report empty buckets
      # @return [Array] Array of [timestamp, value] pairs
      #
      # @example Get all samples
      #   redis.ts_range("temp:sensor1", "-", "+")
      #
      # @example Get with hourly average aggregation
      #   redis.ts_range("temp:sensor1", "-", "+",
      #     aggregation: "avg", bucket_duration: 3600000)
      def ts_range(key, from_ts, to_ts, latest: false, filter_by_ts: nil,
                   filter_by_value: nil, count: nil, align: nil,
                   aggregation: nil, bucket_duration: nil, bucket_timestamp: nil,
                   empty: false)
        # Fast path: no options
        if !latest && filter_by_ts.nil? && filter_by_value.nil? && count.nil? &&
           align.nil? && aggregation.nil?
          return call_3args(CMD_TS_RANGE, key, from_ts, to_ts)
        end

        args = build_range_args(key, from_ts, to_ts,
                                latest: latest, filter_by_ts: filter_by_ts,
                                filter_by_value: filter_by_value, count: count,
                                align: align, aggregation: aggregation,
                                bucket_duration: bucket_duration,
                                bucket_timestamp: bucket_timestamp, empty: empty)
        call(CMD_TS_RANGE, *args)
      end

      # Query range in reverse order
      #
      # @param key [String] Time series key
      # @param from_ts [Integer, String] Start timestamp
      # @param to_ts [Integer, String] End timestamp
      # @param (see #ts_range)
      # @return [Array] Array of [timestamp, value] pairs (newest first)
      def ts_revrange(key, from_ts, to_ts, latest: false, filter_by_ts: nil,
                      filter_by_value: nil, count: nil, align: nil,
                      aggregation: nil, bucket_duration: nil, bucket_timestamp: nil,
                      empty: false)
        # Fast path: no options
        if !latest && filter_by_ts.nil? && filter_by_value.nil? && count.nil? &&
           align.nil? && aggregation.nil?
          return call_3args(CMD_TS_REVRANGE, key, from_ts, to_ts)
        end

        args = build_range_args(key, from_ts, to_ts,
                                latest: latest, filter_by_ts: filter_by_ts,
                                filter_by_value: filter_by_value, count: count,
                                align: align, aggregation: aggregation,
                                bucket_duration: bucket_duration,
                                bucket_timestamp: bucket_timestamp, empty: empty)
        call(CMD_TS_REVRANGE, *args)
      end

      # Query range across multiple time series
      #
      # @param from_ts [Integer, String] Start timestamp
      # @param to_ts [Integer, String] End timestamp
      # @param filters [Array<String>] Label filters
      # @param latest [Boolean] Report latest samples
      # @param filter_by_ts [Array<Integer>] Filter by timestamps
      # @param filter_by_value [Array<Float>] Filter by value range
      # @param withlabels [Boolean] Include labels in response
      # @param selected_labels [Array<String>] Specific labels to include
      # @param count [Integer] Max samples per series
      # @param align [Integer, String] Bucket alignment
      # @param aggregation [String] Aggregation type
      # @param bucket_duration [Integer] Bucket size
      # @param bucket_timestamp [String] Bucket timestamp position
      # @param empty [Boolean] Report empty buckets
      # @param groupby [String] Group by label
      # @param reduce [String] Reduce function for groupby
      # @return [Array] Array of [key, labels, samples] for each series
      #
      # @example Query by label filter
      #   redis.ts_mrange("-", "+", ["sensor=temp", "location=room1"])
      def ts_mrange(from_ts, to_ts, filters, latest: false, filter_by_ts: nil,
                    filter_by_value: nil, withlabels: false, selected_labels: nil,
                    count: nil, align: nil, aggregation: nil, bucket_duration: nil,
                    bucket_timestamp: nil, empty: false, groupby: nil, reduce: nil)
        args = build_mrange_args(from_ts, to_ts, filters,
                                 latest: latest, filter_by_ts: filter_by_ts,
                                 filter_by_value: filter_by_value, withlabels: withlabels,
                                 selected_labels: selected_labels, count: count,
                                 align: align, aggregation: aggregation,
                                 bucket_duration: bucket_duration,
                                 bucket_timestamp: bucket_timestamp, empty: empty,
                                 groupby: groupby, reduce: reduce)
        call(CMD_TS_MRANGE, *args)
      end

      # Query range in reverse across multiple series
      #
      # @param from_ts [Integer, String] Start timestamp
      # @param to_ts [Integer, String] End timestamp
      # @param filters [Array<String>] Label filters
      # @param (see #ts_mrange)
      # @return [Array] Array of [key, labels, samples] (newest first)
      def ts_mrevrange(from_ts, to_ts, filters, latest: false, filter_by_ts: nil,
                       filter_by_value: nil, withlabels: false, selected_labels: nil,
                       count: nil, align: nil, aggregation: nil, bucket_duration: nil,
                       bucket_timestamp: nil, empty: false, groupby: nil, reduce: nil)
        args = build_mrange_args(from_ts, to_ts, filters,
                                 latest: latest, filter_by_ts: filter_by_ts,
                                 filter_by_value: filter_by_value, withlabels: withlabels,
                                 selected_labels: selected_labels, count: count,
                                 align: align, aggregation: aggregation,
                                 bucket_duration: bucket_duration,
                                 bucket_timestamp: bucket_timestamp, empty: empty,
                                 groupby: groupby, reduce: reduce)
        call(CMD_TS_MREVRANGE, *args)
      end

      # Get the latest sample
      #
      # @param key [String] Time series key
      # @param latest [Boolean] Return latest even if replicated
      # @return [Array] [timestamp, value] or nil
      def ts_get(key, latest: false)
        # Fast path: no options
        return call_1arg(CMD_TS_GET, key) unless latest

        call(CMD_TS_GET, key, OPT_LATEST)
      end

      # Get latest samples from multiple series
      #
      # @param filters [Array<String>] Label filters
      # @param latest [Boolean] Return latest even if replicated
      # @param withlabels [Boolean] Include labels
      # @param selected_labels [Array<String>] Specific labels to include
      # @return [Array] Array of [key, labels, [timestamp, value]]
      def ts_mget(filters, latest: false, withlabels: false, selected_labels: nil)
        args = []
        args << OPT_LATEST if latest
        args << OPT_WITHLABELS if withlabels
        args.push(OPT_SELECTED_LABELS, *selected_labels) if selected_labels
        args.push(OPT_FILTER, *filters)
        call(CMD_TS_MGET, *args)
      end

      # Get time series information
      #
      # @param key [String] Time series key
      # @param debug [Boolean] Include debug info
      # @return [Hash] Time series metadata
      def ts_info(key, debug: false)
        # Fast path: no options
        result = if debug
                   call(CMD_TS_INFO, key, OPT_DEBUG)
                 else
                   call_1arg(CMD_TS_INFO, key)
                 end
        return result if result.is_a?(Hash)

        result.each_slice(2).to_h
      end

      # Query time series by filters
      #
      # @param filters [Array<String>] Label filters
      # @return [Array<String>] Matching time series keys
      #
      # @example Find all temperature sensors
      #   redis.ts_queryindex("sensor=temp")
      def ts_queryindex(*filters)
        call(CMD_TS_QUERYINDEX, *filters)
      end

      # Idiomatic Ruby API: Create time series with DSL
      #
      # @param key [String, Symbol] Time series key
      # @param block [Proc] Configuration block
      # @return [String] Time series key
      #
      # @example Create time series with compaction rules
      #   redis.time_series("temperature:sensor1") do
      #     retention 24.hours
      #     labels sensor: "temp", location: "room1"
      #
      #     compact_to "temperature:hourly", :avg, 1.hour do
      #       retention 30.days
      #     end
      #   end
      def time_series(key, &block)
        builder = RR::DSL::TimeSeriesBuilder.new(key.to_s, self)
        builder.instance_eval(&block)
        builder.create
      end

      # Idiomatic Ruby API: Chainable time series proxy
      #
      # @param key_parts [Array<String, Symbol>] Key parts to join with ":"
      # @return [TimeSeriesProxy] Chainable proxy
      #
      # @example Add samples with chaining
      #   redis.ts("temperature:sensor1")
      #     .add(Time.now, 23.5)
      #     .add(Time.now + 60, 24.0)
      #
      # @example Query with fluent API
      #   redis.ts("temperature:sensor1")
      #     .range(from: 1.hour.ago, to: Time.now)
      def ts(*key_parts)
        RR::DSL::TimeSeriesProxy.new(self, *key_parts)
      end

      # Idiomatic Ruby API: Fluent query builder
      #
      # @return [TimeSeriesQueryBuilder] Query builder for chaining
      #
      # @example Query multiple series
      #   redis.ts_query
      #     .filter(sensor: "temp", location: "room1")
      #     .from("-")
      #     .to("+")
      #     .with_labels
      #     .execute
      def ts_query(key = nil)
        RR::DSL::TimeSeriesQueryBuilder.new(self, key)
      end

      private

      # Build arguments for TS.RANGE/TS.REVRANGE commands
      # @private
      def build_range_args(key, from_ts, to_ts, latest:, filter_by_ts:, filter_by_value:,
                           count:, align:, aggregation:, bucket_duration:,
                           bucket_timestamp:, empty:)
        args = [key, from_ts, to_ts]
        append_ts_base_filters(args, latest: latest, filter_by_ts: filter_by_ts,
                                     filter_by_value: filter_by_value)
        append_ts_count_and_align(args, count: count, align: align)
        append_ts_aggregation(args, aggregation: aggregation,
                                    bucket_duration: bucket_duration,
                                    bucket_timestamp: bucket_timestamp, empty: empty)
        args
      end

      # Build arguments for TS.MRANGE/TS.MREVRANGE commands
      # @private
      def build_mrange_args(from_ts, to_ts, filters, latest:, filter_by_ts:,
                            filter_by_value:, withlabels:, selected_labels:,
                            count:, align:, aggregation:, bucket_duration:,
                            bucket_timestamp:, empty:, groupby:, reduce:)
        args = [from_ts, to_ts]
        append_ts_base_filters(args, latest: latest, filter_by_ts: filter_by_ts,
                                     filter_by_value: filter_by_value)
        append_mrange_label_options(args, withlabels: withlabels,
                                          selected_labels: selected_labels)
        append_ts_count_and_align(args, count: count, align: align)
        append_ts_aggregation(args, aggregation: aggregation,
                                    bucket_duration: bucket_duration,
                                    bucket_timestamp: bucket_timestamp, empty: empty)
        args.push(OPT_FILTER, *filters)
        args.push(OPT_GROUPBY, groupby, OPT_REDUCE, reduce) if groupby
        args
      end

      # Append LATEST and FILTER_BY_* options for range commands
      # @private
      def append_ts_base_filters(args, latest:, filter_by_ts:, filter_by_value:)
        args << OPT_LATEST if latest
        args.push(OPT_FILTER_BY_TS, *filter_by_ts) if filter_by_ts
        args.push(OPT_FILTER_BY_VALUE, filter_by_value[0], filter_by_value[1]) if filter_by_value
      end

      # Append COUNT and ALIGN options for range commands
      # @private
      def append_ts_count_and_align(args, count:, align:)
        args.push(OPT_COUNT, count) if count
        args.push(OPT_ALIGN, align) if align
      end

      # Append label options for MRANGE commands
      # @private
      def append_mrange_label_options(args, withlabels:, selected_labels:)
        args << OPT_WITHLABELS if withlabels
        args.push(OPT_SELECTED_LABELS, *selected_labels) if selected_labels
      end

      # Append aggregation options for range commands
      # @private
      def append_ts_aggregation(args, aggregation:, bucket_duration:, bucket_timestamp:, empty:)
        return unless aggregation

        args.push(OPT_AGGREGATION, aggregation, bucket_duration)
        args.push(OPT_BUCKETTIMESTAMP, bucket_timestamp) if bucket_timestamp
        args << OPT_EMPTY if empty
      end

      # Append options specific to TS.CREATE
      # @private
      def append_ts_create_options(args, retention:, encoding:, chunk_size:, duplicate_policy:)
        args.push(OPT_RETENTION, retention) if retention
        args.push(OPT_ENCODING, encoding) if encoding
        args.push(OPT_CHUNK_SIZE, chunk_size) if chunk_size
        args.push(OPT_DUPLICATE_POLICY, duplicate_policy) if duplicate_policy
      end

      # Append options specific to TS.ADD
      # @private
      def append_ts_add_options(args, retention:, encoding:, chunk_size:, on_duplicate:)
        args.push(OPT_RETENTION, retention) if retention
        args.push(OPT_ENCODING, encoding) if encoding
        args.push(OPT_CHUNK_SIZE, chunk_size) if chunk_size
        args.push(OPT_ON_DUPLICATE, on_duplicate) if on_duplicate
      end

      # Build arguments for TS.INCRBY/TS.DECRBY commands
      # @private
      def build_ts_incrby_decrby_args(key, value, timestamp:, retention:, chunk_size:,
                                      ignore_max_time_diff:, ignore_max_val_diff:, labels:)
        args = [key, value]
        args.push(OPT_TIMESTAMP, timestamp) if timestamp
        args.push(OPT_RETENTION, retention) if retention
        args.push(OPT_CHUNK_SIZE, chunk_size) if chunk_size
        build_ts_ignore_and_labels(args,
                                   ignore_max_time_diff: ignore_max_time_diff,
                                   ignore_max_val_diff: ignore_max_val_diff,
                                   labels: labels)
        args
      end

      # Build IGNORE and LABELS arguments common to multiple TS commands
      # @private
      def build_ts_ignore_and_labels(args, ignore_max_time_diff:, ignore_max_val_diff:, labels:)
        if ignore_max_time_diff || ignore_max_val_diff
          args << OPT_IGNORE
          args << ignore_max_time_diff if ignore_max_time_diff
          args << ignore_max_val_diff if ignore_max_val_diff
        end

        return unless labels

        args << OPT_LABELS
        labels.each { |k, v| args.push(k.to_s, v.to_s) }
      end
    end
  end
end
