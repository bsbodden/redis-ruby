# frozen_string_literal: true

require_relative "../dsl/set_proxy"

module RR
  module Commands
    # Set commands
    #
    # @see https://redis.io/commands/?group=set
    module Sets
      # ============================================================
      # Idiomatic Ruby API
      # ============================================================

      # Create a set proxy for idiomatic operations
      #
      # Provides a fluent, Ruby-esque interface for working with Redis sets.
      # Supports composite keys with automatic ":" joining.
      #
      # Note: Named `redis_set` to avoid conflict with the Redis SET command for strings.
      #
      # @param key_parts [Array<String, Symbol, Integer>] Key components
      # @return [RR::DSL::SetProxy] Set proxy instance
      #
      # @example Basic usage
      #   tags = redis.redis_set(:tags)
      #   tags.add("ruby", "redis", "database")
      #   tags.member?("ruby")  # => true
      #
      # @example Composite keys
      #   user_tags = redis.redis_set(:user, 123, :tags)
      #   user_tags.add("developer", "ruby")
      #
      # @example Set operations
      #   common = tags.intersect(:other_tags)
      #   all = tags.union(:tag_set_1, :tag_set_2)
      #
      # @example Chainable operations
      #   redis.redis_set(:temp, :tags)
      #     .add("tag1", "tag2", "tag3")
      #     .remove("tag1")
      #     .expire(3600)
      def redis_set(*key_parts)
        DSL::SetProxy.new(self, *key_parts)
      end

      # ============================================================
      # Low-Level Commands
      # ============================================================

      # Frozen command constants to avoid string allocations
      CMD_SADD = "SADD"
      CMD_SREM = "SREM"
      CMD_SISMEMBER = "SISMEMBER"
      CMD_SMISMEMBER = "SMISMEMBER"
      CMD_SMEMBERS = "SMEMBERS"
      CMD_SCARD = "SCARD"
      CMD_SPOP = "SPOP"
      CMD_SRANDMEMBER = "SRANDMEMBER"
      CMD_SMOVE = "SMOVE"
      CMD_SINTER = "SINTER"
      CMD_SINTERSTORE = "SINTERSTORE"
      CMD_SINTERCARD = "SINTERCARD"
      CMD_SUNION = "SUNION"
      CMD_SUNIONSTORE = "SUNIONSTORE"
      CMD_SDIFF = "SDIFF"
      CMD_SDIFFSTORE = "SDIFFSTORE"
      CMD_SSCAN = "SSCAN"

      # Frozen option strings
      OPT_MATCH = "MATCH"
      OPT_COUNT = "COUNT"
      OPT_LIMIT = "LIMIT"

      # Add one or more members to a set
      #
      # @param key [String]
      # @param members [Array<String>]
      # @return [Integer] number of members added (not already present)
      def sadd(key, *members)
        # Fast path for single member (most common)
        return call_2args(CMD_SADD, key, members[0]) if members.size == 1

        call(CMD_SADD, key, *members)
      end

      # Remove one or more members from a set
      #
      # @param key [String]
      # @param members [Array<String>]
      # @return [Integer] number of members removed
      def srem(key, *members)
        # Fast path for single member (most common)
        return call_2args(CMD_SREM, key, members[0]) if members.size == 1

        call(CMD_SREM, key, *members)
      end

      # Check if a member is in a set
      #
      # @param key [String]
      # @param member [String]
      # @return [Integer] 1 if member exists, 0 otherwise
      def sismember(key, member)
        call_2args(CMD_SISMEMBER, key, member)
      end

      # Check if multiple members are in a set
      #
      # @param key [String]
      # @param members [Array<String>]
      # @return [Array<Integer>] 1 or 0 for each member
      def smismember(key, *members)
        call(CMD_SMISMEMBER, key, *members)
      end

      # Get all members of a set
      #
      # @param key [String]
      # @return [Array<String>] members
      def smembers(key)
        call_1arg(CMD_SMEMBERS, key)
      end

      # Get the number of members in a set
      #
      # @param key [String]
      # @return [Integer] cardinality
      def scard(key)
        call_1arg(CMD_SCARD, key)
      end

      # Remove and return a random member from a set
      #
      # @param key [String]
      # @param count [Integer, nil] number of members to pop
      # @return [String, Array, nil] member(s) or nil
      def spop(key, count = nil)
        if count
          call_2args(CMD_SPOP, key, count)
        else
          call_1arg(CMD_SPOP, key)
        end
      end

      # Get a random member from a set
      #
      # @param key [String]
      # @param count [Integer, nil] number of members to return
      # @return [String, Array, nil] member(s) or nil
      def srandmember(key, count = nil)
        if count
          call_2args(CMD_SRANDMEMBER, key, count)
        else
          call_1arg(CMD_SRANDMEMBER, key)
        end
      end

      # Move a member from one set to another
      #
      # @param source [String]
      # @param destination [String]
      # @param member [String]
      # @return [Integer] 1 if moved, 0 if not in source
      def smove(source, destination, member)
        call_3args(CMD_SMOVE, source, destination, member)
      end

      # Get the intersection of multiple sets
      #
      # @param keys [Array<String>]
      # @return [Array<String>] members in all sets
      def sinter(*keys)
        call(CMD_SINTER, *keys)
      end

      # Get the intersection and store in a new set
      #
      # @param destination [String]
      # @param keys [Array<String>]
      # @return [Integer] number of members in result
      def sinterstore(destination, *keys)
        call(CMD_SINTERSTORE, destination, *keys)
      end

      # Get the cardinality of the intersection
      #
      # @param keys [Array<String>]
      # @param limit [Integer, nil] stop counting after this many
      # @return [Integer] cardinality of intersection
      def sintercard(*keys, limit: nil)
        args = [CMD_SINTERCARD, keys.length, *keys]
        args.push(OPT_LIMIT, limit) if limit
        call(*args)
      end

      # Get the union of multiple sets
      #
      # @param keys [Array<String>]
      # @return [Array<String>] members in any set
      def sunion(*keys)
        call(CMD_SUNION, *keys)
      end

      # Get the union and store in a new set
      #
      # @param destination [String]
      # @param keys [Array<String>]
      # @return [Integer] number of members in result
      def sunionstore(destination, *keys)
        call(CMD_SUNIONSTORE, destination, *keys)
      end

      # Get the difference between sets
      #
      # @param keys [Array<String>]
      # @return [Array<String>] members in first set but not others
      def sdiff(*keys)
        call(CMD_SDIFF, *keys)
      end

      # Get the difference and store in a new set
      #
      # @param destination [String]
      # @param keys [Array<String>]
      # @return [Integer] number of members in result
      def sdiffstore(destination, *keys)
        call(CMD_SDIFFSTORE, destination, *keys)
      end

      # Incrementally iterate set members
      #
      # @param key [String]
      # @param cursor [Integer] cursor position (0 to start)
      # @param match [String, nil] pattern to match
      # @param count [Integer, nil] hint for number of elements
      # @return [Array] [next_cursor, members]
      def sscan(key, cursor, match: nil, count: nil)
        # Fast path: no options
        return call_2args(CMD_SSCAN, key, cursor) if match.nil? && count.nil?

        args = [CMD_SSCAN, key, cursor]
        args.push(OPT_MATCH, match) if match
        args.push(OPT_COUNT, count) if count
        call(*args)
      end

      # Iterate over set members
      #
      # Returns an Enumerator that handles cursor management automatically.
      #
      # @param key [String] set key
      # @param match [String] pattern to match members (default: "*")
      # @param count [Integer] hint for number of elements per iteration
      # @return [Enumerator] yields each member
      # @example
      #   client.sscan_iter("myset").each { |member| puts member }
      #   client.sscan_iter("myset", match: "user:*").to_a
      def sscan_iter(key, match: "*", count: 10)
        Enumerator.new do |yielder|
          cursor = "0"
          loop do
            cursor, members = sscan(key, cursor, match: match, count: count)
            members.each { |member| yielder << member }
            break if cursor == "0"
          end
        end
      end
    end
  end
end
