# frozen_string_literal: true

module RedisRuby
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
        call("SETBIT", key, offset, value)
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
        call("GETBIT", key, offset)
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
        if start && stop
          if mode
            call("BITCOUNT", key, start, stop, mode.to_s.upcase)
          else
            call("BITCOUNT", key, start, stop)
          end
        else
          call("BITCOUNT", key)
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
        cmd = ["BITPOS", key, bit]
        cmd << start if start
        cmd << stop if stop
        cmd << mode.to_s.upcase if mode
        call(*cmd)
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
        call("BITOP", operation.to_s.upcase, destkey, *keys)
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
        call("BITFIELD", key, *subcommands)
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
        call("BITFIELD_RO", key, *subcommands)
      end
    end
  end
end
