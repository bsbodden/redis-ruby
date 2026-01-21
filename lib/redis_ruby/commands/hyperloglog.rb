# frozen_string_literal: true

module RedisRuby
  module Commands
    # HyperLogLog commands for probabilistic cardinality estimation
    #
    # HyperLogLog is a probabilistic data structure that estimates
    # the cardinality (number of unique elements) of a set using
    # only ~12KB of memory regardless of the set size.
    #
    # Standard error is 0.81%, meaning estimates are within 0.81%
    # of the actual cardinality with high probability.
    #
    # @example Basic usage
    #   redis.pfadd("visitors", "user1", "user2", "user3")
    #   redis.pfcount("visitors")  # => 3
    #
    # @see https://redis.io/commands/?group=hyperloglog
    module HyperLogLog
      # Add elements to a HyperLogLog data structure
      #
      # @param key [String] Key name
      # @param elements [Array<String>] Elements to add
      # @return [Integer] 1 if internal state was altered, 0 otherwise
      #
      # @example Add single element
      #   redis.pfadd("hll", "element1")
      #   # => 1
      #
      # @example Add multiple elements
      #   redis.pfadd("hll", "a", "b", "c")
      #   # => 1
      def pfadd(key, *elements)
        call("PFADD", key, *elements)
      end

      # Get the approximate cardinality of set(s)
      #
      # When called with a single key, returns the approximate cardinality.
      # When called with multiple keys, returns the approximate cardinality
      # of the union of all sets.
      #
      # @param keys [Array<String>] Key name(s)
      # @return [Integer] Approximate number of unique elements
      #
      # @example Single key
      #   redis.pfadd("hll", "a", "b", "c")
      #   redis.pfcount("hll")
      #   # => 3
      #
      # @example Multiple keys (union)
      #   redis.pfadd("hll1", "a", "b")
      #   redis.pfadd("hll2", "b", "c")
      #   redis.pfcount("hll1", "hll2")
      #   # => 3 (unique: a, b, c)
      def pfcount(*keys)
        call("PFCOUNT", *keys)
      end

      # Merge multiple HyperLogLog structures into one
      #
      # Creates a merged HyperLogLog at the destination key that
      # represents the union of all source HyperLogLogs.
      #
      # @param destkey [String] Destination key
      # @param sourcekeys [Array<String>] Source keys to merge
      # @return [String] "OK"
      #
      # @example
      #   redis.pfadd("hll1", "a", "b")
      #   redis.pfadd("hll2", "b", "c")
      #   redis.pfmerge("merged", "hll1", "hll2")
      #   redis.pfcount("merged")
      #   # => 3
      def pfmerge(destkey, *sourcekeys)
        call("PFMERGE", destkey, *sourcekeys)
      end
    end
  end
end
