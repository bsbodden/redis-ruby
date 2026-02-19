#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/redis_ruby"

# Connect to Redis
redis = RedisRuby.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379"))

puts "=" * 80
puts "Redis Geo - Idiomatic Ruby API Examples"
puts "=" * 80

# ============================================================
# Example 1: Store Locator
# ============================================================

puts "\nExample 1: Store Locator"
puts "-" * 80

stores = redis.geo(:stores, :sf)

# Add store locations
stores.add(
  downtown: [-122.4194, 37.7749],
  mission: [-122.4194, 37.7599],
  sunset: [-122.4942, 37.7599],
  richmond: [-122.4786, 37.7799],
  marina: [-122.4376, 37.8049]
)

puts "Total stores: #{stores.count}"

# Find stores within 5km of user location
user_lon = -122.42
user_lat = 37.78
puts "\nFinding stores within 5km of user location (#{user_lon}, #{user_lat}):"

nearby_stores = stores.radius(user_lon, user_lat, 5, unit: :km,
                                                     withcoord: true, withdist: true, sort: :asc)

nearby_stores.each do |store_data|
  name = store_data[0]
  distance = store_data[1]
  coords = store_data[2]
  puts "  - #{name}: #{distance}km away at [#{coords[0].to_f.round(4)}, #{coords[1].to_f.round(4)}]"
end

# ============================================================
# Example 2: Delivery Zones
# ============================================================

puts "\nExample 2: Delivery Zones"
puts "-" * 80

restaurants = redis.geo(:restaurants, :sf)

# Add restaurant locations
restaurants.add(
  pizza_palace: [-122.4194, 37.7749],
  burger_barn: [-122.4094, 37.7849],
  taco_town: [-122.4294, 37.7649],
  sushi_spot: [-122.4394, 37.7549]
)

puts "Total restaurants: #{restaurants.count}"

# Check if address is within delivery range
delivery_address = [-122.415, 37.780]
puts "\nChecking delivery to address: [#{delivery_address[0]}, #{delivery_address[1]}]"

# Find all restaurants that deliver within 2 miles
available = restaurants.radius(delivery_address[0], delivery_address[1], 2, unit: :mi,
                                                                            withdist: true, sort: :asc)

puts "\nRestaurants that deliver to your area:"
available.each do |restaurant_data|
  name = restaurant_data[0]
  distance = restaurant_data[1]
  puts "  - #{name}: #{distance} miles away"
end

# ============================================================
# Example 3: Distance Calculations
# ============================================================

puts "\nExample 3: Distance Calculations"
puts "-" * 80

cities = redis.geo(:cities, :usa)

# Add major cities
cities.add(
  sf: [-122.4194, 37.7749],
  la: [-118.2437, 34.0522],
  chicago: [-87.6298, 41.8781],
  nyc: [-74.0060, 40.7128]
)

puts "Calculating distances between cities:"

# Calculate distances in different units
sf_to_la_km = cities.distance(:sf, :la, unit: :km)
sf_to_la_mi = cities.distance(:sf, :la, unit: :mi)
puts "  San Francisco to Los Angeles: #{sf_to_la_km.round(2)}km (#{sf_to_la_mi.round(2)} miles)"

sf_to_nyc_km = cities.distance(:sf, :nyc, unit: :km)
sf_to_nyc_mi = cities.distance(:sf, :nyc, unit: :mi)
puts "  San Francisco to New York: #{sf_to_nyc_km.round(2)}km (#{sf_to_nyc_mi.round(2)} miles)"

chicago_to_nyc_km = cities.distance(:chicago, :nyc, unit: :km)
puts "  Chicago to New York: #{chicago_to_nyc_km.round(2)}km"

# ============================================================
# Example 4: Proximity Matching (Ride Sharing)
# ============================================================

puts "\nExample 4: Proximity Matching (Ride Sharing)"
puts "-" * 80

drivers = redis.geo(:drivers, :active)

# Track driver locations (updated in real-time)
drivers.add(
  driver_alpha: [-122.4194, 37.7749],
  driver_beta: [-122.4094, 37.7849],
  driver_gamma: [-122.4294, 37.7649],
  driver_delta: [-122.4394, 37.7549]
)

puts "Active drivers: #{drivers.count}"

# Find nearest driver to pickup location
pickup = [-122.420, 37.780]
puts "\nFinding nearest driver to pickup location: [#{pickup[0]}, #{pickup[1]}]"

nearest = drivers.radius(pickup[0], pickup[1], 5, unit: :km,
                                                  withdist: true, count: 3, sort: :asc)

puts "\nTop 3 nearest drivers:"
nearest.each_with_index do |driver_data, index|
  driver_id = driver_data[0]
  distance = driver_data[1]
  puts "  #{index + 1}. #{driver_id}: #{distance}km away"
end

# ============================================================
# Example 5: Geohash Operations
# ============================================================

puts "\nExample 5: Geohash Operations"
puts "-" * 80

landmarks = redis.geo(:landmarks, :sf)

landmarks.add(
  golden_gate: [-122.4783, 37.8199],
  alcatraz: [-122.4230, 37.8267],
  ferry_building: [-122.3933, 37.7955]
)

puts "Landmarks and their geohashes:"
landmarks.each_member do |landmark|
  geohash = landmarks.hash(landmark)
  position = landmarks.position(landmark)
  puts "  #{landmark}: #{geohash} at [#{position[0].round(4)}, #{position[1].round(4)}]"
end

# ============================================================
# Example 6: Radius Search by Member
# ============================================================

puts "\nExample 6: Radius Search by Member"
puts "-" * 80

attractions = redis.geo(:attractions, :sf)

attractions.add(
  pier_thirtynine: [-122.4098, 37.8087],
  fishermans_wharf: [-122.4177, 37.8080],
  ghirardelli: [-122.4227, 37.8056],
  coit_tower: [-122.4058, 37.8024],
  lombard_street: [-122.4187, 37.8021]
)

puts "Finding attractions within 1km of Pier 39:"

nearby = attractions.radius_by_member(
  :pier_thirtynine, 1, unit: :km, withdist: true, sort: :asc
)

nearby.each do |attraction_data|
  name = attraction_data[0]
  distance = attraction_data[1]
  puts "  - #{name}: #{distance}km away" unless name == "pier_thirtynine"
end

# ============================================================
# Example 7: Real-World Scenario - Coffee Shop Finder
# ============================================================

puts "\nExample 7: Coffee Shop Finder"
puts "-" * 80

coffee_shops = redis.geo(:coffee_shops, :sf)

# Add coffee shop locations
coffee_shops.add(
  blue_bottle: [-122.4194, 37.7749],
  philz: [-122.4094, 37.7849],
  sightglass: [-122.4194, 37.7599],
  ritual: [-122.4242, 37.7599],
  four_barrel: [-122.4242, 37.7649]
)

puts "Total coffee shops: #{coffee_shops.count}"

# User is at work, wants coffee within walking distance (500m)
work_location = [-122.42, 37.77]
puts "\nFinding coffee shops within 500m of work:"

nearby_coffee = coffee_shops.radius(work_location[0], work_location[1], 500, unit: :m,
                                                                             withdist: true, sort: :asc)

if nearby_coffee.any?
  puts "\nCoffee shops within walking distance:"
  nearby_coffee.each do |shop_data|
    name = shop_data[0]
    distance = shop_data[1]
    puts "  - #{name}: #{distance.to_i}m away"
  end
else
  puts "No coffee shops within walking distance :("
end

# ============================================================
# Example 8: Chaining and Conversion
# ============================================================

puts "\nExample 8: Chaining and Conversion"
puts "-" * 80

parks = redis.geo(:parks, :sf)

# Chain operations
parks.add(golden_gate_park: [-122.4862, 37.7694])
  .add(dolores_park: [-122.4276, 37.7596])
  .add(alamo_square: [-122.4345, 37.7766])
  .expire(3600) # Cache for 1 hour

puts "Parks added with 1 hour expiration"
puts "TTL: #{parks.ttl} seconds"

# Convert to array
puts "\nAll parks (as array):"
parks.to_a.each do |park|
  puts "  - #{park}"
end

# Convert to hash
puts "\nAll parks (as hash with coordinates):"
parks.to_h.each do |park, coords|
  puts "  - #{park}: [#{coords[0].to_f.round(4)}, #{coords[1].to_f.round(4)}]"
end

# Check membership
puts "\nIs Golden Gate Park in the list? #{parks.member?(:golden_gate_park)}"
puts "Is Central Park in the list? #{parks.member?(:central_park)}"

# ============================================================
# Cleanup
# ============================================================

puts "\n#{"=" * 80}"
puts "Cleaning up..."

# Clean up all test keys
redis.del("stores:sf")
redis.del("restaurants:sf")
redis.del("cities:usa")
redis.del("drivers:active")
redis.del("landmarks:sf")
redis.del("attractions:sf")
redis.del("coffee_shops:sf")
redis.del("parks:sf")

puts "Done!"
puts "=" * 80

redis.close
