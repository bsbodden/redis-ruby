# frozen_string_literal: true

require "resolv"
require "monitor"

module RR
  # DNS resolver for Redis connections with support for multiple A records
  # and load balancing strategies.
  #
  # This is particularly useful for:
  # - Redis Enterprise Active-Active databases with multiple endpoints
  # - Load balancing across multiple Redis instances
  # - High availability with automatic failover
  #
  # @example Basic usage
  #   resolver = RR::DNSResolver.new(hostname: "redis.example.com")
  #   ip = resolver.resolve  # Returns one IP from DNS A records
  #
  # @example Round-robin load balancing
  #   resolver = RR::DNSResolver.new(
  #     hostname: "redis.example.com",
  #     strategy: :round_robin
  #   )
  #   ip1 = resolver.resolve  # 10.0.0.1
  #   ip2 = resolver.resolve  # 10.0.0.2
  #   ip3 = resolver.resolve  # 10.0.0.3
  #   ip4 = resolver.resolve  # 10.0.0.1 (wraps around)
  #
  # @example Random load balancing
  #   resolver = RR::DNSResolver.new(
  #     hostname: "redis.example.com",
  #     strategy: :random
  #   )
  #   ip = resolver.resolve  # Random IP from DNS A records
  #
  class DNSResolver
    include MonitorMixin

    VALID_STRATEGIES = %i[round_robin random].freeze

    attr_reader :hostname, :strategy

    # Initialize a new DNS resolver
    #
    # @param hostname [String] The hostname to resolve
    # @param strategy [Symbol] Load balancing strategy (:round_robin or :random)
    # @raise [ArgumentError] if hostname is missing or strategy is invalid
    def initialize(hostname:, strategy: :round_robin)
      super() # Initialize MonitorMixin

      raise ArgumentError, "hostname is required" if hostname.nil? || hostname.empty?
      unless VALID_STRATEGIES.include?(strategy)
        raise ArgumentError, "strategy must be one of #{VALID_STRATEGIES.inspect}"
      end

      @hostname = hostname
      @strategy = strategy
      @ips = []
      @index = 0
    end

    # Resolve hostname to a single IP address using the configured strategy
    #
    # @return [String] An IP address
    # @raise [DNSResolutionError] if no IP addresses are found
    def resolve
      synchronize do
        refresh_if_needed

        raise DNSResolutionError, "No IP addresses found for #{@hostname}" if @ips.empty?

        case @strategy
        when :round_robin
          ip = @ips[@index]
          @index = (@index + 1) % @ips.size
          ip
        when :random
          @ips.sample
        end
      end
    end

    # Resolve hostname to all IP addresses
    #
    # @return [Array<String>] Array of IP addresses
    def resolve_all
      begin
        dns = Resolv::DNS.new
        addresses = dns.getaddresses(@hostname)
        addresses.map(&:to_s)
      rescue Resolv::ResolvError, Resolv::ResolvTimeout
        # DNS resolution failed, return empty array
        []
      ensure
        dns&.close
      end
    end

    # Refresh the cached IP addresses by re-resolving the hostname
    #
    # @return [Array<String>] The new list of IP addresses
    def refresh
      synchronize do
        @ips = resolve_all
        @index = 0
        @ips
      end
    end

    private

    # Refresh IPs if cache is empty
    def refresh_if_needed
      refresh if @ips.empty?
    end
  end

  # Error raised when DNS resolution fails
  class DNSResolutionError < Error; end
end

