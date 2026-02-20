# frozen_string_literal: true

require_relative "../unit_test_helper"

class CacheStoreTest < Minitest::Test
  def setup
    @store = RR::Cache::Store.new(max_entries: 100)
  end

  def test_set_and_get
    @store.set("GET:key", "value")
    assert_equal "value", @store.get("GET:key")
  end

  def test_get_nonexistent_returns_nil
    assert_nil @store.get("nonexistent")
  end

  def test_set_with_ttl
    @store.set("GET:key", "value", ttl: 3600)
    assert_equal "value", @store.get("GET:key")
  end

  def test_expired_entry_returns_nil
    @store.set("GET:key", "value", ttl: 0.001)
    sleep 0.01
    assert_nil @store.get("GET:key")
  end

  def test_no_ttl_does_not_expire
    @store.set("GET:key", "value")
    assert_equal "value", @store.get("GET:key")
  end

  def test_mark_in_progress
    @store.mark_in_progress("GET:key")
    assert_equal RR::Cache::Store::IN_PROGRESS, @store.get("GET:key")
  end

  def test_in_progress_not_counted_as_key
    @store.mark_in_progress("GET:key")
    refute @store.key?("GET:key")
  end

  def test_overwrite_in_progress_with_value
    @store.mark_in_progress("GET:key")
    @store.set("GET:key", "actual_value")
    assert_equal "actual_value", @store.get("GET:key")
  end

  def test_delete
    @store.set("GET:key", "value")
    assert @store.delete("GET:key")
    assert_nil @store.get("GET:key")
  end

  def test_delete_nonexistent
    refute @store.delete("nonexistent")
  end

  def test_delete_by_redis_key
    builder = RR::Cache::KeyBuilder.new
    builder.build("GET", "user:1")
    builder.build("HGET", "user:1", "name")

    @store.set("GET:user:1", "value1")
    @store.set("HGET:user:1:name", "value2")

    count = @store.delete_by_redis_key("user:1", builder)

    assert_equal 2, count
    assert_nil @store.get("GET:user:1")
    assert_nil @store.get("HGET:user:1:name")
  end

  def test_clear
    @store.set("GET:key1", "v1")
    @store.set("GET:key2", "v2")

    count = @store.clear

    assert_equal 2, count
    assert_equal 0, @store.size
  end

  def test_size
    @store.set("GET:key1", "v1")
    @store.set("GET:key2", "v2")

    assert_equal 2, @store.size
  end

  def test_key_exists
    @store.set("GET:key", "value")
    assert @store.key?("GET:key")
  end

  def test_key_expired_returns_false
    @store.set("GET:key", "value", ttl: 0.001)
    sleep 0.01
    refute @store.key?("GET:key")
  end

  def test_key_nonexistent_returns_false
    refute @store.key?("nonexistent")
  end

  def test_lru_eviction
    store = RR::Cache::Store.new(max_entries: 3)
    store.set("GET:key1", "v1")
    store.set("GET:key2", "v2")
    store.set("GET:key3", "v3")

    # Adding key4 should evict key1 (LRU)
    store.set("GET:key4", "v4")

    assert_nil store.get("GET:key1")
    assert_equal "v2", store.get("GET:key2")
    assert_equal "v3", store.get("GET:key3")
    assert_equal "v4", store.get("GET:key4")
  end

  def test_lru_touch_updates_order
    store = RR::Cache::Store.new(max_entries: 3)
    store.set("GET:key1", "v1")
    store.set("GET:key2", "v2")
    store.set("GET:key3", "v3")

    # Touch key1 to move to end
    store.get("GET:key1")

    # Adding key4 should evict key2 (now the LRU)
    store.set("GET:key4", "v4")

    assert_equal "v1", store.get("GET:key1") # touched, not evicted
    assert_nil store.get("GET:key2")          # evicted
    assert_equal "v3", store.get("GET:key3")
    assert_equal "v4", store.get("GET:key4")
  end

  def test_no_eviction_when_updating_existing_key
    store = RR::Cache::Store.new(max_entries: 2)
    store.set("GET:key1", "v1")
    store.set("GET:key2", "v2")

    # Updating existing key should not trigger eviction
    store.set("GET:key1", "v1_updated")

    assert_equal "v1_updated", store.get("GET:key1")
    assert_equal "v2", store.get("GET:key2")
  end

  def test_eviction_count
    store = RR::Cache::Store.new(max_entries: 2)
    store.set("GET:key1", "v1")
    store.set("GET:key2", "v2")
    store.set("GET:key3", "v3") # evicts key1

    assert_equal 1, store.eviction_count
  end

  def test_cache_entry_struct
    entry = RR::Cache::Store::CacheEntry.new("val", nil)
    refute_predicate entry, :expired?

    future = RR::Cache::Store::CacheEntry.new("val", Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3600)
    refute_predicate future, :expired?

    past = RR::Cache::Store::CacheEntry.new("val", Process.clock_gettime(Process::CLOCK_MONOTONIC) - 1)
    assert_predicate past, :expired?
  end
end
