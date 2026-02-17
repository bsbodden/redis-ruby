# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module RR
  module HealthCheck
    # REST API-based health check for Redis Enterprise databases
    #
    # Queries the Redis Enterprise REST API to check database availability.
    # This provides a more comprehensive health check than PING, as it
    # verifies the database is accessible through the cluster management layer.
    #
    # @example Basic usage
    #   health_check = RR::HealthCheck::RestApi.new(
    #     rest_api_host: 'redis-enterprise.example.com',
    #     rest_api_port: 9443,
    #     database_id: 1,
    #     username: 'admin@example.com',
    #     password: 'secret'
    #   )
    #   
    #   healthy = health_check.check(connection)  # => true/false
    #
    # @example With custom timeout
    #   health_check = RR::HealthCheck::RestApi.new(
    #     rest_api_host: 'redis-enterprise.example.com',
    #     database_id: 1,
    #     username: 'admin@example.com',
    #     password: 'secret',
    #     timeout: 5.0  # 5 second timeout
    #   )
    class RestApi < Base
      # Default REST API port for Redis Enterprise
      DEFAULT_PORT = 9443

      # Default HTTP timeout in seconds
      DEFAULT_TIMEOUT = 3.0

      attr_reader :rest_api_host, :rest_api_port, :database_id, :timeout

      # Initialize REST API health check
      #
      # @param rest_api_host [String] Redis Enterprise cluster REST API hostname
      # @param rest_api_port [Integer] REST API port (default: 9443)
      # @param database_id [Integer] Database ID to check
      # @param username [String, nil] Basic auth username
      # @param password [String, nil] Basic auth password
      # @param timeout [Float] HTTP request timeout in seconds (default: 3.0)
      # @param use_ssl [Boolean] Use HTTPS (default: true)
      # @param verify_ssl [Boolean] Verify SSL certificates (default: true)
      def initialize(rest_api_host:, rest_api_port: DEFAULT_PORT, database_id:,
                     username: nil, password: nil,
                     timeout: DEFAULT_TIMEOUT,
                     use_ssl: true, verify_ssl: true)
        @rest_api_host = rest_api_host
        @rest_api_port = rest_api_port
        @database_id = database_id
        @username = username
        @password = password
        @timeout = timeout
        @use_ssl = use_ssl
        @verify_ssl = verify_ssl
      end

      # Check database health using REST API availability endpoint
      #
      # Queries the Redis Enterprise REST API endpoint:
      # GET /v1/bdbs/<database_id>/availability
      #
      # @param connection [Object] Redis connection (not used, but required by interface)
      # @return [Boolean] true if database is available, false otherwise
      def check(connection)
        uri = build_uri
        request = build_request(uri)
        
        response = execute_request(uri, request)
        parse_response(response)
      rescue StandardError => e
        warn "RestApi health check failed: #{e.message}" if $DEBUG
        false
      end

      private

      def build_uri
        scheme = @use_ssl ? 'https' : 'http'
        path = "/v1/bdbs/#{@database_id}/availability"
        
        URI("#{scheme}://#{@rest_api_host}:#{@rest_api_port}#{path}")
      end

      def build_request(uri)
        request = Net::HTTP::Get.new(uri)
        request['Accept'] = 'application/json'
        
        if @username && @password
          request.basic_auth(@username, @password)
        end
        
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
        
        # The API returns 200 OK if available, non-200 if not available
        response.code == '200'
      end
    end
  end
end

