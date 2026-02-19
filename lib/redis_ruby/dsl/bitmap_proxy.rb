# frozen_string_literal: true

require_relative "expirable"

module RR
  module DSL
    # Chainable proxy for Redis Bitmap operations
    #
    # Provides a fluent, idiomatic Ruby API for working with Redis bitmaps,
    # optimized for tracking boolean states, user activity, feature flags,
    # and permissions with extremely efficient memory usage.
    #
    # @example Daily active users tracking
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
    #
    class BitmapProxy
      include Expirable

      attr_reader :key

      # @private
      def initialize(redis, *key_parts)
        @redis = redis
        @key = key_parts.map(&:to_s).join(":")
      end

      # Set bit at offset to 0 or 1
      #
      # @param offset [Integer] Bit offset (0-based)
      # @param value [Integer] 0 or 1
      # @return [self] For method chaining
      #
      # @example
      #   bitmap.set_bit(123, 1)
      #   bitmap.set_bit(456, 0)
      def set_bit(offset, value)
        @redis.setbit(@key, offset, value)
        self
      end

      # Get bit value at offset
      #
      # @param offset [Integer] Bit offset (0-based)
      # @return [Integer] 0 or 1
      #
      # @example
      #   bitmap.get_bit(123)  # => 1
      def get_bit(offset)
        @redis.getbit(@key, offset)
      end

      # Set bit at offset (Array-like syntax)
      #
      # @param offset [Integer] Bit offset (0-based)
      # @param value [Integer] 0 or 1
      # @return [Integer] The value that was set
      #
      # @example
      #   bitmap[123] = 1
      #   bitmap[456] = 0
      def []=(offset, value)
        @redis.setbit(@key, offset, value)
      end

      # Get bit value at offset (Array-like syntax)
      #
      # @param offset [Integer] Bit offset (0-based)
      # @return [Integer] 0 or 1
      #
      # @example
      #   bitmap[123]  # => 1
      def [](offset)
        @redis.getbit(@key, offset)
      end

      # Count set bits (1s) in the bitmap
      #
      # @param start_byte [Integer] Start byte position (default: 0)
      # @param end_byte [Integer] End byte position (default: -1 for end)
      # @return [Integer] Number of bits set to 1
      #
      # @example
      #   bitmap.count           # Count all bits
      #   bitmap.count(0, 10)    # Count bits in bytes 0-10
      def count(start_byte = 0, end_byte = -1)
        if start_byte.zero? && end_byte == -1
          @redis.bitcount(@key)
        else
          @redis.bitcount(@key, start_byte, end_byte)
        end
      end

      # Find first occurrence of bit (0 or 1)
      #
      # @param bit [Integer] 0 or 1
      # @param start_byte [Integer] Start byte position (default: 0)
      # @param end_byte [Integer] End byte position (default: -1 for end)
      # @return [Integer] Position of first bit, or -1 if not found
      #
      # @example
      #   bitmap.position(1)        # Find first 1 bit
      #   bitmap.position(0, 10)    # Find first 0 bit starting at byte 10
      def position(bit, start_byte = 0, end_byte = -1)
        if start_byte.zero? && end_byte == -1
          @redis.bitpos(@key, bit)
        else
          @redis.bitpos(@key, bit, start_byte, end_byte)
        end
      end

      # Perform AND operation (destructive - modifies current key)
      #
      # @param keys [Array<String, Symbol>] Source keys to AND
      # @return [self] For method chaining
      #
      # @example
      #   result.and(:bitmap1, :bitmap2)
      def and(*keys)
        return self if keys.empty?

        @redis.bitop("AND", @key, *keys.map(&:to_s))
        self
      end

      # Perform OR operation (destructive - modifies current key)
      #
      # @param keys [Array<String, Symbol>] Source keys to OR
      # @return [self] For method chaining
      #
      # @example
      #   result.or(:bitmap1, :bitmap2, :bitmap3)
      def or(*keys)
        return self if keys.empty?

        @redis.bitop("OR", @key, *keys.map(&:to_s))
        self
      end

      # Perform XOR operation (destructive - modifies current key)
      #
      # @param keys [Array<String, Symbol>] Source keys to XOR
      # @return [self] For method chaining
      #
      # @example
      #   result.xor(:bitmap1, :bitmap2)
      def xor(*keys)
        return self if keys.empty?

        @redis.bitop("XOR", @key, *keys.map(&:to_s))
        self
      end

      # Perform NOT operation (destructive - modifies current key)
      #
      # @param source_key [String, Symbol] Source key to NOT
      # @return [self] For method chaining
      #
      # @example
      #   result.not(:bitmap1)
      def not(source_key)
        @redis.bitop("NOT", @key, source_key.to_s)
        self
      end

      # Perform AND operation into destination (non-destructive)
      #
      # @param dest [String, Symbol] Destination key
      # @param keys [Array<String, Symbol>] Additional source keys
      # @return [self] For method chaining
      #
      # @example
      #   bitmap1.and_into(:result, :bitmap2)
      def and_into(dest, *keys)
        @redis.bitop("AND", dest.to_s, @key, *keys.map(&:to_s))
        self
      end

      # Perform OR operation into destination (non-destructive)
      #
      # @param dest [String, Symbol] Destination key
      # @param keys [Array<String, Symbol>] Additional source keys
      # @return [self] For method chaining
      #
      # @example
      #   bitmap1.or_into(:result, :bitmap2, :bitmap3)
      def or_into(dest, *keys)
        @redis.bitop("OR", dest.to_s, @key, *keys.map(&:to_s))
        self
      end

      # Perform XOR operation into destination (non-destructive)
      #
      # @param dest [String, Symbol] Destination key
      # @param keys [Array<String, Symbol>] Additional source keys
      # @return [self] For method chaining
      #
      # @example
      #   bitmap1.xor_into(:result, :bitmap2)
      def xor_into(dest, *keys)
        @redis.bitop("XOR", dest.to_s, @key, *keys.map(&:to_s))
        self
      end

      # Perform NOT operation into destination (non-destructive)
      #
      # @param dest [String, Symbol] Destination key
      # @return [self] For method chaining
      #
      # @example
      #   bitmap1.not_into(:result)
      def not_into(dest)
        @redis.bitop("NOT", dest.to_s, @key)
        self
      end

      # Create a bitfield builder for complex bitfield operations
      #
      # @return [BitFieldBuilder] Builder for chaining bitfield operations
      #
      # @example
      #   bitmap.bitfield
      #     .set(:u8, 0, 100)
      #     .incrby(:u8, 0, 10)
      #     .get(:u8, 0)
      #     .execute  # => [0, 110, 110]
      def bitfield
        BitFieldBuilder.new(@redis, @key)
      end

      # Check if the bitmap exists
      #
      # @return [Boolean] true if bitmap exists
      #
      # @example
      #   bitmap.exists?  # => true
      def exists?
        @redis.exists(@key).positive?
      end

      # Check if the bitmap is empty (doesn't exist or has no set bits)
      #
      # @return [Boolean] true if bitmap is empty
      #
      # @example
      #   bitmap.empty?  # => false
      def empty?
        !exists? || count.zero?
      end

      # Delete the bitmap
      #
      # @return [Integer] Number of keys deleted (0 or 1)
      #
      # @example
      #   bitmap.delete
      def delete
        @redis.del(@key)
      end
      alias clear delete
    end
  end
end
