# frozen_string_literal: true

module RedisRuby
  module Commands
    # List commands
    #
    # @see https://redis.io/commands/?group=list
    module Lists
      # Prepend one or more values to a list
      #
      # @param key [String]
      # @param values [Array<String>]
      # @return [Integer] length of list after push
      def lpush(key, *values)
        call("LPUSH", key, *values)
      end

      # Prepend a value to a list, only if the list exists
      #
      # @param key [String]
      # @param values [Array<String>]
      # @return [Integer] length of list after push, or 0 if key doesn't exist
      def lpushx(key, *values)
        call("LPUSHX", key, *values)
      end

      # Append one or more values to a list
      #
      # @param key [String]
      # @param values [Array<String>]
      # @return [Integer] length of list after push
      def rpush(key, *values)
        call("RPUSH", key, *values)
      end

      # Append a value to a list, only if the list exists
      #
      # @param key [String]
      # @param values [Array<String>]
      # @return [Integer] length of list after push, or 0 if key doesn't exist
      def rpushx(key, *values)
        call("RPUSHX", key, *values)
      end

      # Remove and get the first element of a list
      #
      # @param key [String]
      # @param count [Integer, nil] number of elements to pop
      # @return [String, Array, nil] popped element(s) or nil
      def lpop(key, count = nil)
        if count
          call("LPOP", key, count)
        else
          call("LPOP", key)
        end
      end

      # Remove and get the last element of a list
      #
      # @param key [String]
      # @param count [Integer, nil] number of elements to pop
      # @return [String, Array, nil] popped element(s) or nil
      def rpop(key, count = nil)
        if count
          call("RPOP", key, count)
        else
          call("RPOP", key)
        end
      end

      # Get a range of elements from a list
      #
      # @param key [String]
      # @param start [Integer] start index (0-based)
      # @param stop [Integer] stop index (inclusive, -1 for last)
      # @return [Array<String>] elements in range
      def lrange(key, start, stop)
        call("LRANGE", key, start, stop)
      end

      # Get the length of a list
      #
      # @param key [String]
      # @return [Integer] length
      def llen(key)
        call("LLEN", key)
      end

      # Get an element from a list by its index
      #
      # @param key [String]
      # @param index [Integer] index (0-based, negative from end)
      # @return [String, nil] element or nil
      def lindex(key, index)
        call("LINDEX", key, index)
      end

      # Set the value of an element in a list by its index
      #
      # @param key [String]
      # @param index [Integer]
      # @param value [String]
      # @return [String] "OK"
      def lset(key, index, value)
        call("LSET", key, index, value)
      end

      # Insert an element before or after another element
      #
      # @param key [String]
      # @param position [:before, :after] where to insert
      # @param pivot [String] reference element
      # @param value [String] element to insert
      # @return [Integer] length of list, or -1 if pivot not found
      def linsert(key, position, pivot, value)
        call("LINSERT", key, position.to_s.upcase, pivot, value)
      end

      # Remove elements from a list
      #
      # @param key [String]
      # @param count [Integer] number of occurrences to remove (0=all, >0=head, <0=tail)
      # @param value [String] element to remove
      # @return [Integer] number of removed elements
      def lrem(key, count, value)
        call("LREM", key, count, value)
      end

      # Trim a list to the specified range
      #
      # @param key [String]
      # @param start [Integer] start index
      # @param stop [Integer] stop index
      # @return [String] "OK"
      def ltrim(key, start, stop)
        call("LTRIM", key, start, stop)
      end

      # Remove the last element and prepend it to another list
      #
      # @param source [String]
      # @param destination [String]
      # @return [String, nil] moved element or nil
      def rpoplpush(source, destination)
        call("RPOPLPUSH", source, destination)
      end

      # Pop an element from a list, push it to another list and return it
      #
      # @param source [String]
      # @param destination [String]
      # @param wherefrom [:left, :right]
      # @param whereto [:left, :right]
      # @return [String, nil] moved element or nil
      def lmove(source, destination, wherefrom, whereto)
        call("LMOVE", source, destination, wherefrom.to_s.upcase, whereto.to_s.upcase)
      end

      # Pop elements from multiple lists (Redis 7.0+)
      #
      # @param keys [Array<String>] keys to pop from
      # @param direction [:left, :right] which end to pop from
      # @param count [Integer, nil] number of elements to pop
      # @return [Array, nil] [key, [elements]] or nil if all lists are empty
      #
      # @example Pop one element from the left
      #   redis.lmpop("list1", "list2", direction: :left)
      #   # => ["list1", ["element"]]
      #
      # @example Pop multiple elements
      #   redis.lmpop("list1", "list2", direction: :right, count: 3)
      #   # => ["list1", ["e1", "e2", "e3"]]
      def lmpop(*keys, direction: :left, count: nil)
        args = ["LMPOP", keys.length, *keys, direction.to_s.upcase]
        args.push("COUNT", count) if count
        call(*args)
      end

      # Blocking pop from multiple lists (Redis 7.0+)
      #
      # @param keys [Array<String>] keys to pop from
      # @param direction [:left, :right] which end to pop from
      # @param timeout [Numeric] timeout in seconds (0 = block forever)
      # @param count [Integer, nil] number of elements to pop
      # @return [Array, nil] [key, [elements]] or nil on timeout
      def blmpop(timeout, *keys, direction: :left, count: nil)
        args = ["BLMPOP", timeout, keys.length, *keys, direction.to_s.upcase]
        args.push("COUNT", count) if count
        call(*args)
      end

      # Return the index of matching elements
      #
      # @param key [String]
      # @param element [String]
      # @param rank [Integer, nil] rank of match to return
      # @param count [Integer, nil] number of matches to return
      # @param maxlen [Integer, nil] limit comparisons
      # @return [Integer, Array, nil] index, indices, or nil
      def lpos(key, element, rank: nil, count: nil, maxlen: nil)
        args = ["LPOS", key, element]
        args.push("RANK", rank) if rank
        args.push("COUNT", count) if count
        args.push("MAXLEN", maxlen) if maxlen
        call(*args)
      end

      # Blocking pop from the left of one or more lists
      #
      # @param keys [Array<String>] keys to pop from
      # @param timeout [Numeric] timeout in seconds (0 = block forever)
      # @return [Array, nil] [key, element] or nil on timeout
      def blpop(*keys, timeout: 0)
        call("BLPOP", *keys, timeout)
      end

      # Blocking pop from the right of one or more lists
      #
      # @param keys [Array<String>] keys to pop from
      # @param timeout [Numeric] timeout in seconds (0 = block forever)
      # @return [Array, nil] [key, element] or nil on timeout
      def brpop(*keys, timeout: 0)
        call("BRPOP", *keys, timeout)
      end

      # Blocking RPOPLPUSH
      #
      # @param source [String]
      # @param destination [String]
      # @param timeout [Numeric] timeout in seconds
      # @return [String, nil] element or nil on timeout
      def brpoplpush(source, destination, timeout: 0)
        call("BRPOPLPUSH", source, destination, timeout)
      end

      # Blocking LMOVE
      #
      # @param source [String]
      # @param destination [String]
      # @param wherefrom [:left, :right]
      # @param whereto [:left, :right]
      # @param timeout [Numeric] timeout in seconds
      # @return [String, nil] element or nil on timeout
      def blmove(source, destination, wherefrom, whereto, timeout: 0)
        call("BLMOVE", source, destination,
             wherefrom.to_s.upcase, whereto.to_s.upcase, timeout)
      end
    end
  end
end
