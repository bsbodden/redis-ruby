# frozen_string_literal: true

require "socket"

module RR
  class Instrumentation
    # StatsD metrics exporter for Redis instrumentation
    #
    # Exports metrics to StatsD using the StatsD protocol over UDP.
    # Supports counters, gauges, and timers.
    #
    class StatsDExporter
      attr_reader :instrumentation, :host, :port, :prefix, :tags

      # Initialize StatsD exporter
      #
      # @param instrumentation [RR::Instrumentation] Instrumentation instance
      # @param host [String] StatsD server host (default: 'localhost')
      # @param port [Integer] StatsD server port (default: 8125)
      # @param prefix [String] Metric name prefix (default: 'redis')
      # @param tags [Hash] Global tags to add to all metrics (default: {})
      def initialize(instrumentation, host: "localhost", port: 8125, prefix: "redis", tags: {})
        @instrumentation = instrumentation
        @host = host
        @port = port
        @prefix = prefix
        @tags = tags
        @socket = UDPSocket.new
      end

      # Export metrics to StatsD
      #
      # @return [Integer] Number of metrics sent
      def export
        snapshot = @instrumentation.snapshot
        count = 0
        count += export_command_metrics(snapshot)
        count += export_error_metrics(snapshot)
        count += export_pipeline_metrics(snapshot)
        count += export_transaction_metrics(snapshot)
        count += export_pool_metrics(snapshot)
        count
      end

      # Close the UDP socket
      def close
        @socket.close if @socket && !@socket.closed?
      end

      private

      def export_command_metrics(snapshot)
        sent = 0
        send_metric("#{@prefix}.commands.total", snapshot[:total_commands], :c)
        sent += 1

        snapshot[:commands].each do |cmd, data|
          sent += export_single_command(cmd, data)
        end
        sent
      end

      def export_single_command(cmd, data)
        cmd_tags = merge_tags(command: cmd)
        send_metric("#{@prefix}.command.count", data[:count], :c, tags: cmd_tags)
        duration_ms = (data[:total_time] * 1000).round(2)
        send_metric("#{@prefix}.command.duration", duration_ms, :ms, tags: cmd_tags)
        send_metric("#{@prefix}.command.errors", data[:errors], :c, tags: cmd_tags)
        send_metric("#{@prefix}.command.success", data[:success], :c, tags: cmd_tags)
        4
      end

      def export_error_metrics(snapshot)
        send_metric("#{@prefix}.errors.total", snapshot[:total_errors], :c)
        sent = 1
        snapshot[:errors].each do |error_type, count|
          send_metric("#{@prefix}.error.count", count, :c, tags: merge_tags(error_type: error_type))
          sent += 1
        end
        sent
      end

      def export_pipeline_metrics(snapshot)
        pipelines = snapshot[:pipelines]
        send_metric("#{@prefix}.pipeline.count", pipelines[:count], :c)
        send_metric("#{@prefix}.pipeline.duration", (pipelines[:total_time] * 1000).round(2), :ms)
        send_metric("#{@prefix}.pipeline.commands", pipelines[:total_commands], :c)
        send_metric("#{@prefix}.pipeline.avg_commands", pipelines[:avg_commands].round(2), :g)
        4
      end

      def export_transaction_metrics(snapshot)
        txns = snapshot[:transactions]
        send_metric("#{@prefix}.transaction.count", txns[:count], :c)
        send_metric("#{@prefix}.transaction.duration", (txns[:total_time] * 1000).round(2), :ms)
        send_metric("#{@prefix}.transaction.commands", txns[:total_commands], :c)
        send_metric("#{@prefix}.transaction.avg_commands", txns[:avg_commands].round(2), :g)
        4
      end

      def export_pool_metrics(snapshot)
        pool = snapshot[:pool]
        export_pool_counters(pool)
        export_pool_gauges(pool)
        sent = 7
        pool[:connection_closes].each do |reason, count|
          send_metric("#{@prefix}.pool.connections.closed", count, :c, tags: merge_tags(reason: reason))
          sent += 1
        end
        sent
      end

      def export_pool_counters(pool)
        send_metric("#{@prefix}.pool.connections.created", pool[:connection_creates], :c)
        wait_ms = (pool[:total_connection_wait_time] * 1000).round(2)
        send_metric("#{@prefix}.pool.connections.wait_time", wait_ms, :ms)
        checkout_ms = (pool[:total_connection_checkout_time] * 1000).round(2)
        send_metric("#{@prefix}.pool.connections.checkout_time", checkout_ms, :ms)
        send_metric("#{@prefix}.pool.exhaustions", pool[:pool_exhaustions], :c)
      end

      def export_pool_gauges(pool)
        send_metric("#{@prefix}.pool.connections.active", pool[:active_connections], :g)
        send_metric("#{@prefix}.pool.connections.idle", pool[:idle_connections], :g)
        send_metric("#{@prefix}.pool.connections.total", pool[:total_connections], :g)
      end

      # Send a metric to StatsD
      def send_metric(name, value, type, tags: {})
        metric_tags = merge_tags(tags)
        metric_line = format_metric(name, value, type, metric_tags)
        @socket.send(metric_line, 0, @host, @port)
      rescue StandardError => e
        warn "StatsD export error: #{e.message}" if $DEBUG
      end

      def format_metric(name, value, type, tags)
        metric = "#{name}:#{value}|#{type}"
        unless tags.empty?
          tag_string = tags.map { |k, v| "#{k}:#{v}" }.join(",")
          metric += "|##{tag_string}"
        end
        metric
      end

      def merge_tags(tags = {})
        @tags.merge(tags)
      end
    end
  end
end
