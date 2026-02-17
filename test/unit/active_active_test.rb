# frozen_string_literal: true

require_relative "../test_helper"

class ActiveActiveTest < Minitest::Test
  def setup
    @regions = [
      { host: "redis-us-east.example.com", port: 6379 },
      { host: "redis-eu-west.example.com", port: 6379 },
      { host: "redis-ap-south.example.com", port: 6379 }
    ]
  end

  def test_initialize_with_regions
    client = RR::ActiveActiveClient.new(regions: @regions)
    assert_instance_of RR::ActiveActiveClient, client
  end

  def test_initialize_requires_regions
    error = assert_raises(ArgumentError) do
      RR::ActiveActiveClient.new(regions: [])
    end
    assert_match(/at least one region/, error.message)
  end

  def test_initialize_with_single_region
    client = RR::ActiveActiveClient.new(regions: [@regions.first])
    assert_instance_of RR::ActiveActiveClient, client
  end

  def test_initialize_with_options
    client = RR::ActiveActiveClient.new(
      regions: @regions,
      db: 1,
      password: "secret",
      timeout: 10,
      ssl: true,
      ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_PEER }
    )
    assert_instance_of RR::ActiveActiveClient, client
  end

  def test_initialize_with_preferred_region
    client = RR::ActiveActiveClient.new(
      regions: @regions,
      preferred_region: 1
    )
    assert_instance_of RR::ActiveActiveClient, client
  end

  def test_call_method_exists
    client = RR::ActiveActiveClient.new(regions: @regions)
    assert_respond_to client, :call
  end

  def test_fast_path_methods_exist
    client = RR::ActiveActiveClient.new(regions: @regions)
    assert_respond_to client, :call_1arg
    assert_respond_to client, :call_2args
    assert_respond_to client, :call_3args
  end

  def test_includes_command_modules
    client = RR::ActiveActiveClient.new(regions: @regions)
    
    # Test a few key command modules
    assert_respond_to client, :get
    assert_respond_to client, :set
    assert_respond_to client, :hget
    assert_respond_to client, :lpush
    assert_respond_to client, :sadd
    assert_respond_to client, :zadd
  end

  def test_close_method_exists
    client = RR::ActiveActiveClient.new(regions: @regions)
    assert_respond_to client, :close
  end

  def test_connected_method_exists
    client = RR::ActiveActiveClient.new(regions: @regions)
    assert_respond_to client, :connected?
  end

  def test_current_region_method_exists
    client = RR::ActiveActiveClient.new(regions: @regions)
    assert_respond_to client, :current_region
  end

  def test_failover_to_next_region_method_exists
    client = RR::ActiveActiveClient.new(regions: @regions)
    assert_respond_to client, :failover_to_next_region
  end

  def test_thread_safety
    client = RR::ActiveActiveClient.new(regions: @regions)
    
    # Verify mutex exists for thread safety
    assert client.instance_variable_defined?(:@mutex)
    assert_instance_of Mutex, client.instance_variable_get(:@mutex)
  end

  def test_factory_method_exists
    assert_respond_to RR, :active_active
  end

  def test_factory_method_creates_client
    client = RR.active_active(regions: @regions)
    assert_instance_of RR::ActiveActiveClient, client
  end

  def test_factory_method_with_options
    client = RR.active_active(
      regions: @regions,
      db: 2,
      password: "test123"
    )
    assert_instance_of RR::ActiveActiveClient, client
  end

  def test_close_does_not_hang_with_auto_fallback_thread
    client = RR::ActiveActiveClient.new(
      regions: @regions,
      auto_fallback_interval: 999 # Very long sleep interval
    )

    # close should complete quickly with a timeout, not block for 999s
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    client.close
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

    assert elapsed < 5, "close took #{elapsed}s, expected < 5s"
  end

  def test_select_db_passes_string_not_integer
    client = RR::ActiveActiveClient.new(regions: @regions, db: 3)
    mock_conn = mock("connection")
    mock_conn.expects(:call).with("SELECT", "3")
    client.instance_variable_set(:@connection, mock_conn)

    client.send(:select_db)
  end
end

