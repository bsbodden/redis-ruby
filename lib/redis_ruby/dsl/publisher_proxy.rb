# frozen_string_literal: true

require "json"

module RedisRuby
  module DSL
    # Chainable proxy for publishing messages to Redis Pub/Sub channels
    #
    # Provides a fluent interface for publishing messages with automatic
    # JSON encoding and support for multiple channels.
    #
    # @example Simple publishing
    #   redis.publisher(:notifications)
    #     .send("User logged in")
    #     .send("Profile updated")
    #
    # @example Publishing to multiple channels
    #   redis.publisher
    #     .to(:news, :sports, :weather)
    #     .send("Breaking news!")
    #
    # @example Publishing with JSON encoding
    #   redis.publisher(:events)
    #     .send(event: "order_created", order_id: 123)
    #
    class PublisherProxy
      # @private
      attr_reader :redis, :channels

      # Initialize a new publisher proxy
      #
      # @param redis [RedisRuby::Client] Redis client instance
      # @param channels [Array<String, Symbol>] Initial channels to publish to
      def initialize(redis, *channels)
        @redis = redis
        @channels = channels.map(&:to_s)
        @shard = false
      end

      # Set channels to publish to
      #
      # @param channels [Array<String, Symbol>] Channel names
      # @return [self] Returns self for chaining
      #
      # @example
      #   redis.publisher.to(:news, :sports).send("Hello!")
      def to(*channels)
        @channels = channels.map(&:to_s)
        self
      end

      # Publish a message to the configured channels
      #
      # If the message is a Hash, it will be automatically JSON-encoded.
      # Returns self for chaining multiple sends.
      #
      # @param message [String, Hash] Message to publish
      # @return [self] Returns self for chaining
      #
      # @example String message
      #   publisher.send("Hello, World!")
      #
      # @example Hash message (auto JSON-encoded)
      #   publisher.send(event: "user_login", user_id: 123)
      def send(message)
        encoded_message = encode_message(message)
        
        if @channels.empty?
          raise ArgumentError, "No channels specified. Use .to(:channel) or publisher(:channel)"
        end

        @channels.each do |channel|
          if @shard
            @redis.spublish(channel, encoded_message)
          else
            @redis.publish(channel, encoded_message)
          end
        end

        self
      end

      # Alias for send (to avoid conflict with Object#send)
      alias publish send

      # Enable sharded publishing (Redis 7.0+)
      #
      # Sharded pub/sub routes messages based on the channel's key slot.
      #
      # @return [self] Returns self for chaining
      #
      # @example
      #   redis.publisher.shard.to("user:{123}:updates").send("profile_updated")
      def shard
        @shard = true
        self
      end

      # Check if sharded publishing is enabled
      #
      # @return [Boolean]
      def shard?
        @shard
      end

      # Get the number of subscribers for the configured channels
      #
      # @return [Hash<String, Integer>] Channel => subscriber count
      #
      # @example
      #   publisher.to(:news, :sports).subscriber_count
      #   # => {"news" => 5, "sports" => 3}
      def subscriber_count
        return {} if @channels.empty?

        if @shard
          @redis.pubsub_shardnumsub(*@channels)
        else
          @redis.pubsub_numsub(*@channels)
        end
      end

      private

      # Encode message for publishing
      #
      # Hashes are automatically JSON-encoded, everything else is converted to string.
      #
      # @param message [Object] Message to encode
      # @return [String] Encoded message
      def encode_message(message)
        case message
        when Hash
          JSON.generate(message)
        else
          message.to_s
        end
      end
    end
  end
end

