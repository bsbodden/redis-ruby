# frozen_string_literal: true

require_relative "../dsl/bitmap_proxy"
require_relative "../dsl/bitfield_builder"

module RR
  module Commands
    # Bitmap commands for bit-level string operations
    #
    # Redis strings can be treated as arrays of bits, enabling
    # efficient storage and manipulation of boolean data.
    #
    # @example Basic usage
    #   redis.setbit("flags", 0, 1)  # Set bit 0
    #   redis.getbit("flags", 0)     # => 1
    #   redis.bitcount("flags")      # => 1
    #
    # @see https://redis.io/commands/?group=bitmap
    module Bitmap
      # ============================================================
      # Idiomatic Ruby API
      # ============================================================

      # Create a bitmap proxy for idiomatic operations
      #
      # Provides a fluent, Ruby-esque interface for working with Redis bitmaps.
      # Supports composite keys with automatic ":" joining.
      # Optimized for tracking boolean states, user activity, feature flags,
      # and permissions with extremely efficient memory usage (1 bit per element).
      #
      # @param key_parts [Array<String, Symbol, Integer>] Key components
      # @return [RR::DSL::BitmapProxy] Bitmap proxy instance
      #
      # @example Daily active users
      #   today = redis.bitmap(:dau, Date.today.to_s)
      #   today[user_id] = 1
      #   puts "DAU: #{today.count}"
      #
      # @example Feature flags
      #   features = redis.bitmap(:features, :user, user_id)
      #   features[FEATURE_SEARCH] = 1
      #   features[FEATURE_EXPORT] = 1
      #
      # @example Bitwise operations
      #   result = redis.bitmap(:result)
      #   result.and(:bitmap1, :bitmap2)
      #   puts "Common bits: #{result.count}"
      #
      # @example Bitfield operations
      #   counters = redis.bitmap(:counters)
      #   counters.bitfield.set(:u8, 0, 100).incrby(:u8, 0, 10).execute
      def bitmap(*key_parts)
        DSL::BitmapProxy.new(self, *key_parts)
      end

      # ============================================================
      # Low-Level Commands
      # ============================================================

      # Frozen command constants to avoid string allocations
      CMD_SETBIT = "SETBIT"
      CMD_GETBIT = "GETBIT"
      CMD_BITCOUNT = "BITCOUNT"
      CMD_BITPOS = "BITPOS"
      CMD_BITOP = "BITOP"
      CMD_BITFIELD = "BITFIELD"
      CMD_BITFIELD_RO = "BITFIELD_RO"

      # Set or clear the bit at offset in the string value
      #
      # @param key [String] Key name
      # @param offset [Integer] Bit offset (0-based)
      # @param value [Integer] 0 or 1
      # @return [Integer] Original bit value at offset
      #
      # @example
      #   redis.setbit("mykey", 7, 1)  # => 0
      def setbit(key, offset, value)
        call_3args(CMD_SETBIT, key, offset, value)
      end

      # Get the bit value at offset in the string
      #
      # @param key [String] Key name
      # @param offset [Integer] Bit offset (0-based)
      # @return [Integer] 0 or 1
      #
      # @example
      #   redis.getbit("mykey", 7)  # => 1
      def getbit(key, offset)
        call_2args(CMD_GETBIT, key, offset)
      end

      # Count set bits (1s) in a string
      #
      # @param key [String] Key name
      # @param start [Integer, nil] Start byte (or bit with mode)
      # @param stop [Integer, nil] End byte (or bit with mode)
      # @param mode [String, nil] "BYTE" or "BIT" (Redis 7.0+)
      # @return [Integer] Number of bits set to 1
      #
      # @example Count all bits
      #   redis.bitcount("mykey")
      #
      # @example Count bits in byte range
      #   redis.bitcount("mykey", 0, 1)
      #
      # @example Count bits in bit range (Redis 7.0+)
      #   redis.bitcount("mykey", 0, 7, "BIT")
      def bitcount(key, start = nil, stop = nil, mode = nil)
        # Fast path: just key (most common)
        return call_1arg(CMD_BITCOUNT, key) if start.nil? && stop.nil?

        # Fast path: key with byte range, no mode
        return call_3args(CMD_BITCOUNT, key, start, stop) if start && stop && mode.nil?

        # Full path with mode
        if mode
          call(CMD_BITCOUNT, key, start, stop, mode.to_s.upcase)
        else
          call_3args(CMD_BITCOUNT, key, start, stop)
        end
      end

      # Find first bit set to 0 or 1 in a string
      #
      # @param key [String] Key name
      # @param bit [Integer] 0 or 1
      # @param start [Integer, nil] Start byte (or bit with mode)
      # @param stop [Integer, nil] End byte (or bit with mode)
      # @param mode [String, nil] "BYTE" or "BIT" (Redis 7.0+)
      # @return [Integer] Position of first bit, or -1 if not found
      #
      # @example Find first 1 bit
      #   redis.bitpos("mykey", 1)
      #
      # @example Find first 0 bit in range
      #   redis.bitpos("mykey", 0, 2, 4)
      def bitpos(key, bit, start = nil, stop = nil, mode = nil)
        # Fast path: no range
        return call_2args(CMD_BITPOS, key, bit) if start.nil? && stop.nil?

        # Fast path: range without mode
        return call(CMD_BITPOS, key, bit, start, stop) if start && stop && mode.nil?

        call(*build_bitpos_args(key, bit, start, stop, mode))
      end

      # Perform bitwise operations between strings
      #
      # @param operation [String] AND, OR, XOR, or NOT
      # @param destkey [String] Destination key
      # @param keys [Array<String>] Source keys (NOT only uses first)
      # @return [Integer] Size of the string stored in destkey
      #
      # @example AND operation
      #   redis.bitop("AND", "result", "key1", "key2")
      #
      # @example NOT operation
      #   redis.bitop("NOT", "result", "key1")
      def bitop(operation, destkey, *keys)
        # Fast path for NOT (single key)
        return call_3args(CMD_BITOP, operation.to_s.upcase, destkey, keys[0]) if keys.size == 1

        call(CMD_BITOP, operation.to_s.upcase, destkey, *keys)
      end

      # Perform arbitrary bitfield operations
      #
      # Allows reading, setting, and incrementing arbitrary
      # bit ranges within a string value.
      #
      # @param key [String] Key name
      # @param subcommands [Array] Subcommands and arguments
      # @return [Array] Results of each operation
      #
      # @example Get 8-bit unsigned int at offset 0
      #   redis.bitfield("mykey", "GET", "u8", 0)
      #
      # @example Set and increment
      #   redis.bitfield("mykey",
      #     "SET", "u8", 0, 100,
      #     "INCRBY", "u8", 0, 10
      #   )
      #
      # @example With overflow control
      #   redis.bitfield("mykey",
      #     "OVERFLOW", "SAT",
      #     "INCRBY", "u8", 0, 100
      #   )
      def bitfield(key, *subcommands)
        call(CMD_BITFIELD, key, *subcommands)
      end

      # Read-only variant of BITFIELD
      #
      # Only supports GET subcommand. Useful for read replicas.
      #
      # @param key [String] Key name
      # @param subcommands [Array] GET subcommands only
      # @return [Array] Results of each GET operation
      #
      # @example
      #   redis.bitfield_ro("mykey", "GET", "u8", 0, "GET", "u4", 8)
      def bitfield_ro(key, *subcommands)
        call(CMD_BITFIELD_RO, key, *subcommands)
      end

      private

      def build_bitpos_args(key, bit, start, stop, mode)
        cmd = [CMD_BITPOS, key, bit]
        cmd << start if start
        cmd << stop if stop
        cmd << mode.to_s.upcase if mode
        cmd
      end
    end
  end
end
