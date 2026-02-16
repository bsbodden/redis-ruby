# frozen_string_literal: true

require_relative "../test_helper"

module RR
  class DNSResolverTest < Minitest::Test
    # ============================================================
    # Initialization
    # ============================================================

    def test_initialize_with_hostname
      resolver = DNSResolver.new(hostname: "redis.example.com")

      assert_equal "redis.example.com", resolver.hostname
      assert_equal :round_robin, resolver.strategy
    end

    def test_initialize_with_custom_strategy
      resolver = DNSResolver.new(hostname: "redis.example.com", strategy: :random)

      assert_equal :random, resolver.strategy
    end

    def test_initialize_requires_hostname
      assert_raises(ArgumentError) do
        DNSResolver.new
      end
    end

    def test_initialize_validates_strategy
      assert_raises(ArgumentError) do
        DNSResolver.new(hostname: "redis.example.com", strategy: :invalid)
      end
    end

    # ============================================================
    # resolve
    # ============================================================

    def test_resolve_returns_single_ip
      resolver = DNSResolver.new(hostname: "redis.example.com")

      resolver.stub(:resolve_all, ["10.0.0.1"]) do
        ip = resolver.resolve

        assert_equal "10.0.0.1", ip
      end
    end

    def test_resolve_returns_multiple_ips_round_robin
      resolver = DNSResolver.new(hostname: "redis.example.com", strategy: :round_robin)

      resolver.stub(:resolve_all, ["10.0.0.1", "10.0.0.2", "10.0.0.3"]) do
        ip1 = resolver.resolve
        ip2 = resolver.resolve
        ip3 = resolver.resolve
        ip4 = resolver.resolve

        assert_equal "10.0.0.1", ip1
        assert_equal "10.0.0.2", ip2
        assert_equal "10.0.0.3", ip3
        assert_equal "10.0.0.1", ip4  # Wraps around
      end
    end

    def test_resolve_returns_multiple_ips_random
      resolver = DNSResolver.new(hostname: "redis.example.com", strategy: :random)

      resolver.stub(:resolve_all, ["10.0.0.1", "10.0.0.2", "10.0.0.3"]) do
        ips = 10.times.map { resolver.resolve }

        # Should have at least 2 different IPs (very unlikely to get same IP 10 times)
        assert ips.uniq.size >= 2
        # All IPs should be from the resolved list
        assert ips.all? { |ip| ["10.0.0.1", "10.0.0.2", "10.0.0.3"].include?(ip) }
      end
    end

    def test_resolve_raises_when_no_ips_found
      resolver = DNSResolver.new(hostname: "nonexistent.example.com")

      resolver.stub(:resolve_all, []) do
        error = assert_raises(DNSResolutionError) do
          resolver.resolve
        end

        assert_match(/No IP addresses found/, error.message)
      end
    end

    # ============================================================
    # resolve_all
    # ============================================================

    def test_resolve_all_returns_array_of_ips
      resolver = DNSResolver.new(hostname: "redis.example.com")

      # Create a stub DNS object
      stub_dns = Object.new
      def stub_dns.getaddresses(hostname)
        [
          Resolv::IPv4.create("10.0.0.1"),
          Resolv::IPv4.create("10.0.0.2")
        ]
      end
      def stub_dns.close; end

      Resolv::DNS.stub(:new, stub_dns) do
        ips = resolver.resolve_all

        assert_equal ["10.0.0.1", "10.0.0.2"], ips
      end
    end

    def test_resolve_all_handles_dns_failure
      resolver = DNSResolver.new(hostname: "nonexistent.example.com")

      # Create a stub DNS object that raises an error
      stub_dns = Object.new
      def stub_dns.getaddresses(hostname)
        raise Resolv::ResolvError, "DNS resolution failed"
      end
      def stub_dns.close; end

      Resolv::DNS.stub(:new, stub_dns) do
        ips = resolver.resolve_all

        assert_equal [], ips
      end
    end

    # ============================================================
    # refresh
    # ============================================================

    def test_refresh_updates_cached_ips
      resolver = DNSResolver.new(hostname: "redis.example.com")

      # First resolution
      resolver.stub(:resolve_all, ["10.0.0.1", "10.0.0.2"]) do
        ip1 = resolver.resolve
        assert_equal "10.0.0.1", ip1
      end

      # Refresh with new IPs
      resolver.stub(:resolve_all, ["10.0.0.3", "10.0.0.4"]) do
        resolver.refresh
        ip2 = resolver.resolve

        assert_equal "10.0.0.3", ip2
      end
    end

    # ============================================================
    # Thread Safety
    # ============================================================

    def test_resolve_is_thread_safe
      resolver = DNSResolver.new(hostname: "redis.example.com", strategy: :round_robin)

      resolver.stub(:resolve_all, ["10.0.0.1", "10.0.0.2", "10.0.0.3"]) do
        ips = []
        threads = 10.times.map do
          Thread.new do
            10.times { ips << resolver.resolve }
          end
        end

        threads.each(&:join)

        # Should have all 3 IPs represented
        assert_equal ["10.0.0.1", "10.0.0.2", "10.0.0.3"], ips.uniq.sort
        # Should have 100 total IPs
        assert_equal 100, ips.size
      end
    end
  end
end

