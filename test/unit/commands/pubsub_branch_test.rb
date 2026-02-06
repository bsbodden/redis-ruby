# frozen_string_literal: true

require_relative "../unit_test_helper"

# MockClient that includes PubSub module and provides call/call_1arg/call_2args stubs
class PubSubMockClient
  include RedisRuby::Commands::PubSub

  attr_accessor :last_call, :last_call_1arg, :last_call_2args, :call_return_value,
                :call_1arg_return_value, :call_2arg_return_value

  def initialize
    @last_call = nil
    @last_call_1arg = nil
    @last_call_2args = nil
    @call_return_value = nil
    @call_1arg_return_value = nil
    @call_2arg_return_value = nil
    @subscription_connection = nil
  end

  def call(command, *)
    @last_call = [command, *]
    @call_return_value
  end

  def call_1arg(command, arg)
    @last_call_1arg = [command, arg]
    @call_1arg_return_value
  end

  def call_2args(command, arg1, arg2)
    @last_call_2args = [command, arg1, arg2]
    @call_2arg_return_value
  end
end

class PubSubBranchTest < Minitest::Test
  def setup
    @client = PubSubMockClient.new
  end

  # ============================================================
  # publish
  # ============================================================

  def test_publish_sends_correct_command
    @client.call_2arg_return_value = 3
    result = @client.publish("news", "Breaking news!")
    assert_equal ["PUBLISH", "news", "Breaking news!"], @client.last_call_2args
    assert_equal 3, result
  end

  def test_publish_returns_zero_when_no_subscribers
    @client.call_2arg_return_value = 0
    result = @client.publish("empty_channel", "hello")
    assert_equal 0, result
  end

  # ============================================================
  # spublish
  # ============================================================

  def test_spublish_sends_correct_command
    @client.call_2arg_return_value = 1
    result = @client.spublish("user:{123}:updates", "profile_updated")
    assert_equal ["SPUBLISH", "user:{123}:updates", "profile_updated"], @client.last_call_2args
    assert_equal 1, result
  end

  def test_spublish_returns_zero_when_no_subscribers
    @client.call_2arg_return_value = 0
    result = @client.spublish("shard_channel", "msg")
    assert_equal 0, result
  end

  # ============================================================
  # pubsub_channels - with and without pattern
  # ============================================================

  def test_pubsub_channels_without_pattern
    @client.call_1arg_return_value = ["channel1", "channel2"]
    result = @client.pubsub_channels
    assert_equal ["PUBSUB", "CHANNELS"], @client.last_call_1arg
    assert_equal ["channel1", "channel2"], result
  end

  def test_pubsub_channels_with_pattern
    @client.call_2arg_return_value = ["news.sports", "news.tech"]
    result = @client.pubsub_channels("news.*")
    assert_equal ["PUBSUB", "CHANNELS", "news.*"], @client.last_call_2args
    assert_equal ["news.sports", "news.tech"], result
  end

  def test_pubsub_channels_with_nil_pattern
    @client.call_1arg_return_value = ["ch1"]
    result = @client.pubsub_channels(nil)
    assert_equal ["PUBSUB", "CHANNELS"], @client.last_call_1arg
    assert_equal ["ch1"], result
  end

  def test_pubsub_channels_returns_empty_array
    @client.call_1arg_return_value = []
    result = @client.pubsub_channels
    assert_equal [], result
  end

  # ============================================================
  # pubsub_numsub - empty channels, single channel, multiple channels
  # ============================================================

  def test_pubsub_numsub_empty_channels
    result = @client.pubsub_numsub
    assert_equal({}, result)
    # Should NOT have called anything
    assert_nil @client.last_call
    assert_nil @client.last_call_1arg
    assert_nil @client.last_call_2args
  end

  def test_pubsub_numsub_single_channel
    @client.call_2arg_return_value = ["channel1", 5]
    result = @client.pubsub_numsub("channel1")
    assert_equal ["PUBSUB", "NUMSUB", "channel1"], @client.last_call_2args
    assert_equal({ "channel1" => 5 }, result)
  end

  def test_pubsub_numsub_multiple_channels
    @client.call_return_value = ["ch1", 3, "ch2", 7]
    result = @client.pubsub_numsub("ch1", "ch2")
    assert_equal ["PUBSUB", "NUMSUB", "ch1", "ch2"], @client.last_call
    assert_equal({ "ch1" => 3, "ch2" => 7 }, result)
  end

  def test_pubsub_numsub_single_channel_zero_subscribers
    @client.call_2arg_return_value = ["empty_ch", 0]
    result = @client.pubsub_numsub("empty_ch")
    assert_equal({ "empty_ch" => 0 }, result)
  end

  # ============================================================
  # pubsub_numpat
  # ============================================================

  def test_pubsub_numpat
    @client.call_1arg_return_value = 42
    result = @client.pubsub_numpat
    assert_equal ["PUBSUB", "NUMPAT"], @client.last_call_1arg
    assert_equal 42, result
  end

  def test_pubsub_numpat_returns_zero
    @client.call_1arg_return_value = 0
    result = @client.pubsub_numpat
    assert_equal 0, result
  end

  # ============================================================
  # pubsub_shardchannels - with and without pattern
  # ============================================================

  def test_pubsub_shardchannels_without_pattern
    @client.call_1arg_return_value = ["shard1", "shard2"]
    result = @client.pubsub_shardchannels
    assert_equal ["PUBSUB", "SHARDCHANNELS"], @client.last_call_1arg
    assert_equal ["shard1", "shard2"], result
  end

  def test_pubsub_shardchannels_with_pattern
    @client.call_2arg_return_value = ["user:{123}:ch1"]
    result = @client.pubsub_shardchannels("user:*")
    assert_equal ["PUBSUB", "SHARDCHANNELS", "user:*"], @client.last_call_2args
    assert_equal ["user:{123}:ch1"], result
  end

  def test_pubsub_shardchannels_with_nil_pattern
    @client.call_1arg_return_value = []
    result = @client.pubsub_shardchannels(nil)
    assert_equal ["PUBSUB", "SHARDCHANNELS"], @client.last_call_1arg
    assert_equal [], result
  end

  def test_pubsub_shardchannels_returns_empty_array
    @client.call_1arg_return_value = []
    result = @client.pubsub_shardchannels
    assert_equal [], result
  end

  # ============================================================
  # pubsub_shardnumsub - empty, single, multiple channels
  # ============================================================

  def test_pubsub_shardnumsub_empty_channels
    result = @client.pubsub_shardnumsub
    assert_equal({}, result)
    assert_nil @client.last_call
    assert_nil @client.last_call_1arg
    assert_nil @client.last_call_2args
  end

  def test_pubsub_shardnumsub_single_channel
    @client.call_2arg_return_value = ["shard_ch1", 2]
    result = @client.pubsub_shardnumsub("shard_ch1")
    assert_equal ["PUBSUB", "SHARDNUMSUB", "shard_ch1"], @client.last_call_2args
    assert_equal({ "shard_ch1" => 2 }, result)
  end

  def test_pubsub_shardnumsub_multiple_channels
    @client.call_return_value = ["s1", 1, "s2", 4]
    result = @client.pubsub_shardnumsub("s1", "s2")
    assert_equal ["PUBSUB", "SHARDNUMSUB", "s1", "s2"], @client.last_call
    assert_equal({ "s1" => 1, "s2" => 4 }, result)
  end

  def test_pubsub_shardnumsub_single_channel_zero_subscribers
    @client.call_2arg_return_value = ["empty_shard", 0]
    result = @client.pubsub_shardnumsub("empty_shard")
    assert_equal({ "empty_shard" => 0 }, result)
  end

  # ============================================================
  # SubscriptionHandler class - set and call all callback types
  # ============================================================

  def test_subscription_handler_initialize
    handler = RedisRuby::Commands::PubSub::SubscriptionHandler.new
    assert_instance_of RedisRuby::Commands::PubSub::SubscriptionHandler, handler
  end

  # --- subscribe callback ---

  def test_subscription_handler_subscribe_callback
    handler = RedisRuby::Commands::PubSub::SubscriptionHandler.new
    received = nil
    handler.subscribe { |channel, count| received = [channel, count] }
    handler.call_subscribe(:subscribe, "ch1", 1)
    assert_equal ["ch1", 1], received
  end

  def test_subscription_handler_subscribe_callback_not_set
    handler = RedisRuby::Commands::PubSub::SubscriptionHandler.new
    # Should not raise when callback is not set (safe navigation)
    handler.call_subscribe(:subscribe, "ch1", 1)
  end

  # --- psubscribe callback ---

  def test_subscription_handler_psubscribe_callback
    handler = RedisRuby::Commands::PubSub::SubscriptionHandler.new
    received = nil
    handler.psubscribe { |pattern, count| received = [pattern, count] }
    handler.call_subscribe(:psubscribe, "news.*", 1)
    assert_equal ["news.*", 1], received
  end

  def test_subscription_handler_psubscribe_callback_not_set
    handler = RedisRuby::Commands::PubSub::SubscriptionHandler.new
    handler.call_subscribe(:psubscribe, "news.*", 1)
  end

  # --- ssubscribe callback ---

  def test_subscription_handler_ssubscribe_callback
    handler = RedisRuby::Commands::PubSub::SubscriptionHandler.new
    received = nil
    handler.ssubscribe { |channel, count| received = [channel, count] }
    handler.call_subscribe(:ssubscribe, "shard_ch", 1)
    assert_equal ["shard_ch", 1], received
  end

  def test_subscription_handler_ssubscribe_callback_not_set
    handler = RedisRuby::Commands::PubSub::SubscriptionHandler.new
    handler.call_subscribe(:ssubscribe, "shard_ch", 1)
  end

  # --- unsubscribe callback ---

  def test_subscription_handler_unsubscribe_callback
    handler = RedisRuby::Commands::PubSub::SubscriptionHandler.new
    received = nil
    handler.unsubscribe { |channel, count| received = [channel, count] }
    handler.call_unsubscribe(:unsubscribe, "ch1", 0)
    assert_equal ["ch1", 0], received
  end

  def test_subscription_handler_unsubscribe_callback_not_set
    handler = RedisRuby::Commands::PubSub::SubscriptionHandler.new
    handler.call_unsubscribe(:unsubscribe, "ch1", 0)
  end

  # --- punsubscribe callback ---

  def test_subscription_handler_punsubscribe_callback
    handler = RedisRuby::Commands::PubSub::SubscriptionHandler.new
    received = nil
    handler.punsubscribe { |pattern, count| received = [pattern, count] }
    handler.call_unsubscribe(:punsubscribe, "news.*", 0)
    assert_equal ["news.*", 0], received
  end

  def test_subscription_handler_punsubscribe_callback_not_set
    handler = RedisRuby::Commands::PubSub::SubscriptionHandler.new
    handler.call_unsubscribe(:punsubscribe, "news.*", 0)
  end

  # --- sunsubscribe callback ---

  def test_subscription_handler_sunsubscribe_callback
    handler = RedisRuby::Commands::PubSub::SubscriptionHandler.new
    received = nil
    handler.sunsubscribe { |channel, count| received = [channel, count] }
    handler.call_unsubscribe(:sunsubscribe, "shard_ch", 0)
    assert_equal ["shard_ch", 0], received
  end

  def test_subscription_handler_sunsubscribe_callback_not_set
    handler = RedisRuby::Commands::PubSub::SubscriptionHandler.new
    handler.call_unsubscribe(:sunsubscribe, "shard_ch", 0)
  end

  # --- message callback ---

  def test_subscription_handler_message_callback
    handler = RedisRuby::Commands::PubSub::SubscriptionHandler.new
    received = nil
    handler.message { |channel, message| received = [channel, message] }
    handler.call_message("ch1", "hello")
    assert_equal ["ch1", "hello"], received
  end

  def test_subscription_handler_message_callback_not_set
    handler = RedisRuby::Commands::PubSub::SubscriptionHandler.new
    handler.call_message("ch1", "hello")
  end

  # --- pmessage callback ---

  def test_subscription_handler_pmessage_callback
    handler = RedisRuby::Commands::PubSub::SubscriptionHandler.new
    received = nil
    handler.pmessage { |pattern, channel, message| received = [pattern, channel, message] }
    handler.call_pmessage("news.*", "news.tech", "New article!")
    assert_equal ["news.*", "news.tech", "New article!"], received
  end

  def test_subscription_handler_pmessage_callback_not_set
    handler = RedisRuby::Commands::PubSub::SubscriptionHandler.new
    handler.call_pmessage("news.*", "news.tech", "hello")
  end

  # --- smessage callback ---

  def test_subscription_handler_smessage_callback
    handler = RedisRuby::Commands::PubSub::SubscriptionHandler.new
    received = nil
    handler.smessage { |channel, message| received = [channel, message] }
    handler.call_smessage("shard_ch", "shard_msg")
    assert_equal ["shard_ch", "shard_msg"], received
  end

  def test_subscription_handler_smessage_callback_not_set
    handler = RedisRuby::Commands::PubSub::SubscriptionHandler.new
    handler.call_smessage("shard_ch", "shard_msg")
  end

  # --- Multiple callbacks at once ---

  def test_subscription_handler_all_callbacks_set
    handler = RedisRuby::Commands::PubSub::SubscriptionHandler.new
    results = {}

    handler.subscribe { |ch, c| results[:subscribe] = [ch, c] }
    handler.psubscribe { |p, c| results[:psubscribe] = [p, c] }
    handler.ssubscribe { |ch, c| results[:ssubscribe] = [ch, c] }
    handler.unsubscribe { |ch, c| results[:unsubscribe] = [ch, c] }
    handler.punsubscribe { |p, c| results[:punsubscribe] = [p, c] }
    handler.sunsubscribe { |ch, c| results[:sunsubscribe] = [ch, c] }
    handler.message { |ch, m| results[:message] = [ch, m] }
    handler.pmessage { |p, ch, m| results[:pmessage] = [p, ch, m] }
    handler.smessage { |ch, m| results[:smessage] = [ch, m] }

    handler.call_subscribe(:subscribe, "ch1", 1)
    handler.call_subscribe(:psubscribe, "p1", 2)
    handler.call_subscribe(:ssubscribe, "s1", 3)
    handler.call_unsubscribe(:unsubscribe, "ch1", 2)
    handler.call_unsubscribe(:punsubscribe, "p1", 1)
    handler.call_unsubscribe(:sunsubscribe, "s1", 0)
    handler.call_message("ch1", "msg1")
    handler.call_pmessage("p1", "ch2", "msg2")
    handler.call_smessage("s1", "msg3")

    assert_equal ["ch1", 1], results[:subscribe]
    assert_equal ["p1", 2], results[:psubscribe]
    assert_equal ["s1", 3], results[:ssubscribe]
    assert_equal ["ch1", 2], results[:unsubscribe]
    assert_equal ["p1", 1], results[:punsubscribe]
    assert_equal ["s1", 0], results[:sunsubscribe]
    assert_equal ["ch1", "msg1"], results[:message]
    assert_equal ["p1", "ch2", "msg2"], results[:pmessage]
    assert_equal ["s1", "msg3"], results[:smessage]
  end

  # --- Overwriting callbacks ---

  def test_subscription_handler_overwrite_callback
    handler = RedisRuby::Commands::PubSub::SubscriptionHandler.new
    received = nil

    handler.message { |_ch, _m| received = :first }
    handler.message { |_ch, _m| received = :second }

    handler.call_message("ch", "msg")
    assert_equal :second, received
  end

  # ============================================================
  # unsubscribe / punsubscribe / sunsubscribe
  # (testing the @subscription_connection guard)
  # ============================================================

  def test_unsubscribe_returns_nil_when_no_subscription_connection
    # @subscription_connection is nil by default on our mock
    result = @client.unsubscribe("ch1")
    assert_nil result
  end

  def test_unsubscribe_with_channels_writes_command
    mock_conn = Minitest::Mock.new
    mock_conn.expect :write_command, nil, [["UNSUBSCRIBE", "ch1", "ch2"]]
    @client.instance_variable_set(:@subscription_connection, mock_conn)

    @client.unsubscribe("ch1", "ch2")
    mock_conn.verify
  end

  def test_unsubscribe_without_channels_writes_unsubscribe_all
    mock_conn = Minitest::Mock.new
    mock_conn.expect :write_command, nil, [["UNSUBSCRIBE"]]
    @client.instance_variable_set(:@subscription_connection, mock_conn)

    @client.unsubscribe
    mock_conn.verify
  end

  def test_punsubscribe_returns_nil_when_no_subscription_connection
    result = @client.punsubscribe("news.*")
    assert_nil result
  end

  def test_punsubscribe_with_patterns_writes_command
    mock_conn = Minitest::Mock.new
    mock_conn.expect :write_command, nil, [["PUNSUBSCRIBE", "news.*", "sports.*"]]
    @client.instance_variable_set(:@subscription_connection, mock_conn)

    @client.punsubscribe("news.*", "sports.*")
    mock_conn.verify
  end

  def test_punsubscribe_without_patterns_writes_punsubscribe_all
    mock_conn = Minitest::Mock.new
    mock_conn.expect :write_command, nil, [["PUNSUBSCRIBE"]]
    @client.instance_variable_set(:@subscription_connection, mock_conn)

    @client.punsubscribe
    mock_conn.verify
  end

  def test_sunsubscribe_returns_nil_when_no_subscription_connection
    result = @client.sunsubscribe("shard_ch")
    assert_nil result
  end

  def test_sunsubscribe_with_channels_writes_command
    mock_conn = Minitest::Mock.new
    mock_conn.expect :write_command, nil, [["SUNSUBSCRIBE", "s1", "s2"]]
    @client.instance_variable_set(:@subscription_connection, mock_conn)

    @client.sunsubscribe("s1", "s2")
    mock_conn.verify
  end

  def test_sunsubscribe_without_channels_writes_sunsubscribe_all
    mock_conn = Minitest::Mock.new
    mock_conn.expect :write_command, nil, [["SUNSUBSCRIBE"]]
    @client.instance_variable_set(:@subscription_connection, mock_conn)

    @client.sunsubscribe
    mock_conn.verify
  end

  # ============================================================
  # Frozen constant tests
  # ============================================================

  def test_frozen_command_constants
    assert_equal "PUBLISH", RedisRuby::Commands::PubSub::CMD_PUBLISH
    assert_equal "SPUBLISH", RedisRuby::Commands::PubSub::CMD_SPUBLISH
    assert_equal "PUBSUB", RedisRuby::Commands::PubSub::CMD_PUBSUB
    assert_equal "CHANNELS", RedisRuby::Commands::PubSub::SUBCMD_CHANNELS
    assert_equal "NUMSUB", RedisRuby::Commands::PubSub::SUBCMD_NUMSUB
    assert_equal "NUMPAT", RedisRuby::Commands::PubSub::SUBCMD_NUMPAT
    assert_equal "SHARDCHANNELS", RedisRuby::Commands::PubSub::SUBCMD_SHARDCHANNELS
    assert_equal "SHARDNUMSUB", RedisRuby::Commands::PubSub::SUBCMD_SHARDNUMSUB
  end
end
