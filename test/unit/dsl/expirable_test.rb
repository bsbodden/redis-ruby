# frozen_string_literal: true

require_relative "../unit_test_helper"
require_relative "../../../lib/redis_ruby/dsl/expirable"

class ExpirableTest < Minitest::Test
  # Test class that includes Expirable
  class TestProxy
    include RR::DSL::Expirable

    def initialize(redis, key)
      @redis = redis
      @key = key
    end
  end

  def setup
    @mock_redis = mock("redis")
    @proxy = TestProxy.new(@mock_redis, "test:key")
  end

  def test_expire_delegates_to_redis
    @mock_redis.expects(:expire).with("test:key", 3600)

    result = @proxy.expire(3600)

    assert_same @proxy, result
  end

  def test_expire_at_with_integer
    @mock_redis.expects(:expireat).with("test:key", 1700000000)

    result = @proxy.expire_at(1700000000)

    assert_same @proxy, result
  end

  def test_expire_at_with_time_object
    time = Time.at(1700000000)
    @mock_redis.expects(:expireat).with("test:key", 1700000000)

    result = @proxy.expire_at(time)

    assert_same @proxy, result
  end

  def test_ttl_delegates_to_redis
    @mock_redis.expects(:ttl).with("test:key").returns(3599)

    assert_equal 3599, @proxy.ttl
  end

  def test_persist_delegates_to_redis
    @mock_redis.expects(:persist).with("test:key")

    result = @proxy.persist

    assert_same @proxy, result
  end
end
