# frozen_string_literal: true

require "test_helper"

class PubSubIntegrationTest < Minitest::Test
  def setup
    @redis = RedisRuby.new(host: ENV.fetch("REDIS_HOST", "redis"), port: ENV.fetch("REDIS_PORT", 6379).to_i)
    @publisher = RedisRuby.new(host: ENV.fetch("REDIS_HOST", "redis"), port: ENV.fetch("REDIS_PORT", 6379).to_i)
  end

  def teardown
    @redis.close
    @publisher.close
  end

  # PUBLISH tests
  def test_publish_returns_subscriber_count
    # When no subscribers, returns 0
    result = @redis.publish("pubsub:test:channel", "hello")
    assert_equal 0, result
  end

  def test_publish_with_message
    result = @redis.publish("pubsub:test:channel", "test message")
    assert_kind_of Integer, result
  end

  # PUBSUB CHANNELS tests
  def test_pubsub_channels_empty
    # Returns list of active channels (may be empty or have channels from other tests)
    result = @redis.pubsub_channels
    assert_kind_of Array, result
  end

  def test_pubsub_channels_with_pattern
    result = @redis.pubsub_channels("pubsub:test:*")
    assert_kind_of Array, result
  end

  # PUBSUB NUMSUB tests
  def test_pubsub_numsub
    result = @redis.pubsub_numsub("channel1", "channel2")
    assert_kind_of Hash, result
    assert_equal 0, result["channel1"]
    assert_equal 0, result["channel2"]
  end

  def test_pubsub_numsub_empty
    result = @redis.pubsub_numsub
    assert_equal({}, result)
  end

  # PUBSUB NUMPAT tests
  def test_pubsub_numpat
    result = @redis.pubsub_numpat
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
      sleep 0.1  # Wait for subscription to be set up
      @publisher.publish("pubsub:test:block", "message1")
      @publisher.publish("pubsub:test:block", "message2")
      sleep 0.1
    end

    @redis.subscribe("pubsub:test:block") do |on|
      on.subscribe do |channel, subscriptions|
        subscribe_count += 1
      end

      on.message do |channel, message|
        messages << [channel, message]
        # Unsubscribe after receiving 2 messages
        @redis.unsubscribe if messages.size >= 2
      end

      on.unsubscribe do |channel, subscriptions|
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

    @redis.subscribe("pubsub:test:multi1", "pubsub:test:multi2") do |on|
      on.subscribe do |channel, count|
        channels_subscribed << channel
      end

      on.message do |channel, message|
        messages << [channel, message]
        @redis.unsubscribe if messages.size >= 2
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

    @redis.psubscribe("pubsub:pattern:*") do |on|
      on.psubscribe do |pattern, count|
        assert_equal "pubsub:pattern:*", pattern
      end

      on.pmessage do |pattern, channel, message|
        messages << [pattern, channel, message]
        @redis.punsubscribe if messages.size >= 2
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

    @redis.subscribe_with_timeout(0.5, "pubsub:test:timeout") do |on|
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
    result = @redis.pubsub_shardchannels
    assert_kind_of Array, result
  rescue RedisRuby::CommandError => e
    skip "PUBSUB SHARDCHANNELS not supported" if e.message.include?("unknown subcommand")
    raise
  end

  def test_pubsub_shardnumsub
    result = @redis.pubsub_shardnumsub("shard:channel1")
    assert_kind_of Hash, result
  rescue RedisRuby::CommandError => e
    skip "PUBSUB SHARDNUMSUB not supported" if e.message.include?("unknown subcommand")
    raise
  end
end
