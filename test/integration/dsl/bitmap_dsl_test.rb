# frozen_string_literal: true

require "test_helper"

class BitmapDSLTest < RedisRubyTestCase
  use_testcontainers!

  def setup
    super
    @key = "test:bitmap:#{SecureRandom.hex(8)}"
  end

  # ============================================================
  # Entry Point Tests
  # ============================================================

  def test_bitmap_proxy_creation
    proxy = redis.bitmap(:activity)
    
    assert_instance_of RR::DSL::BitmapProxy, proxy
    assert_equal "activity", proxy.key
  end

  def test_bitmap_with_composite_key
    proxy = redis.bitmap(:user, :activity, 123)
    
    assert_equal "user:activity:123", proxy.key
  end

  def test_bitmap_with_single_key_part
    proxy = redis.bitmap(:simple)
    
    assert_equal "simple", proxy.key
  end

  # ============================================================
  # Set/Get Bit Operations Tests
  # ============================================================

  def test_set_bit_returns_self
    bitmap = redis.bitmap(@key)
    
    result = bitmap.set_bit(0, 1)
    
    assert_same bitmap, result  # Returns self for chaining
  end

  def test_set_and_get_bit
    bitmap = redis.bitmap(@key)
    
    bitmap.set_bit(0, 1)
    bitmap.set_bit(1, 0)
    bitmap.set_bit(7, 1)
    
    assert_equal 1, bitmap.get_bit(0)
    assert_equal 0, bitmap.get_bit(1)
    assert_equal 1, bitmap.get_bit(7)
  end

  def test_array_syntax_set_and_get
    bitmap = redis.bitmap(@key)
    
    bitmap[0] = 1
    bitmap[1] = 0
    bitmap[7] = 1
    
    assert_equal 1, bitmap[0]
    assert_equal 0, bitmap[1]
    assert_equal 1, bitmap[7]
  end

  def test_array_syntax_returns_value
    bitmap = redis.bitmap(@key)
    
    result = (bitmap[5] = 1)
    
    assert_equal 1, result
  end

  def test_get_bit_nonexistent_key
    bitmap = redis.bitmap(@key)
    
    assert_equal 0, bitmap.get_bit(0)
    assert_equal 0, bitmap[100]
  end

  def test_set_bit_large_offset
    bitmap = redis.bitmap(@key)
    
    bitmap.set_bit(1000, 1)
    
    assert_equal 1, bitmap.get_bit(1000)
    assert_equal 0, bitmap.get_bit(999)
  end

  # ============================================================
  # Count Operations Tests
  # ============================================================

  def test_count_empty_bitmap
    bitmap = redis.bitmap(@key)
    
    assert_equal 0, bitmap.count
  end

  def test_count_with_set_bits
    bitmap = redis.bitmap(@key)
    
    bitmap[0] = 1
    bitmap[1] = 1
    bitmap[7] = 1
    bitmap[15] = 1
    
    assert_equal 4, bitmap.count
  end

  def test_count_with_byte_range
    bitmap = redis.bitmap(@key)
    
    # Set bits in different bytes
    bitmap[0] = 1   # Byte 0
    bitmap[7] = 1   # Byte 0
    bitmap[8] = 1   # Byte 1
    bitmap[16] = 1  # Byte 2
    
    assert_equal 4, bitmap.count(0, -1)  # All bytes
    assert_equal 2, bitmap.count(0, 0)   # First byte only
    assert_equal 1, bitmap.count(1, 1)   # Second byte only
  end

  def test_count_after_clearing_bits
    bitmap = redis.bitmap(@key)
    
    bitmap[0] = 1
    bitmap[1] = 1
    bitmap[2] = 1
    assert_equal 3, bitmap.count
    
    bitmap[1] = 0
    assert_equal 2, bitmap.count
  end

  # ============================================================
  # Position Operations Tests
  # ============================================================

  def test_position_find_first_set_bit
    bitmap = redis.bitmap(@key)
    
    bitmap[5] = 1
    bitmap[10] = 1
    
    assert_equal 5, bitmap.position(1)
  end

  def test_position_find_first_clear_bit
    bitmap = redis.bitmap(@key)

    bitmap[0] = 1
    bitmap[1] = 1
    bitmap[2] = 1

    assert_equal 3, bitmap.position(0)
  end

  def test_position_with_byte_range
    bitmap = redis.bitmap(@key)

    bitmap[0] = 1
    bitmap[100] = 1

    # Find first 1 bit starting at byte 10
    assert_equal 100, bitmap.position(1, 10)
  end

  def test_position_not_found
    bitmap = redis.bitmap(@key)

    # Set all bits in byte 0 to 1 (bits 0-7)
    8.times { |i| bitmap[i] = 1 }

    # Looking for 0 bit in byte 0 which is now all 1s
    result = bitmap.position(0, 0, 0)
    assert_equal(-1, result)
  end

  # ============================================================
  # Bitwise AND Operations Tests
  # ============================================================

  def test_and_operation
    bitmap1 = redis.bitmap("#{@key}:1")
    bitmap2 = redis.bitmap("#{@key}:2")
    result = redis.bitmap("#{@key}:result")

    bitmap1[0] = 1
    bitmap1[1] = 1
    bitmap1[2] = 0

    bitmap2[0] = 1
    bitmap2[1] = 0
    bitmap2[2] = 1

    result.and("#{@key}:1", "#{@key}:2")

    assert_equal 1, result[0]  # 1 AND 1 = 1
    assert_equal 0, result[1]  # 1 AND 0 = 0
    assert_equal 0, result[2]  # 0 AND 1 = 0
  end

  def test_and_returns_self
    bitmap = redis.bitmap(@key)

    result = bitmap.and("#{@key}:other")

    assert_same bitmap, result
  end

  def test_and_with_empty_keys
    bitmap = redis.bitmap(@key)

    result = bitmap.and

    assert_same bitmap, result
  end

  # ============================================================
  # Bitwise OR Operations Tests
  # ============================================================

  def test_or_operation
    bitmap1 = redis.bitmap("#{@key}:1")
    bitmap2 = redis.bitmap("#{@key}:2")
    result = redis.bitmap("#{@key}:result")

    bitmap1[0] = 1
    bitmap1[1] = 0
    bitmap1[2] = 0

    bitmap2[0] = 0
    bitmap2[1] = 1
    bitmap2[2] = 0

    result.or("#{@key}:1", "#{@key}:2")

    assert_equal 1, result[0]  # 1 OR 0 = 1
    assert_equal 1, result[1]  # 0 OR 1 = 1
    assert_equal 0, result[2]  # 0 OR 0 = 0
  end

  def test_or_multiple_bitmaps
    bitmap1 = redis.bitmap("#{@key}:1")
    bitmap2 = redis.bitmap("#{@key}:2")
    bitmap3 = redis.bitmap("#{@key}:3")
    result = redis.bitmap("#{@key}:result")

    bitmap1[0] = 1
    bitmap2[1] = 1
    bitmap3[2] = 1

    result.or("#{@key}:1", "#{@key}:2", "#{@key}:3")

    assert_equal 1, result[0]
    assert_equal 1, result[1]
    assert_equal 1, result[2]
    assert_equal 3, result.count
  end

  # ============================================================
  # Bitwise XOR Operations Tests
  # ============================================================

  def test_xor_operation
    bitmap1 = redis.bitmap("#{@key}:1")
    bitmap2 = redis.bitmap("#{@key}:2")
    result = redis.bitmap("#{@key}:result")

    bitmap1[0] = 1
    bitmap1[1] = 1
    bitmap1[2] = 0

    bitmap2[0] = 1
    bitmap2[1] = 0
    bitmap2[2] = 1

    result.xor("#{@key}:1", "#{@key}:2")

    assert_equal 0, result[0]  # 1 XOR 1 = 0
    assert_equal 1, result[1]  # 1 XOR 0 = 1
    assert_equal 1, result[2]  # 0 XOR 1 = 1
  end

  # ============================================================
  # Bitwise NOT Operations Tests
  # ============================================================

  def test_not_operation
    bitmap = redis.bitmap("#{@key}:source")
    result = redis.bitmap("#{@key}:result")

    bitmap[0] = 1
    bitmap[1] = 0
    bitmap[2] = 1

    result.not("#{@key}:source")

    assert_equal 0, result[0]  # NOT 1 = 0
    assert_equal 1, result[1]  # NOT 0 = 1
    assert_equal 0, result[2]  # NOT 1 = 0
  end

  # ============================================================
  # Non-Destructive Bitwise Operations Tests
  # ============================================================

  def test_and_into_preserves_source
    bitmap1 = redis.bitmap("#{@key}:1")
    bitmap2 = redis.bitmap("#{@key}:2")

    bitmap1[0] = 1
    bitmap1[1] = 1
    bitmap2[0] = 1
    bitmap2[1] = 0

    result = bitmap1.and_into("#{@key}:result", "#{@key}:2")

    assert_same bitmap1, result

    # Check result
    result_bitmap = redis.bitmap("#{@key}:result")
    assert_equal 1, result_bitmap[0]
    assert_equal 0, result_bitmap[1]

    # Verify source is unchanged
    assert_equal 1, bitmap1[0]
    assert_equal 1, bitmap1[1]
  end

  def test_or_into_preserves_source
    bitmap1 = redis.bitmap("#{@key}:1")
    bitmap2 = redis.bitmap("#{@key}:2")

    bitmap1[0] = 1
    bitmap2[1] = 1

    bitmap1.or_into("#{@key}:result", "#{@key}:2")

    result_bitmap = redis.bitmap("#{@key}:result")
    assert_equal 1, result_bitmap[0]
    assert_equal 1, result_bitmap[1]

    # Verify source is unchanged
    assert_equal 1, bitmap1[0]
    assert_equal 0, bitmap1[1]
  end

  def test_xor_into_preserves_source
    bitmap1 = redis.bitmap("#{@key}:1")
    bitmap2 = redis.bitmap("#{@key}:2")

    bitmap1[0] = 1
    bitmap1[1] = 1
    bitmap2[0] = 1
    bitmap2[1] = 0

    bitmap1.xor_into("#{@key}:result", "#{@key}:2")

    result_bitmap = redis.bitmap("#{@key}:result")
    assert_equal 0, result_bitmap[0]  # 1 XOR 1 = 0
    assert_equal 1, result_bitmap[1]  # 1 XOR 0 = 1
  end

  def test_not_into_preserves_source
    bitmap = redis.bitmap("#{@key}:source")

    bitmap[0] = 1
    bitmap[1] = 0

    bitmap.not_into("#{@key}:result")

    result_bitmap = redis.bitmap("#{@key}:result")
    assert_equal 0, result_bitmap[0]
    assert_equal 1, result_bitmap[1]

    # Verify source is unchanged
    assert_equal 1, bitmap[0]
    assert_equal 0, bitmap[1]
  end

  # ============================================================
  # Bitfield Operations Tests
  # ============================================================

  def test_bitfield_returns_builder
    bitmap = redis.bitmap(@key)

    builder = bitmap.bitfield

    assert_instance_of RR::DSL::BitFieldBuilder, builder
  end

  def test_bitfield_set_and_get
    bitmap = redis.bitmap(@key)

    results = bitmap.bitfield
      .set(:u8, 0, 100)
      .get(:u8, 0)
      .execute

    assert_equal [0, 100], results
  end

  def test_bitfield_multiple_values
    bitmap = redis.bitmap(@key)

    bitmap.bitfield
      .set(:u8, 0, 100)
      .set(:u8, 8, 200)
      .set(:u8, 16, 50)
      .execute

    results = bitmap.bitfield
      .get(:u8, 0)
      .get(:u8, 8)
      .get(:u8, 16)
      .execute

    assert_equal [100, 200, 50], results
  end

  def test_bitfield_incrby
    bitmap = redis.bitmap(@key)

    bitmap.bitfield.set(:u8, 0, 100).execute

    results = bitmap.bitfield
      .incrby(:u8, 0, 10)
      .get(:u8, 0)
      .execute

    assert_equal [110, 110], results
  end

  def test_bitfield_overflow_wrap
    bitmap = redis.bitmap(@key)

    bitmap.bitfield.set(:u8, 0, 255).execute

    results = bitmap.bitfield
      .overflow(:wrap)
      .incrby(:u8, 0, 1)
      .execute

    assert_equal [0], results  # Wraps around
  end

  def test_bitfield_overflow_sat
    bitmap = redis.bitmap(@key)

    bitmap.bitfield.set(:u8, 0, 255).execute

    results = bitmap.bitfield
      .overflow(:sat)
      .incrby(:u8, 0, 10)
      .execute

    assert_equal [255], results  # Saturates at max
  end

  def test_bitfield_overflow_fail
    bitmap = redis.bitmap(@key)

    bitmap.bitfield.set(:u8, 0, 255).execute

    results = bitmap.bitfield
      .overflow(:fail)
      .incrby(:u8, 0, 10)
      .execute

    assert_nil results[0]  # Returns nil on overflow
  end

  def test_bitfield_signed_integers
    bitmap = redis.bitmap(@key)

    results = bitmap.bitfield
      .set(:i8, 0, -50)
      .get(:i8, 0)
      .execute

    assert_equal [0, -50], results
  end

  def test_bitfield_empty_operations
    bitmap = redis.bitmap(@key)

    results = bitmap.bitfield.execute

    assert_equal [], results
  end

  # ============================================================
  # Existence and Clear Tests
  # ============================================================

  def test_exists_returns_false_for_nonexistent_key
    bitmap = redis.bitmap(@key)

    assert_equal false, bitmap.exists?
  end

  def test_exists_returns_true_after_setting_bit
    bitmap = redis.bitmap(@key)

    bitmap[0] = 1

    assert_equal true, bitmap.exists?
  end

  def test_empty_returns_true_for_nonexistent_key
    bitmap = redis.bitmap(@key)

    assert_equal true, bitmap.empty?
  end

  def test_empty_returns_false_when_bits_set
    bitmap = redis.bitmap(@key)

    bitmap[0] = 1

    assert_equal false, bitmap.empty?
  end

  def test_empty_returns_true_when_all_bits_cleared
    bitmap = redis.bitmap(@key)

    bitmap[0] = 1
    bitmap[0] = 0

    # Key exists but has no set bits
    assert_equal true, bitmap.empty?
  end

  def test_delete_removes_key
    bitmap = redis.bitmap(@key)

    bitmap[0] = 1
    assert_equal true, bitmap.exists?

    bitmap.delete

    assert_equal false, bitmap.exists?
  end

  def test_clear_alias_for_delete
    bitmap = redis.bitmap(@key)

    bitmap[0] = 1
    bitmap.clear

    assert_equal false, bitmap.exists?
  end

  # ============================================================
  # Expiration Tests
  # ============================================================

  def test_expire_sets_ttl
    bitmap = redis.bitmap(@key)

    bitmap[0] = 1
    result = bitmap.expire(3600)

    assert_same bitmap, result
    assert_operator bitmap.ttl, :>, 0
    assert_operator bitmap.ttl, :<=, 3600
  end

  def test_expire_at_with_time_object
    bitmap = redis.bitmap(@key)

    bitmap[0] = 1
    future_time = Time.now + 3600
    bitmap.expire_at(future_time)

    assert_operator bitmap.ttl, :>, 0
    assert_operator bitmap.ttl, :<=, 3600
  end

  def test_expire_at_with_timestamp
    bitmap = redis.bitmap(@key)

    bitmap[0] = 1
    timestamp = Time.now.to_i + 3600
    bitmap.expire_at(timestamp)

    assert_operator bitmap.ttl, :>, 0
  end

  def test_ttl_returns_negative_one_for_no_expiration
    bitmap = redis.bitmap(@key)

    bitmap[0] = 1

    assert_equal(-1, bitmap.ttl)
  end

  def test_ttl_returns_negative_two_for_nonexistent_key
    bitmap = redis.bitmap(@key)

    assert_equal(-2, bitmap.ttl)
  end

  def test_persist_removes_expiration
    bitmap = redis.bitmap(@key)

    bitmap[0] = 1
    bitmap.expire(3600)
    assert_operator bitmap.ttl, :>, 0

    result = bitmap.persist

    assert_same bitmap, result
    assert_equal(-1, bitmap.ttl)
  end

  # ============================================================
  # Chainability Tests
  # ============================================================

  def test_chainable_set_bit_operations
    bitmap = redis.bitmap(@key)

    bitmap.set_bit(0, 1).set_bit(1, 1).set_bit(2, 1)

    assert_equal 3, bitmap.count
  end

  def test_chainable_with_expiration
    bitmap = redis.bitmap(@key)

    bitmap.set_bit(0, 1).set_bit(1, 1).expire(3600)

    assert_equal 2, bitmap.count
    assert_operator bitmap.ttl, :>, 0
  end

  def test_chainable_bitwise_operations
    bitmap1 = redis.bitmap("#{@key}:1")
    bitmap2 = redis.bitmap("#{@key}:2")

    bitmap1[0] = 1
    bitmap2[1] = 1

    result = redis.bitmap("#{@key}:result")
      .or("#{@key}:1", "#{@key}:2")
      .expire(3600)

    assert_equal 2, result.count
    assert_operator result.ttl, :>, 0
  end

  # ============================================================
  # Integration Tests - Real-World Scenarios
  # ============================================================

  def test_daily_active_users_tracking
    # Track daily active users
    today = redis.bitmap(:dau, "2024-01-15")

    # Users 1, 5, 10, 15, 20 were active
    [1, 5, 10, 15, 20].each { |user_id| today[user_id] = 1 }

    assert_equal 5, today.count
    assert_equal 1, today[10]
    assert_equal 0, today[11]

    # Set to expire at end of day
    today.expire(86400)
    assert_operator today.ttl, :>, 0
  end

  def test_feature_flags_per_user
    # Track which features are enabled for a user
    user_features = redis.bitmap(:features, :user, 123)

    feature_search = 0
    feature_export = 1
    feature_api = 2
    feature_admin = 3

    user_features[feature_search] = 1
    user_features[feature_export] = 1
    user_features[feature_api] = 0
    user_features[feature_admin] = 0

    assert_equal 1, user_features[feature_search]
    assert_equal 1, user_features[feature_export]
    assert_equal 0, user_features[feature_api]
    assert_equal 2, user_features.count
  end

  def test_permissions_system
    # Track permissions as bits
    user_perms = redis.bitmap(:permissions, :user, 456)

    perm_read = 0
    perm_write = 1
    perm_delete = 2
    perm_admin = 3

    user_perms[perm_read] = 1
    user_perms[perm_write] = 1
    user_perms[perm_delete] = 0
    user_perms[perm_admin] = 0

    assert_equal 2, user_perms.count
    assert_equal 1, user_perms[perm_read]
    assert_equal 0, user_perms[perm_delete]
  end

  def test_combining_daily_active_users
    # Track users active on different days
    day1 = redis.bitmap(:dau, "2024-01-01")
    day2 = redis.bitmap(:dau, "2024-01-02")

    # Day 1: users 1, 2, 3, 4, 5
    [1, 2, 3, 4, 5].each { |id| day1[id] = 1 }

    # Day 2: users 3, 4, 5, 6, 7
    [3, 4, 5, 6, 7].each { |id| day2[id] = 1 }

    # Find users active both days (AND)
    both_days = redis.bitmap(:dau, "both")
    both_days.and("dau:2024-01-01", "dau:2024-01-02")
    assert_equal 3, both_days.count  # Users 3, 4, 5

    # Find users active either day (OR)
    either_day = redis.bitmap(:dau, "either")
    either_day.or("dau:2024-01-01", "dau:2024-01-02")
    assert_equal 7, either_day.count  # Users 1-7

    # Find users active only one day (XOR)
    one_day = redis.bitmap(:dau, "one")
    one_day.xor("dau:2024-01-01", "dau:2024-01-02")
    assert_equal 4, one_day.count  # Users 1, 2, 6, 7
  end

  def test_bitfield_multiple_counters
    # Store multiple small counters in one bitmap
    counters = redis.bitmap(:page_counters)

    # Set view counts for different pages
    counters.bitfield
      .set(:u16, 0, 100)    # Page 1: 100 views
      .set(:u16, 16, 200)   # Page 2: 200 views
      .set(:u16, 32, 300)   # Page 3: 300 views
      .execute

    # Read all counters
    results = counters.bitfield
      .get(:u16, 0)
      .get(:u16, 16)
      .get(:u16, 32)
      .execute

    assert_equal [100, 200, 300], results

    # Increment page 1 views
    new_count = counters.bitfield
      .incrby(:u16, 0, 50)
      .execute

    assert_equal [150], new_count
  end

  def test_user_activity_heatmap
    # Track user activity across 24 hours
    activity = redis.bitmap(:activity, :user, 789)

    # User was active at hours 0, 8, 12, 18, 23
    [0, 8, 12, 18, 23].each { |hour| activity[hour] = 1 }

    assert_equal 5, activity.count
    assert_equal 1, activity[12]
    assert_equal 0, activity[15]

    # Find first active hour
    first_active = activity.position(1)
    assert_equal 0, first_active
  end
end

