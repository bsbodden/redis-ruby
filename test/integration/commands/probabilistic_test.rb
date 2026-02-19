# frozen_string_literal: true

require "test_helper"

class BloomFilterCommandsTest < RedisRubyTestCase
  use_testcontainers!

  def setup
    super
    @bf_key = "bf:test:#{SecureRandom.hex(4)}"
    @cf_key = "cf:test:#{SecureRandom.hex(4)}"
    @cms_key = "cms:test:#{SecureRandom.hex(4)}"
    @topk_key = "topk:test:#{SecureRandom.hex(4)}"
    @td_key = "td:test:#{SecureRandom.hex(4)}"
  end

  def teardown
    redis.del(@bf_key, @cf_key, @cms_key, @topk_key, @td_key)
    super
  end

  # BLOOM FILTER TESTS

  def test_bf_reserve
    result = redis.bf_reserve(@bf_key, 0.01, 1000)

    assert_equal "OK", result

    info = redis.bf_info(@bf_key)

    assert_kind_of Hash, info
  end

  def test_bf_add_and_exists
    redis.bf_reserve(@bf_key, 0.01, 100)

    # Add item
    result = redis.bf_add(@bf_key, "item1")

    assert_equal 1, result

    # Add same item again
    result = redis.bf_add(@bf_key, "item1")

    assert_equal 0, result

    # Check existence
    assert_equal 1, redis.bf_exists(@bf_key, "item1")
    assert_equal 0, redis.bf_exists(@bf_key, "nonexistent")
  end

  def test_bf_madd_and_mexists
    redis.bf_reserve(@bf_key, 0.01, 100)

    # Add multiple items
    result = redis.bf_madd(@bf_key, "a", "b", "c")

    assert_equal [1, 1, 1], result

    # Check multiple items
    result = redis.bf_mexists(@bf_key, "a", "b", "d")

    assert_equal [1, 1, 0], result
  end

  def test_bf_insert
    # Insert with auto-create
    result = redis.bf_insert(@bf_key, "item1", "item2", capacity: 500, error: 0.001)

    assert_equal [1, 1], result

    # Verify items exist
    assert_equal 1, redis.bf_exists(@bf_key, "item1")
    assert_equal 1, redis.bf_exists(@bf_key, "item2")
  end

  def test_bf_info
    redis.bf_reserve(@bf_key, 0.01, 1000)
    redis.bf_add(@bf_key, "test")

    info = redis.bf_info(@bf_key)

    assert_kind_of Hash, info
    assert info.key?("Capacity") || info.key?("capacity")
  end

  def test_bf_card
    redis.bf_reserve(@bf_key, 0.01, 1000)
    redis.bf_madd(@bf_key, "a", "b", "c")

    card = redis.bf_card(@bf_key)

    assert_equal 3, card
  end

  # CUCKOO FILTER TESTS
  def test_cf_reserve
    result = redis.cf_reserve(@cf_key, 1000)

    assert_equal "OK", result
  end

  def test_cf_add_and_exists
    redis.cf_reserve(@cf_key, 1000)

    result = redis.cf_add(@cf_key, "item1")

    assert_equal 1, result

    assert_equal 1, redis.cf_exists(@cf_key, "item1")
    assert_equal 0, redis.cf_exists(@cf_key, "nonexistent")
  end

  def test_cf_addnx
    redis.cf_reserve(@cf_key, 1000)

    # Add new item
    result = redis.cf_addnx(@cf_key, "unique")

    assert_equal 1, result

    # Try to add same item
    result = redis.cf_addnx(@cf_key, "unique")

    assert_equal 0, result
  end

  def test_cf_del
    redis.cf_reserve(@cf_key, 1000)
    redis.cf_add(@cf_key, "to_delete")

    assert_equal 1, redis.cf_exists(@cf_key, "to_delete")

    result = redis.cf_del(@cf_key, "to_delete")

    assert_equal 1, result

    assert_equal 0, redis.cf_exists(@cf_key, "to_delete")
  end

  def test_cf_count
    redis.cf_reserve(@cf_key, 1000)

    # Add same item multiple times
    redis.cf_add(@cf_key, "frequent")
    redis.cf_add(@cf_key, "frequent")

    count = redis.cf_count(@cf_key, "frequent")

    assert_operator count, :>=, 1
  end

  def test_cf_insert
    result = redis.cf_insert(@cf_key, "a", "b", "c", capacity: 500)

    assert_equal [1, 1, 1], result
  end

  def test_cf_mexists
    redis.cf_reserve(@cf_key, 1000)
    redis.cf_add(@cf_key, "a")
    redis.cf_add(@cf_key, "b")

    result = redis.cf_mexists(@cf_key, "a", "b", "c")

    assert_equal [1, 1, 0], result
  end

  def test_cf_info
    redis.cf_reserve(@cf_key, 1000)

    info = redis.cf_info(@cf_key)

    assert_kind_of Hash, info
  end

  # COUNT-MIN SKETCH TESTS
  def test_cms_initbydim
    result = redis.cms_initbydim(@cms_key, 1000, 5)

    assert_equal "OK", result
  end

  def test_cms_initbyprob
    result = redis.cms_initbyprob(@cms_key, 0.001, 0.01)

    assert_equal "OK", result
  end

  def test_cms_incrby_and_query
    redis.cms_initbydim(@cms_key, 1000, 5)

    # Increment counts
    result = redis.cms_incrby(@cms_key, "item1", 5, "item2", 10)

    assert_kind_of Array, result

    # Query counts
    counts = redis.cms_query(@cms_key, "item1", "item2", "item3")

    assert_operator counts[0], :>=, 5
    assert_operator counts[1], :>=, 10
    assert_predicate counts[2], :zero?
  end
end

class BloomFilterCommandsTestPart2 < RedisRubyTestCase
  use_testcontainers!

  def setup
    super
    @bf_key = "bf:test:#{SecureRandom.hex(4)}"
    @cf_key = "cf:test:#{SecureRandom.hex(4)}"
    @cms_key = "cms:test:#{SecureRandom.hex(4)}"
    @topk_key = "topk:test:#{SecureRandom.hex(4)}"
    @td_key = "td:test:#{SecureRandom.hex(4)}"
  end

  def teardown
    redis.del(@bf_key, @cf_key, @cms_key, @topk_key, @td_key)
    super
  end

  # BLOOM FILTER TESTS

  def test_cms_info
    redis.cms_initbydim(@cms_key, 1000, 5)

    info = redis.cms_info(@cms_key)

    assert_kind_of Hash, info
    assert info.key?("width") || info.key?("Width")
  end

  # TOP-K TESTS
  def test_topk_reserve
    result = redis.topk_reserve(@topk_key, 5)

    assert_equal "OK", result
  end

  def test_topk_add_and_list
    redis.topk_reserve(@topk_key, 3)

    # Add items
    redis.topk_add(@topk_key, "a", "b", "c", "a", "a", "b")

    # List top items
    top = redis.topk_list(@topk_key)

    assert_includes top, "a"
    assert_includes top, "b"
  end

  def test_topk_incrby
    redis.topk_reserve(@topk_key, 3)

    result = redis.topk_incrby(@topk_key, "item1", 10, "item2", 5)

    assert_kind_of Array, result
  end

  def test_topk_query
    redis.topk_reserve(@topk_key, 3)
    redis.topk_add(@topk_key, "frequent", "frequent", "frequent")

    result = redis.topk_query(@topk_key, "frequent", "rare")

    assert_equal 1, result[0]
    assert_equal 0, result[1]
  end

  def test_topk_count
    redis.topk_reserve(@topk_key, 3)
    redis.topk_add(@topk_key, "a", "a", "a", "b", "b")

    counts = redis.topk_count(@topk_key, "a", "b", "c")

    assert_operator counts[0], :>=, 3
    assert_operator counts[1], :>=, 2
    assert_predicate counts[2], :zero?
  end

  def test_topk_list_withcount
    redis.topk_reserve(@topk_key, 3)
    redis.topk_add(@topk_key, "x", "x", "y")

    result = redis.topk_list(@topk_key, withcount: true)

    assert_kind_of Array, result
  end

  def test_topk_info
    redis.topk_reserve(@topk_key, 5)

    info = redis.topk_info(@topk_key)

    assert_kind_of Hash, info
    assert info.key?("k") || info.key?("K")
  end

  # T-DIGEST TESTS
  def test_tdigest_create
    result = redis.tdigest_create(@td_key)

    assert_equal "OK", result
  end

  def test_tdigest_create_with_compression
    result = redis.tdigest_create(@td_key, compression: 500)

    assert_equal "OK", result
  end

  def test_tdigest_add
    redis.tdigest_create(@td_key)

    result = redis.tdigest_add(@td_key, 1.0, 2.0, 3.0, 4.0, 5.0)

    assert_equal "OK", result
  end

  def test_tdigest_quantile
    redis.tdigest_create(@td_key)
    redis.tdigest_add(@td_key, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10)

    # Get median (50th percentile)
    result = redis.tdigest_quantile(@td_key, 0.5)

    assert_kind_of Array, result
    value = result[0].to_f

    assert value.between?(4, 6)
  end

  def test_tdigest_min_max
    redis.tdigest_create(@td_key)
    redis.tdigest_add(@td_key, 10, 20, 30, 40, 50)

    min = redis.tdigest_min(@td_key)
    max = redis.tdigest_max(@td_key)

    assert_in_delta(10.0, min.to_f)
    assert_in_delta(50.0, max.to_f)
  end

  def test_tdigest_rank
    redis.tdigest_create(@td_key)
    redis.tdigest_add(@td_key, 1, 2, 3, 4, 5)

    ranks = redis.tdigest_rank(@td_key, 1, 3, 5)

    assert_kind_of Array, ranks
  end

  def test_tdigest_cdf
    redis.tdigest_create(@td_key)
    redis.tdigest_add(@td_key, 1, 2, 3, 4, 5)

    cdf = redis.tdigest_cdf(@td_key, 2.5)

    assert_kind_of Array, cdf
    value = cdf[0].to_f

    assert value.between?(0, 1)
  end

  def test_tdigest_reset
    redis.tdigest_create(@td_key)
    redis.tdigest_add(@td_key, 1, 2, 3)

    result = redis.tdigest_reset(@td_key)

    assert_equal "OK", result
  end

  def test_tdigest_info
    redis.tdigest_create(@td_key)
    redis.tdigest_add(@td_key, 1, 2, 3)

    info = redis.tdigest_info(@td_key)

    assert_kind_of Hash, info
  end

  def test_tdigest_trimmed_mean
    redis.tdigest_create(@td_key)
    redis.tdigest_add(@td_key, 1, 2, 3, 4, 5, 100) # 100 is outlier

    # Get trimmed mean excluding outliers
    mean = redis.tdigest_trimmed_mean(@td_key, 0.1, 0.9)

    assert_kind_of Float, mean.to_f
  end
end
