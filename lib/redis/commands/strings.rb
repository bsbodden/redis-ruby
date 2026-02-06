# frozen_string_literal: true

class Redis
  module Commands
    # String command compatibility methods for redis-rb
    module Strings
      # Get the values of multiple keys as a hash
      #
      # @param keys [Array<String>] keys to retrieve
      # @return [Hash] hash mapping keys to values
      def mapped_mget(*keys)
        keys = keys.flatten
        values = mget(*keys)
        keys.zip(values).to_h
      end

      # Set multiple keys from a hash
      #
      # @param hash [Hash] key-value pairs to set
      # @return [String] "OK"
      def mapped_mset(hash)
        mset(*hash.flatten)
      end

      # Set multiple keys from a hash, only if none exist
      #
      # @param hash [Hash] key-value pairs to set
      # @return [Boolean] true if all keys were set
      def mapped_msetnx(hash)
        # msetnx already returns boolean in this compat layer
        msetnx(*hash.flatten)
      end
    end
  end
end
