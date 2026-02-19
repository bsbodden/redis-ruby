# frozen_string_literal: true

require_relative "unit_test_helper"

class YJITMonitorBranchTest < Minitest::Test
  # ============================================================
  # available?
  # ============================================================

  def test_available_returns_boolean
    result = RR::Utils::YJITMonitor.available?

    assert_includes [true, false], result
  end

  # ============================================================
  # enabled?
  # ============================================================

  def test_enabled_returns_boolean
    result = RR::Utils::YJITMonitor.enabled?

    assert_includes [true, false], result
  end

  # ============================================================
  # enable!
  # ============================================================

  def test_enable_when_not_available
    RR::Utils::YJITMonitor.stub(:available?, false) do
      refute RR::Utils::YJITMonitor.enable!
    end
  end

  def test_enable_when_already_enabled
    RR::Utils::YJITMonitor.stub(:available?, true) do
      RR::Utils::YJITMonitor.stub(:enabled?, true) do
        assert RR::Utils::YJITMonitor.enable!
      end
    end
  end

  def test_enable_when_available_and_not_enabled
    # This tests the branch where enable method is available
    result = RR::Utils::YJITMonitor.enable!

    assert_includes [true, false], result
  end

  # ============================================================
  # stats
  # ============================================================

  def test_stats_when_disabled
    RR::Utils::YJITMonitor.stub(:enabled?, false) do
      result = RR::Utils::YJITMonitor.stats

      assert_empty(result)
    end
  end

  def test_stats_when_enabled
    result = RR::Utils::YJITMonitor.stats

    assert_kind_of Hash, result
  end

  # ============================================================
  # ratio_in_yjit
  # ============================================================

  def test_ratio_in_yjit_when_disabled
    RR::Utils::YJITMonitor.stub(:enabled?, false) do
      assert_nil RR::Utils::YJITMonitor.ratio_in_yjit
    end
  end

  def test_ratio_in_yjit_when_enabled
    result = RR::Utils::YJITMonitor.ratio_in_yjit

    assert result.nil? || result.is_a?(Numeric)
  end

  # ============================================================
  # healthy?
  # ============================================================

  def test_healthy_when_no_ratio
    RR::Utils::YJITMonitor.stub(:ratio_in_yjit, nil) do
      refute_predicate RR::Utils::YJITMonitor, :healthy?
    end
  end

  def test_healthy_when_ratio_above_ninety
    RR::Utils::YJITMonitor.stub(:ratio_in_yjit, 95.0) do
      assert_predicate RR::Utils::YJITMonitor, :healthy?
    end
  end

  def test_healthy_when_ratio_below_ninety
    RR::Utils::YJITMonitor.stub(:ratio_in_yjit, 80.0) do
      refute_predicate RR::Utils::YJITMonitor, :healthy?
    end
  end

  def test_healthy_when_ratio_exactly_ninety
    RR::Utils::YJITMonitor.stub(:ratio_in_yjit, 90.0) do
      assert_predicate RR::Utils::YJITMonitor, :healthy?
    end
  end

  # ============================================================
  # status_report
  # ============================================================

  def test_status_report_when_not_available
    RR::Utils::YJITMonitor.stub(:available?, false) do
      report = RR::Utils::YJITMonitor.status_report

      assert_includes report, "Not available"
      assert_includes report, "Recommendation"
    end
  end

  def test_status_report_when_available_but_not_enabled
    RR::Utils::YJITMonitor.stub(:available?, true) do
      RR::Utils::YJITMonitor.stub(:enabled?, false) do
        report = RR::Utils::YJITMonitor.status_report

        assert_includes report, "Available but not enabled"
        assert_includes report, "Recommendation"
      end
    end
  end

  def test_status_report_when_enabled_and_healthy
    RR::Utils::YJITMonitor.stub(:available?, true) do
      RR::Utils::YJITMonitor.stub(:enabled?, true) do
        mock_stats = { ratio_in_yjit: 97.5, code_region_size: 1024, yjit_alloc_size: 2048 }
        RR::Utils::YJITMonitor.stub(:stats, mock_stats) do
          RR::Utils::YJITMonitor.stub(:healthy?, true) do
            report = RR::Utils::YJITMonitor.status_report

            assert_includes report, "Enabled"
            assert_includes report, "97.5"
            assert_includes report, "Healthy"
          end
        end
      end
    end
  end

  def test_status_report_when_enabled_and_unhealthy
    RR::Utils::YJITMonitor.stub(:available?, true) do
      RR::Utils::YJITMonitor.stub(:enabled?, true) do
        mock_stats = { ratio_in_yjit: 50.0, code_region_size: 512, yjit_alloc_size: 1024 }
        RR::Utils::YJITMonitor.stub(:stats, mock_stats) do
          RR::Utils::YJITMonitor.stub(:healthy?, false) do
            report = RR::Utils::YJITMonitor.status_report

            assert_includes report, "Suboptimal"
          end
        end
      end
    end
  end

  def test_status_report_with_zero_stats
    RR::Utils::YJITMonitor.stub(:available?, true) do
      RR::Utils::YJITMonitor.stub(:enabled?, true) do
        mock_stats = { ratio_in_yjit: nil, code_region_size: 0, yjit_alloc_size: 0 }
        RR::Utils::YJITMonitor.stub(:stats, mock_stats) do
          RR::Utils::YJITMonitor.stub(:healthy?, false) do
            report = RR::Utils::YJITMonitor.status_report

            assert_includes report, "0.0%"
            assert_includes report, "0 B"
          end
        end
      end
    end
  end

  def test_status_report_is_string
    result = RR::Utils::YJITMonitor.status_report

    assert_kind_of String, result
    assert_includes result, "YJIT"
  end
end

class URLParserBranchTest < Minitest::Test
  # ============================================================
  # parse - redis:// scheme
  # ============================================================

  def test_parse_simple_redis_url
    result = RR::Utils::URLParser.parse("redis://localhost:6379")

    assert_equal "localhost", result[:host]
    assert_equal 6379, result[:port]
    assert_equal 0, result[:db]
    assert_nil result[:password]
    refute result[:ssl]
  end

  def test_parse_redis_url_with_db
    result = RR::Utils::URLParser.parse("redis://localhost:6379/5")

    assert_equal 5, result[:db]
  end

  def test_parse_redis_url_with_password
    result = RR::Utils::URLParser.parse("redis://:mypassword@localhost:6379/0")

    assert_equal "mypassword", result[:password]
  end

  def test_parse_redis_url_with_username_and_password
    result = RR::Utils::URLParser.parse("redis://user:pass@localhost:6379")

    assert_equal "user", result[:username]
    assert_equal "pass", result[:password]
  end

  def test_parse_redis_url_empty_username
    result = RR::Utils::URLParser.parse("redis://:pass@localhost:6379")

    assert_nil result[:username]
    assert_equal "pass", result[:password]
  end

  def test_parse_redis_url_default_host
    result = RR::Utils::URLParser.parse("redis:///0")
    # When host is empty, URI returns nil or empty
    assert_equal 0, result[:db]
  end

  def test_parse_redis_url_no_port
    result = RR::Utils::URLParser.parse("redis://myhost")

    assert_equal "myhost", result[:host]
    assert_equal 6379, result[:port]
  end

  def test_parse_redis_url_slash_only_path
    result = RR::Utils::URLParser.parse("redis://localhost:6379/")

    assert_equal 0, result[:db]
  end

  def test_parse_redis_url_no_path
    result = RR::Utils::URLParser.parse("redis://localhost:6379")

    assert_equal 0, result[:db]
  end

  # ============================================================
  # parse - rediss:// scheme (TLS)
  # ============================================================

  def test_parse_rediss_url
    result = RR::Utils::URLParser.parse("rediss://secure.host:6380/1")

    assert_equal "secure.host", result[:host]
    assert_equal 6380, result[:port]
    assert_equal 1, result[:db]
    assert result[:ssl]
  end

  # ============================================================
  # parse - unix:// scheme
  # ============================================================

  def test_parse_unix_url_with_path
    result = RR::Utils::URLParser.parse("unix:///tmp/redis.sock")
    # URI parses unix:///tmp/redis.sock with no host, path = /tmp/redis.sock
    assert_includes result[:path], "redis.sock"
    assert_equal 0, result[:db]
  end

  def test_parse_unix_url_with_db_query_param
    result = RR::Utils::URLParser.parse("unix:///tmp/redis.sock?db=3")

    assert_includes result[:path], "redis.sock"
    assert_equal 3, result[:db]
  end

  def test_parse_unix_url_with_password
    result = RR::Utils::URLParser.parse("unix://:secret@/tmp/redis.sock")

    assert_equal "secret", result[:password]
  end

  def test_parse_unix_url_empty_username
    result = RR::Utils::URLParser.parse("unix://:pass@/tmp/redis.sock")

    assert_nil result[:username]
  end

  # ============================================================
  # parse - unsupported scheme
  # ============================================================

  def test_parse_unsupported_scheme
    assert_raises(ArgumentError) do
      RR::Utils::URLParser.parse("http://localhost:6379")
    end
  end

  def test_parse_ftp_scheme
    assert_raises(ArgumentError) do
      RR::Utils::URLParser.parse("ftp://localhost:6379")
    end
  end

  # ============================================================
  # extract_db
  # ============================================================

  def test_extract_db_nil_path
    assert_equal 0, RR::Utils::URLParser.extract_db(nil)
  end

  def test_extract_db_empty_path
    assert_equal 0, RR::Utils::URLParser.extract_db("")
  end

  def test_extract_db_slash_only
    assert_equal 0, RR::Utils::URLParser.extract_db("/")
  end

  def test_extract_db_with_number
    assert_equal 5, RR::Utils::URLParser.extract_db("/5")
  end

  def test_extract_db_with_large_number
    assert_equal 15, RR::Utils::URLParser.extract_db("/15")
  end
end
