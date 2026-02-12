# frozen_string_literal: true

require "test_helper"
require_relative "../../../lib/redis_ruby/broadcaster"

class PubSubDSLTest < RedisRubyTestCase
  use_testcontainers!

  def setup
    super
    @channel = "test:channel:#{SecureRandom.hex(8)}"
    # Create separate client for publishing (can't share connection with subscriber)
    @publisher_redis = RedisRuby.new(url: @redis_url)
  end

  def teardown
    @publisher_redis&.close
    super
  end

  # ============================================================
  # PublisherProxy Tests
  # ============================================================

  def test_publisher_proxy_creation
    publisher = redis.publisher(:events)
    
    assert_instance_of RedisRuby::DSL::PublisherProxy, publisher
    assert_equal ["events"], publisher.channels
  end

  def test_publisher_send_to_single_channel
    publisher = @publisher_redis.publisher(@channel)
    received = nil

    # Publisher thread that sleeps briefly, then publishes
    publisher_thread = Thread.new do
      sleep 0.1
      publisher.send("Hello, World!")
      sleep 0.1
    end

    # Subscribe and unsubscribe from inside the message callback
    redis.subscribe(@channel) do |on|
      on.message do |_ch, msg|
        received = msg
        redis.unsubscribe
      end
    end

    publisher_thread.join

    assert_equal "Hello, World!", received
  end

  def test_publisher_chainable_sends
    publisher = @publisher_redis.publisher(@channel)
    messages = []

    # Publisher thread that sleeps briefly, then publishes
    publisher_thread = Thread.new do
      sleep 0.1
      publisher.send("Message 1").send("Message 2").send("Message 3")
      sleep 0.1
    end

    # Subscribe and unsubscribe from inside the message callback
    redis.subscribe(@channel) do |on|
      on.message do |_ch, msg|
        messages << msg
        redis.unsubscribe if messages.size >= 3
      end
    end

    publisher_thread.join

    assert_equal 3, messages.length
    assert_includes messages, "Message 1"
  end

  def test_publisher_to_multiple_channels
    channel1 = "#{@channel}:1"
    channel2 = "#{@channel}:2"
    messages = []

    # Publisher thread that sleeps briefly, then publishes
    publisher_thread = Thread.new do
      sleep 0.1
      @publisher_redis.publisher.to(channel1, channel2).send("Broadcast")
      sleep 0.1
    end

    # Subscribe to both channels and unsubscribe after receiving 2 messages
    redis.subscribe(channel1, channel2) do |on|
      on.message do |ch, msg|
        messages << [ch, msg]
        redis.unsubscribe if messages.size >= 2
      end
    end

    publisher_thread.join

    assert_equal 2, messages.size
    channels = messages.map(&:first)
    assert_includes channels, channel1
    assert_includes channels, channel2
    assert_equal "Broadcast", messages[0][1]
    assert_equal "Broadcast", messages[1][1]
  end

  def test_publisher_json_encoding
    publisher = @publisher_redis.publisher(@channel)
    received = nil

    # Publisher thread that sleeps briefly, then publishes
    publisher_thread = Thread.new do
      sleep 0.1
      publisher.send(event: "order_created", order_id: 123)
      sleep 0.1
    end

    # Subscribe and unsubscribe from inside the message callback
    redis.subscribe(@channel) do |on|
      on.message do |_ch, msg|
        received = msg
        redis.unsubscribe
      end
    end

    publisher_thread.join

    assert_kind_of String, received
    data = JSON.parse(received)
    assert_equal "order_created", data["event"]
    assert_equal 123, data["order_id"]
  end

  def test_publisher_subscriber_count
    publisher = @publisher_redis.publisher(@channel)

    # No subscribers initially
    assert_equal({@channel => 0}, publisher.subscriber_count)

    subscriber_ready = false
    count = nil

    # Subscriber thread
    subscriber_thread = Thread.new do
      redis.subscribe(@channel) do |on|
        on.subscribe do |_ch, _count|
          subscriber_ready = true
        end

        on.message do |_ch, _msg|
          redis.unsubscribe
        end
      end
    end

    # Wait for subscriber to be ready
    sleep 0.1 until subscriber_ready
    sleep 0.05

    count = publisher.subscriber_count

    # Trigger unsubscribe by publishing a message
    @publisher_redis.publish(@channel, "trigger")
    subscriber_thread.join

    assert_equal 1, count[@channel]
  end

  def test_publisher_raises_without_channels
    publisher = redis.publisher
    
    error = assert_raises(ArgumentError) do
      publisher.send("Hello")
    end
    
    assert_match(/No channels specified/, error.message)
  end

  # ============================================================
  # SubscriberBuilder Tests
  # ============================================================

  def test_subscriber_builder_creation
    subscriber = redis.subscriber

    assert_instance_of RedisRuby::DSL::SubscriberBuilder, subscriber
  end

  def test_subscriber_on_single_channel
    received = []

    subscriber = redis.subscriber.on(@channel) do |channel, message|
      received << [channel, message]
      subscriber.stop(wait: false) if received.size >= 1
    end

    # Publisher thread that sleeps briefly, then publishes
    publisher_thread = Thread.new do
      sleep 0.1
      @publisher_redis.publish(@channel, "Test message")
      sleep 0.1
    end

    thread = subscriber.run_async
    thread.join
    publisher_thread.join

    assert_equal 1, received.length
    assert_equal @channel, received[0][0]
    assert_equal "Test message", received[0][1]
  end

  def test_subscriber_on_multiple_channels
    channel1 = "#{@channel}:1"
    channel2 = "#{@channel}:2"
    received = []

    subscriber = redis.subscriber.on(channel1, channel2) do |channel, message|
      received << [channel, message]
      subscriber.stop(wait: false) if received.size >= 2
    end

    # Publisher thread that sleeps briefly, then publishes
    publisher_thread = Thread.new do
      sleep 0.1
      @publisher_redis.publish(channel1, "Message 1")
      @publisher_redis.publish(channel2, "Message 2")
      sleep 0.1
    end

    thread = subscriber.run_async
    thread.join
    publisher_thread.join

    assert_equal 2, received.length
    assert_includes received.map(&:first), channel1
    assert_includes received.map(&:first), channel2
  end

  def test_subscriber_on_pattern
    pattern = "#{@channel}:*"
    channel1 = "#{@channel}:news"
    channel2 = "#{@channel}:sports"
    received = []

    subscriber = redis.subscriber.on_pattern(pattern) do |pat, channel, message|
      received << [pat, channel, message]
      subscriber.stop(wait: false) if received.size >= 2
    end

    # Publisher thread that sleeps briefly, then publishes
    publisher_thread = Thread.new do
      sleep 0.1
      @publisher_redis.publish(channel1, "News update")
      @publisher_redis.publish(channel2, "Sports update")
      sleep 0.1
    end

    thread = subscriber.run_async
    thread.join
    publisher_thread.join

    assert_equal 2, received.length
    assert_equal pattern, received[0][0]
    assert_includes received.map { |r| r[1] }, channel1
  end

  def test_subscriber_json_decoding
    received = nil

    subscriber = redis.subscriber.on(@channel, json: true) do |_channel, data|
      received = data
      subscriber.stop(wait: false)
    end

    # Publisher thread that sleeps briefly, then publishes
    publisher_thread = Thread.new do
      sleep 0.1
      @publisher_redis.publish(@channel, JSON.generate(event: "test", value: 123))
      sleep 0.1
    end

    thread = subscriber.run_async
    thread.join
    publisher_thread.join

    assert_kind_of Hash, received
    assert_equal "test", received["event"]
    assert_equal 123, received["value"]
  end

  def test_subscriber_chainable_on_methods
    channel1 = "#{@channel}:1"
    channel2 = "#{@channel}:2"
    pattern = "#{@channel}:pattern:*"

    received_channels = []
    received_patterns = []

    subscriber = redis.subscriber
      .on(channel1) do |ch, msg|
        received_channels << [ch, msg]
        subscriber.stop(wait: false) if received_channels.size + received_patterns.size >= 3
      end
      .on(channel2) do |ch, msg|
        received_channels << [ch, msg]
        subscriber.stop(wait: false) if received_channels.size + received_patterns.size >= 3
      end
      .on_pattern(pattern) do |pat, ch, msg|
        received_patterns << [pat, ch, msg]
        subscriber.stop(wait: false) if received_channels.size + received_patterns.size >= 3
      end

    # Publisher thread that sleeps briefly, then publishes
    publisher_thread = Thread.new do
      sleep 0.1
      @publisher_redis.publish(channel1, "Message 1")
      @publisher_redis.publish(channel2, "Message 2")
      @publisher_redis.publish("#{@channel}:pattern:test", "Pattern message")
      sleep 0.1
    end

    thread = subscriber.run_async
    thread.join
    publisher_thread.join

    assert_equal 2, received_channels.length
    assert_equal 1, received_patterns.length
  end

  def test_subscriber_raises_without_subscriptions
    subscriber = redis.subscriber

    error = assert_raises(ArgumentError) do
      subscriber.run
    end

    assert_match(/No subscriptions configured/, error.message)
  end

  def test_subscriber_raises_without_block
    error = assert_raises(ArgumentError) do
      redis.subscriber.on(@channel)
    end

    assert_match(/Block required/, error.message)
  end

  def test_subscriber_running_status
    received = []
    subscriber = redis.subscriber.on(@channel) do |_ch, msg|
      received << msg
      subscriber.stop(wait: false) if received.size >= 1
    end

    refute subscriber.running?

    # Publisher thread
    publisher_thread = Thread.new do
      sleep 0.1
      @publisher_redis.publish(@channel, "test")
      sleep 0.1
    end

    thread = subscriber.run_async
    sleep 0.1

    assert subscriber.running?

    publisher_thread.join
    thread.join(1)

    refute subscriber.running?
  end

  # ============================================================
  # Broadcaster Module Tests
  # ============================================================

  def test_broadcaster_mixin
    service_class = Class.new do
      include RedisRuby::Broadcaster

      def initialize(redis_client)
        self.redis_client = redis_client
      end

      def do_something
        broadcast(:something_happened, value: 123)
      end
    end

    service = service_class.new(redis)

    # Should have broadcast method
    assert_respond_to service, :broadcast
    assert_respond_to service, :on
  end

  def test_broadcaster_channel_prefix
    service_class = Class.new do
      include RedisRuby::Broadcaster

      def self.name
        "OrderService"
      end
    end

    assert_equal "order_service", service_class.channel_prefix
  end

  def test_broadcaster_custom_channel_prefix
    service_class = Class.new do
      include RedisRuby::Broadcaster
      set_channel_prefix :custom_prefix
    end

    assert_equal "custom_prefix", service_class.channel_prefix
  end

  def test_broadcaster_broadcast_publishes_to_redis
    service_class = Class.new do
      include RedisRuby::Broadcaster

      def self.name
        "TestService"
      end

      def initialize(redis_client)
        self.redis_client = redis_client
      end

      def trigger_event
        broadcast(:event_triggered, data: "test")
      end
    end

    service = service_class.new(@publisher_redis)
    received = nil

    # Publisher thread that sleeps briefly, then triggers event
    publisher_thread = Thread.new do
      sleep 0.1
      service.trigger_event
      sleep 0.1
    end

    # Subscribe and unsubscribe from inside the message callback
    redis.subscribe("test_service:event_triggered") do |on|
      on.message do |_ch, msg|
        received = msg
        redis.unsubscribe
      end
    end

    publisher_thread.join

    assert_kind_of String, received
    data = JSON.parse(received)
    assert_equal "test", data["data"]
  end

  def test_broadcaster_broadcast_with_string_argument
    service_class = Class.new do
      include RedisRuby::Broadcaster

      def self.name
        "TestService"
      end

      def initialize(redis_client)
        self.redis_client = redis_client
      end

      def trigger_event
        broadcast(:event_triggered, "simple message")
      end
    end

    service = service_class.new(@publisher_redis)
    received = nil

    # Publisher thread that sleeps briefly, then triggers event
    publisher_thread = Thread.new do
      sleep 0.2  # Give subscriber more time to connect
      service.trigger_event
      sleep 0.1
    end

    # Subscribe and unsubscribe from inside the message callback
    redis.subscribe("test_service:event_triggered") do |on|
      on.message do |_ch, msg|
        received = msg
        redis.unsubscribe
      end
    end

    publisher_thread.join

    assert_equal "simple message", received
  end

  # ============================================================
  # Integration Tests
  # ============================================================

  def test_publisher_and_subscriber_integration
    publisher = @publisher_redis.publisher(@channel)
    received = []

    subscriber = redis.subscriber.on(@channel) do |channel, message|
      received << message
      subscriber.stop(wait: false) if received.size >= 3
    end

    # Publisher thread that sleeps briefly, then publishes
    publisher_thread = Thread.new do
      sleep 0.1
      publisher.send("Message 1")
        .send("Message 2")
        .send("Message 3")
      sleep 0.1
    end

    thread = subscriber.run_async
    thread.join
    publisher_thread.join

    assert_equal 3, received.length
    assert_equal ["Message 1", "Message 2", "Message 3"], received
  end

  def test_json_encoding_and_decoding_integration
    publisher = @publisher_redis.publisher(@channel)
    received = nil

    subscriber = redis.subscriber.on(@channel, json: true) do |_ch, data|
      received = data
      subscriber.stop(wait: false)
    end

    # Publisher thread that sleeps briefly, then publishes
    publisher_thread = Thread.new do
      sleep 0.1
      publisher.send(event: "test", value: 42, nested: { key: "value" })
      sleep 0.1
    end

    thread = subscriber.run_async
    thread.join
    publisher_thread.join

    assert_kind_of Hash, received
    assert_equal "test", received["event"]
    assert_equal 42, received["value"]
    assert_equal({ "key" => "value" }, received["nested"])
  end
end


