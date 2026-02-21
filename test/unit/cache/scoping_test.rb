# frozen_string_literal: true

require_relative "../unit_test_helper"

class CacheScopingTest < Minitest::Test
  def setup
    @mock_client = build_mock_client
    @cache = RR::Cache.new(@mock_client)
    @cache.enable!
  end

  def test_cached_block_forces_caching_on
    @cache.cached do
      assert @cache.force_cache_state
    end
  end

  def test_uncached_block_forces_caching_off
    @cache.uncached do
      refute @cache.force_cache_state
    end
  end

  def test_force_cache_state_nil_outside_blocks
    assert_nil @cache.force_cache_state
  end

  def test_cached_restores_previous_state
    assert_nil @cache.force_cache_state

    @cache.cached do
      assert @cache.force_cache_state
    end

    assert_nil @cache.force_cache_state
  end

  def test_uncached_restores_previous_state
    assert_nil @cache.force_cache_state

    @cache.uncached do
      refute @cache.force_cache_state
    end

    assert_nil @cache.force_cache_state
  end

  def test_nested_scoping
    @cache.cached do
      assert @cache.force_cache_state

      @cache.uncached do
        refute @cache.force_cache_state
      end

      assert @cache.force_cache_state
    end

    assert_nil @cache.force_cache_state
  end

  def test_cached_block_makes_non_cacheable_commands_cacheable
    # SET is normally not cacheable
    refute @cache.cacheable?("SET", "key")

    @cache.cached do
      assert @cache.cacheable?("SET", "key")
    end

    # Back to normal
    refute @cache.cacheable?("SET", "key")
  end

  def test_uncached_block_makes_cacheable_commands_non_cacheable
    assert @cache.cacheable?("GET", "key")

    @cache.uncached do
      refute @cache.cacheable?("GET", "key")
    end

    assert @cache.cacheable?("GET", "key")
  end

  def test_cached_restores_on_exception
    assert_raises(RuntimeError) do
      @cache.cached do
        raise "boom"
      end
    end

    assert_nil @cache.force_cache_state
  end

  def test_uncached_restores_on_exception
    assert_raises(RuntimeError) do
      @cache.uncached do
        raise "boom"
      end
    end

    assert_nil @cache.force_cache_state
  end

  def test_cached_block_return_value
    result = @cache.cached { 42 }

    assert_equal 42, result
  end

  def test_uncached_block_return_value
    result = @cache.uncached { "hello" }

    assert_equal "hello", result
  end

  private

  def build_mock_client
    client = Object.new

    def client.call(*_args)
      "OK"
    end

    client
  end
end
