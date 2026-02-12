# frozen_string_literal: true

require_relative "../dsl/hyperloglog_proxy"

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
      # ============================================================
      # Idiomatic Ruby API
      # ============================================================

      # Create a HyperLogLog proxy for idiomatic operations
      #
      # Provides a fluent, chainable interface for working with HyperLogLog
      # data structures. HyperLogLog is a probabilistic data structure that
      # estimates cardinality (unique element count) using ~12KB of memory
      # regardless of the set size, with ~0.81% standard error.
      #
      # @param key_parts [Array<String, Symbol, Integer>] Key components (joined with ":")
      # @return [RedisRuby::DSL::HyperLogLogProxy] Chainable proxy object
      #
      # @example Basic usage
      #   visitors = redis.hyperloglog(:visitors, :today)
      #   visitors.add("user:123", "user:456")
      #   puts "Unique visitors: #{visitors.count}"
      #
      # @example Merging HyperLogLogs
      #   weekly = redis.hll(:visitors, :weekly)
      #   weekly.merge("visitors:day1", "visitors:day2", "visitors:day3")
      #
      # @see RedisRuby::DSL::HyperLogLogProxy
      def hyperloglog(*key_parts)
        DSL::HyperLogLogProxy.new(self, *key_parts)
      end

      # Alias for {#hyperloglog}
      #
      # @see #hyperloglog
      alias hll hyperloglog

      # ============================================================
      # Low-Level Commands
      # ============================================================

      # Frozen command constants to avoid string allocations
      CMD_PFADD = "PFADD"
      CMD_PFCOUNT = "PFCOUNT"
      CMD_PFMERGE = "PFMERGE"

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
        # Fast path for single element (most common)
        return call_2args(CMD_PFADD, key, elements[0]) if elements.size == 1

        call(CMD_PFADD, key, *elements)
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
        # Fast path for single key (most common)
        return call_1arg(CMD_PFCOUNT, keys[0]) if keys.size == 1

        call(CMD_PFCOUNT, *keys)
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
        # Fast path for single source key
        return call_2args(CMD_PFMERGE, destkey, sourcekeys[0]) if sourcekeys.size == 1

        call(CMD_PFMERGE, destkey, *sourcekeys)
      end
    end
  end
end
