# frozen_string_literal: true

module RR
  # URL parsing and connection setup for Client
  #
  # Handles parsing of redis://, rediss://, and unix:// URLs
  # and creating the appropriate connection type.
  #
  # @api private
  module ClientUrlParsing
    protected

    # Access the underlying connection object
    # @api private
    attr_reader :connection

    private

    # Parse Redis URL
    # Supports: redis://, rediss://, unix://
    def parse_url(url)
      uri = URI.parse(url)

      case uri.scheme
      when "redis"
        parse_tcp_url(uri)
        @ssl = false
      when "rediss"
        parse_tcp_url(uri)
        @ssl = true
      when "unix"
        parse_unix_url(uri)
      else
        raise ArgumentError, "Unsupported URL scheme: #{uri.scheme}. Use redis://, rediss://, or unix://"
      end
    end

    # Parse TCP/SSL URL
    def parse_tcp_url(uri)
      @host = uri.host || self.class::DEFAULT_HOST
      @port = uri.port || self.class::DEFAULT_PORT
      @db = uri.path&.delete_prefix("/")&.to_i || self.class::DEFAULT_DB
      @password = uri.password
      @username = extract_username(uri)
      @path = nil
    end

    # Extract username from URI, handling edge cases
    def extract_username(uri)
      user = uri.user == "" ? nil : uri.user
      user = nil if user && uri.password && user == uri.password
      user
    end

    # Parse Unix socket URL
    def parse_unix_url(uri)
      @path = uri.path
      @host = nil
      @port = nil

      if uri.query
        params = URI.decode_www_form(uri.query).to_h
        @db = params["db"]&.to_i || self.class::DEFAULT_DB
      else
        @db = self.class::DEFAULT_DB
      end

      @password = uri.user
    end

    # Create appropriate connection based on configuration
    def create_connection
      if @path
        Connection::Unix.new(path: @path, timeout: @timeout)
      elsif @ssl
        Connection::SSL.new(host: @host, port: @port, timeout: @timeout, ssl_params: @ssl_params)
      else
        Connection::TCP.new(host: @host, port: @port, timeout: @timeout)
      end
    end

    # Authenticate with password (and optional username for ACL)
    def authenticate
      if @username
        @connection.call(self.class::CMD_AUTH, @username, @password)
      else
        @connection.call(self.class::CMD_AUTH, @password)
      end
    end

    # Select database
    def select_db
      @connection.call(self.class::CMD_SELECT, @db.to_s)
    end

    # Ensure connection is established, with fork safety.
    # After fork, discards the parent's connection and creates a fresh one
    # with full prelude replay (AUTH, SELECT).
    def ensure_connected
      # Fork safety: detect child process and force reconnection
      if @pid != Process.pid
        @connection = nil # Discard parent's connection (don't close - parent owns it)
        @pid = Process.pid
      end

      return if @connection&.connected?

      @connection = create_connection
      authenticate if @password
      select_db if @db.positive?
    end

    # Build a default retry policy from reconnect_attempts count
    def build_default_retry_policy(reconnect_attempts)
      if reconnect_attempts.positive?
        Retry.new(
          retries: reconnect_attempts,
          backoff: ExponentialWithJitterBackoff.new(base: 0.025, cap: 2.0),
          on_retry: ->(_error, _attempt) { @connection = nil }
        )
      else
        Retry.new(retries: 0)
      end
    end
  end
end
