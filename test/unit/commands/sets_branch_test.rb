# frozen_string_literal: true

require_relative "../unit_test_helper"

class SetsBranchTest < Minitest::Test
  # ============================================================
  # MockClient includes the Sets module and records commands
  # ============================================================

  class MockClient
    include RR::Commands::Sets

    attr_reader :last_command

    def call(*args)
      @last_command = args
      mock_return(args)
    end

    def call_1arg(cmd, arg_one)
      @last_command = [cmd, arg_one]
      mock_return([cmd, arg_one])
    end

    def call_2args(cmd, arg_one, arg_two)
      @last_command = [cmd, arg_one, arg_two]
      mock_return([cmd, arg_one, arg_two])
    end

    def call_3args(cmd, arg_one, arg_two, arg_three)
      @last_command = [cmd, arg_one, arg_two, arg_three]
      1
    end

    SIMPLE_RETURNS = {
      "SADD" => 1, "SREM" => 1, "SISMEMBER" => 1,
      "SMISMEMBER" => [1, 0, 1], "SMEMBERS" => %w[a b c], "SCARD" => 3,
      "SINTER" => %w[a b], "SUNION" => %w[a b], "SDIFF" => %w[a b],
      "SINTERSTORE" => 2, "SUNIONSTORE" => 2, "SDIFFSTORE" => 2, "SINTERCARD" => 2,
      "SSCAN" => ["0", %w[a b c]],
    }.freeze

    private

    def mock_return(args)
      return SIMPLE_RETURNS[args[0]] if SIMPLE_RETURNS.key?(args[0])
      return args.length > 2 ? %w[a b] : "a" if %w[SPOP SRANDMEMBER].include?(args[0])

      "OK"
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

    assert_equal %w[SADD myset member1], @client.last_command
    assert_equal 1, result
  end

  def test_sadd_multiple_members
    result = @client.sadd("myset", "m1", "m2", "m3")

    assert_equal %w[SADD myset m1 m2 m3], @client.last_command
    assert_equal 1, result
  end

  # ============================================================
  # srem branches
  # ============================================================

  def test_srem_single_member_fast_path
    result = @client.srem("myset", "member1")

    assert_equal %w[SREM myset member1], @client.last_command
    assert_equal 1, result
  end

  def test_srem_multiple_members
    result = @client.srem("myset", "m1", "m2")

    assert_equal %w[SREM myset m1 m2], @client.last_command
    assert_equal 1, result
  end

  # ============================================================
  # sismember
  # ============================================================

  def test_sismember
    result = @client.sismember("myset", "member")

    assert_equal %w[SISMEMBER myset member], @client.last_command
    assert_equal 1, result
  end

  # ============================================================
  # smismember
  # ============================================================

  def test_smismember
    result = @client.smismember("myset", "m1", "m2", "m3")

    assert_equal %w[SMISMEMBER myset m1 m2 m3], @client.last_command
    assert_equal [1, 0, 1], result
  end

  # ============================================================
  # smembers
  # ============================================================

  def test_smembers
    result = @client.smembers("myset")

    assert_equal %w[SMEMBERS myset], @client.last_command
    assert_equal %w[a b c], result
  end

  # ============================================================
  # scard
  # ============================================================

  def test_scard
    result = @client.scard("myset")

    assert_equal %w[SCARD myset], @client.last_command
    assert_equal 3, result
  end

  # ============================================================
  # spop branches
  # ============================================================

  def test_spop_without_count
    result = @client.spop("myset")

    assert_equal %w[SPOP myset], @client.last_command
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

    assert_equal %w[SRANDMEMBER myset], @client.last_command
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

    assert_equal %w[SMOVE source dest member], @client.last_command
    assert_equal 1, result
  end

  # ============================================================
  # sinter
  # ============================================================

  def test_sinter
    result = @client.sinter("set1", "set2")

    assert_equal %w[SINTER set1 set2], @client.last_command
    assert_equal %w[a b], result
  end

  def test_sinter_single_key
    result = @client.sinter("set1")

    assert_equal %w[SINTER set1], @client.last_command
    assert_equal %w[a b], result
  end

  # ============================================================
  # sinterstore
  # ============================================================

  def test_sinterstore
    result = @client.sinterstore("dest", "set1", "set2")

    assert_equal %w[SINTERSTORE dest set1 set2], @client.last_command
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

    assert_equal %w[SUNION set1 set2], @client.last_command
    assert_equal %w[a b], result
  end

  # ============================================================
  # sunionstore
  # ============================================================

  def test_sunionstore
    result = @client.sunionstore("dest", "set1", "set2")

    assert_equal %w[SUNIONSTORE dest set1 set2], @client.last_command
    assert_equal 2, result
  end

  # ============================================================
  # sdiff
  # ============================================================

  def test_sdiff
    result = @client.sdiff("set1", "set2")

    assert_equal %w[SDIFF set1 set2], @client.last_command
    assert_equal %w[a b], result
  end

  # ============================================================
  # sdiffstore
  # ============================================================

  def test_sdiffstore
    result = @client.sdiffstore("dest", "set1", "set2")

    assert_equal %w[SDIFFSTORE dest set1 set2], @client.last_command
    assert_equal 2, result
  end

  # ============================================================
  # sscan branches
  # ============================================================

  def test_sscan_no_options_fast_path
    result = @client.sscan("myset", "0")

    assert_equal %w[SSCAN myset 0], @client.last_command
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
    assert_equal %w[SSCAN myset 0], @client.last_command
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
    include RR::Commands::Sets

    attr_accessor :call_count

    def initialize
      @call_count = 0
    end

    def call(*_args)
      @call_count += 1
      if @call_count == 1
        ["42", %w[a b]]
      else
        ["0", %w[c d]]
      end
    end

    def call_1arg(cmd, arg_one) = call(cmd, arg_one)
    def call_2args(cmd, arg_one, arg_two) = call(cmd, arg_one, arg_two)
    def call_3args(cmd, arg_one, arg_two, arg_three) = call(cmd, arg_one, arg_two, arg_three)
  end
end
