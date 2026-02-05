# frozen_string_literal: true

module RedisRuby
  module Commands
    # Sorted Set commands
    #
    # @see https://redis.io/commands/?group=sorted-set
    module SortedSets
      # Frozen command constants to avoid string allocations
      CMD_ZADD = "ZADD"
      CMD_ZREM = "ZREM"
      CMD_ZSCORE = "ZSCORE"
      CMD_ZMSCORE = "ZMSCORE"
      CMD_ZRANK = "ZRANK"
      CMD_ZREVRANK = "ZREVRANK"
      CMD_ZCARD = "ZCARD"
      CMD_ZCOUNT = "ZCOUNT"
      CMD_ZRANGE = "ZRANGE"
      CMD_ZRANGESTORE = "ZRANGESTORE"
      CMD_ZREVRANGE = "ZREVRANGE"
      CMD_ZRANGEBYSCORE = "ZRANGEBYSCORE"
      CMD_ZREVRANGEBYSCORE = "ZREVRANGEBYSCORE"
      CMD_ZINCRBY = "ZINCRBY"
      CMD_ZREMRANGEBYRANK = "ZREMRANGEBYRANK"
      CMD_ZREMRANGEBYSCORE = "ZREMRANGEBYSCORE"
      CMD_ZPOPMIN = "ZPOPMIN"
      CMD_ZPOPMAX = "ZPOPMAX"
      CMD_BZPOPMIN = "BZPOPMIN"
      CMD_BZPOPMAX = "BZPOPMAX"
      CMD_ZSCAN = "ZSCAN"
      CMD_ZINTERSTORE = "ZINTERSTORE"
      CMD_ZUNIONSTORE = "ZUNIONSTORE"
      CMD_ZUNION = "ZUNION"
      CMD_ZINTER = "ZINTER"
      CMD_ZDIFF = "ZDIFF"
      CMD_ZDIFFSTORE = "ZDIFFSTORE"
      CMD_ZINTERCARD = "ZINTERCARD"
      CMD_ZMPOP = "ZMPOP"
      CMD_BZMPOP = "BZMPOP"
      CMD_ZLEXCOUNT = "ZLEXCOUNT"
      CMD_ZRANGEBYLEX = "ZRANGEBYLEX"
      CMD_ZREVRANGEBYLEX = "ZREVRANGEBYLEX"
      CMD_ZREMRANGEBYLEX = "ZREMRANGEBYLEX"
      CMD_ZRANDMEMBER = "ZRANDMEMBER"

      # Frozen option strings
      OPT_NX = "NX"
      OPT_XX = "XX"
      OPT_GT = "GT"
      OPT_LT = "LT"
      OPT_CH = "CH"
      OPT_BYSCORE = "BYSCORE"
      OPT_BYLEX = "BYLEX"
      OPT_REV = "REV"
      OPT_LIMIT = "LIMIT"
      OPT_WITHSCORES = "WITHSCORES"
      OPT_MATCH = "MATCH"
      OPT_COUNT = "COUNT"
      OPT_WEIGHTS = "WEIGHTS"
      OPT_AGGREGATE = "AGGREGATE"

      # Add one or more members to a sorted set
      #
      # @param key [String]
      # @param score_members [Array] score1, member1, score2, member2, ...
      #   or [[score1, member1], [score2, member2], ...]
      # @param nx [Boolean] only add new elements
      # @param xx [Boolean] only update existing elements
      # @param gt [Boolean] only update if new score > current
      # @param lt [Boolean] only update if new score < current
      # @param ch [Boolean] return number of changed elements
      # @return [Integer] number of elements added (or changed if ch)
      def zadd(key, *score_members, nx: false, xx: false, gt: false, lt: false, ch: false)
        args = [CMD_ZADD, key]
        args.push(OPT_NX) if nx
        args.push(OPT_XX) if xx
        args.push(OPT_GT) if gt
        args.push(OPT_LT) if lt
        args.push(OPT_CH) if ch
        args.push(*score_members.flatten)
        call(*args)
      end

      # Remove one or more members from a sorted set
      #
      # @param key [String]
      # @param members [Array<String>]
      # @return [Integer] number of members removed
      def zrem(key, *members)
        # Fast path for single member (most common)
        if members.size == 1
          return call_2args(CMD_ZREM, key, members[0])
        end

        call(CMD_ZREM, key, *members)
      end

      # Get the score of a member
      #
      # @param key [String]
      # @param member [String]
      # @return [Float, nil] score or nil if member doesn't exist
      def zscore(key, member)
        result = call_2args(CMD_ZSCORE, key, member)
        result&.to_f
      end

      # Get the scores of multiple members
      #
      # @param key [String]
      # @param members [Array<String>]
      # @return [Array<Float, nil>] scores
      def zmscore(key, *members)
        result = call(CMD_ZMSCORE, key, *members)
        result.map { |s| s&.to_f }
      end

      # Get the rank of a member (0-based, low to high)
      #
      # @param key [String]
      # @param member [String]
      # @return [Integer, nil] rank or nil if member doesn't exist
      def zrank(key, member)
        call_2args(CMD_ZRANK, key, member)
      end

      # Get the rank of a member (0-based, high to low)
      #
      # @param key [String]
      # @param member [String]
      # @return [Integer, nil] rank or nil if member doesn't exist
      def zrevrank(key, member)
        call_2args(CMD_ZREVRANK, key, member)
      end

      # Get the number of members in a sorted set
      #
      # @param key [String]
      # @return [Integer] cardinality
      def zcard(key)
        call_1arg(CMD_ZCARD, key)
      end

      # Count members in a score range
      #
      # @param key [String]
      # @param min [String, Numeric] minimum score (use "-inf" for no min)
      # @param max [String, Numeric] maximum score (use "+inf" for no max)
      # @return [Integer] count
      def zcount(key, min, max)
        call_3args(CMD_ZCOUNT, key, min, max)
      end

      # Get members in a range (unified interface, Redis 6.2+)
      #
      # This is the unified ZRANGE command that can work with:
      # - Index ranges (default)
      # - Score ranges (with byscore: true)
      # - Lexicographical ranges (with bylex: true)
      #
      # @param key [String]
      # @param start [Integer, String, Numeric] start value
      # @param stop [Integer, String, Numeric] stop value
      # @param byscore [Boolean] interpret start/stop as scores
      # @param bylex [Boolean] interpret start/stop as lexicographical values
      # @param rev [Boolean] reverse the results (high to low)
      # @param limit [Array, nil] [offset, count] for pagination (only with byscore or bylex)
      # @param withscores [Boolean] include scores in result
      # @return [Array] members, or [[member, score], ...] if withscores
      #
      # @example Get by index
      #   redis.zrange("zset", 0, -1)
      #
      # @example Get by score
      #   redis.zrange("zset", 0, 100, byscore: true)
      #
      # @example Get by lex in reverse with limit
      #   redis.zrange("zset", "[c", "[a", bylex: true, rev: true, limit: [0, 5])
      def zrange(key, start, stop, byscore: false, bylex: false, rev: false, limit: nil, withscores: false)
        # Fast path: simple index range without options
        if !byscore && !bylex && !rev && limit.nil? && !withscores
          return call_3args(CMD_ZRANGE, key, start, stop)
        end

        args = [CMD_ZRANGE, key, start, stop]
        args.push(OPT_BYSCORE) if byscore
        args.push(OPT_BYLEX) if bylex
        args.push(OPT_REV) if rev
        args.push(OPT_LIMIT, *limit) if limit && (byscore || bylex)
        args.push(OPT_WITHSCORES) if withscores
        result = call(*args)
        return result unless withscores

        result.each_slice(2).map { |m, s| [m, s.to_f] }
      end

      # Store range results in a destination key (Redis 6.2+)
      #
      # @param destination [String] destination key
      # @param key [String] source key
      # @param start [Integer, String, Numeric] start value
      # @param stop [Integer, String, Numeric] stop value
      # @param byscore [Boolean] interpret start/stop as scores
      # @param bylex [Boolean] interpret start/stop as lexicographical values
      # @param rev [Boolean] reverse the results
      # @param limit [Array, nil] [offset, count] for pagination
      # @return [Integer] number of elements in the resulting sorted set
      #
      # @example Store top 10 by score
      #   redis.zrangestore("top10", "scores", 0, 9)
      def zrangestore(destination, key, start, stop, byscore: false, bylex: false, rev: false, limit: nil)
        args = [CMD_ZRANGESTORE, destination, key, start, stop]
        args.push(OPT_BYSCORE) if byscore
        args.push(OPT_BYLEX) if bylex
        args.push(OPT_REV) if rev
        args.push(OPT_LIMIT, *limit) if limit && (byscore || bylex)
        call(*args)
      end

      # Get members in a range by index (high to low)
      #
      # @param key [String]
      # @param start [Integer] start index
      # @param stop [Integer] stop index
      # @param withscores [Boolean] include scores
      # @return [Array] members, or [[member, score], ...] if withscores
      def zrevrange(key, start, stop, withscores: false)
        # Fast path: no withscores
        unless withscores
          return call_3args(CMD_ZREVRANGE, key, start, stop)
        end

        args = [CMD_ZREVRANGE, key, start, stop]
        args.push(OPT_WITHSCORES) if withscores
        result = call(*args)
        return result unless withscores

        result.each_slice(2).map { |m, s| [m, s.to_f] }
      end

      # Get members in a score range (low to high)
      #
      # @param key [String]
      # @param min [String, Numeric] minimum score
      # @param max [String, Numeric] maximum score
      # @param withscores [Boolean] include scores
      # @param limit [Array, nil] [offset, count] for pagination
      # @return [Array] members
      def zrangebyscore(key, min, max, withscores: false, limit: nil)
        # Fast path: no options
        if !withscores && limit.nil?
          return call_3args(CMD_ZRANGEBYSCORE, key, min, max)
        end

        args = [CMD_ZRANGEBYSCORE, key, min, max]
        args.push(OPT_WITHSCORES) if withscores
        args.push(OPT_LIMIT, *limit) if limit
        result = call(*args)
        return result unless withscores

        result.each_slice(2).map { |m, s| [m, s.to_f] }
      end

      # Get members in a score range (high to low)
      #
      # @param key [String]
      # @param max [String, Numeric] maximum score
      # @param min [String, Numeric] minimum score
      # @param withscores [Boolean] include scores
      # @param limit [Array, nil] [offset, count] for pagination
      # @return [Array] members
      def zrevrangebyscore(key, max, min, withscores: false, limit: nil)
        # Fast path: no options
        if !withscores && limit.nil?
          return call_3args(CMD_ZREVRANGEBYSCORE, key, max, min)
        end

        args = [CMD_ZREVRANGEBYSCORE, key, max, min]
        args.push(OPT_WITHSCORES) if withscores
        args.push(OPT_LIMIT, *limit) if limit
        result = call(*args)
        return result unless withscores

        result.each_slice(2).map { |m, s| [m, s.to_f] }
      end

      # Increment the score of a member
      #
      # @param key [String]
      # @param increment [Numeric]
      # @param member [String]
      # @return [Float] new score
      def zincrby(key, increment, member)
        call_3args(CMD_ZINCRBY, key, increment, member).to_f
      end

      # Remove members in a rank range
      #
      # @param key [String]
      # @param start [Integer] start rank
      # @param stop [Integer] stop rank
      # @return [Integer] number of members removed
      def zremrangebyrank(key, start, stop)
        call_3args(CMD_ZREMRANGEBYRANK, key, start, stop)
      end

      # Remove members in a score range
      #
      # @param key [String]
      # @param min [String, Numeric] minimum score
      # @param max [String, Numeric] maximum score
      # @return [Integer] number of members removed
      def zremrangebyscore(key, min, max)
        call_3args(CMD_ZREMRANGEBYSCORE, key, min, max)
      end

      # Remove and return members with lowest scores
      #
      # @param key [String]
      # @param count [Integer] number of members to pop
      # @return [Array] [[member, score], ...] or nil
      def zpopmin(key, count = nil)
        result = if count
                   call_2args(CMD_ZPOPMIN, key, count)
                 else
                   call_1arg(CMD_ZPOPMIN, key)
                 end
        return nil if result.nil? || result.empty?

        result.each_slice(2).map { |m, s| [m, s.to_f] }
      end

      # Remove and return members with highest scores
      #
      # @param key [String]
      # @param count [Integer] number of members to pop
      # @return [Array] [[member, score], ...] or nil
      def zpopmax(key, count = nil)
        result = if count
                   call_2args(CMD_ZPOPMAX, key, count)
                 else
                   call_1arg(CMD_ZPOPMAX, key)
                 end
        return nil if result.nil? || result.empty?

        result.each_slice(2).map { |m, s| [m, s.to_f] }
      end

      # Blocking pop from sorted set (lowest scores)
      #
      # @param keys [Array<String>]
      # @param timeout [Numeric] timeout in seconds
      # @return [Array, nil] [key, member, score] or nil
      def bzpopmin(*keys, timeout: 0)
        result = call(CMD_BZPOPMIN, *keys, timeout)
        return nil if result.nil?

        [result[0], result[1], result[2].to_f]
      end

      # Blocking pop from sorted set (highest scores)
      #
      # @param keys [Array<String>]
      # @param timeout [Numeric] timeout in seconds
      # @return [Array, nil] [key, member, score] or nil
      def bzpopmax(*keys, timeout: 0)
        result = call(CMD_BZPOPMAX, *keys, timeout)
        return nil if result.nil?

        [result[0], result[1], result[2].to_f]
      end

      # Incrementally iterate sorted set members
      #
      # @param key [String]
      # @param cursor [Integer] cursor position
      # @param match [String, nil] pattern
      # @param count [Integer, nil] hint for count
      # @return [Array] [next_cursor, [[member, score], ...]]
      def zscan(key, cursor, match: nil, count: nil)
        # Fast path: no options
        if match.nil? && count.nil?
          cursor_result, pairs = call_2args(CMD_ZSCAN, key, cursor)
          members = pairs.each_slice(2).map { |m, s| [m, s.to_f] }
          return [cursor_result, members]
        end

        args = [CMD_ZSCAN, key, cursor]
        args.push(OPT_MATCH, match) if match
        args.push(OPT_COUNT, count) if count
        cursor_result, pairs = call(*args)
        members = pairs.each_slice(2).map { |m, s| [m, s.to_f] }
        [cursor_result, members]
      end

      # Iterate over sorted set members with scores
      #
      # Returns an Enumerator that handles cursor management automatically.
      # Yields [member, score] pairs.
      #
      # @param key [String] sorted set key
      # @param match [String] pattern to match members (default: "*")
      # @param count [Integer] hint for number of elements per iteration
      # @return [Enumerator] yields [member, score] pairs
      # @example
      #   client.zscan_iter("myzset").each { |member, score| puts "#{member}: #{score}" }
      #   client.zscan_iter("leaderboard", match: "player:*").first(10)
      def zscan_iter(key, match: "*", count: 10)
        Enumerator.new do |yielder|
          cursor = "0"
          loop do
            cursor, members = zscan(key, cursor, match: match, count: count)
            members.each { |member, score| yielder << [member, score] }
            break if cursor == "0"
          end
        end
      end

      # Store intersection of sorted sets
      #
      # @param destination [String]
      # @param keys [Array<String>]
      # @param weights [Array<Numeric>, nil] multiplication factors
      # @param aggregate [:sum, :min, :max, nil] aggregation function
      # @return [Integer] number of members in result
      def zinterstore(destination, keys, weights: nil, aggregate: nil)
        args = [CMD_ZINTERSTORE, destination, keys.length, *keys]
        args.push(OPT_WEIGHTS, *weights) if weights
        args.push(OPT_AGGREGATE, aggregate.to_s.upcase) if aggregate
        call(*args)
      end

      # Store union of sorted sets
      #
      # @param destination [String]
      # @param keys [Array<String>]
      # @param weights [Array<Numeric>, nil] multiplication factors
      # @param aggregate [:sum, :min, :max, nil] aggregation function
      # @return [Integer] number of members in result
      def zunionstore(destination, keys, weights: nil, aggregate: nil)
        args = [CMD_ZUNIONSTORE, destination, keys.length, *keys]
        args.push(OPT_WEIGHTS, *weights) if weights
        args.push(OPT_AGGREGATE, aggregate.to_s.upcase) if aggregate
        call(*args)
      end

      # Get the union of sorted sets (Redis 6.2+)
      #
      # @param keys [Array<String>]
      # @param weights [Array<Numeric>, nil] multiplication factors
      # @param aggregate [:sum, :min, :max, nil] aggregation function
      # @param withscores [Boolean] include scores
      # @return [Array] members (with scores if requested)
      def zunion(keys, weights: nil, aggregate: nil, withscores: false)
        args = [CMD_ZUNION, keys.length, *keys]
        args.push(OPT_WEIGHTS, *weights) if weights
        args.push(OPT_AGGREGATE, aggregate.to_s.upcase) if aggregate
        args.push(OPT_WITHSCORES) if withscores
        result = call(*args)
        return result unless withscores

        result.each_slice(2).map { |m, s| [m, s.to_f] }
      end

      # Get the intersection of sorted sets (Redis 6.2+)
      #
      # @param keys [Array<String>]
      # @param weights [Array<Numeric>, nil] multiplication factors
      # @param aggregate [:sum, :min, :max, nil] aggregation function
      # @param withscores [Boolean] include scores
      # @return [Array] members (with scores if requested)
      def zinter(keys, weights: nil, aggregate: nil, withscores: false)
        args = [CMD_ZINTER, keys.length, *keys]
        args.push(OPT_WEIGHTS, *weights) if weights
        args.push(OPT_AGGREGATE, aggregate.to_s.upcase) if aggregate
        args.push(OPT_WITHSCORES) if withscores
        result = call(*args)
        return result unless withscores

        result.each_slice(2).map { |m, s| [m, s.to_f] }
      end

      # Get the difference of sorted sets (Redis 6.2+)
      #
      # @param keys [Array<String>]
      # @param withscores [Boolean] include scores
      # @return [Array] members (with scores if requested)
      def zdiff(keys, withscores: false)
        args = [CMD_ZDIFF, keys.length, *keys]
        args.push(OPT_WITHSCORES) if withscores
        result = call(*args)
        return result unless withscores

        result.each_slice(2).map { |m, s| [m, s.to_f] }
      end

      # Store the difference of sorted sets (Redis 6.2+)
      #
      # @param destination [String]
      # @param keys [Array<String>]
      # @return [Integer] number of members in result
      def zdiffstore(destination, keys)
        call(CMD_ZDIFFSTORE, destination, keys.length, *keys)
      end

      # Get the cardinality of the intersection (Redis 7.0+)
      #
      # Returns the number of members that would be in the intersection
      # without actually computing the full intersection.
      #
      # @param keys [Array<String>] sorted sets to intersect
      # @param limit [Integer, nil] stop counting after this many
      # @return [Integer] cardinality of intersection
      #
      # @example
      #   redis.zintercard("zset1", "zset2")
      #   # => 5
      #
      # @example With limit
      #   redis.zintercard("zset1", "zset2", limit: 10)
      #   # => 5 (or up to 10)
      def zintercard(*keys, limit: nil)
        args = [CMD_ZINTERCARD, keys.length, *keys]
        args.push(OPT_LIMIT, limit) if limit
        call(*args)
      end

      # Pop members from multiple sorted sets (Redis 7.0+)
      #
      # @param keys [Array<String>] sorted sets to pop from
      # @param modifier [:min, :max] pop lowest or highest scores
      # @param count [Integer, nil] number of members to pop
      # @return [Array, nil] [key, [[member, score], ...]] or nil if all sets are empty
      #
      # @example Pop one member with lowest score
      #   redis.zmpop("zset1", "zset2", modifier: :min)
      #   # => ["zset1", [["member", 1.0]]]
      #
      # @example Pop multiple members with highest scores
      #   redis.zmpop("zset1", "zset2", modifier: :max, count: 3)
      #   # => ["zset1", [["m1", 10.0], ["m2", 9.0], ["m3", 8.0]]]
      def zmpop(*keys, modifier: :min, count: nil)
        args = [CMD_ZMPOP, keys.length, *keys, modifier.to_s.upcase]
        args.push(OPT_COUNT, count) if count
        result = call(*args)
        return nil if result.nil?

        # Response format is [key, [[member, score], [member, score], ...]]
        key = result[0]
        members = result[1].map { |pair| [pair[0], pair[1].to_f] }
        [key, members]
      end

      # Blocking pop from multiple sorted sets (Redis 7.0+)
      #
      # @param timeout [Numeric] timeout in seconds (0 = block forever)
      # @param keys [Array<String>] sorted sets to pop from
      # @param modifier [:min, :max] pop lowest or highest scores
      # @param count [Integer, nil] number of members to pop
      # @return [Array, nil] [key, [[member, score], ...]] or nil on timeout
      def bzmpop(timeout, *keys, modifier: :min, count: nil)
        args = [CMD_BZMPOP, timeout, keys.length, *keys, modifier.to_s.upcase]
        args.push(OPT_COUNT, count) if count
        result = call(*args)
        return nil if result.nil?

        # Response format is [key, [[member, score], [member, score], ...]]
        key = result[0]
        members = result[1].map { |pair| [pair[0], pair[1].to_f] }
        [key, members]
      end

      # Count members in a lexicographical range
      #
      # @param key [String]
      # @param min [String] minimum value (use "-" for no min, "[a" for inclusive, "(a" for exclusive)
      # @param max [String] maximum value (use "+" for no max, "[z" for inclusive, "(z" for exclusive)
      # @return [Integer] count
      def zlexcount(key, min, max)
        call_3args(CMD_ZLEXCOUNT, key, min, max)
      end

      # Get members in a lexicographical range (low to high)
      #
      # @param key [String]
      # @param min [String] minimum value
      # @param max [String] maximum value
      # @param limit [Array, nil] [offset, count] for pagination
      # @return [Array] members
      def zrangebylex(key, min, max, limit: nil)
        # Fast path: no limit
        if limit.nil?
          return call_3args(CMD_ZRANGEBYLEX, key, min, max)
        end

        args = [CMD_ZRANGEBYLEX, key, min, max]
        args.push(OPT_LIMIT, *limit) if limit
        call(*args)
      end

      # Get members in a lexicographical range (high to low)
      #
      # @param key [String]
      # @param max [String] maximum value
      # @param min [String] minimum value
      # @param limit [Array, nil] [offset, count] for pagination
      # @return [Array] members
      def zrevrangebylex(key, max, min, limit: nil)
        # Fast path: no limit
        if limit.nil?
          return call_3args(CMD_ZREVRANGEBYLEX, key, max, min)
        end

        args = [CMD_ZREVRANGEBYLEX, key, max, min]
        args.push(OPT_LIMIT, *limit) if limit
        call(*args)
      end

      # Remove members in a lexicographical range
      #
      # @param key [String]
      # @param min [String] minimum value
      # @param max [String] maximum value
      # @return [Integer] number of members removed
      def zremrangebylex(key, min, max)
        call_3args(CMD_ZREMRANGEBYLEX, key, min, max)
      end

      # Get random members from a sorted set
      #
      # @param key [String]
      # @param count [Integer, nil] number of members to return
      # @param withscores [Boolean] include scores
      # @return [String, Array] single member or array of members (with scores if requested)
      def zrandmember(key, count = nil, withscores: false)
        # Fast path: just key
        if count.nil? && !withscores
          return call_1arg(CMD_ZRANDMEMBER, key)
        end

        # Fast path: key + count, no withscores
        if count && !withscores
          return call_2args(CMD_ZRANDMEMBER, key, count)
        end

        args = [CMD_ZRANDMEMBER, key]
        args.push(count) if count
        args.push(OPT_WITHSCORES) if withscores && count

        result = call(*args)

        # Handle withscores response
        if withscores && count && result
          result.each_slice(2).map { |m, s| [m, s.to_f] }
        else
          result
        end
      end
    end
  end
end
