# frozen_string_literal: true

require_relative "../unit_test_helper"

class StringProxyFetchTest < Minitest::Test
  def setup
    @mock_redis = build_mock_redis
    @proxy = RR::DSL::StringProxy.new(@mock_redis, "test", "key")
  end

  def test_fetch_returns_existing_value
    @mock_redis.mock_get_return("existing")

    result = @proxy.fetch { "computed" }

    assert_equal "existing", result
  end

  def test_fetch_computes_and_stores_on_miss
    @mock_redis.mock_get_return(nil)

    result = @proxy.fetch { "computed" }

    assert_equal "computed", result
    assert_equal ["test:key", "computed"], @mock_redis.last_set_args
  end

  def test_fetch_with_force_recomputes
    @mock_redis.mock_get_return("existing")

    result = @proxy.fetch(force: true) { "recomputed" }

    assert_equal "recomputed", result
    assert_equal ["test:key", "recomputed"], @mock_redis.last_set_args
  end

  def test_fetch_without_block_returns_nil_on_miss
    @mock_redis.mock_get_return(nil)

    result = @proxy.fetch

    assert_nil result
  end

  def test_fetch_without_block_returns_value_on_hit
    @mock_redis.mock_get_return("existing")

    result = @proxy.fetch

    assert_equal "existing", result
  end

  def test_fetch_does_not_call_get_when_force
    @mock_redis.mock_get_return("existing")

    @proxy.fetch(force: true) { "forced" }

    # When force: true, should not call get
    refute_includes @mock_redis.call_history, [:get, "test:key"]
  end

  private

  def build_mock_redis
    redis = Object.new
    redis.instance_variable_set(:@get_return, nil)
    redis.instance_variable_set(:@last_set_args, nil)
    redis.instance_variable_set(:@call_history, [])

    def redis.get(key)
      @call_history << [:get, key]
      @get_return
    end

    def redis.set(key, value)
      @call_history << [:set, key, value]
      @last_set_args = [key, value.to_s]
      "OK"
    end

    def redis.del(key)
      @call_history << [:del, key]
      1
    end

    def redis.mock_get_return(val)
      @get_return = val
    end

    def redis.last_set_args
      @last_set_args
    end

    def redis.call_history
      @call_history
    end

    redis
  end
end
