# frozen_string_literal: true

class Redis
  module Commands
    # Key command compatibility methods for redis-rb
    module Keys
      # Check if key(s) exist, returns boolean for single key
      #
      # redis-rb returns boolean for single key, Integer for multiple
      # redis-ruby always returns Integer
      #
      # @param keys [Array<String>] keys to check
      # @return [Boolean, Integer] boolean for single key, count for multiple
      def exists?(*keys)
        keys = keys.flatten
        if keys.length == 1
          exists(keys[0]).positive?
        else
          exists(*keys)
        end
      end

      # Scan iterator that yields keys (redis-rb compatibility)
      #
      # redis-rb calls this scan_each, redis-ruby uses scan_iter
      #
      # @param match [String] pattern to match
      # @param count [Integer] hint for number of elements
      # @param type [String, nil] filter by key type
      # @return [Enumerator] yields each matching key
      def scan_each(match: "*", count: 10, type: nil, &block)
        enum = scan_iter(match: match, count: count, type: type)
        block ? enum.each(&block) : enum
      end

      # Expire in seconds, returns boolean
      #
      # @param key [String] key to expire
      # @param seconds [Integer] TTL in seconds
      # @return [Boolean] true if timeout was set
      def expire?(key, seconds)
        expire(key, seconds) == 1
      end

      # Expire at timestamp, returns boolean
      #
      # @param key [String] key to expire
      # @param timestamp [Integer] Unix timestamp
      # @return [Boolean] true if timeout was set
      def expireat?(key, timestamp)
        expireat(key, timestamp) == 1
      end

      # Persist key, returns boolean
      #
      # @param key [String] key to persist
      # @return [Boolean] true if timeout was removed
      def persist?(key)
        persist(key) == 1
      end

      # Rename key only if new key doesn't exist, returns boolean
      #
      # @param old_name [String] current key name
      # @param new_name [String] new key name
      # @return [Boolean] true if renamed
      def renamenx?(old_name, new_name)
        renamenx(old_name, new_name) == 1
      end
    end
  end
end
