# frozen_string_literal: true

require_relative "../test_helper"

class ActiveActiveEnterpriseTest < Minitest::Test
  def setup
    @redis_host = ENV.fetch("REDIS_HOST", "localhost")
    @redis_port = ENV.fetch("REDIS_PORT", "6379").to_i

    # Simulate multiple regions with weights
    @regions = [
      { host: @redis_host, port: @redis_port, weight: 1.0 },
      { host: @redis_host, port: @redis_port, weight: 0.8 },
      { host: @redis_host, port: @redis_port, weight: 0.5 },
    ]
  end

  def teardown
    @client&.close
  end

  def test_health_checks_enabled
    @client = RR.active_active(
      regions: @regions,
      health_check_interval: 1.0,
      health_check_probes: 2,
      health_check_policy: :majority
    )

    # Give health checks time to run
    sleep 0.5

    # All regions should be healthy
    status = @client.health_status

    assert_equal 3, status.size
    status.each_value do |info|
      assert info[:healthy], "Region #{info[:region]} should be healthy"
      assert_equal :closed, info[:circuit_state]
    end
  end

  def test_circuit_breaker_integration
    @client = RR.active_active(
      regions: @regions,
      circuit_breaker_threshold: 3,
      circuit_breaker_timeout: 2
    )

    # Perform operations
    key = "enterprise:circuit:#{SecureRandom.hex(8)}"
    @client.set(key, "test")

    assert_equal "test", @client.get(key)

    # Check circuit breaker states
    status = @client.health_status

    status.each_value do |info|
      assert_includes %i[closed half_open], info[:circuit_state]
    end

    @client.del(key)
  end

  def test_failure_detection
    @client = RR.active_active(
      regions: @regions,
      failure_window_size: 1.0,
      min_failures: 10,
      failure_rate_threshold: 0.5
    )

    # Perform successful operations
    key = "enterprise:failure:#{SecureRandom.hex(8)}"
    100.times do |i|
      @client.set("#{key}:#{i}", i)
    end

    # Check failure stats for current region (region 0)
    status = @client.health_status
    current_region_stats = status[0][:failure_stats]

    assert_predicate current_region_stats[:total_successes], :positive?, "Should have recorded successes"
    assert_operator current_region_stats[:failure_rate], :<, 0.1, "Failure rate should be low"

    # Cleanup
    100.times { |i| @client.del("#{key}:#{i}") }
  end

  def test_event_callbacks
    events = []

    @client = RR.active_active(
      regions: @regions,
      health_check_interval: 0.5
    )

    # Register event listeners
    @client.on_failover do |event|
      events << { type: :failover, event: event }
    end

    @client.on_database_failed do |event|
      events << { type: :failed, event: event }
    end

    @client.on_database_recovered do |event|
      events << { type: :recovered, event: event }
    end

    # Trigger manual failover
    @client.failover_to_next_region

    # Should have received failover event
    assert events.any? { |e| e[:type] == :failover }, "Should have received failover event"

    failover_event = events.find { |e| e[:type] == :failover }[:event]

    assert_equal "manual", failover_event.reason
    assert_instance_of Time, failover_event.timestamp
  end

  def test_auto_fallback_disabled_by_default
    @client = RR.active_active(
      regions: @regions,
      preferred_region: 0
    )

    # Manually failover to region 1
    @client.failover_to_next_region
    current = @client.current_region

    # Wait a bit
    sleep 0.5

    # Should still be on region 1 (no auto-fallback)
    assert_equal current, @client.current_region
  end

  def test_weight_based_failover
    # Create client with weighted regions
    @client = RR.active_active(
      regions: @regions
    )

    # Verify regions have weights
    status = @client.health_status

    assert_equal 3, status.size

    # Perform operations
    key = "enterprise:weight:#{SecureRandom.hex(8)}"
    @client.set(key, "weighted")

    assert_equal "weighted", @client.get(key)
    @client.del(key)
  end
end
