# frozen_string_literal: true

require_relative "../unit_test_helper"

module StreamsBranchTestMocks
  class MockClient
    include RR::Commands::Streams

    attr_reader :last_command

    def call(*args)
      @last_command = args
      mock_return(args)
    end

    def call_1arg(cmd, arg_one)
      @last_command = [cmd, arg_one]
      mock_return(@last_command)
    end

    def call_2args(cmd, arg_one, arg_two)
      @last_command = [cmd, arg_one, arg_two]
      mock_return(@last_command)
    end

    def call_3args(cmd, arg_one, arg_two, arg_three)
      @last_command = [cmd, arg_one, arg_two, arg_three]
      mock_return(@last_command)
    end

    MOCK_RETURNS = {
      "XRANGE" => [["id1", %w[f1 v1]], ["id2", %w[f2 v2]]],
      "XREVRANGE" => [["id1", %w[f1 v1]], ["id2", %w[f2 v2]]],
      "XREAD" => [["stream1", [["id1", %w[f1 v1]]]]],
      "XREADGROUP" => [["stream1", [["id1", %w[f1 v1]]]]],
      "XPENDING" => ["summary"],
      "XCLAIM" => [["id1", %w[f1 v1]]],
      "XAUTOCLAIM" => ["next-id", [["id1", %w[f1 v1]]], []],
      "XLEN" => 1, "XACK" => 1, "XDEL" => 1,
    }.freeze

    XINFO_RETURNS = {
      "STREAM" => %w[key1 val1 key2 val2],
      "GROUPS" => [%w[name g1 consumers 1]],
      "CONSUMERS" => [%w[name c1 pending 0]],
    }.freeze

    private

    def mock_return(args)
      return XINFO_RETURNS[args[1]] if args[0] == "XINFO"

      MOCK_RETURNS.fetch(args[0], "OK")
    end
  end

  class NilReturningMockClient < MockClient
    private

    def mock_return(args)
      if %w[XREAD XREADGROUP XAUTOCLAIM XCLAIM].include?(args[0])
        nil
      else
        super
      end
    end
  end
end

class StreamsBranchTest < Minitest::Test
  def setup
    @client = StreamsBranchTestMocks::MockClient.new
  end

  # ---------------------------------------------------------------------------
  # xadd
  # ---------------------------------------------------------------------------

  def test_xadd_basic
    @client.xadd("mystream", { "field1" => "value1" })

    assert_equal ["XADD", "mystream", "*", "field1", "value1"], @client.last_command
  end

  def test_xadd_with_custom_id
    @client.xadd("mystream", { "f" => "v" }, id: "1000-0")

    assert_equal %w[XADD mystream 1000-0 f v], @client.last_command
  end

  def test_xadd_with_maxlen
    @client.xadd("mystream", { "f" => "v" }, maxlen: 1000)

    assert_equal ["XADD", "mystream", "MAXLEN", 1000, "*", "f", "v"], @client.last_command
  end

  def test_xadd_with_maxlen_approximate
    @client.xadd("mystream", { "f" => "v" }, maxlen: 1000, approximate: true)

    assert_equal ["XADD", "mystream", "MAXLEN", "~", 1000, "*", "f", "v"], @client.last_command
  end

  def test_xadd_with_maxlen_approximate_and_limit
    @client.xadd("mystream", { "f" => "v" }, maxlen: 1000, approximate: true, limit: 100)

    assert_equal ["XADD", "mystream", "MAXLEN", "~", 1000, "LIMIT", 100, "*", "f", "v"], @client.last_command
  end

  def test_xadd_with_maxlen_exact_and_limit_ignored
    # limit is only applied when approximate is true
    @client.xadd("mystream", { "f" => "v" }, maxlen: 1000, approximate: false, limit: 100)

    assert_equal ["XADD", "mystream", "MAXLEN", 1000, "*", "f", "v"], @client.last_command
  end

  def test_xadd_with_minid
    @client.xadd("mystream", { "f" => "v" }, minid: "1000-0")

    assert_equal ["XADD", "mystream", "MINID", "1000-0", "*", "f", "v"], @client.last_command
  end

  def test_xadd_with_minid_approximate
    @client.xadd("mystream", { "f" => "v" }, minid: "1000-0", approximate: true)

    assert_equal ["XADD", "mystream", "MINID", "~", "1000-0", "*", "f", "v"], @client.last_command
  end

  def test_xadd_with_minid_approximate_and_limit
    @client.xadd("mystream", { "f" => "v" }, minid: "1000-0", approximate: true, limit: 50)

    assert_equal ["XADD", "mystream", "MINID", "~", "1000-0", "LIMIT", 50, "*", "f", "v"], @client.last_command
  end

  def test_xadd_with_minid_exact_and_limit_ignored
    # limit is only applied when approximate is true
    @client.xadd("mystream", { "f" => "v" }, minid: "1000-0", approximate: false, limit: 50)

    assert_equal ["XADD", "mystream", "MINID", "1000-0", "*", "f", "v"], @client.last_command
  end

  def test_xadd_with_nomkstream
    @client.xadd("mystream", { "f" => "v" }, nomkstream: true)

    assert_equal ["XADD", "mystream", "NOMKSTREAM", "*", "f", "v"], @client.last_command
  end

  def test_xadd_with_nomkstream_and_maxlen
    @client.xadd("mystream", { "f" => "v" }, nomkstream: true, maxlen: 500)

    assert_equal ["XADD", "mystream", "NOMKSTREAM", "MAXLEN", 500, "*", "f", "v"], @client.last_command
  end

  def test_xadd_with_multiple_fields
    @client.xadd("mystream", { "a" => "1", "b" => "2", "c" => "3" })

    assert_equal ["XADD", "mystream", "*", "a", "1", "b", "2", "c", "3"], @client.last_command
  end

  def test_xadd_no_maxlen_no_minid
    # Neither maxlen nor minid: no trimming options added
    @client.xadd("mystream", { "f" => "v" })

    refute_includes @client.last_command, "MAXLEN"
    refute_includes @client.last_command, "MINID"
  end

  # ---------------------------------------------------------------------------
  # xlen
  # ---------------------------------------------------------------------------

  def test_xlen
    result = @client.xlen("mystream")

    assert_equal %w[XLEN mystream], @client.last_command
    assert_equal 1, result
  end

  # ---------------------------------------------------------------------------
  # xrange
  # ---------------------------------------------------------------------------

  def test_xrange_fast_path_no_count
    result = @client.xrange("mystream", "-", "+")

    assert_equal ["XRANGE", "mystream", "-", "+"], @client.last_command
    # parse_entries converts [id, [f, v]] -> [id, {f => v}]
    assert_equal [["id1", { "f1" => "v1" }], ["id2", { "f2" => "v2" }]], result
  end

  def test_xrange_with_count
    result = @client.xrange("mystream", "-", "+", count: 10)

    assert_equal ["XRANGE", "mystream", "-", "+", "COUNT", 10], @client.last_command
    assert_equal [["id1", { "f1" => "v1" }], ["id2", { "f2" => "v2" }]], result
  end

  # ---------------------------------------------------------------------------
  # xrevrange
  # ---------------------------------------------------------------------------

  def test_xrevrange_fast_path_no_count
    result = @client.xrevrange("mystream", "+", "-")

    assert_equal ["XREVRANGE", "mystream", "+", "-"], @client.last_command
    assert_equal [["id1", { "f1" => "v1" }], ["id2", { "f2" => "v2" }]], result
  end

  def test_xrevrange_with_count
    result = @client.xrevrange("mystream", "+", "-", count: 5)

    assert_equal ["XREVRANGE", "mystream", "+", "-", "COUNT", 5], @client.last_command
    assert_equal [["id1", { "f1" => "v1" }], ["id2", { "f2" => "v2" }]], result
  end

  # ---------------------------------------------------------------------------
  # xread
  # ---------------------------------------------------------------------------

  def test_xread_single_stream_with_id
    result = @client.xread("mystream", "0-0")

    assert_equal %w[XREAD STREAMS mystream 0-0], @client.last_command
    assert_equal [["stream1", [["id1", { "f1" => "v1" }]]]], result
  end

  def test_xread_hash_of_streams
    result = @client.xread({ "stream1" => "0-0", "stream2" => "0-0" })

    assert_equal "XREAD", @client.last_command[0]
    assert_equal "STREAMS", @client.last_command[1]
    # Keys then values from the hash
    assert_equal "stream1", @client.last_command[2]
    assert_equal "stream2", @client.last_command[3]
    assert_equal "0-0", @client.last_command[4]
    assert_equal "0-0", @client.last_command[5]
    assert_equal [["stream1", [["id1", { "f1" => "v1" }]]]], result
  end

  def test_xread_with_count
    @client.xread("mystream", "0-0", count: 10)

    assert_equal ["XREAD", "COUNT", 10, "STREAMS", "mystream", "0-0"], @client.last_command
  end

  def test_xread_with_block
    @client.xread("mystream", "$", block: 5000)

    assert_equal ["XREAD", "BLOCK", 5000, "STREAMS", "mystream", "$"], @client.last_command
  end

  def test_xread_with_count_and_block
    @client.xread("mystream", "$", count: 10, block: 5000)

    assert_equal ["XREAD", "COUNT", 10, "BLOCK", 5000, "STREAMS", "mystream", "$"], @client.last_command
  end

  def test_xread_nil_result
    nil_client = StreamsBranchTestMocks::NilReturningMockClient.new
    result = nil_client.xread("mystream", "0-0")

    assert_nil result
  end

  # ---------------------------------------------------------------------------
  # xgroup_create
  # ---------------------------------------------------------------------------

  def test_xgroup_create_basic
    result = @client.xgroup_create("mystream", "mygroup", "$")

    assert_equal ["XGROUP", "CREATE", "mystream", "mygroup", "$"], @client.last_command
    assert_equal "OK", result
  end

  def test_xgroup_create_with_mkstream
    @client.xgroup_create("mystream", "mygroup", "$", mkstream: true)

    assert_equal ["XGROUP", "CREATE", "mystream", "mygroup", "$", "MKSTREAM"], @client.last_command
  end

  def test_xgroup_create_with_entriesread
    @client.xgroup_create("mystream", "mygroup", "$", entriesread: 100)

    assert_equal ["XGROUP", "CREATE", "mystream", "mygroup", "$", "ENTRIESREAD", 100], @client.last_command
  end

  def test_xgroup_create_with_mkstream_and_entriesread
    @client.xgroup_create("mystream", "mygroup", "$", mkstream: true, entriesread: 50)

    assert_equal ["XGROUP", "CREATE", "mystream", "mygroup", "$", "MKSTREAM", "ENTRIESREAD", 50], @client.last_command
  end

  def test_xgroup_create_without_mkstream
    @client.xgroup_create("mystream", "mygroup", "0")

    refute_includes @client.last_command, "MKSTREAM"
  end

  def test_xgroup_create_without_entriesread
    @client.xgroup_create("mystream", "mygroup", "0")

    refute_includes @client.last_command, "ENTRIESREAD"
  end

  # ---------------------------------------------------------------------------
  # xgroup_destroy
  # ---------------------------------------------------------------------------

  def test_xgroup_destroy
    result = @client.xgroup_destroy("mystream", "mygroup")

    assert_equal %w[XGROUP DESTROY mystream mygroup], @client.last_command
    assert_equal "OK", result
  end

  # ---------------------------------------------------------------------------
  # xgroup_setid
  # ---------------------------------------------------------------------------

  def test_xgroup_setid
    result = @client.xgroup_setid("mystream", "mygroup", "0-0")

    assert_equal %w[XGROUP SETID mystream mygroup 0-0], @client.last_command
    assert_equal "OK", result
  end

  # ---------------------------------------------------------------------------
  # xgroup_createconsumer
  # ---------------------------------------------------------------------------

  def test_xgroup_createconsumer
    result = @client.xgroup_createconsumer("mystream", "mygroup", "consumer1")

    assert_equal %w[XGROUP CREATECONSUMER mystream mygroup consumer1], @client.last_command
    assert_equal "OK", result
  end

  # ---------------------------------------------------------------------------
  # xgroup_delconsumer
  # ---------------------------------------------------------------------------

  def test_xgroup_delconsumer
    result = @client.xgroup_delconsumer("mystream", "mygroup", "consumer1")

    assert_equal %w[XGROUP DELCONSUMER mystream mygroup consumer1], @client.last_command
    assert_equal "OK", result
  end

  # ---------------------------------------------------------------------------
  # xreadgroup
  # ---------------------------------------------------------------------------

  def test_xreadgroup_single_stream
    result = @client.xreadgroup("mygroup", "consumer1", "mystream", ">")

    assert_equal ["XREADGROUP", "GROUP", "mygroup", "consumer1", "STREAMS", "mystream", ">"], @client.last_command
    assert_equal [["stream1", [["id1", { "f1" => "v1" }]]]], result
  end

  def test_xreadgroup_hash_of_streams
    result = @client.xreadgroup("mygroup", "consumer1", { "s1" => ">", "s2" => ">" })

    assert_equal "XREADGROUP", @client.last_command[0]
    assert_equal "GROUP", @client.last_command[1]
    assert_equal "mygroup", @client.last_command[2]
    assert_equal "consumer1", @client.last_command[3]
    assert_equal "STREAMS", @client.last_command[4]
    assert_equal "s1", @client.last_command[5]
    assert_equal "s2", @client.last_command[6]
    assert_equal ">", @client.last_command[7]
    assert_equal ">", @client.last_command[8]
    assert_equal [["stream1", [["id1", { "f1" => "v1" }]]]], result
  end

  def test_xreadgroup_with_count
    @client.xreadgroup("mygroup", "consumer1", "mystream", ">", count: 10)

    assert_equal ["XREADGROUP", "GROUP", "mygroup", "consumer1", "COUNT", 10, "STREAMS", "mystream", ">"],
                 @client.last_command
  end

  def test_xreadgroup_with_block
    @client.xreadgroup("mygroup", "consumer1", "mystream", ">", block: 5000)

    assert_equal ["XREADGROUP", "GROUP", "mygroup", "consumer1", "BLOCK", 5000, "STREAMS", "mystream", ">"],
                 @client.last_command
  end

  def test_xreadgroup_with_noack
    @client.xreadgroup("mygroup", "consumer1", "mystream", ">", noack: true)

    assert_equal ["XREADGROUP", "GROUP", "mygroup", "consumer1", "NOACK", "STREAMS", "mystream", ">"],
                 @client.last_command
  end

  def test_xreadgroup_without_noack
    @client.xreadgroup("mygroup", "consumer1", "mystream", ">", noack: false)

    refute_includes @client.last_command, "NOACK"
  end
end

class StreamsBranchTestPart2 < Minitest::Test
  def setup
    @client = StreamsBranchTestMocks::MockClient.new
  end

  # ---------------------------------------------------------------------------
  # xadd
  # ---------------------------------------------------------------------------

  def test_xreadgroup_with_count_block_and_noack
    @client.xreadgroup("mygroup", "consumer1", "mystream", ">", count: 5, block: 2000, noack: true)

    assert_equal(
      ["XREADGROUP", "GROUP", "mygroup", "consumer1", "COUNT", 5, "BLOCK", 2000, "NOACK", "STREAMS", "mystream", ">"],
      @client.last_command
    )
  end

  def test_xreadgroup_nil_result
    nil_client = StreamsBranchTestMocks::NilReturningMockClient.new
    result = nil_client.xreadgroup("mygroup", "consumer1", "mystream", ">")

    assert_nil result
  end

  # ---------------------------------------------------------------------------
  # xack
  # ---------------------------------------------------------------------------

  def test_xack_single_id_fast_path
    result = @client.xack("mystream", "mygroup", "1000-0")

    assert_equal %w[XACK mystream mygroup 1000-0], @client.last_command
    assert_equal 1, result
  end

  def test_xack_multiple_ids
    result = @client.xack("mystream", "mygroup", "1000-0", "1001-0", "1002-0")

    assert_equal %w[XACK mystream mygroup 1000-0 1001-0 1002-0], @client.last_command
    assert_equal 1, result
  end

  # ---------------------------------------------------------------------------
  # xpending
  # ---------------------------------------------------------------------------

  def test_xpending_summary_no_range_args
    result = @client.xpending("mystream", "mygroup")

    assert_equal %w[XPENDING mystream mygroup], @client.last_command
    assert_equal ["summary"], result
  end

  def test_xpending_detailed_with_start_stop_count
    result = @client.xpending("mystream", "mygroup", "-", "+", 10)

    assert_equal ["XPENDING", "mystream", "mygroup", "-", "+", 10], @client.last_command
    assert_equal ["summary"], result
  end

  def test_xpending_detailed_with_consumer
    result = @client.xpending("mystream", "mygroup", "-", "+", 10, consumer: "consumer1")

    assert_equal ["XPENDING", "mystream", "mygroup", "-", "+", 10, "consumer1"], @client.last_command
    assert_equal ["summary"], result
  end

  def test_xpending_detailed_without_consumer
    @client.xpending("mystream", "mygroup", "-", "+", 5)

    refute_includes @client.last_command, "consumer1"
    assert_equal 6, @client.last_command.size
  end

  def test_xpending_summary_when_only_start_given
    # When not all three range args are provided, falls to summary branch
    result = @client.xpending("mystream", "mygroup", "-")

    assert_equal %w[XPENDING mystream mygroup], @client.last_command
    assert_equal ["summary"], result
  end

  def test_xpending_summary_when_start_and_stop_but_no_count
    # When count is nil, falls to summary branch
    result = @client.xpending("mystream", "mygroup", "-", "+")

    assert_equal %w[XPENDING mystream mygroup], @client.last_command
    assert_equal ["summary"], result
  end

  # ---------------------------------------------------------------------------
  # xclaim
  # ---------------------------------------------------------------------------

  def test_xclaim_basic
    result = @client.xclaim("mystream", "mygroup", "consumer1", 60_000, "1000-0")

    assert_equal ["XCLAIM", "mystream", "mygroup", "consumer1", 60_000, "1000-0"], @client.last_command
    # parse_entries is called when justid is false
    assert_equal [["id1", { "f1" => "v1" }]], result
  end

  def test_xclaim_multiple_ids
    result = @client.xclaim("mystream", "mygroup", "consumer1", 60_000, "1000-0", "1001-0")

    assert_equal ["XCLAIM", "mystream", "mygroup", "consumer1", 60_000, "1000-0", "1001-0"], @client.last_command
    assert_equal [["id1", { "f1" => "v1" }]], result
  end

  def test_xclaim_with_idle
    @client.xclaim("mystream", "mygroup", "consumer1", 60_000, "1000-0", idle: 120_000)

    assert_equal(
      ["XCLAIM", "mystream", "mygroup", "consumer1", 60_000, "1000-0", "IDLE", 120_000],
      @client.last_command
    )
  end

  def test_xclaim_with_time
    @client.xclaim("mystream", "mygroup", "consumer1", 60_000, "1000-0", time: 1_609_459_200_000)

    assert_equal(
      ["XCLAIM", "mystream", "mygroup", "consumer1", 60_000, "1000-0", "TIME", 1_609_459_200_000],
      @client.last_command
    )
  end

  def test_xclaim_with_retrycount
    @client.xclaim("mystream", "mygroup", "consumer1", 60_000, "1000-0", retrycount: 3)

    assert_equal(
      ["XCLAIM", "mystream", "mygroup", "consumer1", 60_000, "1000-0", "RETRYCOUNT", 3],
      @client.last_command
    )
  end

  def test_xclaim_with_force
    @client.xclaim("mystream", "mygroup", "consumer1", 60_000, "1000-0", force: true)

    assert_equal(
      ["XCLAIM", "mystream", "mygroup", "consumer1", 60_000, "1000-0", "FORCE"],
      @client.last_command
    )
  end

  def test_xclaim_without_force
    @client.xclaim("mystream", "mygroup", "consumer1", 60_000, "1000-0", force: false)

    refute_includes @client.last_command, "FORCE"
  end

  def test_xclaim_with_justid
    # With justid: true, result is returned raw (no parse_entries)
    nil_client = StreamsBranchTestMocks::NilReturningMockClient.new
    result = nil_client.xclaim("mystream", "mygroup", "consumer1", 60_000, "1000-0", justid: true)
    # NilReturningMockClient returns nil for XCLAIM; justid branch returns result directly
    assert_nil result
  end

  def test_xclaim_justid_returns_result_directly
    # Create a custom mock that returns IDs for justid
    client = StreamsBranchTestMocks::MockClient.new
    # When justid is true, the result should be returned as-is (not parsed)
    result = client.xclaim("mystream", "mygroup", "consumer1", 60_000, "1000-0", justid: true)
    # MockClient returns [["id1", ["f1", "v1"]]] for XCLAIM
    # With justid: true, it should return that raw (not parse_entries)
    assert_equal [["id1", %w[f1 v1]]], result
  end

  def test_xclaim_without_justid_parses_entries
    result = @client.xclaim("mystream", "mygroup", "consumer1", 60_000, "1000-0", justid: false)
    # Without justid, parse_entries converts [id, [f, v]] -> [id, {f => v}]
    assert_equal [["id1", { "f1" => "v1" }]], result
  end

  def test_xclaim_with_all_options
    @client.xclaim("mystream", "mygroup", "consumer1", 60_000, "1000-0",
                   idle: 120_000, time: 1_609_459_200_000, retrycount: 5, force: true, justid: true)

    assert_equal(
      ["XCLAIM", "mystream", "mygroup", "consumer1", 60_000, "1000-0",
       "IDLE", 120_000, "TIME", 1_609_459_200_000, "RETRYCOUNT", 5, "FORCE", "JUSTID",],
      @client.last_command
    )
  end

  def test_xclaim_without_optional_params
    @client.xclaim("mystream", "mygroup", "consumer1", 60_000, "1000-0")

    refute_includes @client.last_command, "IDLE"
    refute_includes @client.last_command, "TIME"
    refute_includes @client.last_command, "RETRYCOUNT"
    refute_includes @client.last_command, "FORCE"
    refute_includes @client.last_command, "JUSTID"
  end

  # ---------------------------------------------------------------------------
  # xautoclaim
  # ---------------------------------------------------------------------------

  def test_xautoclaim_basic
    result = @client.xautoclaim("mystream", "mygroup", "consumer1", 60_000, "0-0")

    assert_equal ["XAUTOCLAIM", "mystream", "mygroup", "consumer1", 60_000, "0-0"], @client.last_command
    # Returns [next_id, parsed_entries, deleted_ids]
    assert_equal "next-id", result[0]
    assert_equal [["id1", { "f1" => "v1" }]], result[1]
    assert_empty result[2]
  end

  def test_xautoclaim_with_count
    @client.xautoclaim("mystream", "mygroup", "consumer1", 60_000, "0-0", count: 10)

    assert_equal(
      ["XAUTOCLAIM", "mystream", "mygroup", "consumer1", 60_000, "0-0", "COUNT", 10],
      @client.last_command
    )
  end

  def test_xautoclaim_without_count
    @client.xautoclaim("mystream", "mygroup", "consumer1", 60_000, "0-0")

    refute_includes @client.last_command, "COUNT"
  end

  def test_xautoclaim_with_justid
    result = @client.xautoclaim("mystream", "mygroup", "consumer1", 60_000, "0-0", justid: true)

    assert_includes @client.last_command, "JUSTID"
    # With justid: true, entries are returned as-is (not parsed)
    assert_equal "next-id", result[0]
    # justid branch: result[1] returned raw
    assert_equal [["id1", %w[f1 v1]]], result[1]
    assert_empty result[2]
  end

  def test_xautoclaim_without_justid
    result = @client.xautoclaim("mystream", "mygroup", "consumer1", 60_000, "0-0", justid: false)

    refute_includes @client.last_command, "JUSTID"
    # Without justid, entries are parsed
    assert_equal [["id1", { "f1" => "v1" }]], result[1]
  end

  def test_xautoclaim_with_count_and_justid
    @client.xautoclaim("mystream", "mygroup", "consumer1", 60_000, "0-0", count: 5, justid: true)

    assert_equal(
      ["XAUTOCLAIM", "mystream", "mygroup", "consumer1", 60_000, "0-0", "COUNT", 5, "JUSTID"],
      @client.last_command
    )
  end

  def test_xautoclaim_nil_result
    nil_client = StreamsBranchTestMocks::NilReturningMockClient.new
    result = nil_client.xautoclaim("mystream", "mygroup", "consumer1", 60_000, "0-0")

    assert_nil result
  end

  # ---------------------------------------------------------------------------
  # xinfo_stream
  # ---------------------------------------------------------------------------

  def test_xinfo_stream_basic
    result = @client.xinfo_stream("mystream")

    assert_equal %w[XINFO STREAM mystream], @client.last_command
    # hash_result converts ["key1", "val1", "key2", "val2"] -> {"key1" => "val1", "key2" => "val2"}
    assert_equal({ "key1" => "val1", "key2" => "val2" }, result)
  end

  def test_xinfo_stream_with_full
    result = @client.xinfo_stream("mystream", full: true)

    assert_equal %w[XINFO STREAM mystream FULL], @client.last_command
    assert_equal({ "key1" => "val1", "key2" => "val2" }, result)
  end

  def test_xinfo_stream_with_full_and_count
    result = @client.xinfo_stream("mystream", full: true, count: 10)

    assert_equal ["XINFO", "STREAM", "mystream", "FULL", "COUNT", 10], @client.last_command
    assert_equal({ "key1" => "val1", "key2" => "val2" }, result)
  end

  def test_xinfo_stream_without_full_count_ignored
    # count is only used when full is true
    result = @client.xinfo_stream("mystream", full: false, count: 10)

    assert_equal %w[XINFO STREAM mystream], @client.last_command
    refute_includes @client.last_command, "FULL"
    refute_includes @client.last_command, "COUNT"
    assert_equal({ "key1" => "val1", "key2" => "val2" }, result)
  end

  # ---------------------------------------------------------------------------
  # xinfo_groups
  # ---------------------------------------------------------------------------

  def test_xinfo_groups
    result = @client.xinfo_groups("mystream")

    assert_equal %w[XINFO GROUPS mystream], @client.last_command
    # Each group array is converted to a hash
    assert_equal [{ "name" => "g1", "consumers" => "1" }], result
  end

  # ---------------------------------------------------------------------------
  # xinfo_consumers
  # ---------------------------------------------------------------------------
end

class StreamsBranchTestPart3 < Minitest::Test
  def setup
    @client = StreamsBranchTestMocks::MockClient.new
  end

  # ---------------------------------------------------------------------------
  # xadd
  # ---------------------------------------------------------------------------

  def test_xinfo_consumers
    result = @client.xinfo_consumers("mystream", "mygroup")

    assert_equal %w[XINFO CONSUMERS mystream mygroup], @client.last_command
    assert_equal [{ "name" => "c1", "pending" => "0" }], result
  end

  # ---------------------------------------------------------------------------
  # xdel
  # ---------------------------------------------------------------------------

  def test_xdel_single_id_fast_path
    result = @client.xdel("mystream", "1000-0")

    assert_equal %w[XDEL mystream 1000-0], @client.last_command
    assert_equal 1, result
  end

  def test_xdel_multiple_ids
    result = @client.xdel("mystream", "1000-0", "1001-0", "1002-0")

    assert_equal %w[XDEL mystream 1000-0 1001-0 1002-0], @client.last_command
    assert_equal 1, result
  end

  # ---------------------------------------------------------------------------
  # xtrim
  # ---------------------------------------------------------------------------

  def test_xtrim_with_maxlen
    result = @client.xtrim("mystream", maxlen: 1000)

    assert_equal ["XTRIM", "mystream", "MAXLEN", 1000], @client.last_command
    assert_equal "OK", result
  end

  def test_xtrim_with_maxlen_approximate
    @client.xtrim("mystream", maxlen: 1000, approximate: true)

    assert_equal ["XTRIM", "mystream", "MAXLEN", "~", 1000], @client.last_command
  end

  def test_xtrim_with_maxlen_and_limit
    @client.xtrim("mystream", maxlen: 1000, limit: 100)

    assert_equal ["XTRIM", "mystream", "MAXLEN", 1000, "LIMIT", 100], @client.last_command
  end

  def test_xtrim_with_maxlen_approximate_and_limit
    @client.xtrim("mystream", maxlen: 1000, approximate: true, limit: 100)

    assert_equal ["XTRIM", "mystream", "MAXLEN", "~", 1000, "LIMIT", 100], @client.last_command
  end

  def test_xtrim_with_maxlen_exact_no_approximate
    @client.xtrim("mystream", maxlen: 1000, approximate: false)

    refute_includes @client.last_command, "~"
  end

  def test_xtrim_with_minid
    @client.xtrim("mystream", minid: "1000-0")

    assert_equal %w[XTRIM mystream MINID 1000-0], @client.last_command
  end

  def test_xtrim_with_minid_approximate
    @client.xtrim("mystream", minid: "1000-0", approximate: true)

    assert_equal ["XTRIM", "mystream", "MINID", "~", "1000-0"], @client.last_command
  end

  def test_xtrim_with_minid_and_limit
    @client.xtrim("mystream", minid: "1000-0", limit: 50)

    assert_equal ["XTRIM", "mystream", "MINID", "1000-0", "LIMIT", 50], @client.last_command
  end

  def test_xtrim_with_minid_approximate_and_limit
    @client.xtrim("mystream", minid: "1000-0", approximate: true, limit: 50)

    assert_equal ["XTRIM", "mystream", "MINID", "~", "1000-0", "LIMIT", 50], @client.last_command
  end

  def test_xtrim_with_minid_exact_no_approximate
    @client.xtrim("mystream", minid: "1000-0", approximate: false)

    refute_includes @client.last_command, "~"
  end

  def test_xtrim_missing_both_maxlen_and_minid_raises_argument_error
    assert_raises(ArgumentError) do
      @client.xtrim("mystream")
    end
  end

  def test_xtrim_argument_error_message
    error = assert_raises(ArgumentError) do
      @client.xtrim("mystream")
    end
    assert_equal "Must specify maxlen or minid", error.message
  end

  # ---------------------------------------------------------------------------
  # parse_entries (private, tested indirectly)
  # ---------------------------------------------------------------------------

  def test_parse_entries_with_nil_entries_via_xrange
    # Create a mock that returns nil for XRANGE to test parse_entries nil guard
    nil_entries_client = Class.new(StreamsBranchTestMocks::MockClient) do
      private

      def mock_return(args)
        case args[0]
        when "XRANGE", "XREVRANGE" then nil
        else super
        end
      end
    end.new

    result = nil_entries_client.xrange("mystream", "-", "+")

    assert_empty result
  end

  # ---------------------------------------------------------------------------
  # hash_result (private, tested indirectly)
  # ---------------------------------------------------------------------------

  def test_hash_result_with_nil_via_xinfo_stream
    # Create a mock that returns nil for XINFO STREAM to test hash_result nil guard
    nil_info_client = Class.new(StreamsBranchTestMocks::MockClient) do
      private

      def mock_return(args)
        case args[0]
        when "XINFO" then nil
        else super
        end
      end
    end.new

    result = nil_info_client.xinfo_stream("mystream")

    assert_empty(result)
  end
end
