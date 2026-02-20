# frozen_string_literal: true

module RR
  class Cache
    # Registry of which Redis commands can be cached
    #
    # Based on redis-py's DEFAULT_ALLOW_LIST. Only read commands that return
    # deterministic results for a given key state are cacheable.
    #
    # @example Default usage
    #   registry = CommandRegistry.new
    #   registry.cacheable?("GET")    # => true
    #   registry.cacheable?("SET")    # => false
    #
    # @example Custom allow list
    #   registry = CommandRegistry.new(allow_list: %w[GET HGET])
    #   registry.cacheable?("MGET")   # => false
    #
    # @example With deny list
    #   registry = CommandRegistry.new(deny_list: %w[HGETALL])
    #   registry.cacheable?("HGETALL") # => false
    #
    class CommandRegistry
      # Default set of cacheable commands (read-only commands with deterministic results)
      DEFAULT_CACHEABLE = %w[
        GET MGET GETEX GETDEL GETRANGE STRLEN SUBSTR
        HGET HMGET HGETALL HLEN HKEYS HVALS HEXISTS HRANDFIELD HSCAN
        LRANGE LINDEX LLEN LPOS
        SMEMBERS SISMEMBER SCARD SRANDMEMBER SMISMEMBER SSCAN SUNION SINTER SDIFF
        ZRANGE ZREVRANGE ZRANGEBYSCORE ZREVRANGEBYSCORE ZRANGEBYLEX ZREVRANGEBYLEX
        ZSCORE ZMSCORE ZCARD ZCOUNT ZRANK ZREVRANK ZRANDMEMBER ZSCAN ZLEXCOUNT
        EXISTS TYPE TTL PTTL OBJECT DUMP
        PFCOUNT
        XLEN XRANGE XREVRANGE XINFO XPENDING
        BITCOUNT BITPOS GETBIT BITFIELD_RO
        GEORADIUS_RO GEOPOS GEODIST GEOHASH GEOSEARCH GEOMEMBERS
        JSON.GET JSON.MGET JSON.TYPE JSON.STRLEN JSON.ARRLEN JSON.ARRINDEX
        JSON.OBJKEYS JSON.OBJLEN JSON.NUMINCRBY
        FT.SEARCH FT.AGGREGATE FT.INFO FT.TAGVALS
        TS.GET TS.MGET TS.RANGE TS.MRANGE TS.REVRANGE TS.MREVRANGE TS.INFO
        SINTERCARD LMPOP ZMPOP
      ].freeze

      # Commands are stored in a Set for O(1) lookup
      DEFAULT_CACHEABLE_SET = DEFAULT_CACHEABLE.to_set.freeze

      # @param allow_list [Array<String>, nil] Custom allow list (nil = default)
      # @param deny_list [Array<String>, nil] Commands to exclude from caching
      def initialize(allow_list: nil, deny_list: nil)
        base = allow_list ? allow_list.map(&:upcase).to_set : DEFAULT_CACHEABLE_SET.dup
        if deny_list
          deny_list.each { |cmd| base.delete(cmd.upcase) }
        end
        @cacheable = base.freeze
      end

      # Check if a command is cacheable
      #
      # @param command [String] Redis command name (case-insensitive)
      # @return [Boolean]
      def cacheable?(command)
        @cacheable.include?(command)
      end

      # List all cacheable commands
      #
      # @return [Set<String>]
      def commands
        @cacheable
      end
    end
  end
end
