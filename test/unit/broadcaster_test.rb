# frozen_string_literal: true

require_relative "unit_test_helper"
require_relative "../../lib/redis_ruby/broadcaster"

class BroadcasterTest < Minitest::Test
  def test_class_level_redis_client_default_creates_rr_client
    # Verify that the default client uses RR.new, not the undefined RedisRuby
    klass = Class.new do
      include RR::Broadcaster
    end

    # Should not raise NameError for undefined constant and should
    # return a valid RR::Client instance (lazily connected)
    client = klass.redis_client
    assert_instance_of RR::Client, client
  rescue NameError => e
    flunk "Broadcaster references undefined constant: #{e.message}"
  end

  def test_class_level_redis_client_with_explicit_client
    mock_client = Object.new
    klass = Class.new do
      include RR::Broadcaster
      redis_client mock_client
    end

    assert_same mock_client, klass.redis_client
  end

  def test_instance_redis_client_falls_back_to_class_client
    mock_client = Object.new
    klass = Class.new do
      include RR::Broadcaster
      redis_client mock_client
    end

    instance = klass.new
    assert_same mock_client, instance.redis_client
  end

  def test_broadcast_builds_channel_name
    mock_client = Minitest::Mock.new
    klass = Class.new do
      include RR::Broadcaster
      redis_client mock_client
    end

    # Anonymous class name is nil, so channel_prefix will error.
    # Use a named approach instead.
    klass.set_channel_prefix("test_service")

    instance = klass.new
    mock_client.expect(:publish, 1, ["test_service:order_created", "data"])

    instance.broadcast(:order_created, "data")

    mock_client.verify
  end
end
