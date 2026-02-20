# frozen_string_literal: true

require_relative "../dsl/sorted_set_proxy"

module RR
  module Commands
    # Sorted Set commands
    #
    # @see https://redis.io/commands/?group=sorted-set
    module SortedSets
      # ============================================================
      # Idiomatic Ruby API
      # ============================================================

      # Create a sorted set proxy for idiomatic operations
      #
      # @param key_parts [Array<String, Symbol, Integer>] Key components joined with ":"
      # @return [RR::DSL::SortedSetProxy] Chainable sorted set proxy
      #
      # @example Gaming leaderboard
      #   leaderboard = redis.sorted_set(:game, :leaderboard)
      #   leaderboard.add(alice: 1500, bob: 2000)
      #   top_players = leaderboard.top(10, with_scores: true)
      #
      # @example Priority queue
      #   queue = redis.sset(:tasks, :priority)
      #   queue.add(urgent: 1, normal: 5)
      #   next_task = queue.pop_min
      def sset(*key_parts)
        DSL::SortedSetProxy.new(self, *key_parts)
      end

      # Alias for {#sset}
      #
      # @see #sset
      alias sorted_set sset

      # ============================================================
      # Low-Level Commands
      # ============================================================

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
      OPT_INCR = "INCR"
      OPT_BYSCORE = "BYSCORE"
      OPT_BYLEX = "BYLEX"
      OPT_REV = "REV"
      OPT_LIMIT = "LIMIT"
      OPT_WITHSCORES = "WITHSCORES"
      OPT_MATCH = "MATCH"
      OPT_COUNT = "COUNT"
      OPT_WEIGHTS = "WEIGHTS"
      OPT_AGGREGATE = "AGGREGATE"

      # Convert score value to Float, handling infinity
      def parse_score(value)
        return nil if value.nil?
        return value if value.is_a?(Float)

        case value.to_s
        when "inf", "+inf"
          Float::INFINITY
        when "-inf"
          -Float::INFINITY
        else
          Float(value)
        end
      end

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
      def zadd(key, *score_members, nx: false, xx: false, gt: false, lt: false, ch: false, incr: false)
        args = [CMD_ZADD, key]
        args.push(OPT_NX) if nx
        args.push(OPT_XX) if xx
        args.push(OPT_GT) if gt
        args.push(OPT_LT) if lt
        args.push(OPT_CH) if ch
        args.push(OPT_INCR) if incr
        args.push(*score_members.flatten)
        call(*args)
      end

      # Remove one or more members from a sorted set
      #
      # @param key [String]
      # @param members [Array<String>]
      # @return [Integer] number of members removed
      def zrem(key, *members)
        return 0 if members.empty?

        # Fast path for single member (most common)
        return call_2args(CMD_ZREM, key, members[0]) if members.size == 1

        call(CMD_ZREM, key, *members)
      end

      # Get the score of a member
      #
      # @param key [String]
      # @param member [String]
      # @return [Float, nil] score or nil if member doesn't exist
      def zscore(key, member)
        result = call_2args(CMD_ZSCORE, key, member)
        parse_score(result)
      end

      # Get the scores of multiple members
      #
      # @param key [String]
      # @param members [Array<String>]
      # @return [Array<Float, nil>] scores
      def zmscore(key, *members)
        result = call(CMD_ZMSCORE, key, *members)
        result.map { |s| parse_score(s) }
      end

      # Get the rank of a member (0-based, low to high)
      #
      # @param key [String]
      # @param member [String]
      # @return [Integer, nil] rank or nil if member doesn't exist
      def zrank(key, member, withscore: false)
        if withscore
          call(CMD_ZRANK, key, member, "WITHSCORE")
        else
          call_2args(CMD_ZRANK, key, member)
        end
      end

      # Get the rank of a member (0-based, high to low)
      #
      # @param key [String]
      # @param member [String]
      # @param withscore [Boolean] also return score
      # @return [Integer, nil] rank or nil if member doesn't exist
      def zrevrank(key, member, withscore: false)
        if withscore
          call(CMD_ZREVRANK, key, member, "WITHSCORE")
        else
          call_2args(CMD_ZREVRANK, key, member)
        end
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
        return call_3args(CMD_ZRANGE, key, start, stop) if zrange_simple?(byscore, bylex, rev, limit, withscores)

        args = build_zrange_args(key, start, stop, byscore: byscore, bylex: bylex, rev: rev, limit: limit)
        args.push(OPT_WITHSCORES) if withscores
        result = call(*args)
        withscores ? parse_withscores_result(result) : result
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
        return call_3args(CMD_ZREVRANGE, key, start, stop) unless withscores

        result = call(CMD_ZREVRANGE, key, start, stop, OPT_WITHSCORES)
        parse_withscores_result(result)
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
        zrangebyscore_internal(CMD_ZRANGEBYSCORE, key, min, max, withscores: withscores, limit: limit)
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
        zrangebyscore_internal(CMD_ZREVRANGEBYSCORE, key, max, min, withscores: withscores, limit: limit)
      end

      # Increment the score of a member
      #
      # @param key [String]
      # @param increment [Numeric]
      # @param member [String]
      # @return [Float] new score
      def zincrby(key, increment, member)
        parse_score(call_3args(CMD_ZINCRBY, key, increment, member))
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
      # @return [Array] [member, score] without count, [[member, score], ...] with count, or nil
      def zpopmin(key, count = nil)
        zpop_internal(CMD_ZPOPMIN, key, count)
      end

      # Remove and return members with highest scores
      #
      # @param key [String]
      # @param count [Integer] number of members to pop
      # @return [Array] [member, score] without count, [[member, score], ...] with count, or nil
      def zpopmax(key, count = nil)
        zpop_internal(CMD_ZPOPMAX, key, count)
      end

      # Blocking pop from sorted set (lowest scores)
      #
      # @param keys [Array<String>]
      # @param timeout [Numeric] timeout in seconds
      # @return [Array, nil] [key, member, score] or nil
      def bzpopmin(*keys, timeout: 0)
        result = blocking_call(timeout, CMD_BZPOPMIN, *keys, timeout)
        return nil if result.nil?

        [result[0], result[1], parse_score(result[2])]
      end

      # Blocking pop from sorted set (highest scores)
      #
      # @param keys [Array<String>]
      # @param timeout [Numeric] timeout in seconds
      # @return [Array, nil] [key, member, score] or nil
      def bzpopmax(*keys, timeout: 0)
        result = blocking_call(timeout, CMD_BZPOPMAX, *keys, timeout)
        return nil if result.nil?

        [result[0], result[1], parse_score(result[2])]
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
          members = pairs.each_slice(2).map { |m, s| [m, parse_score(s)] }
          return [cursor_result, members]
        end

        args = [CMD_ZSCAN, key, cursor]
        args.push(OPT_MATCH, match) if match
        args.push(OPT_COUNT, count) if count
        cursor_result, pairs = call(*args)
        members = pairs.each_slice(2).map { |m, s| [m, parse_score(s)] }
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
        zstore_operation(CMD_ZINTERSTORE, destination, keys, weights: weights, aggregate: aggregate)
      end

      # Store union of sorted sets
      #
      # @param destination [String]
      # @param keys [Array<String>]
      # @param weights [Array<Numeric>, nil] multiplication factors
      # @param aggregate [:sum, :min, :max, nil] aggregation function
      # @return [Integer] number of members in result
      def zunionstore(destination, keys, weights: nil, aggregate: nil)
        zstore_operation(CMD_ZUNIONSTORE, destination, keys, weights: weights, aggregate: aggregate)
      end

      # Get the union of sorted sets (Redis 6.2+)
      #
      # @param keys [Array<String>]
      # @param weights [Array<Numeric>, nil] multiplication factors
      # @param aggregate [:sum, :min, :max, nil] aggregation function
      # @param withscores [Boolean] include scores
      # @return [Array] members (with scores if requested)
      def zunion(keys, weights: nil, aggregate: nil, withscores: false)
        zset_operation(CMD_ZUNION, keys, weights: weights, aggregate: aggregate, withscores: withscores)
      end

      # Get the intersection of sorted sets (Redis 6.2+)
      #
      # @param keys [Array<String>]
      # @param weights [Array<Numeric>, nil] multiplication factors
      # @param aggregate [:sum, :min, :max, nil] aggregation function
      # @param withscores [Boolean] include scores
      # @return [Array] members (with scores if requested)
      def zinter(keys, weights: nil, aggregate: nil, withscores: false)
        zset_operation(CMD_ZINTER, keys, weights: weights, aggregate: aggregate, withscores: withscores)
      end

      # Get the difference of sorted sets (Redis 6.2+)
      #
      # @param keys [Array<String>]
      # @param withscores [Boolean] include scores
      # @return [Array] members (with scores if requested)
      def zdiff(keys, withscores: false)
        zset_operation(CMD_ZDIFF, keys, withscores: withscores)
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
        parse_zmpop_result(call(*args))
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
        parse_zmpop_result(blocking_call(timeout, *args))
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
        return call_3args(CMD_ZRANGEBYLEX, key, min, max) if limit.nil?

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
        return call_3args(CMD_ZREVRANGEBYLEX, key, max, min) if limit.nil?

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
        return call_1arg(CMD_ZRANDMEMBER, key) if count.nil? && !withscores

        # Fast path: key + count, no withscores
        return call_2args(CMD_ZRANDMEMBER, key, count) if count && !withscores

        # Slow path: withscores
        zrandmember_with_scores(key, count)
      end

      private

      def zrange_simple?(byscore, bylex, rev, limit, withscores)
        !byscore && !bylex && !rev && limit.nil? && !withscores
      end

      def build_zrange_args(key, start, stop, byscore:, bylex:, rev:, limit:)
        args = [CMD_ZRANGE, key, start, stop]
        args.push(OPT_BYSCORE) if byscore
        args.push(OPT_BYLEX) if bylex
        args.push(OPT_REV) if rev
        args.push(OPT_LIMIT, *limit) if limit && (byscore || bylex)
        args
      end

      def zrandmember_with_scores(key, count)
        args = [CMD_ZRANDMEMBER, key]
        args.push(count) if count
        args.push(OPT_WITHSCORES) if count
        result = call(*args)
        count && result ? parse_withscores_result(result) : result
      end

      def parse_withscores_result(result)
        result.each_slice(2).map { |m, s| [m, parse_score(s)] }
      end

      def zpop_internal(cmd, key, count)
        result = count ? call_2args(cmd, key, count) : call_1arg(cmd, key)
        return nil if result.nil? || result.empty?

        pairs = parse_withscores_result(result)
        count ? pairs : pairs[0]
      end

      def zrangebyscore_internal(cmd, key, bound1, bound2, withscores:, limit:)
        return call_3args(cmd, key, bound1, bound2) if !withscores && limit.nil?

        args = [cmd, key, bound1, bound2]
        args.push(OPT_WITHSCORES) if withscores
        args.push(OPT_LIMIT, *limit) if limit
        result = call(*args)
        withscores ? parse_withscores_result(result) : result
      end

      def zset_operation(cmd, keys, weights: nil, aggregate: nil, withscores: false)
        args = [cmd, keys.length, *keys]
        args.push(OPT_WEIGHTS, *weights) if weights
        args.push(OPT_AGGREGATE, aggregate.to_s.upcase) if aggregate
        args.push(OPT_WITHSCORES) if withscores
        result = call(*args)
        withscores ? parse_withscores_result(result) : result
      end

      def zstore_operation(cmd, destination, keys, weights:, aggregate:)
        args = [cmd, destination, keys.length, *keys]
        args.push(OPT_WEIGHTS, *weights) if weights
        args.push(OPT_AGGREGATE, aggregate.to_s.upcase) if aggregate
        call(*args)
      end

      def parse_zmpop_result(result)
        return nil if result.nil?

        key = result[0]
        members = result[1].map { |pair| [pair[0], parse_score(pair[1])] }
        [key, members]
      end
    end
  end
end
