# frozen_string_literal: true

require_relative "../unit_test_helper"

class ListsBranchTest < Minitest::Test
  class MockClient
    include RR::Commands::Lists

    attr_reader :last_command

    def call(*args)
      (@last_command = args
       "OK")
    end

    def call_1arg(cmd, a1)
      (@last_command = [cmd, a1]
       "OK")
    end

    def call_2args(cmd, a1, a2)
      (@last_command = [cmd, a1, a2]
       1)
    end

    def call_3args(cmd, a1, a2, a3)
      (@last_command = [cmd, a1, a2, a3]
       "OK")
    end
  end

  def setup
    @client = MockClient.new
  end

  # lpush
  def test_lpush_single_value_fast_path
    @client.lpush("key", "val")

    assert_equal %w[LPUSH key val], @client.last_command
  end

  def test_lpush_multiple_values
    @client.lpush("key", "v1", "v2", "v3")

    assert_equal %w[LPUSH key v1 v2 v3], @client.last_command
  end

  # lpushx
  def test_lpushx_single_value_fast_path
    @client.lpushx("key", "val")

    assert_equal %w[LPUSHX key val], @client.last_command
  end

  def test_lpushx_multiple_values
    @client.lpushx("key", "v1", "v2")

    assert_equal %w[LPUSHX key v1 v2], @client.last_command
  end

  # rpush
  def test_rpush_single_value_fast_path
    @client.rpush("key", "val")

    assert_equal %w[RPUSH key val], @client.last_command
  end

  def test_rpush_multiple_values
    @client.rpush("key", "v1", "v2")

    assert_equal %w[RPUSH key v1 v2], @client.last_command
  end

  # rpushx
  def test_rpushx_single_value_fast_path
    @client.rpushx("key", "val")

    assert_equal %w[RPUSHX key val], @client.last_command
  end

  def test_rpushx_multiple_values
    @client.rpushx("key", "v1", "v2")

    assert_equal %w[RPUSHX key v1 v2], @client.last_command
  end

  # lpop
  def test_lpop_no_count
    @client.lpop("key")

    assert_equal %w[LPOP key], @client.last_command
  end

  def test_lpop_with_count
    @client.lpop("key", 3)

    assert_equal ["LPOP", "key", 3], @client.last_command
  end

  # rpop
  def test_rpop_no_count
    @client.rpop("key")

    assert_equal %w[RPOP key], @client.last_command
  end

  def test_rpop_with_count
    @client.rpop("key", 5)

    assert_equal ["RPOP", "key", 5], @client.last_command
  end

  # lrange, llen, lindex, lset
  def test_lrange
    @client.lrange("key", 0, -1)

    assert_equal ["LRANGE", "key", 0, -1], @client.last_command
  end

  def test_llen
    @client.llen("key")

    assert_equal %w[LLEN key], @client.last_command
  end

  def test_lindex
    @client.lindex("key", 2)

    assert_equal ["LINDEX", "key", 2], @client.last_command
  end

  def test_lset
    @client.lset("key", 0, "val")

    assert_equal ["LSET", "key", 0, "val"], @client.last_command
  end

  # linsert
  def test_linsert_before
    @client.linsert("key", :before, "pivot", "val")

    assert_equal %w[LINSERT key BEFORE pivot val], @client.last_command
  end

  def test_linsert_after
    @client.linsert("key", :after, "pivot", "val")

    assert_equal %w[LINSERT key AFTER pivot val], @client.last_command
  end

  # lrem, ltrim
  def test_lrem
    @client.lrem("key", 2, "val")

    assert_equal ["LREM", "key", 2, "val"], @client.last_command
  end

  def test_ltrim
    @client.ltrim("key", 0, 99)

    assert_equal ["LTRIM", "key", 0, 99], @client.last_command
  end

  # rpoplpush, lmove
  def test_rpoplpush
    @client.rpoplpush("src", "dst")

    assert_equal %w[RPOPLPUSH src dst], @client.last_command
  end

  def test_lmove
    @client.lmove("src", "dst", :left, :right)

    assert_equal %w[LMOVE src dst LEFT RIGHT], @client.last_command
  end

  # lmpop
  def test_lmpop_default
    @client.lmpop("k1", "k2")

    assert_equal ["LMPOP", 2, "k1", "k2", "LEFT"], @client.last_command
  end

  def test_lmpop_right_with_count
    @client.lmpop("k1", direction: :right, count: 3)

    assert_equal ["LMPOP", 1, "k1", "RIGHT", "COUNT", 3], @client.last_command
  end

  # blmpop
  def test_blmpop_default
    @client.blmpop(0, "k1", "k2")

    assert_equal ["BLMPOP", 0, 2, "k1", "k2", "LEFT"], @client.last_command
  end

  def test_blmpop_right_with_count
    @client.blmpop(5, "k1", direction: :right, count: 2)

    assert_equal ["BLMPOP", 5, 1, "k1", "RIGHT", "COUNT", 2], @client.last_command
  end

  # lpos
  def test_lpos_fast_path
    @client.lpos("key", "elem")

    assert_equal %w[LPOS key elem], @client.last_command
  end

  def test_lpos_with_rank
    @client.lpos("key", "elem", rank: 2)

    assert_equal ["LPOS", "key", "elem", "RANK", 2], @client.last_command
  end

  def test_lpos_with_count
    @client.lpos("key", "elem", count: 0)

    assert_equal ["LPOS", "key", "elem", "COUNT", 0], @client.last_command
  end

  def test_lpos_with_maxlen
    @client.lpos("key", "elem", maxlen: 100)

    assert_equal ["LPOS", "key", "elem", "MAXLEN", 100], @client.last_command
  end

  def test_lpos_all_options
    @client.lpos("key", "elem", rank: 1, count: 5, maxlen: 50)

    assert_equal ["LPOS", "key", "elem", "RANK", 1, "COUNT", 5, "MAXLEN", 50], @client.last_command
  end

  # blpop, brpop
  def test_blpop
    @client.blpop("k1", "k2", timeout: 5)

    assert_equal ["BLPOP", "k1", "k2", 5], @client.last_command
  end

  def test_brpop
    @client.brpop("k1", timeout: 0)

    assert_equal ["BRPOP", "k1", 0], @client.last_command
  end

  # brpoplpush, blmove
  def test_brpoplpush
    @client.brpoplpush("src", "dst", timeout: 10)

    assert_equal ["BRPOPLPUSH", "src", "dst", 10], @client.last_command
  end

  def test_blmove
    @client.blmove("src", "dst", :right, :left, timeout: 5)

    assert_equal ["BLMOVE", "src", "dst", "RIGHT", "LEFT", 5], @client.last_command
  end
end
