# frozen_string_literal: true

require_relative "../unit_test_helper"

class SSLConnectionTest < Minitest::Test
  # SSL connection tests are simpler - we just test the interface
  # Full SSL testing requires actual SSL server (integration tests)

  def test_ssl_class_exists
    assert defined?(RedisRuby::Connection::SSL)
  end

  def test_ssl_default_values
    # Test that defaults are defined
    assert_equal "localhost", RedisRuby::Connection::SSL::DEFAULT_HOST
    assert_equal 6379, RedisRuby::Connection::SSL::DEFAULT_PORT
    assert_equal 5.0, RedisRuby::Connection::SSL::DEFAULT_TIMEOUT
  end

  def test_ssl_has_required_methods
    methods = RedisRuby::Connection::SSL.instance_methods(false)

    assert_includes methods, :host
    assert_includes methods, :port
    assert_includes methods, :timeout
    assert_includes methods, :call
    assert_includes methods, :pipeline
    assert_includes methods, :close
    assert_includes methods, :connected?
  end
end
