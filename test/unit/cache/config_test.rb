# frozen_string_literal: true

require_relative "../unit_test_helper"

class CacheConfigTest < Minitest::Test
  def test_default_config
    config = RR::Cache::Config.new

    assert_equal 10_000, config.max_entries
    assert_nil config.ttl
    assert_equal :default, config.mode
    assert_nil config.cacheable_commands
    assert_nil config.key_filter
    assert_nil config.store
  end

  def test_custom_config
    config = RR::Cache::Config.new(
      max_entries: 5000,
      ttl: 300,
      mode: :optin,
    )

    assert_equal 5000, config.max_entries
    assert_equal 300, config.ttl
    assert_equal :optin, config.mode
  end

  def test_all_valid_modes
    %i[default optin optout broadcast].each do |mode|
      config = RR::Cache::Config.new(mode: mode)
      assert_equal mode, config.mode
    end
  end

  def test_invalid_mode_raises
    assert_raises(ArgumentError) { RR::Cache::Config.new(mode: :invalid) }
  end

  def test_invalid_max_entries_raises
    assert_raises(ArgumentError) { RR::Cache::Config.new(max_entries: 0) }
    assert_raises(ArgumentError) { RR::Cache::Config.new(max_entries: -1) }
    assert_raises(ArgumentError) { RR::Cache::Config.new(max_entries: "100") }
  end

  def test_cacheable_commands_uppercased_and_frozen
    config = RR::Cache::Config.new(cacheable_commands: %w[get hget mget])

    assert_equal %w[GET HGET MGET], config.cacheable_commands
    assert_predicate config.cacheable_commands, :frozen?
  end

  def test_key_filter
    filter = ->(key) { key.start_with?("user:") }
    config = RR::Cache::Config.new(key_filter: filter)

    assert_equal filter, config.key_filter
  end

  def test_config_is_frozen
    config = RR::Cache::Config.new

    assert_predicate config, :frozen?
  end

  def test_from_true
    config = RR::Cache::Config.from(true)

    assert_instance_of RR::Cache::Config, config
    assert_equal 10_000, config.max_entries
  end

  def test_from_hash
    config = RR::Cache::Config.from(max_entries: 5000, ttl: 60)

    assert_instance_of RR::Cache::Config, config
    assert_equal 5000, config.max_entries
    assert_equal 60, config.ttl
  end

  def test_from_config_passthrough
    original = RR::Cache::Config.new(max_entries: 3000)
    config = RR::Cache::Config.from(original)

    assert_same original, config
  end

  def test_from_invalid_raises
    assert_raises(ArgumentError) { RR::Cache::Config.from("invalid") }
    assert_raises(ArgumentError) { RR::Cache::Config.from(42) }
  end

  def test_custom_store
    store = Object.new
    config = RR::Cache::Config.new(store: store)

    assert_equal store, config.store
  end
end
