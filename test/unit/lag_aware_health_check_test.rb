# frozen_string_literal: true

require_relative "../test_helper"
require "redis_ruby/health_check"
require "webmock/minitest"

class LagAwareHealthCheckTest < Minitest::Test
  def setup
    @health_check = RR::HealthCheck::LagAware.new(
      rest_api_host: 'redis-enterprise.example.com',
      rest_api_port: 9443,
      database_id: 1,
      lag_tolerance_ms: 100,
      username: 'admin',
      password: 'secret',
      verify_ssl: false
    )
  end

  def test_initialization
    assert_equal 'redis-enterprise.example.com', @health_check.rest_api_host
    assert_equal 9443, @health_check.rest_api_port
    assert_equal 1, @health_check.database_id
    assert_equal 100, @health_check.lag_tolerance_ms
    assert_equal 3.0, @health_check.timeout
  end

  def test_initialization_with_defaults
    health_check = RR::HealthCheck::LagAware.new(
      rest_api_host: 'example.com',
      database_id: 1,
      username: 'admin',
      password: 'secret'
    )
    
    assert_equal 9443, health_check.rest_api_port
    assert_equal 100, health_check.lag_tolerance_ms
    assert_equal 3.0, health_check.timeout
  end

  def test_check_returns_true_when_available_and_lag_within_tolerance
    stub_request(:get, "https://redis-enterprise.example.com:9443/v1/bdbs/1/availability?extend_check=lag&availability_lag_tolerance_ms=100")
      .with(
        headers: { 'Accept' => 'application/json' },
        basic_auth: ['admin', 'secret']
      )
      .to_return(status: 200, body: '{"available": true}')

    result = @health_check.check(nil)
    assert_equal true, result
  end

  def test_check_returns_false_when_lag_exceeds_tolerance
    stub_request(:get, "https://redis-enterprise.example.com:9443/v1/bdbs/1/availability?extend_check=lag&availability_lag_tolerance_ms=100")
      .with(
        headers: { 'Accept' => 'application/json' },
        basic_auth: ['admin', 'secret']
      )
      .to_return(status: 503, body: '{"available": false, "reason": "lag_too_high"}')

    result = @health_check.check(nil)
    assert_equal false, result
  end

  def test_check_returns_false_when_database_unavailable
    stub_request(:get, "https://redis-enterprise.example.com:9443/v1/bdbs/1/availability?extend_check=lag&availability_lag_tolerance_ms=100")
      .with(
        headers: { 'Accept' => 'application/json' },
        basic_auth: ['admin', 'secret']
      )
      .to_return(status: 503, body: '{"available": false}')

    result = @health_check.check(nil)
    assert_equal false, result
  end

  def test_check_returns_false_on_network_error
    stub_request(:get, "https://redis-enterprise.example.com:9443/v1/bdbs/1/availability?extend_check=lag&availability_lag_tolerance_ms=100")
      .to_raise(Errno::ECONNREFUSED)

    result = @health_check.check(nil)
    assert_equal false, result
  end

  def test_check_returns_false_on_timeout
    stub_request(:get, "https://redis-enterprise.example.com:9443/v1/bdbs/1/availability?extend_check=lag&availability_lag_tolerance_ms=100")
      .to_timeout

    result = @health_check.check(nil)
    assert_equal false, result
  end

  def test_check_with_custom_lag_tolerance
    health_check = RR::HealthCheck::LagAware.new(
      rest_api_host: 'redis-enterprise.example.com',
      database_id: 1,
      lag_tolerance_ms: 200,
      username: 'admin',
      password: 'secret',
      verify_ssl: false
    )

    stub_request(:get, "https://redis-enterprise.example.com:9443/v1/bdbs/1/availability?extend_check=lag&availability_lag_tolerance_ms=200")
      .to_return(status: 200, body: '{"available": true}')

    result = health_check.check(nil)
    assert_equal true, result
  end

  def test_check_without_ssl
    health_check = RR::HealthCheck::LagAware.new(
      rest_api_host: 'redis-enterprise.example.com',
      rest_api_port: 8080,
      database_id: 1,
      username: 'admin',
      password: 'secret',
      use_ssl: false
    )

    stub_request(:get, "http://redis-enterprise.example.com:8080/v1/bdbs/1/availability?extend_check=lag&availability_lag_tolerance_ms=100")
      .to_return(status: 200, body: '{"available": true}')

    result = health_check.check(nil)
    assert_equal true, result
  end

  def test_check_without_authentication
    health_check = RR::HealthCheck::LagAware.new(
      rest_api_host: 'redis-enterprise.example.com',
      database_id: 1,
      verify_ssl: false
    )

    stub_request(:get, "https://redis-enterprise.example.com:9443/v1/bdbs/1/availability?extend_check=lag&availability_lag_tolerance_ms=100")
      .with(headers: { 'Accept' => 'application/json' })
      .to_return(status: 200, body: '{"available": true}')

    result = health_check.check(nil)
    assert_equal true, result
  end
end

