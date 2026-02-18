# frozen_string_literal: true

require_relative "../unit_test_helper"

class SingleConnectionOperationsTest < Minitest::Test
  # Minimal test class that includes the concern
  class TestClient
    include RR::Concerns::SingleConnectionOperations

    attr_accessor :connection

    def initialize(connection, password: nil, db: 0)
      @connection = connection
      @password = password
      @db = db
    end

    def call(command, *args)
      @connection.call(command, *args)
    end

    def ensure_connected
      # no-op for tests
    end
  end

  def setup
    @mock_conn = mock("connection")
  end

  def test_authenticate_sends_auth_command
    client = TestClient.new(@mock_conn, password: "secret")
    @mock_conn.expects(:call).with("AUTH", "secret").returns("OK")

    client.send(:authenticate)
  end

  def test_select_db_sends_select_command
    client = TestClient.new(@mock_conn, db: 3)
    @mock_conn.expects(:call).with("SELECT", "3").returns("OK")

    client.send(:select_db)
  end

  def test_select_db_converts_db_to_string
    client = TestClient.new(@mock_conn, db: 15)
    @mock_conn.expects(:call).with("SELECT", "15").returns("OK")

    client.send(:select_db)
  end
end
