# frozen_string_literal: true

module RR
  class Instrumentation
    # OpenTelemetry metrics exporter for Redis instrumentation
    #
    # Exports metrics in OpenTelemetry format for integration with OTLP collectors.
    #
    class OpenTelemetryExporter
      attr_reader :instrumentation, :service_name, :service_version

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
        timestamp = (Time.now.to_f * 1_000_000_000).to_i

        {
          resource_metrics: [
            {
              resource: build_resource,
              scope_metrics: [
                {
                  scope: { name: "redis-ruby-instrumentation", version: "1.0.0" },
                  metrics: build_metrics(snapshot, timestamp),
                },
              ],
            },
          ],
        }
      end

      private

      def build_resource
        {
          attributes: [
            { key: "service.name", value: { string_value: @service_name } },
            { key: "service.version", value: { string_value: @service_version } },
            { key: "telemetry.sdk.name", value: { string_value: "redis-ruby" } },
            { key: "telemetry.sdk.language", value: { string_value: "ruby" } },
          ],
        }
      end

      def build_metrics(snapshot, timestamp)
        metrics = []
        build_command_metrics(metrics, snapshot, timestamp)
        build_pipeline_metrics(metrics, snapshot, timestamp)
        build_transaction_metrics(metrics, snapshot, timestamp)
        build_pool_metrics(metrics, snapshot, timestamp)
        metrics
      end

      def build_command_metrics(metrics, snapshot, timestamp)
        metrics << counter_metric("redis.commands.total", "Total number of Redis commands executed",
                                  snapshot[:total_commands], timestamp)

        snapshot[:commands].each do |cmd, data|
          build_single_command_metrics(metrics, cmd, data, timestamp)
        end
      end

      def build_single_command_metrics(metrics, cmd, data, timestamp)
        attrs = { "command" => cmd }
        metrics << counter_metric("redis.command.count", "Number of times command was executed",
                                  data[:count], timestamp, attrs)
        metrics << counter_metric("redis.command.duration", "Total time spent executing command",
                                  data[:total_time], timestamp, attrs.merge("unit" => "seconds"))
        metrics << counter_metric("redis.command.errors", "Number of errors for command",
                                  data[:errors], timestamp, attrs)
        metrics << counter_metric("redis.command.success", "Number of successful executions for command",
                                  data[:success], timestamp, attrs)
      end

      def build_pipeline_metrics(metrics, snapshot, timestamp)
        pipelines = snapshot[:pipelines]
        metrics << counter_metric("redis.pipelines.total", "Total number of pipelines executed",
                                  pipelines[:count], timestamp)
        metrics << counter_metric("redis.pipeline.duration", "Total time spent in pipelines",
                                  pipelines[:total_time], timestamp, { "unit" => "seconds" })
      end

      def build_transaction_metrics(metrics, snapshot, timestamp)
        txns = snapshot[:transactions]
        metrics << counter_metric("redis.transactions.total", "Total number of transactions executed",
                                  txns[:count], timestamp)
        metrics << counter_metric("redis.transaction.duration", "Total time spent in transactions",
                                  txns[:total_time], timestamp, { "unit" => "seconds" })
      end

      def build_pool_metrics(metrics, snapshot, timestamp)
        pool = snapshot[:pool]
        metrics << counter_metric("redis.pool.connections.created", "Total connections created",
                                  pool[:connection_creates], timestamp)
        metrics << gauge_metric("redis.pool.connections.active", "Current active connections",
                                pool[:active_connections], timestamp)
        metrics << gauge_metric("redis.pool.connections.idle", "Current idle connections",
                                pool[:idle_connections], timestamp)
        metrics << counter_metric("redis.pool.exhaustions", "Times pool was exhausted",
                                  pool[:pool_exhaustions], timestamp)
      end

      def counter_metric(name, description, value, timestamp, attributes = {})
        {
          name: name, description: description, unit: "1",
          sum: {
            data_points: [build_data_point(value, timestamp, attributes,
                                           start_time: true)],
            aggregation_temporality: "AGGREGATION_TEMPORALITY_CUMULATIVE",
            is_monotonic: true,
          },
        }
      end

      def gauge_metric(name, description, value, timestamp, attributes = {})
        {
          name: name, description: description, unit: "1",
          gauge: { data_points: [build_data_point(value, timestamp, attributes)] },
        }
      end

      def build_data_point(value, timestamp, attributes, start_time: false)
        point = {
          attributes: attributes.map { |k, v| { key: k, value: { string_value: v.to_s } } },
          time_unix_nano: timestamp,
          as_int: value.is_a?(Integer) ? value : nil,
          as_double: value.is_a?(Float) ? value : nil,
        }
        point[:start_time_unix_nano] = timestamp if start_time
        point
      end
    end
  end
end
