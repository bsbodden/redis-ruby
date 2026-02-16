# frozen_string_literal: true

require "test_helper"

class PubSubIntegrationTest < RedisRubyTestCase
  use_testcontainers!

  def setup
    super
    @channel_prefix = "pubsub:test:#{SecureRandom.hex(4)}"
    # Publisher needs its own connection for concurrent operations
    @publisher = create_publisher_connection
  end

  def teardown
    begin
      @publisher&.close
    rescue StandardError
      nil
    end
    super
  end

  private

  def create_publisher_connection
    # Use the same URL as the main redis connection (from testcontainers or ENV)
    RR.new(url: @redis_url)
  end

  public

  # PUBLISH tests
  def test_publish_returns_subscriber_count
    # When no subscribers, returns 0
    result = redis.publish("pubsub:test:channel", "hello")

    assert_equal 0, result
  end

  def test_publish_with_message
    result = redis.publish("pubsub:test:channel", "test message")

    assert_kind_of Integer, result
  end

  # PUBSUB CHANNELS tests
  def test_pubsub_channels_empty
    # Returns list of active channels (may be empty or have channels from other tests)
    result = redis.pubsub_channels

    assert_kind_of Array, result
  end

  def test_pubsub_channels_with_pattern
    result = redis.pubsub_channels("pubsub:test:*")

    assert_kind_of Array, result
  end

  # PUBSUB NUMSUB tests
  def test_pubsub_numsub
    result = redis.pubsub_numsub("channel1", "channel2")

    assert_kind_of Hash, result
    assert_equal 0, result["channel1"]
    assert_equal 0, result["channel2"]
  end

  def test_pubsub_numsub_empty
    result = redis.pubsub_numsub

    assert_empty(result)
  end

  # PUBSUB NUMPAT tests
  def test_pubsub_numpat
    result = redis.pubsub_numpat

    assert_kind_of Integer, result
    assert_operator result, :>=, 0
  end

  # Basic subscribe/unsubscribe pattern tests
  def test_subscribe_with_block
    messages = []
    subscribe_count = 0
    unsubscribe_count = 0

    # Use a separate thread to publish
    publisher_thread = Thread.new do
      sleep 0.1 # Wait for subscription to be set up
      @publisher.publish("pubsub:test:block", "message1")
      @publisher.publish("pubsub:test:block", "message2")
      sleep 0.1
    end

    redis.subscribe("pubsub:test:block") do |on|
      on.subscribe do |_channel, _subscriptions|
        subscribe_count += 1
      end

      on.message do |channel, message|
        messages << [channel, message]
        # Unsubscribe after receiving 2 messages
        redis.unsubscribe if messages.size >= 2
      end

      on.unsubscribe do |_channel, _subscriptions|
        unsubscribe_count += 1
      end
    end

    publisher_thread.join

    assert_equal 1, subscribe_count
    assert_equal 1, unsubscribe_count
    assert_equal 2, messages.size
    assert_equal ["pubsub:test:block", "message1"], messages[0]
    assert_equal ["pubsub:test:block", "message2"], messages[1]
  end

  def test_subscribe_multiple_channels
    channels_subscribed = []
    messages = []

    publisher_thread = Thread.new do
      sleep 0.1
      @publisher.publish("pubsub:test:multi1", "msg1")
      @publisher.publish("pubsub:test:multi2", "msg2")
      sleep 0.1
    end

    redis.subscribe("pubsub:test:multi1", "pubsub:test:multi2") do |on|
      on.subscribe do |channel, _count|
        channels_subscribed << channel
      end

      on.message do |channel, message|
        messages << [channel, message]
        redis.unsubscribe if messages.size >= 2
      end
    end

    publisher_thread.join

    assert_includes channels_subscribed, "pubsub:test:multi1"
    assert_includes channels_subscribed, "pubsub:test:multi2"
    assert_equal 2, messages.size
  end

  def test_psubscribe_pattern
    messages = []

    publisher_thread = Thread.new do
      sleep 0.1
      @publisher.publish("pubsub:pattern:foo", "message1")
      @publisher.publish("pubsub:pattern:bar", "message2")
      sleep 0.1
    end

    redis.psubscribe("pubsub:pattern:*") do |on|
      on.psubscribe do |pattern, _count|
        assert_equal "pubsub:pattern:*", pattern
      end

      on.pmessage do |pattern, channel, message|
        messages << [pattern, channel, message]
        redis.punsubscribe if messages.size >= 2
      end
    end

    publisher_thread.join

    assert_equal 2, messages.size
    assert_equal "pubsub:pattern:*", messages[0][0]
    assert_includes ["pubsub:pattern:foo", "pubsub:pattern:bar"], messages[0][1]
  end

  def test_subscribe_timeout
    # Test that subscribe can timeout without blocking forever
    start_time = Time.now

    redis.subscribe_with_timeout(0.5, "pubsub:test:timeout") do |on|
      on.message do |channel, message|
        # Should not receive anything
      end
    end

    elapsed = Time.now - start_time
    # Should timeout around 0.5 seconds (with some tolerance)
    assert_operator elapsed, :>=, 0.4
    assert_operator elapsed, :<, 2.0
  end

  # PUBSUB SHARDCHANNELS tests (Redis 7+)
  def test_pubsub_shardchannels
    result = redis.pubsub_shardchannels

    assert_kind_of Array, result
  rescue RR::CommandError => e
    skip "PUBSUB SHARDCHANNELS not supported" if e.message.include?("unknown subcommand")
    raise
  end

  def test_pubsub_shardnumsub
    result = redis.pubsub_shardnumsub("shard:channel1")

    assert_kind_of Hash, result
  rescue RR::CommandError => e
    skip "PUBSUB SHARDNUMSUB not supported" if e.message.include?("unknown subcommand")
    raise
  end

  # ============================================================
  # Sharded PubSub Tests (Redis 7.0+)
  # ============================================================

  # SPUBLISH tests
  def test_spublish_returns_subscriber_count
    # When no subscribers, returns 0
    result = redis.spublish("shard:test:channel", "hello")

    assert_equal 0, result
  rescue RR::CommandError => e
    skip "SPUBLISH not supported (requires Redis 7.0+)" if e.message.include?("unknown command")
    raise
  end

  def test_spublish_with_message
    result = redis.spublish("shard:test:channel", "test message")

    assert_kind_of Integer, result
  rescue RR::CommandError => e
    skip "SPUBLISH not supported (requires Redis 7.0+)" if e.message.include?("unknown command")
    raise
  end

  # SSUBSCRIBE tests
  def test_ssubscribe_with_block
    messages = []
    subscribe_count = 0
    unsubscribe_count = 0

    publisher_thread = Thread.new do
      sleep 0.1
      @publisher.spublish("shard:test:block", "message1")
      @publisher.spublish("shard:test:block", "message2")
      sleep 0.1
    end

    redis.ssubscribe("shard:test:block") do |on|
      on.ssubscribe do |_channel, _subscriptions|
        subscribe_count += 1
      end

      on.smessage do |channel, message|
        messages << [channel, message]
        redis.sunsubscribe if messages.size >= 2
      end

      on.sunsubscribe do |_channel, _subscriptions|
        unsubscribe_count += 1
      end
    end

    publisher_thread.join

    assert_equal 1, subscribe_count
    assert_equal 1, unsubscribe_count
    assert_equal 2, messages.size
    assert_equal ["shard:test:block", "message1"], messages[0]
    assert_equal ["shard:test:block", "message2"], messages[1]
  rescue RR::CommandError => e
    skip "SSUBSCRIBE not supported (requires Redis 7.0+)" if e.message.include?("unknown command")
    raise
  end

  def test_ssubscribe_multiple_channels
    channels_subscribed = []
    messages = []

    publisher_thread = Thread.new do
      sleep 0.1
      @publisher.spublish("shard:test:multi1", "msg1")
      @publisher.spublish("shard:test:multi2", "msg2")
      sleep 0.1
    end

    redis.ssubscribe("shard:test:multi1", "shard:test:multi2") do |on|
      on.ssubscribe do |channel, _count|
        channels_subscribed << channel
      end

      on.smessage do |channel, message|
        messages << [channel, message]
        redis.sunsubscribe if messages.size >= 2
      end
    end

    publisher_thread.join

    assert_includes channels_subscribed, "shard:test:multi1"
    assert_includes channels_subscribed, "shard:test:multi2"
    assert_equal 2, messages.size
  rescue RR::CommandError => e
    skip "SSUBSCRIBE not supported (requires Redis 7.0+)" if e.message.include?("unknown command")
    raise
  end

  def test_ssubscribe_timeout
    start_time = Time.now

    redis.ssubscribe_with_timeout(0.5, "shard:test:timeout") do |on|
      on.smessage do |channel, message|
        # Should not receive anything
      end
    end

    elapsed = Time.now - start_time

    assert_operator elapsed, :>=, 0.4
    assert_operator elapsed, :<, 2.0
  rescue RR::CommandError => e
    skip "SSUBSCRIBE not supported (requires Redis 7.0+)" if e.message.include?("unknown command")
    raise
  end

  def test_pubsub_shardchannels_with_pattern
    result = redis.pubsub_shardchannels("shard:test:*")

    assert_kind_of Array, result
  rescue RR::CommandError => e
    skip "PUBSUB SHARDCHANNELS not supported" if e.message.include?("unknown subcommand")
    raise
  end

  # ============================================================
  # Additional Comprehensive PubSub Tests
  # ============================================================

  # Unicode channel names test
  def test_publish_unicode_channel
    unicode_channel = "pubsub:test:unicodeチャンネル"
    result = redis.publish(unicode_channel, "hello")

    assert_kind_of Integer, result
  end

  def test_subscribe_unicode_channel
    messages = []
    unicode_channel = "pubsub:test:unicodeチャンネル"

    publisher_thread = Thread.new do
      sleep 0.1
      @publisher.publish(unicode_channel, "unicode message")
      sleep 0.1
    end

    redis.subscribe(unicode_channel) do |on|
      on.message do |channel, message|
        messages << [channel, message]
        redis.unsubscribe
      end
    end

    publisher_thread.join

    assert_equal 1, messages.size
    # Redis returns binary encoding, force UTF-8 for comparison
    assert_equal unicode_channel, messages[0][0].force_encoding("UTF-8")
    assert_equal "unicode message", messages[0][1]
  end

  # Binary message test
  def test_publish_binary_message
    binary_message = "\x00\x01\x02\xFF".b
    result = redis.publish("pubsub:test:binary", binary_message)

    assert_kind_of Integer, result
  end

  def test_subscribe_binary_message
    messages = []
    binary_message = "\x00\x01\x02\xFF".b

    publisher_thread = Thread.new do
      sleep 0.1
      @publisher.publish("pubsub:test:binary", binary_message)
      sleep 0.1
    end

    redis.subscribe("pubsub:test:binary") do |on|
      on.message do |_channel, message|
        messages << message
        redis.unsubscribe
      end
    end

    publisher_thread.join

    assert_equal 1, messages.size
    assert_equal binary_message, messages[0]
  end

  # Pattern edge cases
  def test_psubscribe_asterisk_pattern
    messages = []

    publisher_thread = Thread.new do
      sleep 0.1
      @publisher.publish("any:channel:here", "message1")
      sleep 0.1
    end

    redis.psubscribe("*") do |on|
      on.pmessage do |pattern, channel, message|
        messages << [pattern, channel, message]
        redis.punsubscribe if messages.size >= 1
      end
    end

    publisher_thread.join

    # Should match any channel
    refute_empty messages
  end

  def test_psubscribe_question_mark_pattern
    messages = []

    publisher_thread = Thread.new do
      sleep 0.1
      @publisher.publish("pubsub:test:a", "message1")
      @publisher.publish("pubsub:test:ab", "message2") # Should not match
      sleep 0.1
    end

    redis.psubscribe("pubsub:test:?") do |on|
      on.pmessage do |pattern, channel, message|
        messages << [pattern, channel, message]
        redis.punsubscribe if messages.size >= 1
      end
    end

    publisher_thread.join

    # Should only match single character channels
    assert_equal 1, messages.size
    assert_equal "pubsub:test:a", messages[0][1]
  end

  def test_psubscribe_bracket_pattern
    messages = []

    publisher_thread = Thread.new do
      sleep 0.1
      @publisher.publish("pubsub:test:x", "message1")
      @publisher.publish("pubsub:test:y", "message2")
      @publisher.publish("pubsub:test:z", "message3") # Should not match
      sleep 0.1
    end

    redis.psubscribe("pubsub:test:[xy]") do |on|
      on.pmessage do |pattern, channel, message|
        messages << [pattern, channel, message]
        redis.punsubscribe if messages.size >= 2
      end
    end

    publisher_thread.join

    # Should only match x and y
    assert_equal 2, messages.size
    channels = messages.map { |m| m[1] }

    assert_includes channels, "pubsub:test:x"
    assert_includes channels, "pubsub:test:y"
  end

  # Unsubscribe all channels
  def test_unsubscribe_all
    channels_unsubscribed = []

    publisher_thread = Thread.new do
      sleep 0.2
    end

    redis.subscribe("pubsub:test:all1", "pubsub:test:all2", "pubsub:test:all3") do |on|
      on.subscribe do |_channel, count|
        # Once we're subscribed to all 3, unsubscribe from all
        redis.unsubscribe if count == 3
      end

      on.unsubscribe do |channel, _count|
        channels_unsubscribed << channel
      end
    end

    publisher_thread.join

    # Should have unsubscribed from all 3 channels
    assert_equal 3, channels_unsubscribed.size
    assert_includes channels_unsubscribed, "pubsub:test:all1"
    assert_includes channels_unsubscribed, "pubsub:test:all2"
    assert_includes channels_unsubscribed, "pubsub:test:all3"
  end

  # Punsubscribe all patterns
  def test_punsubscribe_all
    patterns_unsubscribed = []

    publisher_thread = Thread.new do
      sleep 0.2
    end

    redis.psubscribe("pubsub:test:p1*", "pubsub:test:p2*", "pubsub:test:p3*") do |on|
      on.psubscribe do |_pattern, count|
        redis.punsubscribe if count == 3
      end

      on.punsubscribe do |pattern, _count|
        patterns_unsubscribed << pattern
      end
    end

    publisher_thread.join

    assert_equal 3, patterns_unsubscribed.size
    assert_includes patterns_unsubscribed, "pubsub:test:p1*"
    assert_includes patterns_unsubscribed, "pubsub:test:p2*"
    assert_includes patterns_unsubscribed, "pubsub:test:p3*"
  end

  # Message ordering test
  def test_message_ordering
    messages = []

    publisher_thread = Thread.new do
      sleep 0.1
      (1..5).each do |i|
        @publisher.publish("pubsub:test:order", "message#{i}")
      end
      sleep 0.1
    end

    redis.subscribe("pubsub:test:order") do |on|
      on.message do |_channel, message|
        messages << message
        redis.unsubscribe if messages.size >= 5
      end
    end

    publisher_thread.join

    # Messages should be received in order
    assert_equal %w[message1 message2 message3 message4 message5], messages
  end

  # Publish returns correct subscriber count
  def test_publish_to_subscribed_channel
    subscriber_ready = false

    subscriber_thread = Thread.new do
      redis.subscribe("pubsub:test:count") do |on|
        on.subscribe do |_channel, _count|
          subscriber_ready = true
        end

        on.message do |_channel, _message|
          redis.unsubscribe
        end
      end
    end

    # Wait for subscriber to be ready
    sleep 0.1 until subscriber_ready
    sleep 0.05

    # Should return 1 (one subscriber)
    result = @publisher.publish("pubsub:test:count", "hello")

    subscriber_thread.join

    assert_equal 1, result
  end
end
