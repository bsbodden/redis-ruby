# frozen_string_literal: true

require "test_helper"

class JSONDSLTest < RedisRubyTestCase
  use_testcontainers!

  def setup
    super
    @key = "json:dsl:test"
  end

  def teardown
    redis.del(@key)
    super
  end

  def test_json_proxy_set_and_get_root
    # Set entire document
    redis.json(@key).set(name: "Alice", age: 30)

    # Get entire document
    result = redis.json(@key).get
    assert_equal({ "name" => "Alice", "age" => 30 }, result)
  end

  def test_json_proxy_set_and_get_with_symbols
    # Set using symbols
    redis.json(@key).set(name: "Bob", age: 25)

    # Get using symbols
    name = redis.json(@key).get(:name)
    assert_equal "Bob", name

    age = redis.json(@key).get(:age)
    assert_equal 25, age
  end

  def test_json_proxy_set_specific_path
    redis.json(@key).set(user: { name: "Charlie", age: 35 })

    # Set specific path with symbol
    redis.json(@key).set(:user, { name: "Charlie Updated", age: 36 })

    result = redis.json(@key).get(:user)
    assert_equal({ "name" => "Charlie Updated", "age" => 36 }, result)
  end

  def test_json_proxy_chaining
    # Chain multiple operations
    redis.json(@key)
      .set(name: "Dave", age: 40, score: 100)
      .increment(:age, 1)
      .increment(:score, 50)

    age = redis.json(@key).get(:age)
    assert_equal 41, age

    score = redis.json(@key).get(:score)
    assert_equal 150, score
  end

  def test_json_proxy_increment_and_decrement
    redis.json(@key).set(counter: 10)

    # Increment
    redis.json(@key).increment(:counter, 5)
    assert_equal 15, redis.json(@key).get(:counter)

    # Decrement
    redis.json(@key).decrement(:counter, 3)
    assert_equal 12, redis.json(@key).get(:counter)

    # Default increment by 1
    redis.json(@key).increment(:counter)
    assert_equal 13, redis.json(@key).get(:counter)
  end

  def test_json_proxy_multiply
    redis.json(@key).set(value: 10)

    redis.json(@key).multiply(:value, 3)
    assert_equal 30, redis.json(@key).get(:value)
  end

  def test_json_proxy_array_operations
    redis.json(@key).set(tags: ["ruby"])

    # Append
    redis.json(@key).append(:tags, "redis", "json")
    tags = redis.json(@key).get(:tags)
    assert_equal ["ruby", "redis", "json"], tags

    # Array length
    length = redis.json(@key).array_length(:tags)
    assert_equal 3, length

    # Array index
    index = redis.json(@key).array_index(:tags, "redis")
    assert_equal 1, index

    # Array pop
    popped = redis.json(@key).array_pop(:tags)
    assert_equal "json", popped

    tags = redis.json(@key).get(:tags)
    assert_equal ["ruby", "redis"], tags
  end

  def test_json_proxy_array_insert_and_trim
    redis.json(@key).set(items: ["a", "c"])

    # Insert
    redis.json(@key).array_insert(:items, 1, "b")
    items = redis.json(@key).get(:items)
    assert_equal ["a", "b", "c"], items

    # Trim
    redis.json(@key).array_trim(:items, 0..1)
    items = redis.json(@key).get(:items)
    assert_equal ["a", "b"], items
  end

  def test_json_proxy_object_operations
    redis.json(@key).set(user: { name: "Eve", age: 28, city: "NYC" })

    # Object keys
    keys = redis.json(@key).keys(:user)
    assert_equal ["age", "city", "name"], keys.sort

    # Object length
    length = redis.json(@key).object_length(:user)
    assert_equal 3, length
  end

  def test_json_proxy_type
    redis.json(@key).set(name: "Frank", age: 45, tags: ["a", "b"])

    assert_equal "string", redis.json(@key).type(:name)
    assert_equal "integer", redis.json(@key).type(:age)
    assert_equal "array", redis.json(@key).type(:tags)
  end

  def test_json_proxy_delete
    redis.json(@key).set(name: "Grace", age: 50, temp: "delete me")

    # Delete specific path
    redis.json(@key).delete(:temp)

    result = redis.json(@key).get
    assert_equal({ "name" => "Grace", "age" => 50 }, result)
  end

  def test_json_proxy_clear
    redis.json(@key).set(tags: ["a", "b", "c"], data: { x: 1, y: 2 })

    # Clear array
    redis.json(@key).clear(:tags)
    assert_equal [], redis.json(@key).get(:tags)

    # Clear object
    redis.json(@key).clear(:data)
    assert_equal({}, redis.json(@key).get(:data))
  end

  def test_json_proxy_toggle
    redis.json(@key).set(active: true)

    # Toggle boolean
    result = redis.json(@key).toggle(:active)
    assert_equal false, result

    result = redis.json(@key).toggle(:active)
    assert_equal true, result
  end

  def test_json_proxy_exists
    # Key doesn't exist yet
    refute redis.json(@key).exists?

    # Create key
    redis.json(@key).set(name: "Test")
    assert redis.json(@key).exists?

    # Delete key
    redis.del(@key)
    refute redis.json(@key).exists?
  end

  def test_json_proxy_with_composite_key
    # Use multiple key parts
    redis.json(:user, 123).set(name: "Henry", age: 55)

    result = redis.json(:user, 123).get
    assert_equal({ "name" => "Henry", "age" => 55 }, result)

    # Verify key format
    assert redis.exists("user:123") > 0
  ensure
    redis.del("user:123")
  end

  def test_json_proxy_nested_paths
    redis.json(@key).set(
      user: {
        profile: {
          name: "Ivy",
          contact: {
            email: "ivy@example.com"
          }
        }
      }
    )

    # Access nested paths with JSONPath syntax
    email = redis.json(@key).get("$.user.profile.contact.email")
    assert_equal "ivy@example.com", email
  end

  def test_json_proxy_backward_compatibility
    # Ensure old API still works alongside new API
    redis.json_set(@key, "$", { name: "Jack", age: 60 })

    # Use new API to read
    name = redis.json(@key).get(:name)
    assert_equal "Jack", name

    # Use new API to update
    redis.json(@key).increment(:age, 1)

    # Use old API to read
    result = redis.json_get(@key, "$.age")
    assert_equal [61], result
  end
end

