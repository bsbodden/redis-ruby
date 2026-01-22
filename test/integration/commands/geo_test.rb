# frozen_string_literal: true

require "test_helper"

class GeoIntegrationTest < RedisRubyTestCase
  use_testcontainers!

  def setup
    super
    @geo_key = "@geo_key:#{SecureRandom.hex(4)}"
  end

  def teardown
    begin
      redis.del(@geo_key)
    rescue StandardError
      nil
    end
    begin
      redis.del("geo:nearby")
    rescue StandardError
      nil
    end
    super
  end

  # GEOADD tests
  def test_geoadd_single_location
    result = redis.geoadd(@geo_key, -122.4194, 37.7749, "San Francisco")

    assert_equal 1, result
  end

  def test_geoadd_multiple_locations
    result = redis.geoadd(@geo_key,
                          -122.4194, 37.7749, "San Francisco",
                          -118.2437, 34.0522, "Los Angeles",
                          -73.9857, 40.7484, "New York")

    assert_equal 3, result
  end

  def test_geoadd_with_nx_option
    redis.geoadd(@geo_key, -122.4194, 37.7749, "San Francisco")
    # NX - only add new elements
    result = redis.geoadd(@geo_key, -122.4194, 37.7749, "San Francisco", nx: true)

    assert_equal 0, result
  end

  def test_geoadd_with_xx_option
    # XX - only update existing elements
    result = redis.geoadd(@geo_key, -122.4194, 37.7749, "San Francisco", xx: true)

    assert_equal 0, result

    redis.geoadd(@geo_key, -122.4194, 37.7749, "San Francisco")
    result = redis.geoadd(@geo_key, -122.5, 37.8, "San Francisco", xx: true)

    assert_equal 0, result # Updated, not added
  end

  def test_geoadd_with_ch_option
    redis.geoadd(@geo_key, -122.4194, 37.7749, "San Francisco")
    # CH - return number of changed elements
    result = redis.geoadd(@geo_key, -122.5, 37.8, "San Francisco", ch: true)

    assert_equal 1, result
  end

  # GEOPOS tests
  def test_geopos_single_member
    redis.geoadd(@geo_key, -122.4194, 37.7749, "San Francisco")
    result = redis.geopos(@geo_key, "San Francisco")

    assert_equal 1, result.length
    assert_in_delta(-122.4194, result[0][0], 0.001)
    assert_in_delta(37.7749, result[0][1], 0.001)
  end

  def test_geopos_multiple_members
    redis.geoadd(@geo_key,
                 -122.4194, 37.7749, "San Francisco",
                 -118.2437, 34.0522, "Los Angeles")
    result = redis.geopos(@geo_key, "San Francisco", "Los Angeles", "Unknown")

    assert_equal 3, result.length
    refute_nil result[0]
    refute_nil result[1]
    assert_nil result[2] # Unknown member
  end

  def test_geopos_nonexistent_member
    result = redis.geopos(@geo_key, "Unknown")

    assert_equal [nil], result
  end

  # GEODIST tests
  def test_geodist_default_meters
    redis.geoadd(@geo_key,
                 -122.4194, 37.7749, "San Francisco",
                 -118.2437, 34.0522, "Los Angeles")
    result = redis.geodist(@geo_key, "San Francisco", "Los Angeles")

    # Distance is approximately 559 km
    assert_in_delta(559_000, result.to_f, 5000)
  end

  def test_geodist_kilometers
    redis.geoadd(@geo_key,
                 -122.4194, 37.7749, "San Francisco",
                 -118.2437, 34.0522, "Los Angeles")
    result = redis.geodist(@geo_key, "San Francisco", "Los Angeles", "km")

    assert_in_delta(559, result.to_f, 5)
  end

  def test_geodist_miles
    redis.geoadd(@geo_key,
                 -122.4194, 37.7749, "San Francisco",
                 -118.2437, 34.0522, "Los Angeles")
    result = redis.geodist(@geo_key, "San Francisco", "Los Angeles", "mi")

    assert_in_delta(347, result.to_f, 5)
  end

  def test_geodist_nonexistent_member
    redis.geoadd(@geo_key, -122.4194, 37.7749, "San Francisco")
    result = redis.geodist(@geo_key, "San Francisco", "Unknown")

    assert_nil result
  end

  # GEOHASH tests
  def test_geohash_single_member
    redis.geoadd(@geo_key, -122.4194, 37.7749, "San Francisco")
    result = redis.geohash(@geo_key, "San Francisco")

    assert_equal 1, result.length
    assert_kind_of String, result[0]
    assert_equal 11, result[0].length # Default precision
  end

  def test_geohash_multiple_members
    redis.geoadd(@geo_key,
                 -122.4194, 37.7749, "San Francisco",
                 -118.2437, 34.0522, "Los Angeles")
    result = redis.geohash(@geo_key, "San Francisco", "Los Angeles", "Unknown")

    assert_equal 3, result.length
    refute_nil result[0]
    refute_nil result[1]
    assert_nil result[2]
  end

  # GEOSEARCH tests (Redis 6.2+)
  def test_geosearch_by_radius_from_member
    redis.geoadd(@geo_key,
                 -122.4194, 37.7749, "San Francisco",
                 -122.2711, 37.8044, "Oakland",
                 -118.2437, 34.0522, "Los Angeles")

    result = redis.geosearch(@geo_key,
                             frommember: "San Francisco",
                             byradius: 50,
                             unit: "km")

    assert_includes result, "San Francisco"
    assert_includes result, "Oakland"
    refute_includes result, "Los Angeles"
  end

  def test_geosearch_by_radius_from_coordinates
    redis.geoadd(@geo_key,
                 -122.4194, 37.7749, "San Francisco",
                 -122.2711, 37.8044, "Oakland",
                 -118.2437, 34.0522, "Los Angeles")

    result = redis.geosearch(@geo_key,
                             fromlonlat: [-122.4, 37.8],
                             byradius: 50,
                             unit: "km")

    assert_includes result, "San Francisco"
    assert_includes result, "Oakland"
    refute_includes result, "Los Angeles"
  end

  def test_geosearch_by_box
    redis.geoadd(@geo_key,
                 -122.4194, 37.7749, "San Francisco",
                 -122.2711, 37.8044, "Oakland",
                 -118.2437, 34.0522, "Los Angeles")

    result = redis.geosearch(@geo_key,
                             fromlonlat: [-122.4, 37.8],
                             bybox: [100, 100],
                             unit: "km")

    assert_includes result, "San Francisco"
    assert_includes result, "Oakland"
  end

  def test_geosearch_with_count
    redis.geoadd(@geo_key,
                 -122.4194, 37.7749, "San Francisco",
                 -122.2711, 37.8044, "Oakland",
                 -122.0322, 37.3688, "San Jose")

    result = redis.geosearch(@geo_key,
                             frommember: "San Francisco",
                             byradius: 100,
                             unit: "km",
                             count: 2)

    assert_equal 2, result.length
  end

  def test_geosearch_with_distance
    redis.geoadd(@geo_key,
                 -122.4194, 37.7749, "San Francisco",
                 -122.2711, 37.8044, "Oakland")

    result = redis.geosearch(@geo_key,
                             frommember: "San Francisco",
                             byradius: 50,
                             unit: "km",
                             withdist: true)

    assert_kind_of Array, result
    # Result format: [[member, distance], ...]
    assert(result.any? { |r| r[0] == "Oakland" })
  end

  def test_geosearch_with_coordinates
    redis.geoadd(@geo_key,
                 -122.4194, 37.7749, "San Francisco",
                 -122.2711, 37.8044, "Oakland")

    result = redis.geosearch(@geo_key,
                             frommember: "San Francisco",
                             byradius: 50,
                             unit: "km",
                             withcoord: true)

    assert_kind_of Array, result
  end

  def test_geosearch_with_hash
    redis.geoadd(@geo_key,
                 -122.4194, 37.7749, "San Francisco",
                 -122.2711, 37.8044, "Oakland")

    result = redis.geosearch(@geo_key,
                             frommember: "San Francisco",
                             byradius: 50,
                             unit: "km",
                             withhash: true)

    assert_kind_of Array, result
  end

  def test_geosearch_asc_order
    redis.geoadd(@geo_key,
                 -122.4194, 37.7749, "San Francisco",
                 -122.2711, 37.8044, "Oakland",
                 -122.0322, 37.3688, "San Jose")

    result = redis.geosearch(@geo_key,
                             frommember: "San Francisco",
                             byradius: 100,
                             unit: "km",
                             sort: :asc)

    assert_equal "San Francisco", result[0] # Closest first
  end

  def test_geosearch_desc_order
    redis.geoadd(@geo_key,
                 -122.4194, 37.7749, "San Francisco",
                 -122.2711, 37.8044, "Oakland",
                 -122.0322, 37.3688, "San Jose")

    result = redis.geosearch(@geo_key,
                             frommember: "San Francisco",
                             byradius: 100,
                             unit: "km",
                             sort: :desc)

    # Farthest first (San Jose is farthest from SF)
    assert_equal "San Jose", result[0]
  end

  # GEOSEARCHSTORE tests
  def test_geosearchstore
    redis.geoadd(@geo_key,
                 -122.4194, 37.7749, "San Francisco",
                 -122.2711, 37.8044, "Oakland",
                 -118.2437, 34.0522, "Los Angeles")

    result = redis.geosearchstore("geo:nearby", @geo_key,
                                  frommember: "San Francisco",
                                  byradius: 50,
                                  unit: "km")

    assert_equal 2, result
    redis.del("geo:nearby")
  end

  def test_geosearchstore_storedist
    redis.geoadd(@geo_key,
                 -122.4194, 37.7749, "San Francisco",
                 -122.2711, 37.8044, "Oakland")

    result = redis.geosearchstore("geo:nearby", @geo_key,
                                  frommember: "San Francisco",
                                  byradius: 50,
                                  unit: "km",
                                  storedist: true)

    assert_equal 2, result
    # Stored as sorted set with distance as score
    score = redis.zscore("geo:nearby", "Oakland")

    refute_nil score
    redis.del("geo:nearby")
  end

  # Legacy GEORADIUSBYMEMBER tests
  def test_georadiusbymember_basic
    redis.geoadd(@geo_key,
                 -122.4194, 37.7749, "San Francisco",
                 -122.2711, 37.8044, "Oakland",
                 -118.2437, 34.0522, "Los Angeles")

    result = redis.georadiusbymember(@geo_key, "San Francisco", 50, "km")

    assert_includes result, "San Francisco"
    assert_includes result, "Oakland"
    refute_includes result, "Los Angeles"
  end

  def test_georadiusbymember_with_options
    redis.geoadd(@geo_key,
                 -122.4194, 37.7749, "San Francisco",
                 -122.2711, 37.8044, "Oakland",
                 -122.0322, 37.3688, "San Jose")

    result = redis.georadiusbymember(@geo_key, "San Francisco", 100, "km",
                                     count: 2, sort: :asc, withdist: true)

    assert_kind_of Array, result
    assert_operator result.length, :<=, 2
  end

  # Legacy GEORADIUS tests
  def test_georadius_basic
    redis.geoadd(@geo_key,
                 -122.4194, 37.7749, "San Francisco",
                 -122.2711, 37.8044, "Oakland",
                 -118.2437, 34.0522, "Los Angeles")

    result = redis.georadius(@geo_key, -122.4, 37.8, 50, "km")

    assert_includes result, "San Francisco"
    assert_includes result, "Oakland"
    refute_includes result, "Los Angeles"
  end

  def test_georadius_with_options
    redis.geoadd(@geo_key,
                 -122.4194, 37.7749, "San Francisco",
                 -122.2711, 37.8044, "Oakland",
                 -122.0322, 37.3688, "San Jose")

    result = redis.georadius(@geo_key, -122.4, 37.8, 100, "km",
                             count: 2, sort: :desc, withcoord: true, withhash: true)

    assert_kind_of Array, result
    assert_operator result.length, :<=, 2
  end

  # Error case tests
  def test_geosearch_missing_from_raises_error
    redis.geoadd(@geo_key, -122.4194, 37.7749, "San Francisco")

    assert_raises(ArgumentError) do
      redis.geosearch(@geo_key, byradius: 50, unit: "km")
    end
  end

  def test_geosearch_missing_by_raises_error
    redis.geoadd(@geo_key, -122.4194, 37.7749, "San Francisco")

    assert_raises(ArgumentError) do
      redis.geosearch(@geo_key, frommember: "San Francisco")
    end
  end

  def test_geosearchstore_missing_from_raises_error
    redis.geoadd(@geo_key, -122.4194, 37.7749, "San Francisco")

    assert_raises(ArgumentError) do
      redis.geosearchstore("geo:nearby", @geo_key, byradius: 50, unit: "km")
    end
  end

  def test_geosearchstore_missing_by_raises_error
    redis.geoadd(@geo_key, -122.4194, 37.7749, "San Francisco")

    assert_raises(ArgumentError) do
      redis.geosearchstore("geo:nearby", @geo_key, frommember: "San Francisco")
    end
  end

  # GEOSEARCH with ANY option
  def test_geosearch_with_count_any
    redis.geoadd(@geo_key,
                 -122.4194, 37.7749, "San Francisco",
                 -122.2711, 37.8044, "Oakland",
                 -122.0322, 37.3688, "San Jose",
                 -121.8863, 37.3382, "Santa Clara")

    result = redis.geosearch(@geo_key,
                             frommember: "San Francisco",
                             byradius: 100,
                             unit: "km",
                             count: 2,
                             any: true)

    # With ANY, results may not be sorted by distance
    assert_operator result.length, :<=, 2
  end

  # GEOSEARCHSTORE with fromlonlat and bybox
  def test_geosearchstore_from_coordinates_by_box
    redis.geoadd(@geo_key,
                 -122.4194, 37.7749, "San Francisco",
                 -122.2711, 37.8044, "Oakland",
                 -118.2437, 34.0522, "Los Angeles")

    result = redis.geosearchstore("geo:nearby", @geo_key,
                                  fromlonlat: [-122.4, 37.8],
                                  bybox: [100, 100],
                                  unit: "km",
                                  sort: :asc)

    assert_operator result, :>=, 2
    redis.del("geo:nearby")
  end
end
