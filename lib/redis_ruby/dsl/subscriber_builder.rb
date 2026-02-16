# frozen_string_literal: true

require "json"

module RR
  module DSL
    # Fluent builder for subscribing to Redis Pub/Sub channels
    #
    # Provides a chainable interface for setting up subscriptions with
    # automatic JSON decoding and support for patterns and sharded channels.
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
    class SubscriberBuilder
      # @private
      attr_reader :redis, :channels, :patterns, :shard_channels, :callbacks

      # Initialize a new subscriber builder
      #
      # @param [RR::Client] Redis client instance
      def initialize(redis)
        @redis = redis
        @channels = []
        @patterns = []
        @shard_channels = []
        @callbacks = {
          channels: {},
          patterns: {},
          shards: {},
        }
        @json_decode = {}
        @thread = nil
        @subscriber = nil
        @running = false
        @running_mutex = Mutex.new
        @running_cv = ConditionVariable.new
      end

      # Subscribe to one or more channels
      #
      # @param channels [Array<String, Symbol>] Channel names
      # @param json [Boolean] Automatically decode JSON messages
      # @yield [channel, message] Block to call when message received
      # @return [self] Returns self for chaining
      #
      # @example
      #   subscriber.on(:news, :sports) { |channel, msg| puts msg }
      #
      # @example With JSON decoding
      #   subscriber.on(:events, json: true) { |channel, data| process(data) }
      def on(*channels, json: false, &block)
        raise ArgumentError, "Block required" unless block_given?

        channels.each do |channel|
          channel_str = channel.to_s
          @channels << channel_str unless @channels.include?(channel_str)
          @callbacks[:channels][channel_str] = block
          @json_decode[channel_str] = json if json
        end

        self
      end

      # Subscribe to one or more patterns
      #
      # @param patterns [Array<String, Symbol>] Pattern strings
      # @param json [Boolean] Automatically decode JSON messages
      # @yield [pattern, channel, message] Block to call when message received
      # @return [self] Returns self for chaining
      #
      # @example
      #   subscriber.on_pattern("user:*", "order:*") { |pattern, ch, msg| puts msg }
      def on_pattern(*patterns, json: false, &block)
        raise ArgumentError, "Block required" unless block_given?

        patterns.each do |pattern|
          pattern_str = pattern.to_s
          @patterns << pattern_str unless @patterns.include?(pattern_str)
          @callbacks[:patterns][pattern_str] = block
          @json_decode[pattern_str] = json if json
        end

        self
      end

      # Subscribe to one or more shard channels (Redis 7.0+)
      #
      # @param channels [Array<String, Symbol>] Shard channel names
      # @param json [Boolean] Automatically decode JSON messages
      # @yield [channel, message] Block to call when message received
      # @return [self] Returns self for chaining
      #
      # @example
      #   subscriber.on_shard("user:{123}:updates") { |ch, msg| puts msg }
      def on_shard(*channels, json: false, &block)
        raise ArgumentError, "Block required" unless block_given?

        channels.each do |channel|
          channel_str = channel.to_s
          @shard_channels << channel_str unless @shard_channels.include?(channel_str)
          @callbacks[:shards][channel_str] = block
          @json_decode[channel_str] = json if json
        end

        self
      end

      # Run the subscriber in the current thread (blocking)
      #
      # This will block until all subscriptions are unsubscribed.
      #
      # @return [void]
      #
      # @example
      #   subscriber.on(:news) { |ch, msg| puts msg }.run
      def run
        setup_and_run_subscriptions
      end

      # Run the subscriber in a background thread
      #
      # Returns immediately while subscriptions run in the background.
      #
      # @return [Thread] The background thread
      #
      # @example
      #   thread = subscriber.on(:news) { |ch, msg| puts msg }.run_async
      #   # ... do other work ...
      #   subscriber.stop
      #   thread.join
      def run_async
        @thread = Thread.new do
          setup_and_run_subscriptions
        rescue StandardError => e
          warn "Subscriber error: #{e.message}"
          raise
        ensure
          @running_mutex.synchronize do
            @running = false
            @running_cv.broadcast
          end
        end
        # Wait until the subscriber is actually running before returning
        @running_mutex.synchronize do
          @running_cv.wait(@running_mutex) until @running || !@thread&.alive?
        end
        @thread
      end

      # Stop the subscriber
      #
      # Unsubscribes from all channels and stops the background thread if running.
      #
      # @param wait [Boolean] Wait for thread to finish
      # @return [void]
      def stop(wait: true)
        @subscriber&.stop(wait: wait)
        if wait && @thread
          @thread.join
          @running_mutex.synchronize { @running = false }
        end
      end

      # Check if the subscriber is running
      #
      # @return [Boolean]
      def running?
        @running
      end

      private

      # Set up and run subscriptions
      def setup_and_run_subscriptions
        validate_subscriptions!
        create_subscriber
        configure_subscriber_callbacks
        subscribe_to_channels
        @running_mutex.synchronize do
          @running = true
          @running_cv.broadcast
        end
        @subscriber.run
      end

      # Validate that at least one subscription is configured
      def validate_subscriptions!
        if @channels.empty? && @patterns.empty? && @shard_channels.empty?
          raise ArgumentError, "No subscriptions configured. Use on(), on_pattern(), or on_shard()"
        end
      end

      # Create the underlying Subscriber instance
      def create_subscriber
        @subscriber = RR::Subscriber.new(@redis)
      end

      # Configure callbacks on the subscriber
      def configure_subscriber_callbacks
        # Message callback
        @subscriber.on_message do |channel, message|
          callback = @callbacks[:channels][channel]
          next unless callback

          decoded_message = decode_if_needed(channel, message)
          callback.call(channel, decoded_message)
        end

        # Pattern message callback
        @subscriber.on_pmessage do |pattern, channel, message|
          callback = @callbacks[:patterns][pattern]
          next unless callback

          decoded_message = decode_if_needed(pattern, message)
          callback.call(pattern, channel, decoded_message)
        end

        # Shard message callback
        @subscriber.on_smessage do |channel, message|
          callback = @callbacks[:shards][channel]
          next unless callback

          decoded_message = decode_if_needed(channel, message)
          callback.call(channel, decoded_message)
        end
      end

      # Subscribe to all configured channels
      def subscribe_to_channels
        @subscriber.subscribe(*@channels) unless @channels.empty?
        @subscriber.psubscribe(*@patterns) unless @patterns.empty?
        @subscriber.ssubscribe(*@shard_channels) unless @shard_channels.empty?
      end

      # Decode message if JSON decoding is enabled for this channel/pattern
      def decode_if_needed(key, message)
        if @json_decode[key]
          JSON.parse(message)
        else
          message
        end
      rescue JSON::ParserError
        # If JSON parsing fails, return original message
        message
      end
    end
  end
end

