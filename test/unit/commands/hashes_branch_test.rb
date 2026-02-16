# frozen_string_literal: true

require_relative "../unit_test_helper"

class HashesBranchTest < Minitest::Test
  class MockClient
    include RR::Commands::Hashes

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
      "val"
    end

    def call_3args(cmd, a1, a2, a3)
      @last_command = [cmd, a1, a2, a3]
      1
    end

    private

    def mock_return(args)
      case args[0]
      when "HGETALL" then %w[f1 v1 f2 v2]
      when "HSCAN" then ["0", %w[f1 v1 f2 v2]]
      when "HRANDFIELD"
        if args.include?("WITHVALUES")
          %w[f1 v1 f2 v2]
        elsif args.length > 2
          %w[f1 f2]
        else
          "f1"
        end
      when "HINCRBYFLOAT" then "3.14"
      else "OK"
      end
    end
  end

  def setup
    @client = MockClient.new
  end

  # hset
  def test_hset_single_field_fast_path
    @client.hset("key", "f1", "v1")

    assert_equal %w[HSET key f1 v1], @client.last_command
  end

  def test_hset_multiple_fields
    @client.hset("key", "f1", "v1", "f2", "v2")

    assert_equal %w[HSET key f1 v1 f2 v2], @client.last_command
  end

  # hget, hsetnx
  def test_hget
    @client.hget("key", "field")

    assert_equal %w[HGET key field], @client.last_command
  end

  def test_hsetnx
    @client.hsetnx("key", "field", "val")

    assert_equal %w[HSETNX key field val], @client.last_command
  end

  # hmget, hmset
  def test_hmget
    @client.hmget("key", "f1", "f2")

    assert_equal %w[HMGET key f1 f2], @client.last_command
  end

  def test_hmset
    @client.hmset("key", "f1", "v1", "f2", "v2")

    assert_equal %w[HMSET key f1 v1 f2 v2], @client.last_command
  end

  # hgetall
  def test_hgetall_with_data
    result = @client.hgetall("key")

    assert_equal({ "f1" => "v1", "f2" => "v2" }, result)
  end

  def test_hgetall_empty
    client = EmptyHgetallMock.new
    result = client.hgetall("key")

    assert_empty(result)
  end

  class EmptyHgetallMock
    include RR::Commands::Hashes

    def call(*) = "OK"
    def call_1arg(*, **) = []
    def call_2args(*) = nil
    def call_3args(*) = 0
  end

  # hdel
  def test_hdel_single_field_fast_path
    @client.hdel("key", "f1")

    assert_equal %w[HDEL key f1], @client.last_command
  end

  def test_hdel_multiple_fields
    @client.hdel("key", "f1", "f2", "f3")

    assert_equal %w[HDEL key f1 f2 f3], @client.last_command
  end

  # hexists, hkeys, hvals, hlen, hstrlen
  def test_hexists
    @client.hexists("key", "field")

    assert_equal %w[HEXISTS key field], @client.last_command
  end

  def test_hkeys
    @client.hkeys("key")

    assert_equal %w[HKEYS key], @client.last_command
  end

  def test_hvals
    @client.hvals("key")

    assert_equal %w[HVALS key], @client.last_command
  end

  def test_hlen
    @client.hlen("key")

    assert_equal %w[HLEN key], @client.last_command
  end

  def test_hstrlen
    @client.hstrlen("key", "field")

    assert_equal %w[HSTRLEN key field], @client.last_command
  end

  # hincrby, hincrbyfloat
  def test_hincrby
    @client.hincrby("key", "field", 5)

    assert_equal ["HINCRBY", "key", "field", 5], @client.last_command
  end

  def test_hincrbyfloat
    result = @client.hincrbyfloat("key", "field", 1.5)

    assert_in_delta 3.14, result, 0.001
  end

  # hscan
  def test_hscan_no_options
    cursor, pairs = @client.hscan("key", "0")

    assert_equal "0", cursor
    assert_equal [%w[f1 v1], %w[f2 v2]], pairs
  end

  def test_hscan_with_match
    @client.hscan("key", "0", match: "f*")

    assert_includes @client.last_command, "MATCH"
    assert_includes @client.last_command, "f*"
  end

  def test_hscan_with_count
    @client.hscan("key", "0", count: 100)

    assert_includes @client.last_command, "COUNT"
    assert_includes @client.last_command, 100
  end

  # hrandfield
  def test_hrandfield_no_options
    result = @client.hrandfield("key")

    assert_equal "f1", result
  end

  def test_hrandfield_with_count
    result = @client.hrandfield("key", count: 2)

    assert_equal %w[f1 f2], result
  end

  def test_hrandfield_with_values
    result = @client.hrandfield("key", count: 2, withvalues: true)

    assert_equal [%w[f1 v1], %w[f2 v2]], result
  end

  # hexpire and friends
  def test_hexpire_no_flags
    @client.hexpire("key", 60, "f1", "f2")

    assert_equal ["HEXPIRE", "key", 60, "FIELDS", 2, "f1", "f2"], @client.last_command
  end

  def test_hexpire_with_nx
    @client.hexpire("key", 60, "f1", nx: true)

    assert_includes @client.last_command, "NX"
  end

  def test_hexpire_with_xx
    @client.hexpire("key", 60, "f1", xx: true)

    assert_includes @client.last_command, "XX"
  end

  def test_hexpire_with_gt
    @client.hexpire("key", 60, "f1", gt: true)

    assert_includes @client.last_command, "GT"
  end

  def test_hexpire_with_lt
    @client.hexpire("key", 60, "f1", lt: true)

    assert_includes @client.last_command, "LT"
  end

  def test_hpexpire
    @client.hpexpire("key", 60_000, "f1")

    assert_equal "HPEXPIRE", @client.last_command[0]
  end

  def test_hexpireat
    @client.hexpireat("key", 1_700_000_000, "f1")

    assert_equal "HEXPIREAT", @client.last_command[0]
  end

  def test_hpexpireat
    @client.hpexpireat("key", 1_700_000_000_000, "f1")

    assert_equal "HPEXPIREAT", @client.last_command[0]
  end

  # httl, hpttl, hexpiretime, hpexpiretime, hpersist
  def test_httl
    @client.httl("key", "f1", "f2")

    assert_equal ["HTTL", "key", "FIELDS", 2, "f1", "f2"], @client.last_command
  end

  def test_hpttl
    @client.hpttl("key", "f1")

    assert_equal ["HPTTL", "key", "FIELDS", 1, "f1"], @client.last_command
  end

  def test_hexpiretime
    @client.hexpiretime("key", "f1")

    assert_equal ["HEXPIRETIME", "key", "FIELDS", 1, "f1"], @client.last_command
  end

  def test_hpexpiretime
    @client.hpexpiretime("key", "f1")

    assert_equal ["HPEXPIRETIME", "key", "FIELDS", 1, "f1"], @client.last_command
  end

  def test_hpersist
    @client.hpersist("key", "f1")

    assert_equal ["HPERSIST", "key", "FIELDS", 1, "f1"], @client.last_command
  end
end
