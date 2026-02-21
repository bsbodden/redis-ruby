# frozen_string_literal: true

require_relative "../dsl/publisher_proxy"
require_relative "../dsl/subscriber_builder"

module RR
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
      # ============================================================
      # Idiomatic Ruby API
      # ============================================================

      # Create a publisher proxy for chainable publishing
      #
      # Returns a PublisherProxy that allows fluent, chainable publishing
      # to one or more channels with automatic JSON encoding.
      #
      # @param channels [Array<String, Symbol>] Initial channels to publish to
      # @return [DSL::PublisherProxy] Publisher proxy instance
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
      # @example Sharded publishing (Redis 7.0+)
      #   redis.publisher.shard
      #     .to("user:{123}:updates")
      #     .send("profile_updated")
      def publisher(*channels)
        DSL::PublisherProxy.new(self, *channels)
      end

      # Create a subscriber builder for fluent subscriptions
      #
      # Returns a SubscriberBuilder that allows chainable subscription
      # setup with automatic JSON decoding and support for patterns.
      #
      # @return [DSL::SubscriberBuilder] Subscriber builder instance
      #
      # @example Basic subscription
      #   redis.subscriber
      #     .on(:news, :sports) { |channel, message| puts "#{channel}: #{message}" }
      #     .run
      #
      # @example Pattern subscription
      #   redis.subscriber
      #     .on_pattern("user:*") { |pattern, channel, msg| notify_user(channel, msg) }
      #     .run_async
      #
      # @example With JSON decoding
      #   redis.subscriber
      #     .on(:events, json: true) { |channel, data| process_event(data) }
      #     .run
      #
      # @example Shard subscription (Redis 7.0+)
      #   redis.subscriber
      #     .on_shard("user:{123}:updates") { |channel, msg| update_user(msg) }
      #     .run_async
      def subscriber
        DSL::SubscriberBuilder.new(self)
      end

      # ============================================================
      # Low-Level Commands
      # ============================================================

      # Frozen command constants to avoid string allocations
      CMD_PUBLISH = "PUBLISH"
      CMD_SPUBLISH = "SPUBLISH"
      CMD_PUBSUB = "PUBSUB"

      # Frozen subcommands
      SUBCMD_CHANNELS = "CHANNELS"
      SUBCMD_NUMSUB = "NUMSUB"
      SUBCMD_NUMPAT = "NUMPAT"
      SUBCMD_SHARDCHANNELS = "SHARDCHANNELS"
      SUBCMD_SHARDNUMSUB = "SHARDNUMSUB"

      # Publish a message to a channel
      #
      # @param channel [String] Channel name
      # @param message [String] Message to publish
      # @return [Integer] Number of subscribers that received the message
      #
      # @example
      #   redis.publish("news", "Breaking news!")
      def publish(channel, message)
        call_2args(CMD_PUBLISH, channel, message)
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
      def subscribe(*channels, &)
        subscription_loop("SUBSCRIBE", channels, &)
      end

      # Subscribe with timeout
      #
      # Like subscribe, but with a timeout after which it automatically unsubscribes.
      #
      # @param timeout [Float] Timeout in seconds
      # @param channels [Array<String>] Channel names
      # @yield [SubscriptionHandler] Handler for setting up callbacks
      def subscribe_with_timeout(timeout, *channels, &)
        subscription_loop("SUBSCRIBE", channels, timeout: timeout, &)
      end

      # Unsubscribe from channels
      #
      # @param channels [Array<String>] Channels to unsubscribe from (empty = all)
      # @return [void]
      def unsubscribe(*channels)
        return unless @subscription_connection

        if channels.empty?
          @subscription_connection.write_command(["UNSUBSCRIBE"])
        else
          @subscription_connection.write_command(["UNSUBSCRIBE", *channels])
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
      def psubscribe(*patterns, &)
        subscription_loop("PSUBSCRIBE", patterns, &)
      end

      # Pattern subscribe with timeout
      #
      # @param timeout [Float] Timeout in seconds
      # @param patterns [Array<String>] Patterns to subscribe to
      # @yield [SubscriptionHandler] Handler for setting up callbacks
      def psubscribe_with_timeout(timeout, *patterns, &)
        subscription_loop("PSUBSCRIBE", patterns, timeout: timeout, &)
      end

      # Unsubscribe from patterns
      #
      # @param patterns [Array<String>] Patterns to unsubscribe from (empty = all)
      # @return [void]
      def punsubscribe(*patterns)
        return unless @subscription_connection

        if patterns.empty?
          @subscription_connection.write_command(["PUNSUBSCRIBE"])
        else
          @subscription_connection.write_command(["PUNSUBSCRIBE", *patterns])
        end
      end

      # List active channels
      #
      # @param pattern [String, nil] Optional glob-style pattern
      # @return [Array<String>] List of active channels
      def pubsub_channels(pattern = nil)
        if pattern
          call_2args(CMD_PUBSUB, SUBCMD_CHANNELS, pattern)
        else
          call_1arg(CMD_PUBSUB, SUBCMD_CHANNELS)
        end
      end

      # Get subscriber count for channels
      #
      # @param channels [Array<String>] Channel names
      # @return [Hash<String, Integer>] Channel => subscriber count
      def pubsub_numsub(*channels)
        return {} if channels.empty?

        # Fast path for single channel
        result = if channels.size == 1
                   call_2args(CMD_PUBSUB, SUBCMD_NUMSUB, channels[0])
                 else
                   call(CMD_PUBSUB, SUBCMD_NUMSUB, *channels)
                 end
        return result if result.is_a?(Hash)

        Hash[*result]
      end

      # Get pattern subscriber count
      #
      # @return [Integer] Number of pattern subscriptions
      def pubsub_numpat
        call_1arg(CMD_PUBSUB, SUBCMD_NUMPAT)
      end

      # List active shard channels (Redis 7+)
      #
      # @param pattern [String, nil] Optional glob-style pattern
      # @return [Array<String>] List of active shard channels
      def pubsub_shardchannels(pattern = nil)
        if pattern
          call_2args(CMD_PUBSUB, SUBCMD_SHARDCHANNELS, pattern)
        else
          call_1arg(CMD_PUBSUB, SUBCMD_SHARDCHANNELS)
        end
      end

      # Get shard channel subscriber counts (Redis 7+)
      #
      # @param channels [Array<String>] Channel names
      # @return [Hash<String, Integer>] Channel => subscriber count
      def pubsub_shardnumsub(*channels)
        return {} if channels.empty?

        # Fast path for single channel
        result = if channels.size == 1
                   call_2args(CMD_PUBSUB, SUBCMD_SHARDNUMSUB, channels[0])
                 else
                   call(CMD_PUBSUB, SUBCMD_SHARDNUMSUB, *channels)
                 end
        return result if result.is_a?(Hash)

        Hash[*result]
      end

      # Publish to a shard channel (Redis 7.0+)
      #
      # Sharded pubsub routes messages based on the channel's key slot,
      # ensuring that messages are delivered to clients connected to the
      # node responsible for that slot.
      #
      # @param shardchannel [String] Shard channel name
      # @param message [String] Message to publish
      # @return [Integer] Number of subscribers that received the message
      #
      # @example
      #   redis.spublish("user:{123}:updates", "profile_updated")
      def spublish(shardchannel, message)
        call_2args(CMD_SPUBLISH, shardchannel, message)
      end

      # Subscribe to shard channels (Redis 7.0+)
      #
      # Subscribes to the given shard channels and enters subscription mode.
      # Sharded channels are distributed to specific nodes based on key slot.
      #
      # @param shardchannels [Array<String>] Shard channel names to subscribe to
      # @yield [SubscriptionHandler] Handler for setting up callbacks
      #
      # @example
      #   redis.ssubscribe("user:{123}:updates") do |on|
      #     on.ssubscribe do |channel, count|
      #       puts "Subscribed to shard channel #{channel}"
      #     end
      #
      #     on.smessage do |channel, message|
      #       puts "#{channel}: #{message}"
      #     end
      #   end
      def ssubscribe(*shardchannels, &)
        subscription_loop("SSUBSCRIBE", shardchannels, sharded: true, &)
      end

      # Shard subscribe with timeout (Redis 7.0+)
      #
      # @param timeout [Float] Timeout in seconds
      # @param shardchannels [Array<String>] Shard channel names
      # @yield [SubscriptionHandler] Handler for setting up callbacks
      def ssubscribe_with_timeout(timeout, *shardchannels, &)
        subscription_loop("SSUBSCRIBE", shardchannels, timeout: timeout, sharded: true, &)
      end

      # Unsubscribe from shard channels (Redis 7.0+)
      #
      # @param shardchannels [Array<String>] Shard channels to unsubscribe from (empty = all)
      # @return [void]
      def sunsubscribe(*shardchannels)
        return unless @subscription_connection

        if shardchannels.empty?
          @subscription_connection.write_command(["SUNSUBSCRIBE"])
        else
          @subscription_connection.write_command(["SUNSUBSCRIBE", *shardchannels])
        end
      end

      UNSUBSCRIBE_COMMANDS = {
        "SUBSCRIBE" => "UNSUBSCRIBE",
        "PSUBSCRIBE" => "PUNSUBSCRIBE",
        "SSUBSCRIBE" => "SUNSUBSCRIBE",
      }.freeze

      # Minimum read timeout - prevents negative/zero timeouts after deadline passes,
      # ensuring we can still read unsubscribe confirmations.
      MIN_READ_TIMEOUT = 0.1

      private

      # Main subscription loop
      def subscription_loop(command, targets, timeout: nil, sharded: false) # rubocop:disable Lint/UnusedMethodArgument
        handler = SubscriptionHandler.new
        yield handler if block_given?

        setup_subscription_connection(command, targets)

        deadline = timeout ? Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout : nil
        unsubscribe_cmd = UNSUBSCRIBE_COMMANDS[command]

        process_subscription_messages(handler, unsubscribe_cmd, timeout, deadline)
      ensure
        cleanup_subscription_connection
      end

      # Set up the subscription connection and send subscribe command
      def setup_subscription_connection(command, targets)
        ensure_connected
        @subscription_connection = @connection
        @subscription_connection.write_command([command, *targets])
      end

      # Clean up subscription connection after subscription ends.
      # Drains any remaining unsubscribe confirmations to ensure the connection
      # properly exits pub/sub mode for reuse (redis-rb #1259).
      def cleanup_subscription_connection
        drain_subscription_state if @subscription_connection
        @subscription_connection = nil
      end

      # Drain remaining subscription messages to ensure the connection exits pub/sub mode.
      # After timeout, the UNSUBSCRIBE may have been sent but the confirmation not yet read.
      def drain_subscription_state
        3.times do
          message = @subscription_connection.read_response(timeout: 0.5)
          next unless message.is_a?(Array)

          type = message[0]
          if %w[unsubscribe punsubscribe sunsubscribe].include?(type) && message[2].to_i.zero?
            break # All channels unsubscribed, connection is clean
          end
        rescue TimeoutError, ConnectionError
          break
        end
      end

      # Process subscription messages in a loop until fully unsubscribed
      def process_subscription_messages(handler, unsubscribe_cmd, timeout, deadline)
        loop do
          check_subscription_timeout(unsubscribe_cmd, deadline)
          message = read_subscription_message(timeout, deadline)
          break if message == :break
          next if message == :next

          break unless dispatch_subscription_message(handler, message)
        end
      end

      # Check if the subscription has timed out and send unsubscribe if so
      def check_subscription_timeout(unsubscribe_cmd, deadline)
        return unless deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        @subscription_connection.write_command([unsubscribe_cmd])
      end

      # Read the next subscription message, handling timeouts
      def read_subscription_message(timeout, deadline)
        read_timeout = compute_read_timeout(timeout, deadline)
        message = @subscription_connection.read_response(timeout: read_timeout)
        return :break unless message.is_a?(Array) && !message.empty?

        message
      rescue TimeoutError
        deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline ? :next : :break
      rescue ConnectionError
        :break
      end

      def compute_read_timeout(timeout, deadline)
        result = if timeout
                   [1.0, timeout].min
                 elsif deadline
                   [1.0, deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)].min
                 else
                   3600.0
                 end
        # Never return negative or zero timeout - need at least MIN_READ_TIMEOUT
        # to read unsubscribe confirmations after deadline passes
        [result, MIN_READ_TIMEOUT].max
      end

      # Dispatch a subscription message to the appropriate handler callback
      # @return [Boolean] false if the loop should break
      def dispatch_subscription_message(handler, message)
        type = message[0]
        case type
        when "subscribe", "psubscribe", "ssubscribe"
          handler.call_subscribe(type.to_sym, message[1], message[2].to_i)
        when "unsubscribe", "punsubscribe", "sunsubscribe"
          handler.call_unsubscribe(type.to_sym, message[1], message[2].to_i)
          return false if message[2].to_i.zero?
        when "message"
          handler.call_message(message[1], message[2])
        when "pmessage"
          handler.call_pmessage(message[1], message[2], message[3])
        when "smessage"
          handler.call_smessage(message[1], message[2])
        end
        true
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

        # Set callback for ssubscribe events (Redis 7.0+)
        def ssubscribe(&block)
          @callbacks[:ssubscribe] = block
        end

        # Set callback for unsubscribe events
        def unsubscribe(&block)
          @callbacks[:unsubscribe] = block
        end

        # Set callback for punsubscribe events
        def punsubscribe(&block)
          @callbacks[:punsubscribe] = block
        end

        # Set callback for sunsubscribe events (Redis 7.0+)
        def sunsubscribe(&block)
          @callbacks[:sunsubscribe] = block
        end

        # Set callback for message events
        def message(&block)
          @callbacks[:message] = block
        end

        # Set callback for pmessage events
        def pmessage(&block)
          @callbacks[:pmessage] = block
        end

        # Set callback for smessage events (Redis 7.0+, sharded pubsub)
        def smessage(&block)
          @callbacks[:smessage] = block
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

        # @private
        def call_smessage(channel, message)
          @callbacks[:smessage]&.call(channel, message)
        end
      end
    end
  end
end
