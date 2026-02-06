# frozen_string_literal: true

require_relative "../unit_test_helper"

class SetsBranchTest < Minitest::Test
  # ============================================================
  # MockClient includes the Sets module and records commands
  # ============================================================

  class MockClient
    include RedisRuby::Commands::Sets
    attr_reader :last_command

    def call(*args)
      @last_command = args
      mock_return(args)
    end

    def call_1arg(cmd, a1)
      @last_command = [cmd, a1]
      mock_return([cmd, a1])
    end

    def call_2args(cmd, a1, a2)
      @last_command = [cmd, a1, a2]
      mock_return([cmd, a1, a2])
    end

    def call_3args(cmd, a1, a2, a3)
      @last_command = [cmd, a1, a2, a3]
      1
    end

    private

    def mock_return(args)
      case args[0]
      when "SADD" then 1
      when "SREM" then 1
      when "SISMEMBER" then 1
      when "SMISMEMBER" then [1, 0, 1]
      when "SMEMBERS" then %w[a b c]
      when "SCARD" then 3
      when "SPOP" then args.length > 2 ? %w[a b] : "a"
      when "SRANDMEMBER" then args.length > 2 ? %w[a b] : "a"
      when "SINTER", "SUNION", "SDIFF" then %w[a b]
      when "SINTERSTORE", "SUNIONSTORE", "SDIFFSTORE" then 2
      when "SINTERCARD" then 2
      when "SSCAN" then ["0", %w[a b c]]
      else "OK"
      end
    end
  end

  def setup
    @client = MockClient.new
  end

  # ============================================================
  # sadd branches
  # ============================================================

  def test_sadd_single_member_fast_path
    result = @client.sadd("myset", "member1")
    assert_equal ["SADD", "myset", "member1"], @client.last_command
    assert_equal 1, result
  end

  def test_sadd_multiple_members
    result = @client.sadd("myset", "m1", "m2", "m3")
    assert_equal ["SADD", "myset", "m1", "m2", "m3"], @client.last_command
    assert_equal 1, result
  end

  # ============================================================
  # srem branches
  # ============================================================

  def test_srem_single_member_fast_path
    result = @client.srem("myset", "member1")
    assert_equal ["SREM", "myset", "member1"], @client.last_command
    assert_equal 1, result
  end

  def test_srem_multiple_members
    result = @client.srem("myset", "m1", "m2")
    assert_equal ["SREM", "myset", "m1", "m2"], @client.last_command
    assert_equal 1, result
  end

  # ============================================================
  # sismember
  # ============================================================

  def test_sismember
    result = @client.sismember("myset", "member")
    assert_equal ["SISMEMBER", "myset", "member"], @client.last_command
    assert_equal 1, result
  end

  # ============================================================
  # smismember
  # ============================================================

  def test_smismember
    result = @client.smismember("myset", "m1", "m2", "m3")
    assert_equal ["SMISMEMBER", "myset", "m1", "m2", "m3"], @client.last_command
    assert_equal [1, 0, 1], result
  end

  # ============================================================
  # smembers
  # ============================================================

  def test_smembers
    result = @client.smembers("myset")
    assert_equal ["SMEMBERS", "myset"], @client.last_command
    assert_equal %w[a b c], result
  end

  # ============================================================
  # scard
  # ============================================================

  def test_scard
    result = @client.scard("myset")
    assert_equal ["SCARD", "myset"], @client.last_command
    assert_equal 3, result
  end

  # ============================================================
  # spop branches
  # ============================================================

  def test_spop_without_count
    result = @client.spop("myset")
    assert_equal ["SPOP", "myset"], @client.last_command
    assert_equal "a", result
  end

  def test_spop_with_count
    result = @client.spop("myset", 2)
    assert_equal ["SPOP", "myset", 2], @client.last_command
    assert_equal %w[a b], result
  end

  # ============================================================
  # srandmember branches
  # ============================================================

  def test_srandmember_without_count
    result = @client.srandmember("myset")
    assert_equal ["SRANDMEMBER", "myset"], @client.last_command
    assert_equal "a", result
  end

  def test_srandmember_with_count
    result = @client.srandmember("myset", 2)
    assert_equal ["SRANDMEMBER", "myset", 2], @client.last_command
    assert_equal %w[a b], result
  end

  # ============================================================
  # smove
  # ============================================================

  def test_smove
    result = @client.smove("source", "dest", "member")
    assert_equal ["SMOVE", "source", "dest", "member"], @client.last_command
    assert_equal 1, result
  end

  # ============================================================
  # sinter
  # ============================================================

  def test_sinter
    result = @client.sinter("set1", "set2")
    assert_equal ["SINTER", "set1", "set2"], @client.last_command
    assert_equal %w[a b], result
  end

  def test_sinter_single_key
    result = @client.sinter("set1")
    assert_equal ["SINTER", "set1"], @client.last_command
    assert_equal %w[a b], result
  end

  # ============================================================
  # sinterstore
  # ============================================================

  def test_sinterstore
    result = @client.sinterstore("dest", "set1", "set2")
    assert_equal ["SINTERSTORE", "dest", "set1", "set2"], @client.last_command
    assert_equal 2, result
  end

  # ============================================================
  # sintercard branches
  # ============================================================

  def test_sintercard_without_limit
    result = @client.sintercard("set1", "set2")
    assert_equal ["SINTERCARD", 2, "set1", "set2"], @client.last_command
    assert_equal 2, result
  end

  def test_sintercard_with_limit
    result = @client.sintercard("set1", "set2", limit: 5)
    assert_equal ["SINTERCARD", 2, "set1", "set2", "LIMIT", 5], @client.last_command
    assert_equal 2, result
  end

  def test_sintercard_single_key
    @client.sintercard("set1")
    assert_equal ["SINTERCARD", 1, "set1"], @client.last_command
  end

  # ============================================================
  # sunion
  # ============================================================

  def test_sunion
    result = @client.sunion("set1", "set2")
    assert_equal ["SUNION", "set1", "set2"], @client.last_command
    assert_equal %w[a b], result
  end

  # ============================================================
  # sunionstore
  # ============================================================

  def test_sunionstore
    result = @client.sunionstore("dest", "set1", "set2")
    assert_equal ["SUNIONSTORE", "dest", "set1", "set2"], @client.last_command
    assert_equal 2, result
  end

  # ============================================================
  # sdiff
  # ============================================================

  def test_sdiff
    result = @client.sdiff("set1", "set2")
    assert_equal ["SDIFF", "set1", "set2"], @client.last_command
    assert_equal %w[a b], result
  end

  # ============================================================
  # sdiffstore
  # ============================================================

  def test_sdiffstore
    result = @client.sdiffstore("dest", "set1", "set2")
    assert_equal ["SDIFFSTORE", "dest", "set1", "set2"], @client.last_command
    assert_equal 2, result
  end

  # ============================================================
  # sscan branches
  # ============================================================

  def test_sscan_no_options_fast_path
    result = @client.sscan("myset", "0")
    assert_equal ["SSCAN", "myset", "0"], @client.last_command
    assert_equal ["0", %w[a b c]], result
  end

  def test_sscan_with_match
    result = @client.sscan("myset", "0", match: "user:*")
    assert_equal ["SSCAN", "myset", "0", "MATCH", "user:*"], @client.last_command
    assert_equal ["0", %w[a b c]], result
  end

  def test_sscan_with_count
    result = @client.sscan("myset", "0", count: 100)
    assert_equal ["SSCAN", "myset", "0", "COUNT", 100], @client.last_command
    assert_equal ["0", %w[a b c]], result
  end

  def test_sscan_with_match_and_count
    result = @client.sscan("myset", "0", match: "foo*", count: 50)
    assert_equal ["SSCAN", "myset", "0", "MATCH", "foo*", "COUNT", 50], @client.last_command
    assert_equal ["0", %w[a b c]], result
  end

  def test_sscan_with_nil_match_nil_count
    @client.sscan("myset", "0", match: nil, count: nil)
    # Both nil -> fast path
    assert_equal ["SSCAN", "myset", "0"], @client.last_command
  end

  def test_sscan_with_match_only_no_count
    @client.sscan("myset", "0", match: "prefix:*", count: nil)
    assert_equal ["SSCAN", "myset", "0", "MATCH", "prefix:*"], @client.last_command
  end

  def test_sscan_with_count_only_no_match
    @client.sscan("myset", "0", match: nil, count: 200)
    assert_equal ["SSCAN", "myset", "0", "COUNT", 200], @client.last_command
  end

  # ============================================================
  # sscan_iter
  # ============================================================

  def test_sscan_iter_returns_enumerator
    result = @client.sscan_iter("myset")
    assert_instance_of Enumerator, result
  end

  def test_sscan_iter_yields_members
    # The mock always returns cursor "0" so the loop ends after one iteration
    members = @client.sscan_iter("myset").to_a
    assert_equal %w[a b c], members
  end

  def test_sscan_iter_custom_match_and_count
    members = @client.sscan_iter("myset", match: "user:*", count: 5).to_a
    assert_equal %w[a b c], members
  end

  def test_sscan_iter_multiple_iterations
    client = MultiIterMock.new
    members = client.sscan_iter("myset").to_a
    assert_equal %w[a b c d], members
  end

  class MultiIterMock
    include RedisRuby::Commands::Sets
    attr_accessor :call_count

    def initialize
      @call_count = 0
    end

    def call(*args)
      @call_count += 1
      if @call_count == 1
        ["42", %w[a b]]
      else
        ["0", %w[c d]]
      end
    end

    def call_1arg(cmd, a1) = call(cmd, a1)
    def call_2args(cmd, a1, a2) = call(cmd, a1, a2)
    def call_3args(cmd, a1, a2, a3) = call(cmd, a1, a2, a3)
  end
end
