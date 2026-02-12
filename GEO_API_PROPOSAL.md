# Geo Idiomatic API Proposal

## Overview

Create an idiomatic Ruby API for Redis Geospatial commands that makes working with location-based data feel natural and Ruby-esque. Perfect for store locators, delivery zones, proximity searches, and location-based services.

## Design Goals

1. **Location-Focused** - Optimized for common geospatial use cases
2. **Intuitive Coordinates** - Natural handling of longitude/latitude pairs
3. **Flexible Search** - Radius and box searches with rich options
4. **Distance Calculations** - Easy distance queries with multiple units
5. **Composite Keys** - Automatic `:` joining for multi-part keys
6. **Symbol/String Flexibility** - Accept both for member names

## API Design

### Entry Point

```ruby
# In lib/redis_ruby/commands/geo.rb
module RedisRuby
  module Commands
    module Geo
      # Create a geo proxy for idiomatic operations
      #
      # @param key_parts [Array<String, Symbol, Integer>] Key components
      # @return [RedisRuby::DSL::GeoProxy]
      def geo(*key_parts)
        DSL::GeoProxy.new(self, *key_parts)
      end
    end
  end
end
```

### Core API

```ruby
# Basic operations
locations = redis.geo(:stores, :sf)

# Add locations with coordinates
locations.add(:store1, -122.4194, 37.7749)
locations.add(
  store2: [-118.2437, 34.0522],
  store3: [-87.6298, 41.8781]
)

# Get position
pos = locations.position(:store1)  # => [-122.4194, 37.7749]

# Calculate distance
dist = locations.distance(:store1, :store2, unit: :km)  # => 559.12

# Radius search from coordinates
nearby = locations.radius(-122.4, 37.8, 10, unit: :km)
nearby = locations.radius(-122.4, 37.8, 10, unit: :km,
  withcoord: true, withdist: true, count: 5, sort: :asc)

# Radius search from member
nearby = locations.radius_by_member(:store1, 50, unit: :mi)

# Search (Redis 6.2+)
results = locations.search(-122.4, 37.8, 10, unit: :km,
  withcoord: true, withdist: true, count: 10, sort: :asc)
results = locations.search_by_member(:store1, 50, unit: :mi)

# Get geohash
hash = locations.hash(:store1)  # => "9q8yyk8yutp"
hashes = locations.hash(:store1, :store2)  # => ["9q8yyk8yutp", ...]

# Remove locations
locations.remove(:store1)
locations.remove(:store1, :store2, :store3)

# Existence checks
locations.exists?              # Key exists
locations.member?(:store1)     # Member exists
locations.empty?               # No members

# Count operations
locations.count                # Total members
locations.size                 # Alias for count
locations.length               # Alias for count

# Iteration
locations.each { |member, lon, lat| puts "#{member}: #{lon}, #{lat}" }
locations.each_member { |member| puts member }

# Conversion
locations.to_a                 # => ["store1", "store2", "store3"]
locations.to_h                 # => {store1: [-122.4194, 37.7749], ...}

# Clear
locations.clear                # Remove all members
locations.delete               # Alias for clear
```

## Use Cases

### Use Case 1: Store Locator

```ruby
stores = redis.geo(:stores, :locations)

# Add store locations
stores.add(
  downtown: [-122.4194, 37.7749],
  mission: [-122.4194, 37.7599],
  sunset: [-122.4942, 37.7599]
)

# Find stores within 5km of user location
user_lon, user_lat = -122.42, 37.78
nearby_stores = stores.radius(user_lon, user_lat, 5, unit: :km,
  withcoord: true, withdist: true, sort: :asc)

nearby_stores.each do |store_data|
  name = store_data[0]
  distance = store_data[1]
  coords = store_data[2]
  puts "#{name}: #{distance}km away at #{coords}"
end
```

### Use Case 2: Delivery Zones

```ruby
restaurants = redis.geo(:restaurants, :sf)

# Add restaurant locations
restaurants.add(
  pizza_palace: [-122.4194, 37.7749],
  burger_barn: [-122.4094, 37.7849],
  taco_town: [-122.4294, 37.7649]
)

# Check if address is within delivery range
delivery_address = [-122.415, 37.780]
in_range = restaurants.radius(delivery_address[0], delivery_address[1], 2, unit: :mi)

if in_range.include?("pizza_palace")
  puts "Pizza Palace delivers to your area!"
end

# Find all restaurants that deliver to this address
available = restaurants.radius(delivery_address[0], delivery_address[1], 3, unit: :mi,
  withdist: true, sort: :asc)
```

### Use Case 3: Proximity Matching

```ruby
drivers = redis.geo(:drivers, :active)

# Track driver locations (updated in real-time)
drivers.add(driver_123: [-122.4194, 37.7749])
drivers.add(driver_456: [-122.4094, 37.7849])

# Find nearest driver to pickup location
pickup = [-122.420, 37.780]
nearest = drivers.radius(pickup[0], pickup[1], 5, unit: :km,
  withdist: true, count: 1, sort: :asc)

if nearest.any?
  driver_id = nearest[0][0]
  distance = nearest[0][1]
  puts "Nearest driver: #{driver_id} (#{distance}km away)"
end
```

