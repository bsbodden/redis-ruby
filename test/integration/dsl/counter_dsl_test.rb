# frozen_string_literal: true

require "test_helper"

class CounterDSLTest < RedisRubyTestCase
  use_testcontainers!

  def setup
    super
    @key = "test:counter:#{SecureRandom.hex(8)}"
  end

  # ============================================================
  # Entry Point Tests
  # ============================================================

  def test_counter_proxy_creation
    proxy = redis.counter(:page, :views, 123)
    
    assert_instance_of RedisRuby::DSL::CounterProxy, proxy
    assert_equal "page:views:123", proxy.key
  end

  def test_counter_proxy_with_single_key_part
    proxy = redis.counter(:simple)
    
    assert_equal "simple", proxy.key
  end

  def test_counter_proxy_with_multiple_key_parts
    proxy = redis.counter(:rate_limit, :api, :user, 456)
    
    assert_equal "rate_limit:api:user:456", proxy.key
  end

  # ============================================================
  # Get/Set Operations Tests
  # ============================================================

  def test_set_and_get
    counter = redis.counter(@key)
    
    result = counter.set(100)
    
    assert_same counter, result  # Returns self for chaining
    assert_equal 100, counter.get()
  end

  def test_get_nonexistent_key
    counter = redis.counter(@key)
    
    assert_nil counter.get()
  end

  def test_value_alias_for_get
    counter = redis.counter(@key)
    counter.set(42)
    
    assert_equal 42, counter.value
  end

  def test_to_i_alias_for_get
    counter = redis.counter(@key)
    counter.set(99)
    
    assert_equal 99, counter.to_i
  end

  def test_value_assignment
    counter = redis.counter(@key)
    
    result = (counter.value = 200)
    
    assert_equal 200, result
    assert_equal 200, counter.get()
  end

  def test_set_converts_to_integer
    counter = redis.counter(@key)
    
    counter.set(3.14)
    
    assert_equal 3, counter.get()
  end

  # ============================================================
  # Increment/Decrement Tests
  # ============================================================

  def test_increment_by_one
    counter = redis.counter(@key)
    counter.set(10)
    
    result = counter.increment()
    
    assert_same counter, result
    assert_equal 11, counter.get()
  end

  def test_increment_by_custom_amount
    counter = redis.counter(@key)
    counter.set(100)
    
    result = counter.increment(50)
    
    assert_same counter, result
    assert_equal 150, counter.get()
  end

  def test_increment_nonexistent_key
    counter = redis.counter(@key)
    
    counter.increment()
    
    assert_equal 1, counter.get()
  end

  def test_incr_alias
    counter = redis.counter(@key)
    counter.set(5)
    
    counter.incr
    
    assert_equal 6, counter.get()
  end

  def test_decrement_by_one
    counter = redis.counter(@key)
    counter.set(10)
    
    result = counter.decrement()
    
    assert_same counter, result
    assert_equal 9, counter.get()
  end

  def test_decrement_by_custom_amount
    counter = redis.counter(@key)
    counter.set(100)
    
    result = counter.decrement(30)
    
    assert_same counter, result
    assert_equal 70, counter.get()
  end

  def test_decrement_nonexistent_key
    counter = redis.counter(@key)
    
    counter.decrement()
    
    assert_equal(-1, counter.get())
  end

  def test_decr_alias
    counter = redis.counter(@key)
    counter.set(10)

    counter.decr

    assert_equal 9, counter.get()
  end

  def test_multiple_increments_chained
    counter = redis.counter(@key)

    counter.set(0).increment().increment(5).increment(10)

    assert_equal 16, counter.get()
  end

  # ============================================================
  # Float Increment Tests
  # ============================================================

  def test_increment_float
    counter = redis.counter(@key)
    counter.set(10)

    result = counter.increment_float(1.5)

    assert_same counter, result
    # Note: Redis returns float as string, get() converts to int
    # We need to check the actual value from Redis
    assert_equal "11.5", redis.get(@key)
  end

  def test_increment_float_nonexistent_key
    counter = redis.counter(@key)

    counter.increment_float(2.5)

    assert_equal "2.5", redis.get(@key)
  end

  def test_incrbyfloat_alias
    counter = redis.counter(@key)
    counter.set(5)

    counter.incrbyfloat(0.5)

    assert_equal "5.5", redis.get(@key)
  end

  # ============================================================
  # Atomic Operations Tests
  # ============================================================

  def test_setnx_sets_when_key_does_not_exist
    counter = redis.counter(@key)

    result = counter.setnx(0)

    assert_equal true, result
    assert_equal 0, counter.get()
  end

  def test_setnx_does_not_set_when_key_exists
    counter = redis.counter(@key)
    counter.set(100)

    result = counter.setnx(0)

    assert_equal false, result
    assert_equal 100, counter.get()
  end

  def test_getset_returns_old_value
    counter = redis.counter(@key)
    counter.set(50)

    old_value = counter.getset(100)

    assert_equal 50, old_value
    assert_equal 100, counter.get()
  end

  def test_getset_returns_nil_for_nonexistent_key
    counter = redis.counter(@key)

    old_value = counter.getset(100)

    assert_nil old_value
    assert_equal 100, counter.get()
  end

  # ============================================================
  # Existence Tests
  # ============================================================

  def test_exists_returns_true_when_key_exists
    counter = redis.counter(@key)
    counter.set(10)

    assert counter.exists?()
  end

  def test_exists_returns_false_when_key_does_not_exist
    counter = redis.counter(@key)

    refute counter.exists?()
  end

  def test_zero_returns_true_for_zero_value
    counter = redis.counter(@key)
    counter.set(0)

    assert counter.zero?()
  end

  def test_zero_returns_true_for_nonexistent_key
    counter = redis.counter(@key)

    assert counter.zero?()
  end

  def test_zero_returns_false_for_nonzero_value
    counter = redis.counter(@key)
    counter.set(10)

    refute counter.zero?()
  end

  # ============================================================
  # Expiration Tests
  # ============================================================

  def test_expire_sets_ttl
    counter = redis.counter(@key)
    counter.set(100)

    result = counter.expire(60)

    assert_same counter, result
    assert_operator counter.ttl(), :>, 0
    assert_operator counter.ttl(), :<=, 60
  end

  def test_expire_at_with_time_object
    counter = redis.counter(@key)
    counter.set(100)

    result = counter.expire_at(Time.now + 120)

    assert_same counter, result
    assert_operator counter.ttl(), :>, 0
  end

  def test_expire_at_with_timestamp
    counter = redis.counter(@key)
    counter.set(100)

    timestamp = Time.now.to_i + 90
    result = counter.expire_at(timestamp)

    assert_same counter, result
    assert_operator counter.ttl(), :>, 0
  end

  def test_ttl_returns_minus_one_for_no_expiration
    counter = redis.counter(@key)
    counter.set(100)

    assert_equal(-1, counter.ttl())
  end

  def test_ttl_returns_minus_two_for_nonexistent_key
    counter = redis.counter(@key)

    assert_equal(-2, counter.ttl())
  end

  def test_persist_removes_expiration
    counter = redis.counter(@key)
    counter.set(100)
    counter.expire(60)

    result = counter.persist()

    assert_same counter, result
    assert_equal(-1, counter.ttl())
  end

  # ============================================================
  # Clear Tests
  # ============================================================

  def test_delete_removes_key
    counter = redis.counter(@key)
    counter.set(100)

    result = counter.delete()

    assert_equal 1, result
    refute counter.exists?()
  end

  def test_delete_returns_zero_for_nonexistent_key
    counter = redis.counter(@key)

    result = counter.delete()

    assert_equal 0, result
  end

  def test_clear_alias
    counter = redis.counter(@key)
    counter.set(100)

    result = counter.clear()

    assert_equal 1, result
    refute counter.exists?()
  end

  # ============================================================
  # Integration Tests
  # ============================================================

  def test_rate_limiting_workflow
    limit = redis.counter(:rate_limit, :api, :user, 123)

    # Initialize counter with expiration
    limit.setnx(0)
    limit.expire(60) if limit.ttl() == -1

    # Simulate API calls
    10.times { limit.increment() }

    assert_equal 10, limit.get()
    assert_operator limit.ttl(), :>, 0

    # Check if rate limit exceeded
    if limit.get() > 100
      flunk "Rate limit should not be exceeded"
    end

    limit.clear()
  end

  def test_distributed_counter_workflow
    views = redis.counter(:page, :views, 456)

    # Multiple processes incrementing
    views.increment()
    views.increment(5)
    views.increment(10)

    total = views.get()
    assert_equal 16, total

    views.clear()
  end

  def test_page_view_tracking_workflow
    today = Date.today.to_s
    daily_views = redis.counter(:views, :daily, today)

    # Track views
    daily_views.increment()
    daily_views.increment()
    daily_views.increment()

    # Set expiration (keep for 7 days)
    daily_views.expire(86400 * 7)

    assert_equal 3, daily_views.get()
    assert_operator daily_views.ttl(), :>, 0

    daily_views.clear()
  end

  def test_chainable_operations
    counter = redis.counter(@key)

    counter.set(0)
           .increment(10)
           .increment(5)
           .expire(3600)

    assert_equal 15, counter.get()
    assert_operator counter.ttl(), :>, 0

    counter.clear()
  end

  def test_atomic_increment_workflow
    counter = redis.counter(:atomic, :test)

    # Initialize if not exists
    counter.setnx(0)

    # Atomic increments
    counter.increment()
    counter.increment()

    assert_equal 2, counter.get()

    counter.clear()
  end

  def test_metrics_collection_workflow
    requests = redis.counter(:metrics, :requests, :total)
    errors = redis.counter(:metrics, :errors, :total)

    # Track metrics
    10.times { requests.increment() }
    2.times { errors.increment() }

    assert_equal 10, requests.get()
    assert_equal 2, errors.get()

    # Calculate error rate
    error_rate = (errors.get().to_f / requests.get() * 100).round(2)
    assert_equal 20.0, error_rate

    requests.clear()
    errors.clear()
  end
end



