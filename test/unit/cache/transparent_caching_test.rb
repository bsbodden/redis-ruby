# frozen_string_literal: true

require_relative "../unit_test_helper"

# rubocop:disable Lint/UselessDefaultValueArgument -- Cache#fetch is not Hash#fetch
class CacheTransparentCachingTest < Minitest::Test
  def setup
    @mock_client = build_mock_client
    @cache = RR::Cache.new(@mock_client, max_entries: 100, ttl: 300)
  end

  def test_fetch_returns_cached_value_on_hit
    @cache.enable!

    # First call: miss, stores in cache
    result1 = @cache.fetch("GET", "key1") { "value1" }

    assert_equal "value1", result1

    # Second call: hit, returns from cache
    call_count = 0
    result2 = @cache.fetch("GET", "key1") do
      call_count += 1
      "value2"
    end

    assert_equal "value1", result2
    assert_equal 0, call_count # block should not have been called
  end

  def test_fetch_calls_block_on_miss
    @cache.enable!

    called = false
    result = @cache.fetch("GET", "key1") do
      called = true
      "value1"
    end

    assert called
    assert_equal "value1", result
  end

  def test_fetch_does_not_cache_nil
    @cache.enable!

    @cache.fetch("GET", "key1") { nil }

    # Second call should still miss (nil not cached)
    called = false
    @cache.fetch("GET", "key1") do
      called = true
      "now_exists"
    end

    assert called
  end

  def test_fetch_skips_non_cacheable_commands
    @cache.enable!

    call_count = 0
    @cache.fetch("SET", "key1") do
      call_count += 1
      "OK"
    end
    @cache.fetch("SET", "key1") do
      call_count += 1
      "OK"
    end

    # SET is not cacheable, so both calls should execute
    assert_equal 2, call_count
  end

  def test_fetch_skips_when_cache_disabled
    # Don't enable cache
    call_count = 0
    @cache.fetch("GET", "key1") do
      call_count += 1
      "value"
    end
    @cache.fetch("GET", "key1") do
      call_count += 1
      "value"
    end

    assert_equal 2, call_count
  end

  def test_fetch_with_args_creates_composite_key
    @cache.enable!

    # HGET with field arg
    result1 = @cache.fetch("HGET", "hash", "field1") { "value1" }
    result2 = @cache.fetch("HGET", "hash", "field2") { "value2" }

    # Different fields should have different cache entries
    assert_equal "value1", result1
    assert_equal "value2", result2

    # Same field should hit cache
    call_count = 0
    result3 = @cache.fetch("HGET", "hash", "field1") do
      call_count += 1
      "new"
    end

    assert_equal "value1", result3
    assert_equal 0, call_count
  end

  def test_fetch_tracks_hits_and_misses
    @cache.enable!

    @cache.fetch("GET", "key1") { "value1" } # miss
    @cache.fetch("GET", "key1") { "value1" } # hit
    @cache.fetch("GET", "key1") { "value1" } # hit
    @cache.fetch("GET", "key2") { "value2" } # miss

    stats = @cache.stats

    assert_equal 2, stats[:hits]
    assert_equal 2, stats[:misses]
    assert_in_delta 0.5, stats[:hit_rate]
  end

  def test_invalidation_clears_cache_entry
    @cache.enable!

    @cache.fetch("GET", "key1") { "value1" }
    @cache.invalidate("key1")

    # Should miss after invalidation
    called = false
    @cache.fetch("GET", "key1") do
      called = true
      "value2"
    end

    assert called
  end

  def test_in_progress_sentinel
    @cache.enable!

    # First fetch stores value
    result1 = @cache.fetch("GET", "key1") { "value1" }

    assert_equal "value1", result1

    # Second fetch hits cache, block not called
    call_count = 0
    result2 = @cache.fetch("GET", "key1") do
      call_count += 1
      "should_not_be_called"
    end

    assert_equal "value1", result2
    assert_equal 0, call_count
  end

  private

  def build_mock_client
    client = Object.new

    def client.call(*_args)
      "OK"
    end

    def client.get(_key)
      nil
    end

    client
  end
end
# rubocop:enable Lint/UselessDefaultValueArgument
