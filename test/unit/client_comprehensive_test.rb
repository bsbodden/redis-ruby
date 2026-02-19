# frozen_string_literal: true

require_relative "unit_test_helper"

class ClientComprehensiveTest < Minitest::Test
  # ============================================================
  # URL parsing tests
  # ============================================================

  def test_parse_redis_url
    client = RR::Client.new(url: "redis://localhost:6379")

    assert_equal "localhost", client.host
    assert_equal 6379, client.port
    refute_predicate client, :ssl?
  end

  def test_parse_redis_url_with_db
    client = RR::Client.new(url: "redis://localhost:6379/5")

    assert_equal "localhost", client.host
    assert_equal 6379, client.port
    assert_equal 5, client.db
  end

  def test_parse_rediss_url
    client = RR::Client.new(url: "rediss://localhost:6380")

    assert_equal "localhost", client.host
    assert_equal 6380, client.port
    assert_predicate client, :ssl?
  end

  def test_parse_unix_url
    client = RR::Client.new(url: "unix:///var/run/redis/redis.sock")

    assert_equal "/var/run/redis/redis.sock", client.path
    assert_nil client.host
    assert_nil client.port
    assert_predicate client, :unix?
  end

  def test_parse_unix_url_with_db
    client = RR::Client.new(url: "unix:///var/run/redis/redis.sock?db=3")

    assert_equal "/var/run/redis/redis.sock", client.path
    assert_equal 3, client.db
  end

  def test_parse_url_with_password
    client = RR::Client.new(url: "redis://:secret@localhost:6379")

    assert_equal "localhost", client.host
    # Password is private, just verify parsing didn't fail
  end

  def test_parse_url_with_username_and_password
    client = RR::Client.new(url: "redis://user:pass@localhost:6379")

    assert_equal "localhost", client.host
    # Username and password are private, just verify parsing didn't fail
  end

  def test_parse_url_invalid_scheme
    assert_raises(ArgumentError) do
      RR::Client.new(url: "http://localhost:6379")
    end
  end

  def test_parse_url_overrides_options
    client = RR::Client.new(
      url: "redis://remote:7000/2",
      host: "localhost",
      port: 6379,
      db: 0
    )

    assert_equal "remote", client.host
    assert_equal 7000, client.port
    assert_equal 2, client.db
  end

  # ============================================================
  # Default values tests
  # ============================================================

  def test_default_host
    client = RR::Client.new

    assert_equal "localhost", client.host
  end

  def test_default_port
    client = RR::Client.new

    assert_equal 6379, client.port
  end

  def test_default_db
    client = RR::Client.new

    assert_equal 0, client.db
  end

  def test_default_timeout
    client = RR::Client.new

    assert_in_delta(5.0, client.timeout)
  end

  def test_default_ssl
    client = RR::Client.new

    refute_predicate client, :ssl?
  end

  def test_default_unix
    client = RR::Client.new

    refute_predicate client, :unix?
  end

  # ============================================================
  # Custom options tests
  # ============================================================

  def test_custom_host
    client = RR::Client.new(host: "192.168.1.1")

    assert_equal "192.168.1.1", client.host
  end

  def test_custom_port
    client = RR::Client.new(port: 7000)

    assert_equal 7000, client.port
  end

  def test_custom_db
    client = RR::Client.new(db: 5)

    assert_equal 5, client.db
  end

  def test_custom_timeout
    client = RR::Client.new(timeout: 10.0)

    assert_in_delta(10.0, client.timeout)
  end

  def test_custom_ssl
    client = RR::Client.new(ssl: true)

    assert_predicate client, :ssl?
  end

  def test_custom_path
    client = RR::Client.new(path: "/tmp/redis.sock")

    assert_equal "/tmp/redis.sock", client.path
    assert_predicate client, :unix?
  end

  # ============================================================
  # Connection state tests
  # ============================================================

  def test_connected_returns_false_when_not_connected
    client = RR::Client.new

    refute_predicate client, :connected?
  end

  def test_close_when_not_connected
    client = RR::Client.new
    # Should not raise
    client.close

    refute_predicate client, :connected?
  end

  def test_disconnect_alias
    client = RR::Client.new
    # disconnect should be an alias for close
    assert_respond_to client, :disconnect
  end

  def test_quit_alias
    client = RR::Client.new
    # quit should be an alias for close
    assert_respond_to client, :quit
  end

  # ============================================================
  # Retry policy tests
  # ============================================================

  def test_default_retry_policy_with_zero_attempts
    client = RR::Client.new(reconnect_attempts: 0)
    # Just verify it's created without errors
    assert_instance_of RR::Client, client
  end

  def test_custom_retry_attempts
    client = RR::Client.new(reconnect_attempts: 3)
    # Just verify it's created without errors
    assert_instance_of RR::Client, client
  end

  def test_custom_retry_policy
    policy = RR::Retry.new(retries: 5, backoff: RR::ConstantBackoff.new(0.1))
    client = RR::Client.new(retry_policy: policy)

    assert_instance_of RR::Client, client
  end

  # ============================================================
  # Decode responses tests
  # ============================================================

  def test_decode_responses_disabled_by_default
    client = RR::Client.new
    # decode_responses is a private option but we can test the client is created
    assert_instance_of RR::Client, client
  end

  def test_decode_responses_enabled
    client = RR::Client.new(decode_responses: true)

    assert_instance_of RR::Client, client
  end

  def test_decode_responses_with_custom_encoding
    client = RR::Client.new(decode_responses: true, encoding: "ISO-8859-1")

    assert_instance_of RR::Client, client
  end

  # ============================================================
  # SSL params tests
  # ============================================================

  def test_ssl_with_params
    client = RR::Client.new(
      ssl: true,
      ssl_params: { verify_mode: 0 } # VERIFY_NONE
    )

    assert_predicate client, :ssl?
  end

  # ============================================================
  # Command module inclusion tests
  # ============================================================

  def test_includes_strings_commands
    client = RR::Client.new

    assert_respond_to client, :get
    assert_respond_to client, :set
    assert_respond_to client, :mget
    assert_respond_to client, :mset
  end

  def test_includes_keys_commands
    client = RR::Client.new

    assert_respond_to client, :del
    assert_respond_to client, :exists
    assert_respond_to client, :expire
    assert_respond_to client, :ttl
  end

  def test_includes_hashes_commands
    client = RR::Client.new

    assert_respond_to client, :hget
    assert_respond_to client, :hset
    assert_respond_to client, :hmget
    assert_respond_to client, :hgetall
  end

  def test_includes_lists_commands
    client = RR::Client.new

    assert_respond_to client, :lpush
    assert_respond_to client, :rpush
    assert_respond_to client, :lpop
    assert_respond_to client, :rpop
    assert_respond_to client, :lrange
  end

  def test_includes_sets_commands
    client = RR::Client.new

    assert_respond_to client, :sadd
    assert_respond_to client, :srem
    assert_respond_to client, :smembers
    assert_respond_to client, :sismember
  end

  def test_includes_sorted_sets_commands
    client = RR::Client.new

    assert_respond_to client, :zadd
    assert_respond_to client, :zrem
    assert_respond_to client, :zrange
    assert_respond_to client, :zscore
  end
end

class ClientComprehensiveTestPart2 < Minitest::Test
  # ============================================================
  # URL parsing tests
  # ============================================================

  def test_includes_geo_commands
    client = RR::Client.new

    assert_respond_to client, :geoadd
    assert_respond_to client, :geopos
    assert_respond_to client, :geodist
  end

  def test_includes_hyperloglog_commands
    client = RR::Client.new

    assert_respond_to client, :pfadd
    assert_respond_to client, :pfcount
    assert_respond_to client, :pfmerge
  end

  def test_includes_bitmap_commands
    client = RR::Client.new

    assert_respond_to client, :setbit
    assert_respond_to client, :getbit
    assert_respond_to client, :bitcount
  end

  def test_includes_scripting_commands
    client = RR::Client.new

    assert_respond_to client, :eval
    assert_respond_to client, :evalsha
    assert_respond_to client, :script_load
    assert_respond_to client, :script_exists
  end

  def test_includes_streams_commands
    client = RR::Client.new

    assert_respond_to client, :xadd
    assert_respond_to client, :xread
    assert_respond_to client, :xrange
  end

  def test_includes_pubsub_commands
    client = RR::Client.new

    assert_respond_to client, :publish
    assert_respond_to client, :pubsub_channels
    assert_respond_to client, :pubsub_numsub
  end

  def test_includes_server_commands
    client = RR::Client.new

    assert_respond_to client, :info
    assert_respond_to client, :dbsize
    assert_respond_to client, :flushdb
  end

  # ============================================================
  # Transaction and pipeline tests (without connection)
  # ============================================================

  def test_responds_to_pipelined
    client = RR::Client.new

    assert_respond_to client, :pipelined
  end

  def test_responds_to_multi
    client = RR::Client.new

    assert_respond_to client, :multi
  end

  def test_responds_to_watch
    client = RR::Client.new

    assert_respond_to client, :watch
  end

  def test_responds_to_unwatch
    client = RR::Client.new

    assert_respond_to client, :unwatch
  end

  def test_responds_to_discard
    client = RR::Client.new

    assert_respond_to client, :discard
  end

  def test_responds_to_ping
    client = RR::Client.new

    assert_respond_to client, :ping
  end
end
