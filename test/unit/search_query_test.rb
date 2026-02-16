# frozen_string_literal: true

require_relative "unit_test_helper"

# Comprehensive branch-coverage tests for RR::Search::Query,
# RR::Search::AggregateQuery, and RR::Search::Reducer.
#
# Covers every conditional branch in lib/redis_ruby/search/query.rb.
class SearchQueryTest < Minitest::Test
  # ==================================================================
  # Query - initialization and defaults
  # ==================================================================

  def test_default_query_string
    q = RR::Search::Query.new

    assert_equal "*", q.query_string
    assert_equal "*", q.to_s
  end

  def test_custom_query_string
    q = RR::Search::Query.new("hello world")

    assert_equal "hello world", q.query_string
    assert_equal "hello world", q.to_s
  end

  def test_default_options
    q = RR::Search::Query.new
    opts = q.options

    # Default limit
    assert_equal [0, 10], opts[:limit]

    # No optional keys present by default
    refute opts.key?(:return)
    refute opts.key?(:sortby)
    refute opts.key?(:sortby_order)
    refute opts.key?(:highlight)
    refute opts.key?(:summarize)
    refute opts.key?(:params)
    refute opts.key?(:dialect)
    refute opts.key?(:verbatim)
    refute opts.key?(:nocontent)
    refute opts.key?(:nostopwords)
    refute opts.key?(:withscores)
    refute opts.key?(:withpayloads)
    refute opts.key?(:withsortkeys)
    refute opts.key?(:scorer)
    refute opts.key?(:expander)
    refute opts.key?(:slop)
    refute opts.key?(:inorder)
    refute opts.key?(:language)
    refute opts.key?(:geofilter)
  end

  # ==================================================================
  # Query - filter_numeric
  # ==================================================================

  def test_filter_numeric_single
    q = RR::Search::Query.new("hello")
      .filter_numeric("price", 10, 100)

    assert_equal "hello @price:[10 100]", q.to_s
  end

  def test_filter_numeric_with_inf
    q = RR::Search::Query.new("*")
      .filter_numeric("score", "-inf", "+inf")

    assert_equal "* @score:[-inf +inf]", q.to_s
  end

  def test_filter_numeric_multiple
    q = RR::Search::Query.new("*")
      .filter_numeric("price", 0, 50)
      .filter_numeric("rating", 3, 5)

    assert_equal "* @price:[0 50] @rating:[3 5]", q.to_s
  end

  def test_filter_numeric_returns_self
    q = RR::Search::Query.new
    result = q.filter_numeric("f", 0, 10)

    assert_same q, result
  end

  # ==================================================================
  # Query - filter_tag
  # ==================================================================

  def test_filter_tag_single_value
    q = RR::Search::Query.new("*")
      .filter_tag("category", "electronics")

    assert_equal "* @category:{electronics}", q.to_s
  end

  def test_filter_tag_multiple_values
    q = RR::Search::Query.new("*")
      .filter_tag("category", "electronics", "books")

    assert_equal "* @category:{electronics | books}", q.to_s
  end

  def test_filter_tag_with_spaces_in_value
    q = RR::Search::Query.new("*")
      .filter_tag("category", "home appliances", "books")

    # Values with spaces should be quoted
    assert_equal '* @category:{"home appliances" | books}', q.to_s
  end

  def test_filter_tag_with_array_argument
    q = RR::Search::Query.new("*")
      .filter_tag("status", %w[active pending])

    assert_equal "* @status:{active | pending}", q.to_s
  end

  def test_filter_tag_returns_self
    q = RR::Search::Query.new
    result = q.filter_tag("f", "v")

    assert_same q, result
  end

  # ==================================================================
  # Query - mixed filter types (numeric + tag)
  # ==================================================================

  def test_mixed_filters_in_to_s
    q = RR::Search::Query.new("hello")
      .filter_numeric("price", 10, 100)
      .filter_tag("category", "electronics")

    assert_equal "hello @price:[10 100] @category:{electronics}", q.to_s
  end

  # ==================================================================
  # Query - filter_geo
  # ==================================================================

  def test_filter_geo_default_unit
    q = RR::Search::Query.new("*")
      .filter_geo("location", -73.98, 40.73, 10)

    opts = q.options

    assert_equal ["location", -73.98, 40.73, 10, "km"], opts[:geofilter]
  end

  def test_filter_geo_custom_unit
    q = RR::Search::Query.new("*")
      .filter_geo("location", -73.98, 40.73, 5, unit: :mi)

    opts = q.options

    assert_equal ["location", -73.98, 40.73, 5, "mi"], opts[:geofilter]
  end

  def test_filter_geo_returns_self
    q = RR::Search::Query.new
    result = q.filter_geo("f", 0.0, 0.0, 1)

    assert_same q, result
  end

  def test_no_geo_filter_by_default
    q = RR::Search::Query.new

    refute q.options.key?(:geofilter)
  end

  # ==================================================================
  # Query - return_fields
  # ==================================================================

  def test_return_fields_multiple
    q = RR::Search::Query.new
      .return_fields("title", "body")

    opts = q.options

    assert_equal %w[title body], opts[:return]
  end

  def test_return_fields_with_array
    q = RR::Search::Query.new
      .return_fields(%w[title body author])

    opts = q.options

    assert_equal %w[title body author], opts[:return]
  end

  def test_return_fields_not_set_by_default
    q = RR::Search::Query.new

    refute q.options.key?(:return)
  end

  def test_return_fields_returns_self
    q = RR::Search::Query.new
    result = q.return_fields("f")

    assert_same q, result
  end

  # ==================================================================
  # Query - sort_by
  # ==================================================================

  def test_sort_by_default_asc
    q = RR::Search::Query.new.sort_by("price")

    opts = q.options

    assert_equal "price", opts[:sortby]
    assert_equal :asc, opts[:sortby_order]
  end

  def test_sort_by_desc
    q = RR::Search::Query.new.sort_by("price", :desc)

    opts = q.options

    assert_equal "price", opts[:sortby]
    assert_equal :desc, opts[:sortby_order]
  end

  def test_sort_by_not_set_by_default
    q = RR::Search::Query.new
    opts = q.options

    refute opts.key?(:sortby)
    refute opts.key?(:sortby_order)
  end

  def test_sort_by_returns_self
    q = RR::Search::Query.new
    result = q.sort_by("f")

    assert_same q, result
  end

  # ==================================================================
  # Query - limit and paginate
  # ==================================================================

  def test_limit
    q = RR::Search::Query.new.limit(20, 50)

    assert_equal [20, 50], q.options[:limit]
  end

  def test_limit_returns_self
    q = RR::Search::Query.new
    result = q.limit(0, 10)

    assert_same q, result
  end

  def test_paginate
    q = RR::Search::Query.new.paginate(2, 25)
    # page 2, 25 per page => offset=50, num=25
    assert_equal [50, 25], q.options[:limit]
  end

  def test_paginate_first_page
    q = RR::Search::Query.new.paginate(0, 10)

    assert_equal [0, 10], q.options[:limit]
  end

  # ==================================================================
  # Query - highlight
  # ==================================================================

  def test_highlight_defaults
    q = RR::Search::Query.new.highlight

    opts = q.options

    assert opts[:highlight]
    assert_nil opts[:highlight_fields]
    assert_equal ["<b>", "</b>"], opts[:highlight_tags]
  end

  def test_highlight_with_fields
    q = RR::Search::Query.new
      .highlight(fields: %w[title body])

    opts = q.options

    assert opts[:highlight]
    assert_equal %w[title body], opts[:highlight_fields]
  end

  def test_highlight_with_custom_tags
    q = RR::Search::Query.new
      .highlight(tags: ["<em>", "</em>"])

    opts = q.options

    assert_equal ["<em>", "</em>"], opts[:highlight_tags]
  end

  def test_highlight_with_nil_fields
    q = RR::Search::Query.new
      .highlight(fields: nil)

    opts = q.options

    assert opts[:highlight]
    refute opts.key?(:highlight_fields)
  end

  def test_highlight_not_set_by_default
    q = RR::Search::Query.new

    refute q.options.key?(:highlight)
  end

  def test_highlight_returns_self
    q = RR::Search::Query.new
    result = q.highlight

    assert_same q, result
  end

  # ==================================================================
  # Query - summarize
  # ==================================================================

  def test_summarize_defaults
    q = RR::Search::Query.new.summarize

    opts = q.options

    assert opts[:summarize]
    assert_nil opts[:summarize_fields]
    assert_equal 3, opts[:summarize_frags]
    assert_equal 20, opts[:summarize_len]
    assert_equal "...", opts[:summarize_separator]
  end

  def test_summarize_with_fields
    q = RR::Search::Query.new
      .summarize(fields: ["body"])

    opts = q.options

    assert opts[:summarize]
    assert_equal ["body"], opts[:summarize_fields]
  end

  def test_summarize_with_custom_options
    q = RR::Search::Query.new
      .summarize(frags: 5, len: 50, separator: " --- ")

    opts = q.options

    assert_equal 5, opts[:summarize_frags]
    assert_equal 50, opts[:summarize_len]
    assert_equal " --- ", opts[:summarize_separator]
  end

  def test_summarize_with_nil_fields
    q = RR::Search::Query.new
      .summarize(fields: nil)

    opts = q.options

    assert opts[:summarize]
    refute opts.key?(:summarize_fields)
  end

  def test_summarize_not_set_by_default
    q = RR::Search::Query.new

    refute q.options.key?(:summarize)
  end

  def test_summarize_returns_self
    q = RR::Search::Query.new
    result = q.summarize

    assert_same q, result
  end

  # ==================================================================
  # Query - params
  # ==================================================================

  def test_params
    q = RR::Search::Query.new
      .params(vec: "blob", k: "10")

    opts = q.options

    assert_equal({ vec: "blob", k: "10" }, opts[:params])
  end

  def test_params_merge
    q = RR::Search::Query.new
      .params(a: 1)
      .params(b: 2)

    opts = q.options

    assert_equal({ a: 1, b: 2 }, opts[:params])
  end

  def test_params_not_set_by_default
    q = RR::Search::Query.new

    refute q.options.key?(:params)
  end

  def test_params_returns_self
    q = RR::Search::Query.new
    result = q.params(a: 1)

    assert_same q, result
  end

  # ==================================================================
  # Query - dialect
  # ==================================================================

  def test_dialect
    q = RR::Search::Query.new.dialect(2)

    assert_equal 2, q.options[:dialect]
  end

  def test_dialect_not_set_by_default
    q = RR::Search::Query.new

    refute q.options.key?(:dialect)
  end

  def test_dialect_returns_self
    q = RR::Search::Query.new
    result = q.dialect(3)

    assert_same q, result
  end

  # ==================================================================
  # Query - boolean flags
  # ==================================================================

  def test_verbatim
    q = RR::Search::Query.new.verbatim

    assert q.options[:verbatim]
  end

  def test_verbatim_not_set_by_default
    q = RR::Search::Query.new

    refute q.options.key?(:verbatim)
  end

  def test_verbatim_returns_self
    q = RR::Search::Query.new
    result = q.verbatim

    assert_same q, result
  end

  def test_no_content
    q = RR::Search::Query.new.no_content

    assert q.options[:nocontent]
  end

  def test_no_content_not_set_by_default
    q = RR::Search::Query.new

    refute q.options.key?(:nocontent)
  end

  def test_no_content_returns_self
    q = RR::Search::Query.new
    result = q.no_content

    assert_same q, result
  end

  def test_no_stopwords
    q = RR::Search::Query.new.no_stopwords

    assert q.options[:nostopwords]
  end

  def test_no_stopwords_not_set_by_default
    q = RR::Search::Query.new

    refute q.options.key?(:nostopwords)
  end

  def test_no_stopwords_returns_self
    q = RR::Search::Query.new
    result = q.no_stopwords

    assert_same q, result
  end

  def test_with_scores
    q = RR::Search::Query.new.with_scores

    assert q.options[:withscores]
  end

  def test_with_scores_not_set_by_default
    q = RR::Search::Query.new

    refute q.options.key?(:withscores)
  end

  def test_with_scores_returns_self
    q = RR::Search::Query.new
    result = q.with_scores

    assert_same q, result
  end

  def test_with_payloads
    q = RR::Search::Query.new.with_payloads

    assert q.options[:withpayloads]
  end

  def test_with_payloads_not_set_by_default
    q = RR::Search::Query.new

    refute q.options.key?(:withpayloads)
  end

  def test_with_payloads_returns_self
    q = RR::Search::Query.new
    result = q.with_payloads

    assert_same q, result
  end

  def test_with_sort_keys
    q = RR::Search::Query.new.with_sort_keys

    assert q.options[:withsortkeys]
  end

  def test_with_sort_keys_not_set_by_default
    q = RR::Search::Query.new

    refute q.options.key?(:withsortkeys)
  end

  def test_with_sort_keys_returns_self
    q = RR::Search::Query.new
    result = q.with_sort_keys

    assert_same q, result
  end

  def test_in_order
    q = RR::Search::Query.new.in_order

    assert q.options[:inorder]
  end

  def test_in_order_not_set_by_default
    q = RR::Search::Query.new

    refute q.options.key?(:inorder)
  end

  def test_in_order_returns_self
    q = RR::Search::Query.new
    result = q.in_order

    assert_same q, result
  end

  # ==================================================================
  # Query - scorer
  # ==================================================================

  def test_scorer
    q = RR::Search::Query.new.scorer("BM25")

    assert_equal "BM25", q.options[:scorer]
  end

  def test_scorer_not_set_by_default
    q = RR::Search::Query.new

    refute q.options.key?(:scorer)
  end

  def test_scorer_returns_self
    q = RR::Search::Query.new
    result = q.scorer("BM25")

    assert_same q, result
  end

  # ==================================================================
  # Query - expander
  # ==================================================================

  def test_expander
    q = RR::Search::Query.new.expander("my_expander")

    assert_equal "my_expander", q.options[:expander]
  end

  def test_expander_not_set_by_default
    q = RR::Search::Query.new

    refute q.options.key?(:expander)
  end

  def test_expander_returns_self
    q = RR::Search::Query.new
    result = q.expander("x")

    assert_same q, result
  end

  # ==================================================================
  # Query - slop
  # ==================================================================

  def test_slop
    q = RR::Search::Query.new.slop(3)

    assert_equal 3, q.options[:slop]
  end

  def test_slop_not_set_by_default
    q = RR::Search::Query.new

    refute q.options.key?(:slop)
  end

  def test_slop_returns_self
    q = RR::Search::Query.new
    result = q.slop(1)

    assert_same q, result
  end

  # ==================================================================
  # Query - language
  # ==================================================================

  def test_language
    q = RR::Search::Query.new.language("spanish")

    assert_equal "spanish", q.options[:language]
  end

  def test_language_not_set_by_default
    q = RR::Search::Query.new

    refute q.options.key?(:language)
  end

  def test_language_returns_self
    q = RR::Search::Query.new
    result = q.language("en")

    assert_same q, result
  end

  # ==================================================================
  # Query - execute
  # ==================================================================

  def test_execute_delegates_to_client
    mock_client = mock("client")
    q = RR::Search::Query.new("hello")
      .limit(0, 5)

    mock_client.expects(:ft_search).with("myindex", "hello", **q.options).returns([1, "doc:1", []])
    result = q.execute(mock_client, "myindex")

    assert_equal [1, "doc:1", []], result
  end

  # ==================================================================
  # Query - complex chained builder
  # ==================================================================

  def test_full_builder_chain
    q = RR::Search::Query.new("hello world")
      .filter_numeric("price", 10, 100)
      .filter_tag("category", "electronics")
      .filter_geo("location", -73.98, 40.73, 10, unit: :mi)
      .return_fields("title", "price")
      .sort_by("price", :desc)
      .limit(0, 20)
      .highlight(fields: ["title"], tags: ["<em>", "</em>"])
      .summarize(fields: ["body"], frags: 5, len: 50, separator: " | ")
      .params(vec: "data")
      .dialect(2)
      .verbatim
      .no_content
      .no_stopwords
      .with_scores
      .with_payloads
      .with_sort_keys
      .scorer("BM25")
      .expander("my_exp")
      .slop(2)
      .in_order
      .language("english")

    # to_s includes query + numeric + tag filters
    expected_str = "hello world @price:[10 100] @category:{electronics}"

    assert_equal expected_str, q.to_s

    opts = q.options

    # Return fields
    assert_equal %w[title price], opts[:return]

    # Sort
    assert_equal "price", opts[:sortby]
    assert_equal :desc, opts[:sortby_order]

    # Limit
    assert_equal [0, 20], opts[:limit]

    # Highlight
    assert opts[:highlight]
    assert_equal ["title"], opts[:highlight_fields]
    assert_equal ["<em>", "</em>"], opts[:highlight_tags]

    # Summarize
    assert opts[:summarize]
    assert_equal ["body"], opts[:summarize_fields]
    assert_equal 5, opts[:summarize_frags]
    assert_equal 50, opts[:summarize_len]
    assert_equal " | ", opts[:summarize_separator]

    # Params
    assert_equal({ vec: "data" }, opts[:params])

    # Dialect
    assert_equal 2, opts[:dialect]

    # Flags
    assert opts[:verbatim]
    assert opts[:nocontent]
    assert opts[:nostopwords]
    assert opts[:withscores]
    assert opts[:withpayloads]
    assert opts[:withsortkeys]
    assert opts[:inorder]

    # Advanced
    assert_equal "BM25", opts[:scorer]
    assert_equal "my_exp", opts[:expander]
    assert_equal 2, opts[:slop]
    assert_equal "english", opts[:language]

    # Geo
    assert_equal ["location", -73.98, 40.73, 10, "mi"], opts[:geofilter]
  end

  # ==================================================================
  # Query - to_s with no filters
  # ==================================================================

  def test_to_s_no_filters
    q = RR::Search::Query.new("test query")

    assert_equal "test query", q.to_s
  end

  # ==================================================================
  # AggregateQuery - initialization
  # ==================================================================

  def test_aggregate_default_query_string
    aq = RR::Search::AggregateQuery.new

    assert_equal "*", aq.to_s
  end

  def test_aggregate_custom_query_string
    aq = RR::Search::AggregateQuery.new("@category:{books}")

    assert_equal "@category:{books}", aq.to_s
  end

  def test_aggregate_default_options
    aq = RR::Search::AggregateQuery.new
    opts = aq.options

    assert_equal [0, 10], opts[:limit]
    refute opts.key?(:load)
    refute opts.key?(:groupby)
    refute opts.key?(:sortby)
    refute opts.key?(:apply)
    refute opts.key?(:filter)
    refute opts.key?(:dialect)
  end

  # ==================================================================
  # AggregateQuery - load
  # ==================================================================

  def test_aggregate_load
    aq = RR::Search::AggregateQuery.new.load("@title", "@body")

    assert_equal %w[@title @body], aq.options[:load]
  end

  def test_aggregate_load_array
    aq = RR::Search::AggregateQuery.new.load(%w[@title @body])

    assert_equal %w[@title @body], aq.options[:load]
  end

  def test_aggregate_load_not_set_by_default
    aq = RR::Search::AggregateQuery.new

    refute aq.options.key?(:load)
  end

  def test_aggregate_load_returns_self
    aq = RR::Search::AggregateQuery.new
    result = aq.load("@f")

    assert_same aq, result
  end

  # ==================================================================
  # AggregateQuery - group_by
  # ==================================================================

  def test_aggregate_group_by_simple
    reducer = RR::Search::Reducer.count.as("cnt")
    aq = RR::Search::AggregateQuery.new
      .group_by("@category", reducers: [reducer])

    opts = aq.options

    assert opts.key?(:groupby)
    assert_equal 1, opts[:groupby].length
    assert_equal ["@category"], opts[:groupby][0][:fields]
    assert_equal [%w[COUNT AS cnt]], opts[:groupby][0][:reducers]
  end

  def test_aggregate_group_by_multiple_fields
    reducer = RR::Search::Reducer.count
    aq = RR::Search::AggregateQuery.new
      .group_by("@category", "@brand", reducers: [reducer])

    opts = aq.options

    assert_equal %w[@category @brand], opts[:groupby][0][:fields]
  end

  def test_aggregate_group_by_multiple_stages
    r1 = RR::Search::Reducer.count.as("count")
    r2 = RR::Search::Reducer.avg("@price").as("avg_price")

    aq = RR::Search::AggregateQuery.new
      .group_by("@category", reducers: [r1])
      .group_by("@brand", reducers: [r2])

    opts = aq.options

    assert_equal 2, opts[:groupby].length
  end

  def test_aggregate_group_by_no_reducers
    aq = RR::Search::AggregateQuery.new
      .group_by("@category")

    opts = aq.options

    assert_empty opts[:groupby][0][:reducers]
  end

  def test_aggregate_group_by_not_set_by_default
    aq = RR::Search::AggregateQuery.new

    refute aq.options.key?(:groupby)
  end

  def test_aggregate_group_by_returns_self
    aq = RR::Search::AggregateQuery.new
    result = aq.group_by("@f")

    assert_same aq, result
  end

  # ==================================================================
  # AggregateQuery - sort_by
  # ==================================================================

  def test_aggregate_sort_by_default_asc
    aq = RR::Search::AggregateQuery.new.sort_by("@count")

    opts = aq.options

    assert_equal "@count", opts[:sortby]
    assert_equal :asc, opts[:sortby_order]
  end

  def test_aggregate_sort_by_desc
    aq = RR::Search::AggregateQuery.new.sort_by("@count", :desc)

    opts = aq.options

    assert_equal "@count", opts[:sortby]
    assert_equal :desc, opts[:sortby_order]
  end

  def test_aggregate_sort_by_not_set_by_default
    aq = RR::Search::AggregateQuery.new
    opts = aq.options

    refute opts.key?(:sortby)
    refute opts.key?(:sortby_order)
  end

  def test_aggregate_sort_by_returns_self
    aq = RR::Search::AggregateQuery.new
    result = aq.sort_by("@f")

    assert_same aq, result
  end

  # ==================================================================
  # AggregateQuery - limit
  # ==================================================================

  def test_aggregate_limit
    aq = RR::Search::AggregateQuery.new.limit(5, 15)

    assert_equal [5, 15], aq.options[:limit]
  end

  def test_aggregate_limit_returns_self
    aq = RR::Search::AggregateQuery.new
    result = aq.limit(0, 10)

    assert_same aq, result
  end

  # ==================================================================
  # AggregateQuery - apply
  # ==================================================================

  def test_aggregate_apply_single
    aq = RR::Search::AggregateQuery.new
      .apply("upper(@name)", as: "upper_name")

    opts = aq.options

    assert_equal [{ expression: "upper(@name)", as: "upper_name" }], opts[:apply]
  end

  def test_aggregate_apply_multiple
    aq = RR::Search::AggregateQuery.new
      .apply("upper(@name)", as: "upper_name")
      .apply("@price * 1.1", as: "price_with_tax")

    opts = aq.options

    assert_equal 2, opts[:apply].length
  end

  def test_aggregate_apply_not_set_by_default
    aq = RR::Search::AggregateQuery.new

    refute aq.options.key?(:apply)
  end

  def test_aggregate_apply_returns_self
    aq = RR::Search::AggregateQuery.new
    result = aq.apply("@f", as: "x")

    assert_same aq, result
  end

  # ==================================================================
  # AggregateQuery - filter
  # ==================================================================

  def test_aggregate_filter_single
    aq = RR::Search::AggregateQuery.new
      .filter("@count > 5")

    opts = aq.options

    assert_equal ["@count > 5"], opts[:filter]
  end

  def test_aggregate_filter_multiple
    aq = RR::Search::AggregateQuery.new
      .filter("@count > 5")
      .filter("@price < 100")

    opts = aq.options

    assert_equal ["@count > 5", "@price < 100"], opts[:filter]
  end

  def test_aggregate_filter_not_set_by_default
    aq = RR::Search::AggregateQuery.new

    refute aq.options.key?(:filter)
  end

  def test_aggregate_filter_returns_self
    aq = RR::Search::AggregateQuery.new
    result = aq.filter("@f > 0")

    assert_same aq, result
  end

  # ==================================================================
  # AggregateQuery - dialect
  # ==================================================================

  def test_aggregate_dialect
    aq = RR::Search::AggregateQuery.new.dialect(3)

    assert_equal 3, aq.options[:dialect]
  end

  def test_aggregate_dialect_not_set_by_default
    aq = RR::Search::AggregateQuery.new

    refute aq.options.key?(:dialect)
  end

  def test_aggregate_dialect_returns_self
    aq = RR::Search::AggregateQuery.new
    result = aq.dialect(2)

    assert_same aq, result
  end

  # ==================================================================
  # AggregateQuery - execute
  # ==================================================================

  def test_aggregate_execute_delegates_to_client
    mock_client = mock("client")
    aq = RR::Search::AggregateQuery.new("*")
      .limit(0, 5)

    mock_client.expects(:ft_aggregate).with("myindex", "*", **aq.options).returns([])
    result = aq.execute(mock_client, "myindex")

    assert_empty result
  end

  # ==================================================================
  # AggregateQuery - full chain
  # ==================================================================

  def test_aggregate_full_builder_chain
    reducer = RR::Search::Reducer.count.as("cnt")

    aq = RR::Search::AggregateQuery.new("@status:{active}")
      .load("@title", "@price")
      .group_by("@category", reducers: [reducer])
      .sort_by("@cnt", :desc)
      .limit(0, 20)
      .apply("@price * 1.1", as: "taxed_price")
      .filter("@cnt > 5")
      .dialect(2)

    assert_equal "@status:{active}", aq.to_s

    opts = aq.options

    assert_equal %w[@title @price], opts[:load]
    assert_equal 1, opts[:groupby].length
    assert_equal "@cnt", opts[:sortby]
    assert_equal :desc, opts[:sortby_order]
    assert_equal [0, 20], opts[:limit]
    assert_equal 1, opts[:apply].length
    assert_equal ["@cnt > 5"], opts[:filter]
    assert_equal 2, opts[:dialect]
  end

  # ==================================================================
  # Reducer - basic factory methods
  # ==================================================================

  def test_reducer_count
    r = RR::Search::Reducer.count

    assert_equal "COUNT", r.function
    assert_empty r.args
    assert_nil r.alias_name
  end

  def test_reducer_count_to_args_without_alias
    r = RR::Search::Reducer.count

    assert_equal ["COUNT"], r.to_args
  end

  def test_reducer_count_to_args_with_alias
    r = RR::Search::Reducer.count.as("cnt")

    assert_equal %w[COUNT AS cnt], r.to_args
  end

  def test_reducer_count_distinct
    r = RR::Search::Reducer.count_distinct("@name")

    assert_equal "COUNT_DISTINCT", r.function
    assert_equal ["@name"], r.args
  end

  def test_reducer_count_distinctish
    r = RR::Search::Reducer.count_distinctish("@name")

    assert_equal "COUNT_DISTINCTISH", r.function
    assert_equal ["@name"], r.args
  end

  def test_reducer_sum
    r = RR::Search::Reducer.sum("@price")

    assert_equal "SUM", r.function
    assert_equal ["@price"], r.args
  end

  def test_reducer_min
    r = RR::Search::Reducer.min("@price")

    assert_equal "MIN", r.function
    assert_equal ["@price"], r.args
  end

  def test_reducer_max
    r = RR::Search::Reducer.max("@price")

    assert_equal "MAX", r.function
    assert_equal ["@price"], r.args
  end

  def test_reducer_avg
    r = RR::Search::Reducer.avg("@price")

    assert_equal "AVG", r.function
    assert_equal ["@price"], r.args
  end

  def test_reducer_stddev
    r = RR::Search::Reducer.stddev("@price")

    assert_equal "STDDEV", r.function
    assert_equal ["@price"], r.args
  end

  def test_reducer_quantile
    r = RR::Search::Reducer.quantile("@price", 0.95)

    assert_equal "QUANTILE", r.function
    assert_equal ["@price", 0.95], r.args
  end

  def test_reducer_tolist
    r = RR::Search::Reducer.tolist("@name")

    assert_equal "TOLIST", r.function
    assert_equal ["@name"], r.args
  end

  def test_reducer_random_sample
    r = RR::Search::Reducer.random_sample("@name", 5)

    assert_equal "RANDOM_SAMPLE", r.function
    assert_equal ["@name", 5], r.args
  end

  # ==================================================================
  # Reducer - first_value
  # ==================================================================

  def test_reducer_first_value_no_by
    r = RR::Search::Reducer.first_value("@name")

    assert_equal "FIRST_VALUE", r.function
    assert_equal ["@name"], r.args
  end

  def test_reducer_first_value_with_by
    r = RR::Search::Reducer.first_value("@name", by: "@timestamp")

    assert_equal "FIRST_VALUE", r.function
    assert_equal ["@name", "BY", "@timestamp", "ASC"], r.args
  end

  def test_reducer_first_value_with_by_desc
    r = RR::Search::Reducer.first_value("@name", by: "@timestamp", order: :desc)

    assert_equal ["@name", "BY", "@timestamp", "DESC"], r.args
  end

  def test_reducer_first_value_with_by_nil
    r = RR::Search::Reducer.first_value("@name", by: nil)
    # nil is falsy, so BY should not be included
    assert_equal ["@name"], r.args
  end

  # ==================================================================
  # Reducer - as (alias)
  # ==================================================================

  def test_reducer_as_returns_self
    r = RR::Search::Reducer.count
    result = r.as("cnt")

    assert_same r, result
    assert_equal "cnt", r.alias_name
  end

  # ==================================================================
  # Reducer - to_args with alias
  # ==================================================================

  def test_reducer_to_args_with_field_and_alias
    r = RR::Search::Reducer.sum("@price").as("total")

    assert_equal ["SUM", "@price", "AS", "total"], r.to_args
  end

  def test_reducer_to_args_without_alias
    r = RR::Search::Reducer.sum("@price")

    assert_equal ["SUM", "@price"], r.to_args
  end

  def test_reducer_to_args_with_multiple_args_and_alias
    r = RR::Search::Reducer.quantile("@price", 0.5).as("median")

    assert_equal ["QUANTILE", "@price", 0.5, "AS", "median"], r.to_args
  end
end
