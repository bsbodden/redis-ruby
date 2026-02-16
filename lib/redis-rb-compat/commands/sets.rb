# frozen_string_literal: true

class Redis
  module Commands
    # Set command compatibility methods for redis-rb
    module Sets
      # Add member(s) to a set, returning boolean for single member
      #
      # redis-rb's sadd? returns true if at least one member was added
      # (vs sadd which returns the count)
      #
      # @param key [String] set key
      # @param members [Array<String>] members to add
      # @return [Boolean] true if at least one member was added
      def sadd?(key, *members)
        members = members.flatten
        sadd(key, *members).positive?
      end

      # Remove member(s) from a set, returning boolean for single member
      #
      # redis-rb's srem? returns true if at least one member was removed
      #
      # @param key [String] set key
      # @param members [Array<String>] members to remove
      # @return [Boolean] true if at least one member was removed
      def srem?(key, *members)
        members = members.flatten
        srem(key, *members).positive?
      end

      # Check if member exists in set, returns boolean
      #
      # redis-rb's sismember returns boolean, redis-ruby returns 0/1
      #
      # @param key [String] set key
      # @param member [String] member to check
      # @return [Boolean] true if member exists
      def sismember?(key, member)
        sismember(key, member) == 1
      end

      # Move member between sets, returns boolean
      #
      # @param source [String] source set key
      # @param destination [String] destination set key
      # @param member [String] member to move
      # @return [Boolean] true if member was moved
      def smove?(source, destination, member)
        smove(source, destination, member) == 1
      end
    end
  end
end
