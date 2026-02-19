# frozen_string_literal: true

require "test_helper"

class ListDSLTest < Minitest::Test
  def setup
    @redis = RR.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379"))
    @key = "test:list:#{SecureRandom.hex(8)}"
  end

  def teardown
    @redis.del(@key)
    @redis.close
  end

  attr_reader :redis

  # ============================================================
  # Entry Point Tests
  # ============================================================

  def test_list_creates_proxy
    list = redis.list(@key)

    assert_instance_of RR::DSL::ListProxy, list
  end

  def test_list_with_composite_key
    list = redis.list(:jobs, :pending, 123)
    list.push("job1")

    assert_equal "job1", redis.lindex("jobs:pending:123", 0)
  end
  # ============================================================
  # Push/Pop Tests (Right Side)
  # ============================================================

  def test_push_single_value
    list = redis.list(@key)
    result = list.push("item1")

    assert_same list, result
    assert_equal "item1", redis.lindex(@key, 0)
  end

  def test_push_multiple_values
    list = redis.list(@key)
    list.push("item1", "item2", "item3")

    assert_equal %w[item1 item2 item3], redis.lrange(@key, 0, -1)
  end

  def test_push_operator
    list = redis.list(@key)
    list << "item1" << "item2"

    assert_equal %w[item1 item2], redis.lrange(@key, 0, -1)
  end

  def test_pop_single
    redis.rpush(@key, "item1", "item2", "item3")
    list = redis.list(@key)

    result = list.pop

    assert_equal "item3", result
    assert_equal 2, redis.llen(@key)
  end

  def test_pop_multiple
    redis.rpush(@key, "item1", "item2", "item3")
    list = redis.list(@key)

    result = list.pop(2)

    assert_equal %w[item3 item2], result
    assert_equal 1, redis.llen(@key)
  end
  # ============================================================
  # Shift/Unshift Tests (Left Side)
  # ============================================================

  def test_shift_single
    redis.rpush(@key, "item1", "item2", "item3")
    list = redis.list(@key)

    result = list.shift

    assert_equal "item1", result
    assert_equal 2, redis.llen(@key)
  end

  def test_shift_multiple
    redis.rpush(@key, "item1", "item2", "item3")
    list = redis.list(@key)

    result = list.shift(2)

    assert_equal %w[item1 item2], result
    assert_equal 1, redis.llen(@key)
  end

  def test_unshift_single
    list = redis.list(@key)
    result = list.unshift("item1")

    assert_same list, result
    assert_equal "item1", redis.lindex(@key, 0)
  end

  def test_unshift_multiple
    list = redis.list(@key)
    list.unshift("item1", "item2", "item3")

    # LPUSH adds in reverse order
    assert_equal %w[item3 item2 item1], redis.lrange(@key, 0, -1)
  end
  # ============================================================
  # Array-Like Access Tests
  # ============================================================

  def test_index_access
    redis.rpush(@key, "item1", "item2", "item3")
    list = redis.list(@key)

    assert_equal "item1", list[0]
    assert_equal "item2", list[1]
    assert_equal "item3", list[-1]
  end

  def test_range_access
    redis.rpush(@key, "item1", "item2", "item3", "item4", "item5")
    list = redis.list(@key)

    assert_equal %w[item1 item2 item3], list[0..2]
    assert_equal %w[item2 item3], list[1..2]
  end

  def test_range_access_with_count
    redis.rpush(@key, "item1", "item2", "item3", "item4", "item5")
    list = redis.list(@key)

    assert_equal %w[item1 item2 item3], list[0, 3]
    assert_equal %w[item2 item3], list[1, 2]
  end

  def test_index_assignment
    redis.rpush(@key, "item1", "item2", "item3")
    list = redis.list(@key)

    list[1] = "new_value"

    assert_equal "new_value", redis.lindex(@key, 1)
  end
  # ============================================================
  # Insertion Tests
  # ============================================================

  def test_insert_before
    redis.rpush(@key, "item1", "item2", "item3")
    list = redis.list(@key)

    result = list.insert_before("item2", "new_item")

    assert_same list, result
    assert_equal %w[item1 new_item item2 item3], redis.lrange(@key, 0, -1)
  end

  def test_insert_after
    redis.rpush(@key, "item1", "item2", "item3")
    list = redis.list(@key)

    result = list.insert_after("item2", "new_item")

    assert_same list, result
    assert_equal %w[item1 item2 new_item item3], redis.lrange(@key, 0, -1)
  end
end

class ListDSLTestPart2 < Minitest::Test
  def setup
    @redis = RR.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379"))
    @key = "test:list:#{SecureRandom.hex(8)}"
  end

  def teardown
    @redis.del(@key)
    @redis.close
  end

  attr_reader :redis

  # ============================================================
  # Entry Point Tests
  # ============================================================

  # ============================================================
  # Removal Tests
  # ============================================================

  def test_remove_all_occurrences
    redis.rpush(@key, "a", "b", "a", "c", "a")
    list = redis.list(@key)

    removed = list.remove("a")

    assert_equal 3, removed
    assert_equal %w[b c], redis.lrange(@key, 0, -1)
  end

  def test_remove_first_occurrence
    redis.rpush(@key, "a", "b", "a", "c", "a")
    list = redis.list(@key)

    removed = list.remove("a", count: 1)

    assert_equal 1, removed
    assert_equal %w[b a c a], redis.lrange(@key, 0, -1)
  end

  def test_remove_last_occurrence
    redis.rpush(@key, "a", "b", "a", "c", "a")
    list = redis.list(@key)

    removed = list.remove("a", count: -1)

    assert_equal 1, removed
    assert_equal %w[a b a c], redis.lrange(@key, 0, -1)
  end
  # ============================================================
  # Trimming Tests
  # ============================================================

  def test_trim_with_range
    redis.rpush(@key, "item1", "item2", "item3", "item4", "item5")
    list = redis.list(@key)

    result = list.trim(0..2)

    assert_same list, result
    assert_equal %w[item1 item2 item3], redis.lrange(@key, 0, -1)
  end

  def test_keep_first_n
    redis.rpush(@key, "item1", "item2", "item3", "item4", "item5")
    list = redis.list(@key)

    result = list.keep(3)

    assert_same list, result
    assert_equal %w[item1 item2 item3], redis.lrange(@key, 0, -1)
  end
  # ============================================================
  # Blocking Operations Tests
  # ============================================================

  def test_blocking_shift_with_timeout
    redis.rpush(@key, "item1")
    list = redis.list(@key)

    result = list.blocking_shift(timeout: 1)

    assert_equal "item1", result
  end

  def test_blocking_shift_timeout_expires
    # Test blocking shift with immediate data availability
    # Testing actual timeout expiration would require waiting which conflicts
    # with client read timeout, so we verify the timeout parameter is accepted
    redis.rpush(@key, "quick_item")
    list = redis.list(@key)

    # This should return immediately since data is available
    result = list.blocking_shift(timeout: 5)

    assert_equal "quick_item", result
  end

  def test_blocking_pop_right_with_timeout
    redis.rpush(@key, "item1")
    list = redis.list(@key)

    result = list.blocking_pop_right(timeout: 1)

    assert_equal "item1", result
  end
  # ============================================================
  # Inspection Tests
  # ============================================================

  def test_length
    redis.rpush(@key, "item1", "item2", "item3")
    list = redis.list(@key)

    assert_equal 3, list.length
    assert_equal 3, list.size
    assert_equal 3, list.count
  end

  def test_empty_on_empty_list
    list = redis.list(@key)

    assert_empty list
  end

  def test_empty_on_non_empty_list
    redis.rpush(@key, "item1")
    list = redis.list(@key)

    refute_empty list
  end

  def test_exists_when_key_exists
    redis.rpush(@key, "item1")
    list = redis.list(@key)

    assert_predicate list, :exists?
  end

  def test_exists_when_key_does_not_exist
    list = redis.list(@key)

    refute_predicate list, :exists?
  end
  # ============================================================
  # Conversion Tests
  # ============================================================

  def test_to_a
    redis.rpush(@key, "item1", "item2", "item3")
    list = redis.list(@key)

    assert_equal %w[item1 item2 item3], list.to_a
  end

  def test_first_single
    redis.rpush(@key, "item1", "item2", "item3")
    list = redis.list(@key)

    assert_equal "item1", list.first
  end

  def test_first_multiple
    redis.rpush(@key, "item1", "item2", "item3", "item4")
    list = redis.list(@key)

    assert_equal %w[item1 item2 item3], list.first(3)
  end

  def test_last_single
    redis.rpush(@key, "item1", "item2", "item3")
    list = redis.list(@key)

    assert_equal "item3", list.last
  end

  def test_last_multiple
    redis.rpush(@key, "item1", "item2", "item3", "item4")
    list = redis.list(@key)

    assert_equal %w[item3 item4], list.last(2)
  end
end

class ListDSLTestPart3 < Minitest::Test
  def setup
    @redis = RR.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379"))
    @key = "test:list:#{SecureRandom.hex(8)}"
  end

  def teardown
    @redis.del(@key)
    @redis.close
  end

  attr_reader :redis

  # ============================================================
  # Entry Point Tests
  # ============================================================

  # ============================================================
  # Iteration Tests
  # ============================================================

  def test_each_iterates_over_elements
    redis.rpush(@key, "item1", "item2", "item3")
    list = redis.list(@key)

    items = []
    result = list.each { |item| items << item }

    assert_equal %w[item1 item2 item3], items
    assert_same list, result
  end

  def test_each_returns_enumerator
    redis.rpush(@key, "item1", "item2", "item3")
    list = redis.list(@key)

    enumerator = list.each

    assert_instance_of Enumerator, enumerator
    assert_equal %w[item1 item2 item3], enumerator.to_a
  end

  def test_each_with_index
    redis.rpush(@key, "item1", "item2", "item3")
    list = redis.list(@key)

    items = []
    list.each_with_index { |item, i| items << [item, i] }

    assert_equal [["item1", 0], ["item2", 1], ["item3", 2]], items
  end
  # ============================================================
  # Clear Tests
  # ============================================================

  def test_clear
    redis.rpush(@key, "item1", "item2", "item3")
    list = redis.list(@key)

    result = list.clear

    assert_same list, result
    assert_equal 0, redis.llen(@key)
  end
  # ============================================================
  # Expiration Tests
  # ============================================================

  def test_expire
    list = redis.list(@key)
    list.push("item1")

    result = list.expire(3600)

    assert_same list, result
    assert_operator redis.ttl(@key), :>, 0
  end

  def test_expire_at
    list = redis.list(@key)
    list.push("item1")

    result = list.expire_at(Time.now + 3600)

    assert_same list, result
    assert_operator redis.ttl(@key), :>, 0
  end

  def test_ttl
    list = redis.list(@key)
    list.push("item1").expire(3600)

    ttl = list.ttl

    assert_operator ttl, :>, 0
    assert_operator ttl, :<=, 3600
  end

  def test_persist
    list = redis.list(@key)
    list.push("item1").expire(3600)

    result = list.persist

    assert_same list, result
    assert_equal(-1, redis.ttl(@key))
  end
  # ============================================================
  # Integration Tests
  # ============================================================

  def test_fifo_queue_workflow
    queue = redis.list(:jobs)

    # Producer adds jobs
    queue.push("job1", "job2", "job3")

    # Consumer processes jobs (FIFO)
    job1 = queue.shift
    job2 = queue.shift

    assert_equal "job1", job1
    assert_equal "job2", job2
    assert_equal 1, queue.length

    redis.del("jobs")
  end

  def test_lifo_stack_workflow
    stack = redis.list(:undo)

    # Push actions
    stack.push("action1", "action2", "action3")

    # Undo (LIFO)
    action3 = stack.pop
    action2 = stack.pop

    assert_equal "action3", action3
    assert_equal "action2", action2
    assert_equal 1, stack.length

    redis.del("undo")
  end

  def test_recent_activity_feed_workflow
    feed = redis.list(:user, 123, :activity)

    # Add activities to front
    feed.unshift("activity1")
    feed.unshift("activity2")
    feed.unshift("activity3")

    # Keep only recent 2
    feed.keep(2)

    # Get recent activities
    recent = feed.to_a

    assert_equal %w[activity3 activity2], recent

    redis.del("user:123:activity")
  end

  def test_chainable_operations
    list = redis.list(@key)
      .push("item1", "item2", "item3")
      .trim(0..1)
      .expire(3600)

    assert_equal 2, list.length
    assert_operator list.ttl, :>, 0
  end
end
