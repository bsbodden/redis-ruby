# frozen_string_literal: true

module RR
  # Redis Enterprise Discovery Service client
  #
  # The Discovery Service provides IP-based connection management for Redis Enterprise databases.
  # It uses the Redis Sentinel API to discover which node hosts a database endpoint.
  #
  # The Discovery Service runs on port 8001 on each node of a Redis Enterprise cluster.
  #
  # @example Basic usage
  #   discovery = RR::DiscoveryService.new(
  #     nodes: [
  #       { host: "node1.redis.example.com", port: 8001 },
  #       { host: "node2.redis.example.com", port: 8001 },
  #       { host: "node3.redis.example.com", port: 8001 }
  #     ],
  #     database_name: "my-database"
  #   )
  #
  #   endpoint = discovery.discover_endpoint
  #   # => { host: "10.0.0.45", port: 12000 }
  #
  # @example Internal endpoint
  #   discovery = RR::DiscoveryService.new(
  #     nodes: [{ host: "node1.redis.example.com" }],
  #     database_name: "my-database",
  #     internal: true
  #   )
  #
  #   endpoint = discovery.discover_endpoint
  #   # => { host: "10.0.0.45", port: 12000 }
  #
  class DiscoveryService
    # Default Discovery Service port
    DEFAULT_PORT = 8001

    # Default timeout for discovery queries
    DEFAULT_TIMEOUT = 5.0

    # @return [Array<Hash>] List of discovery service nodes
    attr_reader :nodes

    # @return [String] Database name to discover
    attr_reader :database_name

    # @return [Float] Timeout for discovery queries
    attr_reader :timeout

    # Initialize a new Discovery Service client
    #
    # @param nodes [Array<Hash>] List of discovery service nodes with :host and optional :port
    # @param database_name [String] Name of the database to discover
    # @param internal [Boolean] Whether to discover internal endpoint (default: false)
    # @param timeout [Float] Timeout for discovery queries (default: 5.0)
    #
    # @raise [ArgumentError] if nodes or database_name is missing
    #
    # @example
    #   discovery = RR::DiscoveryService.new(
    #     nodes: [
    #       { host: "node1.redis.example.com", port: 8001 },
    #       { host: "node2.redis.example.com", port: 8001 }
    #     ],
    #     database_name: "my-database"
    #   )
    def initialize(nodes:, database_name:, internal: false, timeout: DEFAULT_TIMEOUT)
      raise ArgumentError, "nodes is required" if nodes.nil? || nodes.empty?
      raise ArgumentError, "database_name is required" if database_name.nil? || database_name.empty?

      @nodes = nodes.map do |node|
        {
          host: node[:host],
          port: node[:port] || DEFAULT_PORT
        }
      end

      @database_name = internal ? "#{database_name}@internal" : database_name
      @timeout = timeout
    end

    # Discover the endpoint for the database
    #
    # Queries the Discovery Service nodes to find the current endpoint for the database.
    # Tries each node in order until one succeeds.
    #
    # @return [Hash] Endpoint with :host and :port keys
    # @raise [DiscoveryServiceError] if all nodes fail or database is not found
    #
    # @example
    #   endpoint = discovery.discover_endpoint
    #   # => { host: "10.0.0.45", port: 12000 }
    def discover_endpoint
      last_error = nil

      @nodes.each do |node|
        begin
          connection = create_connection(
            host: node[:host],
            port: node[:port],
            timeout: @timeout
          )

          result = connection.call("SENTINEL", "get-master-addr-by-name", @database_name)

          connection.close

          if result.nil?
            raise DiscoveryServiceError, "Database '#{@database_name}' not found in discovery service"
          end

          return {
            host: result[0],
            port: result[1].to_i
          }
        rescue StandardError => e
          last_error = e
          connection&.close rescue nil
          next
        end
      end

      raise DiscoveryServiceError, "Failed to discover endpoint for '#{@database_name}': #{last_error&.message}"
    end

    private

    # Create a connection to a discovery service node
    # @api private
    def create_connection(host:, port:, timeout:)
      Connection::TCP.new(host: host, port: port, timeout: timeout)
    end
  end

  # Error raised when discovery service fails
  class DiscoveryServiceError < Error
  end
end

