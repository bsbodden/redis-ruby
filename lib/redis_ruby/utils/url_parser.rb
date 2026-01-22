# frozen_string_literal: true

require "uri"

module RedisRuby
  module Utils
    # Utility for parsing Redis URLs
    #
    # Supports the following URL schemes:
    # - redis://[[username:]password@]host[:port][/db]
    # - rediss://[[username:]password@]host[:port][/db] (TLS)
    # - unix://path/to/socket[?db=0]
    #
    # @example Parse a simple URL
    #   URLParser.parse("redis://localhost:6379/0")
    #   # => { host: "localhost", port: 6379, db: 0 }
    #
    # @example Parse a URL with authentication
    #   URLParser.parse("redis://:password@localhost:6379/1")
    #   # => { host: "localhost", port: 6379, db: 1, password: "password" }
    #
    module URLParser
      DEFAULT_HOST = "localhost"
      DEFAULT_PORT = 6379
      DEFAULT_DB = 0

      module_function

      # Parse a Redis URL into its components
      #
      # @param url [String] Redis URL to parse
      # @return [Hash] Parsed components
      # @option return [String] :host Redis host
      # @option return [Integer] :port Redis port
      # @option return [Integer] :db Database number
      # @option return [String, nil] :password Redis password
      # @option return [String, nil] :username Redis username
      # @option return [Boolean] :ssl Whether to use SSL/TLS
      # @option return [String, nil] :path Unix socket path (for unix:// URLs)
      def parse(url)
        uri = URI.parse(url)

        case uri.scheme
        when "redis"
          parse_tcp(uri).merge(ssl: false)
        when "rediss"
          parse_tcp(uri).merge(ssl: true)
        when "unix"
          parse_unix(uri)
        else
          raise ArgumentError, "Unsupported URL scheme: #{uri.scheme}"
        end
      end

      # Parse a TCP Redis URL (redis:// or rediss://)
      #
      # @param uri [URI] Parsed URI object
      # @return [Hash] Parsed components
      def parse_tcp(uri)
        {
          host: uri.host || DEFAULT_HOST,
          port: uri.port || DEFAULT_PORT,
          db: extract_db(uri.path),
          password: uri.password,
          username: uri.user == "" ? nil : uri.user,
        }
      end

      # Parse a Unix socket URL (unix://)
      #
      # @param uri [URI] Parsed URI object
      # @return [Hash] Parsed components
      def parse_unix(uri)
        # Unix socket path is in the host + path
        path = if uri.host
                 "/#{uri.host}#{uri.path}"
               else
                 uri.path
               end

        # Database can be specified as query param
        params = URI.decode_www_form(uri.query || "").to_h
        db = params["db"]&.to_i || DEFAULT_DB

        {
          path: path,
          db: db,
          password: uri.password,
          username: uri.user == "" ? nil : uri.user,
        }
      end

      # Extract database number from URL path
      #
      # @param path [String, nil] URL path (e.g., "/1")
      # @return [Integer] Database number
      def extract_db(path)
        return DEFAULT_DB if path.nil? || path.empty? || path == "/"

        path.delete_prefix("/").to_i
      end
    end
  end
end
