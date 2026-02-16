# frozen_string_literal: true

require "test_helper"

class HashDSLTest < RedisRubyTestCase
  use_testcontainers!

  def setup
    super
    @key = "test:hash:#{SecureRandom.hex(8)}"
  end

  # ============================================================
  # Entry Point Tests
  # ============================================================

  def test_hash_proxy_creation
    proxy = redis.hash(:user, 123)
    
    assert_instance_of RR::DSL::HashProxy, proxy
    assert_equal "user:123", proxy.key
  end

  def test_hash_proxy_with_single_key_part
    proxy = redis.hash(:config)
    
    assert_equal "config", proxy.key
  end

  # ============================================================
  # Hash-like Access Tests
  # ============================================================

  def test_bracket_get_and_set
    hash = redis.hash(@key)
    
    hash[:name] = "John"
    hash[:email] = "john@example.com"
    
    assert_equal "John", hash[:name]
    assert_equal "john@example.com", hash[:email]
  end

  def test_bracket_get_nonexistent_field
    hash = redis.hash(@key)
    
    assert_nil hash[:nonexistent]
  end

  def test_bracket_set_returns_value
    hash = redis.hash(@key)
    
    result = (hash[:name] = "John")
    
    assert_equal "John", result
  end

  # ============================================================
  # Bulk Operations Tests
  # ============================================================

  def test_set_with_multiple_fields
    hash = redis.hash(@key)
    
    result = hash.set(name: "John", email: "john@example.com", age: 30)
    
    assert_same hash, result  # Returns self for chaining
    assert_equal "John", hash[:name]
    assert_equal "john@example.com", hash[:email]
    assert_equal "30", hash[:age]
  end

  def test_set_with_empty_hash
    hash = redis.hash(@key)
    
    result = hash.set
    
    assert_same hash, result
  end

  def test_merge_alias
    hash = redis.hash(@key)
    
    hash.merge(name: "John", age: 30)
    
    assert_equal "John", hash[:name]
    assert_equal "30", hash[:age]
  end

  def test_update_alias
    hash = redis.hash(@key)
    
    hash.update(name: "John", age: 30)
    
    assert_equal "John", hash[:name]
    assert_equal "30", hash[:age]
  end

  def test_chainable_set
    hash = redis.hash(@key)
    
    hash.set(name: "John")
        .set(email: "john@example.com")
        .set(age: 30)
    
    assert_equal "John", hash[:name]
    assert_equal "john@example.com", hash[:email]
    assert_equal "30", hash[:age]
  end

  # ============================================================
  # Fetch Tests
  # ============================================================

  def test_fetch_existing_field
    hash = redis.hash(@key)
    hash[:name] = "John"
    
    result = hash.fetch(:name, "default")
    
    assert_equal "John", result
  end

  def test_fetch_nonexistent_field_with_default
    hash = redis.hash(@key)
    
    result = hash.fetch(:age, 0)
    
    assert_equal 0, result
  end

  def test_fetch_nonexistent_field_without_default
    hash = redis.hash(@key)
    
    result = hash.fetch(:age)
    
    assert_nil result
  end

  # ============================================================
  # to_h Tests
  # ============================================================

  def test_to_h_returns_hash_with_symbol_keys
    hash = redis.hash(@key)
    hash.set(name: "John", email: "john@example.com", age: 30)
    
    result = hash.to_h
    
    assert_instance_of Hash, result
    assert_equal "John", result[:name]
    assert_equal "john@example.com", result[:email]
    assert_equal "30", result[:age]
  end

  def test_to_h_empty_hash
    hash = redis.hash(@key)

    result = hash.to_h

    assert_equal({}, result)
  end

  # ============================================================
  # Existence Tests
  # ============================================================

  def test_exists_returns_true_when_hash_exists
    hash = redis.hash(@key)
    hash[:name] = "John"

    assert hash.exists?
  end

  def test_exists_returns_false_when_hash_does_not_exist
    hash = redis.hash(@key)

    refute hash.exists?
  end

  def test_key_returns_true_when_field_exists
    hash = redis.hash(@key)
    hash[:name] = "John"

    assert hash.key?(:name)
  end

  def test_key_returns_false_when_field_does_not_exist
    hash = redis.hash(@key)
    hash[:name] = "John"

    refute hash.key?(:email)
  end

  def test_has_key_alias
    hash = redis.hash(@key)
    hash[:name] = "John"

    assert hash.has_key?(:name)
  end

  def test_include_alias
    hash = redis.hash(@key)
    hash[:name] = "John"

    assert hash.include?(:name)
  end

  def test_member_alias
    hash = redis.hash(@key)
    hash[:name] = "John"

    assert hash.member?(:name)
  end

  # ============================================================
  # Inspection Tests
  # ============================================================

  def test_keys_returns_symbol_array
    hash = redis.hash(@key)
    hash.set(name: "John", email: "john@example.com", age: 30)

    result = hash.keys

    assert_instance_of Array, result
    assert_equal 3, result.size
    assert_includes result, :name
    assert_includes result, :email
    assert_includes result, :age
  end

  def test_keys_empty_hash
    hash = redis.hash(@key)

    result = hash.keys

    assert_equal [], result
  end

  def test_values_returns_array
    hash = redis.hash(@key)
    hash.set(name: "John", email: "john@example.com")

    result = hash.values

    assert_instance_of Array, result
    assert_equal 2, result.size
    assert_includes result, "John"
    assert_includes result, "john@example.com"
  end

  def test_length_returns_field_count
    hash = redis.hash(@key)
    hash.set(name: "John", email: "john@example.com", age: 30)

    assert_equal 3, hash.length
  end

  def test_size_alias
    hash = redis.hash(@key)
    hash.set(name: "John", email: "john@example.com")

    assert_equal 2, hash.size
  end

  def test_empty_returns_true_for_empty_hash
    hash = redis.hash(@key)

    assert hash.empty?
  end

  def test_empty_returns_false_for_non_empty_hash
    hash = redis.hash(@key)
    hash[:name] = "John"

    refute hash.empty?
  end

  # ============================================================
  # Deletion Tests
  # ============================================================

  def test_delete_single_field
    hash = redis.hash(@key)
    hash.set(name: "John", email: "john@example.com", age: 30)

    result = hash.delete(:email)

    assert_equal 1, result
    refute hash.key?(:email)
    assert hash.key?(:name)
    assert hash.key?(:age)
  end

  def test_delete_multiple_fields
    hash = redis.hash(@key)
    hash.set(name: "John", email: "john@example.com", age: 30)

    result = hash.delete(:email, :age)

    assert_equal 2, result
    refute hash.key?(:email)
    refute hash.key?(:age)
    assert hash.key?(:name)
  end

  def test_delete_nonexistent_field
    hash = redis.hash(@key)
    hash[:name] = "John"

    result = hash.delete(:nonexistent)

    assert_equal 0, result
  end

  def test_clear_deletes_entire_hash
    hash = redis.hash(@key)
    hash.set(name: "John", email: "john@example.com")

    result = hash.clear

    assert_equal 1, result
    refute hash.exists?
  end

  def test_clear_nonexistent_hash
    hash = redis.hash(@key)

    result = hash.clear

    assert_equal 0, result
  end

  # ============================================================
  # Slice and Except Tests
  # ============================================================

  def test_slice_returns_subset_of_fields
    hash = redis.hash(@key)
    hash.set(name: "John", email: "john@example.com", age: 30, city: "SF")

    result = hash.slice(:name, :email)

    assert_equal({name: "John", email: "john@example.com"}, result)
  end

  def test_slice_with_nonexistent_fields
    hash = redis.hash(@key)
    hash.set(name: "John")

    result = hash.slice(:name, :nonexistent)

    assert_equal({name: "John"}, result)
  end

  def test_slice_empty_fields
    hash = redis.hash(@key)
    hash.set(name: "John")

    result = hash.slice

    assert_equal({}, result)
  end

  def test_except_excludes_specified_fields
    hash = redis.hash(@key)
    hash.set(name: "John", email: "john@example.com", age: 30, city: "SF")

    result = hash.except(:age, :city)

    assert_equal({name: "John", email: "john@example.com"}, result)
  end

  def test_except_with_nonexistent_fields
    hash = redis.hash(@key)
    hash.set(name: "John", email: "john@example.com")

    result = hash.except(:nonexistent)

    assert_equal({name: "John", email: "john@example.com"}, result)
  end

  # ============================================================
  # Numeric Operations Tests
  # ============================================================

  def test_increment_by_one
    hash = redis.hash(@key)
    hash[:count] = "10"

    result = hash.increment(:count)

    assert_same hash, result  # Returns self for chaining
    assert_equal "11", hash[:count]
  end

  def test_increment_by_custom_amount
    hash = redis.hash(@key)
    hash[:points] = "100"

    result = hash.increment(:points, 50)

    assert_same hash, result
    assert_equal "150", hash[:points]
  end

  def test_increment_nonexistent_field
    hash = redis.hash(@key)

    result = hash.increment(:count)

    assert_same hash, result
    assert_equal "1", hash[:count]
  end

  def test_decrement_by_one
    hash = redis.hash(@key)
    hash[:count] = "10"

    result = hash.decrement(:count)

    assert_same hash, result
    assert_equal "9", hash[:count]
  end

  def test_decrement_by_custom_amount
    hash = redis.hash(@key)
    hash[:balance] = "100"

    result = hash.decrement(:balance, 25)

    assert_same hash, result
    assert_equal "75", hash[:balance]
  end

  def test_increment_float
    hash = redis.hash(@key)
    hash[:score] = "10.5"

    result = hash.increment_float(:score, 2.3)

    assert_same hash, result
    # Verify the value was incremented
    assert_in_delta 12.8, hash[:score].to_f, 0.01
  end

  def test_increment_float_nonexistent_field
    hash = redis.hash(@key)

    result = hash.increment_float(:score, 1.5)

    assert_same hash, result
    assert_in_delta 1.5, hash[:score].to_f, 0.01
  end

  # ============================================================
  # Iteration Tests
  # ============================================================

  def test_each_iterates_over_field_value_pairs
    hash = redis.hash(@key)
    hash.set(name: "John", email: "john@example.com")

    pairs = []
    result = hash.each { |field, value| pairs << [field, value] }

    assert_same hash, result
    assert_equal 2, pairs.size
    assert_includes pairs, [:name, "John"]
    assert_includes pairs, [:email, "john@example.com"]
  end

  def test_each_without_block_returns_enumerator
    hash = redis.hash(@key)
    hash.set(name: "John")

    result = hash.each

    assert_instance_of Enumerator, result
  end

  def test_each_key_iterates_over_fields
    hash = redis.hash(@key)
    hash.set(name: "John", email: "john@example.com")

    fields = []
    hash.each_key { |field| fields << field }

    assert_equal 2, fields.size
    assert_includes fields, :name
    assert_includes fields, :email
  end

  def test_each_value_iterates_over_values
    hash = redis.hash(@key)
    hash.set(name: "John", email: "john@example.com")

    values = []
    hash.each_value { |value| values << value }

    assert_equal 2, values.size
    assert_includes values, "John"
    assert_includes values, "john@example.com"
  end

  # ============================================================
  # Expiration Tests
  # ============================================================

  def test_expire_sets_ttl
    hash = redis.hash(@key)
    hash[:name] = "John"

    result = hash.expire(60)

    assert_same hash, result
    ttl = hash.ttl
    assert_operator ttl, :>, 0
    assert_operator ttl, :<=, 60
  end

  def test_expire_at_with_time_object
    hash = redis.hash(@key)
    hash[:name] = "John"

    future_time = Time.now + 60
    result = hash.expire_at(future_time)

    assert_same hash, result
    ttl = hash.ttl
    assert_operator ttl, :>, 0
    assert_operator ttl, :<=, 60
  end

  def test_expire_at_with_timestamp
    hash = redis.hash(@key)
    hash[:name] = "John"

    timestamp = Time.now.to_i + 60
    result = hash.expire_at(timestamp)

    assert_same hash, result
    ttl = hash.ttl
    assert_operator ttl, :>, 0
    assert_operator ttl, :<=, 60
  end

  def test_ttl_returns_seconds_until_expiration
    hash = redis.hash(@key)
    hash[:name] = "John"
    hash.expire(120)

    ttl = hash.ttl

    assert_operator ttl, :>, 0
    assert_operator ttl, :<=, 120
  end

  def test_ttl_returns_minus_one_for_no_expiration
    hash = redis.hash(@key)
    hash[:name] = "John"

    ttl = hash.ttl

    assert_equal(-1, ttl)
  end

  def test_ttl_returns_minus_two_for_nonexistent_key
    hash = redis.hash(@key)

    ttl = hash.ttl

    assert_equal(-2, ttl)
  end

  def test_persist_removes_expiration
    hash = redis.hash(@key)
    hash[:name] = "John"
    hash.expire(60)

    result = hash.persist

    assert_same hash, result
    assert_equal(-1, hash.ttl)
  end

  # ============================================================
  # Integration Tests
  # ============================================================

  def test_complete_user_profile_workflow
    user = redis.hash(:user, 123)
      .set(name: "John Doe", email: "john@example.com", age: 30)
      .increment(:login_count)
      .expire(3600)

    assert_equal "John Doe", user[:name]
    assert_equal "john@example.com", user[:email]
    assert_equal "30", user[:age]
    assert_equal "1", user[:login_count]
    assert_operator user.ttl, :>, 0
  end

  def test_session_storage_workflow
    session = redis.hash(:session, "abc123")
    session[:user_id] = "456"
    session[:ip] = "192.168.1.1"
    session.expire(1800)

    assert session.exists?
    assert_equal "456", session[:user_id]
    assert_operator session.ttl, :>, 0
  end

  def test_feature_flags_workflow
    flags = redis.hash(:features, :production)
    flags.merge(new_ui: "true", beta_api: "false", dark_mode: "true")

    assert_equal "true", flags[:new_ui]
    assert_equal "false", flags[:beta_api]

    flags[:beta_api] = "true"
    assert_equal "true", flags[:beta_api]
  end
end



