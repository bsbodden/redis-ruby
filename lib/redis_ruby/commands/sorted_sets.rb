# frozen_string_literal: true

module RedisRuby
  module Commands
    # Sorted Set commands
    #
    # @see https://redis.io/commands/?group=sorted-set
    module SortedSets
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
        args = ["ZADD", key]
        args.push("NX") if nx
        args.push("XX") if xx
        args.push("GT") if gt
        args.push("LT") if lt
        args.push("CH") if ch
        args.push(*score_members.flatten)
        call(*args)
      end

      # Remove one or more members from a sorted set
      #
      # @param key [String]
      # @param members [Array<String>]
      # @return [Integer] number of members removed
      def zrem(key, *members)
        call("ZREM", key, *members)
      end

      # Get the score of a member
      #
      # @param key [String]
      # @param member [String]
      # @return [Float, nil] score or nil if member doesn't exist
      def zscore(key, member)
        result = call("ZSCORE", key, member)
        result&.to_f
      end

      # Get the scores of multiple members
      #
      # @param key [String]
      # @param members [Array<String>]
      # @return [Array<Float, nil>] scores
      def zmscore(key, *members)
        result = call("ZMSCORE", key, *members)
        result.map { |s| s&.to_f }
      end

      # Get the rank of a member (0-based, low to high)
      #
      # @param key [String]
      # @param member [String]
      # @return [Integer, nil] rank or nil if member doesn't exist
      def zrank(key, member)
        call("ZRANK", key, member)
      end

      # Get the rank of a member (0-based, high to low)
      #
      # @param key [String]
      # @param member [String]
      # @return [Integer, nil] rank or nil if member doesn't exist
      def zrevrank(key, member)
        call("ZREVRANK", key, member)
      end

      # Get the number of members in a sorted set
      #
      # @param key [String]
      # @return [Integer] cardinality
      def zcard(key)
        call("ZCARD", key)
      end

      # Count members in a score range
      #
      # @param key [String]
      # @param min [String, Numeric] minimum score (use "-inf" for no min)
      # @param max [String, Numeric] maximum score (use "+inf" for no max)
      # @return [Integer] count
      def zcount(key, min, max)
        call("ZCOUNT", key, min, max)
      end

      # Get members in a range by index (low to high)
      #
      # @param key [String]
      # @param start [Integer] start index
      # @param stop [Integer] stop index
      # @param withscores [Boolean] include scores
      # @return [Array] members, or [member, score, ...] if withscores
      def zrange(key, start, stop, withscores: false)
        args = ["ZRANGE", key, start, stop]
        args.push("WITHSCORES") if withscores
        result = call(*args)
        return result unless withscores

        result.each_slice(2).map { |m, s| [m, s.to_f] }
      end

      # Get members in a range by index (high to low)
      #
      # @param key [String]
      # @param start [Integer] start index
      # @param stop [Integer] stop index
      # @param withscores [Boolean] include scores
      # @return [Array] members, or [[member, score], ...] if withscores
      def zrevrange(key, start, stop, withscores: false)
        args = ["ZREVRANGE", key, start, stop]
        args.push("WITHSCORES") if withscores
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
        args = ["ZRANGEBYSCORE", key, min, max]
        args.push("WITHSCORES") if withscores
        args.push("LIMIT", *limit) if limit
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
        args = ["ZREVRANGEBYSCORE", key, max, min]
        args.push("WITHSCORES") if withscores
        args.push("LIMIT", *limit) if limit
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
        call("ZINCRBY", key, increment, member).to_f
      end

      # Remove members in a rank range
      #
      # @param key [String]
      # @param start [Integer] start rank
      # @param stop [Integer] stop rank
      # @return [Integer] number of members removed
      def zremrangebyrank(key, start, stop)
        call("ZREMRANGEBYRANK", key, start, stop)
      end

      # Remove members in a score range
      #
      # @param key [String]
      # @param min [String, Numeric] minimum score
      # @param max [String, Numeric] maximum score
      # @return [Integer] number of members removed
      def zremrangebyscore(key, min, max)
        call("ZREMRANGEBYSCORE", key, min, max)
      end

      # Remove and return members with lowest scores
      #
      # @param key [String]
      # @param count [Integer] number of members to pop
      # @return [Array] [[member, score], ...] or nil
      def zpopmin(key, count = nil)
        result = count ? call("ZPOPMIN", key, count) : call("ZPOPMIN", key)
        return nil if result.nil? || result.empty?

        result.each_slice(2).map { |m, s| [m, s.to_f] }
      end

      # Remove and return members with highest scores
      #
      # @param key [String]
      # @param count [Integer] number of members to pop
      # @return [Array] [[member, score], ...] or nil
      def zpopmax(key, count = nil)
        result = count ? call("ZPOPMAX", key, count) : call("ZPOPMAX", key)
        return nil if result.nil? || result.empty?

        result.each_slice(2).map { |m, s| [m, s.to_f] }
      end

      # Blocking pop from sorted set (lowest scores)
      #
      # @param keys [Array<String>]
      # @param timeout [Numeric] timeout in seconds
      # @return [Array, nil] [key, member, score] or nil
      def bzpopmin(*keys, timeout: 0)
        result = call("BZPOPMIN", *keys, timeout)
        return nil if result.nil?

        [result[0], result[1], result[2].to_f]
      end

      # Blocking pop from sorted set (highest scores)
      #
      # @param keys [Array<String>]
      # @param timeout [Numeric] timeout in seconds
      # @return [Array, nil] [key, member, score] or nil
      def bzpopmax(*keys, timeout: 0)
        result = call("BZPOPMAX", *keys, timeout)
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
        args = ["ZSCAN", key, cursor]
        args.push("MATCH", match) if match
        args.push("COUNT", count) if count
        cursor, pairs = call(*args)
        members = pairs.each_slice(2).map { |m, s| [m, s.to_f] }
        [cursor, members]
      end

      # Store intersection of sorted sets
      #
      # @param destination [String]
      # @param keys [Array<String>]
      # @param weights [Array<Numeric>, nil] multiplication factors
      # @param aggregate [:sum, :min, :max, nil] aggregation function
      # @return [Integer] number of members in result
      def zinterstore(destination, keys, weights: nil, aggregate: nil)
        args = ["ZINTERSTORE", destination, keys.length, *keys]
        args.push("WEIGHTS", *weights) if weights
        args.push("AGGREGATE", aggregate.to_s.upcase) if aggregate
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
        args = ["ZUNIONSTORE", destination, keys.length, *keys]
        args.push("WEIGHTS", *weights) if weights
        args.push("AGGREGATE", aggregate.to_s.upcase) if aggregate
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
        args = ["ZUNION", keys.length, *keys]
        args.push("WEIGHTS", *weights) if weights
        args.push("AGGREGATE", aggregate.to_s.upcase) if aggregate
        args.push("WITHSCORES") if withscores
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
        args = ["ZINTER", keys.length, *keys]
        args.push("WEIGHTS", *weights) if weights
        args.push("AGGREGATE", aggregate.to_s.upcase) if aggregate
        args.push("WITHSCORES") if withscores
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
        args = ["ZDIFF", keys.length, *keys]
        args.push("WITHSCORES") if withscores
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
        call("ZDIFFSTORE", destination, keys.length, *keys)
      end

      # Count members in a lexicographical range
      #
      # @param key [String]
      # @param min [String] minimum value (use "-" for no min, "[a" for inclusive, "(a" for exclusive)
      # @param max [String] maximum value (use "+" for no max, "[z" for inclusive, "(z" for exclusive)
      # @return [Integer] count
      def zlexcount(key, min, max)
        call("ZLEXCOUNT", key, min, max)
      end

      # Get members in a lexicographical range (low to high)
      #
      # @param key [String]
      # @param min [String] minimum value
      # @param max [String] maximum value
      # @param limit [Array, nil] [offset, count] for pagination
      # @return [Array] members
      def zrangebylex(key, min, max, limit: nil)
        args = ["ZRANGEBYLEX", key, min, max]
        args.push("LIMIT", *limit) if limit
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
        args = ["ZREVRANGEBYLEX", key, max, min]
        args.push("LIMIT", *limit) if limit
        call(*args)
      end

      # Remove members in a lexicographical range
      #
      # @param key [String]
      # @param min [String] minimum value
      # @param max [String] maximum value
      # @return [Integer] number of members removed
      def zremrangebylex(key, min, max)
        call("ZREMRANGEBYLEX", key, min, max)
      end

      # Get random members from a sorted set
      #
      # @param key [String]
      # @param count [Integer, nil] number of members to return
      # @param withscores [Boolean] include scores
      # @return [String, Array] single member or array of members (with scores if requested)
      def zrandmember(key, count = nil, withscores: false)
        args = ["ZRANDMEMBER", key]
        args.push(count) if count
        args.push("WITHSCORES") if withscores && count

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
