# frozen_string_literal: true

class Redis
  module Commands
    # Hash command compatibility methods for redis-rb
    module Hashes
      # Get multiple hash fields as a hash
      #
      # @param key [String] hash key
      # @param fields [Array<String>] fields to retrieve
      # @return [Hash] hash mapping fields to values
      def mapped_hmget(key, *fields)
        fields = fields.flatten
        values = hmget(key, *fields)
        fields.zip(values).to_h
      end

      # Set multiple hash fields from a hash
      #
      # @param key [String] hash key
      # @param hash [Hash] field-value pairs to set
      # @return [String] "OK"
      def mapped_hmset(key, hash)
        hmset(key, *hash.flatten)
      end

      # Set hash field only if it doesn't exist (redis-rb returns boolean)
      #
      # @param key [String] hash key
      # @param field [String] field name
      # @param value [String] value to set
      # @return [Boolean] true if field was set
      def hsetnx?(key, field, value)
        hsetnx(key, field, value) == 1
      end

      # Increment hash field by float and return as Float
      #
      # redis-rb returns Float, redis-ruby returns String
      # This wrapper ensures Float is returned
      #
      # @param key [String] hash key
      # @param field [String] field name
      # @param increment [Float] amount to increment
      # @return [Float] new value
      def hincrbyfloat_compat(key, field, increment)
        result = hincrbyfloat(key, field, increment)
        result.is_a?(String) ? result.to_f : result
      end
    end
  end
end
