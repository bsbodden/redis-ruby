# frozen_string_literal: true

require "test_helper"

class SearchCommandsTest < RedisRubyTestCase
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

  def test_ft_create_and_search_hash
    # Create index on hash documents
    redis.ft_create(@index_name,
                    "ON", "HASH",
                    "PREFIX", 1, "doc:",
                    "SCHEMA",
                    "title", "TEXT", "SORTABLE",
                    "body", "TEXT",
                    "price", "NUMERIC", "SORTABLE")

    # Add documents
    redis.hset("doc:1", "title", "Hello World", "body", "This is a test document", "price", 100)
    redis.hset("doc:2", "title", "Redis Search", "body", "Full-text search is awesome", "price", 200)
    redis.hset("doc:3", "title", "World of Redis", "body", "Learning Redis is fun", "price", 150)

    # Wait for indexing
    sleep 0.1

    # Basic search
    result = redis.ft_search(@index_name, "Hello")

    assert_equal 1, result[0]
    assert_equal "doc:1", result[1]

    # Search with multiple results
    result = redis.ft_search(@index_name, "Redis")

    assert_equal 2, result[0]

    # Search with scores
    result = redis.ft_search(@index_name, "World", withscores: true)

    assert_equal 2, result[0]
    # With scores: [total, doc_id, score, fields, doc_id, score, fields, ...]
    assert_includes ["doc:1", "doc:3"], result[1]
  ensure
    redis.del("doc:1", "doc:2", "doc:3")
  end

  def test_ft_search_with_limit
    redis.ft_create(@index_name,
                    "ON", "HASH",
                    "PREFIX", 1, "item:",
                    "SCHEMA",
                    "name", "TEXT")

    5.times do |i|
      redis.hset("item:#{i}", "name", "Test item #{i}")
    end
    sleep 0.1

    # Get first 2 results
    result = redis.ft_search(@index_name, "item", limit: [0, 2])

    assert_equal 5, result[0] # Total count
    assert_equal 2, (result.length - 1) / 2 # 2 results returned

    # Get next 2 results
    result = redis.ft_search(@index_name, "item", limit: [2, 2])

    assert_equal 5, result[0]
    assert_equal 2, (result.length - 1) / 2
  ensure
    5.times { |i| redis.del("item:#{i}") }
  end

  def test_ft_search_with_sortby
    redis.ft_create(@index_name,
                    "ON", "HASH",
                    "PREFIX", 1, "product:",
                    "SCHEMA",
                    "name", "TEXT",
                    "price", "NUMERIC", "SORTABLE")

    redis.hset("product:1", "name", "Apple", "price", 150)
    redis.hset("product:2", "name", "Banana", "price", 50)
    redis.hset("product:3", "name", "Cherry", "price", 200)
    sleep 0.1

    # Sort by price ascending
    result = redis.ft_search(@index_name, "*", sortby: "price", sortasc: true)

    assert_equal 3, result[0]
    assert_equal "product:2", result[1] # Cheapest first

    # Sort by price descending
    result = redis.ft_search(@index_name, "*", sortby: "price", sortasc: false)

    assert_equal 3, result[0]
    assert_equal "product:3", result[1] # Most expensive first
  ensure
    redis.del("product:1", "product:2", "product:3")
  end

  def test_ft_search_with_filter
    redis.ft_create(@index_name,
                    "ON", "HASH",
                    "PREFIX", 1, "filtered:",
                    "SCHEMA",
                    "name", "TEXT",
                    "score", "NUMERIC")

    redis.hset("filtered:1", "name", "Low", "score", 10)
    redis.hset("filtered:2", "name", "Medium", "score", 50)
    redis.hset("filtered:3", "name", "High", "score", 90)
    sleep 0.1

    # Filter by numeric range
    result = redis.ft_search(@index_name, "*", filter: { score: [40, 100] })

    assert_equal 2, result[0]
    refute_includes result, "filtered:1"
  ensure
    redis.del("filtered:1", "filtered:2", "filtered:3")
  end

  def test_ft_search_nocontent
    redis.ft_create(@index_name,
                    "ON", "HASH",
                    "PREFIX", 1, "nc:",
                    "SCHEMA",
                    "title", "TEXT")

    redis.hset("nc:1", "title", "Document One")
    redis.hset("nc:2", "title", "Document Two")
    sleep 0.1

    # Get only document IDs
    result = redis.ft_search(@index_name, "Document", nocontent: true)

    assert_equal 2, result[0]
    # No fields returned, just IDs
    assert_equal 3, result.length # [count, id1, id2]
  ensure
    redis.del("nc:1", "nc:2")
  end

  def test_ft_info
    redis.ft_create(@index_name,
                    "ON", "HASH",
                    "PREFIX", 1, "info:",
                    "SCHEMA",
                    "title", "TEXT",
                    "count", "NUMERIC")

    info = redis.ft_info(@index_name)

    assert_equal @index_name, info["index_name"]
    assert_includes info.keys, "index_definition"
    assert_includes info.keys, "attributes"
  end

  def test_ft_list
    redis.ft_create(@index_name,
                    "ON", "HASH",
                    "SCHEMA",
                    "field", "TEXT")

    indexes = redis.ft_list

    assert_includes indexes, @index_name
  end

  def test_ft_dropindex
    redis.ft_create(@index_name,
                    "ON", "HASH",
                    "SCHEMA",
                    "field", "TEXT")

    # Verify index exists
    assert_includes redis.ft_list, @index_name

    # Drop index
    result = redis.ft_dropindex(@index_name)

    assert_equal "OK", result

    # Verify index is gone
    refute_includes redis.ft_list, @index_name
  end

  def test_ft_dropindex_with_documents
    redis.ft_create(@index_name,
                    "ON", "HASH",
                    "PREFIX", 1, "todel:",
                    "SCHEMA",
                    "name", "TEXT")

    redis.hset("todel:1", "name", "Test")
    sleep 0.1

    # Drop index and documents
    redis.ft_dropindex(@index_name, delete_docs: true)

    # Verify document is deleted
    assert_nil redis.hget("todel:1", "name")
  end

  def test_ft_alter
    redis.ft_create(@index_name,
                    "ON", "HASH",
                    "SCHEMA",
                    "title", "TEXT")

    # Add a new field
    redis.ft_alter(@index_name, "SCHEMA", "ADD", "category", "TAG")

    info = redis.ft_info(@index_name)
    attributes = info["attributes"]

    # Find the category field
    category_field = attributes.find { |attr| attr.include?("category") }

    refute_nil category_field
  end

  def test_ft_explain
    redis.ft_create(@index_name,
                    "ON", "HASH",
                    "SCHEMA",
                    "title", "TEXT")

    explanation = redis.ft_explain(@index_name, "hello world")

    assert_kind_of String, explanation
    assert_predicate explanation.length, :positive?
  end

  def test_ft_aggregate_basic
    redis.ft_create(@index_name,
                    "ON", "HASH",
                    "PREFIX", 1, "agg:",
                    "SCHEMA",
                    "category", "TAG",
                    "price", "NUMERIC")

    redis.hset("agg:1", "category", "electronics", "price", 100)
    redis.hset("agg:2", "category", "electronics", "price", 200)
    redis.hset("agg:3", "category", "books", "price", 50)
    sleep 0.1

    # Group by category and count
    result = redis.ft_aggregate(@index_name, "*",
                                "GROUPBY", 1, "@category",
                                "REDUCE", "COUNT", 0, "AS", "count")

    # Result: [total, [field1, val1, field2, val2], ...]
    assert_kind_of Array, result
    assert_operator result[0], :>=, 2 # At least 2 groups
  ensure
    redis.del("agg:1", "agg:2", "agg:3")
  end

  def test_ft_aggregate_with_sum
    redis.ft_create(@index_name,
                    "ON", "HASH",
                    "PREFIX", 1, "sum:",
                    "SCHEMA",
                    "category", "TAG",
                    "price", "NUMERIC")

    redis.hset("sum:1", "category", "a", "price", 10)
    redis.hset("sum:2", "category", "a", "price", 20)
    redis.hset("sum:3", "category", "b", "price", 30)
    sleep 0.1

    result = redis.ft_aggregate(@index_name, "*",
                                "GROUPBY", 1, "@category",
                                "REDUCE", "SUM", 1, "@price", "AS", "total")

    assert_kind_of Array, result
  ensure
    redis.del("sum:1", "sum:2", "sum:3")
  end

  def test_ft_sugadd_and_sugget
    suggestion_key = "suggestions:#{SecureRandom.hex(4)}"

    # Add suggestions
    redis.ft_sugadd(suggestion_key, "hello world", 1.0)
    redis.ft_sugadd(suggestion_key, "hello there", 2.0)
    redis.ft_sugadd(suggestion_key, "hey there", 1.5)

    # Get suggestions
    suggestions = redis.ft_sugget(suggestion_key, "hel")

    assert_kind_of Array, suggestions
    assert_operator suggestions.length, :>=, 2
    assert_includes suggestions, "hello there"
    assert_includes suggestions, "hello world"
  ensure
    redis.del(suggestion_key)
  end

  def test_ft_sugget_with_scores
    suggestion_key = "suggestions:scores:#{SecureRandom.hex(4)}"

    redis.ft_sugadd(suggestion_key, "test one", 1.0)
    redis.ft_sugadd(suggestion_key, "test two", 2.0)

    # Get suggestions with scores
    result = redis.ft_sugget(suggestion_key, "test", withscores: true)

    # With scores: [string, score, string, score, ...]
    assert_kind_of Array, result
    assert_operator result.length, :>=, 4 # At least 2 suggestions with scores
  ensure
    redis.del(suggestion_key)
  end

  def test_ft_sugget_fuzzy
    suggestion_key = "suggestions:fuzzy:#{SecureRandom.hex(4)}"

    redis.ft_sugadd(suggestion_key, "hello", 1.0)

    # Fuzzy match with typo
    result = redis.ft_sugget(suggestion_key, "helo", fuzzy: true)

    assert_includes result, "hello"
  ensure
    redis.del(suggestion_key)
  end

  def test_ft_suglen
    suggestion_key = "suggestions:len:#{SecureRandom.hex(4)}"

    assert_equal 0, redis.ft_suglen(suggestion_key)

    redis.ft_sugadd(suggestion_key, "one", 1.0)
    redis.ft_sugadd(suggestion_key, "two", 1.0)
    redis.ft_sugadd(suggestion_key, "three", 1.0)

    assert_equal 3, redis.ft_suglen(suggestion_key)
  ensure
    redis.del(suggestion_key)
  end

  def test_ft_sugdel
    suggestion_key = "suggestions:del:#{SecureRandom.hex(4)}"

    redis.ft_sugadd(suggestion_key, "to delete", 1.0)

    assert_equal 1, redis.ft_suglen(suggestion_key)

    result = redis.ft_sugdel(suggestion_key, "to delete")

    assert_equal 1, result

    assert_equal 0, redis.ft_suglen(suggestion_key)
  ensure
    redis.del(suggestion_key)
  end

  def test_ft_dictadd_and_dictdump
    dict_name = "testdict:#{SecureRandom.hex(4)}"

    # Add terms to dictionary
    added = redis.ft_dictadd(dict_name, "term1", "term2", "term3")

    assert_equal 3, added

    # Dump dictionary
    terms = redis.ft_dictdump(dict_name)

    assert_kind_of Array, terms
    assert_includes terms, "term1"
    assert_includes terms, "term2"
    assert_includes terms, "term3"
  ensure
    begin
      redis.ft_dictdel(dict_name, "term1", "term2", "term3")
    rescue StandardError
      nil
    end
  end

  def test_ft_dictdel
    dict_name = "testdict:del:#{SecureRandom.hex(4)}"

    redis.ft_dictadd(dict_name, "word1", "word2")
    deleted = redis.ft_dictdel(dict_name, "word1")

    assert_equal 1, deleted

    terms = redis.ft_dictdump(dict_name)

    refute_includes terms, "word1"
    assert_includes terms, "word2"
  ensure
    begin
      redis.ft_dictdel(dict_name, "word2")
    rescue StandardError
      nil
    end
  end

  def test_ft_aliasadd_and_aliasdel
    alias_name = "testalias:#{SecureRandom.hex(4)}"

    redis.ft_create(@index_name,
                    "ON", "HASH",
                    "SCHEMA",
                    "field", "TEXT")

    # Add alias
    result = redis.ft_aliasadd(alias_name, @index_name)

    assert_equal "OK", result

    # Alias should work for search
    redis.hset("aliaskey", "field", "test value")
    sleep 0.1

    # Delete alias
    result = redis.ft_aliasdel(alias_name)

    assert_equal "OK", result
  ensure
    redis.del("aliaskey")
    begin
      redis.ft_aliasdel(alias_name)
    rescue StandardError
      nil
    end
  end

  def test_ft_tagvals
    redis.ft_create(@index_name,
                    "ON", "HASH",
                    "PREFIX", 1, "tagval:",
                    "SCHEMA",
                    "category", "TAG")

    redis.hset("tagval:1", "category", "electronics")
    redis.hset("tagval:2", "category", "books")
    redis.hset("tagval:3", "category", "electronics")
    sleep 0.1

    tags = redis.ft_tagvals(@index_name, "category")

    assert_kind_of Array, tags
    assert_includes tags, "electronics"
    assert_includes tags, "books"
  ensure
    redis.del("tagval:1", "tagval:2", "tagval:3")
  end

  def test_ft_synupdate_and_syndump
    redis.ft_create(@index_name,
                    "ON", "HASH",
                    "SCHEMA",
                    "title", "TEXT")

    # Add synonym group
    redis.ft_synupdate(@index_name, "syn1", "happy", "joyful", "cheerful")

    # Dump synonyms
    synonyms = redis.ft_syndump(@index_name)

    assert_kind_of Hash, synonyms
    # At least one of the synonyms should point to the group
    assert(synonyms.values.any? { |v| v.include?("syn1") })
  end

  def test_ft_spellcheck
    redis.ft_create(@index_name,
                    "ON", "HASH",
                    "PREFIX", 1, "spell:",
                    "SCHEMA",
                    "title", "TEXT")

    redis.hset("spell:1", "title", "hello world")
    redis.hset("spell:2", "title", "hello there")
    sleep 0.1

    # Check spelling
    result = redis.ft_spellcheck(@index_name, "helo wrld")

    assert_kind_of Array, result
  ensure
    redis.del("spell:1", "spell:2")
  end

  def test_ft_config
    # Get all config
    config = redis.ft_config_get("*")

    assert_kind_of Hash, config

    # Get specific config
    timeout_config = redis.ft_config_get("TIMEOUT")

    assert_kind_of Hash, timeout_config
  end

  def test_ft_search_with_return_fields
    redis.ft_create(@index_name,
                    "ON", "HASH",
                    "PREFIX", 1, "ret:",
                    "SCHEMA",
                    "title", "TEXT",
                    "body", "TEXT",
                    "score", "NUMERIC")

    redis.hset("ret:1", "title", "Test", "body", "Content here", "score", 100)
    sleep 0.1

    # Return only specific fields
    result = redis.ft_search(@index_name, "Test", return: %w[title score])

    assert_equal 1, result[0]
    fields = result[2]
    field_hash = Hash[*fields]

    assert field_hash.key?("title")
    assert field_hash.key?("score")
  ensure
    redis.del("ret:1")
  end

  def test_ft_search_with_params
    redis.ft_create(@index_name,
                    "ON", "HASH",
                    "PREFIX", 1, "param:",
                    "SCHEMA",
                    "name", "TEXT")

    redis.hset("param:1", "name", "John Doe")
    sleep 0.1

    # Search with parameterized query
    result = redis.ft_search(@index_name, "$name", params: { name: "John" }, dialect: 2)

    assert_equal 1, result[0]
  ensure
    redis.del("param:1")
  end

  def test_ft_create_json_index
    json_index = "json_idx_#{SecureRandom.hex(4)}"

    begin
      # Create index on JSON documents
      redis.ft_create(json_index,
                      "ON", "JSON",
                      "PREFIX", 1, "user:",
                      "SCHEMA",
                      "$.name", "AS", "name", "TEXT",
                      "$.age", "AS", "age", "NUMERIC", "SORTABLE")

      # Add JSON documents
      redis.json_set("user:1", "$", { name: "Alice", age: 30 })
      redis.json_set("user:2", "$", { name: "Bob", age: 25 })
      sleep 0.1

      # Search JSON index
      result = redis.ft_search(json_index, "@name:Alice")

      assert_equal 1, result[0]

      # Sort by age
      result = redis.ft_search(json_index, "*", sortby: "age", sortasc: true)

      assert_equal 2, result[0]
    ensure
      begin
        redis.ft_dropindex(json_index, delete_docs: true)
      rescue StandardError
        nil
      end
      redis.del("user:1", "user:2")
    end
  end
end
