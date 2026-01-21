# frozen_string_literal: true

module RedisRuby
  module Commands
    # Pub/Sub commands for publish/subscribe messaging
    #
    # Redis Pub/Sub implements the publish/subscribe messaging paradigm.
    # Subscribers express interest in channels, and receive messages without
    # knowing the publishers.
    #
    # @example Publishing a message
    #   redis.publish("channel", "Hello, World!")
    #
    # @example Subscribing to channels
    #   redis.subscribe("channel1", "channel2") do |on|
    #     on.message do |channel, message|
    #       puts "Received #{message} on #{channel}"
    #     end
    #   end
    #
    # @see https://redis.io/commands/?group=pubsub
    module PubSub
      # Publish a message to a channel
      #
      # @param channel [String] Channel name
      # @param message [String] Message to publish
      # @return [Integer] Number of subscribers that received the message
      #
      # @example
      #   redis.publish("news", "Breaking news!")
      def publish(channel, message)
        call("PUBLISH", channel, message)
      end

      # Subscribe to channels
      #
      # Subscribes to the given channels and enters subscription mode.
      # The block receives a handler object to set up callbacks.
      #
      # @param channels [Array<String>] Channel names to subscribe to
      # @yield [SubscriptionHandler] Handler for setting up callbacks
      #
      # @example
      #   redis.subscribe("channel1", "channel2") do |on|
      #     on.subscribe do |channel, count|
      #       puts "Subscribed to #{channel}"
      #     end
      #
      #     on.message do |channel, message|
      #       puts "#{channel}: #{message}"
      #       redis.unsubscribe if message == "quit"
      #     end
      #
      #     on.unsubscribe do |channel, count|
      #       puts "Unsubscribed from #{channel}"
      #     end
      #   end
      def subscribe(*channels, &block)
        subscription_loop("SUBSCRIBE", channels, &block)
      end

      # Subscribe with timeout
      #
      # Like subscribe, but with a timeout after which it automatically unsubscribes.
      #
      # @param timeout [Float] Timeout in seconds
      # @param channels [Array<String>] Channel names
      # @yield [SubscriptionHandler] Handler for setting up callbacks
      def subscribe_with_timeout(timeout, *channels, &block)
        subscription_loop("SUBSCRIBE", channels, timeout: timeout, &block)
      end

      # Unsubscribe from channels
      #
      # @param channels [Array<String>] Channels to unsubscribe from (empty = all)
      # @return [void]
      def unsubscribe(*channels)
        if @subscription_connection
          if channels.empty?
            @subscription_connection.write_command(["UNSUBSCRIBE"])
          else
            @subscription_connection.write_command(["UNSUBSCRIBE", *channels])
          end
        end
      end

      # Subscribe to patterns
      #
      # @param patterns [Array<String>] Patterns to subscribe to
      # @yield [SubscriptionHandler] Handler for setting up callbacks
      #
      # @example
      #   redis.psubscribe("news.*", "sports.*") do |on|
      #     on.psubscribe do |pattern, count|
      #       puts "Subscribed to #{pattern}"
      #     end
      #
      #     on.pmessage do |pattern, channel, message|
      #       puts "#{pattern} -> #{channel}: #{message}"
      #     end
      #   end
      def psubscribe(*patterns, &block)
        subscription_loop("PSUBSCRIBE", patterns, &block)
      end

      # Pattern subscribe with timeout
      #
      # @param timeout [Float] Timeout in seconds
      # @param patterns [Array<String>] Patterns to subscribe to
      # @yield [SubscriptionHandler] Handler for setting up callbacks
      def psubscribe_with_timeout(timeout, *patterns, &block)
        subscription_loop("PSUBSCRIBE", patterns, timeout: timeout, &block)
      end

      # Unsubscribe from patterns
      #
      # @param patterns [Array<String>] Patterns to unsubscribe from (empty = all)
      # @return [void]
      def punsubscribe(*patterns)
        if @subscription_connection
          if patterns.empty?
            @subscription_connection.write_command(["PUNSUBSCRIBE"])
          else
            @subscription_connection.write_command(["PUNSUBSCRIBE", *patterns])
          end
        end
      end

      # List active channels
      #
      # @param pattern [String, nil] Optional glob-style pattern
      # @return [Array<String>] List of active channels
      def pubsub_channels(pattern = nil)
        if pattern
          call("PUBSUB", "CHANNELS", pattern)
        else
          call("PUBSUB", "CHANNELS")
        end
      end

      # Get subscriber count for channels
      #
      # @param channels [Array<String>] Channel names
      # @return [Hash<String, Integer>] Channel => subscriber count
      def pubsub_numsub(*channels)
        return {} if channels.empty?

        result = call("PUBSUB", "NUMSUB", *channels)
        Hash[*result]
      end

      # Get pattern subscriber count
      #
      # @return [Integer] Number of pattern subscriptions
      def pubsub_numpat
        call("PUBSUB", "NUMPAT")
      end

      # List active shard channels (Redis 7+)
      #
      # @param pattern [String, nil] Optional glob-style pattern
      # @return [Array<String>] List of active shard channels
      def pubsub_shardchannels(pattern = nil)
        if pattern
          call("PUBSUB", "SHARDCHANNELS", pattern)
        else
          call("PUBSUB", "SHARDCHANNELS")
        end
      end

      # Get shard channel subscriber counts (Redis 7+)
      #
      # @param channels [Array<String>] Channel names
      # @return [Hash<String, Integer>] Channel => subscriber count
      def pubsub_shardnumsub(*channels)
        return {} if channels.empty?

        result = call("PUBSUB", "SHARDNUMSUB", *channels)
        Hash[*result]
      end

      private

      # Main subscription loop
      def subscription_loop(command, targets, timeout: nil)
        handler = SubscriptionHandler.new

        # Let caller set up callbacks
        yield handler if block_given?

        ensure_connected

        # Use the existing connection for subscriptions
        @subscription_connection = @connection

        # Send initial subscribe command
        @subscription_connection.write_command([command, *targets])

        # Track subscription state
        subscriptions = 0
        deadline = timeout ? Time.now + timeout : nil

        # Read messages until we're fully unsubscribed
        loop do
          # Check timeout
          if deadline && Time.now >= deadline
            # Timeout - unsubscribe from everything
            if command == "SUBSCRIBE"
              @subscription_connection.write_command(["UNSUBSCRIBE"])
            else
              @subscription_connection.write_command(["PUNSUBSCRIBE"])
            end
          end

          # Read next message
          begin
            message = @subscription_connection.read_response(timeout: timeout ? [1.0, timeout].min : nil)
          rescue TimeoutError
            next if deadline && Time.now < deadline
            break
          end

          # Handle message
          break unless message.is_a?(Array) && !message.empty?

          type = message[0]

          case type
          when "subscribe", "psubscribe"
            subscriptions = message[2].to_i
            handler.call_subscribe(type.to_sym, message[1], subscriptions)
          when "unsubscribe", "punsubscribe"
            subscriptions = message[2].to_i
            handler.call_unsubscribe(type.to_sym, message[1], subscriptions)
            break if subscriptions.zero?
          when "message"
            handler.call_message(message[1], message[2])
          when "pmessage"
            handler.call_pmessage(message[1], message[2], message[3])
          end
        end
      ensure
        @subscription_connection = nil
      end

      # Handler for subscription callbacks
      class SubscriptionHandler
        def initialize
          @callbacks = {}
        end

        # Set callback for subscribe events
        def subscribe(&block)
          @callbacks[:subscribe] = block
        end

        # Set callback for psubscribe events
        def psubscribe(&block)
          @callbacks[:psubscribe] = block
        end

        # Set callback for unsubscribe events
        def unsubscribe(&block)
          @callbacks[:unsubscribe] = block
        end

        # Set callback for punsubscribe events
        def punsubscribe(&block)
          @callbacks[:punsubscribe] = block
        end

        # Set callback for message events
        def message(&block)
          @callbacks[:message] = block
        end

        # Set callback for pmessage events
        def pmessage(&block)
          @callbacks[:pmessage] = block
        end

        # @private
        def call_subscribe(type, channel, count)
          @callbacks[type]&.call(channel, count)
        end

        # @private
        def call_unsubscribe(type, channel, count)
          @callbacks[type]&.call(channel, count)
        end

        # @private
        def call_message(channel, message)
          @callbacks[:message]&.call(channel, message)
        end

        # @private
        def call_pmessage(pattern, channel, message)
          @callbacks[:pmessage]&.call(pattern, channel, message)
        end
      end
    end
  end
end
