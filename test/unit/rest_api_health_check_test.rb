# frozen_string_literal: true

require_relative "../test_helper"
require "redis_ruby/health_check"
require "webmock/minitest"

class RestApiHealthCheckTest < Minitest::Test
  def setup
    @health_check = RR::HealthCheck::RestApi.new(
      rest_api_host: "redis-enterprise.example.com",
      rest_api_port: 9443,
      database_id: 1,
      username: "admin",
      password: "secret",
      verify_ssl: false
    )
  end

  def test_initialization
    assert_equal "redis-enterprise.example.com", @health_check.rest_api_host
    assert_equal 9443, @health_check.rest_api_port
    assert_equal 1, @health_check.database_id
    assert_in_delta(3.0, @health_check.timeout)
  end

  def test_initialization_with_defaults
    health_check = RR::HealthCheck::RestApi.new(
      rest_api_host: "example.com",
      database_id: 1,
      username: "admin",
      password: "secret"
    )

    assert_equal 9443, health_check.rest_api_port
    assert_in_delta(3.0, health_check.timeout)
  end

  def test_check_returns_true_when_available
    stub_request(:get, "https://redis-enterprise.example.com:9443/v1/bdbs/1/availability")
      .with(
        headers: { "Accept" => "application/json" },
        basic_auth: %w[admin secret]
      )
      .to_return(status: 200, body: '{"available": true}')

    result = @health_check.check(nil)

    assert result
  end

  def test_check_returns_false_when_unavailable
    stub_request(:get, "https://redis-enterprise.example.com:9443/v1/bdbs/1/availability")
      .with(
        headers: { "Accept" => "application/json" },
        basic_auth: %w[admin secret]
      )
      .to_return(status: 503, body: '{"available": false}')

    result = @health_check.check(nil)

    refute result
  end

  def test_check_returns_false_on_network_error
    stub_request(:get, "https://redis-enterprise.example.com:9443/v1/bdbs/1/availability")
      .to_raise(Errno::ECONNREFUSED)

    result = @health_check.check(nil)

    refute result
  end

  def test_check_returns_false_on_timeout
    stub_request(:get, "https://redis-enterprise.example.com:9443/v1/bdbs/1/availability")
      .to_timeout

    result = @health_check.check(nil)

    refute result
  end

  def test_check_with_custom_timeout
    health_check = RR::HealthCheck::RestApi.new(
      rest_api_host: "redis-enterprise.example.com",
      database_id: 1,
      username: "admin",
      password: "secret",
      timeout: 10.0,
      verify_ssl: false
    )

    stub_request(:get, "https://redis-enterprise.example.com:9443/v1/bdbs/1/availability")
      .to_return(status: 200, body: '{"available": true}')

    result = health_check.check(nil)

    assert result
  end

  def test_check_without_ssl
    health_check = RR::HealthCheck::RestApi.new(
      rest_api_host: "redis-enterprise.example.com",
      rest_api_port: 8080,
      database_id: 1,
      username: "admin",
      password: "secret",
      use_ssl: false
    )

    stub_request(:get, "http://redis-enterprise.example.com:8080/v1/bdbs/1/availability")
      .to_return(status: 200, body: '{"available": true}')

    result = health_check.check(nil)

    assert result
  end

  def test_check_without_authentication
    health_check = RR::HealthCheck::RestApi.new(
      rest_api_host: "redis-enterprise.example.com",
      database_id: 1,
      verify_ssl: false
    )

    stub_request(:get, "https://redis-enterprise.example.com:9443/v1/bdbs/1/availability")
      .with(headers: { "Accept" => "application/json" })
      .to_return(status: 200, body: '{"available": true}')

    result = health_check.check(nil)

    assert result
  end

  def test_check_with_404_error
    stub_request(:get, "https://redis-enterprise.example.com:9443/v1/bdbs/1/availability")
      .to_return(status: 404, body: '{"error": "Database not found"}')

    result = @health_check.check(nil)

    refute result
  end

  def test_check_with_401_unauthorized
    stub_request(:get, "https://redis-enterprise.example.com:9443/v1/bdbs/1/availability")
      .to_return(status: 401, body: '{"error": "Unauthorized"}')

    result = @health_check.check(nil)

    refute result
  end
end
