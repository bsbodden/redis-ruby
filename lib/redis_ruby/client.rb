# frozen_string_literal: true

require "uri"
require_relative "client_url_parsing"

module RR
  # The main synchronous Redis client
  #
  # Pure Ruby implementation using RESP3 protocol.
  # Supports TCP, SSL/TLS, and Unix socket connections.
  #
  # @example Basic TCP usage
  #   client = RR::Client.new(url: "redis://localhost:6379")
  #   client.set("key", "value")
  #   client.get("key") # => "value"
  #
  # @example SSL/TLS connection
  #   client = RR::Client.new(url: "rediss://redis.example.com:6379")
  #
  # @example Unix socket connection
  #   client = RR::Client.new(url: "unix:///var/run/redis/redis.sock")
  #
  class Client
    include Commands::Strings
    include Commands::Keys
    include Commands::Hashes
    include Commands::Lists
    include Commands::Sets
    include Commands::SortedSets
    include Commands::Geo
    include Commands::HyperLogLog
    include Commands::Bitmap
    include Commands::Scripting
    include Commands::JSON
    include Commands::Search
    include Commands::Probabilistic
    include Commands::TimeSeries
    include Commands::VectorSet
    include Commands::Streams
    include Commands::PubSub
    include Commands::Functions
    include Commands::ACL
    include Commands::Server
    include ClientUrlParsing

    attr_reader :host, :port, :path, :db, :timeout

    DEFAULT_HOST = "localhost"
    DEFAULT_PORT = 6379
    DEFAULT_DB = 0
    DEFAULT_TIMEOUT = 5.0

    # Frozen command constants to avoid string allocations
    CMD_PING = "PING"
    CMD_WATCH = "WATCH"
    CMD_UNWATCH = "UNWATCH"
    CMD_DISCARD = "DISCARD"
    CMD_AUTH = "AUTH"
    CMD_SELECT = "SELECT"

    # Initialize a new Redis client
    #
    # @param url [String, nil] Redis URL (redis://, rediss://, unix://)
    # @param host [String] Redis host (for TCP/SSL)
    # @param port [Integer] Redis port (for TCP/SSL)
    # @param path [String, nil] Unix socket path
    # @param db [Integer] Redis database number
    # @param password [String, nil] Redis password
    # @param username [String, nil] Redis username (ACL, Redis 6+)
    # @param timeout [Float] Connection timeout in seconds
    # @param ssl [Boolean] Enable SSL/TLS
    # @param ssl_params [Hash] SSL parameters for OpenSSL::SSL::SSLContext
    # @param [RR::Retry, nil] Retry policy for transient failures
    # @param reconnect_attempts [Integer] Shorthand for retry count (creates default policy)
    # @param decode_responses [Boolean] Auto-decode binary responses to the specified encoding
    # @param encoding [String] Encoding for decoded responses (default: "UTF-8")
    # @param instrumentation [RR::Instrumentation, nil] Instrumentation instance for metrics
    # @param circuit_breaker [RR::CircuitBreaker, nil] Circuit breaker for failure protection
    def initialize(url: nil, host: DEFAULT_HOST, port: DEFAULT_PORT, path: nil,
                   db: DEFAULT_DB, password: nil, username: nil, timeout: DEFAULT_TIMEOUT,
                   ssl: false, ssl_params: {}, retry_policy: nil, reconnect_attempts: 0,
                   decode_responses: false, encoding: "UTF-8", instrumentation: nil,
                   circuit_breaker: nil)
      @host = host
      @port = port
      @path = path
      @db = db
      @password = password
      @username = username
      @ssl = ssl
      @timeout = timeout
      @ssl_params = ssl_params
      @connection = nil
      @decode_responses = decode_responses
      @encoding = encoding
      @instrumentation = instrumentation
      @circuit_breaker = circuit_breaker

      parse_url(url) if url

      @retry_policy = retry_policy || build_default_retry_policy(reconnect_attempts)
    end

    # Execute a Redis command
    #
    # @param command [String] Command name
    # @param args [Array] Command arguments
    # @return [Object] Command result
    def call(command, *args)
      execute_with_protection(command, args)
    end

    # Fast path for single-argument commands (GET, DEL, EXISTS, etc.)
    # @api private
    def call_1arg(command, arg)
      if @circuit_breaker
        @circuit_breaker.call do
          execute_1arg_with_instrumentation(command, arg)
        end
      else
        execute_1arg_with_instrumentation(command, arg)
      end
    end

    # Fast path for two-argument commands (HGET, simple SET, etc.)
    # @api private
    def call_2args(command, arg1, arg2)
      if @circuit_breaker
        @circuit_breaker.call do
          execute_2args_with_instrumentation(command, arg1, arg2)
        end
      else
        execute_2args_with_instrumentation(command, arg1, arg2)
      end
    end

    # Fast path for three-argument commands (HSET, etc.)
    # @api private
    def call_3args(command, arg1, arg2, arg3)
      if @circuit_breaker
        @circuit_breaker.call do
          execute_3args_with_instrumentation(command, arg1, arg2, arg3)
        end
      else
        execute_3args_with_instrumentation(command, arg1, arg2, arg3)
      end
    end

    # Ping the Redis server
    # @return [String] "PONG"
    def ping
      call(CMD_PING)
    end

    # Execute commands in a pipeline
    #
    # @yield [Pipeline] pipeline object to queue commands
    # @return [Array] results from all commands
    def pipelined
      ensure_connected
      pipeline = Pipeline.new(@connection)
      yield pipeline
      results = pipeline.execute
      results.each { |r| raise r if r.is_a?(CommandError) }
      results
    end

    # Execute commands in a transaction (MULTI/EXEC)
    #
    # @yield [Transaction] transaction object to queue commands
    # @return [Array, nil] results from all commands, or nil if aborted
    def multi
      ensure_connected
      transaction = Transaction.new(@connection)
      yield transaction
      results = transaction.execute
      return nil if results.nil?

      raise results if results.is_a?(CommandError)

      results.each { |r| raise r if r.is_a?(CommandError) }
      results
    end

    # Watch keys for changes (optimistic locking)
    #
    # @param keys [Array<String>] keys to watch
    # @yield [optional] block to execute while watching
    # @return [Object] result of block, or "OK" if no block
    def watch(*keys, &block)
      ensure_connected
      result = @connection.call(CMD_WATCH, *keys)
      return result unless block

      begin
        yield self
      ensure
        @connection.call(CMD_UNWATCH)
      end
    end

    # Discard a transaction in progress
    # @return [String] "OK"
    def discard
      ensure_connected
      call(CMD_DISCARD)
    end

    # Unwatch all watched keys
    # @return [String] "OK"
    def unwatch
      ensure_connected
      call(CMD_UNWATCH)
    end

    # Close the connection
    def close
      @connection&.close
      @connection = nil
    end

    alias disconnect close
    alias quit close

    # Check if connected
    # @return [Boolean]
    def connected?
      @connection&.connected? || false
    end

    # Check if using SSL/TLS
    # @return [Boolean]
    def ssl?
      @ssl || false
    end

    # Check if using Unix socket
    # @return [Boolean]
    def unix?
      !@path.nil?
    end

    # Check if the connection is healthy
    #
    # @param command [String] Command to use for health check (default: "PING")
    # @return [Boolean] true if healthy, false otherwise
    def healthy?(command: "PING")
      health_check(command: command)
    end

    # Perform a health check
    #
    # @param command [String] Command to use for health check (default: "PING")
    # @return [Boolean] true if healthy, false otherwise
    def health_check(command: "PING")
      # Check circuit breaker state first
      return false if @circuit_breaker && @circuit_breaker.state == :open

      # Try to execute a simple command
      begin
        call(command)
        true
      rescue
        false
      end
    end

    # Register a callback for connection lifecycle events
    #
    # @param event_type [Symbol] Event type (:connected, :disconnected, :reconnected, :error)
    # @param callback [Proc] Callback to invoke when event occurs
    # @return [void]
    # @raise [ArgumentError] if event_type is invalid
    #
    # @example Register a callback
    #   client.register_connection_callback(:connected) do |event|
    #     puts "Connected to #{event[:host]}:#{event[:port]}"
    #   end
    def register_connection_callback(event_type, callback = nil, &block)
      ensure_connected
      @connection.register_callback(event_type, callback, &block)
    end

    # Deregister a callback for connection lifecycle events
    #
    # @param event_type [Symbol] Event type
    # @param callback [Proc] Callback to remove
    # @return [void]
    def deregister_connection_callback(event_type, callback)
      ensure_connected
      @connection.deregister_callback(event_type, callback)
    end

    private

    # Execute command with circuit breaker and instrumentation protection
    def execute_with_protection(command, args)
      if @circuit_breaker
        @circuit_breaker.call do
          execute_with_instrumentation(command, args)
        end
      else
        execute_with_instrumentation(command, args)
      end
    end

    # Execute command with optional instrumentation
    def execute_with_instrumentation(command, args)
      if @instrumentation
        call_with_instrumentation(command, args)
      else
        call_without_instrumentation(command, args)
      end
    end

    # Execute 1-arg command with optional instrumentation
    def execute_1arg_with_instrumentation(command, arg)
      if @instrumentation
        call_with_instrumentation(command, [arg])
      else
        call_1arg_without_instrumentation(command, arg)
      end
    end

    # Execute 2-args command with optional instrumentation
    def execute_2args_with_instrumentation(command, arg1, arg2)
      if @instrumentation
        call_with_instrumentation(command, [arg1, arg2])
      else
        call_2args_without_instrumentation(command, arg1, arg2)
      end
    end

    # Execute 3-args command with optional instrumentation
    def execute_3args_with_instrumentation(command, arg1, arg2, arg3)
      if @instrumentation
        call_with_instrumentation(command, [arg1, arg2, arg3])
      else
        call_3args_without_instrumentation(command, arg1, arg2, arg3)
      end
    end

    # Execute command with instrumentation
    def call_with_instrumentation(command, args)
      # Trigger before callbacks
      @instrumentation.before_callbacks.each { |cb| cb.call(command, args) }

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      error = nil

      begin
        result = call_without_instrumentation(command, args)
      rescue => e
        error = e
        raise
      ensure
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        @instrumentation.record_command(command, duration, error: error)
        @instrumentation.after_callbacks.each { |cb| cb.call(command, args, duration) }
      end

      result
    end

    # Execute command without instrumentation
    def call_without_instrumentation(command, args)
      @retry_policy.call do
        ensure_connected
        result = @connection.call_direct(command, *args)
        raise result if result.is_a?(CommandError)

        @decode_responses ? decode_result(result) : result
      end
    end

    # Fast path without instrumentation
    def call_1arg_without_instrumentation(command, arg)
      @retry_policy.call do
        ensure_connected
        result = @connection.call_1arg(command, arg)
        raise result if result.is_a?(CommandError)

        @decode_responses ? decode_result(result) : result
      end
    end

    def call_2args_without_instrumentation(command, arg1, arg2)
      @retry_policy.call do
        ensure_connected
        result = @connection.call_2args(command, arg1, arg2)
        raise result if result.is_a?(CommandError)

        @decode_responses ? decode_result(result) : result
      end
    end

    def call_3args_without_instrumentation(command, arg1, arg2, arg3)
      @retry_policy.call do
        ensure_connected
        result = @connection.call_3args(command, arg1, arg2, arg3)
        raise result if result.is_a?(CommandError)

        @decode_responses ? decode_result(result) : result
      end
    end

    # Decode a result to the configured encoding
    def decode_result(result)
      case result
      when String
        result.frozen? ? result.encode(@encoding) : result.force_encoding(@encoding)
      when Array
        result.map { |v| decode_result(v) }
      when Hash
        result.each_with_object({}) { |(k, v), h| h[decode_result(k)] = decode_result(v) }
      else
        result
      end
    end
  end
end
