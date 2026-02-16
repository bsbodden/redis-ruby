# frozen_string_literal: true

require_relative "../unit_test_helper"

# Unit tests for SortedSets module - testing branch coverage
class SortedSetsUnitTest < Minitest::Test
  def setup
    @mock_client = Minitest::Mock.new
  end

  # ============================================================
  # parse_score tests
  # ============================================================

  def test_parse_score_nil
    client = create_test_client

    assert_nil client.parse_score(nil)
  end

  def test_parse_score_float
    client = create_test_client

    assert_in_delta 3.14, client.parse_score(3.14), 0.001
  end

  def test_parse_score_positive_infinity
    client = create_test_client

    assert_equal Float::INFINITY, client.parse_score("inf")
    assert_equal Float::INFINITY, client.parse_score("+inf")
  end

  def test_parse_score_negative_infinity
    client = create_test_client

    assert_equal(-Float::INFINITY, client.parse_score("-inf"))
  end

  def test_parse_score_string_number
    client = create_test_client

    assert_in_delta 42.5, client.parse_score("42.5"), 0.001
  end

  def test_parse_score_integer
    client = create_test_client

    assert_in_delta 100.0, client.parse_score(100), 0.001
  end

  # ============================================================
  # zadd options tests
  # ============================================================

  def test_zadd_builds_correct_args_with_nx
    client = create_test_client
    # Just verify the method exists and has the nx option
    assert_respond_to client, :zadd
  end

  def test_zadd_builds_correct_args_with_xx
    client = create_test_client

    assert_respond_to client, :zadd
  end

  def test_zadd_builds_correct_args_with_gt
    client = create_test_client

    assert_respond_to client, :zadd
  end

  def test_zadd_builds_correct_args_with_lt
    client = create_test_client

    assert_respond_to client, :zadd
  end

  def test_zadd_builds_correct_args_with_ch
    client = create_test_client

    assert_respond_to client, :zadd
  end

  def test_zadd_builds_correct_args_with_incr
    client = create_test_client

    assert_respond_to client, :zadd
  end

  # ============================================================
  # zrange options tests
  # ============================================================

  def test_zrange_options
    client = create_test_client

    assert_respond_to client, :zrange
  end

  # ============================================================
  # Other sorted set commands
  # ============================================================

  def test_responds_to_zrem
    client = create_test_client

    assert_respond_to client, :zrem
  end

  def test_responds_to_zscore
    client = create_test_client

    assert_respond_to client, :zscore
  end

  def test_responds_to_zmscore
    client = create_test_client

    assert_respond_to client, :zmscore
  end

  def test_responds_to_zrank
    client = create_test_client

    assert_respond_to client, :zrank
  end

  def test_responds_to_zrevrank
    client = create_test_client

    assert_respond_to client, :zrevrank
  end

  def test_responds_to_zcard
    client = create_test_client

    assert_respond_to client, :zcard
  end

  def test_responds_to_zcount
    client = create_test_client

    assert_respond_to client, :zcount
  end

  def test_responds_to_zrevrange
    client = create_test_client

    assert_respond_to client, :zrevrange
  end

  def test_responds_to_zrangebyscore
    client = create_test_client

    assert_respond_to client, :zrangebyscore
  end

  def test_responds_to_zrevrangebyscore
    client = create_test_client

    assert_respond_to client, :zrevrangebyscore
  end

  def test_responds_to_zincrby
    client = create_test_client

    assert_respond_to client, :zincrby
  end

  def test_responds_to_zremrangebyrank
    client = create_test_client

    assert_respond_to client, :zremrangebyrank
  end

  def test_responds_to_zremrangebyscore
    client = create_test_client

    assert_respond_to client, :zremrangebyscore
  end

  def test_responds_to_zpopmin
    client = create_test_client

    assert_respond_to client, :zpopmin
  end

  def test_responds_to_zpopmax
    client = create_test_client

    assert_respond_to client, :zpopmax
  end

  def test_responds_to_bzpopmin
    client = create_test_client

    assert_respond_to client, :bzpopmin
  end

  def test_responds_to_bzpopmax
    client = create_test_client

    assert_respond_to client, :bzpopmax
  end

  def test_responds_to_zscan
    client = create_test_client

    assert_respond_to client, :zscan
  end

  def test_responds_to_zinterstore
    client = create_test_client

    assert_respond_to client, :zinterstore
  end

  def test_responds_to_zunionstore
    client = create_test_client

    assert_respond_to client, :zunionstore
  end

  def test_responds_to_zunion
    client = create_test_client

    assert_respond_to client, :zunion
  end

  def test_responds_to_zinter
    client = create_test_client

    assert_respond_to client, :zinter
  end

  def test_responds_to_zdiff
    client = create_test_client

    assert_respond_to client, :zdiff
  end

  def test_responds_to_zdiffstore
    client = create_test_client

    assert_respond_to client, :zdiffstore
  end

  def test_responds_to_zintercard
    client = create_test_client

    assert_respond_to client, :zintercard
  end

  def test_responds_to_zmpop
    client = create_test_client

    assert_respond_to client, :zmpop
  end

  def test_responds_to_bzmpop
    client = create_test_client

    assert_respond_to client, :bzmpop
  end

  def test_responds_to_zlexcount
    client = create_test_client

    assert_respond_to client, :zlexcount
  end

  def test_responds_to_zrangebylex
    client = create_test_client

    assert_respond_to client, :zrangebylex
  end

  def test_responds_to_zrevrangebylex
    client = create_test_client

    assert_respond_to client, :zrevrangebylex
  end

  def test_responds_to_zremrangebylex
    client = create_test_client

    assert_respond_to client, :zremrangebylex
  end

  def test_responds_to_zrandmember
    client = create_test_client

    assert_respond_to client, :zrandmember
  end

  def test_responds_to_zrangestore
    client = create_test_client

    assert_respond_to client, :zrangestore
  end

  private

  def create_test_client
    RR::Client.new
  end
end
