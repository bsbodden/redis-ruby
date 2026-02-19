# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module RR
  module HealthCheck
    # Lag-aware health check for Redis Enterprise Active-Active databases
    #
    # Queries the Redis Enterprise REST API to check database availability
    # and replication lag. This ensures databases are sufficiently synchronized
    # before failover operations, reducing the risk of data inconsistencies.
    #
    # Requires Redis Enterprise 8.0.2-17 or later for lag-aware availability API.
    #
    # @example Basic usage
    #   health_check = RR::HealthCheck::LagAware.new(
    #     rest_api_host: 'redis-enterprise.example.com',
    #     rest_api_port: 9443,
    #     database_id: 1,
    #     username: 'admin@example.com',
    #     password: 'secret'
    #   )
    #
    #   healthy = health_check.check(connection)  # => true/false
    #
    # @example Custom lag tolerance
    #   health_check = RR::HealthCheck::LagAware.new(
    #     rest_api_host: 'redis-enterprise.example.com',
    #     database_id: 1,
    #     lag_tolerance_ms: 200,  # 200ms tolerance
    #     username: 'admin@example.com',
    #     password: 'secret'
    #   )
    #
    # @example With custom timeout
    #   health_check = RR::HealthCheck::LagAware.new(
    #     rest_api_host: 'redis-enterprise.example.com',
    #     database_id: 1,
    #     username: 'admin@example.com',
    #     password: 'secret',
    #     timeout: 5.0  # 5 second timeout
    #   )
    class LagAware < Base
      # Default REST API port for Redis Enterprise
      DEFAULT_PORT = 9443

      # Default lag tolerance in milliseconds
      DEFAULT_LAG_TOLERANCE_MS = 100

      # Default HTTP timeout in seconds
      DEFAULT_TIMEOUT = 3.0

      attr_reader :rest_api_host, :rest_api_port, :database_id, :lag_tolerance_ms, :timeout

      # Initialize lag-aware health check
      #
      # @param rest_api_host [String] Redis Enterprise cluster REST API hostname
      # @param rest_api_port [Integer] REST API port (default: 9443)
      # @param database_id [Integer] Database ID to check
      # @param lag_tolerance_ms [Integer] Maximum acceptable lag in milliseconds (default: 100)
      # @param username [String, nil] Basic auth username
      # @param password [String, nil] Basic auth password
      # @param timeout [Float] HTTP request timeout in seconds (default: 3.0)
      # @param use_ssl [Boolean] Use HTTPS (default: true)
      # @param verify_ssl [Boolean] Verify SSL certificates (default: true)
      def initialize(rest_api_host:, database_id:, rest_api_port: DEFAULT_PORT,
                     lag_tolerance_ms: DEFAULT_LAG_TOLERANCE_MS,
                     username: nil, password: nil,
                     timeout: DEFAULT_TIMEOUT,
                     use_ssl: true, verify_ssl: true)
        super()
        @rest_api_host = rest_api_host
        @rest_api_port = rest_api_port
        @database_id = database_id
        @lag_tolerance_ms = lag_tolerance_ms
        @username = username
        @password = password
        @timeout = timeout
        @use_ssl = use_ssl
        @verify_ssl = verify_ssl
      end

      # Check database health using lag-aware availability API
      #
      # Queries the Redis Enterprise REST API endpoint:
      # GET /v1/bdbs/<database_id>/availability?extend_check=lag&availability_lag_tolerance_ms=<threshold>
      #
      # @param connection [Object] Redis connection (not used, but required by interface)
      # @return [Boolean] true if database is available and lag is within tolerance, false otherwise
      def check(_connection)
        uri = build_uri
        request = build_request(uri)

        response = execute_request(uri, request)
        parse_response(response)
      rescue StandardError => e
        warn "LagAware health check failed: #{e.message}" if $DEBUG
        false
      end

      private

      def build_uri
        scheme = @use_ssl ? "https" : "http"
        path = "/v1/bdbs/#{@database_id}/availability"
        query = "extend_check=lag&availability_lag_tolerance_ms=#{@lag_tolerance_ms}"

        URI("#{scheme}://#{@rest_api_host}:#{@rest_api_port}#{path}?#{query}")
      end

      def build_request(uri)
        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "application/json"

        request.basic_auth(@username, @password) if @username && @password

        request
      end

      def execute_request(uri, request)
        Net::HTTP.start(
          uri.hostname,
          uri.port,
          use_ssl: @use_ssl,
          verify_mode: @verify_ssl ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE,
          open_timeout: @timeout,
          read_timeout: @timeout
        ) do |http|
          http.request(request)
        end
      end

      def parse_response(response)
        return false unless response.is_a?(Net::HTTPSuccess)

        # The API returns 200 OK if available, non-200 if not available or lag exceeds tolerance
        response.code == "200"
      end
    end
  end
end
