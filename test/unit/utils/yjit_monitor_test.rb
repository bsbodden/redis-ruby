# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../test_helper"

class YJITMonitorTest < Minitest::Test
  def test_available_returns_boolean
    result = RedisRuby::Utils::YJITMonitor.available?

    assert_includes [true, false], result
  end

  def test_enabled_returns_boolean
    result = RedisRuby::Utils::YJITMonitor.enabled?

    assert_includes [true, false], result
  end

  def test_stats_returns_hash
    result = RedisRuby::Utils::YJITMonitor.stats

    assert_kind_of Hash, result
  end

  def test_ratio_in_yjit_returns_numeric_or_nil
    result = RedisRuby::Utils::YJITMonitor.ratio_in_yjit

    assert result.nil? || result.is_a?(Numeric)
  end

  def test_healthy_returns_boolean
    result = RedisRuby::Utils::YJITMonitor.healthy?

    assert_includes [true, false], result
  end

  def test_status_report_returns_string
    result = RedisRuby::Utils::YJITMonitor.status_report

    assert_kind_of String, result
    assert_includes result, "YJIT"
  end

  def test_enable_returns_boolean
    result = RedisRuby::Utils::YJITMonitor.enable!

    assert_includes [true, false], result
  end
end
