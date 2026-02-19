# frozen_string_literal: true

require "test_helper"

class JSONCommandsTest < RedisRubyTestCase
  use_testcontainers!

  def test_json_set_and_get_basic
    redis.json_set("json:basic", "$", { name: "Alice", age: 30 })
    result = redis.json_get("json:basic")

    assert_equal [{ "name" => "Alice", "age" => 30 }], result
  ensure
    redis.del("json:basic")
  end

  def test_json_set_and_get_with_path
    redis.json_set("json:path", "$", { user: { name: "Bob", email: "bob@example.com" } })

    result = redis.json_get("json:path", "$.user.name")

    assert_equal ["Bob"], result
  ensure
    redis.del("json:path")
  end

  def test_json_set_nx_option
    redis.json_set("json:nx", "$", { value: "original" })

    # Should not overwrite with NX
    result = redis.json_set("json:nx", "$", { value: "new" }, nx: true)

    assert_nil result
    assert_equal [{ "value" => "original" }], redis.json_get("json:nx")
  ensure
    redis.del("json:nx")
  end

  def test_json_set_xx_option
    # Should not set without XX when key doesn't exist
    result = redis.json_set("json:xx_new", "$", { value: "test" }, xx: true)

    assert_nil result

    # Should set with XX when key exists
    redis.json_set("json:xx_exists", "$", { value: "original" })
    result = redis.json_set("json:xx_exists", "$", { value: "new" }, xx: true)

    assert_equal "OK", result
    assert_equal [{ "value" => "new" }], redis.json_get("json:xx_exists")
  ensure
    redis.del("json:xx_new", "json:xx_exists")
  end

  def test_json_del
    redis.json_set("json:del", "$", { name: "Test", age: 25 })

    deleted = redis.json_del("json:del", "$.age")

    assert_equal 1, deleted
    assert_equal [{ "name" => "Test" }], redis.json_get("json:del")
  ensure
    redis.del("json:del")
  end

  def test_json_del_entire_document
    redis.json_set("json:del_all", "$", { name: "Test" })

    deleted = redis.json_del("json:del_all")

    assert_equal 1, deleted
    assert_nil redis.json_get("json:del_all")
  end

  def test_json_type
    redis.json_set("json:type", "$", {
      string: "hello",
      number: 42,
      array: [1, 2, 3],
      object: { nested: true },
      boolean: true,
      null_val: nil,
    })

    assert_equal ["string"], redis.json_type("json:type", "$.string")
    assert_equal ["integer"], redis.json_type("json:type", "$.number")
    assert_equal ["array"], redis.json_type("json:type", "$.array")
    assert_equal ["object"], redis.json_type("json:type", "$.object")
    assert_equal ["boolean"], redis.json_type("json:type", "$.boolean")
    assert_equal ["null"], redis.json_type("json:type", "$.null_val")
  ensure
    redis.del("json:type")
  end

  def test_json_numincrby
    redis.json_set("json:incr", "$", { counter: 10 })

    result = redis.json_numincrby("json:incr", "$.counter", 5)

    assert_equal [15], result
  ensure
    redis.del("json:incr")
  end

  def test_json_nummultby
    redis.json_set("json:mult", "$", { value: 10 })

    result = redis.json_nummultby("json:mult", "$.value", 3)

    assert_equal [30], result
  ensure
    redis.del("json:mult")
  end

  def test_json_strappend
    redis.json_set("json:strapp", "$", { greeting: "Hello" })

    result = redis.json_strappend("json:strapp", "$.greeting", " World")

    assert_equal [11], result
    assert_equal ["Hello World"], redis.json_get("json:strapp", "$.greeting")
  ensure
    redis.del("json:strapp")
  end

  def test_json_strlen
    redis.json_set("json:strlen", "$", { text: "Redis" })

    result = redis.json_strlen("json:strlen", "$.text")

    assert_equal [5], result
  ensure
    redis.del("json:strlen")
  end

  def test_json_arrappend
    redis.json_set("json:arrapp", "$", { tags: %w[a b] })

    result = redis.json_arrappend("json:arrapp", "$.tags", "c", "d")

    assert_equal [4], result
    assert_equal [%w[a b c d]], redis.json_get("json:arrapp", "$.tags")
  ensure
    redis.del("json:arrapp")
  end

  def test_json_arrlen
    redis.json_set("json:arrlen", "$", { items: [1, 2, 3, 4, 5] })

    result = redis.json_arrlen("json:arrlen", "$.items")

    assert_equal [5], result
  ensure
    redis.del("json:arrlen")
  end

  def test_json_arrindex
    redis.json_set("json:arridx", "$", { colors: %w[red green blue] })

    result = redis.json_arrindex("json:arridx", "$.colors", "green")

    assert_equal [1], result

    # Not found
    result = redis.json_arrindex("json:arridx", "$.colors", "yellow")

    assert_equal [-1], result
  ensure
    redis.del("json:arridx")
  end

  def test_json_arrinsert
    redis.json_set("json:arrins", "$", { nums: [1, 3] })

    result = redis.json_arrinsert("json:arrins", "$.nums", 1, 2)

    assert_equal [3], result
    assert_equal [[1, 2, 3]], redis.json_get("json:arrins", "$.nums")
  ensure
    redis.del("json:arrins")
  end

  def test_json_arrpop
    redis.json_set("json:arrpop", "$", { stack: %w[a b c] })

    result = redis.json_arrpop("json:arrpop", "$.stack")

    assert_equal ["c"], result
    assert_equal [%w[a b]], redis.json_get("json:arrpop", "$.stack")
  ensure
    redis.del("json:arrpop")
  end

  def test_json_arrtrim
    redis.json_set("json:arrtrim", "$", { nums: [0, 1, 2, 3, 4] })

    result = redis.json_arrtrim("json:arrtrim", "$.nums", 1, 3)

    assert_equal [3], result
    assert_equal [[1, 2, 3]], redis.json_get("json:arrtrim", "$.nums")
  ensure
    redis.del("json:arrtrim")
  end
end

class JSONCommandsTestPart2 < RedisRubyTestCase
  use_testcontainers!

  def test_json_objkeys
    redis.json_set("json:objkeys", "$", { name: "Test", age: 25, active: true })

    result = redis.json_objkeys("json:objkeys")

    assert_kind_of Array, result[0]
    assert_includes result[0], "name"
    assert_includes result[0], "age"
    assert_includes result[0], "active"
  ensure
    redis.del("json:objkeys")
  end

  def test_json_objlen
    redis.json_set("json:objlen", "$", { a: 1, b: 2, c: 3 })

    result = redis.json_objlen("json:objlen")

    assert_equal [3], result
  ensure
    redis.del("json:objlen")
  end

  def test_json_clear
    redis.json_set("json:clear", "$", { tags: [1, 2, 3], data: { nested: true } })

    result = redis.json_clear("json:clear", "$.tags")

    assert_equal 1, result
    assert_equal [[]], redis.json_get("json:clear", "$.tags")
  ensure
    redis.del("json:clear")
  end

  def test_json_toggle
    redis.json_set("json:toggle", "$", { active: true })

    result = redis.json_toggle("json:toggle", "$.active")

    assert_equal [false], result

    result = redis.json_toggle("json:toggle", "$.active")

    assert_equal [true], result
  ensure
    redis.del("json:toggle")
  end

  def test_json_mget
    redis.json_set("json:mget:1", "$", { name: "One" })
    redis.json_set("json:mget:2", "$", { name: "Two" })

    result = redis.json_mget("json:mget:1", "json:mget:2", "json:mget:nonexistent", path: "$.name")

    assert_equal 3, result.length
    assert_equal ["One"], result[0]
    assert_equal ["Two"], result[1]
    assert_nil result[2]
  ensure
    redis.del("json:mget:1", "json:mget:2")
  end

  def test_json_nested_document
    doc = {
      user: {
        profile: {
          name: "Alice",
          settings: {
            theme: "dark",
            notifications: true,
          },
        },
        tags: %w[ruby redis json],
      },
    }

    redis.json_set("json:nested", "$", doc)

    assert_equal ["dark"], redis.json_get("json:nested", "$.user.profile.settings.theme")
    assert_equal [%w[ruby redis json]], redis.json_get("json:nested", "$.user.tags")
  ensure
    redis.del("json:nested")
  end
end
