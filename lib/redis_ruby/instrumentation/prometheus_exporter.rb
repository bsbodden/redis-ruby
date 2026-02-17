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
    #   
    #   # Get metrics in Prometheus format
    #   puts exporter.export
    #
    # @example With custom prefix
    #   exporter = RR::Instrumentation::PrometheusExporter.new(
    #     instrumentation,
    #     prefix: "myapp_redis"
    #   )
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

        # Command metrics
        lines << "# HELP #{@prefix}_commands_total Total number of Redis commands executed"
        lines << "# TYPE #{@prefix}_commands_total counter"
        lines << "#{@prefix}_commands_total #{snapshot[:total_commands]}"
        lines << ""

        # Per-command metrics
        lines << "# HELP #{@prefix}_command_count Number of times each command was executed"
        lines << "# TYPE #{@prefix}_command_count counter"
        snapshot[:commands].each do |cmd, data|
          lines << "#{@prefix}_command_count{command=\"#{cmd}\"} #{data[:count]}"
        end
        lines << ""

        lines << "# HELP #{@prefix}_command_duration_seconds Total time spent executing each command"
        lines << "# TYPE #{@prefix}_command_duration_seconds counter"
        snapshot[:commands].each do |cmd, data|
          lines << "#{@prefix}_command_duration_seconds{command=\"#{cmd}\"} #{data[:total_time]}"
        end
        lines << ""

        lines << "# HELP #{@prefix}_command_errors_total Number of errors per command"
        lines << "# TYPE #{@prefix}_command_errors_total counter"
        snapshot[:commands].each do |cmd, data|
          lines << "#{@prefix}_command_errors_total{command=\"#{cmd}\"} #{data[:errors]}"
        end
        lines << ""

        lines << "# HELP #{@prefix}_command_success_total Number of successful executions per command"
        lines << "# TYPE #{@prefix}_command_success_total counter"
        snapshot[:commands].each do |cmd, data|
          lines << "#{@prefix}_command_success_total{command=\"#{cmd}\"} #{data[:success]}"
        end
        lines << ""

        # Error metrics
        lines << "# HELP #{@prefix}_errors_total Total number of errors"
        lines << "# TYPE #{@prefix}_errors_total counter"
        lines << "#{@prefix}_errors_total #{snapshot[:total_errors]}"
        lines << ""

        lines << "# HELP #{@prefix}_error_count Number of errors by type"
        lines << "# TYPE #{@prefix}_error_count counter"
        snapshot[:errors].each do |error_type, count|
          lines << "#{@prefix}_error_count{error_type=\"#{error_type}\"} #{count}"
        end
        lines << ""

        # Pipeline metrics
        lines << "# HELP #{@prefix}_pipelines_total Total number of pipelines executed"
        lines << "# TYPE #{@prefix}_pipelines_total counter"
        lines << "#{@prefix}_pipelines_total #{snapshot[:pipelines][:count]}"
        lines << ""

        lines << "# HELP #{@prefix}_pipeline_duration_seconds Total time spent in pipelines"
        lines << "# TYPE #{@prefix}_pipeline_duration_seconds counter"
        lines << "#{@prefix}_pipeline_duration_seconds #{snapshot[:pipelines][:total_time]}"
        lines << ""

        lines << "# HELP #{@prefix}_pipeline_commands_total Total commands executed in pipelines"
        lines << "# TYPE #{@prefix}_pipeline_commands_total counter"
        lines << "#{@prefix}_pipeline_commands_total #{snapshot[:pipelines][:total_commands]}"
        lines << ""

        # Transaction metrics
        lines << "# HELP #{@prefix}_transactions_total Total number of transactions executed"
        lines << "# TYPE #{@prefix}_transactions_total counter"
        lines << "#{@prefix}_transactions_total #{snapshot[:transactions][:count]}"
        lines << ""

        lines << "# HELP #{@prefix}_transaction_duration_seconds Total time spent in transactions"
        lines << "# TYPE #{@prefix}_transaction_duration_seconds counter"
        lines << "#{@prefix}_transaction_duration_seconds #{snapshot[:transactions][:total_time]}"
        lines << ""

        lines << "# HELP #{@prefix}_transaction_commands_total Total commands executed in transactions"
        lines << "# TYPE #{@prefix}_transaction_commands_total counter"
        lines << "#{@prefix}_transaction_commands_total #{snapshot[:transactions][:total_commands]}"
        lines << ""

        # Pool metrics
        pool = snapshot[:pool]
        lines << "# HELP #{@prefix}_pool_connections_created_total Total connections created"
        lines << "# TYPE #{@prefix}_pool_connections_created_total counter"
        lines << "#{@prefix}_pool_connections_created_total #{pool[:connection_creates]}"
        lines << ""

        lines << "# HELP #{@prefix}_pool_connection_create_duration_seconds Total time creating connections"
        lines << "# TYPE #{@prefix}_pool_connection_create_duration_seconds counter"
        lines << "#{@prefix}_pool_connection_create_duration_seconds #{pool[:avg_connection_create_time] * pool[:connection_creates]}"
        lines << ""

        lines << "# HELP #{@prefix}_pool_connection_wait_duration_seconds Total time waiting for connections"
        lines << "# TYPE #{@prefix}_pool_connection_wait_duration_seconds counter"
        lines << "#{@prefix}_pool_connection_wait_duration_seconds #{pool[:total_connection_wait_time]}"
        lines << ""

        lines << "# HELP #{@prefix}_pool_exhaustions_total Number of times pool was exhausted"
        lines << "# TYPE #{@prefix}_pool_exhaustions_total counter"
        lines << "#{@prefix}_pool_exhaustions_total #{pool[:pool_exhaustions]}"
        lines << ""

        lines << "# HELP #{@prefix}_pool_connections_active Current number of active connections"
        lines << "# TYPE #{@prefix}_pool_connections_active gauge"
        lines << "#{@prefix}_pool_connections_active #{pool[:active_connections]}"
        lines << ""

        lines << "# HELP #{@prefix}_pool_connections_idle Current number of idle connections"
        lines << "# TYPE #{@prefix}_pool_connections_idle gauge"
        lines << "#{@prefix}_pool_connections_idle #{pool[:idle_connections]}"
        lines << ""

        lines.join("\n")
      end
    end
  end
end

