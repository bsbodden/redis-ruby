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
      # Frozen command constants to avoid string allocations
      CMD_GEOADD = "GEOADD"
      CMD_GEOPOS = "GEOPOS"
      CMD_GEODIST = "GEODIST"
      CMD_GEOHASH = "GEOHASH"
      CMD_GEOSEARCH = "GEOSEARCH"
      CMD_GEOSEARCHSTORE = "GEOSEARCHSTORE"
      CMD_GEORADIUSBYMEMBER = "GEORADIUSBYMEMBER"
      CMD_GEORADIUS = "GEORADIUS"

      # Frozen option strings
      OPT_NX = "NX"
      OPT_XX = "XX"
      OPT_CH = "CH"
      OPT_FROMMEMBER = "FROMMEMBER"
      OPT_FROMLONLAT = "FROMLONLAT"
      OPT_BYRADIUS = "BYRADIUS"
      OPT_BYBOX = "BYBOX"
      OPT_COUNT = "COUNT"
      OPT_ANY = "ANY"
      OPT_ASC = "ASC"
      OPT_DESC = "DESC"
      OPT_WITHCOORD = "WITHCOORD"
      OPT_WITHDIST = "WITHDIST"
      OPT_WITHHASH = "WITHHASH"
      OPT_STOREDIST = "STOREDIST"

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
        cmd = [CMD_GEOADD, key]
        cmd << OPT_NX if nx
        cmd << OPT_XX if xx
        cmd << OPT_CH if ch
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
        # Fast path for single member
        result = if members.size == 1
                   call_2args(CMD_GEOPOS, key, members[0])
                 else
                   call(CMD_GEOPOS, key, *members)
                 end
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
        call(CMD_GEODIST, key, member1, member2, unit.to_s.upcase)
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
        # Fast path for single member
        return call_2args(CMD_GEOHASH, key, members[0]) if members.size == 1

        call(CMD_GEOHASH, key, *members)
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
        cmd = [CMD_GEOSEARCH, key]
        build_geosearch_args(cmd,
                             frommember: frommember, fromlonlat: fromlonlat,
                             byradius: byradius, bybox: bybox, unit: unit,
                             count: count, any: any, sort: sort)
        cmd << OPT_WITHCOORD if withcoord
        cmd << OPT_WITHDIST if withdist
        cmd << OPT_WITHHASH if withhash
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
        cmd = [CMD_GEOSEARCHSTORE, destination, source]
        build_geosearch_args(cmd,
                             frommember: frommember, fromlonlat: fromlonlat,
                             byradius: byradius, bybox: bybox, unit: unit,
                             count: count, any: any, sort: sort)
        cmd << OPT_STOREDIST if storedist
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
        cmd = [CMD_GEORADIUSBYMEMBER, key, member, radius, unit.to_s.upcase]
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
        cmd = [CMD_GEORADIUS, key, longitude, latitude, radius, unit.to_s.upcase]
        add_geo_options(cmd, options)
        call(*cmd)
      end

      private

      def build_geosearch_args(cmd, frommember:, fromlonlat:, byradius:, bybox:, unit:, count:, any:, sort:)
        append_geosearch_origin(cmd, frommember: frommember, fromlonlat: fromlonlat)
        append_geosearch_shape(cmd, byradius: byradius, bybox: bybox, unit: unit)
        append_geosearch_modifiers(cmd, count: count, any: any, sort: sort)
      end

      def append_geosearch_origin(cmd, frommember:, fromlonlat:)
        if frommember
          cmd << OPT_FROMMEMBER << frommember
        elsif fromlonlat
          cmd << OPT_FROMLONLAT << fromlonlat[0] << fromlonlat[1]
        else
          raise ArgumentError, "Must specify frommember or fromlonlat"
        end
      end

      def append_geosearch_shape(cmd, byradius:, bybox:, unit:)
        if byradius
          cmd << OPT_BYRADIUS << byradius << unit.to_s.upcase
        elsif bybox
          cmd << OPT_BYBOX << bybox[0] << bybox[1] << unit.to_s.upcase
        else
          raise ArgumentError, "Must specify byradius or bybox"
        end
      end

      def append_geosearch_modifiers(cmd, count:, any:, sort:)
        if count
          cmd << OPT_COUNT << count
          cmd << OPT_ANY if any
        end

        case sort
        when :asc, "ASC", "asc" then cmd << OPT_ASC
        when :desc, "DESC", "desc" then cmd << OPT_DESC
        end
      end

      def add_geo_options(cmd, options)
        cmd << OPT_COUNT << options[:count] if options[:count]
        cmd << OPT_ASC if options[:sort] == :asc
        cmd << OPT_DESC if options[:sort] == :desc
        cmd << OPT_WITHCOORD if options[:withcoord]
        cmd << OPT_WITHDIST if options[:withdist]
        cmd << OPT_WITHHASH if options[:withhash]
      end
    end
  end
end
