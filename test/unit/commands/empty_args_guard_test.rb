# frozen_string_literal: true

require_relative "../unit_test_helper"

# Tests for redis-rb issues #1290 and #1096
# Variadic commands must no-op when given empty arguments
# instead of sending invalid commands to the server.
class EmptyArgsGuardTest < Minitest::Test
  def setup
    @client = RR::Client.new
    # Stub ensure_connected to prevent actual connection
    @client.stubs(:ensure_connected)
  end

  # --- HSET with empty hash (redis-rb #1290) ---

  def test_hset_with_empty_hash_returns_zero
    assert_equal 0, @client.hset("key")
  end

  # --- HDEL with no fields ---

  def test_hdel_with_no_fields_returns_zero
    assert_equal 0, @client.hdel("key")
  end

  # --- SADD with no members ---

  def test_sadd_with_no_members_returns_zero
    assert_equal 0, @client.sadd("key")
  end

  # --- SREM with no members (redis-rb #1096) ---

  def test_srem_with_no_members_returns_zero
    assert_equal 0, @client.srem("key")
  end

  # --- ZREM with no members (redis-rb #1096) ---

  def test_zrem_with_no_members_returns_zero
    assert_equal 0, @client.zrem("key")
  end

  # --- LPUSH with no values ---

  def test_lpush_with_no_values_returns_zero
    assert_equal 0, @client.lpush("key")
  end

  # --- RPUSH with no values ---

  def test_rpush_with_no_values_returns_zero
    assert_equal 0, @client.rpush("key")
  end

  # --- LPUSHX with no values ---

  def test_lpushx_with_no_values_returns_zero
    assert_equal 0, @client.lpushx("key")
  end

  # --- RPUSHX with no values ---

  def test_rpushx_with_no_values_returns_zero
    assert_equal 0, @client.rpushx("key")
  end

  # --- HMSET with no field-values ---

  def test_hmset_with_no_fields_returns_ok
    assert_equal "OK", @client.hmset("key")
  end

  # --- HMGET with no fields ---

  def test_hmget_with_no_fields_returns_empty_array
    assert_equal [], @client.hmget("key")
  end
end
