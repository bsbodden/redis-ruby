# frozen_string_literal: true

require "thread"

module RedisRuby
  # Background subscriber for Redis Pub/Sub
  #
  # Provides a way to run Pub/Sub subscriptions in a background thread,
  # freeing the main thread for other work.
  #
  # @example Basic background subscription
  #   subscriber = RedisRuby::Subscriber.new(client)
  #
  #   subscriber.on_message do |channel, message|
  #     puts "Received: #{message} on #{channel}"
  #   end
  #
  #   subscriber.subscribe("events")
  #   thread = subscriber.run_in_thread
  #
  #   # ... do other work ...
  #
  #   subscriber.stop
  #   thread.join
  #
  # @example With pattern subscriptions
  #   subscriber = RedisRuby::Subscriber.new(client)
  #
  #   subscriber.on_pmessage do |pattern, channel, message|
  #     puts "#{pattern} matched #{channel}: #{message}"
  #   end
  #
  #   subscriber.psubscribe("user:*", "order:*")
  #   subscriber.run_in_thread
  #
  class Subscriber
    attr_reader :channels, :patterns, :thread

    # Initialize a new subscriber
    #
    # @param client [RedisRuby::Client] Redis client (a dedicated connection will be created)
    def initialize(client)
      @client_config = extract_client_config(client)
      @channels = []
      @patterns = []
      @shard_channels = []
      @callbacks = {}
      @running = false
      @stop_requested = false
      @mutex = Mutex.new
      @thread = nil
      @connection = nil
    end

    # Register callback for message events
    #
    # @yield [channel, message] Block to call when message received
    # @return [self]
    def on_message(&block)
      @callbacks[:message] = block
      self
    end

    # Register callback for pattern message events
    #
    # @yield [pattern, channel, message] Block to call when message received
    # @return [self]
    def on_pmessage(&block)
      @callbacks[:pmessage] = block
      self
    end

    # Register callback for shard message events
    #
    # @yield [channel, message] Block to call when message received
    # @return [self]
    def on_smessage(&block)
      @callbacks[:smessage] = block
      self
    end

    # Register callback for subscribe events
    #
    # @yield [channel, count] Block to call when subscribed
    # @return [self]
    def on_subscribe(&block)
      @callbacks[:subscribe] = block
      self
    end

    # Register callback for unsubscribe events
    #
    # @yield [channel, count] Block to call when unsubscribed
    # @return [self]
    def on_unsubscribe(&block)
      @callbacks[:unsubscribe] = block
      self
    end

    # Register callback for errors
    #
    # @yield [error] Block to call on error
    # @return [self]
    def on_error(&block)
      @callbacks[:error] = block
      self
    end

    # Subscribe to channels
    #
    # @param channels [Array<String>] Channel names
    # @return [self]
    def subscribe(*channels)
      @mutex.synchronize do
        @channels.concat(channels)
      end
      self
    end

    # Subscribe to patterns
    #
    # @param patterns [Array<String>] Pattern strings
    # @return [self]
    def psubscribe(*patterns)
      @mutex.synchronize do
        @patterns.concat(patterns)
      end
      self
    end

    # Subscribe to shard channels
    #
    # @param channels [Array<String>] Shard channel names
    # @return [self]
    def ssubscribe(*channels)
      @mutex.synchronize do
        @shard_channels.concat(channels)
      end
      self
    end

    # Run the subscriber in the current thread (blocking)
    #
    # @return [void]
    def run
      @running = true
      @stop_requested = false
      run_subscription_loop
    ensure
      @running = false
    end

    # Run the subscriber in a background thread
    #
    # @return [Thread] The background thread
    def run_in_thread
      @thread = Thread.new do
        run
      rescue StandardError => e
        handle_error(e)
      end
      @thread
    end

    # Stop the subscriber
    #
    # @param wait [Boolean] Wait for thread to finish
    # @return [void]
    def stop(wait: true)
      @stop_requested = true

      # Send unsubscribe commands to break the loop
      if @connection
        begin
          @connection.call("UNSUBSCRIBE") unless @channels.empty?
          @connection.call("PUNSUBSCRIBE") unless @patterns.empty?
          @connection.call("SUNSUBSCRIBE") unless @shard_channels.empty?
        rescue StandardError
          # Ignore errors during shutdown
        end
      end

      @thread&.join if wait
    end

    # Check if the subscriber is running
    #
    # @return [Boolean]
    def running?
      @running
    end

    # Check if stop has been requested
    #
    # @return [Boolean]
    def stop_requested?
      @stop_requested
    end

    private

    # Extract configuration from existing client
    def extract_client_config(client)
      {
        host: client.host,
        port: client.port,
        db: client.db,
        timeout: client.timeout
      }
    end

    # Create a dedicated connection for subscriptions
    def create_connection
      Connection::TCP.new(
        host: @client_config[:host],
        port: @client_config[:port],
        timeout: @client_config[:timeout]
      )
    end

    # Main subscription loop
    def run_subscription_loop
      @connection = create_connection

      # Select database if not default
      if @client_config[:db] && @client_config[:db] != 0
        @connection.call("SELECT", @client_config[:db])
      end

      # Send initial subscriptions
      send_subscriptions

      # Track subscription count
      subscriptions = 0

      # Read messages until stopped
      loop do
        break if @stop_requested && subscriptions.zero?

        begin
          message = read_message
          next unless message

          subscriptions = process_message(message, subscriptions)
        rescue TimeoutError
          next
        rescue StandardError => e
          handle_error(e)
          break
        end
      end
    ensure
      @connection&.close
      @connection = nil
    end

    # Send all subscription commands
    def send_subscriptions
      unless @channels.empty?
        @connection.call("SUBSCRIBE", *@channels)
      end

      unless @patterns.empty?
        @connection.call("PSUBSCRIBE", *@patterns)
      end

      unless @shard_channels.empty?
        @connection.call("SSUBSCRIBE", *@shard_channels)
      end
    end

    # Read a message from the connection
    def read_message
      @connection.instance_variable_get(:@decoder)&.decode
    end

    # Process a received message
    def process_message(message, subscriptions)
      return subscriptions unless message.is_a?(Array) && !message.empty?

      type = message[0]

      case type
      when "subscribe", "psubscribe", "ssubscribe"
        subscriptions = message[2].to_i
        call_callback(:subscribe, message[1], subscriptions)
      when "unsubscribe", "punsubscribe", "sunsubscribe"
        subscriptions = message[2].to_i
        call_callback(:unsubscribe, message[1], subscriptions)
      when "message"
        call_callback(:message, message[1], message[2])
      when "pmessage"
        call_callback(:pmessage, message[1], message[2], message[3])
      when "smessage"
        call_callback(:smessage, message[1], message[2])
      end

      subscriptions
    end

    # Call a registered callback
    def call_callback(type, *args)
      callback = @callbacks[type]
      callback&.call(*args)
    rescue StandardError => e
      handle_error(e)
    end

    # Handle an error
    def handle_error(error)
      if @callbacks[:error]
        @callbacks[:error].call(error)
      else
        # Default error handling - re-raise in main thread
        raise error unless @thread
      end
    end
  end
end
