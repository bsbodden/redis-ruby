# frozen_string_literal: true

require_relative "../unit_test_helper"

class CacheKeyBuilderTest < Minitest::Test
  def setup
    @builder = RR::Cache::KeyBuilder.new
  end

  def test_build_simple_key
    assert_equal "GET:user:1", @builder.build("GET", "user:1")
  end

  def test_build_key_with_args
    assert_equal "HGET:h:field", @builder.build("HGET", "h", "field")
  end

  def test_build_key_with_multiple_args
    assert_equal "ZRANGE:z:0:10", @builder.build("ZRANGE", "z", "0", "10")
  end

  def test_reverse_index_tracks_keys
    @builder.build("GET", "user:1")
    @builder.build("HGET", "user:1", "name")

    cache_keys = @builder.cache_keys_for("user:1")

    assert_includes cache_keys, "GET:user:1"
    assert_includes cache_keys, "HGET:user:1:name"
  end

  def test_reverse_index_no_duplicates
    @builder.build("GET", "user:1")
    @builder.build("GET", "user:1")

    assert_equal 1, @builder.cache_keys_for("user:1").size
  end

  def test_remove_single_entry
    @builder.build("GET", "user:1")
    @builder.build("HGET", "user:1", "name")

    @builder.remove("GET:user:1", "user:1")

    cache_keys = @builder.cache_keys_for("user:1")
    refute_includes cache_keys, "GET:user:1"
    assert_includes cache_keys, "HGET:user:1:name"
  end

  def test_remove_all_for_redis_key
    @builder.build("GET", "user:1")
    @builder.build("HGET", "user:1", "name")

    removed = @builder.remove_all_for("user:1")

    assert_equal 2, removed.size
    assert_empty @builder.cache_keys_for("user:1")
  end

  def test_remove_all_for_nonexistent_key
    removed = @builder.remove_all_for("nonexistent")

    assert_empty removed
  end

  def test_clear
    @builder.build("GET", "user:1")
    @builder.build("GET", "user:2")

    @builder.clear

    assert_equal 0, @builder.size
  end

  def test_size
    @builder.build("GET", "user:1")
    @builder.build("GET", "user:2")
    @builder.build("HGET", "user:1", "name")

    assert_equal 2, @builder.size # 2 unique Redis keys
  end

  def test_different_commands_same_key
    key1 = @builder.build("GET", "key")
    key2 = @builder.build("STRLEN", "key")

    refute_equal key1, key2
    assert_equal "GET:key", key1
    assert_equal "STRLEN:key", key2
  end
end
