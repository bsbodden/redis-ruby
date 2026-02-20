# frozen_string_literal: true

require_relative "../unit_test_helper"

class CacheCommandRegistryTest < Minitest::Test
  def test_default_cacheable_commands
    registry = RR::Cache::CommandRegistry.new

    # Read commands should be cacheable
    assert registry.cacheable?("GET")
    assert registry.cacheable?("HGET")
    assert registry.cacheable?("MGET")
    assert registry.cacheable?("LRANGE")
    assert registry.cacheable?("SMEMBERS")
    assert registry.cacheable?("ZRANGE")
    assert registry.cacheable?("EXISTS")
    assert registry.cacheable?("TTL")
    assert registry.cacheable?("TYPE")

    # Write commands should NOT be cacheable
    refute registry.cacheable?("SET")
    refute registry.cacheable?("DEL")
    refute registry.cacheable?("HSET")
    refute registry.cacheable?("LPUSH")
    refute registry.cacheable?("SADD")
    refute registry.cacheable?("ZADD")
    refute registry.cacheable?("EXPIRE")
    refute registry.cacheable?("INCR")
  end

  def test_json_commands_cacheable
    registry = RR::Cache::CommandRegistry.new

    assert registry.cacheable?("JSON.GET")
    assert registry.cacheable?("JSON.MGET")
    assert registry.cacheable?("JSON.TYPE")
  end

  def test_search_commands_cacheable
    registry = RR::Cache::CommandRegistry.new

    assert registry.cacheable?("FT.SEARCH")
    assert registry.cacheable?("FT.AGGREGATE")
  end

  def test_timeseries_commands_cacheable
    registry = RR::Cache::CommandRegistry.new

    assert registry.cacheable?("TS.GET")
    assert registry.cacheable?("TS.RANGE")
  end

  def test_custom_allow_list
    registry = RR::Cache::CommandRegistry.new(allow_list: %w[GET HGET])

    assert registry.cacheable?("GET")
    assert registry.cacheable?("HGET")
    refute registry.cacheable?("MGET")
    refute registry.cacheable?("LRANGE")
  end

  def test_deny_list
    registry = RR::Cache::CommandRegistry.new(deny_list: %w[HGETALL LRANGE])

    assert registry.cacheable?("GET")
    assert registry.cacheable?("HGET")
    refute registry.cacheable?("HGETALL")
    refute registry.cacheable?("LRANGE")
  end

  def test_case_insensitive_allow_list
    registry = RR::Cache::CommandRegistry.new(allow_list: %w[get hget])

    assert registry.cacheable?("GET")
    assert registry.cacheable?("HGET")
  end

  def test_case_insensitive_deny_list
    registry = RR::Cache::CommandRegistry.new(deny_list: %w[hgetall])

    refute registry.cacheable?("HGETALL")
  end

  def test_commands_returns_set
    registry = RR::Cache::CommandRegistry.new

    assert_kind_of Set, registry.commands
    assert_predicate registry.commands, :frozen?
  end
end
