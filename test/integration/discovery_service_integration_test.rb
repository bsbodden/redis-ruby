# frozen_string_literal: true

require_relative "../test_helper"

module RR
  class DiscoveryServiceIntegrationTest < Minitest::Test
    # Note: These tests require a Redis Enterprise cluster with Discovery Service
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
      assert_equal 5.0, client.timeout
      refute client.connected?

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
      client = DiscoveryServiceClient.allocate
      client.instance_variable_set(:@database_name, "test-db")
      client.instance_variable_set(:@password, nil)
      client.instance_variable_set(:@db, 0)
      client.instance_variable_set(:@timeout, 5.0)
      client.instance_variable_set(:@ssl, false)
      client.instance_variable_set(:@ssl_params, {})
      client.instance_variable_set(:@reconnect_attempts, 3)
      client.instance_variable_set(:@connection, nil)
      client.instance_variable_set(:@current_address, nil)
      client.instance_variable_set(:@mutex, Mutex.new)

      mock_discovery = Minitest::Mock.new
      mock_discovery.expect(:discover_endpoint, { host: "10.0.0.45", port: 12000 })

      # Create a simple stub connection that responds to connected? and call
      stub_connection = Object.new
      def stub_connection.connected?; true; end
      def stub_connection.call(*args); "PONG"; end

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
      client = DiscoveryServiceClient.allocate
      client.instance_variable_set(:@database_name, "test-db")
      client.instance_variable_set(:@password, nil)
      client.instance_variable_set(:@db, 0)
      client.instance_variable_set(:@timeout, 5.0)
      client.instance_variable_set(:@ssl, false)
      client.instance_variable_set(:@ssl_params, {})
      client.instance_variable_set(:@reconnect_attempts, 3)
      client.instance_variable_set(:@current_address, "10.0.0.45:12000")
      client.instance_variable_set(:@mutex, Mutex.new)

      # Old connection that is no longer connected
      old_connection = Object.new
      def old_connection.connected?; false; end
      def old_connection.close; end

      client.instance_variable_set(:@connection, old_connection)

      mock_discovery = Minitest::Mock.new
      mock_discovery.expect(:discover_endpoint, { host: "10.0.0.46", port: 12001 })

      # New connection
      new_connection = Object.new
      def new_connection.connected?; true; end

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
  end
end

