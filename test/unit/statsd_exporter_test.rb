# frozen_string_literal: true

require "test_helper"
require "redis_ruby/instrumentation/statsd_exporter"
require "socket"

class StatsDExporterTest < Minitest::Test
  def setup
    @instrumentation = RR::Instrumentation.new
    @port = 18125 # Use non-standard port for testing
    @exporter = RR::Instrumentation::StatsDExporter.new(
      @instrumentation,
      host: 'localhost',
      port: @port,
      prefix: 'test.redis',
      tags: { environment: 'test' }
    )
    
    # Create a UDP server to receive metrics
    @server = UDPSocket.new
    @server.bind('localhost', @port)
    @received_metrics = []
  end

  def teardown
    @exporter.close
    @server.close if @server && !@server.closed?
  end

  def test_initialization
    assert_equal 'localhost', @exporter.host
    assert_equal @port, @exporter.port
    assert_equal 'test.redis', @exporter.prefix
    assert_equal({ environment: 'test' }, @exporter.tags)
  end

  def test_export_sends_metrics
    # Record some commands
    @instrumentation.record_command('SET', 0.001)
    @instrumentation.record_command('GET', 0.0005)
    
    # Export metrics in a thread
    export_thread = Thread.new { @exporter.export }
    
    # Receive metrics
    timeout = Time.now + 2
    while Time.now < timeout && @received_metrics.size < 5
      begin
        data, = @server.recvfrom_nonblock(1024)
        @received_metrics << data
      rescue IO::WaitReadable
        sleep 0.01
      end
    end
    
    export_thread.join
    
    # Verify we received some metrics
    assert @received_metrics.size > 0, "Should have received metrics"
    
    # Check for expected metric patterns
    metrics_text = @received_metrics.join("\n")
    assert_match(/test\.redis\.commands\.total:\d+\|c/, metrics_text, "Should have total commands counter")
    # Tags can be in any order, so check for both possible orderings
    assert_match(/test\.redis\.command\.count:\d+\|c\|#(command:SET,environment:test|environment:test,command:SET)/, metrics_text, "Should have SET command counter with tags")
  end

  def test_format_metric_counter
    metric = @exporter.send(:format_metric, 'test.counter', 42, :c, {})
    assert_equal 'test.counter:42|c', metric
  end

  def test_format_metric_gauge
    metric = @exporter.send(:format_metric, 'test.gauge', 100, :g, {})
    assert_equal 'test.gauge:100|g', metric
  end

  def test_format_metric_timer
    metric = @exporter.send(:format_metric, 'test.timer', 123.45, :ms, {})
    assert_equal 'test.timer:123.45|ms', metric
  end

  def test_format_metric_with_tags
    tags = { command: 'SET', status: 'success' }
    metric = @exporter.send(:format_metric, 'test.metric', 10, :c, tags)
    assert_equal 'test.metric:10|c|#command:SET,status:success', metric
  end

  def test_merge_tags
    metric_tags = { command: 'GET' }
    merged = @exporter.send(:merge_tags, metric_tags)
    assert_equal({ environment: 'test', command: 'GET' }, merged)
  end

  def test_export_returns_metric_count
    @instrumentation.record_command('SET', 0.001)
    
    # Don't actually send to avoid timing issues, just count
    @exporter.stub(:send_metric, nil) do
      count = @exporter.export
      assert count > 0, "Should return number of metrics sent"
    end
  end

  def test_export_handles_errors_gracefully
    # Close the socket to force an error
    @exporter.instance_variable_get(:@socket).close
    
    # Should not raise an error
    assert_silent do
      @exporter.export
    end
  end

  def test_close_closes_socket
    socket = @exporter.instance_variable_get(:@socket)
    refute socket.closed?, "Socket should be open initially"
    
    @exporter.close
    assert socket.closed?, "Socket should be closed after close()"
  end

  def test_export_with_pool_metrics
    @instrumentation.record_connection_create(0.001)
    @instrumentation.update_connection_counts(active: 5, idle: 3)
    
    @exporter.stub(:send_metric, nil) do
      count = @exporter.export
      assert count > 0, "Should export pool metrics"
    end
  end

  def test_export_with_error_metrics
    # Record commands with errors
    @instrumentation.record_command('GET', 0.001, error: StandardError.new('Command error'))
    @instrumentation.record_command('SET', 0.002, error: Timeout::Error.new('Timeout'))

    @exporter.stub(:send_metric, nil) do
      count = @exporter.export
      assert count > 0, "Should export error metrics"
    end
  end

  def test_export_with_pipeline_metrics
    @instrumentation.record_pipeline(0.005, 10)
    
    @exporter.stub(:send_metric, nil) do
      count = @exporter.export
      assert count > 0, "Should export pipeline metrics"
    end
  end
end

