# frozen_string_literal: true

require "test_helper"

class EventDispatcherTest < Minitest::Test
  def setup
    @dispatcher = RR::EventDispatcher.new
  end

  # ============================================================
  # Event Classes
  # ============================================================

  def test_database_failed_event_creation
    event = RR::DatabaseFailedEvent.new(
      database_id: "db-1",
      region: "us-east-1",
      error: "Connection timeout"
    )

    assert_equal "db-1", event.database_id
    assert_equal "us-east-1", event.region
    assert_equal "Connection timeout", event.error
    assert_instance_of Time, event.timestamp
  end

  def test_database_recovered_event_creation
    event = RR::DatabaseRecoveredEvent.new(
      database_id: "db-1",
      region: "us-east-1"
    )

    assert_equal "db-1", event.database_id
    assert_equal "us-east-1", event.region
    assert_instance_of Time, event.timestamp
  end

  def test_failover_event_creation
    event = RR::FailoverEvent.new(
      from_database_id: "db-1",
      to_database_id: "db-2",
      from_region: "us-east-1",
      to_region: "us-west-2",
      reason: "Primary database unresponsive"
    )

    assert_equal "db-1", event.from_database_id
    assert_equal "db-2", event.to_database_id
    assert_equal "us-east-1", event.from_region
    assert_equal "us-west-2", event.to_region
    assert_equal "Primary database unresponsive", event.reason
    assert_instance_of Time, event.timestamp
  end

  def test_events_are_frozen
    event = RR::DatabaseFailedEvent.new(
      database_id: "db-1",
      region: "us-east-1",
      error: "Test"
    )

    assert event.frozen?
  end

  def test_event_to_s
    event = RR::DatabaseFailedEvent.new(
      database_id: "db-1",
      region: "us-east-1",
      error: "Test"
    )

    str = event.to_s
    assert_includes str, "DatabaseFailedEvent"
    assert_includes str, "db-1"
    assert_includes str, "us-east-1"
  end

  # ============================================================
  # EventDispatcher - Listener Registration
  # ============================================================

  def test_on_registers_listener
    called = false
    @dispatcher.on(RR::DatabaseFailedEvent) { |_event| called = true }

    event = RR::DatabaseFailedEvent.new(
      database_id: "db-1",
      region: "us-east-1",
      error: "Test"
    )
    @dispatcher.dispatch(event)

    assert called
  end

  def test_on_returns_listener_block
    block = proc { |_event| }
    result = @dispatcher.on(RR::DatabaseFailedEvent, &block)

    assert_same block, result
  end

  def test_on_raises_without_block
    assert_raises(ArgumentError) do
      @dispatcher.on(RR::DatabaseFailedEvent)
    end
  end

  def test_on_raises_with_non_event_class
    assert_raises(ArgumentError) do
      @dispatcher.on(String) { |_event| }
    end
  end

  def test_multiple_listeners_for_same_event
    call_count = 0
    @dispatcher.on(RR::DatabaseFailedEvent) { |_event| call_count += 1 }
    @dispatcher.on(RR::DatabaseFailedEvent) { |_event| call_count += 1 }
    @dispatcher.on(RR::DatabaseFailedEvent) { |_event| call_count += 1 }

    event = RR::DatabaseFailedEvent.new(
      database_id: "db-1",
      region: "us-east-1",
      error: "Test"
    )
    @dispatcher.dispatch(event)

    assert_equal 3, call_count
  end

  # ============================================================
  # EventDispatcher - Event Dispatching
  # ============================================================

  def test_dispatch_calls_listeners_with_event
    received_event = nil
    @dispatcher.on(RR::DatabaseFailedEvent) { |event| received_event = event }

    event = RR::DatabaseFailedEvent.new(
      database_id: "db-1",
      region: "us-east-1",
      error: "Test"
    )
    @dispatcher.dispatch(event)

    assert_same event, received_event
  end

  def test_dispatch_returns_listener_count
    @dispatcher.on(RR::DatabaseFailedEvent) { |_event| }
    @dispatcher.on(RR::DatabaseFailedEvent) { |_event| }

    event = RR::DatabaseFailedEvent.new(
      database_id: "db-1",
      region: "us-east-1",
      error: "Test"
    )
    count = @dispatcher.dispatch(event)

    assert_equal 2, count
  end

  def test_dispatch_raises_with_non_event
    assert_raises(ArgumentError) do
      @dispatcher.dispatch("not an event")
    end
  end

  def test_dispatch_only_calls_listeners_for_matching_event_type
    failed_called = false
    recovered_called = false

    @dispatcher.on(RR::DatabaseFailedEvent) { |_event| failed_called = true }
    @dispatcher.on(RR::DatabaseRecoveredEvent) { |_event| recovered_called = true }

    event = RR::DatabaseFailedEvent.new(
      database_id: "db-1",
      region: "us-east-1",
      error: "Test"
    )
    @dispatcher.dispatch(event)

    assert failed_called
    refute recovered_called
  end

  def test_dispatch_continues_on_listener_error
    call_count = 0

    # This listener will raise an error
    @dispatcher.on(RR::DatabaseFailedEvent) { |_event| raise "Error!" }

    # This listener should still be called
    @dispatcher.on(RR::DatabaseFailedEvent) { |_event| call_count += 1 }

    event = RR::DatabaseFailedEvent.new(
      database_id: "db-1",
      region: "us-east-1",
      error: "Test"
    )

    # Should not raise
    @dispatcher.dispatch(event)

    # Second listener should have been called
    assert_equal 1, call_count
  end

  # ============================================================
  # EventDispatcher - Listener Management
  # ============================================================

  def test_listener_count
    @dispatcher.on(RR::DatabaseFailedEvent) { |_event| }
    @dispatcher.on(RR::DatabaseFailedEvent) { |_event| }

    assert_equal 2, @dispatcher.listener_count(RR::DatabaseFailedEvent)
  end

  def test_listener_count_for_unregistered_event
    assert_equal 0, @dispatcher.listener_count(RR::DatabaseFailedEvent)
  end

  def test_listener_count_raises_with_non_event_class
    assert_raises(ArgumentError) do
      @dispatcher.listener_count(String)
    end
  end

  def test_listeners_predicate
    refute @dispatcher.listeners?(RR::DatabaseFailedEvent)

    @dispatcher.on(RR::DatabaseFailedEvent) { |_event| }

    assert @dispatcher.listeners?(RR::DatabaseFailedEvent)
  end

  def test_clear_listeners_for_specific_event
    @dispatcher.on(RR::DatabaseFailedEvent) { |_event| }
    @dispatcher.on(RR::DatabaseFailedEvent) { |_event| }
    @dispatcher.on(RR::DatabaseRecoveredEvent) { |_event| }

    count = @dispatcher.clear_listeners(RR::DatabaseFailedEvent)

    assert_equal 2, count
    assert_equal 0, @dispatcher.listener_count(RR::DatabaseFailedEvent)
    assert_equal 1, @dispatcher.listener_count(RR::DatabaseRecoveredEvent)
  end

  def test_clear_all_listeners
    @dispatcher.on(RR::DatabaseFailedEvent) { |_event| }
    @dispatcher.on(RR::DatabaseRecoveredEvent) { |_event| }
    @dispatcher.on(RR::FailoverEvent) { |_event| }

    count = @dispatcher.clear_listeners

    assert_equal 3, count
    assert_equal 0, @dispatcher.listener_count(RR::DatabaseFailedEvent)
    assert_equal 0, @dispatcher.listener_count(RR::DatabaseRecoveredEvent)
    assert_equal 0, @dispatcher.listener_count(RR::FailoverEvent)
  end

  def test_clear_listeners_raises_with_non_event_class
    assert_raises(ArgumentError) do
      @dispatcher.clear_listeners(String)
    end
  end

  # ============================================================
  # EventDispatcher - Thread Safety
  # ============================================================

  def test_thread_safe_listener_registration
    threads = 10.times.map do
      Thread.new do
        10.times do
          @dispatcher.on(RR::DatabaseFailedEvent) { |_event| }
        end
      end
    end

    threads.each(&:join)

    assert_equal 100, @dispatcher.listener_count(RR::DatabaseFailedEvent)
  end

  def test_thread_safe_event_dispatching
    counter = 0
    mutex = Mutex.new

    @dispatcher.on(RR::DatabaseFailedEvent) do |_event|
      mutex.synchronize { counter += 1 }
    end

    threads = 10.times.map do
      Thread.new do
        10.times do
          event = RR::DatabaseFailedEvent.new(
            database_id: "db-1",
            region: "us-east-1",
            error: "Test"
          )
          @dispatcher.dispatch(event)
        end
      end
    end

    threads.each(&:join)

    assert_equal 100, counter
  end

  # ============================================================
  # EventDispatcher - Logger Integration
  # ============================================================

  def test_logger_integration
    log_output = StringIO.new
    logger = Logger.new(log_output)
    dispatcher = RR::EventDispatcher.new(logger: logger)

    # Register a listener that raises an error
    dispatcher.on(RR::DatabaseFailedEvent) { |_event| raise "Test error" }

    event = RR::DatabaseFailedEvent.new(
      database_id: "db-1",
      region: "us-east-1",
      error: "Test"
    )
    dispatcher.dispatch(event)

    log_content = log_output.string
    assert_includes log_content, "Error in event listener"
    assert_includes log_content, "Test error"
  end
end

