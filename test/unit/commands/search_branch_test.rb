# frozen_string_literal: true

require_relative "../unit_test_helper"

# Branch-coverage unit tests for RedisRuby::Commands::Search
# Uses a lightweight MockClient that includes the module directly
# and records every command sent through call / call_Nargs.
class SearchBranchTest < Minitest::Test
  # ------------------------------------------------------------------ mock --
  class MockClient
    include RedisRuby::Commands::Search

    attr_reader :last_command

    def call(*args)       = (@last_command = args)
    def call_1arg(cmd, a) = (@last_command = [cmd, a])
    def call_2args(cmd, a, b)       = (@last_command = [cmd, a, b])
    def call_3args(cmd, a, b, c)    = (@last_command = [cmd, a, b, c])
  end

  def setup
    @client = MockClient.new
  end

  # ============================================================
  # ft_create
  # ============================================================

  def test_ft_create_basic
    @client.ft_create("idx", "ON", "HASH", "SCHEMA", "title", "TEXT")

    assert_equal ["FT.CREATE", "idx", "ON", "HASH", "SCHEMA", "title", "TEXT"], @client.last_command
  end

  def test_ft_create_json_index
    @client.ft_create("idx", "ON", "JSON", "PREFIX", 1, "user:", "SCHEMA", "$.name", "AS", "name", "TEXT")

    assert_equal ["FT.CREATE", "idx", "ON", "JSON", "PREFIX", 1, "user:", "SCHEMA", "$.name", "AS", "name", "TEXT"],
                 @client.last_command
  end

  # ============================================================
  # ft_list
  # ============================================================

  def test_ft_list
    @client.ft_list

    assert_equal ["FT._LIST"], @client.last_command
  end

  # ============================================================
  # ft_info (converts array pairs to hash)
  # ============================================================

  def test_ft_info_converts_to_hash
    # Stub call_1arg to return array pairs
    mock = MockClient.new
    def mock.call_1arg(_cmd, _a)
      @last_command = [_cmd, _a]
      ["index_name", "idx", "num_docs", 42]
    end
    result = mock.ft_info("idx")

    assert_equal({ "index_name" => "idx", "num_docs" => 42 }, result)
    assert_equal ["FT.INFO", "idx"], mock.last_command
  end

  # ============================================================
  # ft_search -- exhaustive option testing
  # ============================================================

  def test_ft_search_basic
    @client.ft_search("idx", "hello world")

    assert_equal ["FT.SEARCH", "idx", "hello world"], @client.last_command
  end

  def test_ft_search_nocontent
    @client.ft_search("idx", "q", nocontent: true)

    assert_includes @client.last_command, "NOCONTENT"
  end

  def test_ft_search_verbatim
    @client.ft_search("idx", "q", verbatim: true)

    assert_includes @client.last_command, "VERBATIM"
  end

  def test_ft_search_nostopwords
    @client.ft_search("idx", "q", nostopwords: true)

    assert_includes @client.last_command, "NOSTOPWORDS"
  end

  def test_ft_search_inorder
    @client.ft_search("idx", "q", inorder: true)

    assert_includes @client.last_command, "INORDER"
  end

  def test_ft_search_withscores
    @client.ft_search("idx", "q", withscores: true)

    assert_includes @client.last_command, "WITHSCORES"
  end

  def test_ft_search_withpayloads
    @client.ft_search("idx", "q", withpayloads: true)

    assert_includes @client.last_command, "WITHPAYLOADS"
  end

  def test_ft_search_withsortkeys
    @client.ft_search("idx", "q", withsortkeys: true)

    assert_includes @client.last_command, "WITHSORTKEYS"
  end

  def test_ft_search_explainscore
    @client.ft_search("idx", "q", explainscore: true)

    assert_includes @client.last_command, "EXPLAINSCORE"
  end

  def test_ft_search_scorer
    @client.ft_search("idx", "q", scorer: "BM25")
    cmd = @client.last_command
    idx = cmd.index("SCORER")

    refute_nil idx
    assert_equal "BM25", cmd[idx + 1]
  end

  def test_ft_search_language
    @client.ft_search("idx", "q", language: "spanish")
    cmd = @client.last_command
    idx = cmd.index("LANGUAGE")

    refute_nil idx
    assert_equal "spanish", cmd[idx + 1]
  end

  def test_ft_search_slop
    @client.ft_search("idx", "q", slop: 2)
    cmd = @client.last_command
    idx = cmd.index("SLOP")

    refute_nil idx
    assert_equal 2, cmd[idx + 1]
  end

  def test_ft_search_filter_hash
    @client.ft_search("idx", "q", filter: { price: [10, 100] })
    cmd = @client.last_command
    idx = cmd.index("FILTER")

    refute_nil idx
    assert_equal "price", cmd[idx + 1]
    assert_equal 10, cmd[idx + 2]
    assert_equal 100, cmd[idx + 3]
  end

  def test_ft_search_geofilter_hash
    @client.ft_search("idx", "q", geofilter: { location: [-73.98, 40.73, 10, "mi"] })
    cmd = @client.last_command
    idx = cmd.index("GEOFILTER")

    refute_nil idx
    assert_equal "location", cmd[idx + 1]
    assert_in_delta(-73.98, cmd[idx + 2])
    assert_in_delta(40.73, cmd[idx + 3])
    assert_equal 10, cmd[idx + 4]
    assert_equal "mi", cmd[idx + 5]
  end

  def test_ft_search_geofilter_default_unit
    @client.ft_search("idx", "q", geofilter: { location: [-73.98, 40.73, 10, nil] })
    cmd = @client.last_command
    idx = cmd.index("GEOFILTER")
    # Default unit should be "km"
    assert_equal "km", cmd[idx + 5]
  end

  def test_ft_search_inkeys
    @client.ft_search("idx", "q", inkeys: ["doc:1", "doc:2"])
    cmd = @client.last_command
    idx = cmd.index("INKEYS")

    refute_nil idx
    assert_equal 2, cmd[idx + 1]
    assert_equal "doc:1", cmd[idx + 2]
    assert_equal "doc:2", cmd[idx + 3]
  end

  def test_ft_search_infields
    @client.ft_search("idx", "q", infields: %w[title body])
    cmd = @client.last_command
    idx = cmd.index("INFIELDS")

    refute_nil idx
    assert_equal 2, cmd[idx + 1]
    assert_equal "title", cmd[idx + 2]
    assert_equal "body", cmd[idx + 3]
  end

  def test_ft_search_return
    @client.ft_search("idx", "q", return: %w[title body])
    cmd = @client.last_command
    idx = cmd.index("RETURN")

    refute_nil idx
    assert_equal 2, cmd[idx + 1]
    assert_equal "title", cmd[idx + 2]
    assert_equal "body", cmd[idx + 3]
  end

  def test_ft_search_return_single_field
    @client.ft_search("idx", "q", return: "title")
    cmd = @client.last_command
    idx = cmd.index("RETURN")

    refute_nil idx
    assert_equal 1, cmd[idx + 1]
    assert_equal "title", cmd[idx + 2]
  end

  def test_ft_search_summarize_true
    @client.ft_search("idx", "q", summarize: true)

    assert_includes @client.last_command, "SUMMARIZE"
    # When summarize is just true (not a Hash), no extra sub-options
    refute_includes @client.last_command, "FIELDS"
    refute_includes @client.last_command, "FRAGS"
  end

  def test_ft_search_summarize_hash_with_fields
    @client.ft_search("idx", "q", summarize: { fields: %w[title body], frags: 3, len: 50, separator: "..." })
    cmd = @client.last_command

    assert_includes cmd, "SUMMARIZE"
    idx_f = cmd.index("FIELDS")

    refute_nil idx_f
    assert_equal 2, cmd[idx_f + 1]
    assert_equal "title", cmd[idx_f + 2]
    assert_equal "body", cmd[idx_f + 3]
    idx_fr = cmd.index("FRAGS")

    refute_nil idx_fr
    assert_equal 3, cmd[idx_fr + 1]
    idx_l = cmd.index("LEN")

    refute_nil idx_l
    assert_equal 50, cmd[idx_l + 1]
    idx_s = cmd.index("SEPARATOR")

    refute_nil idx_s
    assert_equal "...", cmd[idx_s + 1]
  end

  def test_ft_search_summarize_hash_without_optional_fields
    @client.ft_search("idx", "q", summarize: { frags: 2 })
    cmd = @client.last_command

    assert_includes cmd, "SUMMARIZE"
    refute_includes cmd, "FIELDS"
    idx = cmd.index("FRAGS")

    refute_nil idx
    assert_equal 2, cmd[idx + 1]
  end

  def test_ft_search_highlight_true
    @client.ft_search("idx", "q", highlight: true)

    assert_includes @client.last_command, "HIGHLIGHT"
    refute_includes @client.last_command, "FIELDS"
    refute_includes @client.last_command, "TAGS"
  end

  def test_ft_search_highlight_hash_with_fields_and_tags
    @client.ft_search("idx", "q", highlight: { fields: ["title"], tags: ["<b>", "</b>"] })
    cmd = @client.last_command

    assert_includes cmd, "HIGHLIGHT"
    idx_f = cmd.index("FIELDS")

    refute_nil idx_f
    assert_equal 1, cmd[idx_f + 1]
    assert_equal "title", cmd[idx_f + 2]
    idx_t = cmd.index("TAGS")

    refute_nil idx_t
    assert_equal "<b>", cmd[idx_t + 1]
    assert_equal "</b>", cmd[idx_t + 2]
  end

  def test_ft_search_highlight_hash_without_tags
    @client.ft_search("idx", "q", highlight: { fields: ["title"] })
    cmd = @client.last_command

    assert_includes cmd, "HIGHLIGHT"
    assert_includes cmd, "FIELDS"
    refute_includes cmd, "TAGS"
  end

  def test_ft_search_highlight_hash_empty
    @client.ft_search("idx", "q", highlight: {})
    cmd = @client.last_command

    assert_includes cmd, "HIGHLIGHT"
    refute_includes cmd, "FIELDS"
    refute_includes cmd, "TAGS"
  end

  def test_ft_search_sortby_asc
    @client.ft_search("idx", "q", sortby: "timestamp", sortasc: true)
    cmd = @client.last_command
    idx = cmd.index("SORTBY")

    refute_nil idx
    assert_equal "timestamp", cmd[idx + 1]
    assert_equal "ASC", cmd[idx + 2]
  end

  def test_ft_search_sortby_desc
    @client.ft_search("idx", "q", sortby: "timestamp", sortasc: false)
    cmd = @client.last_command
    idx = cmd.index("SORTBY")

    refute_nil idx
    assert_equal "timestamp", cmd[idx + 1]
    assert_equal "DESC", cmd[idx + 2]
  end

  def test_ft_search_sortby_default_asc
    @client.ft_search("idx", "q", sortby: "timestamp")
    cmd = @client.last_command
    idx = cmd.index("SORTBY")

    refute_nil idx
    assert_equal "ASC", cmd[idx + 2]
  end

  def test_ft_search_limit
    @client.ft_search("idx", "q", limit: [0, 20])
    cmd = @client.last_command
    idx = cmd.index("LIMIT")

    refute_nil idx
    assert_equal 0, cmd[idx + 1]
    assert_equal 20, cmd[idx + 2]
  end

  def test_ft_search_params
    @client.ft_search("idx", "q", params: { vec: "blob", k: "10" })
    cmd = @client.last_command
    idx = cmd.index("PARAMS")

    refute_nil idx
    assert_equal 4, cmd[idx + 1] # 2 params * 2
    assert_includes cmd, "vec"
    assert_includes cmd, "blob"
    assert_includes cmd, "k"
    assert_includes cmd, "10"
  end

  def test_ft_search_dialect
    @client.ft_search("idx", "q", dialect: 3)
    cmd = @client.last_command
    idx = cmd.index("DIALECT")

    refute_nil idx
    assert_equal 3, cmd[idx + 1]
  end

  def test_ft_search_timeout
    @client.ft_search("idx", "q", timeout: 5000)
    cmd = @client.last_command
    idx = cmd.index("TIMEOUT")

    refute_nil idx
    assert_equal 5000, cmd[idx + 1]
  end

  def test_ft_search_combined_options
    @client.ft_search("idx", "q",
                      nocontent: true,
                      verbatim: true,
                      withscores: true,
                      scorer: "TFIDF",
                      limit: [0, 5],
                      dialect: 2)
    cmd = @client.last_command

    assert_includes cmd, "NOCONTENT"
    assert_includes cmd, "VERBATIM"
    assert_includes cmd, "WITHSCORES"
    assert_includes cmd, "SCORER"
    assert_includes cmd, "LIMIT"
    assert_includes cmd, "DIALECT"
  end

  # ============================================================
  # ft_aggregate
  # ============================================================

  def test_ft_aggregate
    @client.ft_aggregate("idx", "*", "GROUPBY", 1, "@category", "REDUCE", "COUNT", 0, "AS", "cnt")

    assert_equal ["FT.AGGREGATE", "idx", "*", "GROUPBY", 1, "@category", "REDUCE", "COUNT", 0, "AS", "cnt"],
                 @client.last_command
  end

  # ============================================================
  # ft_cursor_read
  # ============================================================

  def test_ft_cursor_read_fast_path
    @client.ft_cursor_read("idx", 12_345)

    assert_equal ["FT.CURSOR", "READ", "idx", 12_345], @client.last_command
  end

  def test_ft_cursor_read_with_count
    @client.ft_cursor_read("idx", 12_345, count: 100)

    assert_equal ["FT.CURSOR", "READ", "idx", 12_345, "COUNT", 100], @client.last_command
  end

  # ============================================================
  # ft_cursor_del
  # ============================================================

  def test_ft_cursor_del
    @client.ft_cursor_del("idx", 12_345)

    assert_equal ["FT.CURSOR", "DEL", "idx", 12_345], @client.last_command
  end

  # ============================================================
  # ft_dropindex
  # ============================================================

  def test_ft_dropindex_fast_path
    @client.ft_dropindex("idx")

    assert_equal ["FT.DROPINDEX", "idx"], @client.last_command
  end

  def test_ft_dropindex_with_delete_docs
    @client.ft_dropindex("idx", delete_docs: true)

    assert_equal ["FT.DROPINDEX", "idx", "DD"], @client.last_command
  end

  # ============================================================
  # ft_alter
  # ============================================================

  def test_ft_alter
    @client.ft_alter("idx", "SCHEMA", "ADD", "new_field", "TEXT")

    assert_equal ["FT.ALTER", "idx", "SCHEMA", "ADD", "new_field", "TEXT"], @client.last_command
  end

  # ============================================================
  # ft_aliasadd / ft_aliasupdate / ft_aliasdel
  # ============================================================

  def test_ft_aliasadd
    @client.ft_aliasadd("myalias", "idx")

    assert_equal ["FT.ALIASADD", "myalias", "idx"], @client.last_command
  end

  def test_ft_aliasupdate
    @client.ft_aliasupdate("myalias", "idx2")

    assert_equal ["FT.ALIASUPDATE", "myalias", "idx2"], @client.last_command
  end

  def test_ft_aliasdel
    @client.ft_aliasdel("myalias")

    assert_equal ["FT.ALIASDEL", "myalias"], @client.last_command
  end

  # ============================================================
  # ft_explain
  # ============================================================

  def test_ft_explain_fast_path
    @client.ft_explain("idx", "hello")

    assert_equal ["FT.EXPLAIN", "idx", "hello"], @client.last_command
  end

  def test_ft_explain_with_dialect
    @client.ft_explain("idx", "hello", dialect: 2)

    assert_equal ["FT.EXPLAIN", "idx", "hello", "DIALECT", 2], @client.last_command
  end

  # ============================================================
  # ft_explaincli
  # ============================================================

  def test_ft_explaincli_fast_path
    @client.ft_explaincli("idx", "hello")

    assert_equal ["FT.EXPLAINCLI", "idx", "hello"], @client.last_command
  end

  def test_ft_explaincli_with_dialect
    @client.ft_explaincli("idx", "hello", dialect: 3)

    assert_equal ["FT.EXPLAINCLI", "idx", "hello", "DIALECT", 3], @client.last_command
  end

  # ============================================================
  # ft_profile
  # ============================================================

  def test_ft_profile_basic
    @client.ft_profile("idx", "SEARCH", "hello world")

    assert_equal ["FT.PROFILE", "idx", "SEARCH", "QUERY", "hello world"], @client.last_command
  end

  def test_ft_profile_with_limited
    @client.ft_profile("idx", "SEARCH", "hello", limited: true)

    assert_equal ["FT.PROFILE", "idx", "SEARCH", "LIMITED", "QUERY", "hello"], @client.last_command
  end

  def test_ft_profile_aggregate
    @client.ft_profile("idx", :aggregate, "*", "GROUPBY", 1, "@cat")

    assert_equal ["FT.PROFILE", "idx", "AGGREGATE", "QUERY", "*", "GROUPBY", 1, "@cat"],
                 @client.last_command
  end

  # ============================================================
  # ft_spellcheck
  # ============================================================

  def test_ft_spellcheck_fast_path
    @client.ft_spellcheck("idx", "helo wrld")

    assert_equal ["FT.SPELLCHECK", "idx", "helo wrld"], @client.last_command
  end

  def test_ft_spellcheck_with_distance
    @client.ft_spellcheck("idx", "helo", distance: 2)
    cmd = @client.last_command

    assert_equal "FT.SPELLCHECK", cmd[0]
    idx = cmd.index("DISTANCE")

    refute_nil idx
    assert_equal 2, cmd[idx + 1]
  end

  def test_ft_spellcheck_with_include
    @client.ft_spellcheck("idx", "helo", include: "custom_dict")
    cmd = @client.last_command
    idx = cmd.index("TERMS")

    refute_nil idx
    assert_equal "INCLUDE", cmd[idx + 1]
    assert_equal "custom_dict", cmd[idx + 2]
  end

  def test_ft_spellcheck_with_exclude
    @client.ft_spellcheck("idx", "helo", exclude: "stopwords")
    cmd = @client.last_command
    idx = cmd.index("TERMS")

    refute_nil idx
    assert_equal "EXCLUDE", cmd[idx + 1]
    assert_equal "stopwords", cmd[idx + 2]
  end

  def test_ft_spellcheck_with_dialect
    @client.ft_spellcheck("idx", "helo", dialect: 2)
    cmd = @client.last_command
    idx = cmd.index("DIALECT")

    refute_nil idx
    assert_equal 2, cmd[idx + 1]
  end

  def test_ft_spellcheck_combined_options
    @client.ft_spellcheck("idx", "helo", distance: 2, include: "dict1", exclude: "dict2", dialect: 3)
    cmd = @client.last_command

    assert_includes cmd, "DISTANCE"
    # Two TERMS entries
    terms_indices = cmd.each_index.select { |i| cmd[i] == "TERMS" }

    assert_equal 2, terms_indices.size
    assert_includes cmd, "INCLUDE"
    assert_includes cmd, "EXCLUDE"
    assert_includes cmd, "DIALECT"
  end

  # ============================================================
  # ft_tagvals
  # ============================================================

  def test_ft_tagvals
    @client.ft_tagvals("idx", "category")

    assert_equal ["FT.TAGVALS", "idx", "category"], @client.last_command
  end

  # ============================================================
  # ft_syndump
  # ============================================================

  def test_ft_syndump
    mock = MockClient.new
    def mock.call_1arg(_cmd, _a)
      @last_command = [_cmd, _a]
      ["hello", ["group1"], "world", ["group1"]]
    end
    result = mock.ft_syndump("idx")

    assert_equal({ "hello" => ["group1"], "world" => ["group1"] }, result)
  end

  # ============================================================
  # ft_synupdate
  # ============================================================

  def test_ft_synupdate
    @client.ft_synupdate("idx", "group1", "hello", "hi", "hey")

    assert_equal ["FT.SYNUPDATE", "idx", "group1", "hello", "hi", "hey"], @client.last_command
  end

  def test_ft_synupdate_with_skipinitialscan
    @client.ft_synupdate("idx", "group1", "hello", "hi", skipinitialscan: true)
    cmd = @client.last_command

    assert_equal "FT.SYNUPDATE", cmd[0]
    assert_includes cmd, "SKIPINITIALSCAN"
    assert_includes cmd, "hello"
    assert_includes cmd, "hi"
  end

  def test_ft_synupdate_without_skipinitialscan
    @client.ft_synupdate("idx", "group1", "hello", "hi", skipinitialscan: false)

    refute_includes @client.last_command, "SKIPINITIALSCAN"
  end

  # ============================================================
  # ft_dictadd / ft_dictdel / ft_dictdump
  # ============================================================

  def test_ft_dictadd
    @client.ft_dictadd("mydict", "word1", "word2")

    assert_equal ["FT.DICTADD", "mydict", "word1", "word2"], @client.last_command
  end

  def test_ft_dictdel
    @client.ft_dictdel("mydict", "word1", "word2")

    assert_equal ["FT.DICTDEL", "mydict", "word1", "word2"], @client.last_command
  end

  def test_ft_dictdump
    @client.ft_dictdump("mydict")

    assert_equal ["FT.DICTDUMP", "mydict"], @client.last_command
  end

  # ============================================================
  # ft_sugadd
  # ============================================================

  def test_ft_sugadd_fast_path
    @client.ft_sugadd("sug", "hello", 1.0)

    assert_equal ["FT.SUGADD", "sug", "hello", 1.0], @client.last_command
  end

  def test_ft_sugadd_with_incr
    @client.ft_sugadd("sug", "hello", 1.0, incr: true)
    cmd = @client.last_command

    assert_equal "FT.SUGADD", cmd[0]
    assert_includes cmd, "INCR"
  end

  def test_ft_sugadd_with_payload
    @client.ft_sugadd("sug", "hello", 1.0, payload: "extra")
    cmd = @client.last_command

    assert_equal "FT.SUGADD", cmd[0]
    idx = cmd.index("PAYLOAD")

    refute_nil idx
    assert_equal "extra", cmd[idx + 1]
  end

  def test_ft_sugadd_with_incr_and_payload
    @client.ft_sugadd("sug", "hello", 1.0, incr: true, payload: "data")
    cmd = @client.last_command

    assert_includes cmd, "INCR"
    assert_includes cmd, "PAYLOAD"
  end

  # ============================================================
  # ft_sugget
  # ============================================================

  def test_ft_sugget_fast_path
    @client.ft_sugget("sug", "hel")

    assert_equal ["FT.SUGGET", "sug", "hel"], @client.last_command
  end

  def test_ft_sugget_with_fuzzy
    @client.ft_sugget("sug", "hel", fuzzy: true)

    assert_includes @client.last_command, "FUZZY"
  end

  def test_ft_sugget_with_withscores
    @client.ft_sugget("sug", "hel", withscores: true)

    assert_includes @client.last_command, "WITHSCORES"
  end

  def test_ft_sugget_with_withpayloads
    @client.ft_sugget("sug", "hel", withpayloads: true)

    assert_includes @client.last_command, "WITHPAYLOADS"
  end

  def test_ft_sugget_with_max
    @client.ft_sugget("sug", "hel", max: 5)
    cmd = @client.last_command
    idx = cmd.index("MAX")

    refute_nil idx
    assert_equal 5, cmd[idx + 1]
  end

  def test_ft_sugget_all_options
    @client.ft_sugget("sug", "hel", fuzzy: true, withscores: true, withpayloads: true, max: 10)
    cmd = @client.last_command

    assert_includes cmd, "FUZZY"
    assert_includes cmd, "WITHSCORES"
    assert_includes cmd, "WITHPAYLOADS"
    assert_includes cmd, "MAX"
  end

  # ============================================================
  # ft_suglen / ft_sugdel
  # ============================================================

  def test_ft_suglen
    @client.ft_suglen("sug")

    assert_equal ["FT.SUGLEN", "sug"], @client.last_command
  end

  def test_ft_sugdel
    @client.ft_sugdel("sug", "hello")

    assert_equal ["FT.SUGDEL", "sug", "hello"], @client.last_command
  end

  # ============================================================
  # ft_config_get / ft_config_set
  # ============================================================

  def test_ft_config_get_default
    mock = MockClient.new
    def mock.call_2args(_cmd, _sub, _opt)
      @last_command = [_cmd, _sub, _opt]
      [%w[TIMEOUT 500]]
    end
    result = mock.ft_config_get

    assert_equal ["FT.CONFIG", "GET", "*"], mock.last_command
    assert_instance_of Hash, result
  end

  def test_ft_config_get_specific
    mock = MockClient.new
    def mock.call_2args(_cmd, _sub, _opt)
      @last_command = [_cmd, _sub, _opt]
      [%w[TIMEOUT 500]]
    end
    mock.ft_config_get("TIMEOUT")

    assert_equal ["FT.CONFIG", "GET", "TIMEOUT"], mock.last_command
  end

  def test_ft_config_set
    @client.ft_config_set("TIMEOUT", "500")

    assert_equal ["FT.CONFIG", "SET", "TIMEOUT", "500"], @client.last_command
  end

  # ============================================================
  # Private helpers -- verify indirectly via ft_search
  # ============================================================

  def test_build_search_filters_no_filter
    # No filter or geofilter -- no crash
    @client.ft_search("idx", "q")

    refute_includes @client.last_command, "FILTER"
    refute_includes @client.last_command, "GEOFILTER"
  end

  def test_build_search_filters_no_geofilter
    @client.ft_search("idx", "q", filter: { price: [0, 100] })

    assert_includes @client.last_command, "FILTER"
    refute_includes @client.last_command, "GEOFILTER"
  end

  def test_build_search_no_inkeys_infields_return
    @client.ft_search("idx", "q")

    refute_includes @client.last_command, "INKEYS"
    refute_includes @client.last_command, "INFIELDS"
    refute_includes @client.last_command, "RETURN"
  end

  def test_build_search_no_summarize_highlight
    @client.ft_search("idx", "q")

    refute_includes @client.last_command, "SUMMARIZE"
    refute_includes @client.last_command, "HIGHLIGHT"
  end

  def test_build_search_no_sort_no_limit
    @client.ft_search("idx", "q")

    refute_includes @client.last_command, "SORTBY"
    refute_includes @client.last_command, "LIMIT"
  end

  def test_build_search_no_params_dialect_timeout
    @client.ft_search("idx", "q")

    refute_includes @client.last_command, "PARAMS"
    refute_includes @client.last_command, "DIALECT"
    refute_includes @client.last_command, "TIMEOUT"
  end

  def test_ft_search_multiple_filters
    @client.ft_search("idx", "q", filter: { price: [0, 100], rating: [3, 5] })
    cmd = @client.last_command
    filter_indices = cmd.each_index.select { |i| cmd[i] == "FILTER" }

    assert_equal 2, filter_indices.size
  end
end
