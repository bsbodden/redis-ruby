# frozen_string_literal: true

require "json"

module RedisRuby
  # Wisper-style broadcaster mixin for Redis Pub/Sub
  #
  # Provides a familiar API for applications migrating from Wisper.
  # Include this module in your classes to add broadcast() and on() methods.
  #
  # @example Basic usage
  #   class OrderService
  #     include RedisRuby::Broadcaster
  #
  #     def create_order(params)
  #       order = Order.create(params)
  #
  #       if order.persisted?
  #         broadcast(:order_created, order.to_json)
  #       else
  #         broadcast(:order_failed, order.errors.to_json)
  #       end
  #     end
  #   end
  #
  #   service = OrderService.new
  #   service.on(:order_created) { |data| puts "Order created: #{data}" }
  #   service.create_order(params)
  #
  module Broadcaster
    # @private
    def self.included(base)
      base.extend(ClassMethods)
    end

    # Class methods added when Broadcaster is included
    module ClassMethods
      # Get or set the Redis client for this class
      #
      # @param client [RedisRuby::Client, nil] Redis client to use
      # @return [RedisRuby::Client] The Redis client
      #
      # @example
      #   class MyService
      #     include RedisRuby::Broadcaster
      #     redis_client RedisRuby.new
      #   end
      def redis_client(client = nil)
        if client
          @redis_client = client
        else
          @redis_client ||= RedisRuby.new
        end
      end

      # Get the channel prefix for this class
      #
      # By default, uses the class name in snake_case.
      #
      # @return [String] Channel prefix
      #
      # @example
      #   OrderService.channel_prefix  # => "order_service"
      def channel_prefix
        @channel_prefix ||= name.gsub("::", "_").
                                 gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').
                                 gsub(/([a-z\d])([A-Z])/, '\1_\2').
                                 downcase
      end

      # Set a custom channel prefix
      #
      # @param prefix [String, Symbol] Custom prefix
      #
      # @example
      #   class OrderService
      #     include RedisRuby::Broadcaster
      #     set_channel_prefix :orders
      #   end
      def set_channel_prefix(prefix)
        @channel_prefix = prefix.to_s
      end
    end

    # Broadcast an event to Redis Pub/Sub
    #
    # The channel name is automatically generated from the class name and event.
    # For example, OrderService broadcasting :order_created will publish to
    # "order_service:order_created".
    #
    # @param event [String, Symbol] Event name
    # @param args [Array] Arguments to pass (will be JSON-encoded if multiple or Hash)
    # @return [Integer] Number of subscribers that received the message
    #
    # @example
    #   broadcast(:order_created, order_id: 123, amount: 99.99)
    #   broadcast(:user_login, user_id)
    def broadcast(event, *args)
      channel = build_channel_name(event)
      message = encode_broadcast_message(args)
      
      redis_client.publish(channel, message)
    end

    # Subscribe to an event
    #
    # Sets up a local callback that will be triggered when this instance
    # broadcasts the event. This is useful for testing or local event handling.
    #
    # For distributed subscriptions across processes, use the subscriber builder:
    #   redis.subscriber.on("order_service:order_created") { |ch, msg| ... }
    #
    # @param event [String, Symbol] Event name
    # @yield [*args] Block to call when event is broadcast
    # @return [self]
    #
    # @example
    #   service = OrderService.new
    #   service.on(:order_created) { |data| puts "Created: #{data}" }
    #   service.create_order(params)  # Will trigger the callback
    def on(event, &block)
      local_callbacks[event.to_sym] = block
      self
    end

    # Get the Redis client for this instance
    #
    # @return [RedisRuby::Client]
    def redis_client
      @redis_client ||= self.class.redis_client
    end

    # Set a custom Redis client for this instance
    #
    # @param client [RedisRuby::Client] Redis client
    def redis_client=(client)
      @redis_client = client
    end

    private

    # Build the full channel name from event
    def build_channel_name(event)
      "#{self.class.channel_prefix}:#{event}"
    end

    # Encode broadcast message
    def encode_broadcast_message(args)
      case args.length
      when 0
        ""
      when 1
        args[0].is_a?(Hash) ? JSON.generate(args[0]) : args[0].to_s
      else
        JSON.generate(args)
      end
    end

    # Get local callbacks hash
    def local_callbacks
      @local_callbacks ||= {}
    end
  end
end

