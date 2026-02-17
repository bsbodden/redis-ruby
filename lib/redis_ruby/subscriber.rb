# frozen_string_literal: true

module RR
  # Background subscriber for Redis Pub/Sub
  #
  # Provides a way to run Pub/Sub subscriptions in a background thread,
  # freeing the main thread for other work.
  #
  # @example Basic background subscription
  #   subscriber = RR::Subscriber.new(client)
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
  #   subscriber = RR::Subscriber.new(client)
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
    # @param [RR::Client] Redis client (a dedicated connection will be created)
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
      send_unsubscribe_commands
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

    def send_unsubscribe_commands
      return unless @connection

      begin
        @connection.call("UNSUBSCRIBE") unless @channels.empty?
        @connection.call("PUNSUBSCRIBE") unless @patterns.empty?
        @connection.call("SUNSUBSCRIBE") unless @shard_channels.empty?
      rescue StandardError
        # Ignore errors during shutdown
      end
    end

    # Extract configuration from existing client
    def extract_client_config(client)
      config = {
        host: client.host,
        port: client.port,
        db: client.db,
        timeout: client.timeout,
      }

      # Extract password, ssl, ssl_params (not publicly exposed on Client)
      config[:password] = client.instance_variable_get(:@password) if client.instance_variable_defined?(:@password)
      config[:ssl] = client.instance_variable_get(:@ssl) if client.instance_variable_defined?(:@ssl)
      config[:ssl_params] = client.instance_variable_get(:@ssl_params) if client.instance_variable_defined?(:@ssl_params)

      config
    end

    # Create a dedicated connection for subscriptions
    def create_connection
      if @client_config[:ssl]
        Connection::SSL.new(
          host: @client_config[:host],
          port: @client_config[:port],
          timeout: @client_config[:timeout],
          ssl_params: @client_config[:ssl_params] || {}
        )
      else
        Connection::TCP.new(
          host: @client_config[:host],
          port: @client_config[:port],
          timeout: @client_config[:timeout]
        )
      end
    end

    # Main subscription loop
    def run_subscription_loop
      @connection = create_connection
      authenticate_if_needed
      select_database_if_needed
      send_subscriptions
      message_loop
    ensure
      @connection&.close
      @connection = nil
    end

    def authenticate_if_needed
      password = @client_config[:password]
      @connection.call("AUTH", password) if password
    end

    def select_database_if_needed
      db = @client_config[:db]
      @connection.call("SELECT", db) if db && db != 0
    end

    def message_loop
      subscriptions = 0
      catch(:break_loop) do
        loop do
          break if @stop_requested && subscriptions.zero?

          subscriptions = read_and_process(subscriptions)
        end
      end
    end

    def read_and_process(subscriptions)
      message = read_message
      return subscriptions unless message

      process_message(message, subscriptions)
    rescue TimeoutError
      subscriptions
    rescue StandardError => e
      handle_error(e)
      throw :break_loop
    end

    # Send all subscription commands
    def send_subscriptions
      @connection.call("SUBSCRIBE", *@channels) unless @channels.empty?

      @connection.call("PSUBSCRIBE", *@patterns) unless @patterns.empty?

      return if @shard_channels.empty?

      @connection.call("SSUBSCRIBE", *@shard_channels)
    end

    # Read a message from the connection
    def read_message
      @connection.instance_variable_get(:@decoder)&.decode
    end

    # Process a received message
    def process_message(message, subscriptions)
      return subscriptions unless message.is_a?(Array) && !message.empty?

      type = message[0]
      subscriptions = handle_subscription_change(message, subscriptions, type)
      dispatch_message_callback(message, type)
      subscriptions
    end

    def handle_subscription_change(message, subscriptions, type)
      case type
      when "subscribe", "psubscribe", "ssubscribe"
        subscriptions = message[2].to_i
        call_callback(:subscribe, message[1], subscriptions)
      when "unsubscribe", "punsubscribe", "sunsubscribe"
        subscriptions = message[2].to_i
        call_callback(:unsubscribe, message[1], subscriptions)
      end
      subscriptions
    end

    def dispatch_message_callback(message, type)
      case type
      when "message"  then call_callback(:message, message[1], message[2])
      when "pmessage" then call_callback(:pmessage, message[1], message[2], message[3])
      when "smessage" then call_callback(:smessage, message[1], message[2])
      end
    end

    # Call a registered callback
    def call_callback(type, *)
      callback = @callbacks[type]
      callback&.call(*)
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
