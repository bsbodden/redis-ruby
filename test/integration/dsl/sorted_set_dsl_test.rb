# frozen_string_literal: true

require "test_helper"

class SortedSetDSLTest < Minitest::Test
  def setup
    @redis = RR.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379"))
    @key = "test:sorted_set:#{SecureRandom.hex(8)}"
  end

  def teardown
    @redis.del(@key) if @redis
    @redis&.close
  end

  def redis
    @redis
  end

  # ============================================================
  # Entry Point Tests
  # ============================================================

  def test_sorted_set_creates_proxy
    sorted_set = redis.sorted_set(@key)
    
    assert_instance_of RR::DSL::SortedSetProxy, sorted_set
    assert_equal @key, sorted_set.key
  end

  def test_sorted_set_with_composite_key
    sorted_set = redis.sorted_set(:leaderboard, :game, 123)
    
    assert_equal "leaderboard:game:123", sorted_set.key
  end

  # ============================================================
  # Add Operations Tests
  # ============================================================

  def test_add_single_member
    sorted_set = redis.sorted_set(@key)
    
    result = sorted_set.add(:player1, 100)
    
    assert_same sorted_set, result
    assert_equal 100.0, sorted_set.score(:player1)
  end

  def test_add_multiple_members_with_hash
    sorted_set = redis.sorted_set(@key)
    
    sorted_set.add(player1: 100, player2: 200, player3: 150)
    
    assert_equal 100.0, sorted_set.score(:player1)
    assert_equal 200.0, sorted_set.score(:player2)
    assert_equal 150.0, sorted_set.score(:player3)
  end

  def test_add_chainable
    sorted_set = redis.sorted_set(@key)
    
    sorted_set.add(:player1, 100)
              .add(:player2, 200)
              .add(player3: 150)
    
    assert_equal 3, sorted_set.count
  end

  # ============================================================
  # Score Operations Tests
  # ============================================================

  def test_increment_score
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(:player1, 100)
    
    result = sorted_set.increment(:player1, 10)
    
    assert_same sorted_set, result
    assert_equal 110.0, sorted_set.score(:player1)
  end

  def test_increment_default_by_one
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(:player1, 100)
    
    sorted_set.increment(:player1)
    
    assert_equal 101.0, sorted_set.score(:player1)
  end

  def test_decrement_score
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(:player1, 100)
    
    result = sorted_set.decrement(:player1, 10)
    
    assert_same sorted_set, result
    assert_equal 90.0, sorted_set.score(:player1)
  end

  def test_score_returns_nil_for_nonexistent_member
    sorted_set = redis.sorted_set(@key)
    
    score = sorted_set.score(:nonexistent)
    
    assert_nil score
  end

  # ============================================================
  # Rank Operations Tests
  # ============================================================

  def test_rank_ascending_order
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(player1: 100, player2: 200, player3: 150)
    
    assert_equal 0, sorted_set.rank(:player1)  # Lowest score
    assert_equal 1, sorted_set.rank(:player3)
    assert_equal 2, sorted_set.rank(:player2)  # Highest score
  end

  def test_reverse_rank_descending_order
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(player1: 100, player2: 200, player3: 150)
    
    assert_equal 2, sorted_set.reverse_rank(:player1)  # Lowest score
    assert_equal 1, sorted_set.reverse_rank(:player3)
    assert_equal 0, sorted_set.reverse_rank(:player2)  # Highest score
  end

  def test_rank_returns_nil_for_nonexistent_member
    sorted_set = redis.sorted_set(@key)
    
    assert_nil sorted_set.rank(:nonexistent)
    assert_nil sorted_set.reverse_rank(:nonexistent)
  end

  # ============================================================
  # Range Query Tests
  # ============================================================

  def test_top_returns_highest_scores
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(player1: 100, player2: 200, player3: 150, player4: 175)
    
    result = sorted_set.top(2)
    
    assert_equal ["player2", "player4"], result
  end

  def test_top_with_scores
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(player1: 100, player2: 200)

    result = sorted_set.top(2, with_scores: true)

    assert_equal [["player2", 200.0], ["player1", 100.0]], result
  end

  def test_bottom_returns_lowest_scores
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(player1: 100, player2: 200, player3: 150, player4: 175)

    result = sorted_set.bottom(2)

    assert_equal ["player1", "player3"], result
  end

  def test_bottom_with_scores
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(player1: 100, player2: 200)

    result = sorted_set.bottom(2, with_scores: true)

    assert_equal [["player1", 100.0], ["player2", 200.0]], result
  end

  def test_range_by_rank
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(player1: 100, player2: 200, player3: 150)

    result = sorted_set.range(0..1)

    assert_equal ["player1", "player3"], result
  end

  def test_reverse_range_by_rank
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(player1: 100, player2: 200, player3: 150)

    result = sorted_set.reverse_range(0..1)

    assert_equal ["player2", "player3"], result
  end

  def test_by_score_range
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(player1: 100, player2: 200, player3: 150, player4: 175)

    result = sorted_set.by_score(100, 175)

    assert_equal 3, result.size
    assert_includes result, "player1"
    assert_includes result, "player3"
    assert_includes result, "player4"
  end

  def test_by_score_with_scores
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(player1: 100, player2: 200)

    result = sorted_set.by_score(100, 200, with_scores: true)

    assert_equal [["player1", 100.0], ["player2", 200.0]], result
  end

  def test_reverse_by_score_range
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(player1: 100, player2: 200, player3: 150)

    result = sorted_set.reverse_by_score(200, 100)

    assert_equal ["player2", "player3", "player1"], result
  end

  # ============================================================
  # Removal Tests
  # ============================================================

  def test_remove_single_member
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(player1: 100, player2: 200)

    result = sorted_set.remove(:player1)

    assert_same sorted_set, result
    assert_nil sorted_set.score(:player1)
    assert_equal 1, sorted_set.count
  end

  def test_remove_multiple_members
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(player1: 100, player2: 200, player3: 150)

    sorted_set.remove(:player1, :player2)

    assert_equal 1, sorted_set.count
    assert_equal 150.0, sorted_set.score(:player3)
  end

  def test_remove_by_rank
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(player1: 100, player2: 200, player3: 150)

    result = sorted_set.remove_by_rank(0..0)  # Remove lowest

    assert_equal 1, result  # Returns count of removed members
    assert_nil sorted_set.score(:player1)
    assert_equal 2, sorted_set.count
  end

  def test_remove_by_score
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(player1: 100, player2: 200, player3: 150)

    result = sorted_set.remove_by_score(0, 150)

    assert_equal 2, result  # Returns count of removed members
    assert_equal 1, sorted_set.count
    assert_equal 200.0, sorted_set.score(:player2)
  end

  # ============================================================
  # Pop Tests
  # ============================================================

  def test_pop_min_single
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(player1: 100, player2: 200)

    result = sorted_set.pop_min

    assert_equal "player1", result
    assert_equal 1, sorted_set.count
  end

  def test_pop_min_multiple
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(player1: 100, player2: 200, player3: 150)

    result = sorted_set.pop_min(2)

    assert_equal ["player1", "player3"], result
    assert_equal 1, sorted_set.count
  end

  def test_pop_min_with_scores
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(player1: 100, player2: 200)

    result = sorted_set.pop_min(2, with_scores: true)

    assert_equal [["player1", 100.0], ["player2", 200.0]], result
  end

  def test_pop_max_single
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(player1: 100, player2: 200)

    result = sorted_set.pop_max

    assert_equal "player2", result
    assert_equal 1, sorted_set.count
  end

  def test_pop_max_multiple
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(player1: 100, player2: 200, player3: 150)

    result = sorted_set.pop_max(2)

    assert_equal ["player2", "player3"], result
    assert_equal 1, sorted_set.count
  end

  # ============================================================
  # Count Tests
  # ============================================================

  def test_count_returns_total_members
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(player1: 100, player2: 200, player3: 150)

    assert_equal 3, sorted_set.count
    assert_equal 3, sorted_set.size
    assert_equal 3, sorted_set.length
  end

  def test_count_by_score
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(player1: 100, player2: 200, player3: 150, player4: 175)

    count = sorted_set.count_by_score(100, 175)

    assert_equal 3, count
  end

  # ============================================================
  # Existence Tests
  # ============================================================

  def test_member_returns_true_when_exists
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(:player1, 100)

    assert sorted_set.member?(:player1)
    assert sorted_set.include?(:player1)
  end

  def test_member_returns_false_when_not_exists
    sorted_set = redis.sorted_set(@key)

    refute sorted_set.member?(:nonexistent)
  end

  def test_exists_returns_true_when_key_exists
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(:player1, 100)

    assert sorted_set.exists?
  end

  def test_exists_returns_false_when_key_not_exists
    sorted_set = redis.sorted_set(@key)

    refute sorted_set.exists?
  end

  def test_empty_returns_true_when_no_members
    sorted_set = redis.sorted_set(@key)

    assert sorted_set.empty?
  end

  def test_empty_returns_false_when_has_members
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(:player1, 100)

    refute sorted_set.empty?
  end

  # ============================================================
  # Clear Test
  # ============================================================

  def test_clear_removes_all_members
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(player1: 100, player2: 200)

    result = sorted_set.clear

    assert_equal 1, result
    refute sorted_set.exists?
  end

  # ============================================================
  # Iteration Tests
  # ============================================================

  def test_each_iterates_over_members_with_scores
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(player1: 100, player2: 200)

    members = []
    result = sorted_set.each { |member, score| members << [member, score] }

    assert_same sorted_set, result
    assert_equal 2, members.size
    assert_includes members, [:player1, 100.0]
    assert_includes members, [:player2, 200.0]
  end

  def test_each_without_block_returns_enumerator
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(:player1, 100)

    result = sorted_set.each

    assert_instance_of Enumerator, result
  end

  def test_each_member_iterates_over_members_only
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(player1: 100, player2: 200)

    members = []
    sorted_set.each_member { |member| members << member }

    assert_equal 2, members.size
    assert_includes members, :player1
    assert_includes members, :player2
  end

  # ============================================================
  # Conversion Tests
  # ============================================================

  def test_to_a_returns_array_of_members
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(player1: 100, player2: 200, player3: 150)

    result = sorted_set.to_a

    assert_equal ["player1", "player3", "player2"], result
  end

  def test_to_a_with_scores
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(player1: 100, player2: 200)

    result = sorted_set.to_a(with_scores: true)

    assert_equal [["player1", 100.0], ["player2", 200.0]], result
  end

  def test_to_h_returns_hash
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(player1: 100, player2: 200, player3: 150)

    result = sorted_set.to_h

    assert_equal({player1: 100.0, player2: 200.0, player3: 150.0}, result)
  end

  def test_to_h_empty_sorted_set
    sorted_set = redis.sorted_set(@key)

    result = sorted_set.to_h

    assert_equal({}, result)
  end

  # ============================================================
  # Expiration Tests
  # ============================================================

  def test_expire_sets_ttl
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(:player1, 100)

    result = sorted_set.expire(60)

    assert_same sorted_set, result
    ttl = sorted_set.ttl
    assert_operator ttl, :>, 0
    assert_operator ttl, :<=, 60
  end

  def test_expire_at_with_time_object
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(:player1, 100)

    future_time = Time.now + 60
    result = sorted_set.expire_at(future_time)

    assert_same sorted_set, result
    ttl = sorted_set.ttl
    assert_operator ttl, :>, 0
    assert_operator ttl, :<=, 60
  end

  def test_ttl_returns_seconds_until_expiration
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(:player1, 100)
    sorted_set.expire(120)

    ttl = sorted_set.ttl

    assert_operator ttl, :>, 0
    assert_operator ttl, :<=, 120
  end

  def test_ttl_returns_minus_one_for_no_expiration
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(:player1, 100)

    ttl = sorted_set.ttl

    assert_equal(-1, ttl)
  end

  def test_persist_removes_expiration
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(:player1, 100)
    sorted_set.expire(60)

    result = sorted_set.persist

    assert_same sorted_set, result
    assert_equal(-1, sorted_set.ttl)
  end

  # ============================================================
  # Random Tests
  # ============================================================

  def test_random_returns_single_member
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(player1: 100, player2: 200)

    result = sorted_set.random

    assert_includes ["player1", "player2"], result
  end

  def test_random_with_count
    sorted_set = redis.sorted_set(@key)
    sorted_set.add(player1: 100, player2: 200, player3: 150)

    result = sorted_set.random(2)

    assert_equal 2, result.size
  end

  # ============================================================
  # Integration Tests
  # ============================================================

  def test_gaming_leaderboard_workflow
    leaderboard = redis.sorted_set(:game, :leaderboard)
      .add(alice: 1500, bob: 2000, charlie: 1800, diana: 2200)
      .increment(:alice, 100)
      .expire(3600)

    # Check top players
    top_3 = leaderboard.top(3)
    assert_equal ["diana", "bob", "charlie"], top_3

    # Check Alice's rank (0-based from highest)
    rank = leaderboard.reverse_rank(:alice)
    assert_equal 3, rank  # 4th place

    # Check score
    assert_equal 1600.0, leaderboard.score(:alice)

    # Check TTL
    assert_operator leaderboard.ttl, :>, 0

    # Cleanup
    redis.del("game:leaderboard")
  end

  def test_priority_queue_workflow
    queue = redis.sorted_set(:tasks, :priority)
    queue.add(urgent: 1, normal: 5, low: 10)

    # Get highest priority (lowest score)
    task = queue.pop_min
    assert_equal "urgent", task

    # Verify removed
    assert_equal 2, queue.count
    refute queue.member?(:urgent)

    # Cleanup
    redis.del("tasks:priority")
  end

  def test_time_based_ranking_workflow
    recent = redis.sorted_set(:posts, :recent)

    now = Time.now.to_i
    recent.add(
      "post:123" => now,
      "post:124" => now - 3600,
      "post:125" => now - 7200
    )

    # Get most recent
    latest = recent.top(2)
    assert_equal ["post:123", "post:124"], latest

    # Remove old posts
    cutoff = now - 5000
    recent.remove_by_score(-Float::INFINITY, cutoff)

    assert_equal 2, recent.count

    # Cleanup
    redis.del("posts:recent")
  end

  def test_chainable_operations
    sorted_set = redis.sorted_set(@key)
      .add(player1: 100)
      .add(player2: 200)
      .increment(:player1, 50)
      .decrement(:player2, 25)
      .expire(3600)

    assert_equal 150.0, sorted_set.score(:player1)
    assert_equal 175.0, sorted_set.score(:player2)
    assert_operator sorted_set.ttl, :>, 0
  end
end

