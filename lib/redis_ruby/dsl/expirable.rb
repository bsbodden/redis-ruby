# frozen_string_literal: true

module RR
  module DSL
    # Shared expiration methods for DSL proxy objects
    #
    # The including class must define:
    # - @redis: A Redis client instance
    # - @key: The Redis key for this proxy
    module Expirable
      # Set a timeout on the key
      #
      # @param seconds [Integer] TTL in seconds
      # @return [self] For method chaining
      def expire(seconds)
        @redis.expire(@key, seconds)
        self
      end

      # Set expiration time at a specific timestamp
      #
      # @param time [Time, Integer] Unix timestamp or Time object
      # @return [self] For method chaining
      def expire_at(time)
        timestamp = time.is_a?(Time) ? time.to_i : time
        @redis.expireat(@key, timestamp)
        self
      end

      # Get time-to-live in seconds
      #
      # @return [Integer] Seconds until expiration, -1 if no expiration, -2 if key doesn't exist
      def ttl
        @redis.ttl(@key)
      end

      # Remove expiration from the key
      #
      # @return [self] For method chaining
      def persist
        @redis.persist(@key)
        self
      end
    end
  end
end
