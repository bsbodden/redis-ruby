# frozen_string_literal: true

require_relative "../unit_test_helper"

class JSONBranchTest < Minitest::Test
  # ============================================================
  # MockClient includes the JSON module and records commands
  # ============================================================

  class MockClient
    include RedisRuby::Commands::JSON
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
      mock_return([cmd, a1, a2])
    end

    def call_3args(cmd, a1, a2, a3)
      @last_command = [cmd, a1, a2, a3]
      mock_return([cmd, a1, a2, a3])
    end

    private

    def mock_return(args)
      case args[0]
      when "JSON.GET" then '{"name":"test"}'
      when "JSON.MGET" then ['{"name":"Alice"}', nil, '{"name":"Bob"}']
      when "JSON.SET" then "OK"
      when "JSON.DEL" then 1
      when "JSON.TYPE" then ["object"]
      when "JSON.NUMINCRBY" then "[31]"
      when "JSON.NUMMULTBY" then "[200]"
      when "JSON.STRAPPEND" then [10]
      when "JSON.STRLEN" then [5]
      when "JSON.ARRAPPEND" then [3]
      when "JSON.ARRLEN" then [3]
      when "JSON.ARRINDEX" then [0]
      when "JSON.ARRINSERT" then [4]
      when "JSON.ARRPOP" then ['"last_tag"']
      when "JSON.ARRTRIM" then [2]
      when "JSON.OBJKEYS" then [%w[name age]]
      when "JSON.OBJLEN" then [2]
      when "JSON.CLEAR" then 1
      when "JSON.TOGGLE" then [1]
      when "JSON.DEBUG" then 256
      else "OK"
      end
    end
  end

  def setup
    @client = MockClient.new
  end

  # ============================================================
  # json_set branches
  # ============================================================

  def test_json_set_fast_path_no_options
    @client.json_set("doc", "$", { name: "test" })
    assert_equal "JSON.SET", @client.last_command[0]
    assert_equal "doc", @client.last_command[1]
    assert_equal "$", @client.last_command[2]
    assert_equal '{"name":"test"}', @client.last_command[3]
  end

  def test_json_set_with_nx
    @client.json_set("doc", "$", { name: "test" }, nx: true)
    assert_includes @client.last_command, "NX"
    refute_includes @client.last_command, "XX"
  end

  def test_json_set_with_xx
    @client.json_set("doc", "$", { name: "test" }, xx: true)
    assert_includes @client.last_command, "XX"
    refute_includes @client.last_command, "NX"
  end

  def test_json_set_with_both_nx_and_xx
    @client.json_set("doc", "$", { name: "test" }, nx: true, xx: true)
    assert_includes @client.last_command, "NX"
    assert_includes @client.last_command, "XX"
  end

  def test_json_set_without_nx_without_xx
    @client.json_set("doc", "$", "hello", nx: false, xx: false)
    # Should use fast path (call_3args)
    assert_equal 4, @client.last_command.size
  end

  # ============================================================
  # json_get branches
  # ============================================================

  def test_json_get_no_paths_uses_default
    result = @client.json_get("doc")
    assert_equal ["JSON.GET", "doc", "$"], @client.last_command
    assert_instance_of Hash, result
  end

  def test_json_get_single_path
    result = @client.json_get("doc", "$.name")
    assert_equal ["JSON.GET", "doc", "$.name"], @client.last_command
    assert_instance_of Hash, result
  end

  def test_json_get_multiple_paths
    result = @client.json_get("doc", "$.name", "$.age")
    assert_equal ["JSON.GET", "doc", "$.name", "$.age"], @client.last_command
    assert_instance_of Hash, result
  end

  def test_json_get_returns_nil_when_result_nil
    client = NilJsonGetMock.new
    result = client.json_get("nonexistent")
    assert_nil result
  end

  class NilJsonGetMock
    include RedisRuby::Commands::JSON
    def call(*) = nil
    def call_1arg(*, **) = nil
    def call_2args(*) = nil
    def call_3args(*) = nil
  end

  # ============================================================
  # json_mget
  # ============================================================

  def test_json_mget_default_path
    result = @client.json_mget("doc1", "doc2", "doc3")
    assert_equal "JSON.MGET", @client.last_command[0]
    assert_includes @client.last_command, "$"
    assert_instance_of Array, result
    assert_equal 3, result.size
    assert_nil result[1]  # nil entry stays nil
  end

  def test_json_mget_custom_path
    @client.json_mget("doc1", "doc2", path: "$.name")
    assert_includes @client.last_command, "$.name"
  end

  # ============================================================
  # json_del
  # ============================================================

  def test_json_del_default_path
    result = @client.json_del("doc")
    assert_equal ["JSON.DEL", "doc", "$"], @client.last_command
    assert_equal 1, result
  end

  def test_json_del_custom_path
    result = @client.json_del("doc", "$.age")
    assert_equal ["JSON.DEL", "doc", "$.age"], @client.last_command
    assert_equal 1, result
  end

  # ============================================================
  # json_type
  # ============================================================

  def test_json_type_default_path
    result = @client.json_type("doc")
    assert_equal ["JSON.TYPE", "doc", "$"], @client.last_command
    assert_equal ["object"], result
  end

  def test_json_type_custom_path
    result = @client.json_type("doc", "$.name")
    assert_equal ["JSON.TYPE", "doc", "$.name"], @client.last_command
    assert_equal ["object"], result
  end

  # ============================================================
  # json_numincrby
  # ============================================================

  def test_json_numincrby
    result = @client.json_numincrby("doc", "$.age", 1)
    assert_equal "JSON.NUMINCRBY", @client.last_command[0]
    assert_equal "doc", @client.last_command[1]
    assert_equal "$.age", @client.last_command[2]
    assert_equal "1", @client.last_command[3]
    assert_equal [31], result
  end

  def test_json_numincrby_float
    result = @client.json_numincrby("doc", "$.score", 1.5)
    assert_equal "1.5", @client.last_command[3]
    assert_instance_of Array, result
  end

  # ============================================================
  # json_nummultby
  # ============================================================

  def test_json_nummultby
    result = @client.json_nummultby("doc", "$.score", 2)
    assert_equal "JSON.NUMMULTBY", @client.last_command[0]
    assert_equal "2", @client.last_command[3]
    assert_equal [200], result
  end

  def test_json_nummultby_float
    result = @client.json_nummultby("doc", "$.score", 0.5)
    assert_equal "0.5", @client.last_command[3]
    assert_instance_of Array, result
  end

  # ============================================================
  # json_strappend
  # ============================================================

  def test_json_strappend
    result = @client.json_strappend("doc", "$.name", " Smith")
    assert_equal "JSON.STRAPPEND", @client.last_command[0]
    assert_equal "doc", @client.last_command[1]
    assert_equal "$.name", @client.last_command[2]
    assert_equal '" Smith"', @client.last_command[3]
    assert_equal [10], result
  end

  # ============================================================
  # json_strlen
  # ============================================================

  def test_json_strlen_default_path
    result = @client.json_strlen("doc")
    assert_equal ["JSON.STRLEN", "doc", "$"], @client.last_command
    assert_equal [5], result
  end

  def test_json_strlen_custom_path
    result = @client.json_strlen("doc", "$.name")
    assert_equal ["JSON.STRLEN", "doc", "$.name"], @client.last_command
    assert_equal [5], result
  end

  # ============================================================
  # json_arrappend
  # ============================================================

  def test_json_arrappend_single_value
    result = @client.json_arrappend("doc", "$.tags", "ruby")
    assert_equal "JSON.ARRAPPEND", @client.last_command[0]
    assert_equal "doc", @client.last_command[1]
    assert_equal "$.tags", @client.last_command[2]
    assert_equal '"ruby"', @client.last_command[3]
    assert_equal [3], result
  end

  def test_json_arrappend_multiple_values
    result = @client.json_arrappend("doc", "$.tags", "ruby", "redis")
    assert_equal "JSON.ARRAPPEND", @client.last_command[0]
    assert_equal '"ruby"', @client.last_command[3]
    assert_equal '"redis"', @client.last_command[4]
    assert_equal [3], result
  end

  # ============================================================
  # json_arrlen
  # ============================================================

  def test_json_arrlen_default_path
    result = @client.json_arrlen("doc")
    assert_equal ["JSON.ARRLEN", "doc", "$"], @client.last_command
    assert_equal [3], result
  end

  def test_json_arrlen_custom_path
    result = @client.json_arrlen("doc", "$.tags")
    assert_equal ["JSON.ARRLEN", "doc", "$.tags"], @client.last_command
    assert_equal [3], result
  end

  # ============================================================
  # json_arrindex
  # ============================================================

  def test_json_arrindex_default_range
    result = @client.json_arrindex("doc", "$.tags", "ruby")
    assert_equal "JSON.ARRINDEX", @client.last_command[0]
    assert_equal "doc", @client.last_command[1]
    assert_equal "$.tags", @client.last_command[2]
    assert_equal '"ruby"', @client.last_command[3]
    assert_equal 0, @client.last_command[4]
    assert_equal 0, @client.last_command[5]
    assert_equal [0], result
  end

  def test_json_arrindex_with_start_and_stop
    @client.json_arrindex("doc", "$.tags", "redis", start: 1, stop: 5)
    assert_equal 1, @client.last_command[4]
    assert_equal 5, @client.last_command[5]
  end

  # ============================================================
  # json_arrinsert
  # ============================================================

  def test_json_arrinsert_single_value
    result = @client.json_arrinsert("doc", "$.tags", 1, "new_tag")
    assert_equal "JSON.ARRINSERT", @client.last_command[0]
    assert_equal "doc", @client.last_command[1]
    assert_equal "$.tags", @client.last_command[2]
    assert_equal 1, @client.last_command[3]
    assert_equal '"new_tag"', @client.last_command[4]
    assert_equal [4], result
  end

  def test_json_arrinsert_multiple_values
    @client.json_arrinsert("doc", "$.tags", 0, "a", "b")
    assert_equal '"a"', @client.last_command[4]
    assert_equal '"b"', @client.last_command[5]
  end

  # ============================================================
  # json_arrpop branches
  # ============================================================

  def test_json_arrpop_default_path_and_index
    result = @client.json_arrpop("doc")
    assert_equal "JSON.ARRPOP", @client.last_command[0]
    assert_equal "doc", @client.last_command[1]
    assert_equal "$", @client.last_command[2]
    assert_equal(-1, @client.last_command[3])
    assert_equal ["last_tag"], result
  end

  def test_json_arrpop_custom_path
    result = @client.json_arrpop("doc", "$.tags")
    assert_equal "$.tags", @client.last_command[2]
    assert_equal ["last_tag"], result
  end

  def test_json_arrpop_custom_index
    result = @client.json_arrpop("doc", "$.tags", 0)
    assert_equal 0, @client.last_command[3]
    assert_equal ["last_tag"], result
  end

  def test_json_arrpop_returns_nil_when_result_nil
    client = NilArrpopMock.new
    result = client.json_arrpop("doc")
    assert_nil result
  end

  class NilArrpopMock
    include RedisRuby::Commands::JSON
    def call(*) = nil
    def call_1arg(*, **) = nil
    def call_2args(*) = nil
    def call_3args(*) = nil
  end

  def test_json_arrpop_with_non_array_result
    client = ScalarArrpopMock.new
    result = client.json_arrpop("doc")
    assert_equal "last_tag", result
  end

  class ScalarArrpopMock
    include RedisRuby::Commands::JSON
    def call(*) = '"last_tag"'
    def call_1arg(*, **) = '"last_tag"'
    def call_2args(*) = '"last_tag"'
    def call_3args(*) = '"last_tag"'
  end

  def test_json_arrpop_with_array_containing_nil
    client = ArrayWithNilArrpopMock.new
    result = client.json_arrpop("doc")
    assert_equal [nil, "tag"], result
  end

  class ArrayWithNilArrpopMock
    include RedisRuby::Commands::JSON
    def call(*) = [nil, '"tag"']
    def call_1arg(*, **) = [nil, '"tag"']
    def call_2args(*) = [nil, '"tag"']
    def call_3args(*) = [nil, '"tag"']
  end

  # ============================================================
  # json_arrtrim
  # ============================================================

  def test_json_arrtrim
    result = @client.json_arrtrim("doc", "$.tags", 0, 2)
    assert_equal "JSON.ARRTRIM", @client.last_command[0]
    assert_equal "doc", @client.last_command[1]
    assert_equal "$.tags", @client.last_command[2]
    assert_equal 0, @client.last_command[3]
    assert_equal 2, @client.last_command[4]
    assert_equal [2], result
  end

  # ============================================================
  # json_objkeys
  # ============================================================

  def test_json_objkeys_default_path
    result = @client.json_objkeys("doc")
    assert_equal ["JSON.OBJKEYS", "doc", "$"], @client.last_command
    assert_equal [%w[name age]], result
  end

  def test_json_objkeys_custom_path
    result = @client.json_objkeys("doc", "$.nested")
    assert_equal ["JSON.OBJKEYS", "doc", "$.nested"], @client.last_command
    assert_equal [%w[name age]], result
  end

  # ============================================================
  # json_objlen
  # ============================================================

  def test_json_objlen_default_path
    result = @client.json_objlen("doc")
    assert_equal ["JSON.OBJLEN", "doc", "$"], @client.last_command
    assert_equal [2], result
  end

  def test_json_objlen_custom_path
    result = @client.json_objlen("doc", "$.nested")
    assert_equal ["JSON.OBJLEN", "doc", "$.nested"], @client.last_command
    assert_equal [2], result
  end

  # ============================================================
  # json_clear
  # ============================================================

  def test_json_clear_default_path
    result = @client.json_clear("doc")
    assert_equal ["JSON.CLEAR", "doc", "$"], @client.last_command
    assert_equal 1, result
  end

  def test_json_clear_custom_path
    result = @client.json_clear("doc", "$.tags")
    assert_equal ["JSON.CLEAR", "doc", "$.tags"], @client.last_command
    assert_equal 1, result
  end

  # ============================================================
  # json_toggle
  # ============================================================

  def test_json_toggle
    result = @client.json_toggle("doc", "$.active")
    assert_equal ["JSON.TOGGLE", "doc", "$.active"], @client.last_command
    assert_equal [true], result
  end

  def test_json_toggle_returns_boolean_array
    client = ToggleFalseMock.new
    result = client.json_toggle("doc", "$.active")
    assert_equal [false], result
  end

  class ToggleFalseMock
    include RedisRuby::Commands::JSON
    def call(*) = [0]
    def call_1arg(*, **) = [0]
    def call_2args(*) = [0]
    def call_3args(*) = [0]
  end

  # ============================================================
  # json_debug_memory
  # ============================================================

  def test_json_debug_memory_default_path
    result = @client.json_debug_memory("doc")
    assert_equal ["JSON.DEBUG", "MEMORY", "doc", "$"], @client.last_command
    assert_equal 256, result
  end

  def test_json_debug_memory_custom_path
    result = @client.json_debug_memory("doc", "$.name")
    assert_equal ["JSON.DEBUG", "MEMORY", "doc", "$.name"], @client.last_command
    assert_equal 256, result
  end
end
