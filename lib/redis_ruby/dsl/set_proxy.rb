# frozen_string_literal: true

require_relative "expirable"

module RR
  module DSL
    # Chainable proxy for Redis Set operations
    #
    # Provides a fluent, idiomatic Ruby API for working with Redis sets,
    # making them feel like native Ruby Set objects while maintaining
    # the power of Redis operations.
    #
    # @example Tag management
    #   tags = redis.set(:post, 123, :tags)
    #   tags.add("ruby", "redis", "tutorial")
    #   tags.member?("ruby")  # => true
    #
    # @example Set operations
    #   common = tags.intersect("post:456:tags")
    #   all = tags.union("post:456:tags", "post:789:tags")
    #
    # @example Random selection
    #   winner = redis.set(:contest, :participants).pop
    #
    class SetProxy
      include Expirable

      attr_reader :key

      # @private
      def initialize(redis, *key_parts)
        @redis = redis
        @key = build_key(*key_parts)
      end

      # Add one or more members to the set
      #
      # @param members [Array<String, Symbol>] Members to add
      # @return [self] For method chaining
      #
      # @example
      #   set.add("ruby", "redis", "database")
      #   set.add(:tag1, :tag2)
      def add(*members)
        return self if members.empty?

        @redis.sadd(@key, *members.map(&:to_s))
        self
      end

      # Alias for add (Ruby Set compatibility)
      alias << add

      # Remove one or more members from the set
      #
      # @param members [Array<String, Symbol>] Members to remove
      # @return [self] For method chaining
      #
      # @example
      #   set.remove("old_tag")
      #   set.remove(:tag1, :tag2, :tag3)
      def remove(*members)
        return self if members.empty?

        @redis.srem(@key, *members.map(&:to_s))
        self
      end

      # Alias for remove
      alias delete remove

      # Check if a member exists in the set
      #
      # @param member [String, Symbol] Member to check
      # @return [Boolean] true if member exists
      #
      # @example
      #   set.member?("ruby")  # => true
      #   set.member?(:redis)  # => true
      def member?(member)
        @redis.sismember(@key, member.to_s) == 1
      end

      # Alias for member? (Ruby Set compatibility)
      alias include? member?

      # Get all members of the set
      #
      # @return [Array<String>] Array of members
      #
      # @example
      #   set.members  # => ["ruby", "redis", "database"]
      def members
        @redis.smembers(@key) || []
      end

      # Alias for members
      alias to_a members

      # Get the number of members in the set
      #
      # @return [Integer] Number of members
      #
      # @example
      #   set.size  # => 3
      def size
        @redis.scard(@key)
      end

      # Aliases for size (Ruby Set compatibility)
      alias length size
      alias count size

      # Check if the set is empty
      #
      # @return [Boolean] true if set has no members
      #
      # @example
      #   set.empty?  # => false
      def empty?
        size.zero?
      end

      # Check if the set key exists
      #
      # @return [Boolean] true if key exists
      #
      # @example
      #   set.exists?  # => true
      def exists?
        @redis.exists(@key).positive?
      end

      # Get the union of this set with other sets
      #
      # @param other_keys [Array<String, Symbol>] Other set keys
      # @return [Array<String>] Members in any of the sets
      #
      # @example
      #   set.union(:other_set1, :other_set2)
      def union(*other_keys)
        return members if other_keys.empty?

        @redis.sunion(@key, *other_keys.map(&:to_s))
      end

      # Get the intersection of this set with other sets
      #
      # @param other_keys [Array<String, Symbol>] Other set keys
      # @return [Array<String>] Members in all sets
      #
      # @example
      #   set.intersect(:other_set1, :other_set2)
      def intersect(*other_keys)
        return members if other_keys.empty?

        @redis.sinter(@key, *other_keys.map(&:to_s))
      end

      # Get the difference between this set and other sets
      #
      # @param other_keys [Array<String, Symbol>] Other set keys
      # @return [Array<String>] Members in this set but not in others
      #
      # @example
      #   set.difference(:other_set1, :other_set2)
      def difference(*other_keys)
        return members if other_keys.empty?

        @redis.sdiff(@key, *other_keys.map(&:to_s))
      end

      # Get random member(s) from the set without removing
      #
      # @param count [Integer, nil] Number of members to return
      # @return [String, Array, nil] Random member(s) or nil
      #
      # @example
      #   set.random       # => "ruby"
      #   set.random(3)    # => ["ruby", "redis", "database"]
      def random(count = nil)
        @redis.srandmember(@key, count)
      end

      # Remove and return random member(s) from the set
      #
      # @param count [Integer, nil] Number of members to pop
      # @return [String, Array, nil] Popped member(s) or nil
      #
      # @example
      #   set.pop       # => "ruby"
      #   set.pop(2)    # => ["redis", "database"]
      def pop(count = nil)
        @redis.spop(@key, count)
      end

      # Remove all members from the set
      #
      # @return [Integer] Number of keys deleted (0 or 1)
      #
      # @example
      #   set.clear
      def clear
        @redis.del(@key)
      end

      # Iterate over all members
      #
      # @yield [member] Yields each member
      # @return [self, Enumerator] self if block given, Enumerator otherwise
      #
      # @example
      #   set.each { |member| puts member }
      def each(&)
        return enum_for(:each) unless block_given?

        members.each(&)
        self
      end

      # Alias for each
      alias each_member each

      private

      # Build composite key from parts
      #
      # @param parts [Array] Key components
      # @return [String] Joined key
      def build_key(*parts)
        parts.map(&:to_s).join(":")
      end
    end
  end
end
