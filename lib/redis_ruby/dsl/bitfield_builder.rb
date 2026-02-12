# frozen_string_literal: true

module RedisRuby
  module DSL
    # Builder for Redis BITFIELD operations
    #
    # Provides a fluent interface for building complex bitfield operations
    # that can read, write, and increment arbitrary bit ranges within a string.
    #
    # Supports signed and unsigned integers of various sizes:
    # - u8, u16, u32, u64 (unsigned)
    # - i8, i16, i32, i64 (signed)
    #
    # @example Store multiple counters
    #   bitmap.bitfield
    #     .set(:u8, 0, 100)
    #     .set(:u8, 8, 200)
    #     .set(:u8, 16, 300)
    #     .execute  # => [0, 0, 0]
    #
    # @example Increment with overflow control
    #   bitmap.bitfield
    #     .overflow(:sat)
    #     .incrby(:u8, 0, 10)
    #     .execute  # => [110]
    #
    # @example Read multiple values
    #   bitmap.bitfield
    #     .get(:u8, 0)
    #     .get(:u8, 8)
    #     .get(:u8, 16)
    #     .execute  # => [100, 200, 300]
    #
    class BitFieldBuilder
      # @private
      def initialize(redis, key)
        @redis = redis
        @key = key
        @operations = []
      end

      # Get value from bitfield
      #
      # @param type [Symbol, String] Integer type (e.g., :u8, :i16, :u32)
      # @param offset [Integer] Bit offset
      # @return [self] For method chaining
      #
      # @example
      #   builder.get(:u8, 0)
      #   builder.get(:i16, 16)
      def get(type, offset)
        @operations << "GET" << type.to_s << offset
        self
      end

      # Set value in bitfield
      #
      # @param type [Symbol, String] Integer type (e.g., :u8, :i16, :u32)
      # @param offset [Integer] Bit offset
      # @param value [Integer] Value to set
      # @return [self] For method chaining
      #
      # @example
      #   builder.set(:u8, 0, 100)
      #   builder.set(:i16, 16, -500)
      def set(type, offset, value)
        @operations << "SET" << type.to_s << offset << value
        self
      end

      # Increment value in bitfield
      #
      # @param type [Symbol, String] Integer type (e.g., :u8, :i16, :u32)
      # @param offset [Integer] Bit offset
      # @param increment [Integer] Amount to increment (can be negative)
      # @return [self] For method chaining
      #
      # @example
      #   builder.incrby(:u8, 0, 10)
      #   builder.incrby(:i16, 16, -5)
      def incrby(type, offset, increment)
        @operations << "INCRBY" << type.to_s << offset << increment
        self
      end

      # Set overflow behavior for subsequent operations
      #
      # @param mode [Symbol, String] Overflow mode: :wrap, :sat, or :fail
      #   - :wrap - Wrap around on overflow (default)
      #   - :sat - Saturate at min/max value
      #   - :fail - Return nil on overflow
      # @return [self] For method chaining
      #
      # @example
      #   builder.overflow(:sat).incrby(:u8, 0, 200)
      #   builder.overflow(:fail).incrby(:u8, 8, 300)
      def overflow(mode)
        @operations << "OVERFLOW" << mode.to_s.upcase
        self
      end

      # Execute all queued bitfield operations
      #
      # @return [Array] Results of each operation
      #
      # @example
      #   results = builder
      #     .set(:u8, 0, 100)
      #     .incrby(:u8, 0, 10)
      #     .get(:u8, 0)
      #     .execute  # => [0, 110, 110]
      def execute
        return [] if @operations.empty?
        @redis.bitfield(@key, *@operations)
      end
    end
  end
end

