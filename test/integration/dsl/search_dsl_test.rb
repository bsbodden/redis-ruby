# frozen_string_literal: true

require "test_helper"

class SearchDSLTest < RedisRubyTestCase
  use_testcontainers!

  def setup
    super
    @index_name = "test_idx_#{SecureRandom.hex(4)}"
    # Clean up any leftover indexes
    begin
      redis.ft_dropindex(@index_name, delete_docs: true)
    rescue RedisRuby::CommandError
      # Index doesn't exist, that's fine
    end
  end

  def teardown
    # Clean up after each test
    begin
      redis.ft_dropindex(@index_name, delete_docs: true)
    rescue RedisRuby::CommandError
      # Index doesn't exist, that's fine
    end
    super
  end

  def test_search_index_dsl_basic
    # Create index using DSL
    result = redis.search_index(@index_name) do
      on :hash
      prefix "product:"

      schema do
        text :name, sortable: true
        text :description
        numeric :price, sortable: true
        tag :category
      end
    end

    assert_equal "OK", result

    # Verify index was created
    info = redis.ft_info(@index_name)
    assert_equal "HASH", info["index_definition"][1]
  end

  def test_search_index_dsl_with_options
    result = redis.search_index(@index_name) do
      on :hash
      prefix "product:", "item:"
      language "english"
      score 1.0

      schema do
        text :name, sortable: true, weight: 5.0
        text :description, nostem: true
        numeric :price, sortable: true
        tag :category, separator: "|"
        geo :location
      end
    end

    assert_equal "OK", result

    # Add a document and search
    redis.hset("product:1", "name", "Laptop", "description", "Gaming laptop",
               "price", 1000, "category", "electronics")
    sleep 0.1

    results = redis.ft_search(@index_name, "@name:laptop")
    assert_equal 1, results[0]
  end

  def test_search_index_dsl_json
    result = redis.search_index(@index_name) do
      on :json
      prefix "user:"

      schema do
        text "$.name", as: :name, sortable: true
        numeric "$.age", as: :age, sortable: true
        tag "$.tags[*]", as: :tags
      end
    end

    assert_equal "OK", result

    # Add JSON document
    redis.json_set("user:1", "$", { name: "Alice", age: 30, tags: ["ruby", "redis"] })
    sleep 0.1

    results = redis.ft_search(@index_name, "@name:alice")
    assert_equal 1, results[0]
  end

  def test_search_query_builder_basic
    # Create index first
    redis.ft_create(@index_name,
                    "ON", "HASH",
                    "PREFIX", 1, "product:",
                    "SCHEMA",
                    "name", "TEXT", "SORTABLE",
                    "price", "NUMERIC", "SORTABLE",
                    "category", "TAG")

    # Add test data
    redis.hset("product:1", "name", "Laptop", "price", 1000, "category", "electronics")
    redis.hset("product:2", "name", "Mouse", "price", 25, "category", "electronics")
    redis.hset("product:3", "name", "Desk", "price", 500, "category", "furniture")
    sleep 0.1

    # Use query builder
    results = redis.search(@index_name)
                   .query("@category:{electronics}")
                   .sort_by(:price, :asc)
                   .limit(10)
                   .execute

    assert_equal 2, results[0]
    assert_includes results[1], "product:2" # Mouse is cheaper
  end

  def test_search_query_builder_with_filters
    # Create index
    redis.ft_create(@index_name,
                    "ON", "HASH",
                    "PREFIX", 1, "product:",
                    "SCHEMA",
                    "name", "TEXT",
                    "price", "NUMERIC", "SORTABLE",
                    "rating", "NUMERIC")

    # Add test data
    redis.hset("product:1", "name", "Laptop", "price", 1000, "rating", 4.5)
    redis.hset("product:2", "name", "Mouse", "price", 25, "rating", 4.8)
    redis.hset("product:3", "name", "Keyboard", "price", 75, "rating", 3.5)
    sleep 0.1

    # Query with filters
    results = redis.search(@index_name)
                   .query("*")
                   .filter(:price, 0..100)
                   .filter(:rating, 4..5)
                   .with_scores
                   .execute

    assert_equal 1, results[0]
    assert_includes results[1], "product:2" # Only mouse matches both filters
  end

  def test_search_query_builder_chaining
    # Create index
    redis.ft_create(@index_name,
                    "ON", "HASH",
                    "PREFIX", 1, "doc:",
                    "SCHEMA",
                    "title", "TEXT", "SORTABLE")

    redis.hset("doc:1", "title", "Hello World")
    redis.hset("doc:2", "title", "Hello Ruby")
    sleep 0.1

    # Test method chaining
    results = redis.search(@index_name)
                   .query("hello")
                   .verbatim
                   .limit(5)
                   .with_scores
                   .execute

    assert_equal 2, results[0]
  end
end

