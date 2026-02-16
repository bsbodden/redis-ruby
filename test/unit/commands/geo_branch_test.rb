# frozen_string_literal: true

require_relative "../unit_test_helper"

# Comprehensive branch coverage tests for RR::Commands::Geo
class GeoBranchTest < Minitest::Test
  class MockClient
    include RR::Commands::Geo

    attr_reader :last_command

    def call(*args)
      @last_command = args
      "OK"
    end

    def call_1arg(cmd, a1)
      @last_command = [cmd, a1]
      "OK"
    end

    def call_2args(cmd, a1, a2)
      @last_command = [cmd, a1, a2]
      mock_geo_return(cmd)
    end

    def call_3args(cmd, a1, a2, a3)
      @last_command = [cmd, a1, a2, a3]
      "OK"
    end

    private

    def mock_geo_return(cmd)
      case cmd
      when "GEOPOS" then [["1.0", "2.0"]]
      when "GEOHASH" then ["abc123"]
      else "OK"
      end
    end
  end

  def setup
    @client = MockClient.new
  end

  # ============================================================
  # geoadd - basic
  # ============================================================

  def test_geoadd_basic
    @client.geoadd("locations", -122.4194, 37.7749, "San Francisco")

    assert_equal ["GEOADD", "locations", -122.4194, 37.7749, "San Francisco"], @client.last_command
  end

  # ============================================================
  # geoadd - with NX option
  # ============================================================

  def test_geoadd_with_nx
    @client.geoadd("locations", -122.4194, 37.7749, "San Francisco", nx: true)

    assert_equal ["GEOADD", "locations", "NX", -122.4194, 37.7749, "San Francisco"], @client.last_command
  end

  # ============================================================
  # geoadd - with XX option
  # ============================================================

  def test_geoadd_with_xx
    @client.geoadd("locations", -122.4194, 37.7749, "San Francisco", xx: true)

    assert_equal ["GEOADD", "locations", "XX", -122.4194, 37.7749, "San Francisco"], @client.last_command
  end

  # ============================================================
  # geoadd - with CH option
  # ============================================================

  def test_geoadd_with_ch
    @client.geoadd("locations", -122.4194, 37.7749, "San Francisco", ch: true)

    assert_equal ["GEOADD", "locations", "CH", -122.4194, 37.7749, "San Francisco"], @client.last_command
  end

  # ============================================================
  # geoadd - with all options combined
  # ============================================================

  def test_geoadd_with_nx_and_ch
    @client.geoadd("locations", -122.4194, 37.7749, "San Francisco", nx: true, ch: true)

    assert_equal ["GEOADD", "locations", "NX", "CH", -122.4194, 37.7749, "San Francisco"], @client.last_command
  end

  def test_geoadd_with_xx_and_ch
    @client.geoadd("locations", -122.4194, 37.7749, "San Francisco", xx: true, ch: true)

    assert_equal ["GEOADD", "locations", "XX", "CH", -122.4194, 37.7749, "San Francisco"], @client.last_command
  end

  # ============================================================
  # geoadd - multiple members
  # ============================================================

  def test_geoadd_multiple_members
    @client.geoadd("locations",
                   -122.4194, 37.7749, "San Francisco",
                   -118.2437, 34.0522, "Los Angeles")

    assert_equal [
      "GEOADD", "locations",
      -122.4194, 37.7749, "San Francisco",
      -118.2437, 34.0522, "Los Angeles",
    ], @client.last_command
  end

  # ============================================================
  # geoadd - no options (nx/xx/ch all false)
  # ============================================================

  def test_geoadd_no_options_all_false
    @client.geoadd("locations", 1.0, 2.0, "place", nx: false, xx: false, ch: false)

    assert_equal ["GEOADD", "locations", 1.0, 2.0, "place"], @client.last_command
  end

  # ============================================================
  # geopos - single member fast path
  # ============================================================

  def test_geopos_single_member_fast_path
    result = @client.geopos("locations", "San Francisco")

    assert_equal ["GEOPOS", "locations", "San Francisco"], @client.last_command
    assert_equal [[1.0, 2.0]], result
  end

  # ============================================================
  # geopos - multiple members
  # ============================================================

  def test_geopos_multiple_members
    # Override call for multi-member to return array of positions
    def @client.call(*args)
      @last_command = args
      [["3.0", "4.0"], ["5.0", "6.0"]]
    end

    result = @client.geopos("locations", "San Francisco", "Los Angeles")

    assert_equal ["GEOPOS", "locations", "San Francisco", "Los Angeles"], @client.last_command
    assert_equal [[3.0, 4.0], [5.0, 6.0]], result
  end

  # ============================================================
  # geopos - nil position (non-existing member)
  # ============================================================

  def test_geopos_nil_position
    def @client.call(*args)
      @last_command = args
      [nil, ["1.0", "2.0"]]
    end

    result = @client.geopos("locations", "NonExistent", "Existing")

    assert_nil result[0]
    assert_equal [1.0, 2.0], result[1]
  end

  # ============================================================
  # geodist - default unit (meters)
  # ============================================================

  def test_geodist_default_unit
    @client.geodist("locations", "A", "B")

    assert_equal %w[GEODIST locations A B M], @client.last_command
  end

  # ============================================================
  # geodist - kilometers
  # ============================================================

  def test_geodist_km
    @client.geodist("locations", "A", "B", "km")

    assert_equal %w[GEODIST locations A B KM], @client.last_command
  end

  # ============================================================
  # geodist - miles
  # ============================================================

  def test_geodist_mi
    @client.geodist("locations", "A", "B", "mi")

    assert_equal %w[GEODIST locations A B MI], @client.last_command
  end

  # ============================================================
  # geodist - feet
  # ============================================================

  def test_geodist_ft
    @client.geodist("locations", "A", "B", "ft")

    assert_equal %w[GEODIST locations A B FT], @client.last_command
  end

  # ============================================================
  # geodist - symbol unit conversion
  # ============================================================

  def test_geodist_symbol_unit
    @client.geodist("locations", "A", "B", :km)

    assert_equal %w[GEODIST locations A B KM], @client.last_command
  end

  # ============================================================
  # geohash - single member fast path
  # ============================================================

  def test_geohash_single_member_fast_path
    result = @client.geohash("locations", "San Francisco")

    assert_equal ["GEOHASH", "locations", "San Francisco"], @client.last_command
    assert_equal ["abc123"], result
  end

  # ============================================================
  # geohash - multiple members
  # ============================================================

  def test_geohash_multiple_members
    def @client.call(*args)
      @last_command = args
      %w[hash1 hash2]
    end

    result = @client.geohash("locations", "SF", "LA")

    assert_equal %w[GEOHASH locations SF LA], @client.last_command
    assert_equal %w[hash1 hash2], result
  end

  # ============================================================
  # geosearch - frommember + byradius
  # ============================================================

  def test_geosearch_frommember_byradius
    @client.geosearch("locations", frommember: "SF", byradius: 100, unit: "km")

    assert_equal ["GEOSEARCH", "locations", "FROMMEMBER", "SF", "BYRADIUS", 100, "KM"], @client.last_command
  end

  # ============================================================
  # geosearch - fromlonlat + byradius
  # ============================================================

  def test_geosearch_fromlonlat_byradius
    @client.geosearch("locations", fromlonlat: [-122.4, 37.8], byradius: 50, unit: "mi")

    assert_equal ["GEOSEARCH", "locations", "FROMLONLAT", -122.4, 37.8, "BYRADIUS", 50, "MI"], @client.last_command
  end

  # ============================================================
  # geosearch - frommember + bybox
  # ============================================================

  def test_geosearch_frommember_bybox
    @client.geosearch("locations", frommember: "SF", bybox: [200, 300], unit: "km")

    assert_equal ["GEOSEARCH", "locations", "FROMMEMBER", "SF", "BYBOX", 200, 300, "KM"], @client.last_command
  end

  # ============================================================
  # geosearch - fromlonlat + bybox
  # ============================================================

  def test_geosearch_fromlonlat_bybox
    @client.geosearch("locations", fromlonlat: [-122.4, 37.8], bybox: [100, 200], unit: "ft")

    assert_equal [
      "GEOSEARCH", "locations", "FROMLONLAT", -122.4, 37.8, "BYBOX", 100, 200, "FT",
    ], @client.last_command
  end

  # ============================================================
  # geosearch - missing frommember and fromlonlat (ArgumentError)
  # ============================================================

  def test_geosearch_missing_from_raises_argument_error
    assert_raises(ArgumentError) do
      @client.geosearch("locations", byradius: 100)
    end
  end

  # ============================================================
  # geosearch - missing byradius and bybox (ArgumentError)
  # ============================================================

  def test_geosearch_missing_shape_raises_argument_error
    assert_raises(ArgumentError) do
      @client.geosearch("locations", frommember: "SF")
    end
  end

  # ============================================================
  # geosearch - with count (without any)
  # ============================================================

  def test_geosearch_with_count
    @client.geosearch("locations", frommember: "SF", byradius: 100, unit: "km", count: 5)

    assert_equal [
      "GEOSEARCH", "locations", "FROMMEMBER", "SF", "BYRADIUS", 100, "KM", "COUNT", 5,
    ], @client.last_command
  end

  # ============================================================
  # geosearch - with count and any
  # ============================================================

  def test_geosearch_with_count_and_any
    @client.geosearch("locations", frommember: "SF", byradius: 100, unit: "km", count: 5, any: true)

    assert_equal [
      "GEOSEARCH", "locations", "FROMMEMBER", "SF", "BYRADIUS", 100, "KM", "COUNT", 5, "ANY",
    ], @client.last_command
  end

  # ============================================================
  # geosearch - with count but any=false (nil compacted)
  # ============================================================

  def test_geosearch_with_count_any_false
    @client.geosearch("locations", frommember: "SF", byradius: 100, unit: "km", count: 3, any: false)
    # When any is false, (OPT_ANY if false) => nil, which is compacted out
    assert_equal [
      "GEOSEARCH", "locations", "FROMMEMBER", "SF", "BYRADIUS", 100, "KM", "COUNT", 3,
    ], @client.last_command
  end

  # ============================================================
  # geosearch - sort :asc
  # ============================================================

  def test_geosearch_sort_asc_symbol
    @client.geosearch("locations", frommember: "SF", byradius: 100, unit: "km", sort: :asc)

    assert_includes @client.last_command, "ASC"
  end

  # ============================================================
  # geosearch - sort :desc
  # ============================================================

  def test_geosearch_sort_desc_symbol
    @client.geosearch("locations", frommember: "SF", byradius: 100, unit: "km", sort: :desc)

    assert_includes @client.last_command, "DESC"
  end

  # ============================================================
  # geosearch - sort "ASC" string
  # ============================================================

  def test_geosearch_sort_asc_string
    @client.geosearch("locations", frommember: "SF", byradius: 100, unit: "km", sort: "ASC")

    assert_includes @client.last_command, "ASC"
  end

  # ============================================================
  # geosearch - sort "asc" lowercase string
  # ============================================================

  def test_geosearch_sort_asc_lowercase_string
    @client.geosearch("locations", frommember: "SF", byradius: 100, unit: "km", sort: "asc")

    assert_includes @client.last_command, "ASC"
  end

  # ============================================================
  # geosearch - sort "DESC" string
  # ============================================================

  def test_geosearch_sort_desc_string
    @client.geosearch("locations", frommember: "SF", byradius: 100, unit: "km", sort: "DESC")

    assert_includes @client.last_command, "DESC"
  end

  # ============================================================
  # geosearch - sort "desc" lowercase string
  # ============================================================

  def test_geosearch_sort_desc_lowercase_string
    @client.geosearch("locations", frommember: "SF", byradius: 100, unit: "km", sort: "desc")

    assert_includes @client.last_command, "DESC"
  end

  # ============================================================
  # geosearch - sort nil (no sort added)
  # ============================================================

  def test_geosearch_sort_nil
    @client.geosearch("locations", frommember: "SF", byradius: 100, unit: "km", sort: nil)

    refute_includes @client.last_command, "ASC"
    refute_includes @client.last_command, "DESC"
  end

  # ============================================================
  # geosearch - sort unrecognized value (no sort added)
  # ============================================================

  def test_geosearch_sort_unrecognized_value
    @client.geosearch("locations", frommember: "SF", byradius: 100, unit: "km", sort: "random")

    refute_includes @client.last_command, "ASC"
    refute_includes @client.last_command, "DESC"
  end

  # ============================================================
  # geosearch - withcoord
  # ============================================================

  def test_geosearch_withcoord
    @client.geosearch("locations", frommember: "SF", byradius: 100, unit: "km", withcoord: true)

    assert_includes @client.last_command, "WITHCOORD"
  end

  def test_geosearch_without_withcoord
    @client.geosearch("locations", frommember: "SF", byradius: 100, unit: "km", withcoord: false)

    refute_includes @client.last_command, "WITHCOORD"
  end

  # ============================================================
  # geosearch - withdist
  # ============================================================

  def test_geosearch_withdist
    @client.geosearch("locations", frommember: "SF", byradius: 100, unit: "km", withdist: true)

    assert_includes @client.last_command, "WITHDIST"
  end

  def test_geosearch_without_withdist
    @client.geosearch("locations", frommember: "SF", byradius: 100, unit: "km", withdist: false)

    refute_includes @client.last_command, "WITHDIST"
  end

  # ============================================================
  # geosearch - withhash
  # ============================================================

  def test_geosearch_withhash
    @client.geosearch("locations", frommember: "SF", byradius: 100, unit: "km", withhash: true)

    assert_includes @client.last_command, "WITHHASH"
  end

  def test_geosearch_without_withhash
    @client.geosearch("locations", frommember: "SF", byradius: 100, unit: "km", withhash: false)

    refute_includes @client.last_command, "WITHHASH"
  end

  # ============================================================
  # geosearch - all options combined
  # ============================================================

  def test_geosearch_all_options
    @client.geosearch("locations",
                      frommember: "SF",
                      byradius: 100,
                      unit: "km",
                      count: 10,
                      any: true,
                      sort: :asc,
                      withcoord: true,
                      withdist: true,
                      withhash: true)
    expected = [
      "GEOSEARCH", "locations", "FROMMEMBER", "SF",
      "BYRADIUS", 100, "KM",
      "COUNT", 10, "ANY",
      "ASC",
      "WITHCOORD", "WITHDIST", "WITHHASH",
    ]

    assert_equal expected, @client.last_command
  end

  # ============================================================
  # geosearchstore - frommember + byradius
  # ============================================================

  def test_geosearchstore_frommember_byradius
    @client.geosearchstore("dest", "source", frommember: "SF", byradius: 100, unit: "km")

    assert_equal [
      "GEOSEARCHSTORE", "dest", "source", "FROMMEMBER", "SF", "BYRADIUS", 100, "KM",
    ], @client.last_command
  end

  # ============================================================
  # geosearchstore - fromlonlat + byradius
  # ============================================================

  def test_geosearchstore_fromlonlat_byradius
    @client.geosearchstore("dest", "source", fromlonlat: [-122.4, 37.8], byradius: 50, unit: "mi")

    assert_equal [
      "GEOSEARCHSTORE", "dest", "source", "FROMLONLAT", -122.4, 37.8, "BYRADIUS", 50, "MI",
    ], @client.last_command
  end

  # ============================================================
  # geosearchstore - frommember + bybox
  # ============================================================

  def test_geosearchstore_frommember_bybox
    @client.geosearchstore("dest", "source", frommember: "SF", bybox: [200, 300], unit: "km")

    assert_equal [
      "GEOSEARCHSTORE", "dest", "source", "FROMMEMBER", "SF", "BYBOX", 200, 300, "KM",
    ], @client.last_command
  end

  # ============================================================
  # geosearchstore - fromlonlat + bybox
  # ============================================================

  def test_geosearchstore_fromlonlat_bybox
    @client.geosearchstore("dest", "source", fromlonlat: [10.0, 20.0], bybox: [100, 200], unit: "ft")

    assert_equal [
      "GEOSEARCHSTORE", "dest", "source", "FROMLONLAT", 10.0, 20.0, "BYBOX", 100, 200, "FT",
    ], @client.last_command
  end

  # ============================================================
  # geosearchstore - missing from (ArgumentError)
  # ============================================================

  def test_geosearchstore_missing_from_raises_argument_error
    assert_raises(ArgumentError) do
      @client.geosearchstore("dest", "source", byradius: 100)
    end
  end

  # ============================================================
  # geosearchstore - missing shape (ArgumentError)
  # ============================================================

  def test_geosearchstore_missing_shape_raises_argument_error
    assert_raises(ArgumentError) do
      @client.geosearchstore("dest", "source", frommember: "SF")
    end
  end

  # ============================================================
  # geosearchstore - with count (without any)
  # ============================================================

  def test_geosearchstore_with_count
    @client.geosearchstore("dest", "source", frommember: "SF", byradius: 100, unit: "km", count: 5)

    assert_equal [
      "GEOSEARCHSTORE", "dest", "source", "FROMMEMBER", "SF", "BYRADIUS", 100, "KM", "COUNT", 5,
    ], @client.last_command
  end

  # ============================================================
  # geosearchstore - with count and any
  # ============================================================

  def test_geosearchstore_with_count_and_any
    @client.geosearchstore("dest", "source", frommember: "SF", byradius: 100, unit: "km", count: 5, any: true)

    assert_equal [
      "GEOSEARCHSTORE", "dest", "source", "FROMMEMBER", "SF", "BYRADIUS", 100, "KM", "COUNT", 5, "ANY",
    ], @client.last_command
  end

  # ============================================================
  # geosearchstore - with count, any=false (nil compacted)
  # ============================================================

  def test_geosearchstore_with_count_any_false
    @client.geosearchstore("dest", "source", frommember: "SF", byradius: 100, unit: "km", count: 3, any: false)

    assert_equal [
      "GEOSEARCHSTORE", "dest", "source", "FROMMEMBER", "SF", "BYRADIUS", 100, "KM", "COUNT", 3,
    ], @client.last_command
  end

  # ============================================================
  # geosearchstore - sort :asc
  # ============================================================

  def test_geosearchstore_sort_asc
    @client.geosearchstore("dest", "source", frommember: "SF", byradius: 100, unit: "km", sort: :asc)

    assert_includes @client.last_command, "ASC"
  end

  # ============================================================
  # geosearchstore - sort :desc
  # ============================================================

  def test_geosearchstore_sort_desc
    @client.geosearchstore("dest", "source", frommember: "SF", byradius: 100, unit: "km", sort: :desc)

    assert_includes @client.last_command, "DESC"
  end

  # ============================================================
  # geosearchstore - sort "ASC" string
  # ============================================================

  def test_geosearchstore_sort_asc_string
    @client.geosearchstore("dest", "source", frommember: "SF", byradius: 100, unit: "km", sort: "ASC")

    assert_includes @client.last_command, "ASC"
  end

  # ============================================================
  # geosearchstore - sort "asc" lowercase string
  # ============================================================

  def test_geosearchstore_sort_asc_lowercase_string
    @client.geosearchstore("dest", "source", frommember: "SF", byradius: 100, unit: "km", sort: "asc")

    assert_includes @client.last_command, "ASC"
  end

  # ============================================================
  # geosearchstore - sort "DESC" string
  # ============================================================

  def test_geosearchstore_sort_desc_string
    @client.geosearchstore("dest", "source", frommember: "SF", byradius: 100, unit: "km", sort: "DESC")

    assert_includes @client.last_command, "DESC"
  end

  # ============================================================
  # geosearchstore - sort "desc" lowercase string
  # ============================================================

  def test_geosearchstore_sort_desc_lowercase_string
    @client.geosearchstore("dest", "source", frommember: "SF", byradius: 100, unit: "km", sort: "desc")

    assert_includes @client.last_command, "DESC"
  end

  # ============================================================
  # geosearchstore - sort nil (no sort)
  # ============================================================

  def test_geosearchstore_sort_nil
    @client.geosearchstore("dest", "source", frommember: "SF", byradius: 100, unit: "km", sort: nil)

    refute_includes @client.last_command, "ASC"
    refute_includes @client.last_command, "DESC"
  end

  # ============================================================
  # geosearchstore - storedist true
  # ============================================================

  def test_geosearchstore_storedist
    @client.geosearchstore("dest", "source", frommember: "SF", byradius: 100, unit: "km", storedist: true)

    assert_includes @client.last_command, "STOREDIST"
  end

  # ============================================================
  # geosearchstore - storedist false
  # ============================================================

  def test_geosearchstore_storedist_false
    @client.geosearchstore("dest", "source", frommember: "SF", byradius: 100, unit: "km", storedist: false)

    refute_includes @client.last_command, "STOREDIST"
  end

  # ============================================================
  # geosearchstore - all options combined
  # ============================================================

  def test_geosearchstore_all_options
    @client.geosearchstore("dest", "source",
                           fromlonlat: [-122.4, 37.8],
                           bybox: [200, 300],
                           unit: "km",
                           count: 10,
                           any: true,
                           sort: :desc,
                           storedist: true)
    expected = [
      "GEOSEARCHSTORE", "dest", "source",
      "FROMLONLAT", -122.4, 37.8,
      "BYBOX", 200, 300, "KM",
      "COUNT", 10, "ANY",
      "DESC",
      "STOREDIST",
    ]

    assert_equal expected, @client.last_command
  end

  # ============================================================
  # georadiusbymember - basic (no options)
  # ============================================================

  def test_georadiusbymember_basic
    @client.georadiusbymember("locations", "SF", 100)

    assert_equal ["GEORADIUSBYMEMBER", "locations", "SF", 100, "M"], @client.last_command
  end

  # ============================================================
  # georadiusbymember - with unit
  # ============================================================

  def test_georadiusbymember_with_unit
    @client.georadiusbymember("locations", "SF", 100, "km")

    assert_equal ["GEORADIUSBYMEMBER", "locations", "SF", 100, "KM"], @client.last_command
  end

  # ============================================================
  # georadiusbymember - with count option
  # ============================================================

  def test_georadiusbymember_with_count
    @client.georadiusbymember("locations", "SF", 100, "km", count: 5)

    assert_equal ["GEORADIUSBYMEMBER", "locations", "SF", 100, "KM", "COUNT", 5], @client.last_command
  end

  # ============================================================
  # georadiusbymember - with sort :asc
  # ============================================================

  def test_georadiusbymember_with_sort_asc
    @client.georadiusbymember("locations", "SF", 100, "km", sort: :asc)

    assert_includes @client.last_command, "ASC"
  end

  # ============================================================
  # georadiusbymember - with sort :desc
  # ============================================================

  def test_georadiusbymember_with_sort_desc
    @client.georadiusbymember("locations", "SF", 100, "km", sort: :desc)

    assert_includes @client.last_command, "DESC"
  end

  # ============================================================
  # georadiusbymember - sort not :asc or :desc (no sort added)
  # ============================================================

  def test_georadiusbymember_with_sort_other
    @client.georadiusbymember("locations", "SF", 100, "km", sort: :none)

    refute_includes @client.last_command, "ASC"
    refute_includes @client.last_command, "DESC"
  end

  # ============================================================
  # georadiusbymember - with withcoord
  # ============================================================

  def test_georadiusbymember_with_withcoord
    @client.georadiusbymember("locations", "SF", 100, "km", withcoord: true)

    assert_includes @client.last_command, "WITHCOORD"
  end

  # ============================================================
  # georadiusbymember - with withdist
  # ============================================================

  def test_georadiusbymember_with_withdist
    @client.georadiusbymember("locations", "SF", 100, "km", withdist: true)

    assert_includes @client.last_command, "WITHDIST"
  end

  # ============================================================
  # georadiusbymember - with withhash
  # ============================================================

  def test_georadiusbymember_with_withhash
    @client.georadiusbymember("locations", "SF", 100, "km", withhash: true)

    assert_includes @client.last_command, "WITHHASH"
  end

  # ============================================================
  # georadiusbymember - all options combined
  # ============================================================

  def test_georadiusbymember_all_options
    @client.georadiusbymember("locations", "SF", 100, "km",
                              count: 5, sort: :asc, withcoord: true, withdist: true, withhash: true)
    expected = [
      "GEORADIUSBYMEMBER", "locations", "SF", 100, "KM",
      "COUNT", 5, "ASC", "WITHCOORD", "WITHDIST", "WITHHASH",
    ]

    assert_equal expected, @client.last_command
  end

  # ============================================================
  # georadius - basic (no options)
  # ============================================================

  def test_georadius_basic
    @client.georadius("locations", -122.4, 37.8, 100)

    assert_equal ["GEORADIUS", "locations", -122.4, 37.8, 100, "M"], @client.last_command
  end

  # ============================================================
  # georadius - with unit
  # ============================================================

  def test_georadius_with_unit
    @client.georadius("locations", -122.4, 37.8, 100, "km")

    assert_equal ["GEORADIUS", "locations", -122.4, 37.8, 100, "KM"], @client.last_command
  end

  # ============================================================
  # georadius - with count
  # ============================================================

  def test_georadius_with_count
    @client.georadius("locations", -122.4, 37.8, 100, "km", count: 5)

    assert_equal ["GEORADIUS", "locations", -122.4, 37.8, 100, "KM", "COUNT", 5], @client.last_command
  end

  # ============================================================
  # georadius - with sort :asc
  # ============================================================

  def test_georadius_with_sort_asc
    @client.georadius("locations", -122.4, 37.8, 100, "km", sort: :asc)

    assert_includes @client.last_command, "ASC"
  end

  # ============================================================
  # georadius - with sort :desc
  # ============================================================

  def test_georadius_with_sort_desc
    @client.georadius("locations", -122.4, 37.8, 100, "km", sort: :desc)

    assert_includes @client.last_command, "DESC"
  end

  # ============================================================
  # georadius - with withcoord
  # ============================================================

  def test_georadius_with_withcoord
    @client.georadius("locations", -122.4, 37.8, 100, "km", withcoord: true)

    assert_includes @client.last_command, "WITHCOORD"
  end

  # ============================================================
  # georadius - with withdist
  # ============================================================

  def test_georadius_with_withdist
    @client.georadius("locations", -122.4, 37.8, 100, "km", withdist: true)

    assert_includes @client.last_command, "WITHDIST"
  end

  # ============================================================
  # georadius - with withhash
  # ============================================================

  def test_georadius_with_withhash
    @client.georadius("locations", -122.4, 37.8, 100, "km", withhash: true)

    assert_includes @client.last_command, "WITHHASH"
  end

  # ============================================================
  # georadius - all options combined
  # ============================================================

  def test_georadius_all_options
    @client.georadius("locations", -122.4, 37.8, 100, "km",
                      count: 10, sort: :desc, withcoord: true, withdist: true, withhash: true)
    expected = [
      "GEORADIUS", "locations", -122.4, 37.8, 100, "KM",
      "COUNT", 10, "DESC", "WITHCOORD", "WITHDIST", "WITHHASH",
    ]

    assert_equal expected, @client.last_command
  end

  # ============================================================
  # georadius - no options (empty hash)
  # ============================================================

  def test_georadius_no_options
    @client.georadius("locations", -122.4, 37.8, 100, "m")

    assert_equal ["GEORADIUS", "locations", -122.4, 37.8, 100, "M"], @client.last_command
  end

  # ============================================================
  # georadiusbymember - no options (empty hash)
  # ============================================================

  def test_georadiusbymember_no_options
    @client.georadiusbymember("locations", "SF", 50, "m")

    assert_equal ["GEORADIUSBYMEMBER", "locations", "SF", 50, "M"], @client.last_command
  end

  # ============================================================
  # geosearch - default unit (m)
  # ============================================================

  def test_geosearch_default_unit
    @client.geosearch("locations", frommember: "SF", byradius: 100)

    assert_equal ["GEOSEARCH", "locations", "FROMMEMBER", "SF", "BYRADIUS", 100, "M"], @client.last_command
  end

  # ============================================================
  # geosearchstore - default unit (m)
  # ============================================================

  def test_geosearchstore_default_unit
    @client.geosearchstore("dest", "source", frommember: "SF", byradius: 100)

    assert_equal [
      "GEOSEARCHSTORE", "dest", "source", "FROMMEMBER", "SF", "BYRADIUS", 100, "M",
    ], @client.last_command
  end
end
