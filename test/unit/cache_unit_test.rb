# frozen_string_literal: true

require_relative "unit_test_helper"

# Mock client for Cache tests - avoids real Redis connections
class CacheMockClient
  attr_reader :last_call_args, :get_return_value, :call_history

  def initialize
    @get_return_value = nil
    @call_return_value = "OK"
    @call_history = []
  end

  def call(*args)
    @call_history << args
    @last_call_args = args
    @call_return_value
  end

  def get(key)
    @call_history << [:get, key]
    @get_return_value
  end

  def mock_get_return(value)
    @get_return_value = value
  end

  def mock_call_return(value)
    @call_return_value = value
  end
end

class CacheUnitTest < Minitest::Test
  def setup
    @mock_client = CacheMockClient.new
  end

  # ============================================================
  # Initialization
  # ============================================================

  def test_initialize_with_defaults
    cache = RR::Cache.new(@mock_client)

    assert_equal 10_000, cache.max_entries
    assert_nil cache.ttl
    assert_equal :default, cache.mode
    refute_predicate cache, :enabled?
  end

  def test_initialize_with_custom_max_entries
    cache = RR::Cache.new(@mock_client, max_entries: 500)

    assert_equal 500, cache.max_entries
  end

  def test_initialize_with_custom_ttl
    cache = RR::Cache.new(@mock_client, ttl: 60)

    assert_equal 60, cache.ttl
  end

  def test_initialize_with_optin_mode
    cache = RR::Cache.new(@mock_client, mode: :optin)

    assert_equal :optin, cache.mode
  end

  def test_initialize_with_optout_mode
    cache = RR::Cache.new(@mock_client, mode: :optout)

    assert_equal :optout, cache.mode
  end

  def test_initialize_with_broadcast_mode
    cache = RR::Cache.new(@mock_client, mode: :broadcast)

    assert_equal :broadcast, cache.mode
  end
  # ============================================================
  # enable! / disable!
  # ============================================================

  def test_enable_default_mode
    cache = RR::Cache.new(@mock_client)
    result = cache.enable!

    assert result
    assert_predicate cache, :enabled?
    # Should have called CLIENT TRACKING ON
    assert_equal %w[CLIENT TRACKING ON], @mock_client.call_history.first
  end

  def test_enable_optin_mode
    cache = RR::Cache.new(@mock_client, mode: :optin)
    cache.enable!

    assert_equal %w[CLIENT TRACKING ON OPTIN], @mock_client.call_history.first
  end

  def test_enable_optout_mode
    cache = RR::Cache.new(@mock_client, mode: :optout)
    cache.enable!

    assert_equal %w[CLIENT TRACKING ON OPTOUT], @mock_client.call_history.first
  end

  def test_enable_broadcast_mode
    cache = RR::Cache.new(@mock_client, mode: :broadcast)
    cache.enable!

    assert_equal %w[CLIENT TRACKING ON BCAST], @mock_client.call_history.first
  end

  def test_enable_already_enabled_returns_true_without_call
    cache = RR::Cache.new(@mock_client)
    cache.enable!
    call_count = @mock_client.call_history.size
    result = cache.enable!

    assert result
    # Should NOT have made another call
    assert_equal call_count, @mock_client.call_history.size
  end

  def test_enable_returns_false_when_server_does_not_return_ok
    @mock_client.mock_call_return("ERR something")
    cache = RR::Cache.new(@mock_client)
    result = cache.enable!

    refute result
    refute_predicate cache, :enabled?
  end

  def test_disable_when_enabled
    cache = RR::Cache.new(@mock_client)
    cache.enable!
    result = cache.disable!

    assert result
    refute_predicate cache, :enabled?
  end

  def test_disable_when_already_disabled
    cache = RR::Cache.new(@mock_client)
    result = cache.disable!

    assert result
  end

  def test_disable_clears_cache
    cache = RR::Cache.new(@mock_client)
    cache.enable!
    @mock_client.mock_get_return("value1")
    cache.get("key1")

    assert cache.cached?("key1")

    cache.disable!

    refute cache.cached?("key1")
  end
  # ============================================================
  # enabled?
  # ============================================================

  def test_enabled_false_by_default
    cache = RR::Cache.new(@mock_client)

    refute_predicate cache, :enabled?
  end

  def test_enabled_true_after_enable
    cache = RR::Cache.new(@mock_client)
    cache.enable!

    assert_predicate cache, :enabled?
  end
end

class CacheUnitTestPart2 < Minitest::Test
  def setup
    @mock_client = CacheMockClient.new
  end

  # ============================================================
  # Initialization
  # ============================================================

  # ============================================================
  # get - default mode
  # ============================================================

  def test_get_fetches_from_redis_when_not_enabled
    @mock_client.mock_get_return("value1")
    cache = RR::Cache.new(@mock_client)
    result = cache.get("key1")

    assert_equal "value1", result
    refute cache.cached?("key1") # Not cached because not enabled
  end

  def test_get_fetches_and_caches_when_enabled
    @mock_client.mock_get_return("value1")
    cache = RR::Cache.new(@mock_client)
    cache.enable!
    result = cache.get("key1")

    assert_equal "value1", result
    assert cache.cached?("key1")
  end

  def test_get_returns_cached_value_on_second_call
    @mock_client.mock_get_return("value1")
    cache = RR::Cache.new(@mock_client)
    cache.enable!

    cache.get("key1")
    call_count = @mock_client.call_history.size

    # Second call should return from cache, not call Redis again
    result = cache.get("key1")

    assert_equal "value1", result
    assert_equal call_count, @mock_client.call_history.size
  end

  def test_get_does_not_cache_nil_value
    @mock_client.mock_get_return(nil)
    cache = RR::Cache.new(@mock_client)
    cache.enable!
    cache.get("missing_key")

    refute cache.cached?("missing_key")
  end
  # ============================================================
  # get - optin mode
  # ============================================================

  def test_get_optin_does_not_cache_without_cache_flag
    @mock_client.mock_get_return("value1")
    cache = RR::Cache.new(@mock_client, mode: :optin)
    cache.enable!
    cache.get("key1")

    refute cache.cached?("key1")
  end

  def test_get_optin_caches_with_cache_true
    @mock_client.mock_get_return("value1")
    cache = RR::Cache.new(@mock_client, mode: :optin)
    cache.enable!
    cache.get("key1", cache: true)

    assert cache.cached?("key1")
  end

  def test_get_optin_sends_caching_yes_command
    @mock_client.mock_get_return("value1")
    cache = RR::Cache.new(@mock_client, mode: :optin)
    cache.enable!
    cache.get("key1", cache: true)
    # Should have sent CLIENT CACHING YES
    caching_calls = @mock_client.call_history.select { |c| c == %w[CLIENT CACHING YES] }

    assert_equal 1, caching_calls.size
  end

  def test_get_optin_does_not_send_caching_yes_without_cache_flag
    @mock_client.mock_get_return("value1")
    cache = RR::Cache.new(@mock_client, mode: :optin)
    cache.enable!
    cache.get("key1")
    caching_calls = @mock_client.call_history.select { |c| c == %w[CLIENT CACHING YES] }

    assert_equal 0, caching_calls.size
  end
  # ============================================================
  # get - optout mode
  # ============================================================

  def test_get_optout_caches_by_default
    @mock_client.mock_get_return("value1")
    cache = RR::Cache.new(@mock_client, mode: :optout)
    cache.enable!
    cache.get("key1")

    assert cache.cached?("key1")
  end

  def test_get_optout_does_not_cache_with_cache_false
    @mock_client.mock_get_return("value1")
    cache = RR::Cache.new(@mock_client, mode: :optout)
    cache.enable!
    cache.get("key1", cache: false)

    refute cache.cached?("key1")
  end

  def test_get_optout_caches_with_cache_true
    @mock_client.mock_get_return("value1")
    cache = RR::Cache.new(@mock_client, mode: :optout)
    cache.enable!
    cache.get("key1", cache: true)

    assert cache.cached?("key1")
  end
  # ============================================================
  # TTL handling
  # ============================================================

  def test_get_with_ttl_caches_value
    @mock_client.mock_get_return("value1")
    cache = RR::Cache.new(@mock_client, ttl: 3600)
    cache.enable!
    cache.get("key1")

    assert cache.cached?("key1")
  end

  def test_expired_entry_not_returned_from_cache
    @mock_client.mock_get_return("value1")
    cache = RR::Cache.new(@mock_client, ttl: 0.001)
    cache.enable!
    cache.get("key1")

    # Wait for expiration
    sleep 0.01

    refute cache.cached?("key1")
  end

  def test_expired_entry_refetches_from_redis
    @mock_client.mock_get_return("value1")
    cache = RR::Cache.new(@mock_client, ttl: 0.001)
    cache.enable!
    cache.get("key1")

    sleep 0.01

    @mock_client.mock_get_return("value2")
    result = cache.get("key1")

    assert_equal "value2", result
  end

  def test_no_ttl_entries_do_not_expire
    @mock_client.mock_get_return("value1")
    cache = RR::Cache.new(@mock_client, ttl: nil)
    cache.enable!
    cache.get("key1")

    assert cache.cached?("key1")
  end
end

class CacheUnitTestPart3 < Minitest::Test
  def setup
    @mock_client = CacheMockClient.new
  end

  # ============================================================
  # Initialization
  # ============================================================

  # ============================================================
  # CacheEntry
  # ============================================================

  def test_cache_entry_not_expired_when_no_expires_at
    entry = RR::Cache::CacheEntry.new("val", nil)

    refute_predicate entry, :expired?
  end

  def test_cache_entry_not_expired_when_future
    entry = RR::Cache::CacheEntry.new("val", Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3600)

    refute_predicate entry, :expired?
  end

  def test_cache_entry_expired_when_past
    entry = RR::Cache::CacheEntry.new("val", Process.clock_gettime(Process::CLOCK_MONOTONIC) - 1)

    assert_predicate entry, :expired?
  end
  # ============================================================
  # invalidate
  # ============================================================

  def test_invalidate_cached_key
    @mock_client.mock_get_return("value1")
    cache = RR::Cache.new(@mock_client)
    cache.enable!
    cache.get("key1")

    assert cache.cached?("key1")

    result = cache.invalidate("key1")

    assert result
    refute cache.cached?("key1")
  end

  def test_invalidate_uncached_key
    cache = RR::Cache.new(@mock_client)
    result = cache.invalidate("nonexistent")

    refute result
  end
  # ============================================================
  # invalidate_all
  # ============================================================

  def test_invalidate_all_multiple_keys
    @mock_client.mock_get_return("value1")
    cache = RR::Cache.new(@mock_client)
    cache.enable!
    cache.get("key1")

    @mock_client.mock_get_return("value2")
    cache.get("key2")

    count = cache.invalidate_all(%w[key1 key2])

    assert_equal 2, count
    refute cache.cached?("key1")
    refute cache.cached?("key2")
  end

  def test_invalidate_all_mixed_existing_and_missing
    @mock_client.mock_get_return("value1")
    cache = RR::Cache.new(@mock_client)
    cache.enable!
    cache.get("key1")

    count = cache.invalidate_all(%w[key1 nonexistent])

    assert_equal 1, count
  end

  def test_invalidate_all_empty_keys
    cache = RR::Cache.new(@mock_client)
    count = cache.invalidate_all([])

    assert_equal 0, count
  end
  # ============================================================
  # clear
  # ============================================================

  def test_clear_returns_count
    @mock_client.mock_get_return("value1")
    cache = RR::Cache.new(@mock_client)
    cache.enable!
    cache.get("key1")
    @mock_client.mock_get_return("value2")
    cache.get("key2")

    count = cache.clear

    assert_equal 2, count
  end

  def test_clear_empty_cache
    cache = RR::Cache.new(@mock_client)
    count = cache.clear

    assert_equal 0, count
  end

  def test_clear_removes_all_entries
    @mock_client.mock_get_return("value1")
    cache = RR::Cache.new(@mock_client)
    cache.enable!
    cache.get("key1")
    cache.get("key2")
    cache.clear

    refute cache.cached?("key1")
    refute cache.cached?("key2")
  end
  # ============================================================
  # stats
  # ============================================================

  def test_stats_empty_cache
    cache = RR::Cache.new(@mock_client, ttl: 30, mode: :optin)
    stats = cache.stats

    assert_equal 0, stats[:size]
    assert_equal 10_000, stats[:max_entries]
    refute stats[:enabled]
    assert_equal :optin, stats[:mode]
    assert_equal 30, stats[:ttl]
  end

  def test_stats_with_entries
    @mock_client.mock_get_return("value1")
    cache = RR::Cache.new(@mock_client)
    cache.enable!
    cache.get("key1")
    cache.get("key2")

    stats = cache.stats

    assert_equal 2, stats[:size]
    assert stats[:enabled]
  end
end

class CacheUnitTestPart4 < Minitest::Test
  def setup
    @mock_client = CacheMockClient.new
  end

  # ============================================================
  # Initialization
  # ============================================================

  # ============================================================
  # process_invalidation
  # ============================================================

  def test_process_invalidation_with_valid_message
    @mock_client.mock_get_return("value1")
    cache = RR::Cache.new(@mock_client)
    cache.enable!
    cache.get("key1")

    result = cache.process_invalidation(["invalidate", ["key1"]])

    assert result
    refute cache.cached?("key1")
  end

  def test_process_invalidation_not_an_array
    cache = RR::Cache.new(@mock_client)
    result = cache.process_invalidation("not_an_array")

    refute result
  end

  def test_process_invalidation_wrong_type
    cache = RR::Cache.new(@mock_client)
    result = cache.process_invalidation(["other_type", ["key1"]])

    refute result
  end

  def test_process_invalidation_nil_keys_triggers_full_flush
    @mock_client.mock_get_return("value1")
    cache = RR::Cache.new(@mock_client)
    cache.enable!
    cache.get("key1")
    @mock_client.mock_get_return("value2")
    cache.get("key2")

    assert cache.cached?("key1")
    assert cache.cached?("key2")

    # Redis sends ["invalidate", nil] to signal a full cache flush
    result = cache.process_invalidation(["invalidate", nil])

    assert result
    refute cache.cached?("key1")
    refute cache.cached?("key2")
  end

  def test_process_invalidation_with_multiple_keys
    @mock_client.mock_get_return("v1")
    cache = RR::Cache.new(@mock_client)
    cache.enable!
    cache.get("key1")
    @mock_client.mock_get_return("v2")
    cache.get("key2")

    result = cache.process_invalidation(["invalidate", %w[key1 key2]])

    assert result
    refute cache.cached?("key1")
    refute cache.cached?("key2")
  end
  # ============================================================
  # cached?
  # ============================================================

  def test_cached_returns_false_for_missing_key
    cache = RR::Cache.new(@mock_client)

    refute cache.cached?("nonexistent")
  end

  def test_cached_returns_true_for_cached_key
    @mock_client.mock_get_return("value1")
    cache = RR::Cache.new(@mock_client)
    cache.enable!
    cache.get("key1")

    assert cache.cached?("key1")
  end

  def test_cached_returns_false_for_expired_key
    @mock_client.mock_get_return("value1")
    cache = RR::Cache.new(@mock_client, ttl: 0.001)
    cache.enable!
    cache.get("key1")
    sleep 0.01

    refute cache.cached?("key1")
  end
  # ============================================================
  # LRU eviction
  # ============================================================

  def test_lru_eviction_when_at_capacity
    cache = RR::Cache.new(@mock_client, max_entries: 3)
    cache.enable!

    @mock_client.mock_get_return("v1")
    cache.get("key1")
    @mock_client.mock_get_return("v2")
    cache.get("key2")
    @mock_client.mock_get_return("v3")
    cache.get("key3")

    # At capacity now; adding another should evict key1 (LRU)
    @mock_client.mock_get_return("v4")
    cache.get("key4")

    refute cache.cached?("key1") # evicted
    assert cache.cached?("key2")
    assert cache.cached?("key3")
    assert cache.cached?("key4")
  end

  def test_lru_touch_updates_order
    cache = RR::Cache.new(@mock_client, max_entries: 3)
    cache.enable!

    @mock_client.mock_get_return("v1")
    cache.get("key1")
    @mock_client.mock_get_return("v2")
    cache.get("key2")
    @mock_client.mock_get_return("v3")
    cache.get("key3")

    # Access key1 again to move it to the end of LRU
    cache.get("key1")

    # Adding key4 should now evict key2 (the real LRU)
    @mock_client.mock_get_return("v4")
    cache.get("key4")

    assert cache.cached?("key1") # touched, so not evicted
    refute cache.cached?("key2") # evicted
    assert cache.cached?("key3")
    assert cache.cached?("key4")
  end

  def test_lru_no_eviction_when_updating_existing_key
    cache = RR::Cache.new(@mock_client, max_entries: 2)
    cache.enable!

    @mock_client.mock_get_return("v1")
    cache.get("key1")
    @mock_client.mock_get_return("v2")
    cache.get("key2")

    # Invalidate key1, then re-fetch it (same slot, should not evict key2)
    cache.invalidate("key1")
    @mock_client.mock_get_return("v1_updated")
    cache.get("key1")

    assert cache.cached?("key1")
    assert cache.cached?("key2")
  end

  def test_lru_eviction_order_after_invalidate_and_reinsert
    cache = RR::Cache.new(@mock_client, max_entries: 3)
    cache.enable!

    # Fill cache: key1, key2, key3
    %w[key1 key2 key3].each_with_index do |k, i|
      @mock_client.mock_get_return("v#{i + 1}")
      cache.get(k)
    end

    # Invalidate key2, then re-add it (should be most recent)
    cache.invalidate("key2")
    @mock_client.mock_get_return("v2_new")
    cache.get("key2")

    # Now add key4 — should evict key1 (oldest untouched), NOT key2
    @mock_client.mock_get_return("v4")
    cache.get("key4")

    refute cache.cached?("key1") # evicted as LRU
    assert cache.cached?("key2") # reinserted, so recent
    assert cache.cached?("key3")
    assert cache.cached?("key4")
  end

  def test_lru_correct_with_many_entries
    n = 50
    cache = RR::Cache.new(@mock_client, max_entries: n)
    cache.enable!

    # Fill cache completely
    (1..n).each do |i|
      @mock_client.mock_get_return("v#{i}")
      cache.get("key#{i}")
    end

    # Touch the first 10 keys to make them most recent
    (1..10).each do |i|
      cache.get("key#{i}")
      # Add 10 new keys — should evict keys 11-20 (the LRU ones)
      @mock_client.mock_get_return("new#{i}")
      cache.get("new#{i}")

      # Keys 1-10 should still be cached (they were touched)
      assert cache.cached?("key#{i}"), "key#{i} should be cached"
    end

    # Keys 11-20 should be evicted
    (11..20).each { |i| refute cache.cached?("key#{i}"), "key#{i} should be evicted" }

    # Keys 21-50 should still be cached
    (21..n).each { |i| assert cache.cached?("key#{i}"), "key#{i} should be cached" }
  end

  # ============================================================
  # should_cache? (private, tested via get)
  # ============================================================

  def test_default_mode_always_caches
    @mock_client.mock_get_return("value1")
    cache = RR::Cache.new(@mock_client, mode: :default)
    cache.enable!
    cache.get("key1")

    assert cache.cached?("key1")
  end

  def test_optin_mode_requires_cache_true
    @mock_client.mock_get_return("value1")
    cache = RR::Cache.new(@mock_client, mode: :optin)
    cache.enable!

    cache.get("key1")

    refute cache.cached?("key1")

    cache.get("key1", cache: true)

    assert cache.cached?("key1")
  end

  def test_optout_mode_caches_unless_false
    @mock_client.mock_get_return("value1")
    cache = RR::Cache.new(@mock_client, mode: :optout)
    cache.enable!

    cache.get("key1")

    assert cache.cached?("key1")

    cache.invalidate("key1")
    cache.get("key1", cache: false)

    refute cache.cached?("key1")
  end

  # ============================================================
  # DEFAULT_MAX_ENTRIES / DEFAULT_TTL constants
  # ============================================================

  def test_default_max_entries_constant
    assert_equal 10_000, RR::Cache::DEFAULT_MAX_ENTRIES
  end

  def test_default_ttl_constant
    assert_nil RR::Cache::DEFAULT_TTL
  end
end
