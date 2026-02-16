# frozen_string_literal: true

module RR
  module DSL
    # Chainable proxy for Redis Sorted Set operations
    #
    # Provides a fluent, idiomatic Ruby API for working with Redis sorted sets,
    # optimized for leaderboards, rankings, and scored collections.
    #
    # @example Gaming leaderboard
    #   leaderboard = redis.sorted_set(:game, :leaderboard)
    #   leaderboard.add(alice: 1500, bob: 2000, charlie: 1800)
    #   top_players = leaderboard.top(10).with_scores.execute
    #
    # @example Priority queue
    #   queue = redis.sorted_set(:tasks, :priority)
    #   queue.add(urgent: 1, normal: 5, low: 10)
    #   next_task = queue.bottom(1).execute.first
    #
    class SortedSetProxy
      attr_reader :key

      # @private
      def initialize(redis, *key_parts)
        @redis = redis
        @key = key_parts.map(&:to_s).join(":")
      end

      # Add one or more members with scores
      #
      # @overload add(member, score)
      #   Add a single member with score
      #   @param member [String, Symbol] Member name
      #   @param score [Numeric] Score value
      #
      # @overload add(**members_scores)
      #   Add multiple members with scores
      #   @param members_scores [Hash] Member => score pairs
      #
      # @return [self] For method chaining
      #
      # @example Single member
      #   sorted_set.add(:player1, 100)
      #
      # @example Multiple members
      #   sorted_set.add(player1: 100, player2: 200, player3: 150)
      def add(*args, **kwargs)
        if args.empty? && !kwargs.empty?
          # add(player1: 100, player2: 200)
          flat_args = kwargs.flat_map { |member, score| [score, member.to_s] }
          @redis.zadd(@key, *flat_args)
        elsif args.size == 2 && kwargs.empty?
          # add(:player1, 100)
          @redis.zadd(@key, args[1], args[0].to_s)
        else
          raise ArgumentError, "Invalid arguments. Use add(member, score) or add(member1: score1, member2: score2)"
        end
        self
      end

      # Increment a member's score
      #
      # @param member [String, Symbol] Member name
      # @param by [Numeric] Amount to increment (default: 1)
      # @return [self] For method chaining
      #
      # @example
      #   sorted_set.increment(:player1, 10)
      def increment(member, by = 1)
        @redis.zincrby(@key, by, member.to_s)
        self
      end

      # Decrement a member's score
      #
      # @param member [String, Symbol] Member name
      # @param by [Numeric] Amount to decrement (default: 1)
      # @return [self] For method chaining
      #
      # @example
      #   sorted_set.decrement(:player1, 5)
      def decrement(member, by = 1)
        @redis.zincrby(@key, -by, member.to_s)
        self
      end

      # Get a member's score
      #
      # @param member [String, Symbol] Member name
      # @return [Float, nil] Score or nil if member doesn't exist
      #
      # @example
      #   sorted_set.score(:player1)  # => 100.0
      def score(member)
        @redis.zscore(@key, member.to_s)
      end

      # Get a member's rank (0-based, ascending order)
      #
      # @param member [String, Symbol] Member name
      # @return [Integer, nil] Rank or nil if member doesn't exist
      #
      # @example
      #   sorted_set.rank(:player1)  # => 0 (lowest score)
      def rank(member)
        @redis.zrank(@key, member.to_s)
      end

      # Get a member's rank (0-based, descending order)
      #
      # @param member [String, Symbol] Member name
      # @return [Integer, nil] Rank or nil if member doesn't exist
      #
      # @example
      #   sorted_set.reverse_rank(:player1)  # => 0 (highest score)
      def reverse_rank(member)
        @redis.zrevrank(@key, member.to_s)
      end

      # Get top N members (highest scores first)
      #
      # @param n [Integer] Number of members to retrieve
      # @param with_scores [Boolean] Include scores in result
      # @return [Array] Array of members or [member, score] pairs
      #
      # @example
      #   sorted_set.top(10)  # => ["player3", "player2", "player1"]
      #   sorted_set.top(10, with_scores: true)  # => [["player3", 200.0], ...]
      def top(n, with_scores: false)
        @redis.zrevrange(@key, 0, n - 1, withscores: with_scores)
      end

      # Get bottom N members (lowest scores first)
      #
      # @param n [Integer] Number of members to retrieve
      # @param with_scores [Boolean] Include scores in result
      # @return [Array] Array of members or [member, score] pairs
      #
      # @example
      #   sorted_set.bottom(5)  # => ["player1", "player2", ...]
      def bottom(n, with_scores: false)
        @redis.zrange(@key, 0, n - 1, withscores: with_scores)
      end

      # Get members in a rank range (ascending order)
      #
      # @param range [Range] Rank range (0-based)
      # @param with_scores [Boolean] Include scores in result
      # @return [Array] Array of members or [member, score] pairs
      #
      # @example
      #   sorted_set.range(0..9)  # Top 10 by rank (ascending)
      #   sorted_set.range(0..9, with_scores: true)
      def range(range, with_scores: false)
        @redis.zrange(@key, range.begin, range.end, withscores: with_scores)
      end

      # Get members in a rank range (descending order)
      #
      # @param range [Range] Rank range (0-based)
      # @param with_scores [Boolean] Include scores in result
      # @return [Array] Array of members or [member, score] pairs
      #
      # @example
      #   sorted_set.reverse_range(0..9)  # Top 10 by rank (descending)
      def reverse_range(range, with_scores: false)
        @redis.zrevrange(@key, range.begin, range.end, withscores: with_scores)
      end

      # Get members in a score range
      #
      # @param min [Numeric, String] Minimum score (or "-inf")
      # @param max [Numeric, String] Maximum score (or "+inf")
      # @param with_scores [Boolean] Include scores in result
      # @param limit [Array<Integer, Integer>] [offset, count] for pagination
      # @return [Array] Array of members or [member, score] pairs
      #
      # @example
      #   sorted_set.by_score(100, 200)
      #   sorted_set.by_score(100, "+inf", with_scores: true)
      #   sorted_set.by_score(0, 100, limit: [0, 10])
      def by_score(min, max, with_scores: false, limit: nil)
        @redis.zrangebyscore(@key, min, max, withscores: with_scores, limit: limit)
      end

      # Get members in a score range (descending order)
      #
      # @param max [Numeric, String] Maximum score (or "+inf")
      # @param min [Numeric, String] Minimum score (or "-inf")
      # @param with_scores [Boolean] Include scores in result
      # @param limit [Array<Integer, Integer>] [offset, count] for pagination
      # @return [Array] Array of members or [member, score] pairs
      #
      # @example
      #   sorted_set.reverse_by_score(200, 100)
      def reverse_by_score(max, min, with_scores: false, limit: nil)
        @redis.zrevrangebyscore(@key, max, min, withscores: with_scores, limit: limit)
      end

      # Remove one or more members
      #
      # @param members [Array<String, Symbol>] Members to remove
      # @return [self] For method chaining
      #
      # @example
      #   sorted_set.remove(:player1)
      #   sorted_set.remove(:player1, :player2, :player3)
      def remove(*members)
        return self if members.empty?
        @redis.zrem(@key, *members.map(&:to_s))
        self
      end

      # Remove members by rank range
      #
      # @param range [Range] Rank range (0-based)
      # @return [Integer] Number of members removed
      #
      # @example
      #   sorted_set.remove_by_rank(0..4)  # Remove bottom 5, returns 5
      def remove_by_rank(range)
        @redis.zremrangebyrank(@key, range.begin, range.end)
      end

      # Remove members by score range
      #
      # @param min [Numeric, String] Minimum score
      # @param max [Numeric, String] Maximum score
      # @return [Integer] Number of members removed
      #
      # @example
      #   sorted_set.remove_by_score(0, 50)  # => 3
      def remove_by_score(min, max)
        @redis.zremrangebyscore(@key, min, max)
      end

      # Pop member with lowest score
      #
      # @param count [Integer] Number of members to pop
      # @param with_scores [Boolean] Include scores in result
      # @return [String, Array] Member(s) or [member, score] pair(s)
      #
      # @example
      #   sorted_set.pop_min  # => "player1"
      #   sorted_set.pop_min(2, with_scores: true)  # => [["player1", 100.0], ...]
      def pop_min(count = nil, with_scores: false)
        result = @redis.zpopmin(@key, count)
        return nil if result.nil?

        if with_scores
          result
        elsif count.nil?
          result[0]  # Single member without count
        else
          result.map(&:first)  # Multiple members
        end
      end

      # Pop member with highest score
      #
      # @param count [Integer] Number of members to pop
      # @param with_scores [Boolean] Include scores in result
      # @return [String, Array] Member(s) or [member, score] pair(s)
      #
      # @example
      #   sorted_set.pop_max  # => "player3"
      def pop_max(count = nil, with_scores: false)
        result = @redis.zpopmax(@key, count)
        return nil if result.nil?

        if with_scores
          result
        elsif count.nil?
          result[0]  # Single member without count
        else
          result.map(&:first)  # Multiple members
        end
      end

      # Get total number of members
      #
      # @return [Integer] Number of members
      #
      # @example
      #   sorted_set.count  # => 10
      def count
        @redis.zcard(@key)
      end
      alias size count
      alias length count

      # Count members in a score range
      #
      # @param min [Numeric, String] Minimum score
      # @param max [Numeric, String] Maximum score
      # @return [Integer] Number of members in range
      #
      # @example
      #   sorted_set.count_by_score(100, 200)  # => 5
      def count_by_score(min, max)
        @redis.zcount(@key, min, max)
      end

      # Check if a member exists
      #
      # @param member [String, Symbol] Member name
      # @return [Boolean] true if member exists
      #
      # @example
      #   sorted_set.member?(:player1)  # => true
      def member?(member)
        !@redis.zscore(@key, member.to_s).nil?
      end
      alias include? member?

      # Check if the sorted set exists
      #
      # @return [Boolean] true if key exists
      #
      # @example
      #   sorted_set.exists?  # => true
      def exists?
        @redis.exists(@key) == 1
      end

      # Check if the sorted set is empty
      #
      # @return [Boolean] true if no members
      #
      # @example
      #   sorted_set.empty?  # => false
      def empty?
        count == 0
      end

      # Remove all members
      #
      # @return [Integer] Number of members removed
      #
      # @example
      #   sorted_set.clear
      def clear
        @redis.del(@key)
      end

      # Iterate over all members with scores
      #
      # @yield [member, score] Yields each member and score
      # @return [self, Enumerator] self if block given, Enumerator otherwise
      #
      # @example
      #   sorted_set.each { |member, score| puts "#{member}: #{score}" }
      def each(&block)
        return enum_for(:each) unless block_given?

        cursor = 0
        loop do
          cursor, results = @redis.zscan(@key, cursor)
          # zscan returns [[member, score], ...] pairs
          results.each do |member, score|
            yield member.to_sym, score
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
      #   sorted_set.each_member { |member| puts member }
      def each_member(&block)
        return enum_for(:each_member) unless block_given?

        each { |member, _score| yield member }
      end

      # Get all members as an array
      #
      # @param with_scores [Boolean] Include scores
      # @return [Array] Array of members or [member, score] pairs
      #
      # @example
      #   sorted_set.to_a  # => ["player1", "player2", "player3"]
      #   sorted_set.to_a(with_scores: true)  # => [["player1", 100.0], ...]
      def to_a(with_scores: false)
        @redis.zrange(@key, 0, -1, withscores: with_scores)
      end

      # Get all members as a hash (member => score)
      #
      # @return [Hash] Hash of member => score pairs
      #
      # @example
      #   sorted_set.to_h  # => {player1: 100.0, player2: 200.0}
      def to_h
        result = @redis.zrange(@key, 0, -1, withscores: true)
        return {} if result.nil? || result.empty?

        Hash[result.map { |member, score| [member.to_sym, score] }]
      end

      # Set expiration time in seconds
      #
      # @param seconds [Integer] Seconds until expiration
      # @return [self] For method chaining
      #
      # @example
      #   sorted_set.expire(3600)  # Expire in 1 hour
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
      #   sorted_set.expire_at(Time.now + 3600)
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
      #   sorted_set.ttl  # => 3600
      def ttl
        @redis.ttl(@key)
      end

      # Remove expiration
      #
      # @return [self] For method chaining
      #
      # @example
      #   sorted_set.persist
      def persist
        @redis.persist(@key)
        self
      end

      # Get random member(s)
      #
      # @param count [Integer] Number of members to return
      # @param with_scores [Boolean] Include scores in result
      # @return [String, Array] Random member(s)
      #
      # @example
      #   sorted_set.random  # => "player2"
      #   sorted_set.random(3)  # => ["player1", "player3", "player2"]
      def random(count = nil, with_scores: false)
        if count.nil?
          @redis.zrandmember(@key)
        else
          args = [@key, count]
          args.push("WITHSCORES") if with_scores
          @redis.zrandmember(*args)
        end
      end

      private

      # Build composite key from parts
      def build_key(*parts)
        parts.map(&:to_s).join(":")
      end
    end
  end
end


