# frozen_string_literal: true

require_relative "unit_test_helper"

# Tests for redis-rb issue #1274
# IPv6 URLs with bracket notation must be parsed correctly,
# preserving the address without brackets for Socket.tcp.
class IPv6URLParsingTest < Minitest::Test
  def test_ipv6_loopback_with_port_and_db
    result = RR::Utils::URLParser.parse("redis://[::1]:6379/0")

    assert_equal "::1", result[:host]
    assert_equal 6379, result[:port]
    assert_equal 0, result[:db]
    refute result[:ssl]
  end

  def test_ipv6_full_address_with_port_and_db
    result = RR::Utils::URLParser.parse("redis://[fd1b:ac4a:ab80::fcf]:6379/2")

    assert_equal "fd1b:ac4a:ab80::fcf", result[:host]
    assert_equal 6379, result[:port]
    assert_equal 2, result[:db]
  end

  def test_ipv6_with_tls
    result = RR::Utils::URLParser.parse("rediss://[::1]:6380/0")

    assert_equal "::1", result[:host]
    assert_equal 6380, result[:port]
    assert result[:ssl]
  end

  def test_ipv6_without_port_uses_default
    result = RR::Utils::URLParser.parse("redis://[::1]/0")

    assert_equal "::1", result[:host]
    assert_equal 6379, result[:port]
  end

  def test_ipv6_without_db_uses_default
    result = RR::Utils::URLParser.parse("redis://[::1]:6379")

    assert_equal "::1", result[:host]
    assert_equal 0, result[:db]
  end

  def test_ipv6_with_password
    result = RR::Utils::URLParser.parse("redis://:secret@[::1]:6379/0")

    assert_equal "::1", result[:host]
    assert_equal "secret", result[:password]
    assert_nil result[:username]
  end

  def test_ipv6_with_username_and_password
    result = RR::Utils::URLParser.parse("redis://user:pass@[::1]:6379/3")

    assert_equal "::1", result[:host]
    assert_equal "user", result[:username]
    assert_equal "pass", result[:password]
    assert_equal 3, result[:db]
  end

  def test_ipv4_still_works
    result = RR::Utils::URLParser.parse("redis://192.168.1.1:6379/0")

    assert_equal "192.168.1.1", result[:host]
    assert_equal 6379, result[:port]
  end

  def test_hostname_still_works
    result = RR::Utils::URLParser.parse("redis://redis.example.com:6379/1")

    assert_equal "redis.example.com", result[:host]
    assert_equal 6379, result[:port]
  end
end
