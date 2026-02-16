# frozen_string_literal: true

require_relative "../test_helper"

module RR
  class DiscoveryServiceTest < Minitest::Test
    def setup
      @mock_connection = Minitest::Mock.new
    end

    def teardown
      @mock_connection.verify
    end

    # ============================================================
    # Initialization
    # ============================================================

    def test_initialize_with_single_node
      discovery = DiscoveryService.new(
        nodes: [{ host: "localhost", port: 8001 }],
        database_name: "db1"
      )

      assert_equal "db1", discovery.database_name
      assert_equal 1, discovery.nodes.size
      assert_equal "localhost", discovery.nodes[0][:host]
      assert_equal 8001, discovery.nodes[0][:port]
    end

    def test_initialize_with_multiple_nodes
      discovery = DiscoveryService.new(
        nodes: [
          { host: "node1", port: 8001 },
          { host: "node2", port: 8001 },
          { host: "node3", port: 8001 }
        ],
        database_name: "db1"
      )

      assert_equal 3, discovery.nodes.size
    end

    def test_initialize_with_internal_endpoint
      discovery = DiscoveryService.new(
        nodes: [{ host: "localhost", port: 8001 }],
        database_name: "db1",
        internal: true
      )

      assert_equal "db1@internal", discovery.database_name
    end

    def test_initialize_requires_nodes
      assert_raises(ArgumentError) do
        DiscoveryService.new(database_name: "db1")
      end
    end

    def test_initialize_requires_database_name
      assert_raises(ArgumentError) do
        DiscoveryService.new(nodes: [{ host: "localhost", port: 8001 }])
      end
    end

    def test_initialize_with_default_port
      discovery = DiscoveryService.new(
        nodes: [{ host: "localhost" }],
        database_name: "db1"
      )

      assert_equal 8001, discovery.nodes[0][:port]
    end

    # ============================================================
    # discover_endpoint
    # ============================================================

    def test_discover_endpoint_returns_host_and_port
      discovery = DiscoveryService.allocate
      discovery.instance_variable_set(:@nodes, [{ host: "localhost", port: 8001 }])
      discovery.instance_variable_set(:@database_name, "db1")
      discovery.instance_variable_set(:@timeout, 5.0)

      @mock_connection.expect(:call, ["10.0.0.45", "12000"], ["SENTINEL", "get-master-addr-by-name", "db1"])
      @mock_connection.expect(:close, nil)

      discovery.stub(:create_connection, ->(**kwargs) { @mock_connection }) do
        endpoint = discovery.discover_endpoint

        assert_equal "10.0.0.45", endpoint[:host]
        assert_equal 12000, endpoint[:port]
      end
    end

    def test_discover_endpoint_tries_next_node_on_failure
      discovery = DiscoveryService.allocate
      discovery.instance_variable_set(:@nodes, [
        { host: "node1", port: 8001 },
        { host: "node2", port: 8001 }
      ])
      discovery.instance_variable_set(:@database_name, "db1")
      discovery.instance_variable_set(:@timeout, 5.0)

      failing_connection = Minitest::Mock.new
      def failing_connection.call(*args)
        raise ConnectionError, "Connection failed"
      end
      failing_connection.expect(:close, nil)

      @mock_connection.expect(:call, ["10.0.0.45", "12000"], ["SENTINEL", "get-master-addr-by-name", "db1"])
      @mock_connection.expect(:close, nil)

      call_count = 0
      discovery.stub(:create_connection, ->(**kwargs) {
        call_count += 1
        call_count == 1 ? failing_connection : @mock_connection
      }) do
        endpoint = discovery.discover_endpoint

        assert_equal "10.0.0.45", endpoint[:host]
        assert_equal 12000, endpoint[:port]
      end

      failing_connection.verify
    end

    def test_discover_endpoint_raises_when_all_nodes_fail
      discovery = DiscoveryService.allocate
      discovery.instance_variable_set(:@nodes, [
        { host: "node1", port: 8001 },
        { host: "node2", port: 8001 }
      ])
      discovery.instance_variable_set(:@database_name, "db1")
      discovery.instance_variable_set(:@timeout, 5.0)

      call_count = 0
      discovery.stub(:create_connection, ->(**kwargs) {
        call_count += 1
        conn = Minitest::Mock.new
        def conn.call(*args)
          raise ConnectionError, "Connection failed"
        end
        conn.expect(:close, nil)
        conn
      }) do
        error = assert_raises(DiscoveryServiceError) do
          discovery.discover_endpoint
        end

        assert_match(/Failed to discover endpoint/, error.message)
      end

      assert_equal 2, call_count
    end

    def test_discover_endpoint_raises_when_database_not_found
      discovery = DiscoveryService.allocate
      discovery.instance_variable_set(:@nodes, [{ host: "localhost", port: 8001 }])
      discovery.instance_variable_set(:@database_name, "nonexistent")
      discovery.instance_variable_set(:@timeout, 5.0)

      @mock_connection.expect(:call, nil, ["SENTINEL", "get-master-addr-by-name", "nonexistent"])
      @mock_connection.expect(:close, nil)

      discovery.stub(:create_connection, ->(**kwargs) { @mock_connection }) do
        error = assert_raises(DiscoveryServiceError) do
          discovery.discover_endpoint
        end

        assert_match(/Database.*not found/, error.message)
      end
    end
  end
end

