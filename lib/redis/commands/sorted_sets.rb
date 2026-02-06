# frozen_string_literal: true

class Redis
  module Commands
    # Sorted Set command compatibility methods for redis-rb
    module SortedSets
      # Increment by float, ensuring Float return (redis-rb always returns Float)
      #
      # @param key [String] sorted set key
      # @param increment [Numeric] amount to increment
      # @param member [String] member to increment
      # @return [Float] new score
      def zincrby_compat(key, increment, member)
        result = zincrby(key, increment, member)
        result.is_a?(String) ? result.to_f : result
      end

      # Get scores of multiple members, ensuring Float return
      #
      # @param key [String] sorted set key
      # @param members [Array<String>] members to get scores for
      # @return [Array<Float, nil>] scores as floats
      def zmscore_compat(key, *members)
        result = zmscore(key, *members)
        result.map { |s| s&.to_f }
      end

      # Scan iterator that yields [member, score] pairs (redis-rb compatibility)
      #
      # redis-rb calls this zscan_each, redis-ruby uses zscan_iter
      #
      # @param key [String] sorted set key
      # @param match [String] pattern to match
      # @param count [Integer] hint for number of elements
      # @return [Enumerator] yields [member, score] pairs
      def zscan_each(key, match: "*", count: 10, &block)
        enum = zscan_iter(key, match: match, count: count)
        block ? enum.each(&block) : enum
      end
    end
  end
end
