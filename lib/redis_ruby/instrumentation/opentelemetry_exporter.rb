# frozen_string_literal: true

module RR
  class Instrumentation
    # OpenTelemetry metrics exporter for Redis instrumentation
    #
    # Exports metrics in OpenTelemetry format for integration with OTLP collectors.
    # This exporter provides a simple hash-based format that can be easily converted
    # to OpenTelemetry protocol buffers or JSON.
    #
    # @example Basic usage
    #   instrumentation = RR::Instrumentation.new
    #   exporter = RR::Instrumentation::OpenTelemetryExporter.new(instrumentation)
    #   
    #   # Get metrics in OpenTelemetry format
    #   metrics = exporter.export
    #   # => { resource_metrics: [...] }
    #
    # @example With custom service name
    #   exporter = RR::Instrumentation::OpenTelemetryExporter.new(
    #     instrumentation,
    #     service_name: "my-app",
    #     service_version: "1.0.0"
    #   )
    #
    class OpenTelemetryExporter
      attr_reader :instrumentation, :service_name, :service_version

      # Initialize exporter
      #
      # @param instrumentation [RR::Instrumentation] Instrumentation instance
      # @param service_name [String] Service name for resource attributes
      # @param service_version [String] Service version for resource attributes
      def initialize(instrumentation, service_name: "redis-ruby", service_version: "1.0.0")
        @instrumentation = instrumentation
        @service_name = service_name
        @service_version = service_version
      end

      # Export metrics in OpenTelemetry format
      #
      # @return [Hash] OpenTelemetry-formatted metrics
      def export
        snapshot = @instrumentation.snapshot
        timestamp = (Time.now.to_f * 1_000_000_000).to_i # nanoseconds

        {
          resource_metrics: [
            {
              resource: {
                attributes: [
                  { key: "service.name", value: { string_value: @service_name } },
                  { key: "service.version", value: { string_value: @service_version } },
                  { key: "telemetry.sdk.name", value: { string_value: "redis-ruby" } },
                  { key: "telemetry.sdk.language", value: { string_value: "ruby" } }
                ]
              },
              scope_metrics: [
                {
                  scope: {
                    name: "redis-ruby-instrumentation",
                    version: "1.0.0"
                  },
                  metrics: build_metrics(snapshot, timestamp)
                }
              ]
            }
          ]
        }
      end

      private

      def build_metrics(snapshot, timestamp)
        metrics = []

        # Total commands counter
        metrics << counter_metric(
          "redis.commands.total",
          "Total number of Redis commands executed",
          snapshot[:total_commands],
          timestamp
        )

        # Per-command metrics
        snapshot[:commands].each do |cmd, data|
          metrics << counter_metric(
            "redis.command.count",
            "Number of times command was executed",
            data[:count],
            timestamp,
            { "command" => cmd }
          )

          metrics << counter_metric(
            "redis.command.duration",
            "Total time spent executing command",
            data[:total_time],
            timestamp,
            { "command" => cmd, "unit" => "seconds" }
          )

          metrics << counter_metric(
            "redis.command.errors",
            "Number of errors for command",
            data[:errors],
            timestamp,
            { "command" => cmd }
          )

          metrics << counter_metric(
            "redis.command.success",
            "Number of successful executions for command",
            data[:success],
            timestamp,
            { "command" => cmd }
          )
        end

        # Pipeline metrics
        metrics << counter_metric(
          "redis.pipelines.total",
          "Total number of pipelines executed",
          snapshot[:pipelines][:count],
          timestamp
        )

        metrics << counter_metric(
          "redis.pipeline.duration",
          "Total time spent in pipelines",
          snapshot[:pipelines][:total_time],
          timestamp,
          { "unit" => "seconds" }
        )

        # Transaction metrics
        metrics << counter_metric(
          "redis.transactions.total",
          "Total number of transactions executed",
          snapshot[:transactions][:count],
          timestamp
        )

        metrics << counter_metric(
          "redis.transaction.duration",
          "Total time spent in transactions",
          snapshot[:transactions][:total_time],
          timestamp,
          { "unit" => "seconds" }
        )

        # Pool metrics
        pool = snapshot[:pool]
        metrics << counter_metric(
          "redis.pool.connections.created",
          "Total connections created",
          pool[:connection_creates],
          timestamp
        )

        metrics << gauge_metric(
          "redis.pool.connections.active",
          "Current number of active connections",
          pool[:active_connections],
          timestamp
        )

        metrics << gauge_metric(
          "redis.pool.connections.idle",
          "Current number of idle connections",
          pool[:idle_connections],
          timestamp
        )

        metrics << counter_metric(
          "redis.pool.exhaustions",
          "Number of times pool was exhausted",
          pool[:pool_exhaustions],
          timestamp
        )

        metrics
      end

      def counter_metric(name, description, value, timestamp, attributes = {})
        {
          name: name,
          description: description,
          unit: "1",
          sum: {
            data_points: [
              {
                attributes: attributes.map { |k, v| { key: k, value: { string_value: v.to_s } } },
                start_time_unix_nano: timestamp,
                time_unix_nano: timestamp,
                as_int: value.is_a?(Integer) ? value : nil,
                as_double: value.is_a?(Float) ? value : nil
              }
            ],
            aggregation_temporality: "AGGREGATION_TEMPORALITY_CUMULATIVE",
            is_monotonic: true
          }
        }
      end

      def gauge_metric(name, description, value, timestamp, attributes = {})
        {
          name: name,
          description: description,
          unit: "1",
          gauge: {
            data_points: [
              {
                attributes: attributes.map { |k, v| { key: k, value: { string_value: v.to_s } } },
                time_unix_nano: timestamp,
                as_int: value.is_a?(Integer) ? value : nil,
                as_double: value.is_a?(Float) ? value : nil
              }
            ]
          }
        }
      end
    end
  end
end

