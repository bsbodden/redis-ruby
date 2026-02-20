# frozen_string_literal: true

require_relative "../dsl/list_proxy"

module RR
  module Commands
    # List commands
    #
    # @see https://redis.io/commands/?group=list
    module Lists
      # ============================================================
      # Idiomatic Ruby API
      # ============================================================

      # Create a list proxy for idiomatic array-like operations
      #
      # @param key_parts [Array<String, Symbol, Integer>] Key components to join with ':'
      # @return [RR::DSL::ListProxy] List proxy instance
      #
      # @example Queue operations (FIFO)
      #   queue = redis.list(:jobs)
      #   queue.push("job1", "job2")
      #   job = queue.shift  # FIFO
      #
      # @example Stack operations (LIFO)
      #   stack = redis.list(:undo)
      #   stack.push("action1")
      #   action = stack.pop  # LIFO
      #
      # @example Array-like access
      #   list = redis.list(:items)
      #   list << "item1"
      #   list[0]  # => "item1"
      def list(*key_parts)
        DSL::ListProxy.new(self, *key_parts)
      end

      # ============================================================
      # Low-Level Commands
      # ============================================================
      # Frozen command constants to avoid string allocations
      CMD_LPUSH = "LPUSH"
      CMD_LPUSHX = "LPUSHX"
      CMD_RPUSH = "RPUSH"
      CMD_RPUSHX = "RPUSHX"
      CMD_LPOP = "LPOP"
      CMD_RPOP = "RPOP"
      CMD_LRANGE = "LRANGE"
      CMD_LLEN = "LLEN"
      CMD_LINDEX = "LINDEX"
      CMD_LSET = "LSET"
      CMD_LINSERT = "LINSERT"
      CMD_LREM = "LREM"
      CMD_LTRIM = "LTRIM"
      CMD_RPOPLPUSH = "RPOPLPUSH"
      CMD_LMOVE = "LMOVE"
      CMD_LMPOP = "LMPOP"
      CMD_BLMPOP = "BLMPOP"
      CMD_LPOS = "LPOS"
      CMD_BLPOP = "BLPOP"
      CMD_BRPOP = "BRPOP"
      CMD_BRPOPLPUSH = "BRPOPLPUSH"
      CMD_BLMOVE = "BLMOVE"

      # Prepend one or more values to a list
      #
      # @param key [String]
      # @param values [Array<String>]
      # @return [Integer] length of list after push
      def lpush(key, *values)
        return 0 if values.empty?

        # Fast path for single value (most common)
        return call_2args(CMD_LPUSH, key, values[0]) if values.size == 1

        call(CMD_LPUSH, key, *values)
      end

      # Prepend a value to a list, only if the list exists
      #
      # @param key [String]
      # @param values [Array<String>]
      # @return [Integer] length of list after push, or 0 if key doesn't exist
      def lpushx(key, *values)
        return 0 if values.empty?

        # Fast path for single value
        return call_2args(CMD_LPUSHX, key, values[0]) if values.size == 1

        call(CMD_LPUSHX, key, *values)
      end

      # Append one or more values to a list
      #
      # @param key [String]
      # @param values [Array<String>]
      # @return [Integer] length of list after push
      def rpush(key, *values)
        return 0 if values.empty?

        # Fast path for single value (most common)
        return call_2args(CMD_RPUSH, key, values[0]) if values.size == 1

        call(CMD_RPUSH, key, *values)
      end

      # Append a value to a list, only if the list exists
      #
      # @param key [String]
      # @param values [Array<String>]
      # @return [Integer] length of list after push, or 0 if key doesn't exist
      def rpushx(key, *values)
        return 0 if values.empty?

        # Fast path for single value
        return call_2args(CMD_RPUSHX, key, values[0]) if values.size == 1

        call(CMD_RPUSHX, key, *values)
      end

      # Remove and get the first element of a list
      #
      # @param key [String]
      # @param count [Integer, nil] number of elements to pop
      # @return [String, Array, nil] popped element(s) or nil
      def lpop(key, count = nil)
        if count
          call_2args(CMD_LPOP, key, count)
        else
          call_1arg(CMD_LPOP, key)
        end
      end

      # Remove and get the last element of a list
      #
      # @param key [String]
      # @param count [Integer, nil] number of elements to pop
      # @return [String, Array, nil] popped element(s) or nil
      def rpop(key, count = nil)
        if count
          call_2args(CMD_RPOP, key, count)
        else
          call_1arg(CMD_RPOP, key)
        end
      end

      # Get a range of elements from a list
      #
      # @param key [String]
      # @param start [Integer] start index (0-based)
      # @param stop [Integer] stop index (inclusive, -1 for last)
      # @return [Array<String>] elements in range
      def lrange(key, start, stop)
        call_3args(CMD_LRANGE, key, start, stop)
      end

      # Get the length of a list
      #
      # @param key [String]
      # @return [Integer] length
      def llen(key)
        call_1arg(CMD_LLEN, key)
      end

      # Get an element from a list by its index
      #
      # @param key [String]
      # @param index [Integer] index (0-based, negative from end)
      # @return [String, nil] element or nil
      def lindex(key, index)
        call_2args(CMD_LINDEX, key, index)
      end

      # Set the value of an element in a list by its index
      #
      # @param key [String]
      # @param index [Integer]
      # @param value [String]
      # @return [String] "OK"
      def lset(key, index, value)
        call_3args(CMD_LSET, key, index, value)
      end

      # Insert an element before or after another element
      #
      # @param key [String]
      # @param position [:before, :after] where to insert
      # @param pivot [String] reference element
      # @param value [String] element to insert
      # @return [Integer] length of list, or -1 if pivot not found
      def linsert(key, position, pivot, value)
        call(CMD_LINSERT, key, position.to_s.upcase, pivot, value)
      end

      # Remove elements from a list
      #
      # @param key [String]
      # @param count [Integer] number of occurrences to remove (0=all, >0=head, <0=tail)
      # @param value [String] element to remove
      # @return [Integer] number of removed elements
      def lrem(key, count, value)
        call_3args(CMD_LREM, key, count, value)
      end

      # Trim a list to the specified range
      #
      # @param key [String]
      # @param start [Integer] start index
      # @param stop [Integer] stop index
      # @return [String] "OK"
      def ltrim(key, start, stop)
        call_3args(CMD_LTRIM, key, start, stop)
      end

      # Remove the last element and prepend it to another list
      #
      # @param source [String]
      # @param destination [String]
      # @return [String, nil] moved element or nil
      def rpoplpush(source, destination)
        call_2args(CMD_RPOPLPUSH, source, destination)
      end

      # Pop an element from a list, push it to another list and return it
      #
      # @param source [String]
      # @param destination [String]
      # @param wherefrom [:left, :right]
      # @param whereto [:left, :right]
      # @return [String, nil] moved element or nil
      def lmove(source, destination, wherefrom, whereto)
        call(CMD_LMOVE, source, destination, wherefrom.to_s.upcase, whereto.to_s.upcase)
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
        args = [CMD_LMPOP, keys.length, *keys, direction.to_s.upcase]
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
        args = [CMD_BLMPOP, timeout, keys.length, *keys, direction.to_s.upcase]
        args.push("COUNT", count) if count
        blocking_call(timeout, *args)
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
        # Fast path: no options
        return call_2args(CMD_LPOS, key, element) if rank.nil? && count.nil? && maxlen.nil?

        args = [CMD_LPOS, key, element]
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
        blocking_call(timeout, CMD_BLPOP, *keys, timeout)
      end

      # Blocking pop from the right of one or more lists
      #
      # @param keys [Array<String>] keys to pop from
      # @param timeout [Numeric] timeout in seconds (0 = block forever)
      # @return [Array, nil] [key, element] or nil on timeout
      def brpop(*keys, timeout: 0)
        blocking_call(timeout, CMD_BRPOP, *keys, timeout)
      end

      # Blocking RPOPLPUSH
      #
      # @param source [String]
      # @param destination [String]
      # @param timeout [Numeric] timeout in seconds
      # @return [String, nil] element or nil on timeout
      def brpoplpush(source, destination, timeout: 0)
        blocking_call(timeout, CMD_BRPOPLPUSH, source, destination, timeout)
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
        blocking_call(timeout, CMD_BLMOVE, source, destination,
                      wherefrom.to_s.upcase, whereto.to_s.upcase, timeout)
      end
    end
  end
end
