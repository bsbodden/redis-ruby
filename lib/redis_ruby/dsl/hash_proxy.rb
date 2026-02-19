# frozen_string_literal: true

require_relative "expirable"

module RR
  module DSL
    # Chainable proxy for Redis Hash operations
    #
    # Provides a fluent, idiomatic Ruby API for working with Redis hashes,
    # making them feel like native Ruby Hash objects while maintaining
    # the power of Redis operations.
    #
    # @example Basic hash-like operations
    #   user = redis.hash(:user, 123)
    #   user[:name] = "John"
    #   user[:email] = "john@example.com"
    #   puts user[:name]  # => "John"
    #
    # @example Chainable operations
    #   redis.hash(:user, 123)
    #     .set(name: "John", email: "john@example.com")
    #     .increment(:login_count)
    #     .expire(3600)
    #
    # @example Bulk operations
    #   user = redis.hash(:user, 123)
    #   user.merge(age: 30, city: "SF")
    #   user.to_h  # => {name: "John", email: "...", age: "30", city: "SF"}
    #
    class HashProxy
      include Expirable

      attr_reader :key

      # @private
      def initialize(redis, *key_parts)
        @redis = redis
        @key = key_parts.map(&:to_s).join(":")
      end

      # Get the value of a hash field (Hash-like access)
      #
      # @param field [String, Symbol] Field name
      # @return [String, nil] Field value or nil
      #
      # @example
      #   user[:name]  # => "John"
      def [](field)
        @redis.hget(@key, field.to_s)
      end

      # Set the value of a hash field (Hash-like access)
      #
      # @param field [String, Symbol] Field name
      # @param value [String, Integer, Float] Field value
      # @return [String, Integer, Float] The value that was set
      #
      # @example
      #   user[:name] = "John"
      def []=(field, value)
        @redis.hset(@key, field.to_s, value)
      end

      # Set multiple fields at once
      #
      # @param fields [Hash] Field-value pairs
      # @return [self] For method chaining
      #
      # @example
      #   user.set(name: "John", email: "john@example.com")
      def set(**fields)
        return self if fields.empty?

        # Convert symbol keys to strings and flatten for HSET
        flat_args = fields.flat_map { |k, v| [k.to_s, v] }
        @redis.hset(@key, *flat_args)
        self
      end

      # Alias for set (Ruby Hash compatibility)
      alias merge set
      alias update set

      # Get the value of a field with a default
      #
      # @param field [String, Symbol] Field name
      # @param default [Object] Default value if field doesn't exist
      # @return [String, Object] Field value or default
      #
      # @example
      #   user.fetch(:age, 0)  # => 0 if age doesn't exist
      def fetch(field, default = nil)
        value = @redis.hget(@key, field.to_s)
        value.nil? ? default : value
      end

      # Get all fields and values as a Hash
      #
      # @return [Hash] Hash with symbol keys
      #
      # @example
      #   user.to_h  # => {name: "John", email: "john@example.com"}
      def to_h
        result = @redis.hgetall(@key)
        return {} if result.nil? || result.empty?

        # Convert string keys to symbols
        result.transform_keys(&:to_sym)
      end

      # Check if the hash exists
      #
      # @return [Boolean] true if hash exists
      #
      # @example
      #   user.exists?  # => true
      def exists?
        @redis.exists(@key).positive?
      end

      # Check if a field exists in the hash
      #
      # @param field [String, Symbol] Field name
      # @return [Boolean] true if field exists
      #
      # @example
      #   user.key?(:name)  # => true
      def key?(field)
        @redis.hexists(@key, field.to_s) == 1
      end

      # Alias for key? (Ruby Hash compatibility)
      alias has_key? key?
      alias include? key?
      alias member? key?

      # Get all field names
      #
      # @return [Array<Symbol>] Array of field names as symbols
      #
      # @example
      #   user.keys  # => [:name, :email, :age]
      def keys
        @redis.hkeys(@key).map(&:to_sym)
      end

      # Get all values
      #
      # @return [Array<String>] Array of values
      #
      # @example
      #   user.values  # => ["John", "john@example.com", "30"]
      def values
        @redis.hvals(@key)
      end

      # Get the number of fields in the hash
      #
      # @return [Integer] Number of fields
      #
      # @example
      #   user.length  # => 3
      def length
        @redis.hlen(@key)
      end

      # Alias for length (Ruby Hash compatibility)
      alias size length

      # Check if the hash is empty
      #
      # @return [Boolean] true if hash has no fields
      #
      # @example
      #   user.empty?  # => false
      def empty?
        length.zero?
      end

      # Delete one or more fields from the hash
      #
      # @param fields [Array<String, Symbol>] Field names to delete
      # @return [Integer] Number of fields deleted
      #
      # @example
      #   user.delete(:old_field)
      #   user.delete(:field1, :field2, :field3)
      def delete(*fields)
        return 0 if fields.empty?

        @redis.hdel(@key, *fields.map(&:to_s))
      end

      # Delete the entire hash
      #
      # @return [Integer] Number of keys deleted (0 or 1)
      #
      # @example
      #   user.clear
      def clear
        @redis.del(@key)
      end

      # Get a subset of fields
      #
      # @param fields [Array<String, Symbol>] Field names to retrieve
      # @return [Hash] Hash with only the specified fields
      #
      # @example
      #   user.slice(:name, :email)  # => {name: "John", email: "..."}
      def slice(*fields)
        return {} if fields.empty?

        values = @redis.hmget(@key, *fields.map(&:to_s))
        result = {}
        fields.each_with_index do |field, index|
          result[field.to_sym] = values[index] unless values[index].nil?
        end
        result
      end

      # Get all fields except the specified ones
      #
      # @param fields [Array<String, Symbol>] Field names to exclude
      # @return [Hash] Hash without the specified fields
      #
      # @example
      #   user.except(:password)  # => {name: "John", email: "..."}
      def except(*fields)
        all_data = to_h
        fields.each { |field| all_data.delete(field.to_sym) }
        all_data
      end

      # Increment a field's integer value
      #
      # @param field [String, Symbol] Field name
      # @param by [Integer] Amount to increment (default: 1)
      # @return [self] For method chaining
      #
      # @example
      #   user.increment(:login_count)      # Increment by 1
      #   user.increment(:points, 10)       # Increment by 10
      def increment(field, by = 1)
        @redis.hincrby(@key, field.to_s, by)
        self
      end

      # Decrement a field's integer value
      #
      # @param field [String, Symbol] Field name
      # @param by [Integer] Amount to decrement (default: 1)
      # @return [self] For method chaining
      #
      # @example
      #   user.decrement(:credits)          # Decrement by 1
      #   user.decrement(:balance, 5)       # Decrement by 5
      def decrement(field, by = 1)
        @redis.hincrby(@key, field.to_s, -by)
        self
      end

      # Increment a field's float value
      #
      # @param field [String, Symbol] Field name
      # @param by [Float] Amount to increment
      # @return [self] For method chaining
      #
      # @example
      #   user.increment_float(:score, 1.5)
      def increment_float(field, by)
        @redis.hincrbyfloat(@key, field.to_s, by)
        self
      end

      # Iterate over all field-value pairs
      #
      # @yield [field, value] Yields each field-value pair
      # @return [self, Enumerator] Returns self if block given, Enumerator otherwise
      #
      # @example
      #   user.each { |field, value| puts "#{field}: #{value}" }
      def each(&)
        return to_enum(:each) unless block_given?

        to_h.each(&)
        self
      end

      # Iterate over all field names
      #
      # @yield [field] Yields each field name
      # @return [self, Enumerator] Returns self if block given, Enumerator otherwise
      #
      # @example
      #   user.each_key { |field| puts field }
      def each_key(&)
        return to_enum(:each_key) unless block_given?

        keys.each(&)
        self
      end

      # Iterate over all values
      #
      # @yield [value] Yields each value
      # @return [self, Enumerator] Returns self if block given, Enumerator otherwise
      #
      # @example
      #   user.each_value { |value| puts value }
      def each_value(&)
        return to_enum(:each_value) unless block_given?

        values.each(&)
        self
      end
    end
  end
end
