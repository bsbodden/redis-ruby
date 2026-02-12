# frozen_string_literal: true

require "test_helper"

class HyperLogLogDSLTest < RedisRubyTestCase
  use_testcontainers!

  def setup
    super
    @key = "test:hll:#{SecureRandom.hex(8)}"
  end

  # ============================================================
  # Entry Point Tests
  # ============================================================

  def test_hyperloglog_proxy_creation
    proxy = redis.hyperloglog(:visitors)
    
    assert_instance_of RedisRuby::DSL::HyperLogLogProxy, proxy
    assert_equal "visitors", proxy.key
  end

  def test_hll_alias
    proxy = redis.hll(:visitors)
    
    assert_instance_of RedisRuby::DSL::HyperLogLogProxy, proxy
    assert_equal "visitors", proxy.key
  end

  def test_hyperloglog_with_composite_key
    proxy = redis.hyperloglog(:visitors, :today, 2024)
    
    assert_equal "visitors:today:2024", proxy.key
  end

  def test_hyperloglog_with_single_key_part
    proxy = redis.hll(:simple)
    
    assert_equal "simple", proxy.key
  end

  # ============================================================
  # Add Operations Tests
  # ============================================================

  def test_add_single_element
    hll = redis.hll(@key)
    
    result = hll.add("user:123")
    
    assert_same hll, result  # Returns self for chaining
    assert_equal 1, hll.count
  end

  def test_add_multiple_elements
    hll = redis.hll(@key)
    
    hll.add("user:1", "user:2", "user:3")
    
    assert_equal 3, hll.count
  end

  def test_add_duplicate_elements
    hll = redis.hll(@key)
    
    hll.add("user:1", "user:2", "user:3")
    hll.add("user:1", "user:2")  # Duplicates
    
    # Count should still be 3 (unique elements)
    assert_equal 3, hll.count
  end

  def test_add_with_symbols
    hll = redis.hll(@key)
    
    hll.add(:user1, :user2, :user3)
    
    assert_equal 3, hll.count
  end

  def test_add_with_integers
    hll = redis.hll(@key)
    
    hll.add(1, 2, 3, 4, 5)
    
    assert_equal 5, hll.count
  end

  def test_add_empty_elements
    hll = redis.hll(@key)
    
    result = hll.add
    
    assert_same hll, result
    assert_equal 0, hll.count
  end

  def test_chainable_add
    hll = redis.hll(@key)
    
    hll.add("a").add("b").add("c")
    
    assert_equal 3, hll.count
  end

  # ============================================================
  # Count Operations Tests
  # ============================================================

  def test_count_empty_hll
    hll = redis.hll(@key)
    
    assert_equal 0, hll.count
  end

  def test_count_with_elements
    hll = redis.hll(@key)
    hll.add("a", "b", "c", "d", "e")
    
    assert_equal 5, hll.count
  end

  def test_size_alias
    hll = redis.hll(@key)
    hll.add("a", "b", "c")
    
    assert_equal 3, hll.size
    assert_equal hll.count, hll.size
  end

  def test_length_alias
    hll = redis.hll(@key)
    hll.add("a", "b", "c")
    
    assert_equal 3, hll.length
    assert_equal hll.count, hll.length
  end

  def test_count_large_dataset
    hll = redis.hll(@key)

    # Add 10,000 unique elements
    10_000.times { |i| hll.add("user:#{i}") }

    count = hll.count
    # HyperLogLog has ~0.81% standard error
    # For 10,000 elements, we expect count to be within ~81 of actual
    assert_in_delta 10_000, count, 200  # Allow 2% margin
  end

  # ============================================================
  # Merge Operations Tests
  # ============================================================

  def test_merge_single_hll
    hll1 = redis.hll("#{@key}:1")
    hll2 = redis.hll("#{@key}:2")

    hll1.add("a", "b", "c")
    hll2.add("c", "d", "e")

    result = hll1.merge("#{@key}:2")

    assert_same hll1, result  # Returns self for chaining
    assert_equal 5, hll1.count  # a, b, c, d, e
  end

  def test_merge_multiple_hlls
    hll1 = redis.hll("#{@key}:1")
    hll2 = redis.hll("#{@key}:2")
    hll3 = redis.hll("#{@key}:3")

    hll1.add("a", "b")
    hll2.add("c", "d")
    hll3.add("e", "f")

    hll1.merge("#{@key}:2", "#{@key}:3")

    assert_equal 6, hll1.count  # a, b, c, d, e, f
  end

  def test_merge_with_overlapping_elements
    hll1 = redis.hll("#{@key}:1")
    hll2 = redis.hll("#{@key}:2")
    hll3 = redis.hll("#{@key}:3")

    hll1.add("a", "b", "c")
    hll2.add("b", "c", "d")
    hll3.add("c", "d", "e")

    hll1.merge("#{@key}:2", "#{@key}:3")

    assert_equal 5, hll1.count  # a, b, c, d, e (unique)
  end

  def test_merge_empty_hlls
    hll = redis.hll(@key)

    result = hll.merge

    assert_same hll, result
  end

  def test_merge_into_new_destination
    hll1 = redis.hll("#{@key}:1")
    hll2 = redis.hll("#{@key}:2")
    dest = redis.hll("#{@key}:merged")

    hll1.add("a", "b", "c")
    hll2.add("c", "d", "e")

    result = hll1.merge_into("#{@key}:merged", "#{@key}:2")

    assert_same hll1, result  # Returns self for chaining
    assert_equal 5, dest.count  # a, b, c, d, e
    assert_equal 3, hll1.count  # Original unchanged
  end

  def test_merge_into_with_multiple_sources
    hll1 = redis.hll("#{@key}:1")
    hll2 = redis.hll("#{@key}:2")
    hll3 = redis.hll("#{@key}:3")
    dest = redis.hll("#{@key}:merged")

    hll1.add("a", "b")
    hll2.add("c", "d")
    hll3.add("e", "f")

    hll1.merge_into("#{@key}:merged", "#{@key}:2", "#{@key}:3")

    assert_equal 6, dest.count
  end

  # ============================================================
  # Clear/Delete Operations Tests
  # ============================================================

  def test_delete
    hll = redis.hll(@key)
    hll.add("a", "b", "c")

    result = hll.delete

    assert_equal 1, result  # Number of keys deleted
    refute hll.exists?
  end

  def test_clear_alias
    hll = redis.hll(@key)
    hll.add("a", "b", "c")

    result = hll.clear

    assert_equal 1, result
    refute hll.exists?
  end

  def test_delete_nonexistent_hll
    hll = redis.hll(@key)

    result = hll.delete

    assert_equal 0, result  # No keys deleted
  end

  # ============================================================
  # Existence Tests
  # ============================================================

  def test_exists_with_existing_hll
    hll = redis.hll(@key)
    hll.add("a")

    assert hll.exists?
  end

  def test_exists_with_nonexistent_hll
    hll = redis.hll(@key)

    refute hll.exists?
  end

  def test_empty_with_no_elements
    hll = redis.hll(@key)

    assert hll.empty?
  end

  def test_empty_with_elements
    hll = redis.hll(@key)
    hll.add("a", "b", "c")

    refute hll.empty?
  end

  def test_empty_after_delete
    hll = redis.hll(@key)
    hll.add("a", "b", "c")
    hll.delete

    assert hll.empty?
  end

  # ============================================================
  # Expiration Tests
  # ============================================================

  def test_expire
    hll = redis.hll(@key)
    hll.add("a", "b", "c")

    result = hll.expire(3600)

    assert_same hll, result  # Returns self for chaining
    ttl = hll.ttl
    assert ttl > 0
    assert ttl <= 3600
  end

  def test_expire_at_with_time
    hll = redis.hll(@key)
    hll.add("a", "b", "c")

    future_time = Time.now + 3600
    result = hll.expire_at(future_time)

    assert_same hll, result
    ttl = hll.ttl
    assert ttl > 0
    assert ttl <= 3600
  end

  def test_expire_at_with_timestamp
    hll = redis.hll(@key)
    hll.add("a", "b", "c")

    future_timestamp = Time.now.to_i + 3600
    hll.expire_at(future_timestamp)

    ttl = hll.ttl
    assert ttl > 0
    assert ttl <= 3600
  end

  def test_ttl_with_expiration
    hll = redis.hll(@key)
    hll.add("a", "b", "c")
    hll.expire(1000)

    ttl = hll.ttl

    assert ttl > 0
    assert ttl <= 1000
  end

  def test_ttl_without_expiration
    hll = redis.hll(@key)
    hll.add("a", "b", "c")

    assert_equal(-1, hll.ttl)
  end

  def test_ttl_nonexistent_key
    hll = redis.hll(@key)

    assert_equal(-2, hll.ttl)
  end

  def test_persist
    hll = redis.hll(@key)
    hll.add("a", "b", "c")
    hll.expire(3600)

    result = hll.persist

    assert_same hll, result
    assert_equal(-1, hll.ttl)
  end

  def test_chainable_with_expiration
    hll = redis.hll(@key)
      .add("a", "b", "c")
      .expire(3600)

    assert_equal 3, hll.count
    assert hll.ttl > 0
  end

  # ============================================================
  # Integration Tests - Real-World Scenarios
  # ============================================================

  def test_unique_visitor_counting
    # Track unique visitors per day
    key_prefix = "test:visitors:#{SecureRandom.hex(4)}"
    today = redis.hll(key_prefix, Date.today.to_s)

    # Simulate visitors
    today.add("user:123", "user:456", "user:789")
    today.add("user:123")  # Duplicate visit

    assert_equal 3, today.count

    # Set to expire at end of day
    today.expire(86400)
    assert today.ttl > 0
  end

  def test_unique_event_tracking
    # Track unique event types per user
    key_prefix = "test:events:#{SecureRandom.hex(4)}"
    user_events = redis.hll(key_prefix, :user, 123)

    user_events.add("page_view", "button_click", "form_submit")
    user_events.add("page_view")  # Duplicate event type

    assert_equal 3, user_events.count
  end

  def test_ab_testing_scenario
    # Track unique users in each variant
    key_prefix = "test:experiment:#{SecureRandom.hex(4)}"
    variant_a = redis.hll(key_prefix, :checkout, :variant_a)
    variant_b = redis.hll(key_prefix, :checkout, :variant_b)

    variant_a.add("user:1", "user:2", "user:3", "user:4", "user:5")
    variant_b.add("user:6", "user:7", "user:8")

    assert_equal 5, variant_a.count
    assert_equal 3, variant_b.count

    # Total unique users across both variants
    total = redis.hll(key_prefix, :checkout, :total)
    total.merge(
      "#{key_prefix}:checkout:variant_a",
      "#{key_prefix}:checkout:variant_b"
    )

    assert_equal 8, total.count
  end

  def test_daily_to_weekly_aggregation
    # Track daily unique visitors
    key_prefix = "test:daily:#{SecureRandom.hex(4)}"
    redis.hll(key_prefix, :day1).add("u1", "u2", "u3")
    redis.hll(key_prefix, :day2).add("u2", "u3", "u4")
    redis.hll(key_prefix, :day3).add("u3", "u4", "u5")

    # Merge into weekly count
    weekly = redis.hll(key_prefix, :weekly)
    weekly.merge("#{key_prefix}:day1", "#{key_prefix}:day2", "#{key_prefix}:day3")

    # Should have 5 unique visitors (u1, u2, u3, u4, u5)
    assert_equal 5, weekly.count
  end

  def test_merge_into_preserves_source
    # Create daily counts with unique keys
    key_prefix = "test:merge:#{SecureRandom.hex(4)}"
    day1 = redis.hll(key_prefix, :day1).add("u1", "u2", "u3")
    day2 = redis.hll(key_prefix, :day2).add("u4", "u5", "u6")

    # Merge into weekly without modifying daily
    day1.merge_into("#{key_prefix}:weekly", "#{key_prefix}:day2")

    weekly = redis.hll(key_prefix, :weekly)

    assert_equal 3, day1.count   # Original unchanged
    assert_equal 3, day2.count   # Original unchanged
    assert_equal 6, weekly.count # Merged result
  end

  def test_large_scale_unique_counting
    # Simulate tracking unique IPs
    key_prefix = "test:ips:#{SecureRandom.hex(4)}"
    ip_tracker = redis.hll(key_prefix, :unique)

    # Add 1000 unique IPs
    1000.times { |i| ip_tracker.add("192.168.1.#{i % 256}:#{i}") }

    count = ip_tracker.count
    # Should be close to 1000 with ~0.81% error
    assert_in_delta 1000, count, 20
  end

  def test_multi_level_aggregation
    # Hour -> Day -> Week hierarchy
    key_prefix = "test:agg:#{SecureRandom.hex(4)}"
    redis.hll(key_prefix, :hour, 1).add("u1", "u2")
    redis.hll(key_prefix, :hour, 2).add("u2", "u3")
    redis.hll(key_prefix, :hour, 3).add("u3", "u4")

    # Aggregate hours into day
    day = redis.hll(key_prefix, :day)
    day.merge("#{key_prefix}:hour:1", "#{key_prefix}:hour:2", "#{key_prefix}:hour:3")

    assert_equal 4, day.count  # u1, u2, u3, u4
  end
end


