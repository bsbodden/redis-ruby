# frozen_string_literal: true

require_relative "../unit_test_helper"

class GeoProxyErrorTest < Minitest::Test
  def test_search_rescues_rr_command_error_not_redis_command_error
    mock_client = mock("client")
    mock_client.expects(:geosearch).raises(RR::CommandError, "ERR unknown command 'GEOSEARCH'")
    mock_client.expects(:georadius).returns([])

    geo = RR::DSL::GeoProxy.new(mock_client, "test:geo")

    # Should rescue RR::CommandError and fall back to georadius,
    # not raise NameError for Redis::CommandError
    result = geo.search(-122.4, 37.8, 10)

    assert_empty result
  end

  def test_search_by_member_rescues_rr_command_error_not_redis_command_error
    mock_client = mock("client")
    mock_client.expects(:geosearch).raises(RR::CommandError, "ERR unknown command 'GEOSEARCH'")
    mock_client.expects(:georadiusbymember).returns([])

    geo = RR::DSL::GeoProxy.new(mock_client, "test:geo")

    result = geo.search_by_member("store1", 50)

    assert_empty result
  end

  def test_search_re_raises_non_geosearch_command_errors
    mock_client = mock("client")
    mock_client.expects(:geosearch).raises(RR::CommandError, "WRONGTYPE Operation")

    geo = RR::DSL::GeoProxy.new(mock_client, "test:geo")

    assert_raises(RR::CommandError) { geo.search(-122.4, 37.8, 10) }
  end
end
