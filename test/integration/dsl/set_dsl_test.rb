# frozen_string_literal: true

require "test_helper"

class SetDSLTest < RedisRubyTestCase
  use_testcontainers!

  def setup
    super
    @key = "test:set:#{SecureRandom.hex(8)}"
  end

  # ============================================================
  # Entry Point Tests
  # ============================================================

  def test_set_proxy_creation
    proxy = redis.redis_set(:tags)
    
    assert_instance_of RR::DSL::SetProxy, proxy
    assert_equal "tags", proxy.key
  end

  def test_set_proxy_with_composite_key
    proxy = redis.redis_set(:user, 123, :tags)
    
    assert_equal "user:123:tags", proxy.key
  end

  def test_set_proxy_with_single_key_part
    proxy = redis.redis_set(:simple)
    
    assert_equal "simple", proxy.key
  end

  # ============================================================
  # Add Operations Tests
  # ============================================================

  def test_add_single_member
    set = redis.redis_set(@key)
    
    result = set.add("ruby")
    
    assert_same set, result  # Returns self for chaining
    assert set.member?("ruby")
  end

  def test_add_multiple_members
    set = redis.redis_set(@key)
    
    set.add("ruby", "redis", "database")
    
    assert set.member?("ruby")
    assert set.member?("redis")
    assert set.member?("database")
  end

  def test_add_with_symbols
    set = redis.redis_set(@key)
    
    set.add(:ruby, :redis)
    
    assert set.member?("ruby")
    assert set.member?("redis")
  end

  def test_add_empty_members
    set = redis.redis_set(@key)
    
    result = set.add
    
    assert_same set, result
  end

  def test_shovel_operator_alias
    set = redis.redis_set(@key)
    
    set << "ruby"
    
    assert set.member?("ruby")
  end

  def test_chainable_add
    set = redis.redis_set(@key)
    
    set.add("tag1").add("tag2").add("tag3")
    
    assert_equal 3, set.size
  end

  # ============================================================
  # Removal Tests
  # ============================================================

  def test_remove_single_member
    set = redis.redis_set(@key)
    set.add("ruby", "redis", "database")
    
    result = set.remove("ruby")
    
    assert_same set, result
    refute set.member?("ruby")
    assert set.member?("redis")
  end

  def test_remove_multiple_members
    set = redis.redis_set(@key)
    set.add("tag1", "tag2", "tag3", "tag4")
    
    set.remove("tag1", "tag2", "tag3")
    
    refute set.member?("tag1")
    refute set.member?("tag2")
    refute set.member?("tag3")
    assert set.member?("tag4")
  end

  def test_remove_with_symbols
    set = redis.redis_set(@key)
    set.add("ruby", "redis")
    
    set.remove(:ruby)
    
    refute set.member?("ruby")
    assert set.member?("redis")
  end

  def test_remove_empty_members
    set = redis.redis_set(@key)
    set.add("ruby")
    
    result = set.remove
    
    assert_same set, result
    assert set.member?("ruby")
  end

  def test_delete_alias
    set = redis.redis_set(@key)
    set.add("ruby")
    
    set.delete("ruby")
    
    refute set.member?("ruby")
  end

  def test_clear
    set = redis.redis_set(@key)
    set.add("tag1", "tag2", "tag3")

    result = set.clear

    assert_equal 1, result  # Returns number of keys deleted
    assert set.empty?
  end

  # ============================================================
  # Membership Tests
  # ============================================================

  def test_member_with_existing_member
    set = redis.redis_set(@key)
    set.add("ruby", "redis")

    assert set.member?("ruby")
    assert set.member?("redis")
  end

  def test_member_with_nonexistent_member
    set = redis.redis_set(@key)
    set.add("ruby")

    refute set.member?("python")
  end

  def test_member_with_symbol
    set = redis.redis_set(@key)
    set.add("ruby")

    assert set.member?(:ruby)
  end

  def test_include_alias
    set = redis.redis_set(@key)
    set.add("ruby")

    assert set.include?("ruby")
    refute set.include?("python")
  end

  # ============================================================
  # Inspection Tests
  # ============================================================

  def test_members
    set = redis.redis_set(@key)
    set.add("ruby", "redis", "database")

    members = set.members

    assert_equal 3, members.size
    assert_includes members, "ruby"
    assert_includes members, "redis"
    assert_includes members, "database"
  end

  def test_members_empty_set
    set = redis.redis_set(@key)

    assert_equal [], set.members
  end

  def test_to_a_alias
    set = redis.redis_set(@key)
    set.add("tag1", "tag2")

    assert_equal 2, set.to_a.size
  end

  def test_size
    set = redis.redis_set(@key)
    set.add("tag1", "tag2", "tag3")

    assert_equal 3, set.size
  end

  def test_size_empty_set
    set = redis.redis_set(@key)

    assert_equal 0, set.size
  end

  def test_length_alias
    set = redis.redis_set(@key)
    set.add("tag1", "tag2")

    assert_equal 2, set.length
  end

  def test_count_alias
    set = redis.redis_set(@key)
    set.add("tag1", "tag2")

    assert_equal 2, set.count
  end

  def test_empty_with_empty_set
    set = redis.redis_set(@key)

    assert set.empty?
  end

  def test_empty_with_non_empty_set
    set = redis.redis_set(@key)
    set.add("tag1")

    refute set.empty?
  end

  def test_exists_with_existing_key
    set = redis.redis_set(@key)
    set.add("tag1")

    assert set.exists?
  end

  def test_exists_with_nonexistent_key
    set = redis.redis_set(@key)

    refute set.exists?
  end

  # ============================================================
  # Set Operations Tests
  # ============================================================

  def test_union_with_other_sets
    set1 = redis.redis_set("#{@key}:1")
    set2 = redis.redis_set("#{@key}:2")
    set3 = redis.redis_set("#{@key}:3")

    set1.add("a", "b", "c")
    set2.add("b", "c", "d")
    set3.add("c", "d", "e")

    result = set1.union("#{@key}:2", "#{@key}:3")

    assert_equal 5, result.size
    assert_includes result, "a"
    assert_includes result, "b"
    assert_includes result, "c"
    assert_includes result, "d"
    assert_includes result, "e"
  end

  def test_union_with_no_other_sets
    set = redis.redis_set(@key)
    set.add("a", "b")

    result = set.union

    assert_equal 2, result.size
  end

  def test_intersect_with_other_sets
    set1 = redis.redis_set("#{@key}:1")
    set2 = redis.redis_set("#{@key}:2")
    set3 = redis.redis_set("#{@key}:3")

    set1.add("a", "b", "c", "d")
    set2.add("b", "c", "d", "e")
    set3.add("c", "d", "e", "f")

    result = set1.intersect("#{@key}:2", "#{@key}:3")

    assert_equal 2, result.size
    assert_includes result, "c"
    assert_includes result, "d"
  end

  def test_intersect_with_no_other_sets
    set = redis.redis_set(@key)
    set.add("a", "b")

    result = set.intersect

    assert_equal 2, result.size
  end

  def test_difference_with_other_sets
    set1 = redis.redis_set("#{@key}:1")
    set2 = redis.redis_set("#{@key}:2")
    set3 = redis.redis_set("#{@key}:3")

    set1.add("a", "b", "c", "d", "e")
    set2.add("b", "c")
    set3.add("d")

    result = set1.difference("#{@key}:2", "#{@key}:3")

    assert_equal 2, result.size
    assert_includes result, "a"
    assert_includes result, "e"
  end

  def test_difference_with_no_other_sets
    set = redis.redis_set(@key)
    set.add("a", "b")

    result = set.difference

    assert_equal 2, result.size
  end

  # ============================================================
  # Random/Pop Tests
  # ============================================================

  def test_random_single_member
    set = redis.redis_set(@key)
    set.add("tag1", "tag2", "tag3")

    member = set.random

    assert_includes ["tag1", "tag2", "tag3"], member
  end

  def test_random_multiple_members
    set = redis.redis_set(@key)
    set.add("tag1", "tag2", "tag3", "tag4", "tag5")

    members = set.random(3)

    assert_equal 3, members.size
    members.each do |member|
      assert_includes ["tag1", "tag2", "tag3", "tag4", "tag5"], member
    end
  end

  def test_random_empty_set
    set = redis.redis_set(@key)

    assert_nil set.random
  end

  def test_pop_single_member
    set = redis.redis_set(@key)
    set.add("tag1", "tag2", "tag3")

    member = set.pop

    assert_includes ["tag1", "tag2", "tag3"], member
    assert_equal 2, set.size
  end

  def test_pop_multiple_members
    set = redis.redis_set(@key)
    set.add("tag1", "tag2", "tag3", "tag4", "tag5")

    members = set.pop(3)

    assert_equal 3, members.size
    assert_equal 2, set.size
  end

  def test_pop_empty_set
    set = redis.redis_set(@key)

    assert_nil set.pop
  end

  # ============================================================
  # Iteration Tests
  # ============================================================

  def test_each_with_block
    set = redis.redis_set(@key)
    set.add("tag1", "tag2", "tag3")

    collected = []
    result = set.each { |member| collected << member }

    assert_same set, result
    assert_equal 3, collected.size
    assert_includes collected, "tag1"
    assert_includes collected, "tag2"
    assert_includes collected, "tag3"
  end

  def test_each_without_block
    set = redis.redis_set(@key)
    set.add("tag1", "tag2")

    enumerator = set.each

    assert_instance_of Enumerator, enumerator
    assert_equal 2, enumerator.to_a.size
  end

  def test_each_member_alias
    set = redis.redis_set(@key)
    set.add("tag1", "tag2")

    collected = []
    set.each_member { |member| collected << member }

    assert_equal 2, collected.size
  end

  # ============================================================
  # Expiration Tests
  # ============================================================

  def test_expire
    set = redis.redis_set(@key)
    set.add("tag1")

    result = set.expire(3600)

    assert_same set, result
    ttl = set.ttl
    assert ttl > 0
    assert ttl <= 3600
  end

  def test_expire_at_with_time
    set = redis.redis_set(@key)
    set.add("tag1")

    result = set.expire_at(Time.now + 3600)

    assert_same set, result
    ttl = set.ttl
    assert ttl > 0
    assert ttl <= 3600
  end

  def test_expire_at_with_timestamp
    set = redis.redis_set(@key)
    set.add("tag1")

    result = set.expire_at(Time.now.to_i + 3600)

    assert_same set, result
    ttl = set.ttl
    assert ttl > 0
  end

  def test_ttl_with_expiration
    set = redis.redis_set(@key)
    set.add("tag1")
    set.expire(3600)

    ttl = set.ttl

    assert ttl > 0
    assert ttl <= 3600
  end

  def test_ttl_without_expiration
    set = redis.redis_set(@key)
    set.add("tag1")

    assert_equal(-1, set.ttl)
  end

  def test_ttl_nonexistent_key
    set = redis.redis_set(@key)

    assert_equal(-2, set.ttl)
  end

  def test_persist
    set = redis.redis_set(@key)
    set.add("tag1")
    set.expire(3600)

    result = set.persist

    assert_same set, result
    assert_equal(-1, set.ttl)
  end

  # ============================================================
  # Integration Tests
  # ============================================================

  def test_tags_workflow
    post_tags = redis.redis_set(:post, 123, :tags)

    # Add tags
    post_tags.add("ruby", "redis", "tutorial", "database")

    # Check membership
    assert post_tags.member?("ruby")
    assert_equal 4, post_tags.size

    # Remove a tag
    post_tags.remove("tutorial")
    assert_equal 3, post_tags.size

    # Iterate
    tags = []
    post_tags.each { |tag| tags << tag }
    assert_equal 3, tags.size

    # Cleanup
    post_tags.clear
  end

  def test_unique_visitors_workflow
    visitors = redis.redis_set(:visitors, :today)

    # Add visitors
    visitors.add("user:123", "user:456", "user:789")
    visitors.add("user:123")  # Duplicate, should not increase count

    assert_equal 3, visitors.size

    # Check if user visited
    assert visitors.member?("user:123")
    refute visitors.member?("user:999")

    # Set expiration (daily reset)
    visitors.expire(86400)
    assert visitors.ttl > 0

    # Cleanup
    visitors.clear
  end

  def test_set_operations_workflow
    product_a_fans = redis.redis_set(:product, "A", :fans)
    product_b_fans = redis.redis_set(:product, "B", :fans)
    product_c_fans = redis.redis_set(:product, "C", :fans)

    product_a_fans.add("user:1", "user:2", "user:3", "user:4")
    product_b_fans.add("user:2", "user:3", "user:5", "user:6")
    product_c_fans.add("user:3", "user:6", "user:7")

    # Users who like both A and B
    both = product_a_fans.intersect("product:B:fans")
    assert_equal 2, both.size
    assert_includes both, "user:2"
    assert_includes both, "user:3"

    # Users who like A or B
    either = product_a_fans.union("product:B:fans")
    assert_equal 6, either.size

    # Users who like A but not B
    only_a = product_a_fans.difference("product:B:fans")
    assert_equal 2, only_a.size
    assert_includes only_a, "user:1"
    assert_includes only_a, "user:4"

    # Cleanup
    product_a_fans.clear
    product_b_fans.clear
    product_c_fans.clear
  end

  def test_chainable_operations
    set = redis.redis_set(@key)

    set.add("tag1", "tag2", "tag3")
       .remove("tag1")
       .expire(3600)

    assert_equal 2, set.size
    refute set.member?("tag1")
    assert set.ttl > 0

    set.clear
  end
end


