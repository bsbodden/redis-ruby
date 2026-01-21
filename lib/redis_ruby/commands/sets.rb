# frozen_string_literal: true

module RedisRuby
  module Commands
    # Set commands
    #
    # @see https://redis.io/commands/?group=set
    module Sets
      # Add one or more members to a set
      #
      # @param key [String]
      # @param members [Array<String>]
      # @return [Integer] number of members added (not already present)
      def sadd(key, *members)
        call("SADD", key, *members)
      end

      # Remove one or more members from a set
      #
      # @param key [String]
      # @param members [Array<String>]
      # @return [Integer] number of members removed
      def srem(key, *members)
        call("SREM", key, *members)
      end

      # Check if a member is in a set
      #
      # @param key [String]
      # @param member [String]
      # @return [Integer] 1 if member exists, 0 otherwise
      def sismember(key, member)
        call("SISMEMBER", key, member)
      end

      # Check if multiple members are in a set
      #
      # @param key [String]
      # @param members [Array<String>]
      # @return [Array<Integer>] 1 or 0 for each member
      def smismember(key, *members)
        call("SMISMEMBER", key, *members)
      end

      # Get all members of a set
      #
      # @param key [String]
      # @return [Array<String>] members
      def smembers(key)
        call("SMEMBERS", key)
      end

      # Get the number of members in a set
      #
      # @param key [String]
      # @return [Integer] cardinality
      def scard(key)
        call("SCARD", key)
      end

      # Remove and return a random member from a set
      #
      # @param key [String]
      # @param count [Integer, nil] number of members to pop
      # @return [String, Array, nil] member(s) or nil
      def spop(key, count = nil)
        if count
          call("SPOP", key, count)
        else
          call("SPOP", key)
        end
      end

      # Get a random member from a set
      #
      # @param key [String]
      # @param count [Integer, nil] number of members to return
      # @return [String, Array, nil] member(s) or nil
      def srandmember(key, count = nil)
        if count
          call("SRANDMEMBER", key, count)
        else
          call("SRANDMEMBER", key)
        end
      end

      # Move a member from one set to another
      #
      # @param source [String]
      # @param destination [String]
      # @param member [String]
      # @return [Integer] 1 if moved, 0 if not in source
      def smove(source, destination, member)
        call("SMOVE", source, destination, member)
      end

      # Get the intersection of multiple sets
      #
      # @param keys [Array<String>]
      # @return [Array<String>] members in all sets
      def sinter(*keys)
        call("SINTER", *keys)
      end

      # Get the intersection and store in a new set
      #
      # @param destination [String]
      # @param keys [Array<String>]
      # @return [Integer] number of members in result
      def sinterstore(destination, *keys)
        call("SINTERSTORE", destination, *keys)
      end

      # Get the cardinality of the intersection
      #
      # @param keys [Array<String>]
      # @param limit [Integer, nil] stop counting after this many
      # @return [Integer] cardinality of intersection
      def sintercard(*keys, limit: nil)
        args = ["SINTERCARD", keys.length, *keys]
        args.push("LIMIT", limit) if limit
        call(*args)
      end

      # Get the union of multiple sets
      #
      # @param keys [Array<String>]
      # @return [Array<String>] members in any set
      def sunion(*keys)
        call("SUNION", *keys)
      end

      # Get the union and store in a new set
      #
      # @param destination [String]
      # @param keys [Array<String>]
      # @return [Integer] number of members in result
      def sunionstore(destination, *keys)
        call("SUNIONSTORE", destination, *keys)
      end

      # Get the difference between sets
      #
      # @param keys [Array<String>]
      # @return [Array<String>] members in first set but not others
      def sdiff(*keys)
        call("SDIFF", *keys)
      end

      # Get the difference and store in a new set
      #
      # @param destination [String]
      # @param keys [Array<String>]
      # @return [Integer] number of members in result
      def sdiffstore(destination, *keys)
        call("SDIFFSTORE", destination, *keys)
      end

      # Incrementally iterate set members
      #
      # @param key [String]
      # @param cursor [Integer] cursor position (0 to start)
      # @param match [String, nil] pattern to match
      # @param count [Integer, nil] hint for number of elements
      # @return [Array] [next_cursor, members]
      def sscan(key, cursor, match: nil, count: nil)
        args = ["SSCAN", key, cursor]
        args.push("MATCH", match) if match
        args.push("COUNT", count) if count
        call(*args)
      end
    end
  end
end
