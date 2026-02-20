# frozen_string_literal: true

require_relative "../unit_test_helper"

class CacheStatsTest < Minitest::Test
  def setup
    @stats = RR::Cache::Stats.new
  end

  def test_initial_values
    assert_equal 0, @stats.hits
    assert_equal 0, @stats.misses
    assert_equal 0, @stats.evictions
    assert_equal 0, @stats.invalidations
  end

  def test_hit
    @stats.hit!

    assert_equal 1, @stats.hits
  end

  def test_miss
    @stats.miss!

    assert_equal 1, @stats.misses
  end

  def test_evict
    @stats.evict!

    assert_equal 1, @stats.evictions
  end

  def test_invalidate
    @stats.invalidate!

    assert_equal 1, @stats.invalidations
  end

  def test_invalidate_bulk
    @stats.invalidate_bulk!(5)

    assert_equal 5, @stats.invalidations
  end

  def test_hit_rate_zero_when_no_requests
    assert_in_delta 0.0, @stats.hit_rate
  end

  def test_hit_rate_calculation
    3.times { @stats.hit! }
    1.times { @stats.miss! }

    assert_in_delta 0.75, @stats.hit_rate
  end

  def test_hit_rate_100_percent
    5.times { @stats.hit! }

    assert_in_delta 1.0, @stats.hit_rate
  end

  def test_to_h
    @stats.hit!
    @stats.miss!
    @stats.evict!
    @stats.invalidate!

    result = @stats.to_h(size: 42)

    assert_equal 1, result[:hits]
    assert_equal 1, result[:misses]
    assert_in_delta 0.5, result[:hit_rate]
    assert_equal 1, result[:evictions]
    assert_equal 1, result[:invalidations]
    assert_equal 42, result[:size]
  end

  def test_reset
    3.times { @stats.hit! }
    2.times { @stats.miss! }
    @stats.evict!
    @stats.invalidate!

    @stats.reset!

    assert_equal 0, @stats.hits
    assert_equal 0, @stats.misses
    assert_equal 0, @stats.evictions
    assert_equal 0, @stats.invalidations
  end
end
