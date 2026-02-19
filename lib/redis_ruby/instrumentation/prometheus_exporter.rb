# frozen_string_literal: true

module RR
  class Instrumentation
    # Prometheus metrics exporter for Redis instrumentation
    #
    # Exports metrics in Prometheus text format for scraping by Prometheus server.
    #
    # @example Basic usage
    #   instrumentation = RR::Instrumentation.new
    #   exporter = RR::Instrumentation::PrometheusExporter.new(instrumentation)
    #   puts exporter.export
    #
    class PrometheusExporter
      attr_reader :instrumentation, :prefix

      # Initialize exporter
      #
      # @param instrumentation [RR::Instrumentation] Instrumentation instance
      # @param prefix [String] Metric name prefix (default: "redis_ruby")
      def initialize(instrumentation, prefix: "redis_ruby")
        @instrumentation = instrumentation
        @prefix = prefix
      end

      # Export metrics in Prometheus text format
      #
      # @return [String] Prometheus-formatted metrics
      def export
        lines = []
        snapshot = @instrumentation.snapshot

        export_command_metrics(lines, snapshot)
        export_error_metrics(lines, snapshot)
        export_pipeline_metrics(lines, snapshot)
        export_transaction_metrics(lines, snapshot)
        export_pool_metrics(lines, snapshot)

        lines.join("\n")
      end

      private

      def export_command_metrics(lines, snapshot)
        counter(lines, "commands_total", "Total number of Redis commands executed",
                snapshot[:total_commands])

        export_per_command_metrics(lines, snapshot[:commands])
      end

      def export_per_command_metrics(lines, commands)
        labeled_counter(lines, "command_count", "Number of times each command was executed",
                        commands, :count, "command")
        labeled_counter(lines, "command_duration_seconds", "Total time spent executing each command",
                        commands, :total_time, "command")
        labeled_counter(lines, "command_errors_total", "Number of errors per command",
                        commands, :errors, "command")
        labeled_counter(lines, "command_success_total", "Number of successful executions per command",
                        commands, :success, "command")
      end

      def export_error_metrics(lines, snapshot)
        counter(lines, "errors_total", "Total number of errors", snapshot[:total_errors])
        labeled_counter(lines, "error_count", "Number of errors by type",
                        snapshot[:errors], nil, "error_type")
      end

      def export_pipeline_metrics(lines, snapshot)
        pipelines = snapshot[:pipelines]
        counter(lines, "pipelines_total", "Total number of pipelines executed", pipelines[:count])
        counter(lines, "pipeline_duration_seconds", "Total time spent in pipelines", pipelines[:total_time])
        counter(lines, "pipeline_commands_total", "Total commands executed in pipelines",
                pipelines[:total_commands])
      end

      def export_transaction_metrics(lines, snapshot)
        txns = snapshot[:transactions]
        counter(lines, "transactions_total", "Total number of transactions executed", txns[:count])
        counter(lines, "transaction_duration_seconds", "Total time spent in transactions",
                txns[:total_time])
        counter(lines, "transaction_commands_total", "Total commands executed in transactions",
                txns[:total_commands])
      end

      def export_pool_metrics(lines, snapshot)
        pool = snapshot[:pool]
        counter(lines, "pool_connections_created_total", "Total connections created",
                pool[:connection_creates])
        create_duration = pool[:avg_connection_create_time] * pool[:connection_creates]
        counter(lines, "pool_connection_create_duration_seconds",
                "Total time creating connections", create_duration)
        counter(lines, "pool_connection_wait_duration_seconds",
                "Total time waiting for connections", pool[:total_connection_wait_time])
        counter(lines, "pool_exhaustions_total", "Number of times pool was exhausted",
                pool[:pool_exhaustions])
        gauge(lines, "pool_connections_active", "Current number of active connections",
              pool[:active_connections])
        gauge(lines, "pool_connections_idle", "Current number of idle connections",
              pool[:idle_connections])
      end

      def counter(lines, name, help, value)
        lines << "# HELP #{@prefix}_#{name} #{help}"
        lines << "# TYPE #{@prefix}_#{name} counter"
        lines << "#{@prefix}_#{name} #{value}"
        lines << ""
      end

      def gauge(lines, name, help, value)
        lines << "# HELP #{@prefix}_#{name} #{help}"
        lines << "# TYPE #{@prefix}_#{name} gauge"
        lines << "#{@prefix}_#{name} #{value}"
        lines << ""
      end

      def labeled_counter(lines, name, help, data, field, label_name)
        lines << "# HELP #{@prefix}_#{name} #{help}"
        lines << "# TYPE #{@prefix}_#{name} counter"
        data.each do |key, value|
          metric_value = field ? value[field] : value
          lines << "#{@prefix}_#{name}{#{label_name}=\"#{key}\"} #{metric_value}"
        end
        lines << ""
      end
    end
  end
end
