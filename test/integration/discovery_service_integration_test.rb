# frozen_string_literal: true

require_relative "../test_helper"

module RR
  class DiscoveryServiceIntegrationTest < Minitest::Test
    # NOTE: These tests require a Redis Enterprise cluster with Discovery Service
    # running on port 8001. Since we don't have Redis Enterprise in CI, we'll
    # create mock-based integration tests that verify the client behavior.

    def setup
      # No shared mocks - each test creates its own
    end

    def teardown
      # No shared mocks to verify
    end

    # ============================================================
    # Client Initialization
    # ============================================================

    def test_client_initialization
      client = DiscoveryServiceClient.new(
        nodes: [{ host: "localhost", port: 8001 }],
        database_name: "test-db"
      )

      assert_equal "test-db", client.database_name
      assert_in_delta(5.0, client.timeout)
      refute_predicate client, :connected?

      client.close
    end

    def test_client_with_internal_endpoint
      client = DiscoveryServiceClient.new(
        nodes: [{ host: "localhost", port: 8001 }],
        database_name: "test-db",
        internal: true
      )

      assert_equal "test-db", client.database_name
      client.close
    end

    # ============================================================
    # Connection Management
    # ============================================================

    def test_client_discovers_and_connects
      client = build_discovery_client
      mock_discovery = build_mock_discovery(host: "10.0.0.45", port: 12_000)
      stub_connection = build_stub_connection

      client.instance_variable_set(:@discovery_service, mock_discovery)

      client.stub(:create_connection, ->(_host, _port) { stub_connection }) do
        client.send(:ensure_connected)
        response = client.instance_variable_get(:@connection).call("PING")

        assert_equal "PONG", response
        assert_equal "10.0.0.45:12000", client.instance_variable_get(:@current_address)
      end

      mock_discovery.verify
    end

    def test_client_reconnects_on_address_change
      client = build_discovery_client(current_address: "10.0.0.45:12000")
      client.instance_variable_set(:@connection, build_disconnected_stub)

      mock_discovery = build_mock_discovery(host: "10.0.0.46", port: 12_001)
      new_connection = build_stub_connection

      client.instance_variable_set(:@discovery_service, mock_discovery)

      client.stub(:create_connection, ->(_host, _port) { new_connection }) do
        client.send(:ensure_connected)

        assert_equal "10.0.0.46:12001", client.instance_variable_get(:@current_address)
      end

      mock_discovery.verify
    end

    # ============================================================
    # Factory Method
    # ============================================================

    def test_factory_method
      client = RR.discovery(
        nodes: [{ host: "localhost", port: 8001 }],
        database_name: "test-db"
      )

      assert_instance_of DiscoveryServiceClient, client
      assert_equal "test-db", client.database_name

      client.close
    end

    def test_factory_method_with_internal
      client = RR.discovery(
        nodes: [{ host: "localhost", port: 8001 }],
        database_name: "test-db",
        internal: true
      )

      assert_instance_of DiscoveryServiceClient, client
      client.close
    end

    private

    def build_discovery_client(current_address: nil)
      client = DiscoveryServiceClient.allocate
      client.instance_variable_set(:@database_name, "test-db")
      client.instance_variable_set(:@password, nil)
      client.instance_variable_set(:@db, 0)
      client.instance_variable_set(:@timeout, 5.0)
      client.instance_variable_set(:@ssl, false)
      client.instance_variable_set(:@ssl_params, {})
      client.instance_variable_set(:@reconnect_attempts, 3)
      client.instance_variable_set(:@connection, nil)
      client.instance_variable_set(:@current_address, current_address)
      client.instance_variable_set(:@mutex, Mutex.new)
      client
    end

    def build_mock_discovery(host:, port:)
      mock = Minitest::Mock.new
      mock.expect(:discover_endpoint, { host: host, port: port })
      mock
    end

    def build_stub_connection
      stub_conn = Object.new
      def stub_conn.connected? = true
      def stub_conn.call(*_args) = "PONG"
      stub_conn
    end

    def build_disconnected_stub
      stub_conn = Object.new
      def stub_conn.connected? = false
      def stub_conn.close; end
      stub_conn
    end
  end
end
