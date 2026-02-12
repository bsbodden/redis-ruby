# frozen_string_literal: true

module RedisRuby
  module DSL
    # Chainable proxy for Redis Geo operations
    #
    # Provides a fluent, idiomatic Ruby API for working with Redis geospatial data,
    # optimized for location-based services, store locators, and proximity searches.
    #
    # @example Store locator
    #   stores = redis.geo(:stores, :sf)
    #   stores.add(downtown: [-122.4194, 37.7749], mission: [-122.4194, 37.7599])
    #   nearby = stores.radius(-122.42, 37.78, 5, unit: :km)
    #
    # @example Delivery zones
    #   restaurants = redis.geo(:restaurants)
    #   restaurants.add(:pizza_palace, -122.4194, 37.7749)
    #   in_range = restaurants.radius_by_member(:pizza_palace, 2, unit: :mi)
    #
    # @example Distance calculation
    #   locations = redis.geo(:cities)
    #   locations.add(sf: [-122.4194, 37.7749], la: [-118.2437, 34.0522])
    #   distance = locations.distance(:sf, :la, unit: :km)  # => 559.12
    #
    class GeoProxy
      attr_reader :key

      # @private
      def initialize(redis, *key_parts)
        @redis = redis
        @key = key_parts.map(&:to_s).join(":")
      end

      # Add one or more geospatial items
      #
      # @overload add(member, longitude, latitude)
      #   Add a single location
      #   @param member [String, Symbol] Member name
      #   @param longitude [Float] Longitude coordinate
      #   @param latitude [Float] Latitude coordinate
      #
      # @overload add(**members_coords)
      #   Add multiple locations
      #   @param members_coords [Hash] Member => [longitude, latitude] pairs
      #
      # @return [self] For method chaining
      #
      # @example Single location
      #   geo.add(:store1, -122.4194, 37.7749)
      #
      # @example Multiple locations
      #   geo.add(store1: [-122.4194, 37.7749], store2: [-118.2437, 34.0522])
      def add(*args, **kwargs)
        if args.empty? && !kwargs.empty?
          # add(store1: [-122.4194, 37.7749], store2: [-118.2437, 34.0522])
          flat_args = kwargs.flat_map { |member, coords| [coords[0], coords[1], member.to_s] }
          @redis.geoadd(@key, *flat_args)
        elsif args.size == 3 && kwargs.empty?
          # add(:store1, -122.4194, 37.7749)
          @redis.geoadd(@key, args[1], args[2], args[0].to_s)
        else
          raise ArgumentError, "Invalid arguments. Use add(member, lon, lat) or add(member1: [lon, lat], ...)"
        end
        self
      end

      # Get position (longitude, latitude) of a member
      #
      # @param member [String, Symbol] Member name
      # @return [Array<Float>, nil] [longitude, latitude] or nil if member doesn't exist
      #
      # @example
      #   geo.position(:store1)  # => [-122.4194, 37.7749]
      def position(member)
        result = @redis.geopos(@key, member.to_s)
        result.first
      end

      # Calculate distance between two members
      #
      # @param member1 [String, Symbol] First member
      # @param member2 [String, Symbol] Second member
      # @param unit [Symbol] Unit: :m (meters), :km, :mi (miles), :ft (feet)
      # @return [Float, nil] Distance or nil if member doesn't exist
      #
      # @example
      #   geo.distance(:store1, :store2, unit: :km)  # => 559.12
      def distance(member1, member2, unit: :m)
        result = @redis.geodist(@key, member1.to_s, member2.to_s, unit.to_s)
        result&.to_f
      end

      # Search for members within a radius from coordinates
      #
      # @param longitude [Float] Center longitude
      # @param latitude [Float] Center latitude
      # @param radius [Float] Radius value
      # @param unit [Symbol] Unit: :m, :km, :mi, :ft
      # @param withcoord [Boolean] Include coordinates in result
      # @param withdist [Boolean] Include distance in result
      # @param withhash [Boolean] Include geohash in result
      # @param count [Integer] Limit number of results
      # @param sort [Symbol] Sort order: :asc or :desc
      # @return [Array] Matching members
      #
      # @example
      #   geo.radius(-122.4, 37.8, 10, unit: :km)
      #   geo.radius(-122.4, 37.8, 10, unit: :km, withcoord: true, withdist: true, count: 5, sort: :asc)
      def radius(longitude, latitude, radius, unit: :m, withcoord: false, withdist: false, withhash: false, count: nil, sort: nil)
        options = {}
        options[:withcoord] = true if withcoord
        options[:withdist] = true if withdist
        options[:withhash] = true if withhash
        options[:count] = count if count
        options[:sort] = sort if sort
        
        @redis.georadius(@key, longitude, latitude, radius, unit.to_s, **options)
      end

      # Search for members within a radius from a member
      #
      # @param member [String, Symbol] Center member
      # @param radius [Float] Radius value
      # @param unit [Symbol] Unit: :m, :km, :mi, :ft
      # @param withcoord [Boolean] Include coordinates in result
      # @param withdist [Boolean] Include distance in result
      # @param withhash [Boolean] Include geohash in result
      # @param count [Integer] Limit number of results
      # @param sort [Symbol] Sort order: :asc or :desc
      # @return [Array] Matching members
      #
      # @example
      #   geo.radius_by_member(:store1, 50, unit: :mi)
      #   geo.radius_by_member(:store1, 50, unit: :mi, withdist: true, count: 10, sort: :asc)
      def radius_by_member(member, radius, unit: :m, withcoord: false, withdist: false, withhash: false, count: nil, sort: nil)
        options = {}
        options[:withcoord] = true if withcoord
        options[:withdist] = true if withdist
        options[:withhash] = true if withhash
        options[:count] = count if count
        options[:sort] = sort if sort

        @redis.georadiusbymember(@key, member.to_s, radius, unit.to_s, **options)
      end

      # Search for members within a radius from coordinates (Redis 6.2+)
      #
      # @param longitude [Float] Center longitude
      # @param latitude [Float] Center latitude
      # @param radius [Float] Radius value
      # @param unit [Symbol] Unit: :m, :km, :mi, :ft
      # @param withcoord [Boolean] Include coordinates in result
      # @param withdist [Boolean] Include distance in result
      # @param withhash [Boolean] Include geohash in result
      # @param count [Integer] Limit number of results
      # @param sort [Symbol] Sort order: :asc or :desc
      # @param any [Boolean] Return any N results (not necessarily closest)
      # @return [Array] Matching members
      #
      # @example
      #   geo.search(-122.4, 37.8, 10, unit: :km)
      #   geo.search(-122.4, 37.8, 10, unit: :km, withcoord: true, withdist: true, count: 10, sort: :asc)
      def search(longitude, latitude, radius, unit: :m, withcoord: false, withdist: false, withhash: false, count: nil, sort: nil, any: false)
        @redis.geosearch(@key,
          fromlonlat: [longitude, latitude],
          byradius: radius,
          unit: unit.to_s,
          withcoord: withcoord,
          withdist: withdist,
          withhash: withhash,
          count: count,
          sort: sort,
          any: any)
      rescue Redis::CommandError => e
        # Fall back to georadius for older Redis versions
        if e.message.include?("unknown command") || e.message.include?("GEOSEARCH")
          radius(longitude, latitude, radius, unit: unit, withcoord: withcoord, withdist: withdist, withhash: withhash, count: count, sort: sort)
        else
          raise
        end
      end

      # Search for members within a radius from a member (Redis 6.2+)
      #
      # @param member [String, Symbol] Center member
      # @param radius [Float] Radius value
      # @param unit [Symbol] Unit: :m, :km, :mi, :ft
      # @param withcoord [Boolean] Include coordinates in result
      # @param withdist [Boolean] Include distance in result
      # @param withhash [Boolean] Include geohash in result
      # @param count [Integer] Limit number of results
      # @param sort [Symbol] Sort order: :asc or :desc
      # @param any [Boolean] Return any N results (not necessarily closest)
      # @return [Array] Matching members
      #
      # @example
      #   geo.search_by_member(:store1, 50, unit: :mi)
      #   geo.search_by_member(:store1, 50, unit: :mi, withdist: true, count: 10, sort: :asc)
      def search_by_member(member, radius, unit: :m, withcoord: false, withdist: false, withhash: false, count: nil, sort: nil, any: false)
        @redis.geosearch(@key,
          frommember: member.to_s,
          byradius: radius,
          unit: unit.to_s,
          withcoord: withcoord,
          withdist: withdist,
          withhash: withhash,
          count: count,
          sort: sort,
          any: any)
      rescue Redis::CommandError => e
        # Fall back to georadiusbymember for older Redis versions
        if e.message.include?("unknown command") || e.message.include?("GEOSEARCH")
          radius_by_member(member, radius, unit: unit, withcoord: withcoord, withdist: withdist, withhash: withhash, count: count, sort: sort)
        else
          raise
        end
      end

      # Get geohash string(s) for member(s)
      #
      # @param members [Array<String, Symbol>] Member names
      # @return [String, Array<String>] Geohash string(s) or nil for missing members
      #
      # @example
      #   geo.hash(:store1)  # => "9q8yyk8yutp"
      #   geo.hash(:store1, :store2)  # => ["9q8yyk8yutp", "9q5ctr8xvnp"]
      def hash(*members)
        return nil if members.empty?

        result = @redis.geohash(@key, *members.map(&:to_s))
        members.size == 1 ? result.first : result
      end

      # Remove one or more members
      #
      # @param members [Array<String, Symbol>] Members to remove
      # @return [self] For method chaining
      #
      # @example
      #   geo.remove(:store1)
      #   geo.remove(:store1, :store2, :store3)
      def remove(*members)
        return self if members.empty?
        @redis.zrem(@key, *members.map(&:to_s))
        self
      end

      # Check if a member exists
      #
      # @param member [String, Symbol] Member name
      # @return [Boolean] true if member exists
      #
      # @example
      #   geo.member?(:store1)  # => true
      def member?(member)
        !@redis.geopos(@key, member.to_s).first.nil?
      end
      alias include? member?

      # Check if the geo key exists
      #
      # @return [Boolean] true if key exists
      #
      # @example
      #   geo.exists?  # => true
      def exists?
        @redis.exists(@key) == 1
      end

      # Check if the geo set is empty
      #
      # @return [Boolean] true if no members
      #
      # @example
      #   geo.empty?  # => false
      def empty?
        count == 0
      end

      # Get total number of members
      #
      # @return [Integer] Number of members
      #
      # @example
      #   geo.count  # => 10
      def count
        @redis.zcard(@key)
      end
      alias size count
      alias length count

      # Iterate over all members with coordinates
      #
      # @yield [member, longitude, latitude] Yields each member and coordinates
      # @return [self, Enumerator] self if block given, Enumerator otherwise
      #
      # @example
      #   geo.each { |member, lon, lat| puts "#{member}: #{lon}, #{lat}" }
      def each(&block)
        return enum_for(:each) unless block_given?

        cursor = 0
        loop do
          cursor, results = @redis.zscan(@key, cursor)
          # zscan returns [[member, score], ...] pairs
          # For each member, get its position
          results.each do |member, _score|
            pos = @redis.geopos(@key, member).first
            if pos
              yield member.to_sym, pos[0], pos[1]
            end
          end
          break if cursor == "0"
        end
        self
      end

      # Iterate over all members
      #
      # @yield [member] Yields each member
      # @return [self, Enumerator] self if block given, Enumerator otherwise
      #
      # @example
      #   geo.each_member { |member| puts member }
      def each_member(&block)
        return enum_for(:each_member) unless block_given?

        each { |member, _lon, _lat| yield member }
      end

      # Get all members as an array
      #
      # @return [Array<String>] Array of members
      #
      # @example
      #   geo.to_a  # => ["store1", "store2", "store3"]
      def to_a
        @redis.zrange(@key, 0, -1)
      end

      # Get all members as a hash (member => [longitude, latitude])
      #
      # @return [Hash] Hash of member => [lon, lat] pairs
      #
      # @example
      #   geo.to_h  # => {store1: [-122.4194, 37.7749], store2: [-118.2437, 34.0522]}
      def to_h
        members = @redis.zrange(@key, 0, -1)
        return {} if members.nil? || members.empty?

        positions = @redis.geopos(@key, *members)
        Hash[members.map.with_index { |member, i| [member.to_sym, positions[i]] }]
      end

      # Remove all members
      #
      # @return [Integer] Number of members removed
      #
      # @example
      #   geo.clear
      def clear
        @redis.del(@key)
      end
      alias delete clear

      # Set expiration time in seconds
      #
      # @param seconds [Integer] Seconds until expiration
      # @return [self] For method chaining
      #
      # @example
      #   geo.expire(3600)  # Expire in 1 hour
      def expire(seconds)
        @redis.expire(@key, seconds)
        self
      end

      # Set expiration time at a specific timestamp
      #
      # @param timestamp [Integer, Time] Unix timestamp or Time object
      # @return [self] For method chaining
      #
      # @example
      #   geo.expire_at(Time.now + 3600)
      def expire_at(timestamp)
        timestamp = timestamp.to_i if timestamp.is_a?(Time)
        @redis.expireat(@key, timestamp)
        self
      end

      # Get time-to-live in seconds
      #
      # @return [Integer] Seconds until expiration (-1 if no expiration, -2 if key doesn't exist)
      #
      # @example
      #   geo.ttl  # => 3600
      def ttl
        @redis.ttl(@key)
      end

      # Remove expiration
      #
      # @return [self] For method chaining
      #
      # @example
      #   geo.persist
      def persist
        @redis.persist(@key)
        self
      end
    end
  end
end

