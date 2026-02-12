# frozen_string_literal: true

require "test_helper"

class StringDSLTest < RedisRubyTestCase
  use_testcontainers!

  def setup
    super
    @key = "test:string:#{SecureRandom.hex(8)}"
  end

  # ============================================================
  # Entry Point Tests
  # ============================================================

  def test_string_proxy_creation
    proxy = redis.string(:config, :api_key)
    
    assert_instance_of RedisRuby::DSL::StringProxy, proxy
    assert_equal "config:api_key", proxy.key
  end

  def test_string_proxy_with_single_key_part
    proxy = redis.string(:simple)
    
    assert_equal "simple", proxy.key
  end

  def test_string_proxy_with_multiple_key_parts
    proxy = redis.string(:cache, :user, 123, :profile)
    
    assert_equal "cache:user:123:profile", proxy.key
  end

  # ============================================================
  # Get/Set Operations Tests
  # ============================================================

  def test_set_and_get
    str = redis.string(@key)
    
    result = str.set("hello world")
    
    assert_same str, result  # Returns self for chaining
    assert_equal "hello world", str.get()
  end

  def test_get_nonexistent_key
    str = redis.string(@key)
    
    assert_nil str.get()
  end

  def test_value_alias_for_get
    str = redis.string(@key)
    str.set("test value")
    
    assert_equal "test value", str.value
  end

  def test_value_assignment
    str = redis.string(@key)
    
    result = (str.value = "assigned value")
    
    assert_equal "assigned value", result
    assert_equal "assigned value", str.get()
  end

  def test_set_with_integer
    str = redis.string(@key)
    
    str.set(123)
    
    assert_equal "123", str.get()
  end

  def test_set_with_float
    str = redis.string(@key)
    
    str.set(3.14)
    
    assert_equal "3.14", str.get()
  end

  # ============================================================
  # Append Operations Tests
  # ============================================================

  def test_append_to_existing_value
    str = redis.string(@key)
    str.set("hello")
    
    result = str.append(" world")
    
    assert_same str, result
    assert_equal "hello world", str.get()
  end

  def test_append_to_nonexistent_key
    str = redis.string(@key)
    
    str.append("hello")
    
    assert_equal "hello", str.get()
  end

  def test_multiple_appends_chained
    str = redis.string(@key)
    
    str.set("a").append("b").append("c")
    
    assert_equal "abc", str.get()
  end

  # ============================================================
  # Length Tests
  # ============================================================

  def test_length_of_string
    str = redis.string(@key)
    str.set("hello world")
    
    assert_equal 11, str.length()
  end

  def test_length_of_nonexistent_key
    str = redis.string(@key)
    
    assert_equal 0, str.length()
  end

  def test_size_alias
    str = redis.string(@key)
    str.set("test")
    
    assert_equal 4, str.size()
  end

  # ============================================================
  # Range Operations Tests
  # ============================================================

  def test_getrange_basic
    str = redis.string(@key)
    str.set("Hello World")
    
    result = str.getrange(0, 4)
    
    assert_equal "Hello", result
  end

  def test_getrange_negative_indices
    str = redis.string(@key)
    str.set("Hello World")
    
    result = str.getrange(-5, -1)
    
    assert_equal "World", result
  end

  def test_getrange_full_string
    str = redis.string(@key)
    str.set("test")

    result = str.getrange(0, -1)

    assert_equal "test", result
  end

  def test_setrange_basic
    str = redis.string(@key)
    str.set("Hello World")

    result = str.setrange(6, "Redis")

    assert_same str, result
    assert_equal "Hello Redis", str.get()
  end

  def test_setrange_extends_string
    str = redis.string(@key)
    str.set("Hi")

    str.setrange(5, "there")

    # Redis pads with null bytes
    result = str.get()
    assert_equal 10, result.length
  end

  # ============================================================
  # Existence Tests
  # ============================================================

  def test_exists_returns_true_when_key_exists
    str = redis.string(@key)
    str.set("value")

    assert str.exists?()
  end

  def test_exists_returns_false_when_key_does_not_exist
    str = redis.string(@key)

    refute str.exists?()
  end

  def test_empty_returns_true_for_nonexistent_key
    str = redis.string(@key)

    assert str.empty?()
  end

  def test_empty_returns_true_for_empty_string
    str = redis.string(@key)
    str.set("")

    assert str.empty?()
  end

  def test_empty_returns_false_for_nonempty_string
    str = redis.string(@key)
    str.set("value")

    refute str.empty?()
  end

  # ============================================================
  # Expiration Tests
  # ============================================================

  def test_expire_sets_ttl
    str = redis.string(@key)
    str.set("value")

    result = str.expire(60)

    assert_same str, result
    assert_operator str.ttl(), :>, 0
    assert_operator str.ttl(), :<=, 60
  end

  def test_expire_at_with_time_object
    str = redis.string(@key)
    str.set("value")

    result = str.expire_at(Time.now + 120)

    assert_same str, result
    assert_operator str.ttl(), :>, 0
  end

  def test_expire_at_with_timestamp
    str = redis.string(@key)
    str.set("value")

    timestamp = Time.now.to_i + 90
    result = str.expire_at(timestamp)

    assert_same str, result
    assert_operator str.ttl(), :>, 0
  end

  def test_ttl_returns_minus_one_for_no_expiration
    str = redis.string(@key)
    str.set("value")

    assert_equal(-1, str.ttl())
  end

  def test_ttl_returns_minus_two_for_nonexistent_key
    str = redis.string(@key)

    assert_equal(-2, str.ttl())
  end

  def test_persist_removes_expiration
    str = redis.string(@key)
    str.set("value")
    str.expire(60)

    result = str.persist()

    assert_same str, result
    assert_equal(-1, str.ttl())
  end

  # ============================================================
  # Atomic Operations Tests
  # ============================================================

  def test_setnx_sets_when_key_does_not_exist
    str = redis.string(@key)

    result = str.setnx("value")

    assert_equal true, result
    assert_equal "value", str.get()
  end

  def test_setnx_does_not_set_when_key_exists
    str = redis.string(@key)
    str.set("existing")

    result = str.setnx("new value")

    assert_equal false, result
    assert_equal "existing", str.get()
  end

  def test_setex_sets_value_with_expiration
    str = redis.string(@key)

    result = str.setex(60, "temp value")

    assert_same str, result
    assert_equal "temp value", str.get()
    assert_operator str.ttl(), :>, 0
  end

  # ============================================================
  # Clear Tests
  # ============================================================

  def test_delete_removes_key
    str = redis.string(@key)
    str.set("value")

    result = str.delete()

    assert_equal 1, result
    refute str.exists?()
  end

  def test_delete_returns_zero_for_nonexistent_key
    str = redis.string(@key)

    result = str.delete()

    assert_equal 0, result
  end

  def test_clear_alias
    str = redis.string(@key)
    str.set("value")

    result = str.clear()

    assert_equal 1, result
    refute str.exists?()
  end

  # ============================================================
  # Integration Tests
  # ============================================================

  def test_configuration_management_workflow
    api_key = redis.string(:config, :api_key)

    api_key.set("sk_live_123456").expire(86400)

    assert_equal "sk_live_123456", api_key.get()
    assert_operator api_key.ttl(), :>, 0

    api_key.clear()
  end

  def test_caching_workflow
    cache = redis.string(:cache, :user, 123)

    user_data = '{"name":"John","email":"john@example.com"}'
    cache.set(user_data).expire(3600)

    assert_equal user_data, cache.get()
    assert_operator cache.ttl(), :>, 0

    cache.clear()
  end

  def test_log_aggregation_workflow
    log = redis.string(:log, :app, Date.today.to_s)

    log.set("[START]")
    log.append(" [INFO] Application started")
    log.append(" [INFO] Ready to accept connections")

    result = log.get()
    assert_includes result, "[START]"
    assert_includes result, "Application started"
    assert_includes result, "Ready to accept connections"

    log.clear()
  end

  def test_chainable_operations
    str = redis.string(@key)

    str.set("initial")
       .append(" value")
       .expire(3600)

    assert_equal "initial value", str.get()
    assert_operator str.ttl(), :>, 0

    str.clear()
  end

  def test_text_manipulation_workflow
    text = redis.string(:document, :draft)

    text.set("Hello World")
    assert_equal 11, text.length()

    # Get first word
    assert_equal "Hello", text.getrange(0, 4)

    # Replace "World" with "Redis"
    text.setrange(6, "Redis")
    assert_equal "Hello Redis", text.get()

    text.clear()
  end
end



