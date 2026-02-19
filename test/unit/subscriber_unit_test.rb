# frozen_string_literal: true

require_relative "unit_test_helper"

# Mock client that provides host/port/db/timeout for Subscriber config extraction
class SubscriberMockClient
  attr_accessor :host, :port, :db, :timeout

  def initialize(host: "localhost", port: 6379, db: 0, timeout: 5.0)
    @host = host
    @port = port
    @db = db
    @timeout = timeout
  end
end

# Mock connection for the Subscriber's internal use
class SubscriberMockConnection
  attr_reader :calls, :closed

  def initialize
    @calls = []
    @closed = false
    @decoder = nil
  end

  def call(*args)
    @calls << args
  end

  def close
    @closed = true
  end
end

class SubscriberUnitTest < Minitest::Test
  def setup
    @mock_client = SubscriberMockClient.new
  end

  # ============================================================
  # Initialization
  # ============================================================

  def test_initialize_sets_empty_channels
    subscriber = RR::Subscriber.new(@mock_client)

    assert_empty subscriber.channels
  end

  def test_initialize_sets_empty_patterns
    subscriber = RR::Subscriber.new(@mock_client)

    assert_empty subscriber.patterns
  end

  def test_initialize_not_running
    subscriber = RR::Subscriber.new(@mock_client)

    refute_predicate subscriber, :running?
  end

  def test_initialize_not_stop_requested
    subscriber = RR::Subscriber.new(@mock_client)

    refute_predicate subscriber, :stop_requested?
  end

  def test_initialize_thread_nil
    subscriber = RR::Subscriber.new(@mock_client)

    assert_nil subscriber.thread
  end

  def test_initialize_extracts_client_config
    client = SubscriberMockClient.new(host: "redis.example.com", port: 6380, db: 2, timeout: 10.0)
    subscriber = RR::Subscriber.new(client)
    config = subscriber.instance_variable_get(:@client_config)

    assert_equal "redis.example.com", config[:host]
    assert_equal 6380, config[:port]
    assert_equal 2, config[:db]
    assert_in_delta(10.0, config[:timeout])
  end
  # ============================================================
  # Channel / Pattern subscription registration
  # ============================================================

  def test_subscribe_adds_channels
    subscriber = RR::Subscriber.new(@mock_client)
    result = subscriber.subscribe("ch1", "ch2")

    assert_equal %w[ch1 ch2], subscriber.channels
    assert_same subscriber, result # returns self for chaining
  end

  def test_subscribe_accumulates_channels
    subscriber = RR::Subscriber.new(@mock_client)
    subscriber.subscribe("ch1")
    subscriber.subscribe("ch2", "ch3")

    assert_equal %w[ch1 ch2 ch3], subscriber.channels
  end

  def test_psubscribe_adds_patterns
    subscriber = RR::Subscriber.new(@mock_client)
    result = subscriber.psubscribe("news.*", "sports.*")

    assert_equal ["news.*", "sports.*"], subscriber.patterns
    assert_same subscriber, result
  end

  def test_psubscribe_accumulates_patterns
    subscriber = RR::Subscriber.new(@mock_client)
    subscriber.psubscribe("news.*")
    subscriber.psubscribe("sports.*")

    assert_equal ["news.*", "sports.*"], subscriber.patterns
  end

  def test_ssubscribe_adds_shard_channels
    subscriber = RR::Subscriber.new(@mock_client)
    result = subscriber.ssubscribe("shard1", "shard2")
    shard_channels = subscriber.instance_variable_get(:@shard_channels)

    assert_equal %w[shard1 shard2], shard_channels
    assert_same subscriber, result
  end
  # ============================================================
  # Callback registration
  # ============================================================

  def test_on_message_registers_callback
    subscriber = RR::Subscriber.new(@mock_client)
    block = proc { |_ch, _msg| }
    result = subscriber.on_message(&block)
    callbacks = subscriber.instance_variable_get(:@callbacks)

    assert_equal block, callbacks[:message]
    assert_same subscriber, result
  end

  def test_on_pmessage_registers_callback
    subscriber = RR::Subscriber.new(@mock_client)
    block = proc { |_p, _ch, _msg| }
    result = subscriber.on_pmessage(&block)
    callbacks = subscriber.instance_variable_get(:@callbacks)

    assert_equal block, callbacks[:pmessage]
    assert_same subscriber, result
  end

  def test_on_smessage_registers_callback
    subscriber = RR::Subscriber.new(@mock_client)
    block = proc { |_ch, _msg| }
    result = subscriber.on_smessage(&block)
    callbacks = subscriber.instance_variable_get(:@callbacks)

    assert_equal block, callbacks[:smessage]
    assert_same subscriber, result
  end

  def test_on_subscribe_registers_callback
    subscriber = RR::Subscriber.new(@mock_client)
    block = proc { |_ch, _count| }
    result = subscriber.on_subscribe(&block)
    callbacks = subscriber.instance_variable_get(:@callbacks)

    assert_equal block, callbacks[:subscribe]
    assert_same subscriber, result
  end

  def test_on_unsubscribe_registers_callback
    subscriber = RR::Subscriber.new(@mock_client)
    block = proc { |_ch, _count| }
    result = subscriber.on_unsubscribe(&block)
    callbacks = subscriber.instance_variable_get(:@callbacks)

    assert_equal block, callbacks[:unsubscribe]
    assert_same subscriber, result
  end

  def test_on_error_registers_callback
    subscriber = RR::Subscriber.new(@mock_client)
    block = proc { |_err| }
    result = subscriber.on_error(&block)
    callbacks = subscriber.instance_variable_get(:@callbacks)

    assert_equal block, callbacks[:error]
    assert_same subscriber, result
  end
  # ============================================================
  # Fluent chaining
  # ============================================================

  def test_fluent_chaining
    subscriber = RR::Subscriber.new(@mock_client)
    result = subscriber
      .on_message { |_ch, _msg| nil }
      .on_error { |_e| nil }
      .subscribe("ch1")
      .psubscribe("p*")

    assert_same subscriber, result
    assert_equal ["ch1"], subscriber.channels
    assert_equal ["p*"], subscriber.patterns
  end
  # ============================================================
  # running? / stop_requested?
  # ============================================================

  def test_running_false_initially
    subscriber = RR::Subscriber.new(@mock_client)

    refute_predicate subscriber, :running?
  end

  def test_stop_requested_false_initially
    subscriber = RR::Subscriber.new(@mock_client)

    refute_predicate subscriber, :stop_requested?
  end
end

class SubscriberUnitTestPart2 < Minitest::Test
  def setup
    @mock_client = SubscriberMockClient.new
  end

  # ============================================================
  # Initialization
  # ============================================================

  # ============================================================
  # process_message (private, but important for coverage)
  # ============================================================

  def test_process_message_subscribe
    subscriber = RR::Subscriber.new(@mock_client)
    received = nil
    subscriber.on_subscribe { |ch, count| received = [ch, count] }

    result = subscriber.send(:process_message, ["subscribe", "ch1", 1], 0)

    assert_equal 1, result
    assert_equal ["ch1", 1], received
  end

  def test_process_message_psubscribe
    subscriber = RR::Subscriber.new(@mock_client)
    received = nil
    subscriber.on_subscribe { |ch, count| received = [ch, count] }

    result = subscriber.send(:process_message, ["psubscribe", "p*", 2], 0)

    assert_equal 2, result
    assert_equal ["p*", 2], received
  end

  def test_process_message_ssubscribe
    subscriber = RR::Subscriber.new(@mock_client)
    received = nil
    subscriber.on_subscribe { |ch, count| received = [ch, count] }

    result = subscriber.send(:process_message, ["ssubscribe", "s1", 3], 0)

    assert_equal 3, result
    assert_equal ["s1", 3], received
  end

  def test_process_message_unsubscribe
    subscriber = RR::Subscriber.new(@mock_client)
    received = nil
    subscriber.on_unsubscribe { |ch, count| received = [ch, count] }

    result = subscriber.send(:process_message, ["unsubscribe", "ch1", 0], 1)

    assert_equal 0, result
    assert_equal ["ch1", 0], received
  end

  def test_process_message_punsubscribe
    subscriber = RR::Subscriber.new(@mock_client)
    received = nil
    subscriber.on_unsubscribe { |ch, count| received = [ch, count] }

    result = subscriber.send(:process_message, ["punsubscribe", "p*", 1], 2)

    assert_equal 1, result
    assert_equal ["p*", 1], received
  end

  def test_process_message_sunsubscribe
    subscriber = RR::Subscriber.new(@mock_client)
    received = nil
    subscriber.on_unsubscribe { |ch, count| received = [ch, count] }

    result = subscriber.send(:process_message, ["sunsubscribe", "s1", 0], 1)

    assert_equal 0, result
    assert_equal ["s1", 0], received
  end

  def test_process_message_message
    subscriber = RR::Subscriber.new(@mock_client)
    received = nil
    subscriber.on_message { |ch, msg| received = [ch, msg] }

    result = subscriber.send(:process_message, %w[message ch1 hello], 1)

    assert_equal 1, result
    assert_equal %w[ch1 hello], received
  end

  def test_process_message_pmessage
    subscriber = RR::Subscriber.new(@mock_client)
    received = nil
    subscriber.on_pmessage { |pattern, ch, msg| received = [pattern, ch, msg] }

    result = subscriber.send(:process_message, ["pmessage", "news.*", "news.tech", "article"], 1)

    assert_equal 1, result
    assert_equal ["news.*", "news.tech", "article"], received
  end

  def test_process_message_smessage
    subscriber = RR::Subscriber.new(@mock_client)
    received = nil
    subscriber.on_smessage { |ch, msg| received = [ch, msg] }

    result = subscriber.send(:process_message, %w[smessage shard1 data], 2)

    assert_equal 2, result
    assert_equal %w[shard1 data], received
  end

  def test_process_message_not_an_array
    subscriber = RR::Subscriber.new(@mock_client)
    result = subscriber.send(:process_message, "not_array", 5)

    assert_equal 5, result # returns subscriptions unchanged
  end

  def test_process_message_empty_array
    subscriber = RR::Subscriber.new(@mock_client)
    result = subscriber.send(:process_message, [], 5)

    assert_equal 5, result
  end

  def test_process_message_unknown_type
    subscriber = RR::Subscriber.new(@mock_client)
    result = subscriber.send(:process_message, %w[unknown_type data], 3)

    assert_equal 3, result
  end
  # ============================================================
  # call_callback (private, error handling)
  # ============================================================

  def test_call_callback_with_registered_callback
    subscriber = RR::Subscriber.new(@mock_client)
    received = nil
    subscriber.on_message { |ch, msg| received = [ch, msg] }

    subscriber.send(:call_callback, :message, "ch1", "msg1")

    assert_equal %w[ch1 msg1], received
  end

  def test_call_callback_with_no_callback_registered
    subscriber = RR::Subscriber.new(@mock_client)
    # Should not raise
    subscriber.send(:call_callback, :message, "ch1", "msg1")
  end

  def test_call_callback_error_handled_by_on_error
    subscriber = RR::Subscriber.new(@mock_client)
    error_received = nil
    subscriber.on_message { |_ch, _msg| raise "test error" }
    subscriber.on_error { |e| error_received = e }

    subscriber.send(:call_callback, :message, "ch1", "msg1")

    assert_instance_of RuntimeError, error_received
    assert_equal "test error", error_received.message
  end
end

class SubscriberUnitTestPart3 < Minitest::Test
  def setup
    @mock_client = SubscriberMockClient.new
  end

  # ============================================================
  # Initialization
  # ============================================================

  # ============================================================
  # handle_error (private)
  # ============================================================

  def test_handle_error_with_error_callback
    subscriber = RR::Subscriber.new(@mock_client)
    error_received = nil
    subscriber.on_error { |e| error_received = e }

    error = RuntimeError.new("test")
    subscriber.send(:handle_error, error)

    assert_same error, error_received
  end

  def test_handle_error_without_callback_and_no_thread_raises
    subscriber = RR::Subscriber.new(@mock_client)
    # No error callback, no thread - should raise
    assert_raises(RuntimeError) do
      subscriber.send(:handle_error, RuntimeError.new("test"))
    end
  end

  def test_handle_error_without_callback_with_thread_does_not_raise
    subscriber = RR::Subscriber.new(@mock_client)
    # Simulate being in a thread
    subscriber.instance_variable_set(:@thread, Thread.current)

    # Should NOT raise (thread absorbs it)
    subscriber.send(:handle_error, RuntimeError.new("test"))
  end
  # ============================================================
  # stop
  # ============================================================

  def test_stop_sets_stop_requested
    subscriber = RR::Subscriber.new(@mock_client)
    subscriber.stop(wait: false)

    assert_predicate subscriber, :stop_requested?
  end

  def test_stop_sends_unsubscribe_commands
    subscriber = RR::Subscriber.new(@mock_client)
    subscriber.subscribe("ch1")
    subscriber.psubscribe("p*")
    subscriber.ssubscribe("s1")

    mock_conn = SubscriberMockConnection.new
    subscriber.instance_variable_set(:@connection, mock_conn)

    subscriber.stop(wait: false)

    # Should have sent UNSUBSCRIBE, PUNSUBSCRIBE, and SUNSUBSCRIBE
    assert_includes mock_conn.calls, ["UNSUBSCRIBE"]
    assert_includes mock_conn.calls, ["PUNSUBSCRIBE"]
    assert_includes mock_conn.calls, ["SUNSUBSCRIBE"]
  end

  def test_stop_does_not_send_unsubscribe_for_empty_channels
    subscriber = RR::Subscriber.new(@mock_client)
    # No channels/patterns registered

    mock_conn = SubscriberMockConnection.new
    subscriber.instance_variable_set(:@connection, mock_conn)

    subscriber.stop(wait: false)

    # Should NOT have sent any unsubscribe commands
    assert_empty mock_conn.calls
  end

  def test_stop_with_no_connection
    subscriber = RR::Subscriber.new(@mock_client)
    subscriber.subscribe("ch1")
    # No connection set - should not raise
    subscriber.stop(wait: false)

    assert_predicate subscriber, :stop_requested?
  end

  def test_stop_ignores_errors_during_unsubscribe
    subscriber = RR::Subscriber.new(@mock_client)
    subscriber.subscribe("ch1")

    # Create a mock connection that raises on call
    error_conn = Object.new
    def error_conn.call(*)
      raise StandardError, "connection lost"
    end
    subscriber.instance_variable_set(:@connection, error_conn)

    # Should not raise
    subscriber.stop(wait: false)

    assert_predicate subscriber, :stop_requested?
  end
  # ============================================================
  # send_subscriptions (private)
  # ============================================================

  def test_send_subscriptions_with_channels
    subscriber = RR::Subscriber.new(@mock_client)
    subscriber.subscribe("ch1", "ch2")

    mock_conn = SubscriberMockConnection.new
    subscriber.instance_variable_set(:@connection, mock_conn)

    subscriber.send(:send_subscriptions)

    assert_includes mock_conn.calls, %w[SUBSCRIBE ch1 ch2]
  end

  def test_send_subscriptions_with_patterns
    subscriber = RR::Subscriber.new(@mock_client)
    subscriber.psubscribe("news.*")

    mock_conn = SubscriberMockConnection.new
    subscriber.instance_variable_set(:@connection, mock_conn)

    subscriber.send(:send_subscriptions)

    assert_includes mock_conn.calls, ["PSUBSCRIBE", "news.*"]
  end

  def test_send_subscriptions_with_shard_channels
    subscriber = RR::Subscriber.new(@mock_client)
    subscriber.ssubscribe("shard1")

    mock_conn = SubscriberMockConnection.new
    subscriber.instance_variable_set(:@connection, mock_conn)

    subscriber.send(:send_subscriptions)

    assert_includes mock_conn.calls, %w[SSUBSCRIBE shard1]
  end

  def test_send_subscriptions_skips_empty_channels
    subscriber = RR::Subscriber.new(@mock_client)
    # No channels registered

    mock_conn = SubscriberMockConnection.new
    subscriber.instance_variable_set(:@connection, mock_conn)

    subscriber.send(:send_subscriptions)

    assert_empty mock_conn.calls
  end

  def test_send_subscriptions_all_types
    subscriber = RR::Subscriber.new(@mock_client)
    subscriber.subscribe("ch1")
    subscriber.psubscribe("p*")
    subscriber.ssubscribe("s1")

    mock_conn = SubscriberMockConnection.new
    subscriber.instance_variable_set(:@connection, mock_conn)

    subscriber.send(:send_subscriptions)

    assert_equal 3, mock_conn.calls.size
    assert_includes mock_conn.calls, %w[SUBSCRIBE ch1]
    assert_includes mock_conn.calls, ["PSUBSCRIBE", "p*"]
    assert_includes mock_conn.calls, %w[SSUBSCRIBE s1]
  end
  # ============================================================
  # read_message (private)
  # ============================================================

  def test_read_message_delegates_to_connection_read_response
    subscriber = RR::Subscriber.new(@mock_client)
    mock_conn = mock("connection")
    mock_conn.expects(:read_response).returns(%w[message ch1 hello])
    subscriber.instance_variable_set(:@connection, mock_conn)

    result = subscriber.send(:read_message)

    assert_equal %w[message ch1 hello], result
  end
end

class SubscriberUnitTestPart4 < Minitest::Test
  def setup
    @mock_client = SubscriberMockClient.new
  end

  # ============================================================
  # Initialization
  # ============================================================

  # ============================================================
  # extract_client_config (private)
  # ============================================================

  def test_extract_client_config
    client = SubscriberMockClient.new(host: "10.0.0.1", port: 6380, db: 3, timeout: 15.0)
    subscriber = RR::Subscriber.new(client)
    config = subscriber.instance_variable_get(:@client_config)

    assert_equal "10.0.0.1", config[:host]
    assert_equal 6380, config[:port]
    assert_equal 3, config[:db]
    assert_in_delta(15.0, config[:timeout])
  end

  def test_extract_client_config_includes_password
    client = SubscriberMockClient.new
    client.define_singleton_method(:password) { "secret" }
    subscriber = RR::Subscriber.new(client)
    config = subscriber.instance_variable_get(:@client_config)

    assert_equal "secret", config[:password]
  end

  def test_extract_client_config_includes_ssl
    client = SubscriberMockClient.new
    client.define_singleton_method(:ssl) { true }
    client.define_singleton_method(:ssl_params) { { verify_mode: 1 } }
    subscriber = RR::Subscriber.new(client)
    config = subscriber.instance_variable_get(:@client_config)

    assert config[:ssl]
    assert_equal({ verify_mode: 1 }, config[:ssl_params])
  end

  def test_create_connection_uses_ssl_when_configured
    client = SubscriberMockClient.new
    client.define_singleton_method(:ssl) { true }
    client.define_singleton_method(:ssl_params) { {} }
    subscriber = RR::Subscriber.new(client)

    mock_ssl_conn = mock("ssl_conn")
    RR::Connection::SSL.expects(:new).with(
      host: "localhost",
      port: 6379,
      timeout: 5.0,
      ssl_params: {}
    ).returns(mock_ssl_conn)

    conn = subscriber.send(:create_connection)

    assert_equal mock_ssl_conn, conn
  end

  def test_authenticate_called_when_password_set
    client = SubscriberMockClient.new
    client.define_singleton_method(:password) { "secret" }
    subscriber = RR::Subscriber.new(client)

    mock_conn = SubscriberMockConnection.new
    subscriber.instance_variable_set(:@connection, mock_conn)

    subscriber.send(:authenticate_if_needed)

    assert_includes mock_conn.calls, %w[AUTH secret]
  end

  def test_authenticate_not_called_without_password
    client = SubscriberMockClient.new
    subscriber = RR::Subscriber.new(client)

    mock_conn = SubscriberMockConnection.new
    subscriber.instance_variable_set(:@connection, mock_conn)

    subscriber.send(:authenticate_if_needed)

    refute(mock_conn.calls.any? { |c| c[0] == "AUTH" })
  end
end
