# frozen_string_literal: true

require_relative "../unit_test_helper"

# Branch-coverage unit tests for RedisRuby::Commands::Probabilistic
# Uses a lightweight MockClient that includes the module directly
# and records every command sent through call / call_Nargs.
class ProbabilisticBranchTest < Minitest::Test
  # ------------------------------------------------------------------ mock --
  class MockClient
    include RedisRuby::Commands::Probabilistic
    attr_reader :last_command
    attr_accessor :next_return

    def call(*args)
      @last_command = args
      @next_return
    end

    def call_1arg(cmd, a)
      @last_command = [cmd, a]
      @next_return
    end

    def call_2args(cmd, a, b)
      @last_command = [cmd, a, b]
      @next_return
    end

    def call_3args(cmd, a, b, c)
      @last_command = [cmd, a, b, c]
      @next_return
    end
  end

  def setup
    @client = MockClient.new
  end

  # ============================================================
  # BLOOM FILTER
  # ============================================================

  # --- bf_reserve ---

  def test_bf_reserve_fast_path
    @client.bf_reserve("bf", 0.01, 1000)
    assert_equal ["BF.RESERVE", "bf", 0.01, 1000], @client.last_command
  end

  def test_bf_reserve_with_expansion
    @client.bf_reserve("bf", 0.01, 1000, expansion: 2)
    cmd = @client.last_command
    assert_equal "BF.RESERVE", cmd[0]
    idx = cmd.index("EXPANSION")
    refute_nil idx
    assert_equal 2, cmd[idx + 1]
  end

  def test_bf_reserve_with_nonscaling
    @client.bf_reserve("bf", 0.01, 1000, nonscaling: true)
    assert_includes @client.last_command, "NONSCALING"
  end

  def test_bf_reserve_with_expansion_and_nonscaling
    @client.bf_reserve("bf", 0.01, 1000, expansion: 4, nonscaling: true)
    cmd = @client.last_command
    assert_includes cmd, "EXPANSION"
    assert_includes cmd, "NONSCALING"
  end

  # --- bf_add ---

  def test_bf_add
    @client.next_return = 1
    result = @client.bf_add("bf", "item1")
    assert_equal 1, result
    assert_equal ["BF.ADD", "bf", "item1"], @client.last_command
  end

  # --- bf_madd ---

  def test_bf_madd
    @client.next_return = [1, 0, 1]
    result = @client.bf_madd("bf", "a", "b", "c")
    assert_equal [1, 0, 1], result
    assert_equal ["BF.MADD", "bf", "a", "b", "c"], @client.last_command
  end

  # --- bf_exists ---

  def test_bf_exists
    @client.next_return = 1
    result = @client.bf_exists("bf", "item1")
    assert_equal 1, result
    assert_equal ["BF.EXISTS", "bf", "item1"], @client.last_command
  end

  # --- bf_mexists ---

  def test_bf_mexists
    @client.next_return = [1, 0]
    result = @client.bf_mexists("bf", "a", "b")
    assert_equal [1, 0], result
    assert_equal ["BF.MEXISTS", "bf", "a", "b"], @client.last_command
  end

  # --- bf_insert ---

  def test_bf_insert_basic
    @client.next_return = [1, 1]
    result = @client.bf_insert("bf", "a", "b")
    assert_equal [1, 1], result
    cmd = @client.last_command
    assert_equal "BF.INSERT", cmd[0]
    assert_equal "bf", cmd[1]
    assert_includes cmd, "ITEMS"
    # Items should follow ITEMS
    idx = cmd.index("ITEMS")
    assert_equal "a", cmd[idx + 1]
    assert_equal "b", cmd[idx + 2]
  end

  def test_bf_insert_with_capacity
    @client.bf_insert("bf", "a", capacity: 5000)
    cmd = @client.last_command
    idx = cmd.index("CAPACITY")
    refute_nil idx
    assert_equal 5000, cmd[idx + 1]
  end

  def test_bf_insert_with_error
    @client.bf_insert("bf", "a", error: 0.001)
    cmd = @client.last_command
    idx = cmd.index("ERROR")
    refute_nil idx
    assert_in_delta 0.001, cmd[idx + 1]
  end

  def test_bf_insert_with_expansion
    @client.bf_insert("bf", "a", expansion: 4)
    cmd = @client.last_command
    idx = cmd.index("EXPANSION")
    refute_nil idx
    assert_equal 4, cmd[idx + 1]
  end

  def test_bf_insert_with_nocreate
    @client.bf_insert("bf", "a", nocreate: true)
    assert_includes @client.last_command, "NOCREATE"
  end

  def test_bf_insert_with_nonscaling
    @client.bf_insert("bf", "a", nonscaling: true)
    assert_includes @client.last_command, "NONSCALING"
  end

  def test_bf_insert_without_nocreate_nonscaling
    @client.bf_insert("bf", "a")
    refute_includes @client.last_command, "NOCREATE"
    refute_includes @client.last_command, "NONSCALING"
  end

  def test_bf_insert_all_options
    @client.bf_insert("bf", "a", "b", capacity: 1000, error: 0.01, expansion: 2, nocreate: true, nonscaling: true)
    cmd = @client.last_command
    assert_includes cmd, "CAPACITY"
    assert_includes cmd, "ERROR"
    assert_includes cmd, "EXPANSION"
    assert_includes cmd, "NOCREATE"
    assert_includes cmd, "NONSCALING"
    assert_includes cmd, "ITEMS"
  end

  # --- bf_info ---

  def test_bf_info
    @client.next_return = ["Capacity", 1000, "Size", 4096]
    result = @client.bf_info("bf")
    assert_equal({ "Capacity" => 1000, "Size" => 4096 }, result)
    assert_equal ["BF.INFO", "bf"], @client.last_command
  end

  # --- bf_card ---

  def test_bf_card
    @client.next_return = 42
    result = @client.bf_card("bf")
    assert_equal 42, result
    assert_equal ["BF.CARD", "bf"], @client.last_command
  end

  # --- bf_scandump ---

  def test_bf_scandump
    @client.next_return = [1, "data"]
    result = @client.bf_scandump("bf", 0)
    assert_equal [1, "data"], result
    assert_equal ["BF.SCANDUMP", "bf", 0], @client.last_command
  end

  # --- bf_loadchunk ---

  def test_bf_loadchunk
    @client.next_return = "OK"
    result = @client.bf_loadchunk("bf", 1, "data")
    assert_equal "OK", result
    assert_equal ["BF.LOADCHUNK", "bf", 1, "data"], @client.last_command
  end

  # ============================================================
  # CUCKOO FILTER
  # ============================================================

  # --- cf_reserve ---

  def test_cf_reserve_fast_path
    @client.cf_reserve("cf", 1000)
    assert_equal ["CF.RESERVE", "cf", 1000], @client.last_command
  end

  def test_cf_reserve_with_bucketsize
    @client.cf_reserve("cf", 1000, bucketsize: 4)
    cmd = @client.last_command
    assert_equal "CF.RESERVE", cmd[0]
    idx = cmd.index("BUCKETSIZE")
    refute_nil idx
    assert_equal 4, cmd[idx + 1]
  end

  def test_cf_reserve_with_maxiterations
    @client.cf_reserve("cf", 1000, maxiterations: 20)
    cmd = @client.last_command
    idx = cmd.index("MAXITERATIONS")
    refute_nil idx
    assert_equal 20, cmd[idx + 1]
  end

  def test_cf_reserve_with_expansion
    @client.cf_reserve("cf", 1000, expansion: 2)
    cmd = @client.last_command
    idx = cmd.index("EXPANSION")
    refute_nil idx
    assert_equal 2, cmd[idx + 1]
  end

  def test_cf_reserve_all_options
    @client.cf_reserve("cf", 1000, bucketsize: 4, maxiterations: 20, expansion: 2)
    cmd = @client.last_command
    assert_includes cmd, "BUCKETSIZE"
    assert_includes cmd, "MAXITERATIONS"
    assert_includes cmd, "EXPANSION"
  end

  # --- cf_add / cf_addnx ---

  def test_cf_add
    @client.next_return = 1
    result = @client.cf_add("cf", "item1")
    assert_equal 1, result
    assert_equal ["CF.ADD", "cf", "item1"], @client.last_command
  end

  def test_cf_addnx
    @client.next_return = 1
    result = @client.cf_addnx("cf", "item1")
    assert_equal 1, result
    assert_equal ["CF.ADDNX", "cf", "item1"], @client.last_command
  end

  # --- cf_exists / cf_mexists ---

  def test_cf_exists
    @client.next_return = 1
    result = @client.cf_exists("cf", "item1")
    assert_equal 1, result
    assert_equal ["CF.EXISTS", "cf", "item1"], @client.last_command
  end

  def test_cf_mexists
    @client.next_return = [1, 0]
    result = @client.cf_mexists("cf", "a", "b")
    assert_equal [1, 0], result
    assert_equal ["CF.MEXISTS", "cf", "a", "b"], @client.last_command
  end

  # --- cf_del ---

  def test_cf_del
    @client.next_return = 1
    result = @client.cf_del("cf", "item1")
    assert_equal 1, result
    assert_equal ["CF.DEL", "cf", "item1"], @client.last_command
  end

  # --- cf_count ---

  def test_cf_count
    @client.next_return = 3
    result = @client.cf_count("cf", "item1")
    assert_equal 3, result
    assert_equal ["CF.COUNT", "cf", "item1"], @client.last_command
  end

  # --- cf_insert ---

  def test_cf_insert_basic
    @client.next_return = [1, 1]
    result = @client.cf_insert("cf", "a", "b")
    assert_equal [1, 1], result
    cmd = @client.last_command
    assert_equal "CF.INSERT", cmd[0]
    assert_includes cmd, "ITEMS"
    idx = cmd.index("ITEMS")
    assert_equal "a", cmd[idx + 1]
    assert_equal "b", cmd[idx + 2]
  end

  def test_cf_insert_with_capacity
    @client.cf_insert("cf", "a", capacity: 5000)
    cmd = @client.last_command
    idx = cmd.index("CAPACITY")
    refute_nil idx
    assert_equal 5000, cmd[idx + 1]
  end

  def test_cf_insert_with_nocreate
    @client.cf_insert("cf", "a", nocreate: true)
    assert_includes @client.last_command, "NOCREATE"
  end

  def test_cf_insert_without_nocreate
    @client.cf_insert("cf", "a")
    refute_includes @client.last_command, "NOCREATE"
  end

  # --- cf_insertnx ---

  def test_cf_insertnx_basic
    @client.next_return = [1, 0]
    result = @client.cf_insertnx("cf", "a", "b")
    assert_equal [1, 0], result
    cmd = @client.last_command
    assert_equal "CF.INSERTNX", cmd[0]
    assert_includes cmd, "ITEMS"
  end

  def test_cf_insertnx_with_capacity
    @client.cf_insertnx("cf", "a", capacity: 5000)
    cmd = @client.last_command
    idx = cmd.index("CAPACITY")
    refute_nil idx
    assert_equal 5000, cmd[idx + 1]
  end

  def test_cf_insertnx_with_nocreate
    @client.cf_insertnx("cf", "a", nocreate: true)
    assert_includes @client.last_command, "NOCREATE"
  end

  def test_cf_insertnx_without_nocreate
    @client.cf_insertnx("cf", "a")
    refute_includes @client.last_command, "NOCREATE"
  end

  # --- cf_info ---

  def test_cf_info
    @client.next_return = ["Size", 1024, "Number of buckets", 512]
    result = @client.cf_info("cf")
    assert_equal({ "Size" => 1024, "Number of buckets" => 512 }, result)
    assert_equal ["CF.INFO", "cf"], @client.last_command
  end

  # --- cf_scandump / cf_loadchunk ---

  def test_cf_scandump
    @client.next_return = [1, "data"]
    result = @client.cf_scandump("cf", 0)
    assert_equal [1, "data"], result
    assert_equal ["CF.SCANDUMP", "cf", 0], @client.last_command
  end

  def test_cf_loadchunk
    @client.next_return = "OK"
    result = @client.cf_loadchunk("cf", 1, "data")
    assert_equal "OK", result
    assert_equal ["CF.LOADCHUNK", "cf", 1, "data"], @client.last_command
  end

  # ============================================================
  # COUNT-MIN SKETCH
  # ============================================================

  # --- cms_initbydim ---

  def test_cms_initbydim
    @client.next_return = "OK"
    result = @client.cms_initbydim("cms", 2000, 5)
    assert_equal "OK", result
    assert_equal ["CMS.INITBYDIM", "cms", 2000, 5], @client.last_command
  end

  # --- cms_initbyprob ---

  def test_cms_initbyprob
    @client.next_return = "OK"
    result = @client.cms_initbyprob("cms", 0.001, 0.01)
    assert_equal "OK", result
    assert_equal ["CMS.INITBYPROB", "cms", 0.001, 0.01], @client.last_command
  end

  # --- cms_incrby ---

  def test_cms_incrby
    @client.next_return = [5, 3]
    result = @client.cms_incrby("cms", "item1", 5, "item2", 3)
    assert_equal [5, 3], result
    assert_equal ["CMS.INCRBY", "cms", "item1", 5, "item2", 3], @client.last_command
  end

  # --- cms_query ---

  def test_cms_query
    @client.next_return = [5, 3]
    result = @client.cms_query("cms", "item1", "item2")
    assert_equal [5, 3], result
    assert_equal ["CMS.QUERY", "cms", "item1", "item2"], @client.last_command
  end

  # --- cms_merge ---

  def test_cms_merge_without_weights
    @client.next_return = "OK"
    result = @client.cms_merge("dest", "src1", "src2")
    assert_equal "OK", result
    assert_equal ["CMS.MERGE", "dest", 2, "src1", "src2"], @client.last_command
  end

  def test_cms_merge_with_weights
    @client.next_return = "OK"
    result = @client.cms_merge("dest", "src1", "src2", weights: [1, 2])
    assert_equal "OK", result
    cmd = @client.last_command
    assert_equal "CMS.MERGE", cmd[0]
    assert_equal "dest", cmd[1]
    assert_equal 2, cmd[2]
    assert_equal "src1", cmd[3]
    assert_equal "src2", cmd[4]
    assert_equal "WEIGHTS", cmd[5]
    assert_equal 1, cmd[6]
    assert_equal 2, cmd[7]
  end

  # --- cms_info ---

  def test_cms_info
    @client.next_return = ["width", 2000, "depth", 5, "count", 100]
    result = @client.cms_info("cms")
    assert_equal({ "width" => 2000, "depth" => 5, "count" => 100 }, result)
    assert_equal ["CMS.INFO", "cms"], @client.last_command
  end

  # ============================================================
  # TOP-K
  # ============================================================

  # --- topk_reserve ---

  def test_topk_reserve_fast_path
    @client.next_return = "OK"
    result = @client.topk_reserve("tk", 10)
    assert_equal "OK", result
    assert_equal ["TOPK.RESERVE", "tk", 10], @client.last_command
  end

  def test_topk_reserve_with_width_depth_decay
    @client.topk_reserve("tk", 10, width: 50, depth: 5, decay: 0.9)
    cmd = @client.last_command
    assert_equal "TOPK.RESERVE", cmd[0]
    assert_equal "tk", cmd[1]
    assert_equal 10, cmd[2]
    assert_equal 50, cmd[3]
    assert_equal 5, cmd[4]
    assert_in_delta 0.9, cmd[5]
  end

  def test_topk_reserve_with_partial_options
    @client.topk_reserve("tk", 10, width: 50)
    cmd = @client.last_command
    assert_equal "TOPK.RESERVE", cmd[0]
    assert_equal 50, cmd[3]
    # depth and decay are nil, so not appended
    assert_equal 4, cmd.length
  end

  # --- topk_add ---

  def test_topk_add
    @client.next_return = [nil, nil]
    result = @client.topk_add("tk", "a", "b")
    assert_equal [nil, nil], result
    assert_equal ["TOPK.ADD", "tk", "a", "b"], @client.last_command
  end

  # --- topk_incrby ---

  def test_topk_incrby
    @client.next_return = [nil, "old_item"]
    result = @client.topk_incrby("tk", "a", 5, "b", 3)
    assert_equal [nil, "old_item"], result
    assert_equal ["TOPK.INCRBY", "tk", "a", 5, "b", 3], @client.last_command
  end

  # --- topk_query ---

  def test_topk_query
    @client.next_return = [1, 0]
    result = @client.topk_query("tk", "a", "b")
    assert_equal [1, 0], result
    assert_equal ["TOPK.QUERY", "tk", "a", "b"], @client.last_command
  end

  # --- topk_count ---

  def test_topk_count
    @client.next_return = [10, 5]
    result = @client.topk_count("tk", "a", "b")
    assert_equal [10, 5], result
    assert_equal ["TOPK.COUNT", "tk", "a", "b"], @client.last_command
  end

  # --- topk_list ---

  def test_topk_list_fast_path
    @client.next_return = ["a", "b", "c"]
    result = @client.topk_list("tk")
    assert_equal ["a", "b", "c"], result
    assert_equal ["TOPK.LIST", "tk"], @client.last_command
  end

  def test_topk_list_with_withcount
    @client.next_return = ["a", 10, "b", 5]
    result = @client.topk_list("tk", withcount: true)
    assert_equal ["a", 10, "b", 5], result
    assert_equal ["TOPK.LIST", "tk", "WITHCOUNT"], @client.last_command
  end

  # --- topk_info ---

  def test_topk_info
    @client.next_return = ["k", 10, "width", 50, "depth", 5, "decay", 0.9]
    result = @client.topk_info("tk")
    assert_equal({ "k" => 10, "width" => 50, "depth" => 5, "decay" => 0.9 }, result)
    assert_equal ["TOPK.INFO", "tk"], @client.last_command
  end

  # ============================================================
  # T-DIGEST
  # ============================================================

  # --- tdigest_create ---

  def test_tdigest_create_fast_path
    @client.next_return = "OK"
    result = @client.tdigest_create("td")
    assert_equal "OK", result
    assert_equal ["TDIGEST.CREATE", "td"], @client.last_command
  end

  def test_tdigest_create_with_compression
    @client.next_return = "OK"
    result = @client.tdigest_create("td", compression: 500)
    assert_equal "OK", result
    assert_equal ["TDIGEST.CREATE", "td", "COMPRESSION", 500], @client.last_command
  end

  # --- tdigest_add ---

  def test_tdigest_add
    @client.next_return = "OK"
    result = @client.tdigest_add("td", 1.0, 2.0, 3.0)
    assert_equal "OK", result
    assert_equal ["TDIGEST.ADD", "td", 1.0, 2.0, 3.0], @client.last_command
  end

  # --- tdigest_reset ---

  def test_tdigest_reset
    @client.next_return = "OK"
    result = @client.tdigest_reset("td")
    assert_equal "OK", result
    assert_equal ["TDIGEST.RESET", "td"], @client.last_command
  end

  # --- tdigest_merge ---

  def test_tdigest_merge_basic
    @client.next_return = "OK"
    result = @client.tdigest_merge("dest", "src1", "src2")
    assert_equal "OK", result
    assert_equal ["TDIGEST.MERGE", "dest", 2, "src1", "src2"], @client.last_command
  end

  def test_tdigest_merge_with_compression
    @client.next_return = "OK"
    @client.tdigest_merge("dest", "src1", compression: 200)
    cmd = @client.last_command
    assert_equal "TDIGEST.MERGE", cmd[0]
    idx = cmd.index("COMPRESSION")
    refute_nil idx
    assert_equal 200, cmd[idx + 1]
  end

  def test_tdigest_merge_with_override
    @client.next_return = "OK"
    @client.tdigest_merge("dest", "src1", override: true)
    assert_includes @client.last_command, "OVERRIDE"
  end

  def test_tdigest_merge_without_override
    @client.next_return = "OK"
    @client.tdigest_merge("dest", "src1")
    refute_includes @client.last_command, "OVERRIDE"
  end

  def test_tdigest_merge_with_compression_and_override
    @client.tdigest_merge("dest", "src1", "src2", compression: 300, override: true)
    cmd = @client.last_command
    assert_includes cmd, "COMPRESSION"
    assert_includes cmd, "OVERRIDE"
    assert_equal 2, cmd[2]  # numkeys
  end

  # --- tdigest_quantile ---

  def test_tdigest_quantile
    @client.next_return = [1.5, 3.0]
    result = @client.tdigest_quantile("td", 0.5, 0.9)
    assert_equal [1.5, 3.0], result
    assert_equal ["TDIGEST.QUANTILE", "td", 0.5, 0.9], @client.last_command
  end

  # --- tdigest_rank ---

  def test_tdigest_rank
    @client.next_return = [5, 20]
    result = @client.tdigest_rank("td", 1.5, 3.0)
    assert_equal [5, 20], result
    assert_equal ["TDIGEST.RANK", "td", 1.5, 3.0], @client.last_command
  end

  # --- tdigest_revrank ---

  def test_tdigest_revrank
    @client.next_return = [15, 0]
    result = @client.tdigest_revrank("td", 1.5, 3.0)
    assert_equal [15, 0], result
    assert_equal ["TDIGEST.REVRANK", "td", 1.5, 3.0], @client.last_command
  end

  # --- tdigest_cdf ---

  def test_tdigest_cdf
    @client.next_return = [0.5, 0.9]
    result = @client.tdigest_cdf("td", 1.5, 3.0)
    assert_equal [0.5, 0.9], result
    assert_equal ["TDIGEST.CDF", "td", 1.5, 3.0], @client.last_command
  end

  # --- tdigest_trimmed_mean ---

  def test_tdigest_trimmed_mean
    @client.next_return = 2.5
    result = @client.tdigest_trimmed_mean("td", 0.1, 0.9)
    assert_in_delta 2.5, result
    assert_equal ["TDIGEST.TRIMMED_MEAN", "td", 0.1, 0.9], @client.last_command
  end

  # --- tdigest_min ---

  def test_tdigest_min
    @client.next_return = 0.5
    result = @client.tdigest_min("td")
    assert_in_delta 0.5, result
    assert_equal ["TDIGEST.MIN", "td"], @client.last_command
  end

  # --- tdigest_max ---

  def test_tdigest_max
    @client.next_return = 100.0
    result = @client.tdigest_max("td")
    assert_in_delta 100.0, result
    assert_equal ["TDIGEST.MAX", "td"], @client.last_command
  end

  # --- tdigest_info ---

  def test_tdigest_info
    @client.next_return = ["Compression", 100, "Capacity", 610, "Merged nodes", 5]
    result = @client.tdigest_info("td")
    assert_equal({ "Compression" => 100, "Capacity" => 610, "Merged nodes" => 5 }, result)
    assert_equal ["TDIGEST.INFO", "td"], @client.last_command
  end

  # --- tdigest_byrank ---

  def test_tdigest_byrank
    @client.next_return = [1.0, 2.0, 3.0]
    result = @client.tdigest_byrank("td", 0, 5, 10)
    assert_equal [1.0, 2.0, 3.0], result
    assert_equal ["TDIGEST.BYRANK", "td", 0, 5, 10], @client.last_command
  end

  # --- tdigest_byrevrank ---

  def test_tdigest_byrevrank
    @client.next_return = [10.0, 5.0, 1.0]
    result = @client.tdigest_byrevrank("td", 0, 5, 10)
    assert_equal [10.0, 5.0, 1.0], result
    assert_equal ["TDIGEST.BYREVRANK", "td", 0, 5, 10], @client.last_command
  end
end
