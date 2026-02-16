# frozen_string_literal: true

require_relative "../test_helper"

module RR
  class DNSLoadBalancingIntegrationTest < Minitest::Test
    # ============================================================
    # Client Initialization
    # ============================================================

    def test_client_initialization
      client = DNSClient.new(hostname: "localhost", port: 6379)

      assert_equal "localhost", client.hostname
      assert_equal 6379, client.port
      assert_equal 0, client.db
      assert_equal 5.0, client.timeout
    end

    def test_client_with_custom_options
      client = DNSClient.new(
        hostname: "localhost",
        port: 6380,
        db: 1,
        password: "secret",
        timeout: 10.0,
        dns_strategy: :random
      )

      assert_equal "localhost", client.hostname
      assert_equal 6380, client.port
      assert_equal 1, client.db
      assert_equal 10.0, client.timeout
    end

    # ============================================================
    # Connection Management
    # ============================================================

    def test_client_resolves_and_connects
      client = DNSClient.new(hostname: "localhost", port: 6379)

      # Mock DNS resolver to return localhost IP
      stub_resolver = Object.new
      def stub_resolver.resolve
        "127.0.0.1"
      end
      def stub_resolver.refresh; end

      client.instance_variable_set(:@dns_resolver, stub_resolver)

      # Should connect successfully
      result = client.ping

      assert_equal "PONG", result
      assert client.connected?

      client.close
    end

    def test_client_executes_commands
      client = DNSClient.new(hostname: "localhost", port: 6379)

      # Mock DNS resolver
      stub_resolver = Object.new
      def stub_resolver.resolve
        "127.0.0.1"
      end
      def stub_resolver.refresh; end

      client.instance_variable_set(:@dns_resolver, stub_resolver)

      # Execute commands
      client.set("dns:test:key", "value")
      result = client.get("dns:test:key")

      assert_equal "value", result

      client.del("dns:test:key")
      client.close
    end

    def test_client_reconnects_on_connection_failure
      client = DNSClient.new(hostname: "localhost", port: 6379, reconnect_attempts: 2)

      # Mock DNS resolver to return different IPs
      call_count = 0
      stub_resolver = Object.new
      define_singleton_method = ->(obj, name, &block) do
        obj.define_singleton_method(name, &block)
      end

      define_singleton_method.call(stub_resolver, :resolve) do
        call_count += 1
        "127.0.0.1"
      end

      define_singleton_method.call(stub_resolver, :refresh) {}

      client.instance_variable_set(:@dns_resolver, stub_resolver)

      # First connection
      client.ping
      assert client.connected?

      # Force disconnect
      client.close
      refute client.connected?

      # Should reconnect on next command
      result = client.ping
      assert_equal "PONG", result
      assert client.connected?

      client.close
    end

    # ============================================================
    # Factory Method
    # ============================================================

    def test_factory_method
      client = RR.dns(hostname: "localhost", port: 6379)

      assert_instance_of DNSClient, client
      assert_equal "localhost", client.hostname
      assert_equal 6379, client.port

      # Mock DNS resolver
      stub_resolver = Object.new
      def stub_resolver.resolve
        "127.0.0.1"
      end
      def stub_resolver.refresh; end

      client.instance_variable_set(:@dns_resolver, stub_resolver)

      result = client.ping
      assert_equal "PONG", result

      client.close
    end

    def test_factory_method_with_options
      client = RR.dns(
        hostname: "localhost",
        port: 6379,
        db: 1,
        dns_strategy: :random
      )

      assert_instance_of DNSClient, client
      assert_equal 1, client.db

      client.close
    end
  end
end

