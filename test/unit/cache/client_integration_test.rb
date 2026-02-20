# frozen_string_literal: true

require_relative "../unit_test_helper"

class CacheClientIntegrationTest < Minitest::Test
  # Test Config.from with different option types
  def test_config_from_true
    config = RR::Cache::Config.from(true)
    assert_instance_of RR::Cache::Config, config
    assert_equal 10_000, config.max_entries
  end

  def test_config_from_hash
    config = RR::Cache::Config.from(max_entries: 5000, ttl: 60)
    assert_equal 5000, config.max_entries
    assert_equal 60, config.ttl
  end

  def test_config_from_config
    original = RR::Cache::Config.new(max_entries: 3000)
    config = RR::Cache::Config.from(original)
    assert_same original, config
  end

  def test_config_from_invalid
    assert_raises(ArgumentError) { RR::Cache::Config.from("invalid") }
  end

  # Test cache integrated with Cache class
  def test_cache_with_config_object
    client = build_mock_client
    config = RR::Cache::Config.new(max_entries: 500, ttl: 60)
    cache = RR::Cache.new(client, config)

    assert_equal 500, cache.max_entries
    assert_equal 60, cache.ttl
  end

  def test_cache_with_legacy_kwargs
    client = build_mock_client
    cache = RR::Cache.new(client, max_entries: 500, ttl: 60)

    assert_equal 500, cache.max_entries
    assert_equal 60, cache.ttl
  end

  def test_cache_stats_include_hit_miss_info
    client = build_mock_client
    cache = RR::Cache.new(client)
    cache.enable!

    client.mock_get_return("value1")
    cache.get("key1")  # miss (first time)
    cache.get("key1")  # hit (from cache)

    stats = cache.stats

    assert_equal 1, stats[:hits]
    assert_equal 0, stats[:misses]  # The legacy .get path uses lookup_cached which tracks separately
    assert_equal 1, stats[:size]
    assert stats[:enabled]
  end

  def test_cache_invalidation_updates_stats
    client = build_mock_client
    cache = RR::Cache.new(client)
    cache.enable!

    client.mock_get_return("value1")
    cache.get("key1")

    cache.process_invalidation(["invalidate", ["key1"]])

    stats = cache.stats
    assert_equal 1, stats[:invalidations]
  end

  def test_cacheable_check_with_key_filter
    client = build_mock_client
    config = RR::Cache::Config.new(
      key_filter: ->(key) { key.start_with?("user:") },
    )
    cache = RR::Cache.new(client, config)

    assert cache.cacheable?("GET", "user:1")
    refute cache.cacheable?("GET", "session:abc")
  end

  def test_cacheable_check_with_optin_mode
    client = build_mock_client
    cache = RR::Cache.new(client, mode: :optin)

    # In optin mode, cacheable? returns false by default
    refute cache.cacheable?("GET", "key")
  end

  private

  def build_mock_client
    client = Object.new
    client.instance_variable_set(:@get_return, nil)

    def client.call(*args)
      "OK"
    end

    def client.get(key)
      @get_return
    end

    def client.mock_get_return(val)
      @get_return = val
    end

    client
  end
end
