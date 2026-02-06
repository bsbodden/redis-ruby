# frozen_string_literal: true

require_relative "commands/strings"
require_relative "commands/hashes"
require_relative "commands/sets"
require_relative "commands/keys"
require_relative "commands/sorted_sets"

class Redis
  # Command compatibility methods
  #
  # This module is included in the Redis class to provide
  # redis-rb compatible method signatures and return values.
  module Commands
    include Strings
    include Hashes
    include Sets
    include Keys
    include SortedSets

    # Additional compatibility methods that span multiple categories

    # Scan iterators for hash (redis-rb compatibility)
    def hscan_each(key, match: "*", count: 10, &block)
      enum = hscan_iter(key, match: match, count: count)
      block ? enum.each(&block) : enum
    end

    # Scan iterators for set (redis-rb compatibility)
    def sscan_each(key, match: "*", count: 10, &block)
      enum = sscan_iter(key, match: match, count: count)
      block ? enum.each(&block) : enum
    end
  end
end
