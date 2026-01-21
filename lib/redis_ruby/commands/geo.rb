# frozen_string_literal: true

module RedisRuby
  module Commands
    # Geospatial commands for location-based data
    #
    # Redis Geo commands store geographic coordinates and perform
    # radius queries, distance calculations, and geohash operations.
    #
    # @example Basic usage
    #   redis.geoadd("locations", -122.4194, 37.7749, "San Francisco")
    #   redis.geoadd("locations", -118.2437, 34.0522, "Los Angeles")
    #   redis.geodist("locations", "San Francisco", "Los Angeles", "km")
    #   # => "559.1185"
    #
    # @see https://redis.io/commands/?group=geo
    module Geo
      # Add geospatial items (longitude, latitude, name) to a sorted set
      #
      # @param key [String] Key name
      # @param longitude [Float] Longitude of the location
      # @param latitude [Float] Latitude of the location
      # @param member [String] Member name
      # @param args [Array] Additional longitude, latitude, member triplets
      # @param nx [Boolean] Only add new elements (don't update existing)
      # @param xx [Boolean] Only update existing elements (don't add new)
      # @param ch [Boolean] Return number of changed elements (added + updated)
      # @return [Integer] Number of elements added
      #
      # @example Add single location
      #   redis.geoadd("cities", -122.4194, 37.7749, "San Francisco")
      #
      # @example Add multiple locations
      #   redis.geoadd("cities",
      #     -122.4194, 37.7749, "San Francisco",
      #     -118.2437, 34.0522, "Los Angeles"
      #   )
      def geoadd(key, longitude, latitude, member, *args, nx: false, xx: false, ch: false)
        cmd = ["GEOADD", key]
        cmd << "NX" if nx
        cmd << "XX" if xx
        cmd << "CH" if ch
        cmd << longitude << latitude << member
        cmd.concat(args)
        call(*cmd)
      end

      # Get the position (longitude, latitude) of members
      #
      # @param key [String] Key name
      # @param members [Array<String>] Member names
      # @return [Array<Array<Float>, nil>] Array of [longitude, latitude] pairs or nil
      #
      # @example
      #   redis.geopos("cities", "San Francisco", "Los Angeles")
      #   # => [[-122.4194, 37.7749], [-118.2437, 34.0522]]
      def geopos(key, *members)
        result = call("GEOPOS", key, *members)
        result.map do |pos|
          pos.nil? ? nil : [pos[0].to_f, pos[1].to_f]
        end
      end

      # Calculate distance between two members
      #
      # @param key [String] Key name
      # @param member1 [String] First member
      # @param member2 [String] Second member
      # @param unit [String] Unit: m (meters), km, mi (miles), ft (feet)
      # @return [String, nil] Distance as string or nil if member doesn't exist
      #
      # @example
      #   redis.geodist("cities", "San Francisco", "Los Angeles", "km")
      #   # => "559.1185"
      def geodist(key, member1, member2, unit = "m")
        call("GEODIST", key, member1, member2, unit.to_s.upcase)
      end

      # Get geohash strings for members
      #
      # @param key [String] Key name
      # @param members [Array<String>] Member names
      # @return [Array<String, nil>] Geohash strings or nil for missing members
      #
      # @example
      #   redis.geohash("cities", "San Francisco")
      #   # => ["9q8yyk8yutp"]
      def geohash(key, *members)
        call("GEOHASH", key, *members)
      end

      # Search for members within a radius or box
      #
      # @param key [String] Key name
      # @param frommember [String] Search from this member's position
      # @param fromlonlat [Array<Float>] Search from [longitude, latitude]
      # @param byradius [Float] Search by radius
      # @param bybox [Array<Float>] Search by box [width, height]
      # @param unit [String] Unit: m, km, mi, ft
      # @param count [Integer] Limit results
      # @param any [Boolean] Return any N results (not necessarily closest)
      # @param sort [Symbol] :asc or :desc
      # @param withcoord [Boolean] Include coordinates
      # @param withdist [Boolean] Include distance
      # @param withhash [Boolean] Include geohash
      # @return [Array] Matching members
      #
      # @example Search by radius from member
      #   redis.geosearch("cities", frommember: "San Francisco", byradius: 100, unit: "km")
      #
      # @example Search by box from coordinates
      #   redis.geosearch("cities", fromlonlat: [-122.4, 37.8], bybox: [200, 200], unit: "km")
      def geosearch(key, frommember: nil, fromlonlat: nil, byradius: nil, bybox: nil,
                    unit: "m", count: nil, any: false, sort: nil,
                    withcoord: false, withdist: false, withhash: false)
        cmd = ["GEOSEARCH", key]

        # From position
        if frommember
          cmd << "FROMMEMBER" << frommember
        elsif fromlonlat
          cmd << "FROMLONLAT" << fromlonlat[0] << fromlonlat[1]
        else
          raise ArgumentError, "Must specify frommember or fromlonlat"
        end

        # Search shape
        if byradius
          cmd << "BYRADIUS" << byradius << unit.to_s.upcase
        elsif bybox
          cmd << "BYBOX" << bybox[0] << bybox[1] << unit.to_s.upcase
        else
          raise ArgumentError, "Must specify byradius or bybox"
        end

        # Options
        cmd << "COUNT" << count << ("ANY" if any) if count
        cmd.compact!

        case sort
        when :asc, "ASC", "asc"
          cmd << "ASC"
        when :desc, "DESC", "desc"
          cmd << "DESC"
        end

        cmd << "WITHCOORD" if withcoord
        cmd << "WITHDIST" if withdist
        cmd << "WITHHASH" if withhash

        call(*cmd)
      end

      # Search and store results in a destination key
      #
      # @param destination [String] Destination key
      # @param source [String] Source key
      # @param storedist [Boolean] Store distances instead of geohashes
      # @param (see #geosearch)
      # @return [Integer] Number of elements stored
      #
      # @example
      #   redis.geosearchstore("nearby", "cities",
      #     frommember: "San Francisco", byradius: 50, unit: "km")
      def geosearchstore(destination, source, frommember: nil, fromlonlat: nil,
                         byradius: nil, bybox: nil, unit: "m", count: nil, any: false,
                         sort: nil, storedist: false)
        cmd = ["GEOSEARCHSTORE", destination, source]

        # From position
        if frommember
          cmd << "FROMMEMBER" << frommember
        elsif fromlonlat
          cmd << "FROMLONLAT" << fromlonlat[0] << fromlonlat[1]
        else
          raise ArgumentError, "Must specify frommember or fromlonlat"
        end

        # Search shape
        if byradius
          cmd << "BYRADIUS" << byradius << unit.to_s.upcase
        elsif bybox
          cmd << "BYBOX" << bybox[0] << bybox[1] << unit.to_s.upcase
        else
          raise ArgumentError, "Must specify byradius or bybox"
        end

        # Options
        cmd << "COUNT" << count << ("ANY" if any) if count
        cmd.compact!

        case sort
        when :asc, "ASC", "asc"
          cmd << "ASC"
        when :desc, "DESC", "desc"
          cmd << "DESC"
        end

        cmd << "STOREDIST" if storedist

        call(*cmd)
      end

      # Legacy command: Search by radius from member (deprecated, use geosearch)
      #
      # @param key [String] Key name
      # @param member [String] Center member
      # @param radius [Float] Radius
      # @param unit [String] Unit: m, km, mi, ft
      # @return [Array] Matching members
      def georadiusbymember(key, member, radius, unit = "m", **options)
        cmd = ["GEORADIUSBYMEMBER", key, member, radius, unit.to_s.upcase]
        add_geo_options(cmd, options)
        call(*cmd)
      end

      # Legacy command: Search by radius from coordinates (deprecated, use geosearch)
      #
      # @param key [String] Key name
      # @param longitude [Float] Center longitude
      # @param latitude [Float] Center latitude
      # @param radius [Float] Radius
      # @param unit [String] Unit: m, km, mi, ft
      # @return [Array] Matching members
      def georadius(key, longitude, latitude, radius, unit = "m", **options)
        cmd = ["GEORADIUS", key, longitude, latitude, radius, unit.to_s.upcase]
        add_geo_options(cmd, options)
        call(*cmd)
      end

      private

      def add_geo_options(cmd, options)
        cmd << "COUNT" << options[:count] if options[:count]
        cmd << "ASC" if options[:sort] == :asc
        cmd << "DESC" if options[:sort] == :desc
        cmd << "WITHCOORD" if options[:withcoord]
        cmd << "WITHDIST" if options[:withdist]
        cmd << "WITHHASH" if options[:withhash]
      end
    end
  end
end
