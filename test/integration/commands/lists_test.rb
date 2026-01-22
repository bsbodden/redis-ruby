# frozen_string_literal: true

require "test_helper"

class ListsCommandsTest < RedisRubyTestCase
  use_testcontainers!

  def test_lpush_and_lrange
    redis.lpush("test:list", "c", "b", "a")

    assert_equal %w[a b c], redis.lrange("test:list", 0, -1)
  ensure
    redis.del("test:list")
  end

  def test_rpush
    redis.rpush("test:list", "a", "b", "c")

    assert_equal %w[a b c], redis.lrange("test:list", 0, -1)
  ensure
    redis.del("test:list")
  end

  def test_lpop
    redis.rpush("test:list", "a", "b", "c")

    assert_equal "a", redis.lpop("test:list")
    assert_equal %w[b c], redis.lrange("test:list", 0, -1)
  ensure
    redis.del("test:list")
  end

  def test_rpop
    redis.rpush("test:list", "a", "b", "c")

    assert_equal "c", redis.rpop("test:list")
    assert_equal %w[a b], redis.lrange("test:list", 0, -1)
  ensure
    redis.del("test:list")
  end

  def test_llen
    redis.rpush("test:list", "a", "b", "c")

    assert_equal 3, redis.llen("test:list")
  ensure
    redis.del("test:list")
  end

  def test_lindex
    redis.rpush("test:list", "a", "b", "c")

    assert_equal "b", redis.lindex("test:list", 1)
    assert_equal "c", redis.lindex("test:list", -1)
  ensure
    redis.del("test:list")
  end

  def test_lset
    redis.rpush("test:list", "a", "b", "c")
    redis.lset("test:list", 1, "B")

    assert_equal %w[a B c], redis.lrange("test:list", 0, -1)
  ensure
    redis.del("test:list")
  end

  def test_linsert
    redis.rpush("test:list", "a", "c")
    redis.linsert("test:list", :before, "c", "b")

    assert_equal %w[a b c], redis.lrange("test:list", 0, -1)
  ensure
    redis.del("test:list")
  end

  def test_lrem
    redis.rpush("test:list", "a", "b", "a", "c", "a")

    assert_equal 2, redis.lrem("test:list", 2, "a")
    assert_equal %w[b c a], redis.lrange("test:list", 0, -1)
  ensure
    redis.del("test:list")
  end

  def test_ltrim
    redis.rpush("test:list", "a", "b", "c", "d", "e")
    redis.ltrim("test:list", 1, 3)

    assert_equal %w[b c d], redis.lrange("test:list", 0, -1)
  ensure
    redis.del("test:list")
  end

  def test_lmove
    redis.rpush("test:src", "a", "b", "c")
    result = redis.lmove("test:src", "test:dst", :right, :left)

    assert_equal "c", result
    assert_equal %w[a b], redis.lrange("test:src", 0, -1)
    assert_equal %w[c], redis.lrange("test:dst", 0, -1)
  ensure
    redis.del("test:src", "test:dst")
  end

  # LPOP with count tests (Redis 6.2+)
  def test_lpop_with_count
    redis.rpush("test:list", "a", "b", "c", "d", "e")

    result = redis.lpop("test:list", 3)

    assert_equal %w[a b c], result
    assert_equal %w[d e], redis.lrange("test:list", 0, -1)
  ensure
    redis.del("test:list")
  end

  def test_lpop_with_count_greater_than_length
    redis.rpush("test:list", "a", "b")

    result = redis.lpop("test:list", 5)

    assert_equal %w[a b], result
    assert_equal 0, redis.llen("test:list")
  ensure
    redis.del("test:list")
  end

  def test_lpop_with_count_empty_list
    redis.del("test:list")

    result = redis.lpop("test:list", 3)

    assert_nil result
  end

  def test_lpop_with_count_one
    redis.rpush("test:list", "a", "b", "c")

    result = redis.lpop("test:list", 1)

    assert_equal %w[a], result
  ensure
    redis.del("test:list")
  end

  # RPOP with count tests (Redis 6.2+)
  def test_rpop_with_count
    redis.rpush("test:list", "a", "b", "c", "d", "e")

    result = redis.rpop("test:list", 3)

    assert_equal %w[e d c], result
    assert_equal %w[a b], redis.lrange("test:list", 0, -1)
  ensure
    redis.del("test:list")
  end

  def test_rpop_with_count_greater_than_length
    redis.rpush("test:list", "a", "b")

    result = redis.rpop("test:list", 5)

    assert_equal %w[b a], result
    assert_equal 0, redis.llen("test:list")
  ensure
    redis.del("test:list")
  end

  def test_rpop_with_count_empty_list
    redis.del("test:list")

    result = redis.rpop("test:list", 3)

    assert_nil result
  end

  # LPUSHX tests
  def test_lpushx_on_existing_list
    redis.rpush("test:list", "a")
    result = redis.lpushx("test:list", "b", "c")

    assert_equal 3, result
    assert_equal %w[c b a], redis.lrange("test:list", 0, -1)
  ensure
    redis.del("test:list")
  end

  def test_lpushx_on_nonexistent_list
    redis.del("test:list")
    result = redis.lpushx("test:list", "a")

    assert_equal 0, result
    assert_equal 0, redis.llen("test:list")
  end

  def test_lpushx_multiple_values
    redis.rpush("test:list", "d")
    result = redis.lpushx("test:list", "a", "b", "c")

    assert_equal 4, result
    # LPUSH pushes in reverse order, so a, b, c becomes c, b, a, d
    assert_equal %w[c b a d], redis.lrange("test:list", 0, -1)
  ensure
    redis.del("test:list")
  end

  # RPUSHX tests
  def test_rpushx_on_existing_list
    redis.rpush("test:list", "a")
    result = redis.rpushx("test:list", "b", "c")

    assert_equal 3, result
    assert_equal %w[a b c], redis.lrange("test:list", 0, -1)
  ensure
    redis.del("test:list")
  end

  def test_rpushx_on_nonexistent_list
    redis.del("test:list")
    result = redis.rpushx("test:list", "a")

    assert_equal 0, result
    assert_equal 0, redis.llen("test:list")
  end

  def test_rpushx_multiple_values
    redis.rpush("test:list", "a")
    result = redis.rpushx("test:list", "b", "c", "d")

    assert_equal 4, result
    assert_equal %w[a b c d], redis.lrange("test:list", 0, -1)
  ensure
    redis.del("test:list")
  end

  # LPOS tests (Redis 6.0.6+)
  def test_lpos_finds_element
    redis.rpush("test:list", "a", "b", "c", "b", "d")

    result = redis.lpos("test:list", "b")

    assert_equal 1, result
  ensure
    redis.del("test:list")
  end

  def test_lpos_with_rank
    redis.rpush("test:list", "a", "b", "c", "b", "d")

    # rank 2 means find the second occurrence
    result = redis.lpos("test:list", "b", rank: 2)

    assert_equal 3, result
  ensure
    redis.del("test:list")
  end

  def test_lpos_with_count
    redis.rpush("test:list", "a", "b", "c", "b", "d", "b")

    result = redis.lpos("test:list", "b", count: 2)

    assert_equal [1, 3], result
  ensure
    redis.del("test:list")
  end

  def test_lpos_not_found
    redis.rpush("test:list", "a", "b", "c")

    result = redis.lpos("test:list", "z")

    assert_nil result
  ensure
    redis.del("test:list")
  end

  # Binary data tests
  def test_list_binary_data
    binary_value = "\x00\x01\x02\xFF".b
    redis.rpush("test:list", binary_value)

    result = redis.lpop("test:list")

    assert_equal binary_value, result
  ensure
    redis.del("test:list")
  end

  def test_list_empty_string
    redis.rpush("test:list", "")

    result = redis.lpop("test:list")

    assert_equal "", result
  ensure
    redis.del("test:list")
  end

  # Edge cases
  def test_lpop_empty_list
    redis.del("test:list")

    assert_nil redis.lpop("test:list")
  end

  def test_rpop_empty_list
    redis.del("test:list")

    assert_nil redis.rpop("test:list")
  end

  def test_lrange_empty_list
    redis.del("test:list")

    assert_equal [], redis.lrange("test:list", 0, -1)
  end

  def test_llen_empty_list
    redis.del("test:list")

    assert_equal 0, redis.llen("test:list")
  end

  def test_lindex_out_of_bounds
    redis.rpush("test:list", "a", "b", "c")

    assert_nil redis.lindex("test:list", 10)
    assert_nil redis.lindex("test:list", -10)
  ensure
    redis.del("test:list")
  end

  def test_lset_out_of_bounds_raises
    redis.rpush("test:list", "a", "b", "c")

    assert_raises(RedisRuby::CommandError) do
      redis.lset("test:list", 10, "value")
    end
  ensure
    redis.del("test:list")
  end

  def test_linsert_pivot_not_found
    redis.rpush("test:list", "a", "b", "c")

    result = redis.linsert("test:list", :before, "z", "value")

    assert_equal(-1, result)
  ensure
    redis.del("test:list")
  end

  def test_lrem_zero_removes_all
    redis.rpush("test:list", "a", "b", "a", "c", "a")

    result = redis.lrem("test:list", 0, "a")

    assert_equal 3, result
    assert_equal %w[b c], redis.lrange("test:list", 0, -1)
  ensure
    redis.del("test:list")
  end

  def test_lrem_negative_from_tail
    redis.rpush("test:list", "a", "b", "a", "c", "a")

    result = redis.lrem("test:list", -2, "a")

    assert_equal 2, result
    assert_equal %w[a b c], redis.lrange("test:list", 0, -1)
  ensure
    redis.del("test:list")
  end

  # RPOPLPUSH tests
  def test_rpoplpush
    redis.rpush("test:src", "a", "b", "c")

    result = redis.rpoplpush("test:src", "test:dst")

    assert_equal "c", result
    assert_equal %w[a b], redis.lrange("test:src", 0, -1)
    assert_equal %w[c], redis.lrange("test:dst", 0, -1)
  ensure
    redis.del("test:src", "test:dst")
  end

  def test_rpoplpush_same_list
    redis.rpush("test:list", "a", "b", "c")

    result = redis.rpoplpush("test:list", "test:list")

    assert_equal "c", result
    assert_equal %w[c a b], redis.lrange("test:list", 0, -1)
  ensure
    redis.del("test:list")
  end

  def test_rpoplpush_empty_source
    redis.del("test:src")

    result = redis.rpoplpush("test:src", "test:dst")

    assert_nil result
  ensure
    redis.del("test:src", "test:dst")
  end

  # ============================================================
  # LMPOP Tests (Redis 7.0+)
  # ============================================================

  def test_lmpop_left
    redis.rpush("test:list", "a", "b", "c")

    result = redis.lmpop("test:list", direction: :left)

    assert_equal "test:list", result[0]
    assert_equal ["a"], result[1]
    assert_equal %w[b c], redis.lrange("test:list", 0, -1)
  rescue RedisRuby::CommandError => e
    skip "LMPOP not supported (requires Redis 7.0+)" if e.message.include?("unknown command")
    raise
  ensure
    redis.del("test:list")
  end

  def test_lmpop_right
    redis.rpush("test:list", "a", "b", "c")

    result = redis.lmpop("test:list", direction: :right)

    assert_equal "test:list", result[0]
    assert_equal ["c"], result[1]
    assert_equal %w[a b], redis.lrange("test:list", 0, -1)
  rescue RedisRuby::CommandError => e
    skip "LMPOP not supported (requires Redis 7.0+)" if e.message.include?("unknown command")
    raise
  ensure
    redis.del("test:list")
  end

  def test_lmpop_with_count
    redis.rpush("test:list", "a", "b", "c", "d", "e")

    result = redis.lmpop("test:list", direction: :left, count: 3)

    assert_equal "test:list", result[0]
    assert_equal %w[a b c], result[1]
    assert_equal %w[d e], redis.lrange("test:list", 0, -1)
  rescue RedisRuby::CommandError => e
    skip "LMPOP not supported (requires Redis 7.0+)" if e.message.include?("unknown command")
    raise
  ensure
    redis.del("test:list")
  end

  def test_lmpop_multiple_lists
    redis.rpush("test:list2", "x", "y")

    result = redis.lmpop("test:list1", "test:list2", direction: :left)

    # Pops from first non-empty list
    assert_equal "test:list2", result[0]
    assert_equal ["x"], result[1]
  rescue RedisRuby::CommandError => e
    skip "LMPOP not supported (requires Redis 7.0+)" if e.message.include?("unknown command")
    raise
  ensure
    redis.del("test:list1", "test:list2")
  end

  def test_lmpop_empty_lists
    redis.del("test:list1", "test:list2")

    result = redis.lmpop("test:list1", "test:list2", direction: :left)

    assert_nil result
  rescue RedisRuby::CommandError => e
    skip "LMPOP not supported (requires Redis 7.0+)" if e.message.include?("unknown command")
    raise
  end

  def test_lmpop_default_direction_is_left
    redis.rpush("test:list", "a", "b", "c")

    result = redis.lmpop("test:list")

    assert_equal "test:list", result[0]
    assert_equal ["a"], result[1]  # Left pop = first element
  rescue RedisRuby::CommandError => e
    skip "LMPOP not supported (requires Redis 7.0+)" if e.message.include?("unknown command")
    raise
  ensure
    redis.del("test:list")
  end
end
