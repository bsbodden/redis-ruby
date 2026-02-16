# frozen_string_literal: true

module RR
  module DSL
    # Builder for creating time series with compaction rules
    #
    # Provides a fluent, idiomatic Ruby API for setting up time series
    # with multiple aggregation levels.
    #
    # @example Create time series with compaction rules
    #   redis.time_series("temperature:sensor1") do
    #     retention 24.hours
    #     labels sensor: "temp", location: "room1"
    #     
    #     compact_to "temperature:hourly", :avg, 1.hour do
    #       retention 30.days
    #     end
    #     
    #     compact_to "temperature:daily", :avg, 1.day do
    #       retention 1.year
    #     end
    #   end
    class TimeSeriesBuilder
      # @private
      def initialize(key, client)
        @key = key
        @client = client
        @retention = nil
        @encoding = nil
        @chunk_size = nil
        @duplicate_policy = nil
        @labels = {}
        @compaction_rules = []
      end

      # Set retention period
      # @param value [Integer, ActiveSupport::Duration] Retention in milliseconds or duration
      def retention(value)
        @retention = duration_to_ms(value)
      end

      # Set encoding
      # @param value [Symbol, String] :compressed or :uncompressed
      def encoding(value)
        @encoding = value.to_s.upcase
      end

      # Set chunk size
      # @param value [Integer] Chunk size in bytes
      def chunk_size(value)
        @chunk_size = value
      end

      # Set duplicate policy
      # @param value [Symbol, String] Policy: :block, :first, :last, :min, :max, :sum
      def duplicate_policy(value)
        @duplicate_policy = value.to_s.upcase
      end

      # Add labels
      # @param labels_hash [Hash] Labels as key-value pairs
      def labels(**labels_hash)
        @labels.merge!(labels_hash)
      end

      # Add a compaction rule
      # @param dest_key [String, Symbol] Destination time series key
      # @param aggregation [Symbol, String] Aggregation type (:avg, :sum, :min, :max, etc.)
      # @param bucket_duration [Integer, ActiveSupport::Duration] Bucket size
      # @param block [Proc] Optional block to configure destination time series
      def compact_to(dest_key, aggregation, bucket_duration, &block)
        dest_key = dest_key.to_s
        aggregation = aggregation.to_s
        bucket_duration = duration_to_ms(bucket_duration)
        
        @compaction_rules << {
          dest_key: dest_key,
          aggregation: aggregation,
          bucket_duration: bucket_duration,
          config: block
        }
      end

      # Alias for compact_to
      alias_method :aggregate_to, :compact_to

      # Create the time series and all compaction rules
      # @private
      def create
        # Create the main time series
        create_opts = {}
        create_opts[:retention] = @retention if @retention
        create_opts[:encoding] = @encoding if @encoding
        create_opts[:chunk_size] = @chunk_size if @chunk_size
        create_opts[:duplicate_policy] = @duplicate_policy if @duplicate_policy
        create_opts[:labels] = @labels unless @labels.empty?

        @client.ts_create(@key, **create_opts)

        # Create destination time series and compaction rules
        @compaction_rules.each do |rule|
          # Create destination time series if config block provided
          if rule[:config]
            dest_builder = TimeSeriesBuilder.new(rule[:dest_key], @client)
            dest_builder.instance_eval(&rule[:config])
            dest_builder.create_without_rules
          end

          # Create the compaction rule
          @client.ts_createrule(
            @key,
            rule[:dest_key],
            rule[:aggregation],
            rule[:bucket_duration]
          )
        end

        @key
      end

      # Create time series without compaction rules (used internally)
      # @private
      def create_without_rules
        create_opts = {}
        create_opts[:retention] = @retention if @retention
        create_opts[:encoding] = @encoding if @encoding
        create_opts[:chunk_size] = @chunk_size if @chunk_size
        create_opts[:duplicate_policy] = @duplicate_policy if @duplicate_policy
        create_opts[:labels] = @labels unless @labels.empty?

        @client.ts_create(@key, **create_opts)
      end

      private

      # Convert duration to milliseconds
      def duration_to_ms(value)
        return value if value.is_a?(Integer)
        
        # Support ActiveSupport::Duration if available
        return (value * 1000).to_i if value.respond_to?(:to_i)
        
        value
      end
    end
  end
end

