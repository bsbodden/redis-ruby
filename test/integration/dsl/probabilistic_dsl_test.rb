# frozen_string_literal: true

require "test_helper"

class ProbabilisticDSLTest < RedisRubyTestCase
  use_testcontainers!

  def setup
    super
    @bf_key = "test:bf:#{SecureRandom.hex(8)}"
    @cf_key = "test:cf:#{SecureRandom.hex(8)}"
    @cms_key = "test:cms:#{SecureRandom.hex(8)}"
    @topk_key = "test:topk:#{SecureRandom.hex(8)}"
  end

  # ============================================================
  # Bloom Filter Tests
  # ============================================================

  def test_bloom_filter_proxy_creation
    proxy = redis.bloom_filter(:spam, :emails)
    
    assert_instance_of RedisRuby::DSL::BloomFilterProxy, proxy
    assert_equal "spam:emails", proxy.key
  end

  def test_bloom_alias
    proxy = redis.bloom(:spam, :emails)
    
    assert_instance_of RedisRuby::DSL::BloomFilterProxy, proxy
    assert_equal "spam:emails", proxy.key
  end

  def test_bloom_filter_with_composite_key
    proxy = redis.bloom_filter(:spam, :detector, 123)
    
    assert_equal "spam:detector:123", proxy.key
  end

  def test_bloom_filter_reserve
    filter = redis.bloom_filter(@bf_key)
    result = filter.reserve(error_rate: 0.01, capacity: 1000)
    
    assert_same filter, result  # Returns self for chaining
    assert filter.key_exists?
  end

  def test_bloom_filter_add_single_item
    filter = redis.bloom_filter(@bf_key)
    filter.reserve(error_rate: 0.01, capacity: 1000)
    
    result = filter.add("item1")
    
    assert_same filter, result
    assert filter.exists?("item1")
  end

  def test_bloom_filter_add_multiple_items
    filter = redis.bloom_filter(@bf_key)
    filter.reserve(error_rate: 0.01, capacity: 1000)
    
    filter.add("item1", "item2", "item3")
    
    assert filter.exists?("item1")
    assert filter.exists?("item2")
    assert filter.exists?("item3")
  end

  def test_bloom_filter_exists_single_item
    filter = redis.bloom_filter(@bf_key)
    filter.reserve(error_rate: 0.01, capacity: 1000)
    filter.add("item1")
    
    assert_equal true, filter.exists?("item1")
    assert_equal false, filter.exists?("unknown")
  end

  def test_bloom_filter_exists_multiple_items
    filter = redis.bloom_filter(@bf_key)
    filter.reserve(error_rate: 0.01, capacity: 1000)
    filter.add("item1", "item2")
    
    result = filter.exists?("item1", "item2", "unknown")
    
    assert_equal [true, true, false], result
  end

  def test_bloom_filter_info
    filter = redis.bloom_filter(@bf_key)
    filter.reserve(error_rate: 0.01, capacity: 1000)
    
    info = filter.info
    
    assert_kind_of Hash, info
    assert info.key?("Capacity")
    assert_equal 1000, info["Capacity"]
  end

  def test_bloom_filter_cardinality
    filter = redis.bloom_filter(@bf_key)
    filter.reserve(error_rate: 0.01, capacity: 1000)
    filter.add("item1", "item2", "item3")
    
    card = filter.cardinality
    
    assert card >= 3  # Approximate count
  end

  def test_bloom_filter_chaining
    filter = redis.bloom_filter(@bf_key)
      .reserve(error_rate: 0.01, capacity: 1000)
      .add("item1", "item2")
      .expire(3600)
    
    assert filter.exists?("item1")
    assert filter.ttl > 0
  end

  def test_bloom_filter_expiration
    filter = redis.bloom_filter(@bf_key)
    filter.reserve(error_rate: 0.01, capacity: 1000)
    filter.add("item1")
    
    filter.expire(3600)
    assert filter.ttl > 0
    
    filter.persist
    assert_equal(-1, filter.ttl)
  end

  def test_bloom_filter_delete
    filter = redis.bloom_filter(@bf_key)
    filter.reserve(error_rate: 0.01, capacity: 1000)
    filter.add("item1")
    
    assert filter.key_exists?
    filter.delete
    refute filter.key_exists?
  end

  def test_bloom_filter_clear_alias
    filter = redis.bloom_filter(@bf_key)
    filter.reserve(error_rate: 0.01, capacity: 1000)

    filter.clear
    refute filter.key_exists?
  end

  # ============================================================
  # Cuckoo Filter Tests
  # ============================================================

  def test_cuckoo_filter_proxy_creation
    proxy = redis.cuckoo_filter(:sessions)

    assert_instance_of RedisRuby::DSL::CuckooFilterProxy, proxy
    assert_equal "sessions", proxy.key
  end

  def test_cuckoo_alias
    proxy = redis.cuckoo(:sessions)

    assert_instance_of RedisRuby::DSL::CuckooFilterProxy, proxy
    assert_equal "sessions", proxy.key
  end

  def test_cuckoo_filter_with_composite_key
    proxy = redis.cuckoo_filter(:active, :sessions, 123)

    assert_equal "active:sessions:123", proxy.key
  end

  def test_cuckoo_filter_reserve
    filter = redis.cuckoo_filter(@cf_key)
    result = filter.reserve(capacity: 1000)

    assert_same filter, result
    assert filter.key_exists?
  end

  def test_cuckoo_filter_add_single_item
    filter = redis.cuckoo_filter(@cf_key)
    filter.reserve(capacity: 1000)

    result = filter.add("item1")

    assert_same filter, result
    assert filter.exists?("item1")
  end

  def test_cuckoo_filter_add_multiple_items
    filter = redis.cuckoo_filter(@cf_key)
    filter.reserve(capacity: 1000)

    filter.add("item1", "item2", "item3")

    assert filter.exists?("item1")
    assert filter.exists?("item2")
    assert filter.exists?("item3")
  end

  def test_cuckoo_filter_add_nx
    filter = redis.cuckoo_filter(@cf_key)
    filter.reserve(capacity: 1000)

    assert_equal true, filter.add_nx("item1")
    assert_equal false, filter.add_nx("item1")  # Already exists
  end

  def test_cuckoo_filter_exists_single_item
    filter = redis.cuckoo_filter(@cf_key)
    filter.reserve(capacity: 1000)
    filter.add("item1")

    assert_equal true, filter.exists?("item1")
    assert_equal false, filter.exists?("unknown")
  end

  def test_cuckoo_filter_exists_multiple_items
    filter = redis.cuckoo_filter(@cf_key)
    filter.reserve(capacity: 1000)
    filter.add("item1", "item2")

    result = filter.exists?("item1", "item2", "unknown")

    assert_equal [true, true, false], result
  end

  def test_cuckoo_filter_remove
    filter = redis.cuckoo_filter(@cf_key)
    filter.reserve(capacity: 1000)
    filter.add("item1", "item2")

    result = filter.remove("item1")

    assert_same filter, result
    refute filter.exists?("item1")
    assert filter.exists?("item2")
  end

  def test_cuckoo_filter_count
    filter = redis.cuckoo_filter(@cf_key)
    filter.reserve(capacity: 1000)
    filter.add("item1")

    count = filter.count("item1")

    assert_equal 1, count
  end

  def test_cuckoo_filter_info
    filter = redis.cuckoo_filter(@cf_key)
    filter.reserve(capacity: 1000)

    info = filter.info

    assert_kind_of Hash, info
    assert info.key?("Size")
  end

  def test_cuckoo_filter_chaining
    filter = redis.cuckoo_filter(@cf_key)
      .reserve(capacity: 1000)
      .add("item1", "item2")
      .remove("item1")
      .expire(3600)

    refute filter.exists?("item1")
    assert filter.exists?("item2")
    assert filter.ttl > 0
  end

  def test_cuckoo_filter_expiration
    filter = redis.cuckoo_filter(@cf_key)
    filter.reserve(capacity: 1000)
    filter.add("item1")

    filter.expire(3600)
    assert filter.ttl > 0

    filter.persist
    assert_equal(-1, filter.ttl)
  end

  def test_cuckoo_filter_delete
    filter = redis.cuckoo_filter(@cf_key)
    filter.reserve(capacity: 1000)
    filter.add("item1")

    assert filter.key_exists?
    filter.delete
    refute filter.key_exists?
  end

  # ============================================================
  # Count-Min Sketch Tests
  # ============================================================

  def test_count_min_sketch_proxy_creation
    proxy = redis.count_min_sketch(:pageviews)

    assert_instance_of RedisRuby::DSL::CountMinSketchProxy, proxy
    assert_equal "pageviews", proxy.key
  end

  def test_cms_alias
    proxy = redis.cms(:pageviews)

    assert_instance_of RedisRuby::DSL::CountMinSketchProxy, proxy
    assert_equal "pageviews", proxy.key
  end

  def test_count_min_sketch_with_composite_key
    proxy = redis.count_min_sketch(:pageviews, :daily, 2024)

    assert_equal "pageviews:daily:2024", proxy.key
  end

  def test_count_min_sketch_init_by_dim
    sketch = redis.count_min_sketch(@cms_key)
    result = sketch.init_by_dim(width: 2000, depth: 5)

    assert_same sketch, result
    assert sketch.key_exists?
  end

  def test_count_min_sketch_init_by_prob
    sketch = redis.count_min_sketch(@cms_key)
    result = sketch.init_by_prob(error_rate: 0.001, probability: 0.01)

    assert_same sketch, result
    assert sketch.key_exists?
  end

  def test_count_min_sketch_increment_single_item
    sketch = redis.count_min_sketch(@cms_key)
    sketch.init_by_dim(width: 2000, depth: 5)

    result = sketch.increment("/home")

    assert_same sketch, result
    assert_equal 1, sketch.query("/home")
  end

  def test_count_min_sketch_increment_multiple_items
    sketch = redis.count_min_sketch(@cms_key)
    sketch.init_by_dim(width: 2000, depth: 5)

    sketch.increment("/home", "/about", "/contact")

    assert_equal 1, sketch.query("/home")
    assert_equal 1, sketch.query("/about")
    assert_equal 1, sketch.query("/contact")
  end

  def test_count_min_sketch_increment_by
    sketch = redis.count_min_sketch(@cms_key)
    sketch.init_by_dim(width: 2000, depth: 5)

    result = sketch.increment_by("/home", 5)

    assert_same sketch, result
    assert sketch.query("/home") >= 5  # May over-estimate
  end

  def test_count_min_sketch_query_single_item
    sketch = redis.count_min_sketch(@cms_key)
    sketch.init_by_dim(width: 2000, depth: 5)
    sketch.increment("/home")
    sketch.increment("/home")

    count = sketch.query("/home")

    assert count >= 2  # May over-estimate, never under-estimates
  end

  def test_count_min_sketch_query_multiple_items
    sketch = redis.count_min_sketch(@cms_key)
    sketch.init_by_dim(width: 2000, depth: 5)
    sketch.increment("/home", "/about")

    counts = sketch.query("/home", "/about", "/unknown")

    assert_kind_of Array, counts
    assert_equal 3, counts.size
    assert counts[0] >= 1
    assert counts[1] >= 1
    assert_equal 0, counts[2]
  end

  def test_count_min_sketch_merge
    sketch1 = redis.count_min_sketch("#{@cms_key}:1")
    sketch1.init_by_dim(width: 2000, depth: 5)
    sketch1.increment("/home")

    sketch2 = redis.count_min_sketch("#{@cms_key}:2")
    sketch2.init_by_dim(width: 2000, depth: 5)
    sketch2.increment("/home")

    sketch1.merge("#{@cms_key}:2")

    assert sketch1.query("/home") >= 2
  end

  def test_count_min_sketch_info
    sketch = redis.count_min_sketch(@cms_key)
    sketch.init_by_dim(width: 2000, depth: 5)

    info = sketch.info

    assert_kind_of Hash, info
    assert_equal 2000, info["width"]
    assert_equal 5, info["depth"]
  end

  def test_count_min_sketch_chaining
    sketch = redis.count_min_sketch(@cms_key)
      .init_by_dim(width: 2000, depth: 5)
      .increment("/home", "/about")
      .increment_by("/home", 5)
      .expire(3600)

    assert sketch.query("/home") >= 6
    assert sketch.ttl > 0
  end

  def test_count_min_sketch_expiration
    sketch = redis.count_min_sketch(@cms_key)
    sketch.init_by_dim(width: 2000, depth: 5)

    sketch.expire(3600)
    assert sketch.ttl > 0

    sketch.persist
    assert_equal(-1, sketch.ttl)
  end

  def test_count_min_sketch_delete
    sketch = redis.count_min_sketch(@cms_key)
    sketch.init_by_dim(width: 2000, depth: 5)

    assert sketch.key_exists?
    sketch.delete
    refute sketch.key_exists?
  end

  # ============================================================
  # Top-K Tests
  # ============================================================

  def test_top_k_proxy_creation
    proxy = redis.top_k(:trending, :products)

    assert_instance_of RedisRuby::DSL::TopKProxy, proxy
    assert_equal "trending:products", proxy.key
  end

  def test_top_k_with_composite_key
    proxy = redis.top_k(:trending, :items, 2024)

    assert_equal "trending:items:2024", proxy.key
  end

  def test_top_k_reserve
    topk = redis.top_k(@topk_key)
    result = topk.reserve(k: 5)

    assert_same topk, result
    assert topk.key_exists?
  end

  def test_top_k_add_single_item
    topk = redis.top_k(@topk_key)
    topk.reserve(k: 5)

    dropped = topk.add("item1")

    assert_kind_of Array, dropped
    assert topk.query("item1")
  end

  def test_top_k_add_multiple_items
    topk = redis.top_k(@topk_key)
    topk.reserve(k: 5)

    dropped = topk.add("item1", "item2", "item3")

    assert_kind_of Array, dropped
    assert topk.query("item1")
    assert topk.query("item2")
    assert topk.query("item3")
  end

  def test_top_k_increment_by
    topk = redis.top_k(@topk_key)
    topk.reserve(k: 5)

    result = topk.increment_by("item1", 10)

    assert_same topk, result
    assert topk.count("item1") >= 10
  end

  def test_top_k_query_single_item
    topk = redis.top_k(@topk_key)
    topk.reserve(k: 5)
    topk.add("item1")

    assert_equal true, topk.query("item1")
    assert_equal false, topk.query("unknown")
  end

  def test_top_k_query_multiple_items
    topk = redis.top_k(@topk_key)
    topk.reserve(k: 5)
    topk.add("item1", "item2")

    result = topk.query("item1", "item2", "unknown")

    assert_equal [true, true, false], result
  end

  def test_top_k_count_single_item
    topk = redis.top_k(@topk_key)
    topk.reserve(k: 5)
    topk.add("item1")
    topk.add("item1")

    count = topk.count("item1")

    assert count >= 2
  end

  def test_top_k_count_multiple_items
    topk = redis.top_k(@topk_key)
    topk.reserve(k: 5)
    topk.add("item1", "item2")

    counts = topk.count("item1", "item2")

    assert_kind_of Array, counts
    assert_equal 2, counts.size
  end

  def test_top_k_list_without_counts
    topk = redis.top_k(@topk_key)
    topk.reserve(k: 5)
    topk.add("item1", "item2", "item3")

    list = topk.list

    assert_kind_of Array, list
    assert_includes list, "item1"
  end

  def test_top_k_list_with_counts
    topk = redis.top_k(@topk_key)
    topk.reserve(k: 5)
    topk.add("item1", "item2")

    list = topk.list(with_counts: true)

    assert_kind_of Array, list
    assert_kind_of Array, list.first
    assert_equal 2, list.first.size  # [item, count]
  end

  def test_top_k_info
    topk = redis.top_k(@topk_key)
    topk.reserve(k: 5)

    info = topk.info

    assert_kind_of Hash, info
    assert_equal 5, info["k"]
  end

  def test_top_k_chaining
    topk = redis.top_k(@topk_key)
      .reserve(k: 5)
      .increment_by("item1", 10)
      .expire(3600)

    assert topk.query("item1")
    assert topk.ttl > 0
  end

  def test_top_k_expiration
    topk = redis.top_k(@topk_key)
    topk.reserve(k: 5)

    topk.expire(3600)
    assert topk.ttl > 0

    topk.persist
    assert_equal(-1, topk.ttl)
  end

  def test_top_k_delete
    topk = redis.top_k(@topk_key)
    topk.reserve(k: 5)

    assert topk.key_exists?
    topk.delete
    refute topk.key_exists?
  end

  # ============================================================
  # Integration Tests - Real-World Scenarios
  # ============================================================

  def test_bloom_filter_spam_detection
    # Spam email detection
    spam = redis.bloom_filter(:spam, :emails, :test)
    spam.reserve(error_rate: 0.01, capacity: 10_000)

    # Add known spam emails
    spam.add("spam1@example.com", "spam2@example.com", "spam3@example.com")

    # Check emails
    assert spam.exists?("spam1@example.com")
    refute spam.exists?("legitimate@example.com")

    # Cleanup
    spam.delete
  end

  def test_cuckoo_filter_session_tracking
    # Active session tracking with cleanup
    sessions = redis.cuckoo_filter(:active, :sessions, :test)
    sessions.reserve(capacity: 1000)

    # Add sessions
    sessions.add("session:abc123", "session:def456")

    # Check session exists
    assert sessions.exists?("session:abc123")

    # Remove expired session
    sessions.remove("session:abc123")
    refute sessions.exists?("session:abc123")
    assert sessions.exists?("session:def456")

    # Cleanup
    sessions.delete
  end

  def test_count_min_sketch_pageview_counting
    # Page view frequency counting
    pageviews = redis.count_min_sketch(:pageviews, :test)
    pageviews.init_by_prob(error_rate: 0.001, probability: 0.01)

    # Simulate page views
    pageviews.increment("/home", "/home", "/home")
    pageviews.increment("/about", "/about")
    pageviews.increment("/contact")

    # Query counts
    home_count = pageviews.query("/home")
    about_count = pageviews.query("/about")
    contact_count = pageviews.query("/contact")

    assert home_count >= 3
    assert about_count >= 2
    assert contact_count >= 1

    # Cleanup
    pageviews.delete
  end

  def test_top_k_trending_products
    # Track trending products
    trending = redis.top_k(:trending, :products, :test)
    trending.reserve(k: 3)

    # Simulate product views
    trending.add("product:1", "product:1", "product:1")  # 3 views
    trending.add("product:2", "product:2")  # 2 views
    trending.add("product:3")  # 1 view
    trending.add("product:4")  # 1 view (may drop product:3 or product:4)

    # Get top products
    top_products = trending.list

    assert_kind_of Array, top_products
    assert top_products.size <= 3
    assert_includes top_products, "product:1"  # Most viewed

    # Cleanup
    trending.delete
  end

  def test_bloom_and_cuckoo_comparison
    # Compare Bloom (no deletion) vs Cuckoo (with deletion)
    bloom = redis.bloom_filter(:test, :bloom)
    bloom.reserve(error_rate: 0.01, capacity: 1000)

    cuckoo = redis.cuckoo_filter(:test, :cuckoo)
    cuckoo.reserve(capacity: 1000)

    # Add same items to both
    bloom.add("item1", "item2", "item3")
    cuckoo.add("item1", "item2", "item3")

    # Both should find items
    assert bloom.exists?("item1")
    assert cuckoo.exists?("item1")

    # Only Cuckoo can delete
    cuckoo.remove("item1")
    refute cuckoo.exists?("item1")
    assert bloom.exists?("item1")  # Bloom still has it

    # Cleanup
    bloom.delete
    cuckoo.delete
  end

  def test_count_min_sketch_merge_distributed_counts
    # Merge counts from multiple servers
    server1 = redis.count_min_sketch(:pageviews, :server1, :test)
    server1.init_by_dim(width: 2000, depth: 5)
    server1.increment("/home", "/home")

    server2 = redis.count_min_sketch(:pageviews, :server2, :test)
    server2.init_by_dim(width: 2000, depth: 5)
    server2.increment("/home", "/home", "/home")

    # Merge into total
    total = redis.count_min_sketch(:pageviews, :total, :test)
    total.init_by_dim(width: 2000, depth: 5)
    total.merge("pageviews:server1:test", "pageviews:server2:test")

    # Total should have combined counts
    assert total.query("/home") >= 5

    # Cleanup
    server1.delete
    server2.delete
    total.delete
  end
end




