# frozen_string_literal: true

require 'socket'

module RR
  class Instrumentation
    # StatsD metrics exporter for Redis instrumentation
    #
    # Exports metrics to StatsD using the StatsD protocol over UDP.
    # Supports counters, gauges, and timers.
    #
    # @example Basic usage
    #   instrumentation = RR::Instrumentation.new
    #   exporter = RR::Instrumentation::StatsDExporter.new(
    #     instrumentation,
    #     host: 'localhost',
    #     port: 8125
    #   )
    #
    #   # Export metrics to StatsD
    #   exporter.export
    #
    # @example With custom prefix and tags
    #   exporter = RR::Instrumentation::StatsDExporter.new(
    #     instrumentation,
    #     host: 'localhost',
    #     port: 8125,
    #     prefix: 'myapp.redis',
    #     tags: { environment: 'production', service: 'api' }
    #   )
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
      def initialize(instrumentation, host: 'localhost', port: 8125, prefix: 'redis', tags: {})
        @instrumentation = instrumentation
        @host = host
        @port = port
        @prefix = prefix
        @tags = tags
        @socket = UDPSocket.new
      end

      # Export metrics to StatsD
      #
      # Sends all current metrics to the StatsD server via UDP.
      # Returns the number of metrics sent.
      #
      # @return [Integer] Number of metrics sent
      def export
        snapshot = @instrumentation.snapshot
        metrics_sent = 0

        # Total commands counter
        send_metric("#{@prefix}.commands.total", snapshot[:total_commands], :c)
        metrics_sent += 1

        # Per-command metrics
        snapshot[:commands].each do |cmd, data|
          cmd_tags = merge_tags(command: cmd)

          # Command count
          send_metric("#{@prefix}.command.count", data[:count], :c, tags: cmd_tags)
          metrics_sent += 1

          # Command duration (convert to milliseconds for StatsD convention)
          duration_ms = (data[:total_time] * 1000).round(2)
          send_metric("#{@prefix}.command.duration", duration_ms, :ms, tags: cmd_tags)
          metrics_sent += 1

          # Command errors
          send_metric("#{@prefix}.command.errors", data[:errors], :c, tags: cmd_tags)
          metrics_sent += 1

          # Command success
          send_metric("#{@prefix}.command.success", data[:success], :c, tags: cmd_tags)
          metrics_sent += 1
        end

        # Total errors counter
        send_metric("#{@prefix}.errors.total", snapshot[:total_errors], :c)
        metrics_sent += 1

        # Per-error-type metrics
        snapshot[:errors].each do |error_type, count|
          error_tags = merge_tags(error_type: error_type)
          send_metric("#{@prefix}.error.count", count, :c, tags: error_tags)
          metrics_sent += 1
        end

        # Pipeline metrics
        pipelines = snapshot[:pipelines]
        send_metric("#{@prefix}.pipeline.count", pipelines[:count], :c)
        send_metric("#{@prefix}.pipeline.duration", (pipelines[:total_time] * 1000).round(2), :ms)
        send_metric("#{@prefix}.pipeline.commands", pipelines[:total_commands], :c)
        send_metric("#{@prefix}.pipeline.avg_commands", pipelines[:avg_commands].round(2), :g)
        metrics_sent += 4

        # Transaction metrics
        transactions = snapshot[:transactions]
        send_metric("#{@prefix}.transaction.count", transactions[:count], :c)
        send_metric("#{@prefix}.transaction.duration", (transactions[:total_time] * 1000).round(2), :ms)
        send_metric("#{@prefix}.transaction.commands", transactions[:total_commands], :c)
        send_metric("#{@prefix}.transaction.avg_commands", transactions[:avg_commands].round(2), :g)
        metrics_sent += 4

        # Pool metrics
        pool = snapshot[:pool]
        send_metric("#{@prefix}.pool.connections.created", pool[:connection_creates], :c)
        send_metric("#{@prefix}.pool.connections.wait_time", (pool[:total_connection_wait_time] * 1000).round(2), :ms)
        send_metric("#{@prefix}.pool.connections.checkout_time", (pool[:total_connection_checkout_time] * 1000).round(2), :ms)
        send_metric("#{@prefix}.pool.exhaustions", pool[:pool_exhaustions], :c)
        send_metric("#{@prefix}.pool.connections.active", pool[:active_connections], :g)
        send_metric("#{@prefix}.pool.connections.idle", pool[:idle_connections], :g)
        send_metric("#{@prefix}.pool.connections.total", pool[:total_connections], :g)
        metrics_sent += 7

        # Connection close reasons
        pool[:connection_closes].each do |reason, count|
          close_tags = merge_tags(reason: reason)
          send_metric("#{@prefix}.pool.connections.closed", count, :c, tags: close_tags)
          metrics_sent += 1
        end

        metrics_sent
      end

      # Close the UDP socket
      def close
        @socket.close if @socket && !@socket.closed?
      end

      private

      # Send a metric to StatsD
      #
      # @param name [String] Metric name
      # @param value [Numeric] Metric value
      # @param type [Symbol] Metric type (:c for counter, :g for gauge, :ms for timer)
      # @param tags [Hash] Additional tags for this metric
      def send_metric(name, value, type, tags: {})
        metric_tags = merge_tags(tags)
        metric_line = format_metric(name, value, type, metric_tags)
        @socket.send(metric_line, 0, @host, @port)
      rescue StandardError => e
        # Silently ignore errors to avoid breaking the application
        # In production, you might want to log this
        warn "StatsD export error: #{e.message}" if $DEBUG
      end

      # Format a metric in StatsD protocol format
      #
      # @param name [String] Metric name
      # @param value [Numeric] Metric value
      # @param type [Symbol] Metric type
      # @param tags [Hash] Tags for this metric
      # @return [String] Formatted metric line
      def format_metric(name, value, type, tags)
        # StatsD format: metric_name:value|type|@sample_rate|#tag1:value1,tag2:value2
        # We don't use sampling, so we omit @sample_rate
        metric = "#{name}:#{value}|#{type}"

        # Add tags if present (DogStatsD format)
        unless tags.empty?
          tag_string = tags.map { |k, v| "#{k}:#{v}" }.join(',')
          metric += "|##{tag_string}"
        end

        metric
      end

      # Merge global tags with metric-specific tags
      #
      # @param tags [Hash] Metric-specific tags
      # @return [Hash] Merged tags
      def merge_tags(tags = {})
        @tags.merge(tags)
      end
    end
  end
end


