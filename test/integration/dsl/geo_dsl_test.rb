# frozen_string_literal: true

require "test_helper"

class GeoDSLTest < Minitest::Test
  def setup
    @redis = RR.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379"))
    @key = "test:geo:#{SecureRandom.hex(8)}"
  end

  def teardown
    @redis&.del(@key)
    @redis&.close
  end

  attr_reader :redis

  # ============================================================
  # Entry Point Tests
  # ============================================================

  def test_geo_creates_proxy
    geo = redis.geo(@key)

    assert_instance_of RR::DSL::GeoProxy, geo
    assert_equal @key, geo.key
  end

  def test_geo_with_composite_key
    geo = redis.geo(:stores, :sf, :locations)

    assert_equal "stores:sf:locations", geo.key
  end
  # ============================================================
  # Add Operations Tests
  # ============================================================

  def test_add_single_location
    geo = redis.geo(@key)

    result = geo.add(:store1, -122.4194, 37.7749)

    assert_same geo, result
    pos = geo.position(:store1)

    assert_in_delta(-122.4194, pos[0], 0.001)
    assert_in_delta(37.7749, pos[1], 0.001)
  end

  def test_add_multiple_locations_with_hash
    geo = redis.geo(@key)

    geo.add(
      store1: [-122.4194, 37.7749],
      store2: [-118.2437, 34.0522],
      store3: [-87.6298, 41.8781]
    )

    assert_equal 3, geo.count
    pos1 = geo.position(:store1)

    assert_in_delta(-122.4194, pos1[0], 0.001)
    pos2 = geo.position(:store2)

    assert_in_delta(-118.2437, pos2[0], 0.001)
  end

  def test_add_chainable
    geo = redis.geo(@key)

    geo.add(:store1, -122.4194, 37.7749)
      .add(:store2, -118.2437, 34.0522)
      .add(store3: [-87.6298, 41.8781])

    assert_equal 3, geo.count
  end

  def test_add_invalid_arguments
    geo = redis.geo(@key)

    assert_raises(ArgumentError) do
      geo.add(:store1)
    end
  end
  # ============================================================
  # Position Query Tests
  # ============================================================

  def test_position_returns_coordinates
    geo = redis.geo(@key)
    geo.add(:sf, -122.4194, 37.7749)

    pos = geo.position(:sf)

    assert_instance_of Array, pos
    assert_equal 2, pos.size
    assert_in_delta(-122.4194, pos[0], 0.001)
    assert_in_delta(37.7749, pos[1], 0.001)
  end

  def test_position_returns_nil_for_missing_member
    geo = redis.geo(@key)

    pos = geo.position(:nonexistent)

    assert_nil pos
  end
  # ============================================================
  # Distance Tests
  # ============================================================

  def test_distance_in_meters
    geo = redis.geo(@key)
    geo.add(sf: [-122.4194, 37.7749], la: [-118.2437, 34.0522])

    dist = geo.distance(:sf, :la, unit: :m)

    assert_instance_of Float, dist
    assert_in_delta 559_118, dist, 1000 # ~559km in meters
  end

  def test_distance_in_kilometers
    geo = redis.geo(@key)
    geo.add(sf: [-122.4194, 37.7749], la: [-118.2437, 34.0522])

    dist = geo.distance(:sf, :la, unit: :km)

    assert_in_delta 559.1, dist, 1.0
  end

  def test_distance_in_miles
    geo = redis.geo(@key)
    geo.add(sf: [-122.4194, 37.7749], la: [-118.2437, 34.0522])

    dist = geo.distance(:sf, :la, unit: :mi)

    assert_in_delta 347.4, dist, 1.0
  end

  def test_distance_in_feet
    geo = redis.geo(@key)
    geo.add(sf: [-122.4194, 37.7749], la: [-118.2437, 34.0522])

    dist = geo.distance(:sf, :la, unit: :ft)

    assert_in_delta 1_834_652, dist, 5000
  end

  def test_distance_default_unit_meters
    geo = redis.geo(@key)
    geo.add(sf: [-122.4194, 37.7749], la: [-118.2437, 34.0522])

    dist = geo.distance(:sf, :la)

    assert_in_delta 559_118, dist, 1000
  end

  def test_distance_returns_nil_for_missing_member
    geo = redis.geo(@key)
    geo.add(:sf, -122.4194, 37.7749)

    dist = geo.distance(:sf, :nonexistent)

    assert_nil dist
  end
end

class GeoDSLTestPart2 < Minitest::Test
  def setup
    @redis = RR.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379"))
    @key = "test:geo:#{SecureRandom.hex(8)}"
  end

  def teardown
    @redis&.del(@key)
    @redis&.close
  end

  attr_reader :redis

  # ============================================================
  # Entry Point Tests
  # ============================================================

  # ============================================================
  # Radius Search Tests
  # ============================================================

  def test_radius_finds_nearby_locations
    geo = redis.geo(@key)
    geo.add(
      downtown: [-122.4194, 37.7749],
      mission: [-122.4194, 37.7599],
      sunset: [-122.4942, 37.7599]
    )

    # Search from downtown area
    nearby = geo.radius(-122.42, 37.78, 5, unit: :km)

    assert_includes nearby, "downtown"
    assert_includes nearby, "mission"
  end

  def test_radius_with_coordinates
    geo = redis.geo(@key)
    geo.add(store1: [-122.4194, 37.7749], store2: [-122.4094, 37.7849])

    nearby = geo.radius(-122.42, 37.78, 5, unit: :km, withcoord: true)

    assert_instance_of Array, nearby
    assert_predicate nearby.size, :positive?
    # Each result should be [member, [lon, lat]]
    assert_instance_of Array, nearby[0]
    assert_instance_of Array, nearby[0][1]
  end

  def test_radius_with_distance
    geo = redis.geo(@key)
    geo.add(store1: [-122.4194, 37.7749], store2: [-122.4094, 37.7849])

    nearby = geo.radius(-122.42, 37.78, 5, unit: :km, withdist: true)

    assert_instance_of Array, nearby
    assert_predicate nearby.size, :positive?
    # Each result should be [member, distance]
    assert_instance_of Array, nearby[0]
    assert_instance_of String, nearby[0][1]
  end

  def test_radius_with_count_limit
    geo = redis.geo(@key)
    geo.add(
      store1: [-122.4194, 37.7749],
      store2: [-122.4094, 37.7849],
      store3: [-122.4294, 37.7649]
    )

    nearby = geo.radius(-122.42, 37.78, 10, unit: :km, count: 2)

    assert_equal 2, nearby.size
  end

  def test_radius_with_sort_asc
    geo = redis.geo(@key)
    geo.add(
      far: [-122.5, 37.7],
      near: [-122.42, 37.78],
      mid: [-122.45, 37.75]
    )

    nearby = geo.radius(-122.42, 37.78, 50, unit: :km, withdist: true, sort: :asc)

    # First result should be closest
    assert_equal "near", nearby[0][0]
  end

  def test_radius_with_sort_desc
    geo = redis.geo(@key)
    geo.add(
      far: [-122.5, 37.7],
      near: [-122.42, 37.78],
      mid: [-122.45, 37.75]
    )

    nearby = geo.radius(-122.42, 37.78, 50, unit: :km, withdist: true, sort: :desc)

    # First result should be farthest
    assert_equal "far", nearby[0][0]
  end
  # ============================================================
  # Radius by Member Tests
  # ============================================================

  def test_radius_by_member_finds_nearby
    geo = redis.geo(@key)
    geo.add(
      store1: [-122.4194, 37.7749],
      store2: [-122.4094, 37.7849],
      store3: [-87.6298, 41.8781] # Chicago - far away
    )

    nearby = geo.radius_by_member(:store1, 50, unit: :km)

    assert_includes nearby, "store1"
    assert_includes nearby, "store2"
    refute_includes nearby, "store3"
  end

  def test_radius_by_member_with_distance
    geo = redis.geo(@key)
    geo.add(store1: [-122.4194, 37.7749], store2: [-122.4094, 37.7849])

    nearby = geo.radius_by_member(:store1, 50, unit: :km, withdist: true)

    assert_instance_of Array, nearby
    assert_predicate nearby.size, :positive?
    # Each result should be [member, distance]
    assert_instance_of Array, nearby[0]
  end

  def test_radius_by_member_with_count
    geo = redis.geo(@key)
    geo.add(
      store1: [-122.4194, 37.7749],
      store2: [-122.4094, 37.7849],
      store3: [-122.4294, 37.7649]
    )

    nearby = geo.radius_by_member(:store1, 50, unit: :km, count: 2)

    assert_equal 2, nearby.size
  end
  # ============================================================
  # Hash Tests
  # ============================================================

  def test_hash_single_member
    geo = redis.geo(@key)
    geo.add(:sf, -122.4194, 37.7749)

    geohash = geo.hash(:sf)

    assert_instance_of String, geohash
    assert_predicate geohash.length, :positive?
  end

  def test_hash_multiple_members
    geo = redis.geo(@key)
    geo.add(sf: [-122.4194, 37.7749], la: [-118.2437, 34.0522])

    hashes = geo.hash(:sf, :la)

    assert_instance_of Array, hashes
    assert_equal 2, hashes.size
    assert_instance_of String, hashes[0]
    assert_instance_of String, hashes[1]
  end

  def test_hash_returns_nil_for_missing_member
    geo = redis.geo(@key)
    geo.add(:sf, -122.4194, 37.7749)

    hashes = geo.hash(:sf, :nonexistent)

    assert_equal 2, hashes.size
    assert_instance_of String, hashes[0]
    assert_nil hashes[1]
  end

  def test_hash_empty_members
    geo = redis.geo(@key)

    result = geo.hash

    assert_nil result
  end
end

class GeoDSLTestPart3 < Minitest::Test
  def setup
    @redis = RR.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379"))
    @key = "test:geo:#{SecureRandom.hex(8)}"
  end

  def teardown
    @redis&.del(@key)
    @redis&.close
  end

  attr_reader :redis

  # ============================================================
  # Entry Point Tests
  # ============================================================

  # ============================================================
  # Removal Tests
  # ============================================================

  def test_remove_single_member
    geo = redis.geo(@key)
    geo.add(store1: [-122.4194, 37.7749], store2: [-118.2437, 34.0522])

    result = geo.remove(:store1)

    assert_same geo, result
    assert_equal 1, geo.count
    assert_nil geo.position(:store1)
  end

  def test_remove_multiple_members
    geo = redis.geo(@key)
    geo.add(
      store1: [-122.4194, 37.7749],
      store2: [-118.2437, 34.0522],
      store3: [-87.6298, 41.8781]
    )

    geo.remove(:store1, :store2)

    assert_equal 1, geo.count
    assert_nil geo.position(:store1)
    assert_nil geo.position(:store2)
    refute_nil geo.position(:store3)
  end

  def test_remove_chainable
    geo = redis.geo(@key)
    geo.add(store1: [-122.4194, 37.7749], store2: [-118.2437, 34.0522])

    geo.remove(:store1).add(:store3, -87.6298, 41.8781)

    assert_equal 2, geo.count
  end
  # ============================================================
  # Existence Tests
  # ============================================================

  def test_member_predicate
    geo = redis.geo(@key)
    geo.add(:store1, -122.4194, 37.7749)

    assert geo.member?(:store1)
    refute geo.member?(:nonexistent)
  end

  def test_include_alias
    geo = redis.geo(@key)
    geo.add(:store1, -122.4194, 37.7749)

    assert_includes geo, :store1
    refute_includes geo, :nonexistent
  end

  def test_exists_predicate
    geo = redis.geo(@key)

    refute_predicate geo, :exists?

    geo.add(:store1, -122.4194, 37.7749)

    assert_predicate geo, :exists?
  end

  def test_empty_predicate
    geo = redis.geo(@key)

    assert_empty geo

    geo.add(:store1, -122.4194, 37.7749)

    refute_empty geo
  end
  # ============================================================
  # Count Tests
  # ============================================================

  def test_count
    geo = redis.geo(@key)

    assert_equal 0, geo.count

    geo.add(store1: [-122.4194, 37.7749], store2: [-118.2437, 34.0522])

    assert_equal 2, geo.count
  end

  def test_size_alias
    geo = redis.geo(@key)
    geo.add(store1: [-122.4194, 37.7749], store2: [-118.2437, 34.0522])

    assert_equal 2, geo.size
  end

  def test_length_alias
    geo = redis.geo(@key)
    geo.add(store1: [-122.4194, 37.7749], store2: [-118.2437, 34.0522])

    assert_equal 2, geo.length
  end
  # ============================================================
  # Iteration Tests
  # ============================================================

  def test_each_with_block
    geo = redis.geo(@key)
    geo.add(store1: [-122.4194, 37.7749], store2: [-118.2437, 34.0522])

    members = []
    result = geo.each { |member, _lon, _lat| members << member }

    assert_same geo, result
    assert_equal 2, members.size
    assert_includes members, :store1
    assert_includes members, :store2
  end

  def test_each_without_block_returns_enumerator
    geo = redis.geo(@key)
    geo.add(:store1, -122.4194, 37.7749)

    enum = geo.each

    assert_instance_of Enumerator, enum
  end

  def test_each_member_with_block
    geo = redis.geo(@key)
    geo.add(store1: [-122.4194, 37.7749], store2: [-118.2437, 34.0522])

    members = []
    result = geo.each_member { |member| members << member }

    assert_same geo, result
    assert_equal 2, members.size
    assert_includes members, :store1
  end

  def test_each_member_without_block_returns_enumerator
    geo = redis.geo(@key)
    geo.add(:store1, -122.4194, 37.7749)

    enum = geo.each_member

    assert_instance_of Enumerator, enum
  end
end

class GeoDSLTestPart4 < Minitest::Test
  def setup
    @redis = RR.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379"))
    @key = "test:geo:#{SecureRandom.hex(8)}"
  end

  def teardown
    @redis&.del(@key)
    @redis&.close
  end

  attr_reader :redis

  # ============================================================
  # Entry Point Tests
  # ============================================================

  # ============================================================
  # Conversion Tests
  # ============================================================

  def test_to_a
    geo = redis.geo(@key)
    geo.add(store1: [-122.4194, 37.7749], store2: [-118.2437, 34.0522])

    arr = geo.to_a

    assert_instance_of Array, arr
    assert_equal 2, arr.size
    assert_includes arr, "store1"
    assert_includes arr, "store2"
  end

  def test_to_h
    geo = redis.geo(@key)
    geo.add(store1: [-122.4194, 37.7749], store2: [-118.2437, 34.0522])

    hash = geo.to_h

    assert_instance_of Hash, hash
    assert_equal 2, hash.size
    assert hash.key?(:store1)
    assert hash.key?(:store2)
    assert_instance_of Array, hash[:store1]
    assert_equal 2, hash[:store1].size
  end

  def test_to_h_empty
    geo = redis.geo(@key)

    hash = geo.to_h

    assert_empty(hash)
  end
  # ============================================================
  # Clear Tests
  # ============================================================

  def test_clear
    geo = redis.geo(@key)
    geo.add(store1: [-122.4194, 37.7749], store2: [-118.2437, 34.0522])

    result = geo.clear

    assert_equal 1, result
    assert_equal 0, geo.count
  end

  def test_delete_alias
    geo = redis.geo(@key)
    geo.add(:store1, -122.4194, 37.7749)

    result = geo.delete

    assert_equal 1, result
    assert_equal 0, geo.count
  end
  # ============================================================
  # Expiration Tests
  # ============================================================

  def test_expire
    geo = redis.geo(@key)
    geo.add(:store1, -122.4194, 37.7749)

    result = geo.expire(60)

    assert_same geo, result
    assert_predicate geo.ttl, :positive?
  end

  def test_expire_at
    geo = redis.geo(@key)
    geo.add(:store1, -122.4194, 37.7749)

    result = geo.expire_at(Time.now + 60)

    assert_same geo, result
    assert_predicate geo.ttl, :positive?
  end

  def test_ttl
    geo = redis.geo(@key)
    geo.add(:store1, -122.4194, 37.7749)

    assert_equal(-1, geo.ttl)

    geo.expire(60)

    assert_predicate geo.ttl, :positive?
    assert_operator geo.ttl, :<=, 60
  end

  def test_persist
    geo = redis.geo(@key)
    geo.add(:store1, -122.4194, 37.7749)
    geo.expire(60)

    result = geo.persist

    assert_same geo, result
    assert_equal(-1, geo.ttl)
  end
  # ============================================================
  # Integration Tests
  # ============================================================

  def test_store_locator_scenario
    stores = redis.geo(:stores, :sf)

    # Add stores
    stores.add(
      downtown: [-122.4194, 37.7749],
      mission: [-122.4194, 37.7599],
      sunset: [-122.4942, 37.7599]
    )

    # Find nearby stores
    user_location = [-122.42, 37.78]
    nearby = stores.radius(user_location[0], user_location[1], 5, unit: :km, withdist: true, sort: :asc)

    assert_predicate nearby.size, :positive?
    # Closest should be first
    assert_equal "downtown", nearby[0][0]
  end

  def test_delivery_zone_scenario
    restaurants = redis.geo(:restaurants)

    # Add restaurants
    restaurants.add(
      pizza: [-122.4194, 37.7749],
      burger: [-122.4094, 37.7849],
      taco: [-122.4294, 37.7649]
    )

    # Check delivery range
    delivery_addr = [-122.415, 37.780]
    in_range = restaurants.radius(delivery_addr[0], delivery_addr[1], 2, unit: :mi)

    assert_includes in_range, "pizza"
    assert_includes in_range, "burger"
  end

  def test_proximity_matching_scenario
    drivers = redis.geo(:drivers, :active)

    # Add driver locations
    drivers.add(driver123: [-122.4194, 37.7749], driver456: [-122.4094, 37.7849])

    # Find nearest driver
    pickup = [-122.420, 37.780]
    nearest = drivers.radius(pickup[0], pickup[1], 5, unit: :km, withdist: true, count: 1, sort: :asc)

    assert_equal 1, nearest.size
    assert_instance_of Array, nearest[0]
  end

  def test_chaining_operations
    geo = redis.geo(@key)

    geo.add(:store1, -122.4194, 37.7749)
      .add(store2: [-118.2437, 34.0522])
      .remove(:store1)
      .expire(3600)

    assert_equal 1, geo.count
    assert_predicate geo.ttl, :positive?
  end
end
