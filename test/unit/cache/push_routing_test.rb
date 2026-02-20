# frozen_string_literal: true

require_relative "../unit_test_helper"

class CachePushRoutingTest < Minitest::Test
  # Test that PushMessage exists and has the right interface
  def test_push_message_class
    msg = RR::Protocol::PushMessage.new(["invalidate", ["key1"]])

    assert_equal ["invalidate", ["key1"]], msg.data
  end

  # Test that cache.process_invalidation handles push message data
  def test_process_invalidation_from_push_data
    mock_client = mock_cache_client
    cache = RR::Cache.new(mock_client)
    cache.enable!

    # Simulate caching a value
    mock_client.mock_get_return("value1")
    cache.get("key1")
    assert cache.cached?("key1")

    # Simulate receiving push invalidation (the data array from PushMessage)
    result = cache.process_invalidation(["invalidate", ["key1"]])

    assert result
    refute cache.cached?("key1")
  end

  def test_process_invalidation_full_flush
    mock_client = mock_cache_client
    cache = RR::Cache.new(mock_client)
    cache.enable!

    mock_client.mock_get_return("v1")
    cache.get("key1")
    mock_client.mock_get_return("v2")
    cache.get("key2")

    # nil keys = full flush
    result = cache.process_invalidation(["invalidate", nil])

    assert result
    refute cache.cached?("key1")
    refute cache.cached?("key2")
  end

  def test_process_invalidation_ignores_non_invalidate
    cache = RR::Cache.new(mock_cache_client)

    refute cache.process_invalidation(["subscribe", ["channel"]])
    refute cache.process_invalidation("not_array")
  end

  private

  def mock_cache_client
    client = Object.new
    client.instance_variable_set(:@get_return, nil)
    client.instance_variable_set(:@call_history, [])

    def client.call(*args)
      @call_history << args
      "OK"
    end

    def client.get(key)
      @call_history << [:get, key]
      @get_return
    end

    def client.mock_get_return(val)
      @get_return = val
    end

    def client.call_history
      @call_history
    end

    client
  end
end
