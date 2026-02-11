# frozen_string_literal: true

require "test_helper"

class VectorSetsDSLTest < RedisRubyTestCase
  use_testcontainers!

  def setup
    super
    @vset_key = "test:vectors:#{SecureRandom.hex(8)}"

    # Check if Vector Set commands are available (Redis 8.0+)
    begin
      redis.vcard("__test_vset__")
    rescue RedisRuby::CommandError => e
      if e.message.include?("unknown command") || e.message.include?("ERR unknown")
        skip "Vector Set commands not available (requires Redis 8.0+)"
      end
    end
  end

  def teardown
    redis.del(@vset_key) if redis
    super
  end

  # ============================================================
  # vector_set DSL
  # ============================================================

  def test_vector_set_dsl_basic
    builder = redis.vector_set(@vset_key) do
      dimension 384
      quantization :binary
    end

    assert_equal @vset_key, builder.key
    assert_equal 384, builder.config[:dimension]
    assert_equal :binary, builder.config[:quantization]
  end

  def test_vector_set_dsl_with_metadata_schema
    builder = redis.vector_set(@vset_key) do
      dimension 128
      metadata_schema do
        field :category, type: :string
        field :price, type: :number
        field :in_stock, type: :boolean
      end
    end

    assert_equal 3, builder.config[:metadata_fields].size
    assert_equal :string, builder.config[:metadata_fields][:category]
    assert_equal :number, builder.config[:metadata_fields][:price]
    assert_equal :boolean, builder.config[:metadata_fields][:in_stock]
  end

  # ============================================================
  # vectors proxy - add operations
  # ============================================================

  def test_vectors_add_basic
    vectors = redis.vectors(@vset_key)
    result = vectors.add("item1", [1.0, 2.0, 3.0])

    assert_equal vectors, result # Returns self for chaining
    assert_equal 1, redis.vcard(@vset_key)
  end

  def test_vectors_add_with_metadata
    vectors = redis.vectors(@vset_key)
    vectors.add("product1", [1.0, 2.0, 3.0],
                category: "electronics",
                price: 99.99,
                in_stock: true)

    attrs = redis.vgetattr(@vset_key, "product1")
    assert_equal "electronics", attrs["category"]
    assert_in_delta 99.99, attrs["price"]
    assert_equal true, attrs["in_stock"]
  end

  def test_vectors_add_chaining
    redis.vectors(@vset_key)
      .add("item1", [1.0, 2.0, 3.0], category: "a")
      .add("item2", [4.0, 5.0, 6.0], category: "b")
      .add("item3", [7.0, 8.0, 9.0], category: "c")

    assert_equal 3, redis.vcard(@vset_key)
  end

  def test_vectors_add_many
    vectors = redis.vectors(@vset_key)
    vectors.add_many([
      { id: "doc1", vector: [1.0, 2.0, 3.0], category: "tech" },
      { id: "doc2", vector: [4.0, 5.0, 6.0], category: "books" },
      { id: "doc3", vector: [7.0, 8.0, 9.0], category: "music" },
    ])

    assert_equal 3, redis.vcard(@vset_key)
    assert_equal "tech", redis.vgetattr(@vset_key, "doc1")["category"]
  end

  def test_vectors_upsert_alias
    vectors = redis.vectors(@vset_key)
    vectors.upsert("item1", [1.0, 2.0, 3.0])

    assert_equal 1, redis.vcard(@vset_key)
  end

  # ============================================================
  # vectors proxy - retrieval operations
  # ============================================================

  def test_vectors_get
    redis.vadd(@vset_key, [1.0, 2.0, 3.0], "item1", quantization: "NOQUANT")

    vectors = redis.vectors(@vset_key)
    result = vectors.get("item1")

    assert_kind_of Array, result
    assert_equal 3, result.length
  end

  def test_vectors_fetch_alias
    redis.vadd(@vset_key, [1.0, 2.0, 3.0], "item1", quantization: "NOQUANT")

    vectors = redis.vectors(@vset_key)
    result = vectors.fetch("item1")

    assert_kind_of Array, result
  end

  def test_vectors_metadata
    redis.vadd(@vset_key, [1.0, 2.0], "item1", attributes: { color: "red" })

    vectors = redis.vectors(@vset_key)
    attrs = vectors.metadata("item1")

    assert_equal "red", attrs["color"]
  end

  def test_vectors_set_metadata
    redis.vadd(@vset_key, [1.0, 2.0], "item1")

    vectors = redis.vectors(@vset_key)
    result = vectors.set_metadata("item1", color: "blue", size: "large")

    assert_equal 1, result
    assert_equal "blue", redis.vgetattr(@vset_key, "item1")["color"]
  end

  # ============================================================
  # vectors proxy - deletion operations
  # ============================================================

  def test_vectors_remove
    redis.vadd(@vset_key, [1.0, 2.0], "to_remove")

    vectors = redis.vectors(@vset_key)
    result = vectors.remove("to_remove")

    assert_equal 1, result
    assert_equal 0, redis.vcard(@vset_key)
  end

  def test_vectors_delete_alias
    redis.vadd(@vset_key, [1.0, 2.0], "to_delete")

    vectors = redis.vectors(@vset_key)
    result = vectors.delete("to_delete")

    assert_equal 1, result
  end

  # ============================================================
  # vectors proxy - info operations
  # ============================================================

  def test_vectors_dimension
    redis.vadd(@vset_key, [1.0, 2.0, 3.0, 4.0], "item1")

    vectors = redis.vectors(@vset_key)
    dim = vectors.dimension

    assert_equal 4, dim
  end

  def test_vectors_dim_alias
    redis.vadd(@vset_key, [1.0, 2.0, 3.0], "item1")

    vectors = redis.vectors(@vset_key)
    assert_equal 3, vectors.dim
  end

  def test_vectors_count
    redis.vadd(@vset_key, [1.0, 2.0], "a")
    redis.vadd(@vset_key, [3.0, 4.0], "b")
    redis.vadd(@vset_key, [5.0, 6.0], "c")

    vectors = redis.vectors(@vset_key)
    assert_equal 3, vectors.count
  end

  def test_vectors_size_alias
    redis.vadd(@vset_key, [1.0, 2.0], "a")
    redis.vadd(@vset_key, [3.0, 4.0], "b")

    vectors = redis.vectors(@vset_key)
    assert_equal 2, vectors.size
  end

  def test_vectors_cardinality_alias
    redis.vadd(@vset_key, [1.0, 2.0], "a")

    vectors = redis.vectors(@vset_key)
    assert_equal 1, vectors.cardinality
  end

  def test_vectors_info
    redis.vadd(@vset_key, [1.0, 2.0, 3.0], "item1")

    vectors = redis.vectors(@vset_key)
    info = vectors.info

    assert_kind_of Hash, info
    assert_predicate info.length, :positive?
  end

  # ============================================================
  # search builder - basic search
  # ============================================================

  def test_search_basic
    redis.vadd(@vset_key, [1.0, 0.0, 0.0], "x_axis")
    redis.vadd(@vset_key, [0.0, 1.0, 0.0], "y_axis")
    redis.vadd(@vset_key, [0.9, 0.1, 0.0], "near_x")

    vectors = redis.vectors(@vset_key)
    results = vectors.search([1.0, 0.0, 0.0])
      .limit(2)
      .execute

    assert_kind_of Array, results
    assert_equal 2, results.length
    assert_includes results, "x_axis"
    assert_includes results, "near_x"
  end

  def test_search_with_scores
    redis.vadd(@vset_key, [1.0, 0.0], "item1")
    redis.vadd(@vset_key, [0.0, 1.0], "item2")

    vectors = redis.vectors(@vset_key)
    results = vectors.search([1.0, 0.0])
      .limit(2)
      .with_scores
      .execute

    assert_kind_of Hash, results
    assert results.key?("item1")
    assert_kind_of Float, results["item1"]
  end

  def test_search_with_metadata
    redis.vadd(@vset_key, [1.0, 0.0], "item1", attributes: { type: "a" })
    redis.vadd(@vset_key, [0.0, 1.0], "item2", attributes: { type: "b" })

    vectors = redis.vectors(@vset_key)
    results = vectors.search([1.0, 0.0])
      .limit(2)
      .with_metadata
      .execute

    assert_kind_of Hash, results
    assert results["item1"]["type"] == "a" || results["item1"] == { "type" => "a" }
  end

  def test_search_with_scores_and_metadata
    redis.vadd(@vset_key, [1.0, 0.0], "item1", attributes: { category: "tech" })
    redis.vadd(@vset_key, [0.9, 0.1], "item2", attributes: { category: "books" })

    vectors = redis.vectors(@vset_key)
    results = vectors.search([1.0, 0.0])
      .limit(2)
      .with_scores
      .with_metadata
      .execute

    assert_kind_of Hash, results
    assert results.key?("item1")
    assert_kind_of Hash, results["item1"]
    assert results["item1"].key?("score")
    assert results["item1"].key?("attributes")
  end

  # ============================================================
  # search builder - filtering
  # ============================================================

  def test_search_with_filter
    redis.vadd(@vset_key, [1.0, 0.0], "cheap", attributes: { price: 10 })
    redis.vadd(@vset_key, [0.9, 0.1], "expensive", attributes: { price: 100 })

    vectors = redis.vectors(@vset_key)
    results = vectors.search([1.0, 0.0])
      .filter(".price < 50")
      .limit(10)
      .execute

    assert_includes results, "cheap"
    refute_includes results, "expensive"
  end

  def test_search_where_alias
    redis.vadd(@vset_key, [1.0, 0.0], "item1", attributes: { score: 100 })
    redis.vadd(@vset_key, [0.9, 0.1], "item2", attributes: { score: 50 })

    vectors = redis.vectors(@vset_key)
    results = vectors.search([1.0, 0.0])
      .where(".score > 75")
      .limit(10)
      .execute

    assert_includes results, "item1"
    refute_includes results, "item2"
  end
end
