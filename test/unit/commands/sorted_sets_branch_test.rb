# frozen_string_literal: true

require_relative "../unit_test_helper"

class SortedSetsBranchTest < Minitest::Test
  class MockClient
    include RR::Commands::SortedSets

    attr_reader :last_command

    UNSET = Object.new

    def initialize
      @mock_override = UNSET
    end

    def call(*args)
      @last_command = args
      mock_return_value(args)
    end

    def call_1arg(cmd, arg_one)
      @last_command = [cmd, arg_one]
      mock_return_value(@last_command)
    end

    def call_2args(cmd, arg_one, arg_two)
      @last_command = [cmd, arg_one, arg_two]
      mock_return_value(@last_command)
    end

    def call_3args(cmd, arg_one, arg_two, arg_three)
      @last_command = [cmd, arg_one, arg_two, arg_three]
      mock_return_value(@last_command)
    end

    attr_writer :mock_override

    def clear_mock_override
      @mock_override = UNSET
    end

    SIMPLE_RETURNS = {
      "ZSCORE" => "1.5", "ZINCRBY" => "1.5",
      "ZMSCORE" => ["1.0", "2.0"],
      "ZPOPMIN" => ["member1", "1.0"], "ZPOPMAX" => ["member1", "1.0"],
      "BZPOPMIN" => ["key", "member", "1.0"], "BZPOPMAX" => ["key", "member", "1.0"],
      "ZSCAN" => ["0", ["member1", "1.0", "member2", "2.0"]],
      "ZMPOP" => ["key", [["m1", "1.0"], ["m2", "2.0"]]],
      "BZMPOP" => ["key", [["m1", "1.0"], ["m2", "2.0"]]],
    }.freeze

    WITHSCORES_CMDS = %w[ZRANGE ZREVRANGE ZRANGEBYSCORE ZREVRANGEBYSCORE ZUNION ZINTER ZDIFF].freeze

    private

    def mock_return_value(args)
      return @mock_override unless @mock_override.equal?(UNSET)
      return SIMPLE_RETURNS[args[0]] if SIMPLE_RETURNS.key?(args[0])
      return withscores_return(args) if WITHSCORES_CMDS.include?(args[0])
      return zrandmember_return(args) if args[0] == "ZRANDMEMBER"
      return rank_return(args) if %w[ZRANK ZREVRANK].include?(args[0])

      "OK"
    end

    def withscores_return(args)
      args.include?("WITHSCORES") ? ["member1", "1.0", "member2", "2.0"] : %w[member1 member2]
    end

    def zrandmember_return(args)
      return ["member1", "1.0", "member2", "2.0"] if args.include?("WITHSCORES")

      args.length > 2 ? %w[member1 member2] : "member1"
    end

    def rank_return(args)
      args.include?("WITHSCORE") ? [2, "1.5"] : 2
    end
  end

  def setup
    @client = MockClient.new
  end

  # ============================================================
  # parse_score tests
  # ============================================================

  def test_parse_score_nil
    assert_nil @client.parse_score(nil)
  end

  def test_parse_score_float_passthrough
    result = @client.parse_score(3.14)

    assert_instance_of Float, result
    assert_in_delta 3.14, result, 0.001
  end

  def test_parse_score_inf
    assert_equal Float::INFINITY, @client.parse_score("inf")
  end

  def test_parse_score_plus_inf
    assert_equal Float::INFINITY, @client.parse_score("+inf")
  end

  def test_parse_score_minus_inf
    assert_equal(-Float::INFINITY, @client.parse_score("-inf"))
  end

  def test_parse_score_numeric_string
    assert_in_delta 42.5, @client.parse_score("42.5"), 0.001
  end

  def test_parse_score_integer
    assert_in_delta 100.0, @client.parse_score(100), 0.001
  end

  def test_parse_score_zero_string
    assert_in_delta 0.0, @client.parse_score("0"), 0.001
  end

  def test_parse_score_negative_string
    assert_in_delta(-7.5, @client.parse_score("-7.5"), 0.001)
  end
end

class SortedSetsBranchTestPart2 < Minitest::Test
  class MockClient
    include RR::Commands::SortedSets

    attr_reader :last_command

    UNSET = Object.new

    def initialize
      @mock_override = UNSET
    end

    def call(*args)
      @last_command = args
      mock_return_value(args)
    end

    def call_1arg(cmd, arg_one)
      @last_command = [cmd, arg_one]
      mock_return_value(@last_command)
    end

    def call_2args(cmd, arg_one, arg_two)
      @last_command = [cmd, arg_one, arg_two]
      mock_return_value(@last_command)
    end

    def call_3args(cmd, arg_one, arg_two, arg_three)
      @last_command = [cmd, arg_one, arg_two, arg_three]
      mock_return_value(@last_command)
    end

    attr_writer :mock_override

    def clear_mock_override
      @mock_override = UNSET
    end

    SIMPLE_RETURNS = {
      "ZSCORE" => "1.5", "ZINCRBY" => "1.5",
      "ZMSCORE" => ["1.0", "2.0"],
      "ZPOPMIN" => ["member1", "1.0"], "ZPOPMAX" => ["member1", "1.0"],
      "BZPOPMIN" => ["key", "member", "1.0"], "BZPOPMAX" => ["key", "member", "1.0"],
      "ZSCAN" => ["0", ["member1", "1.0", "member2", "2.0"]],
      "ZMPOP" => ["key", [["m1", "1.0"], ["m2", "2.0"]]],
      "BZMPOP" => ["key", [["m1", "1.0"], ["m2", "2.0"]]],
    }.freeze

    WITHSCORES_CMDS = %w[ZRANGE ZREVRANGE ZRANGEBYSCORE ZREVRANGEBYSCORE ZUNION ZINTER ZDIFF].freeze

    private

    def mock_return_value(args)
      return @mock_override unless @mock_override.equal?(UNSET)
      return SIMPLE_RETURNS[args[0]] if SIMPLE_RETURNS.key?(args[0])
      return withscores_return(args) if WITHSCORES_CMDS.include?(args[0])
      return zrandmember_return(args) if args[0] == "ZRANDMEMBER"
      return rank_return(args) if %w[ZRANK ZREVRANK].include?(args[0])

      "OK"
    end

    def withscores_return(args)
      args.include?("WITHSCORES") ? ["member1", "1.0", "member2", "2.0"] : %w[member1 member2]
    end

    def zrandmember_return(args)
      return ["member1", "1.0", "member2", "2.0"] if args.include?("WITHSCORES")

      args.length > 2 ? %w[member1 member2] : "member1"
    end

    def rank_return(args)
      args.include?("WITHSCORE") ? [2, "1.5"] : 2
    end
  end

  def setup
    @client = MockClient.new
  end

  # ============================================================
  # parse_score tests
  # ============================================================

  # ============================================================
  # zadd tests - all flag combinations
  # ============================================================

  def test_zadd_basic
    @client.zadd("myset", 1.0, "member1")

    assert_equal ["ZADD", "myset", 1.0, "member1"], @client.last_command
  end

  def test_zadd_with_nx
    @client.zadd("myset", 1.0, "member1", nx: true)

    assert_equal ["ZADD", "myset", "NX", 1.0, "member1"], @client.last_command
  end

  def test_zadd_without_nx
    @client.zadd("myset", 1.0, "member1", nx: false)

    assert_equal ["ZADD", "myset", 1.0, "member1"], @client.last_command
  end

  def test_zadd_with_xx
    @client.zadd("myset", 1.0, "member1", xx: true)

    assert_equal ["ZADD", "myset", "XX", 1.0, "member1"], @client.last_command
  end

  def test_zadd_without_xx
    @client.zadd("myset", 1.0, "member1", xx: false)

    assert_equal ["ZADD", "myset", 1.0, "member1"], @client.last_command
  end

  def test_zadd_with_gt
    @client.zadd("myset", 1.0, "member1", gt: true)

    assert_equal ["ZADD", "myset", "GT", 1.0, "member1"], @client.last_command
  end

  def test_zadd_without_gt
    @client.zadd("myset", 1.0, "member1", gt: false)

    assert_equal ["ZADD", "myset", 1.0, "member1"], @client.last_command
  end

  def test_zadd_with_lt
    @client.zadd("myset", 1.0, "member1", lt: true)

    assert_equal ["ZADD", "myset", "LT", 1.0, "member1"], @client.last_command
  end

  def test_zadd_without_lt
    @client.zadd("myset", 1.0, "member1", lt: false)

    assert_equal ["ZADD", "myset", 1.0, "member1"], @client.last_command
  end

  def test_zadd_with_ch
    @client.zadd("myset", 1.0, "member1", ch: true)

    assert_equal ["ZADD", "myset", "CH", 1.0, "member1"], @client.last_command
  end

  def test_zadd_without_ch
    @client.zadd("myset", 1.0, "member1", ch: false)

    assert_equal ["ZADD", "myset", 1.0, "member1"], @client.last_command
  end

  def test_zadd_with_incr
    @client.zadd("myset", 1.0, "member1", incr: true)

    assert_equal ["ZADD", "myset", "INCR", 1.0, "member1"], @client.last_command
  end

  def test_zadd_without_incr
    @client.zadd("myset", 1.0, "member1", incr: false)

    assert_equal ["ZADD", "myset", 1.0, "member1"], @client.last_command
  end

  def test_zadd_all_flags_combined
    @client.zadd("myset", 1.0, "member1", nx: true, xx: true, gt: true, lt: true, ch: true, incr: true)

    assert_equal ["ZADD", "myset", "NX", "XX", "GT", "LT", "CH", "INCR", 1.0, "member1"], @client.last_command
  end

  def test_zadd_multiple_members
    @client.zadd("myset", 1.0, "m1", 2.0, "m2")

    assert_equal ["ZADD", "myset", 1.0, "m1", 2.0, "m2"], @client.last_command
  end

  def test_zadd_no_flags
    @client.zadd("myset", 5.0, "member")

    refute_includes @client.last_command, "NX"
    refute_includes @client.last_command, "XX"
    refute_includes @client.last_command, "GT"
    refute_includes @client.last_command, "LT"
    refute_includes @client.last_command, "CH"
    refute_includes @client.last_command, "INCR"
  end
end

class SortedSetsBranchTestPart3 < Minitest::Test
  class MockClient
    include RR::Commands::SortedSets

    attr_reader :last_command

    UNSET = Object.new

    def initialize
      @mock_override = UNSET
    end

    def call(*args)
      @last_command = args
      mock_return_value(args)
    end

    def call_1arg(cmd, arg_one)
      @last_command = [cmd, arg_one]
      mock_return_value(@last_command)
    end

    def call_2args(cmd, arg_one, arg_two)
      @last_command = [cmd, arg_one, arg_two]
      mock_return_value(@last_command)
    end

    def call_3args(cmd, arg_one, arg_two, arg_three)
      @last_command = [cmd, arg_one, arg_two, arg_three]
      mock_return_value(@last_command)
    end

    attr_writer :mock_override

    def clear_mock_override
      @mock_override = UNSET
    end

    SIMPLE_RETURNS = {
      "ZSCORE" => "1.5", "ZINCRBY" => "1.5",
      "ZMSCORE" => ["1.0", "2.0"],
      "ZPOPMIN" => ["member1", "1.0"], "ZPOPMAX" => ["member1", "1.0"],
      "BZPOPMIN" => ["key", "member", "1.0"], "BZPOPMAX" => ["key", "member", "1.0"],
      "ZSCAN" => ["0", ["member1", "1.0", "member2", "2.0"]],
      "ZMPOP" => ["key", [["m1", "1.0"], ["m2", "2.0"]]],
      "BZMPOP" => ["key", [["m1", "1.0"], ["m2", "2.0"]]],
    }.freeze

    WITHSCORES_CMDS = %w[ZRANGE ZREVRANGE ZRANGEBYSCORE ZREVRANGEBYSCORE ZUNION ZINTER ZDIFF].freeze

    private

    def mock_return_value(args)
      return @mock_override unless @mock_override.equal?(UNSET)
      return SIMPLE_RETURNS[args[0]] if SIMPLE_RETURNS.key?(args[0])
      return withscores_return(args) if WITHSCORES_CMDS.include?(args[0])
      return zrandmember_return(args) if args[0] == "ZRANDMEMBER"
      return rank_return(args) if %w[ZRANK ZREVRANK].include?(args[0])

      "OK"
    end

    def withscores_return(args)
      args.include?("WITHSCORES") ? ["member1", "1.0", "member2", "2.0"] : %w[member1 member2]
    end

    def zrandmember_return(args)
      return ["member1", "1.0", "member2", "2.0"] if args.include?("WITHSCORES")

      args.length > 2 ? %w[member1 member2] : "member1"
    end

    def rank_return(args)
      args.include?("WITHSCORE") ? [2, "1.5"] : 2
    end
  end

  def setup
    @client = MockClient.new
  end

  # ============================================================
  # parse_score tests
  # ============================================================

  # ============================================================
  # zrem tests - single vs multiple members
  # ============================================================

  def test_zrem_single_member_fast_path
    @client.zrem("myset", "member1")

    assert_equal %w[ZREM myset member1], @client.last_command
  end

  def test_zrem_multiple_members
    @client.zrem("myset", "m1", "m2", "m3")

    assert_equal %w[ZREM myset m1 m2 m3], @client.last_command
  end
  # ============================================================
  # zscore tests
  # ============================================================

  def test_zscore_returns_parsed_float
    result = @client.zscore("myset", "member1")

    assert_equal %w[ZSCORE myset member1], @client.last_command
    assert_in_delta 1.5, result, 0.001
  end
  # ============================================================
  # zmscore tests
  # ============================================================

  def test_zmscore_returns_parsed_floats
    result = @client.zmscore("myset", "m1", "m2")

    assert_equal %w[ZMSCORE myset m1 m2], @client.last_command
    assert_in_delta 1.0, result[0], 0.001
    assert_in_delta 2.0, result[1], 0.001
  end
  # ============================================================
  # zrank tests - with and without withscore
  # ============================================================

  def test_zrank_without_withscore
    result = @client.zrank("myset", "member1")

    assert_equal %w[ZRANK myset member1], @client.last_command
    assert_equal 2, result
  end

  def test_zrank_with_withscore
    result = @client.zrank("myset", "member1", withscore: true)

    assert_equal %w[ZRANK myset member1 WITHSCORE], @client.last_command
    assert_equal [2, "1.5"], result
  end

  def test_zrank_with_withscore_false
    @client.zrank("myset", "member1", withscore: false)

    assert_equal %w[ZRANK myset member1], @client.last_command
  end
  # ============================================================
  # zrevrank tests - with and without withscore
  # ============================================================

  def test_zrevrank_without_withscore
    result = @client.zrevrank("myset", "member1")

    assert_equal %w[ZREVRANK myset member1], @client.last_command
    assert_equal 2, result
  end

  def test_zrevrank_with_withscore
    result = @client.zrevrank("myset", "member1", withscore: true)

    assert_equal %w[ZREVRANK myset member1 WITHSCORE], @client.last_command
    assert_equal [2, "1.5"], result
  end

  def test_zrevrank_with_withscore_false
    @client.zrevrank("myset", "member1", withscore: false)

    assert_equal %w[ZREVRANK myset member1], @client.last_command
  end
  # ============================================================
  # zcard tests
  # ============================================================

  def test_zcard
    @client.zcard("myset")

    assert_equal %w[ZCARD myset], @client.last_command
  end
  # ============================================================
  # zcount tests
  # ============================================================

  def test_zcount
    @client.zcount("myset", "-inf", "+inf")

    assert_equal ["ZCOUNT", "myset", "-inf", "+inf"], @client.last_command
  end
end

class SortedSetsBranchTestPart4 < Minitest::Test
  class MockClient
    include RR::Commands::SortedSets

    attr_reader :last_command

    UNSET = Object.new

    def initialize
      @mock_override = UNSET
    end

    def call(*args)
      @last_command = args
      mock_return_value(args)
    end

    def call_1arg(cmd, arg_one)
      @last_command = [cmd, arg_one]
      mock_return_value(@last_command)
    end

    def call_2args(cmd, arg_one, arg_two)
      @last_command = [cmd, arg_one, arg_two]
      mock_return_value(@last_command)
    end

    def call_3args(cmd, arg_one, arg_two, arg_three)
      @last_command = [cmd, arg_one, arg_two, arg_three]
      mock_return_value(@last_command)
    end

    attr_writer :mock_override

    def clear_mock_override
      @mock_override = UNSET
    end

    SIMPLE_RETURNS = {
      "ZSCORE" => "1.5", "ZINCRBY" => "1.5",
      "ZMSCORE" => ["1.0", "2.0"],
      "ZPOPMIN" => ["member1", "1.0"], "ZPOPMAX" => ["member1", "1.0"],
      "BZPOPMIN" => ["key", "member", "1.0"], "BZPOPMAX" => ["key", "member", "1.0"],
      "ZSCAN" => ["0", ["member1", "1.0", "member2", "2.0"]],
      "ZMPOP" => ["key", [["m1", "1.0"], ["m2", "2.0"]]],
      "BZMPOP" => ["key", [["m1", "1.0"], ["m2", "2.0"]]],
    }.freeze

    WITHSCORES_CMDS = %w[ZRANGE ZREVRANGE ZRANGEBYSCORE ZREVRANGEBYSCORE ZUNION ZINTER ZDIFF].freeze

    private

    def mock_return_value(args)
      return @mock_override unless @mock_override.equal?(UNSET)
      return SIMPLE_RETURNS[args[0]] if SIMPLE_RETURNS.key?(args[0])
      return withscores_return(args) if WITHSCORES_CMDS.include?(args[0])
      return zrandmember_return(args) if args[0] == "ZRANDMEMBER"
      return rank_return(args) if %w[ZRANK ZREVRANK].include?(args[0])

      "OK"
    end

    def withscores_return(args)
      args.include?("WITHSCORES") ? ["member1", "1.0", "member2", "2.0"] : %w[member1 member2]
    end

    def zrandmember_return(args)
      return ["member1", "1.0", "member2", "2.0"] if args.include?("WITHSCORES")

      args.length > 2 ? %w[member1 member2] : "member1"
    end

    def rank_return(args)
      args.include?("WITHSCORE") ? [2, "1.5"] : 2
    end
  end

  def setup
    @client = MockClient.new
  end

  # ============================================================
  # parse_score tests
  # ============================================================

  # ============================================================
  # zrange tests - all branches
  # ============================================================

  def test_zrange_fast_path_no_options
    @client.zrange("myset", 0, -1)

    assert_equal ["ZRANGE", "myset", 0, -1], @client.last_command
  end

  def test_zrange_with_byscore
    @client.zrange("myset", 0, 100, byscore: true)

    assert_equal ["ZRANGE", "myset", 0, 100, "BYSCORE"], @client.last_command
  end

  def test_zrange_with_bylex
    @client.zrange("myset", "[a", "[z", bylex: true)

    assert_equal ["ZRANGE", "myset", "[a", "[z", "BYLEX"], @client.last_command
  end

  def test_zrange_with_rev
    @client.zrange("myset", 0, -1, rev: true)

    assert_equal ["ZRANGE", "myset", 0, -1, "REV"], @client.last_command
  end

  def test_zrange_with_limit_and_byscore
    @client.zrange("myset", 0, 100, byscore: true, limit: [0, 10])

    assert_equal ["ZRANGE", "myset", 0, 100, "BYSCORE", "LIMIT", 0, 10], @client.last_command
  end

  def test_zrange_with_limit_and_bylex
    @client.zrange("myset", "[a", "[z", bylex: true, limit: [5, 10])

    assert_equal ["ZRANGE", "myset", "[a", "[z", "BYLEX", "LIMIT", 5, 10], @client.last_command
  end

  def test_zrange_with_limit_without_byscore_or_bylex_does_not_add_limit
    @client.zrange("myset", 0, -1, limit: [0, 10])

    refute_includes @client.last_command, "LIMIT"
  end

  def test_zrange_with_withscores
    result = @client.zrange("myset", 0, -1, withscores: true)

    assert_includes @client.last_command, "WITHSCORES"
    assert_equal [["member1", 1.0], ["member2", 2.0]], result
  end

  def test_zrange_without_withscores_returns_raw_result
    result = @client.zrange("myset", 0, -1, byscore: true)

    refute_includes @client.last_command, "WITHSCORES"
    assert_equal %w[member1 member2], result
  end

  def test_zrange_with_all_options
    result = @client.zrange("myset", 0, 100, byscore: true, rev: true, limit: [0, 5], withscores: true)

    assert_equal "ZRANGE", @client.last_command[0]
    assert_includes @client.last_command, "BYSCORE"
    assert_includes @client.last_command, "REV"
    assert_includes @client.last_command, "LIMIT"
    assert_includes @client.last_command, "WITHSCORES"
    assert_equal [["member1", 1.0], ["member2", 2.0]], result
  end
end

class SortedSetsBranchTestPart5 < Minitest::Test
  class MockClient
    include RR::Commands::SortedSets

    attr_reader :last_command

    UNSET = Object.new

    def initialize
      @mock_override = UNSET
    end

    def call(*args)
      @last_command = args
      mock_return_value(args)
    end

    def call_1arg(cmd, arg_one)
      @last_command = [cmd, arg_one]
      mock_return_value(@last_command)
    end

    def call_2args(cmd, arg_one, arg_two)
      @last_command = [cmd, arg_one, arg_two]
      mock_return_value(@last_command)
    end

    def call_3args(cmd, arg_one, arg_two, arg_three)
      @last_command = [cmd, arg_one, arg_two, arg_three]
      mock_return_value(@last_command)
    end

    attr_writer :mock_override

    def clear_mock_override
      @mock_override = UNSET
    end

    SIMPLE_RETURNS = {
      "ZSCORE" => "1.5", "ZINCRBY" => "1.5",
      "ZMSCORE" => ["1.0", "2.0"],
      "ZPOPMIN" => ["member1", "1.0"], "ZPOPMAX" => ["member1", "1.0"],
      "BZPOPMIN" => ["key", "member", "1.0"], "BZPOPMAX" => ["key", "member", "1.0"],
      "ZSCAN" => ["0", ["member1", "1.0", "member2", "2.0"]],
      "ZMPOP" => ["key", [["m1", "1.0"], ["m2", "2.0"]]],
      "BZMPOP" => ["key", [["m1", "1.0"], ["m2", "2.0"]]],
    }.freeze

    WITHSCORES_CMDS = %w[ZRANGE ZREVRANGE ZRANGEBYSCORE ZREVRANGEBYSCORE ZUNION ZINTER ZDIFF].freeze

    private

    def mock_return_value(args)
      return @mock_override unless @mock_override.equal?(UNSET)
      return SIMPLE_RETURNS[args[0]] if SIMPLE_RETURNS.key?(args[0])
      return withscores_return(args) if WITHSCORES_CMDS.include?(args[0])
      return zrandmember_return(args) if args[0] == "ZRANDMEMBER"
      return rank_return(args) if %w[ZRANK ZREVRANK].include?(args[0])

      "OK"
    end

    def withscores_return(args)
      args.include?("WITHSCORES") ? ["member1", "1.0", "member2", "2.0"] : %w[member1 member2]
    end

    def zrandmember_return(args)
      return ["member1", "1.0", "member2", "2.0"] if args.include?("WITHSCORES")

      args.length > 2 ? %w[member1 member2] : "member1"
    end

    def rank_return(args)
      args.include?("WITHSCORE") ? [2, "1.5"] : 2
    end
  end

  def setup
    @client = MockClient.new
  end

  # ============================================================
  # parse_score tests
  # ============================================================

  # ============================================================
  # zrangestore tests
  # ============================================================

  def test_zrangestore_basic
    @client.zrangestore("dest", "src", 0, -1)

    assert_equal ["ZRANGESTORE", "dest", "src", 0, -1], @client.last_command
  end

  def test_zrangestore_with_byscore
    @client.zrangestore("dest", "src", 0, 100, byscore: true)

    assert_includes @client.last_command, "BYSCORE"
  end

  def test_zrangestore_with_bylex
    @client.zrangestore("dest", "src", "[a", "[z", bylex: true)

    assert_includes @client.last_command, "BYLEX"
  end

  def test_zrangestore_with_rev
    @client.zrangestore("dest", "src", 0, -1, rev: true)

    assert_includes @client.last_command, "REV"
  end

  def test_zrangestore_with_limit_and_byscore
    @client.zrangestore("dest", "src", 0, 100, byscore: true, limit: [0, 10])

    assert_includes @client.last_command, "LIMIT"
  end

  def test_zrangestore_with_limit_and_bylex
    @client.zrangestore("dest", "src", "[a", "[z", bylex: true, limit: [5, 10])

    assert_includes @client.last_command, "LIMIT"
  end

  def test_zrangestore_with_limit_without_byscore_or_bylex_does_not_add_limit
    @client.zrangestore("dest", "src", 0, -1, limit: [0, 10])

    refute_includes @client.last_command, "LIMIT"
  end

  def test_zrangestore_all_options
    @client.zrangestore("dest", "src", 0, 100, byscore: true, rev: true, limit: [0, 5])

    assert_includes @client.last_command, "BYSCORE"
    assert_includes @client.last_command, "REV"
    assert_includes @client.last_command, "LIMIT"
  end
  # ============================================================
  # zrevrange tests
  # ============================================================

  def test_zrevrange_fast_path_no_withscores
    @client.zrevrange("myset", 0, -1)

    assert_equal ["ZREVRANGE", "myset", 0, -1], @client.last_command
  end

  def test_zrevrange_with_withscores
    result = @client.zrevrange("myset", 0, -1, withscores: true)

    assert_includes @client.last_command, "WITHSCORES"
    assert_equal [["member1", 1.0], ["member2", 2.0]], result
  end
end

class SortedSetsBranchTestPart6 < Minitest::Test
  class MockClient
    include RR::Commands::SortedSets

    attr_reader :last_command

    UNSET = Object.new

    def initialize
      @mock_override = UNSET
    end

    def call(*args)
      @last_command = args
      mock_return_value(args)
    end

    def call_1arg(cmd, arg_one)
      @last_command = [cmd, arg_one]
      mock_return_value(@last_command)
    end

    def call_2args(cmd, arg_one, arg_two)
      @last_command = [cmd, arg_one, arg_two]
      mock_return_value(@last_command)
    end

    def call_3args(cmd, arg_one, arg_two, arg_three)
      @last_command = [cmd, arg_one, arg_two, arg_three]
      mock_return_value(@last_command)
    end

    attr_writer :mock_override

    def clear_mock_override
      @mock_override = UNSET
    end

    SIMPLE_RETURNS = {
      "ZSCORE" => "1.5", "ZINCRBY" => "1.5",
      "ZMSCORE" => ["1.0", "2.0"],
      "ZPOPMIN" => ["member1", "1.0"], "ZPOPMAX" => ["member1", "1.0"],
      "BZPOPMIN" => ["key", "member", "1.0"], "BZPOPMAX" => ["key", "member", "1.0"],
      "ZSCAN" => ["0", ["member1", "1.0", "member2", "2.0"]],
      "ZMPOP" => ["key", [["m1", "1.0"], ["m2", "2.0"]]],
      "BZMPOP" => ["key", [["m1", "1.0"], ["m2", "2.0"]]],
    }.freeze

    WITHSCORES_CMDS = %w[ZRANGE ZREVRANGE ZRANGEBYSCORE ZREVRANGEBYSCORE ZUNION ZINTER ZDIFF].freeze

    private

    def mock_return_value(args)
      return @mock_override unless @mock_override.equal?(UNSET)
      return SIMPLE_RETURNS[args[0]] if SIMPLE_RETURNS.key?(args[0])
      return withscores_return(args) if WITHSCORES_CMDS.include?(args[0])
      return zrandmember_return(args) if args[0] == "ZRANDMEMBER"
      return rank_return(args) if %w[ZRANK ZREVRANK].include?(args[0])

      "OK"
    end

    def withscores_return(args)
      args.include?("WITHSCORES") ? ["member1", "1.0", "member2", "2.0"] : %w[member1 member2]
    end

    def zrandmember_return(args)
      return ["member1", "1.0", "member2", "2.0"] if args.include?("WITHSCORES")

      args.length > 2 ? %w[member1 member2] : "member1"
    end

    def rank_return(args)
      args.include?("WITHSCORE") ? [2, "1.5"] : 2
    end
  end

  def setup
    @client = MockClient.new
  end

  # ============================================================
  # parse_score tests
  # ============================================================

  # ============================================================
  # zrangebyscore tests
  # ============================================================

  def test_zrangebyscore_fast_path_no_options
    @client.zrangebyscore("myset", "-inf", "+inf")

    assert_equal ["ZRANGEBYSCORE", "myset", "-inf", "+inf"], @client.last_command
  end

  def test_zrangebyscore_with_withscores
    result = @client.zrangebyscore("myset", 0, 100, withscores: true)

    assert_includes @client.last_command, "WITHSCORES"
    assert_equal [["member1", 1.0], ["member2", 2.0]], result
  end

  def test_zrangebyscore_with_limit
    @client.zrangebyscore("myset", 0, 100, limit: [0, 10])

    assert_includes @client.last_command, "LIMIT"
  end

  def test_zrangebyscore_with_limit_and_withscores
    result = @client.zrangebyscore("myset", 0, 100, withscores: true, limit: [0, 10])

    assert_includes @client.last_command, "WITHSCORES"
    assert_includes @client.last_command, "LIMIT"
    assert_equal [["member1", 1.0], ["member2", 2.0]], result
  end

  def test_zrangebyscore_without_withscores_returns_raw_result
    result = @client.zrangebyscore("myset", 0, 100, limit: [0, 10])

    refute_includes @client.last_command, "WITHSCORES"
    assert_equal %w[member1 member2], result
  end
  # ============================================================
  # zrevrangebyscore tests
  # ============================================================

  def test_zrevrangebyscore_fast_path_no_options
    @client.zrevrangebyscore("myset", "+inf", "-inf")

    assert_equal ["ZREVRANGEBYSCORE", "myset", "+inf", "-inf"], @client.last_command
  end

  def test_zrevrangebyscore_with_withscores
    result = @client.zrevrangebyscore("myset", 100, 0, withscores: true)

    assert_includes @client.last_command, "WITHSCORES"
    assert_equal [["member1", 1.0], ["member2", 2.0]], result
  end

  def test_zrevrangebyscore_with_limit
    @client.zrevrangebyscore("myset", 100, 0, limit: [0, 10])

    assert_includes @client.last_command, "LIMIT"
  end

  def test_zrevrangebyscore_with_limit_and_withscores
    result = @client.zrevrangebyscore("myset", 100, 0, withscores: true, limit: [0, 10])

    assert_includes @client.last_command, "WITHSCORES"
    assert_includes @client.last_command, "LIMIT"
    assert_equal [["member1", 1.0], ["member2", 2.0]], result
  end

  def test_zrevrangebyscore_without_withscores_returns_raw_result
    result = @client.zrevrangebyscore("myset", 100, 0, limit: [0, 10])

    refute_includes @client.last_command, "WITHSCORES"
    assert_equal %w[member1 member2], result
  end
  # ============================================================
  # zincrby tests
  # ============================================================

  def test_zincrby
    result = @client.zincrby("myset", 2.5, "member1")

    assert_equal ["ZINCRBY", "myset", 2.5, "member1"], @client.last_command
    assert_in_delta 1.5, result, 0.001
  end
  # ============================================================
  # zremrangebyrank tests
  # ============================================================

  def test_zremrangebyrank
    @client.zremrangebyrank("myset", 0, 5)

    assert_equal ["ZREMRANGEBYRANK", "myset", 0, 5], @client.last_command
  end
  # ============================================================
  # zremrangebyscore tests
  # ============================================================

  def test_zremrangebyscore
    @client.zremrangebyscore("myset", "-inf", "+inf")

    assert_equal ["ZREMRANGEBYSCORE", "myset", "-inf", "+inf"], @client.last_command
  end
end

class SortedSetsBranchTestPart7 < Minitest::Test
  class MockClient
    include RR::Commands::SortedSets

    attr_reader :last_command

    UNSET = Object.new

    def initialize
      @mock_override = UNSET
    end

    def call(*args)
      @last_command = args
      mock_return_value(args)
    end

    def call_1arg(cmd, arg_one)
      @last_command = [cmd, arg_one]
      mock_return_value(@last_command)
    end

    def call_2args(cmd, arg_one, arg_two)
      @last_command = [cmd, arg_one, arg_two]
      mock_return_value(@last_command)
    end

    def call_3args(cmd, arg_one, arg_two, arg_three)
      @last_command = [cmd, arg_one, arg_two, arg_three]
      mock_return_value(@last_command)
    end

    attr_writer :mock_override

    def clear_mock_override
      @mock_override = UNSET
    end

    SIMPLE_RETURNS = {
      "ZSCORE" => "1.5", "ZINCRBY" => "1.5",
      "ZMSCORE" => ["1.0", "2.0"],
      "ZPOPMIN" => ["member1", "1.0"], "ZPOPMAX" => ["member1", "1.0"],
      "BZPOPMIN" => ["key", "member", "1.0"], "BZPOPMAX" => ["key", "member", "1.0"],
      "ZSCAN" => ["0", ["member1", "1.0", "member2", "2.0"]],
      "ZMPOP" => ["key", [["m1", "1.0"], ["m2", "2.0"]]],
      "BZMPOP" => ["key", [["m1", "1.0"], ["m2", "2.0"]]],
    }.freeze

    WITHSCORES_CMDS = %w[ZRANGE ZREVRANGE ZRANGEBYSCORE ZREVRANGEBYSCORE ZUNION ZINTER ZDIFF].freeze

    private

    def mock_return_value(args)
      return @mock_override unless @mock_override.equal?(UNSET)
      return SIMPLE_RETURNS[args[0]] if SIMPLE_RETURNS.key?(args[0])
      return withscores_return(args) if WITHSCORES_CMDS.include?(args[0])
      return zrandmember_return(args) if args[0] == "ZRANDMEMBER"
      return rank_return(args) if %w[ZRANK ZREVRANK].include?(args[0])

      "OK"
    end

    def withscores_return(args)
      args.include?("WITHSCORES") ? ["member1", "1.0", "member2", "2.0"] : %w[member1 member2]
    end

    def zrandmember_return(args)
      return ["member1", "1.0", "member2", "2.0"] if args.include?("WITHSCORES")

      args.length > 2 ? %w[member1 member2] : "member1"
    end

    def rank_return(args)
      args.include?("WITHSCORE") ? [2, "1.5"] : 2
    end
  end

  def setup
    @client = MockClient.new
  end

  # ============================================================
  # parse_score tests
  # ============================================================

  # ============================================================
  # zpopmin tests
  # ============================================================

  def test_zpopmin_without_count
    result = @client.zpopmin("myset")

    assert_equal %w[ZPOPMIN myset], @client.last_command
    assert_equal ["member1", 1.0], result
  end

  def test_zpopmin_with_count
    result = @client.zpopmin("myset", 2)

    assert_equal ["ZPOPMIN", "myset", 2], @client.last_command
    assert_equal [["member1", 1.0]], result
  end

  def test_zpopmin_nil_result
    @client.mock_override = nil
    result = @client.zpopmin("myset")

    assert_nil result
    @client.clear_mock_override
  end

  def test_zpopmin_empty_result
    @client.mock_override = []
    result = @client.zpopmin("myset")

    assert_nil result
    @client.clear_mock_override
  end
  # ============================================================
  # zpopmax tests
  # ============================================================

  def test_zpopmax_without_count
    result = @client.zpopmax("myset")

    assert_equal %w[ZPOPMAX myset], @client.last_command
    assert_equal ["member1", 1.0], result
  end

  def test_zpopmax_with_count
    result = @client.zpopmax("myset", 3)

    assert_equal ["ZPOPMAX", "myset", 3], @client.last_command
    assert_equal [["member1", 1.0]], result
  end

  def test_zpopmax_nil_result
    @client.mock_override = nil
    result = @client.zpopmax("myset")

    assert_nil result
    @client.clear_mock_override
  end

  def test_zpopmax_empty_result
    @client.mock_override = []
    result = @client.zpopmax("myset")

    assert_nil result
    @client.clear_mock_override
  end
  # ============================================================
  # bzpopmin tests
  # ============================================================

  def test_bzpopmin_with_result
    result = @client.bzpopmin("key1", "key2", timeout: 5)

    assert_equal ["BZPOPMIN", "key1", "key2", 5], @client.last_command
    assert_equal ["key", "member", 1.0], result
  end

  def test_bzpopmin_nil_result
    @client.mock_override = nil
    result = @client.bzpopmin("key1", timeout: 1)

    assert_nil result
    @client.clear_mock_override
  end

  def test_bzpopmin_default_timeout
    @client.bzpopmin("key1")

    assert_equal ["BZPOPMIN", "key1", 0], @client.last_command
  end
end

class SortedSetsBranchTestPart8 < Minitest::Test
  class MockClient
    include RR::Commands::SortedSets

    attr_reader :last_command

    UNSET = Object.new

    def initialize
      @mock_override = UNSET
    end

    def call(*args)
      @last_command = args
      mock_return_value(args)
    end

    def call_1arg(cmd, arg_one)
      @last_command = [cmd, arg_one]
      mock_return_value(@last_command)
    end

    def call_2args(cmd, arg_one, arg_two)
      @last_command = [cmd, arg_one, arg_two]
      mock_return_value(@last_command)
    end

    def call_3args(cmd, arg_one, arg_two, arg_three)
      @last_command = [cmd, arg_one, arg_two, arg_three]
      mock_return_value(@last_command)
    end

    attr_writer :mock_override

    def clear_mock_override
      @mock_override = UNSET
    end

    SIMPLE_RETURNS = {
      "ZSCORE" => "1.5", "ZINCRBY" => "1.5",
      "ZMSCORE" => ["1.0", "2.0"],
      "ZPOPMIN" => ["member1", "1.0"], "ZPOPMAX" => ["member1", "1.0"],
      "BZPOPMIN" => ["key", "member", "1.0"], "BZPOPMAX" => ["key", "member", "1.0"],
      "ZSCAN" => ["0", ["member1", "1.0", "member2", "2.0"]],
      "ZMPOP" => ["key", [["m1", "1.0"], ["m2", "2.0"]]],
      "BZMPOP" => ["key", [["m1", "1.0"], ["m2", "2.0"]]],
    }.freeze

    WITHSCORES_CMDS = %w[ZRANGE ZREVRANGE ZRANGEBYSCORE ZREVRANGEBYSCORE ZUNION ZINTER ZDIFF].freeze

    private

    def mock_return_value(args)
      return @mock_override unless @mock_override.equal?(UNSET)
      return SIMPLE_RETURNS[args[0]] if SIMPLE_RETURNS.key?(args[0])
      return withscores_return(args) if WITHSCORES_CMDS.include?(args[0])
      return zrandmember_return(args) if args[0] == "ZRANDMEMBER"
      return rank_return(args) if %w[ZRANK ZREVRANK].include?(args[0])

      "OK"
    end

    def withscores_return(args)
      args.include?("WITHSCORES") ? ["member1", "1.0", "member2", "2.0"] : %w[member1 member2]
    end

    def zrandmember_return(args)
      return ["member1", "1.0", "member2", "2.0"] if args.include?("WITHSCORES")

      args.length > 2 ? %w[member1 member2] : "member1"
    end

    def rank_return(args)
      args.include?("WITHSCORE") ? [2, "1.5"] : 2
    end
  end

  def setup
    @client = MockClient.new
  end

  # ============================================================
  # parse_score tests
  # ============================================================

  # ============================================================
  # bzpopmax tests
  # ============================================================

  def test_bzpopmax_with_result
    result = @client.bzpopmax("key1", "key2", timeout: 5)

    assert_equal ["BZPOPMAX", "key1", "key2", 5], @client.last_command
    assert_equal ["key", "member", 1.0], result
  end

  def test_bzpopmax_nil_result
    @client.mock_override = nil
    result = @client.bzpopmax("key1", timeout: 1)

    assert_nil result
    @client.clear_mock_override
  end

  def test_bzpopmax_default_timeout
    @client.bzpopmax("key1")

    assert_equal ["BZPOPMAX", "key1", 0], @client.last_command
  end
  # ============================================================
  # zscan tests
  # ============================================================

  def test_zscan_fast_path_no_match_no_count
    cursor, members = @client.zscan("myset", "0")

    assert_equal %w[ZSCAN myset 0], @client.last_command
    assert_equal "0", cursor
    assert_equal [["member1", 1.0], ["member2", 2.0]], members
  end

  def test_zscan_with_match
    cursor, members = @client.zscan("myset", "0", match: "mem*")

    assert_equal ["ZSCAN", "myset", "0", "MATCH", "mem*"], @client.last_command
    assert_equal "0", cursor
    assert_equal [["member1", 1.0], ["member2", 2.0]], members
  end

  def test_zscan_with_count
    cursor, members = @client.zscan("myset", "0", count: 100)

    assert_equal ["ZSCAN", "myset", "0", "COUNT", 100], @client.last_command
    assert_equal "0", cursor
    assert_equal [["member1", 1.0], ["member2", 2.0]], members
  end

  def test_zscan_with_match_and_count
    cursor, members = @client.zscan("myset", "0", match: "prefix:*", count: 50)

    assert_equal ["ZSCAN", "myset", "0", "MATCH", "prefix:*", "COUNT", 50], @client.last_command
    assert_equal "0", cursor
    assert_equal [["member1", 1.0], ["member2", 2.0]], members
  end
  # ============================================================
  # zscan_iter tests
  # ============================================================

  def test_zscan_iter_basic_iteration
    enumerator = @client.zscan_iter("myset")

    assert_instance_of Enumerator, enumerator

    # The mock returns cursor "0" immediately, so only one iteration
    results = enumerator.to_a

    assert_equal [["member1", 1.0], ["member2", 2.0]], results
  end

  def test_zscan_iter_with_match_and_count
    enumerator = @client.zscan_iter("myset", match: "player:*", count: 20)

    assert_instance_of Enumerator, enumerator

    results = enumerator.to_a

    assert_equal [["member1", 1.0], ["member2", 2.0]], results
  end
end

class SortedSetsBranchTestPart9 < Minitest::Test
  class MockClient
    include RR::Commands::SortedSets

    attr_reader :last_command

    UNSET = Object.new

    def initialize
      @mock_override = UNSET
    end

    def call(*args)
      @last_command = args
      mock_return_value(args)
    end

    def call_1arg(cmd, arg_one)
      @last_command = [cmd, arg_one]
      mock_return_value(@last_command)
    end

    def call_2args(cmd, arg_one, arg_two)
      @last_command = [cmd, arg_one, arg_two]
      mock_return_value(@last_command)
    end

    def call_3args(cmd, arg_one, arg_two, arg_three)
      @last_command = [cmd, arg_one, arg_two, arg_three]
      mock_return_value(@last_command)
    end

    attr_writer :mock_override

    def clear_mock_override
      @mock_override = UNSET
    end

    SIMPLE_RETURNS = {
      "ZSCORE" => "1.5", "ZINCRBY" => "1.5",
      "ZMSCORE" => ["1.0", "2.0"],
      "ZPOPMIN" => ["member1", "1.0"], "ZPOPMAX" => ["member1", "1.0"],
      "BZPOPMIN" => ["key", "member", "1.0"], "BZPOPMAX" => ["key", "member", "1.0"],
      "ZSCAN" => ["0", ["member1", "1.0", "member2", "2.0"]],
      "ZMPOP" => ["key", [["m1", "1.0"], ["m2", "2.0"]]],
      "BZMPOP" => ["key", [["m1", "1.0"], ["m2", "2.0"]]],
    }.freeze

    WITHSCORES_CMDS = %w[ZRANGE ZREVRANGE ZRANGEBYSCORE ZREVRANGEBYSCORE ZUNION ZINTER ZDIFF].freeze

    private

    def mock_return_value(args)
      return @mock_override unless @mock_override.equal?(UNSET)
      return SIMPLE_RETURNS[args[0]] if SIMPLE_RETURNS.key?(args[0])
      return withscores_return(args) if WITHSCORES_CMDS.include?(args[0])
      return zrandmember_return(args) if args[0] == "ZRANDMEMBER"
      return rank_return(args) if %w[ZRANK ZREVRANK].include?(args[0])

      "OK"
    end

    def withscores_return(args)
      args.include?("WITHSCORES") ? ["member1", "1.0", "member2", "2.0"] : %w[member1 member2]
    end

    def zrandmember_return(args)
      return ["member1", "1.0", "member2", "2.0"] if args.include?("WITHSCORES")

      args.length > 2 ? %w[member1 member2] : "member1"
    end

    def rank_return(args)
      args.include?("WITHSCORE") ? [2, "1.5"] : 2
    end
  end

  def setup
    @client = MockClient.new
  end

  # ============================================================
  # parse_score tests
  # ============================================================

  # ============================================================
  # zinterstore tests
  # ============================================================

  def test_zinterstore_basic
    @client.zinterstore("dest", %w[key1 key2])

    assert_equal ["ZINTERSTORE", "dest", 2, "key1", "key2"], @client.last_command
  end

  def test_zinterstore_with_weights
    @client.zinterstore("dest", %w[key1 key2], weights: [1, 2])

    assert_equal ["ZINTERSTORE", "dest", 2, "key1", "key2", "WEIGHTS", 1, 2], @client.last_command
  end

  def test_zinterstore_with_aggregate
    @client.zinterstore("dest", %w[key1 key2], aggregate: :sum)

    assert_equal ["ZINTERSTORE", "dest", 2, "key1", "key2", "AGGREGATE", "SUM"], @client.last_command
  end

  def test_zinterstore_with_aggregate_min
    @client.zinterstore("dest", %w[key1 key2], aggregate: :min)

    assert_includes @client.last_command, "MIN"
  end

  def test_zinterstore_with_aggregate_max
    @client.zinterstore("dest", %w[key1 key2], aggregate: :max)

    assert_includes @client.last_command, "MAX"
  end

  def test_zinterstore_with_weights_and_aggregate
    @client.zinterstore("dest", %w[k1 k2], weights: [2, 3], aggregate: :max)

    assert_equal ["ZINTERSTORE", "dest", 2, "k1", "k2", "WEIGHTS", 2, 3, "AGGREGATE", "MAX"], @client.last_command
  end

  def test_zinterstore_without_weights_or_aggregate
    @client.zinterstore("dest", %w[key1 key2])

    refute_includes @client.last_command, "WEIGHTS"
    refute_includes @client.last_command, "AGGREGATE"
  end
  # ============================================================
  # zunionstore tests
  # ============================================================

  def test_zunionstore_basic
    @client.zunionstore("dest", %w[key1 key2])

    assert_equal ["ZUNIONSTORE", "dest", 2, "key1", "key2"], @client.last_command
  end

  def test_zunionstore_with_weights
    @client.zunionstore("dest", %w[key1 key2], weights: [1, 2])

    assert_equal ["ZUNIONSTORE", "dest", 2, "key1", "key2", "WEIGHTS", 1, 2], @client.last_command
  end

  def test_zunionstore_with_aggregate
    @client.zunionstore("dest", %w[key1 key2], aggregate: :sum)

    assert_equal ["ZUNIONSTORE", "dest", 2, "key1", "key2", "AGGREGATE", "SUM"], @client.last_command
  end

  def test_zunionstore_with_weights_and_aggregate
    @client.zunionstore("dest", %w[k1 k2], weights: [2, 3], aggregate: :min)

    assert_equal ["ZUNIONSTORE", "dest", 2, "k1", "k2", "WEIGHTS", 2, 3, "AGGREGATE", "MIN"], @client.last_command
  end

  def test_zunionstore_without_weights_or_aggregate
    @client.zunionstore("dest", ["key1"])

    refute_includes @client.last_command, "WEIGHTS"
    refute_includes @client.last_command, "AGGREGATE"
  end
end

class SortedSetsBranchTestPart10 < Minitest::Test
  class MockClient
    include RR::Commands::SortedSets

    attr_reader :last_command

    UNSET = Object.new

    def initialize
      @mock_override = UNSET
    end

    def call(*args)
      @last_command = args
      mock_return_value(args)
    end

    def call_1arg(cmd, arg_one)
      @last_command = [cmd, arg_one]
      mock_return_value(@last_command)
    end

    def call_2args(cmd, arg_one, arg_two)
      @last_command = [cmd, arg_one, arg_two]
      mock_return_value(@last_command)
    end

    def call_3args(cmd, arg_one, arg_two, arg_three)
      @last_command = [cmd, arg_one, arg_two, arg_three]
      mock_return_value(@last_command)
    end

    attr_writer :mock_override

    def clear_mock_override
      @mock_override = UNSET
    end

    SIMPLE_RETURNS = {
      "ZSCORE" => "1.5", "ZINCRBY" => "1.5",
      "ZMSCORE" => ["1.0", "2.0"],
      "ZPOPMIN" => ["member1", "1.0"], "ZPOPMAX" => ["member1", "1.0"],
      "BZPOPMIN" => ["key", "member", "1.0"], "BZPOPMAX" => ["key", "member", "1.0"],
      "ZSCAN" => ["0", ["member1", "1.0", "member2", "2.0"]],
      "ZMPOP" => ["key", [["m1", "1.0"], ["m2", "2.0"]]],
      "BZMPOP" => ["key", [["m1", "1.0"], ["m2", "2.0"]]],
    }.freeze

    WITHSCORES_CMDS = %w[ZRANGE ZREVRANGE ZRANGEBYSCORE ZREVRANGEBYSCORE ZUNION ZINTER ZDIFF].freeze

    private

    def mock_return_value(args)
      return @mock_override unless @mock_override.equal?(UNSET)
      return SIMPLE_RETURNS[args[0]] if SIMPLE_RETURNS.key?(args[0])
      return withscores_return(args) if WITHSCORES_CMDS.include?(args[0])
      return zrandmember_return(args) if args[0] == "ZRANDMEMBER"
      return rank_return(args) if %w[ZRANK ZREVRANK].include?(args[0])

      "OK"
    end

    def withscores_return(args)
      args.include?("WITHSCORES") ? ["member1", "1.0", "member2", "2.0"] : %w[member1 member2]
    end

    def zrandmember_return(args)
      return ["member1", "1.0", "member2", "2.0"] if args.include?("WITHSCORES")

      args.length > 2 ? %w[member1 member2] : "member1"
    end

    def rank_return(args)
      args.include?("WITHSCORE") ? [2, "1.5"] : 2
    end
  end

  def setup
    @client = MockClient.new
  end

  # ============================================================
  # parse_score tests
  # ============================================================

  # ============================================================
  # zunion tests
  # ============================================================

  def test_zunion_basic
    result = @client.zunion(%w[key1 key2])

    assert_equal ["ZUNION", 2, "key1", "key2"], @client.last_command
    assert_equal %w[member1 member2], result
  end

  def test_zunion_with_weights
    @client.zunion(%w[key1 key2], weights: [1, 2])

    assert_includes @client.last_command, "WEIGHTS"
  end

  def test_zunion_with_aggregate
    @client.zunion(%w[key1 key2], aggregate: :sum)

    assert_includes @client.last_command, "AGGREGATE"
    assert_includes @client.last_command, "SUM"
  end

  def test_zunion_with_withscores
    result = @client.zunion(%w[key1 key2], withscores: true)

    assert_includes @client.last_command, "WITHSCORES"
    assert_equal [["member1", 1.0], ["member2", 2.0]], result
  end

  def test_zunion_without_withscores_returns_raw
    result = @client.zunion(%w[key1 key2])

    refute_includes @client.last_command, "WITHSCORES"
    assert_equal %w[member1 member2], result
  end

  def test_zunion_all_options
    result = @client.zunion(%w[k1 k2], weights: [1, 2], aggregate: :max, withscores: true)

    assert_includes @client.last_command, "WEIGHTS"
    assert_includes @client.last_command, "AGGREGATE"
    assert_includes @client.last_command, "MAX"
    assert_includes @client.last_command, "WITHSCORES"
    assert_equal [["member1", 1.0], ["member2", 2.0]], result
  end
  # ============================================================
  # zinter tests
  # ============================================================

  def test_zinter_basic
    result = @client.zinter(%w[key1 key2])

    assert_equal ["ZINTER", 2, "key1", "key2"], @client.last_command
    assert_equal %w[member1 member2], result
  end

  def test_zinter_with_weights
    @client.zinter(%w[key1 key2], weights: [1, 2])

    assert_includes @client.last_command, "WEIGHTS"
  end

  def test_zinter_with_aggregate
    @client.zinter(%w[key1 key2], aggregate: :min)

    assert_includes @client.last_command, "AGGREGATE"
    assert_includes @client.last_command, "MIN"
  end

  def test_zinter_with_withscores
    result = @client.zinter(%w[key1 key2], withscores: true)

    assert_includes @client.last_command, "WITHSCORES"
    assert_equal [["member1", 1.0], ["member2", 2.0]], result
  end

  def test_zinter_without_withscores_returns_raw
    result = @client.zinter(%w[key1 key2])

    refute_includes @client.last_command, "WITHSCORES"
    assert_equal %w[member1 member2], result
  end

  def test_zinter_all_options
    result = @client.zinter(%w[k1 k2], weights: [3, 4], aggregate: :sum, withscores: true)

    assert_includes @client.last_command, "WEIGHTS"
    assert_includes @client.last_command, "AGGREGATE"
    assert_includes @client.last_command, "SUM"
    assert_includes @client.last_command, "WITHSCORES"
    assert_equal [["member1", 1.0], ["member2", 2.0]], result
  end
end

class SortedSetsBranchTestPart11 < Minitest::Test
  class MockClient
    include RR::Commands::SortedSets

    attr_reader :last_command

    UNSET = Object.new

    def initialize
      @mock_override = UNSET
    end

    def call(*args)
      @last_command = args
      mock_return_value(args)
    end

    def call_1arg(cmd, arg_one)
      @last_command = [cmd, arg_one]
      mock_return_value(@last_command)
    end

    def call_2args(cmd, arg_one, arg_two)
      @last_command = [cmd, arg_one, arg_two]
      mock_return_value(@last_command)
    end

    def call_3args(cmd, arg_one, arg_two, arg_three)
      @last_command = [cmd, arg_one, arg_two, arg_three]
      mock_return_value(@last_command)
    end

    attr_writer :mock_override

    def clear_mock_override
      @mock_override = UNSET
    end

    SIMPLE_RETURNS = {
      "ZSCORE" => "1.5", "ZINCRBY" => "1.5",
      "ZMSCORE" => ["1.0", "2.0"],
      "ZPOPMIN" => ["member1", "1.0"], "ZPOPMAX" => ["member1", "1.0"],
      "BZPOPMIN" => ["key", "member", "1.0"], "BZPOPMAX" => ["key", "member", "1.0"],
      "ZSCAN" => ["0", ["member1", "1.0", "member2", "2.0"]],
      "ZMPOP" => ["key", [["m1", "1.0"], ["m2", "2.0"]]],
      "BZMPOP" => ["key", [["m1", "1.0"], ["m2", "2.0"]]],
    }.freeze

    WITHSCORES_CMDS = %w[ZRANGE ZREVRANGE ZRANGEBYSCORE ZREVRANGEBYSCORE ZUNION ZINTER ZDIFF].freeze

    private

    def mock_return_value(args)
      return @mock_override unless @mock_override.equal?(UNSET)
      return SIMPLE_RETURNS[args[0]] if SIMPLE_RETURNS.key?(args[0])
      return withscores_return(args) if WITHSCORES_CMDS.include?(args[0])
      return zrandmember_return(args) if args[0] == "ZRANDMEMBER"
      return rank_return(args) if %w[ZRANK ZREVRANK].include?(args[0])

      "OK"
    end

    def withscores_return(args)
      args.include?("WITHSCORES") ? ["member1", "1.0", "member2", "2.0"] : %w[member1 member2]
    end

    def zrandmember_return(args)
      return ["member1", "1.0", "member2", "2.0"] if args.include?("WITHSCORES")

      args.length > 2 ? %w[member1 member2] : "member1"
    end

    def rank_return(args)
      args.include?("WITHSCORE") ? [2, "1.5"] : 2
    end
  end

  def setup
    @client = MockClient.new
  end

  # ============================================================
  # parse_score tests
  # ============================================================

  # ============================================================
  # zdiff tests
  # ============================================================

  def test_zdiff_without_withscores
    result = @client.zdiff(%w[key1 key2])

    assert_equal ["ZDIFF", 2, "key1", "key2"], @client.last_command
    assert_equal %w[member1 member2], result
  end

  def test_zdiff_with_withscores
    result = @client.zdiff(%w[key1 key2], withscores: true)

    assert_includes @client.last_command, "WITHSCORES"
    assert_equal [["member1", 1.0], ["member2", 2.0]], result
  end
  # ============================================================
  # zdiffstore tests
  # ============================================================

  def test_zdiffstore
    @client.zdiffstore("dest", %w[key1 key2 key3])

    assert_equal ["ZDIFFSTORE", "dest", 3, "key1", "key2", "key3"], @client.last_command
  end
  # ============================================================
  # zintercard tests
  # ============================================================

  def test_zintercard_without_limit
    @client.zintercard("key1", "key2")

    assert_equal ["ZINTERCARD", 2, "key1", "key2"], @client.last_command
  end

  def test_zintercard_with_limit
    @client.zintercard("key1", "key2", limit: 10)

    assert_equal ["ZINTERCARD", 2, "key1", "key2", "LIMIT", 10], @client.last_command
  end

  def test_zintercard_without_limit_does_not_include_limit
    @client.zintercard("key1", "key2")

    refute_includes @client.last_command, "LIMIT"
  end
  # ============================================================
  # zmpop tests
  # ============================================================

  def test_zmpop_basic
    result = @client.zmpop("key1", "key2")

    assert_equal ["ZMPOP", 2, "key1", "key2", "MIN"], @client.last_command
    assert_equal "key", result[0]
    assert_equal [["m1", 1.0], ["m2", 2.0]], result[1]
  end

  def test_zmpop_with_modifier_max
    @client.zmpop("key1", modifier: :max)

    assert_includes @client.last_command, "MAX"
  end

  def test_zmpop_with_modifier_min
    @client.zmpop("key1", modifier: :min)

    assert_includes @client.last_command, "MIN"
  end

  def test_zmpop_with_count
    @client.zmpop("key1", count: 5)

    assert_includes @client.last_command, "COUNT"
    assert_includes @client.last_command, 5
  end

  def test_zmpop_without_count
    @client.zmpop("key1")

    refute_includes @client.last_command, "COUNT"
  end

  def test_zmpop_nil_result
    @client.mock_override = nil
    result = @client.zmpop("key1")

    assert_nil result
    @client.clear_mock_override
  end
end

class SortedSetsBranchTestPart12 < Minitest::Test
  class MockClient
    include RR::Commands::SortedSets

    attr_reader :last_command

    UNSET = Object.new

    def initialize
      @mock_override = UNSET
    end

    def call(*args)
      @last_command = args
      mock_return_value(args)
    end

    def call_1arg(cmd, arg_one)
      @last_command = [cmd, arg_one]
      mock_return_value(@last_command)
    end

    def call_2args(cmd, arg_one, arg_two)
      @last_command = [cmd, arg_one, arg_two]
      mock_return_value(@last_command)
    end

    def call_3args(cmd, arg_one, arg_two, arg_three)
      @last_command = [cmd, arg_one, arg_two, arg_three]
      mock_return_value(@last_command)
    end

    attr_writer :mock_override

    def clear_mock_override
      @mock_override = UNSET
    end

    SIMPLE_RETURNS = {
      "ZSCORE" => "1.5", "ZINCRBY" => "1.5",
      "ZMSCORE" => ["1.0", "2.0"],
      "ZPOPMIN" => ["member1", "1.0"], "ZPOPMAX" => ["member1", "1.0"],
      "BZPOPMIN" => ["key", "member", "1.0"], "BZPOPMAX" => ["key", "member", "1.0"],
      "ZSCAN" => ["0", ["member1", "1.0", "member2", "2.0"]],
      "ZMPOP" => ["key", [["m1", "1.0"], ["m2", "2.0"]]],
      "BZMPOP" => ["key", [["m1", "1.0"], ["m2", "2.0"]]],
    }.freeze

    WITHSCORES_CMDS = %w[ZRANGE ZREVRANGE ZRANGEBYSCORE ZREVRANGEBYSCORE ZUNION ZINTER ZDIFF].freeze

    private

    def mock_return_value(args)
      return @mock_override unless @mock_override.equal?(UNSET)
      return SIMPLE_RETURNS[args[0]] if SIMPLE_RETURNS.key?(args[0])
      return withscores_return(args) if WITHSCORES_CMDS.include?(args[0])
      return zrandmember_return(args) if args[0] == "ZRANDMEMBER"
      return rank_return(args) if %w[ZRANK ZREVRANK].include?(args[0])

      "OK"
    end

    def withscores_return(args)
      args.include?("WITHSCORES") ? ["member1", "1.0", "member2", "2.0"] : %w[member1 member2]
    end

    def zrandmember_return(args)
      return ["member1", "1.0", "member2", "2.0"] if args.include?("WITHSCORES")

      args.length > 2 ? %w[member1 member2] : "member1"
    end

    def rank_return(args)
      args.include?("WITHSCORE") ? [2, "1.5"] : 2
    end
  end

  def setup
    @client = MockClient.new
  end

  # ============================================================
  # parse_score tests
  # ============================================================

  # ============================================================
  # bzmpop tests
  # ============================================================

  def test_bzmpop_basic
    result = @client.bzmpop(5, "key1", "key2")

    assert_equal ["BZMPOP", 5, 2, "key1", "key2", "MIN"], @client.last_command
    assert_equal "key", result[0]
    assert_equal [["m1", 1.0], ["m2", 2.0]], result[1]
  end

  def test_bzmpop_with_modifier_max
    @client.bzmpop(0, "key1", modifier: :max)

    assert_includes @client.last_command, "MAX"
  end

  def test_bzmpop_with_count
    @client.bzmpop(0, "key1", count: 3)

    assert_includes @client.last_command, "COUNT"
    assert_includes @client.last_command, 3
  end

  def test_bzmpop_without_count
    @client.bzmpop(0, "key1")

    refute_includes @client.last_command, "COUNT"
  end

  def test_bzmpop_nil_result
    @client.mock_override = nil
    result = @client.bzmpop(1, "key1")

    assert_nil result
    @client.clear_mock_override
  end
  # ============================================================
  # zlexcount tests
  # ============================================================

  def test_zlexcount
    @client.zlexcount("myset", "-", "+")

    assert_equal ["ZLEXCOUNT", "myset", "-", "+"], @client.last_command
  end
  # ============================================================
  # zrangebylex tests
  # ============================================================

  def test_zrangebylex_fast_path_no_limit
    @client.zrangebylex("myset", "[a", "[z")

    assert_equal ["ZRANGEBYLEX", "myset", "[a", "[z"], @client.last_command
  end

  def test_zrangebylex_with_limit
    @client.zrangebylex("myset", "[a", "[z", limit: [0, 10])

    assert_equal ["ZRANGEBYLEX", "myset", "[a", "[z", "LIMIT", 0, 10], @client.last_command
  end
  # ============================================================
  # zrevrangebylex tests
  # ============================================================

  def test_zrevrangebylex_fast_path_no_limit
    @client.zrevrangebylex("myset", "[z", "[a")

    assert_equal ["ZREVRANGEBYLEX", "myset", "[z", "[a"], @client.last_command
  end

  def test_zrevrangebylex_with_limit
    @client.zrevrangebylex("myset", "[z", "[a", limit: [0, 10])

    assert_equal ["ZREVRANGEBYLEX", "myset", "[z", "[a", "LIMIT", 0, 10], @client.last_command
  end
  # ============================================================
  # zremrangebylex tests
  # ============================================================

  def test_zremrangebylex
    @client.zremrangebylex("myset", "[a", "[z")

    assert_equal ["ZREMRANGEBYLEX", "myset", "[a", "[z"], @client.last_command
  end
end

class SortedSetsBranchTestPart13 < Minitest::Test
  class MockClient
    include RR::Commands::SortedSets

    attr_reader :last_command

    UNSET = Object.new

    def initialize
      @mock_override = UNSET
    end

    def call(*args)
      @last_command = args
      mock_return_value(args)
    end

    def call_1arg(cmd, arg_one)
      @last_command = [cmd, arg_one]
      mock_return_value(@last_command)
    end

    def call_2args(cmd, arg_one, arg_two)
      @last_command = [cmd, arg_one, arg_two]
      mock_return_value(@last_command)
    end

    def call_3args(cmd, arg_one, arg_two, arg_three)
      @last_command = [cmd, arg_one, arg_two, arg_three]
      mock_return_value(@last_command)
    end

    attr_writer :mock_override

    def clear_mock_override
      @mock_override = UNSET
    end

    SIMPLE_RETURNS = {
      "ZSCORE" => "1.5", "ZINCRBY" => "1.5",
      "ZMSCORE" => ["1.0", "2.0"],
      "ZPOPMIN" => ["member1", "1.0"], "ZPOPMAX" => ["member1", "1.0"],
      "BZPOPMIN" => ["key", "member", "1.0"], "BZPOPMAX" => ["key", "member", "1.0"],
      "ZSCAN" => ["0", ["member1", "1.0", "member2", "2.0"]],
      "ZMPOP" => ["key", [["m1", "1.0"], ["m2", "2.0"]]],
      "BZMPOP" => ["key", [["m1", "1.0"], ["m2", "2.0"]]],
    }.freeze

    WITHSCORES_CMDS = %w[ZRANGE ZREVRANGE ZRANGEBYSCORE ZREVRANGEBYSCORE ZUNION ZINTER ZDIFF].freeze

    private

    def mock_return_value(args)
      return @mock_override unless @mock_override.equal?(UNSET)
      return SIMPLE_RETURNS[args[0]] if SIMPLE_RETURNS.key?(args[0])
      return withscores_return(args) if WITHSCORES_CMDS.include?(args[0])
      return zrandmember_return(args) if args[0] == "ZRANDMEMBER"
      return rank_return(args) if %w[ZRANK ZREVRANK].include?(args[0])

      "OK"
    end

    def withscores_return(args)
      args.include?("WITHSCORES") ? ["member1", "1.0", "member2", "2.0"] : %w[member1 member2]
    end

    def zrandmember_return(args)
      return ["member1", "1.0", "member2", "2.0"] if args.include?("WITHSCORES")

      args.length > 2 ? %w[member1 member2] : "member1"
    end

    def rank_return(args)
      args.include?("WITHSCORE") ? [2, "1.5"] : 2
    end
  end

  def setup
    @client = MockClient.new
  end

  # ============================================================
  # parse_score tests
  # ============================================================

  # ============================================================
  # zrandmember tests - all fast paths
  # ============================================================

  def test_zrandmember_just_key
    result = @client.zrandmember("myset")

    assert_equal %w[ZRANDMEMBER myset], @client.last_command
    assert_equal "member1", result
  end

  def test_zrandmember_with_count_no_withscores
    result = @client.zrandmember("myset", 3)

    assert_equal ["ZRANDMEMBER", "myset", 3], @client.last_command
    assert_equal %w[member1 member2], result
  end

  def test_zrandmember_with_count_and_withscores
    result = @client.zrandmember("myset", 3, withscores: true)

    assert_includes @client.last_command, "WITHSCORES"
    assert_equal [["member1", 1.0], ["member2", 2.0]], result
  end

  def test_zrandmember_withscores_without_count_does_not_include_withscores
    # When withscores is true but count is nil, WITHSCORES is not added
    # because the code has: args.push(OPT_WITHSCORES) if withscores && count
    @client.zrandmember("myset", nil, withscores: true)

    refute_includes @client.last_command, "WITHSCORES"
  end

  def test_zrandmember_nil_count_no_withscores_uses_fast_path
    @client.zrandmember("myset")

    assert_equal %w[ZRANDMEMBER myset], @client.last_command
  end

  def test_zrandmember_count_no_withscores_uses_fast_path
    @client.zrandmember("myset", 5)

    assert_equal ["ZRANDMEMBER", "myset", 5], @client.last_command
  end

  def test_zrandmember_withscores_and_count_parses_scores
    result = @client.zrandmember("myset", 2, withscores: true)
    # Result is array of [member, score] pairs; scores should be parsed to Float
    scores = result.map { |pair| pair[1] }

    scores.each { |score| assert_instance_of Float, score }
  end

  def test_zrandmember_withscores_true_count_nil_returns_raw_result
    # withscores: true but count: nil -> withscores && count is false -> no WITHSCORES flag
    # Goes through the else branch and returns raw result
    result = @client.zrandmember("myset", nil, withscores: true)
    # Should return raw result since withscores && count is falsy
    assert_equal "member1", result
  end
end

class SortedSetsBranchTestPart14 < Minitest::Test
  class MockClient
    include RR::Commands::SortedSets

    attr_reader :last_command

    UNSET = Object.new

    def initialize
      @mock_override = UNSET
    end

    def call(*args)
      @last_command = args
      mock_return_value(args)
    end

    def call_1arg(cmd, arg_one)
      @last_command = [cmd, arg_one]
      mock_return_value(@last_command)
    end

    def call_2args(cmd, arg_one, arg_two)
      @last_command = [cmd, arg_one, arg_two]
      mock_return_value(@last_command)
    end

    def call_3args(cmd, arg_one, arg_two, arg_three)
      @last_command = [cmd, arg_one, arg_two, arg_three]
      mock_return_value(@last_command)
    end

    attr_writer :mock_override

    def clear_mock_override
      @mock_override = UNSET
    end

    SIMPLE_RETURNS = {
      "ZSCORE" => "1.5", "ZINCRBY" => "1.5",
      "ZMSCORE" => ["1.0", "2.0"],
      "ZPOPMIN" => ["member1", "1.0"], "ZPOPMAX" => ["member1", "1.0"],
      "BZPOPMIN" => ["key", "member", "1.0"], "BZPOPMAX" => ["key", "member", "1.0"],
      "ZSCAN" => ["0", ["member1", "1.0", "member2", "2.0"]],
      "ZMPOP" => ["key", [["m1", "1.0"], ["m2", "2.0"]]],
      "BZMPOP" => ["key", [["m1", "1.0"], ["m2", "2.0"]]],
    }.freeze

    WITHSCORES_CMDS = %w[ZRANGE ZREVRANGE ZRANGEBYSCORE ZREVRANGEBYSCORE ZUNION ZINTER ZDIFF].freeze

    private

    def mock_return_value(args)
      return @mock_override unless @mock_override.equal?(UNSET)
      return SIMPLE_RETURNS[args[0]] if SIMPLE_RETURNS.key?(args[0])
      return withscores_return(args) if WITHSCORES_CMDS.include?(args[0])
      return zrandmember_return(args) if args[0] == "ZRANDMEMBER"
      return rank_return(args) if %w[ZRANK ZREVRANK].include?(args[0])

      "OK"
    end

    def withscores_return(args)
      args.include?("WITHSCORES") ? ["member1", "1.0", "member2", "2.0"] : %w[member1 member2]
    end

    def zrandmember_return(args)
      return ["member1", "1.0", "member2", "2.0"] if args.include?("WITHSCORES")

      args.length > 2 ? %w[member1 member2] : "member1"
    end

    def rank_return(args)
      args.include?("WITHSCORE") ? [2, "1.5"] : 2
    end
  end

  def setup
    @client = MockClient.new
  end

  # ============================================================
  # parse_score tests
  # ============================================================

  # ============================================================
  # Additional edge case tests for thorough branch coverage
  # ============================================================

  def test_zpopmin_with_count_returns_array_of_pairs
    result = @client.zpopmin("myset", 1)

    assert_instance_of Array, result
    # With count, returns [[member, score], ...]
    assert_instance_of Array, result[0]
  end

  def test_zpopmin_without_count_returns_single_pair
    result = @client.zpopmin("myset")

    assert_instance_of Array, result
    # Without count, returns [member, score]
    assert_equal "member1", result[0]
    assert_in_delta 1.0, result[1], 0.001
  end

  def test_zpopmax_with_count_returns_array_of_pairs
    result = @client.zpopmax("myset", 1)

    assert_instance_of Array, result
    assert_instance_of Array, result[0]
  end

  def test_zpopmax_without_count_returns_single_pair
    result = @client.zpopmax("myset")

    assert_instance_of Array, result
    assert_equal "member1", result[0]
    assert_in_delta 1.0, result[1], 0.001
  end

  def test_bzpopmin_parses_score
    result = @client.bzpopmin("key1", timeout: 0)

    assert_in_delta 1.0, result[2], 0.001
  end

  def test_bzpopmax_parses_score
    result = @client.bzpopmax("key1", timeout: 0)

    assert_in_delta 1.0, result[2], 0.001
  end

  def test_zrange_fast_path_returns_without_processing
    # Fast path: no options at all - returns call_3args result directly
    @client.zrange("myset", 0, -1)
    # Should use the call_3args path (last_command has exactly 4 elements)
    assert_equal 4, @client.last_command.length
  end

  def test_zrange_byscore_false_bylex_false_rev_false_limit_nil_withscores_false_is_fast_path
    # Explicitly pass all false/nil defaults to verify fast path
    @client.zrange("myset", 0, -1, byscore: false, bylex: false, rev: false, limit: nil, withscores: false)

    assert_equal ["ZRANGE", "myset", 0, -1], @client.last_command
  end

  def test_zrangestore_with_limit_nil_does_not_add_limit
    @client.zrangestore("dest", "src", 0, -1, byscore: true, limit: nil)

    refute_includes @client.last_command, "LIMIT"
  end

  def test_zscan_match_nil_count_nil_uses_fast_path
    # Explicitly pass nil to verify fast path
    @client.zscan("myset", "0", match: nil, count: nil)

    assert_equal %w[ZSCAN myset 0], @client.last_command
  end

  def test_zscan_match_only
    @client.zscan("myset", "0", match: "test*")

    assert_includes @client.last_command, "MATCH"
    refute_includes @client.last_command, "COUNT"
  end

  def test_zscan_count_only
    @client.zscan("myset", "0", count: 200)

    refute_includes @client.last_command, "MATCH"
    assert_includes @client.last_command, "COUNT"
  end
end
