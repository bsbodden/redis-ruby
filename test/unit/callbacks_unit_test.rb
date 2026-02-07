# frozen_string_literal: true

require_relative "unit_test_helper"

class CallbacksUnitTest < Minitest::Test
  def setup
    @callbacks = RedisRuby::ResponseCallbacks.new
  end

  # ============================================================
  # Initialization
  # ============================================================

  def test_initialize_creates_empty_callbacks
    callbacks = RedisRuby::ResponseCallbacks.new

    assert_empty(callbacks.to_h)
  end

  # ============================================================
  # register
  # ============================================================

  def test_register_with_block
    @callbacks.register("GET") { |r| r.to_s.upcase }

    assert @callbacks.registered?("GET")
  end

  def test_register_with_proc
    cb = ->(r) { r.to_s.upcase }
    @callbacks.register("GET", cb)

    assert @callbacks.registered?("GET")
  end

  def test_register_returns_self
    result = @callbacks.register("GET") { |r| r }

    assert_same @callbacks, result
  end

  def test_register_normalizes_command_to_uppercase
    @callbacks.register("get") { |r| r }

    assert @callbacks.registered?("GET")
    assert @callbacks.registered?("get")
  end

  def test_register_without_callback_raises_argument_error
    assert_raises(ArgumentError) do
      @callbacks.register("GET")
    end
  end

  def test_register_overwrites_existing_callback
    @callbacks.register("GET") { |_r| "first" }
    @callbacks.register("GET") { |_r| "second" }

    assert_equal "second", @callbacks.apply("GET", nil)
  end

  def test_register_with_symbol_command
    @callbacks.register(:get) { |r| r }

    assert @callbacks.registered?("GET")
  end

  # ============================================================
  # unregister
  # ============================================================

  def test_unregister_existing_callback
    @callbacks.register("GET") { |r| r }
    result = @callbacks.unregister("GET")

    assert result
    refute @callbacks.to_h.key?("GET")
  end

  def test_unregister_nonexistent_callback
    result = @callbacks.unregister("NONEXISTENT")

    refute result
  end

  def test_unregister_normalizes_command
    @callbacks.register("GET") { |r| r }
    result = @callbacks.unregister("get")

    assert result
  end

  # ============================================================
  # registered?
  # ============================================================

  def test_registered_for_custom_callback
    @callbacks.register("CUSTOM") { |r| r }

    assert @callbacks.registered?("CUSTOM")
  end

  def test_registered_for_default_callback
    # INFO is in DEFAULTS
    assert @callbacks.registered?("INFO")
  end

  def test_registered_for_unknown_command
    refute @callbacks.registered?("TOTALLY_UNKNOWN_CMD")
  end

  def test_registered_normalizes_command
    @callbacks.register("hgetall") { |r| r }

    assert @callbacks.registered?("HGETALL")
    assert @callbacks.registered?("hgetall")
  end

  def test_registered_default_client_list
    assert @callbacks.registered?("CLIENT LIST")
  end

  def test_registered_default_debug_object
    assert @callbacks.registered?("DEBUG OBJECT")
  end

  def test_registered_default_memory_stats
    assert @callbacks.registered?("MEMORY STATS")
  end

  def test_registered_default_config_get
    assert @callbacks.registered?("CONFIG GET")
  end

  def test_registered_default_acl_log
    assert @callbacks.registered?("ACL LOG")
  end

  # ============================================================
  # apply
  # ============================================================

  def test_apply_custom_callback
    @callbacks.register("GET") { |r| "custom:#{r}" }
    result = @callbacks.apply("GET", "hello")

    assert_equal "custom:hello", result
  end

  def test_apply_custom_overrides_default
    @callbacks.register("INFO") { |_r| "custom_info" }
    result = @callbacks.apply("INFO", "raw data")

    assert_equal "custom_info", result
  end

  def test_apply_default_callback_info
    result = @callbacks.apply("INFO", "# Server\nredis_version:7.0.0\n")

    assert_instance_of Hash, result
    assert_equal({ server: { "redis_version" => "7.0.0" } }, result)
  end

  def test_apply_no_callback_returns_response_as_is
    result = @callbacks.apply("GET", "hello")

    assert_equal "hello", result
  end

  def test_apply_normalizes_command
    @callbacks.register("get") { |r| "processed:#{r}" }
    result = @callbacks.apply("GET", "val")

    assert_equal "processed:val", result
  end

  def test_apply_default_memory_stats_with_array
    result = @callbacks.apply("MEMORY STATS", ["peak.allocated", 1000, "used_memory", 500])

    assert_instance_of Hash, result
    assert_equal({ "peak.allocated" => 1000, "used_memory" => 500 }, result)
  end

  def test_apply_default_memory_stats_with_non_array
    result = @callbacks.apply("MEMORY STATS", "already_parsed")

    assert_equal "already_parsed", result
  end

  def test_apply_default_config_get_with_array
    result = @callbacks.apply("CONFIG GET", %w[maxmemory 0 hz 10])

    assert_instance_of Hash, result
    assert_equal({ "maxmemory" => "0", "hz" => "10" }, result)
  end

  def test_apply_default_config_get_with_non_array
    result = @callbacks.apply("CONFIG GET", { "maxmemory" => "0" })

    assert_equal({ "maxmemory" => "0" }, result)
  end

  def test_apply_default_acl_log_with_array
    entries = [%w[key1 val1 key2 val2], %w[key3 val3]]
    result = @callbacks.apply("ACL LOG", entries)

    assert_instance_of Array, result
    assert_equal [{ "key1" => "val1", "key2" => "val2" }, { "key3" => "val3" }], result
  end

  def test_apply_default_acl_log_with_non_array
    result = @callbacks.apply("ACL LOG", "non-array")

    assert_equal "non-array", result
  end

  # ============================================================
  # to_h
  # ============================================================

  def test_to_h_returns_copy
    @callbacks.register("GET") { |r| r }
    h = @callbacks.to_h
    h["SET"] = proc { |r| r }
    # Original should not be modified
    refute @callbacks.registered?("SET") || @callbacks.to_h.key?("SET")
  end

  def test_to_h_empty
    assert_empty(@callbacks.to_h)
  end

  def test_to_h_with_registered_callbacks
    @callbacks.register("GET") { |r| r }
    @callbacks.register("SET") { |r| r }
    h = @callbacks.to_h

    assert h.key?("GET")
    assert h.key?("SET")
    assert_equal 2, h.size
  end

  # ============================================================
  # reset!
  # ============================================================

  def test_reset_clears_custom_callbacks
    @callbacks.register("GET") { |r| r }
    @callbacks.register("SET") { |r| r }
    result = @callbacks.reset!

    assert_empty(@callbacks.to_h)
    assert_same @callbacks, result
  end

  def test_reset_does_not_affect_defaults
    @callbacks.reset!
    # Defaults should still work through registered?
    assert @callbacks.registered?("INFO")
  end

  # ============================================================
  # load_defaults!
  # ============================================================

  def test_load_defaults_copies_defaults_to_custom
    @callbacks.load_defaults!
    h = @callbacks.to_h

    assert h.key?("INFO")
    assert h.key?("CLIENT LIST")
    assert h.key?("DEBUG OBJECT")
    assert h.key?("MEMORY STATS")
    assert h.key?("CONFIG GET")
    assert h.key?("ACL LOG")
  end

  def test_load_defaults_returns_self
    result = @callbacks.load_defaults!

    assert_same @callbacks, result
  end

  def test_load_defaults_preserves_existing_custom
    @callbacks.register("CUSTOM") { |_r| "custom" }
    @callbacks.load_defaults!

    assert @callbacks.to_h.key?("CUSTOM")
    assert @callbacks.to_h.key?("INFO")
  end

  # ============================================================
  # Class methods: parse_info
  # ============================================================

  def test_parse_info_with_sections
    raw = "# Server\nredis_version:7.0.0\ntcp_port:6379\n\n# Clients\nconnected_clients:5\n"
    result = RedisRuby::ResponseCallbacks.parse_info(raw)

    assert_instance_of Hash, result
    assert_equal "7.0.0", result[:server]["redis_version"]
    assert_equal 6379, result[:server]["tcp_port"]
    assert_equal 5, result[:clients]["connected_clients"]
  end

  def test_parse_info_without_section
    raw = "redis_version:7.0.0\ntcp_port:6379\n"
    result = RedisRuby::ResponseCallbacks.parse_info(raw)

    assert_equal "7.0.0", result["redis_version"]
    assert_equal 6379, result["tcp_port"]
  end

  def test_parse_info_non_string_returns_as_is
    result = RedisRuby::ResponseCallbacks.parse_info(42)

    assert_equal 42, result
  end

  def test_parse_info_empty_lines_skipped
    raw = "# Server\n\nredis_version:7.0.0\n\n"
    result = RedisRuby::ResponseCallbacks.parse_info(raw)

    assert_equal "7.0.0", result[:server]["redis_version"]
  end

  def test_parse_info_value_integer
    raw = "connected_clients:5\n"
    result = RedisRuby::ResponseCallbacks.parse_info(raw)

    assert_equal 5, result["connected_clients"]
  end

  def test_parse_info_value_float
    raw = "used_cpu_sys:1.23\n"
    result = RedisRuby::ResponseCallbacks.parse_info(raw)

    assert_in_delta 1.23, result["used_cpu_sys"], 0.001
  end

  def test_parse_info_value_string
    raw = "redis_git_sha1:abcdef\n"
    result = RedisRuby::ResponseCallbacks.parse_info(raw)

    assert_equal "abcdef", result["redis_git_sha1"]
  end

  # ============================================================
  # Class methods: parse_info_value
  # ============================================================

  def test_parse_info_value_integer_string
    result = RedisRuby::ResponseCallbacks.parse_info_value("42")

    assert_equal 42, result
  end

  def test_parse_info_value_float_string
    result = RedisRuby::ResponseCallbacks.parse_info_value("3.14")

    assert_in_delta 3.14, result, 0.001
  end

  def test_parse_info_value_plain_string
    result = RedisRuby::ResponseCallbacks.parse_info_value("abcdef")

    assert_equal "abcdef", result
  end

  def test_parse_info_value_empty_string
    result = RedisRuby::ResponseCallbacks.parse_info_value("")

    assert_equal "", result
  end

  # ============================================================
  # Class methods: parse_client_list
  # ============================================================

  def test_parse_client_list_string
    raw = "id=1 addr=127.0.0.1:1234 fd=5 name=myconn\nid=2 addr=127.0.0.1:1235 fd=6 name=\n"
    result = RedisRuby::ResponseCallbacks.parse_client_list(raw)

    assert_instance_of Array, result
    assert_equal 2, result.size
    assert_equal "1", result[0]["id"]
    assert_equal "127.0.0.1:1234", result[0]["addr"]
    assert_equal "5", result[0]["fd"]
    assert_equal "myconn", result[0]["name"]
    assert_equal "2", result[1]["id"]
  end

  def test_parse_client_list_non_string
    result = RedisRuby::ResponseCallbacks.parse_client_list([{ "id" => 1 }])

    assert_equal [{ "id" => 1 }], result
  end

  def test_parse_client_list_single_client
    raw = "id=42 addr=10.0.0.1:5000"
    result = RedisRuby::ResponseCallbacks.parse_client_list(raw)

    assert_equal 1, result.size
    assert_equal "42", result[0]["id"]
    assert_equal "10.0.0.1:5000", result[0]["addr"]
  end

  # ============================================================
  # Class methods: parse_debug_object
  # ============================================================

  def test_parse_debug_object_string
    raw = "Value at:0x7f8e encoding:ziplist refcount:1 serializedlength:42 lru:123456"
    result = RedisRuby::ResponseCallbacks.parse_debug_object(raw)

    assert_instance_of Hash, result
    # "at:0x7f8e" => pair split on ":"
    assert_equal "0x7f8e", result["at"]
    assert_equal "ziplist", result["encoding"]
    assert_equal 1, result["refcount"]
    assert_equal 42, result["serializedlength"]
    assert_equal 123_456, result["lru"]
  end

  def test_parse_debug_object_non_string
    result = RedisRuby::ResponseCallbacks.parse_debug_object({ "encoding" => "raw" })

    assert_equal({ "encoding" => "raw" }, result)
  end

  def test_parse_debug_object_no_colons
    raw = "Value nocolon"
    result = RedisRuby::ResponseCallbacks.parse_debug_object(raw)
    # "Value" and "nocolon" don't contain colons, so nothing parsed
    assert_empty(result)
  end

  # ============================================================
  # DEFAULTS constant
  # ============================================================

  def test_defaults_frozen
    assert_predicate RedisRuby::ResponseCallbacks::DEFAULTS, :frozen?
  end

  def test_defaults_keys
    expected_keys = ["INFO", "CLIENT LIST", "DEBUG OBJECT", "MEMORY STATS", "CONFIG GET", "ACL LOG"]

    expected_keys.each do |key|
      assert RedisRuby::ResponseCallbacks::DEFAULTS.key?(key), "Expected DEFAULTS to have key #{key}"
    end
  end

  # ============================================================
  # normalize_command (private, tested via public methods)
  # ============================================================

  def test_normalize_command_via_register_and_apply
    @callbacks.register("hgetall") { |_r| "normalized" }

    assert_equal "normalized", @callbacks.apply("HGETALL", "data")
  end

  def test_normalize_command_symbol
    @callbacks.register(:info) { |_r| "symbol_info" }

    assert_equal "symbol_info", @callbacks.apply("INFO", "data")
  end
end
