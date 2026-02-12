# frozen_string_literal: true

module RedisRuby
  module DSL
    # Idiomatic Ruby interface for Redis Lists
    #
    # Provides array-like operations, queue/stack semantics, and chainable methods
    # for working with Redis lists in a Ruby-esque way.
    #
    # @example Queue operations (FIFO)
    #   queue = redis.list(:jobs)
    #   queue.push("job1", "job2")  # Add to right
    #   job = queue.shift           # Remove from left (FIFO)
    #
    # @example Stack operations (LIFO)
    #   stack = redis.list(:undo)
    #   stack.push("action1")       # Add to right
    #   action = stack.pop          # Remove from right (LIFO)
    #
    # @example Array-like access
    #   list = redis.list(:items)
    #   list << "item1" << "item2"
    #   list[0]                     # => "item1"
    #   list[0..2]                  # => ["item1", "item2", "item3"]
    #   list[0] = "new_value"
    #
    class ListProxy
      # @param redis [RedisRuby::Client] Redis client instance
      # @param key_parts [Array<String, Symbol, Integer>] Key components to join with ':'
      def initialize(redis, *key_parts)
        @redis = redis
        @key = build_key(*key_parts)
      end

      # ============================================================
      # Array-Like Push/Pop Operations (Right Side)
      # ============================================================

      # Append values to the right side of the list (RPUSH)
      #
      # @param values [Array<String, Symbol>] Values to append
      # @return [self] For method chaining
      #
      # @example
      #   list.push("item1", "item2")
      #   list << "item3"
      def push(*values)
        return self if values.empty?
        @redis.rpush(@key, *values.map(&:to_s))
        self
      end
      alias << push
      alias append push

      # Remove and return element(s) from the right side (RPOP)
      #
      # @param count [Integer, nil] Number of elements to pop
      # @return [String, Array, nil] Popped element(s) or nil
      #
      # @example
      #   list.pop       # => "last_item"
      #   list.pop(2)    # => ["item2", "item1"]
      def pop(count = nil)
        @redis.rpop(@key, count)
      end

      # ============================================================
      # Queue/Stack Operations (Left Side)
      # ============================================================

      # Remove and return element(s) from the left side (LPOP)
      #
      # @param count [Integer, nil] Number of elements to pop
      # @return [String, Array, nil] Popped element(s) or nil
      #
      # @example
      #   list.shift     # => "first_item" (FIFO when used with push)
      #   list.shift(2)  # => ["item1", "item2"]
      def shift(count = nil)
        @redis.lpop(@key, count)
      end

      # Prepend values to the left side of the list (LPUSH)
      #
      # @param values [Array<String, Symbol>] Values to prepend
      # @return [self] For method chaining
      #
      # @example
      #   list.unshift("urgent")
      def unshift(*values)
        return self if values.empty?
        @redis.lpush(@key, *values.map(&:to_s))
        self
      end
      alias prepend unshift

      # ============================================================
      # Array-Like Access
      # ============================================================

      # Get element(s) by index or range (LINDEX/LRANGE)
      #
      # @param index_or_range [Integer, Range] Index or range
      # @param count [Integer, nil] Number of elements (when first arg is Integer)
      # @return [String, Array, nil] Element(s) or nil
      #
      # @example
      #   list[0]        # => "first"
      #   list[-1]       # => "last"
      #   list[0..2]     # => ["first", "second", "third"]
      #   list[0, 5]     # => First 5 elements
      def [](index_or_range, count = nil)
        if index_or_range.is_a?(Range)
          start_idx = index_or_range.begin
          end_idx = index_or_range.end
          end_idx -= 1 if index_or_range.exclude_end?
          @redis.lrange(@key, start_idx, end_idx)
        elsif count
          @redis.lrange(@key, index_or_range, index_or_range + count - 1)
        else
          @redis.lindex(@key, index_or_range)
        end
      end

      # Set element at index (LSET)
      #
      # @param index [Integer] Index to set
      # @param value [String, Symbol] Value to set
      # @return [String] "OK"
      #
      # @example
      #   list[0] = "new_value"
      def []=(index, value)
        @redis.lset(@key, index, value.to_s)
      end

      # ============================================================
      # Insertion
      # ============================================================

      # Insert value before pivot element (LINSERT)
      #
      # @param pivot [String, Symbol] Reference element
      # @param value [String, Symbol] Value to insert
      # @return [self] For method chaining
      #
      # @example
      #   list.insert_before("item2", "new_item")
      def insert_before(pivot, value)
        @redis.linsert(@key, :before, pivot.to_s, value.to_s)
        self
      end

      # Insert value after pivot element (LINSERT)
      #
      # @param pivot [String, Symbol] Reference element
      # @param value [String, Symbol] Value to insert
      # @return [self] For method chaining
      #
      # @example
      #   list.insert_after("item1", "new_item")
      def insert_after(pivot, value)
        @redis.linsert(@key, :after, pivot.to_s, value.to_s)
        self
      end

      # ============================================================
      # Removal
      # ============================================================

      # Remove occurrences of value from list (LREM)
      #
      # @param value [String, Symbol] Value to remove
      # @param count [Integer] Number of occurrences (0=all, >0=from head, <0=from tail)
      # @return [Integer] Number of removed elements
      #
      # @example
      #   list.remove("item")           # Remove all occurrences
      #   list.remove("item", count: 1) # Remove first occurrence
      #   list.remove("item", count: -1) # Remove last occurrence
      def remove(value, count: 0)
        @redis.lrem(@key, count, value.to_s)
      end
      alias delete remove

      # ============================================================
      # Trimming
      # ============================================================

      # Trim list to specified range (LTRIM)
      #
      # @param range [Range] Range to keep
      # @return [self] For method chaining
      #
      # @example
      #   list.trim(0..9)   # Keep first 10 elements
      #   list.trim(0..-1)  # Keep all (no-op)
      def trim(range)
        end_idx = range.end
        end_idx -= 1 if range.exclude_end?
        @redis.ltrim(@key, range.begin, end_idx)
        self
      end

      # Keep only first N elements (LTRIM)
      #
      # @param n [Integer] Number of elements to keep
      # @return [self] For method chaining
      #
      # @example
      #   list.keep(100)  # Keep only first 100 elements
      def keep(n)
        @redis.ltrim(@key, 0, n - 1)
        self
      end

      # ============================================================
      # Blocking Operations
      # ============================================================

      # Blocking pop from left side (BLPOP)
      #
      # @param timeout [Integer] Timeout in seconds (0 = wait forever)
      # @return [String, nil] Popped element or nil on timeout
      #
      # @example
      #   item = list.blocking_shift(timeout: 5)
      def blocking_shift(timeout: 0)
        result = @redis.blpop(@key, timeout)
        result&.last  # BLPOP returns [key, value]
      end
      alias blocking_pop blocking_shift

      # Blocking pop from right side (BRPOP)
      #
      # @param timeout [Integer] Timeout in seconds (0 = wait forever)
      # @return [String, nil] Popped element or nil on timeout
      #
      # @example
      #   item = list.blocking_pop_right(timeout: 5)
      def blocking_pop_right(timeout: 0)
        result = @redis.brpop(@key, timeout)
        result&.last  # BRPOP returns [key, value]
      end

      # ============================================================
      # Inspection
      # ============================================================

      # Get length of list (LLEN)
      #
      # @return [Integer] Number of elements
      #
      # @example
      #   list.length  # => 5
      def length
        @redis.llen(@key)
      end
      alias size length
      alias count length

      # Check if list is empty
      #
      # @return [Boolean] true if list has no elements
      #
      # @example
      #   list.empty?  # => false
      def empty?
        length == 0
      end

      # Check if list key exists
      #
      # @return [Boolean] true if key exists
      #
      # @example
      #   list.exists?  # => true
      def exists?
        @redis.exists(@key) > 0
      end

      # ============================================================
      # Conversion
      # ============================================================

      # Get all elements as array (LRANGE)
      #
      # @return [Array<String>] All elements
      #
      # @example
      #   list.to_a  # => ["item1", "item2", "item3"]
      def to_a
        @redis.lrange(@key, 0, -1)
      end

      # Get first element(s) (LINDEX/LRANGE)
      #
      # @param n [Integer, nil] Number of elements (nil = single element)
      # @return [String, Array, nil] First element(s) or nil
      #
      # @example
      #   list.first     # => "item1"
      #   list.first(3)  # => ["item1", "item2", "item3"]
      def first(n = nil)
        if n.nil?
          @redis.lindex(@key, 0)
        else
          @redis.lrange(@key, 0, n - 1)
        end
      end

      # Get last element(s) (LINDEX/LRANGE)
      #
      # @param n [Integer, nil] Number of elements (nil = single element)
      # @return [String, Array, nil] Last element(s) or nil
      #
      # @example
      #   list.last     # => "item3"
      #   list.last(2)  # => ["item2", "item3"]
      def last(n = nil)
        if n.nil?
          @redis.lindex(@key, -1)
        else
          @redis.lrange(@key, -n, -1)
        end
      end

      # ============================================================
      # Iteration
      # ============================================================

      # Iterate over all elements
      #
      # @yield [element] Yields each element
      # @return [self, Enumerator] self if block given, Enumerator otherwise
      #
      # @example
      #   list.each { |item| puts item }
      def each(&block)
        return enum_for(:each) unless block_given?

        to_a.each(&block)
        self
      end

      # Iterate over elements with index
      #
      # @yield [element, index] Yields each element and its index
      # @return [self, Enumerator] self if block given, Enumerator otherwise
      #
      # @example
      #   list.each_with_index { |item, i| puts "#{i}: #{item}" }
      def each_with_index(&block)
        return enum_for(:each_with_index) unless block_given?

        to_a.each_with_index(&block)
        self
      end

      # ============================================================
      # Clear
      # ============================================================

      # Delete all elements (DEL)
      #
      # @return [self] For method chaining
      #
      # @example
      #   list.clear
      def clear
        @redis.del(@key)
        self
      end

      # ============================================================
      # Expiration
      # ============================================================

      # Set expiration in seconds (EXPIRE)
      #
      # @param seconds [Integer] Seconds until expiration
      # @return [self] For method chaining
      #
      # @example
      #   list.expire(3600)  # Expire in 1 hour
      def expire(seconds)
        @redis.expire(@key, seconds)
        self
      end

      # Set expiration at timestamp (EXPIREAT)
      #
      # @param timestamp [Integer, Time] Unix timestamp or Time object
      # @return [self] For method chaining
      #
      # @example
      #   list.expire_at(Time.now + 3600)
      def expire_at(timestamp)
        timestamp = timestamp.to_i if timestamp.is_a?(Time)
        @redis.expireat(@key, timestamp)
        self
      end

      # Get time-to-live in seconds (TTL)
      #
      # @return [Integer] Seconds until expiration (-1 = no expiry, -2 = doesn't exist)
      #
      # @example
      #   list.ttl  # => 3600
      def ttl
        @redis.ttl(@key)
      end

      # Remove expiration (PERSIST)
      #
      # @return [self] For method chaining
      #
      # @example
      #   list.persist
      def persist
        @redis.persist(@key)
        self
      end

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

