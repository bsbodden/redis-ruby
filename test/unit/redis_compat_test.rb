# frozen_string_literal: true

require_relative "unit_test_helper"
require "redis"

class RedisCompatTest < Minitest::Test
  # =================================================================
  # Setup / Helpers
  # =================================================================

  def setup
    @mock_client = mock("redis_ruby_client")
    @mock_client.stubs(:connected?).returns(true)
    @mock_client.stubs(:close)
    RedisRuby::Client.stubs(:new).returns(@mock_client)
  end

  def build_redis(options = {})
    Redis.new(options)
  end

  # =================================================================
  # Initialization & Options Normalization
  # =================================================================

  def test_initialize_with_defaults
    redis = build_redis

    assert_equal "localhost", redis.options[:host]
    assert_equal 6379, redis.options[:port]
    assert_equal 0, redis.options[:db]
    assert_in_delta(5.0, redis.options[:timeout])
  end

  def test_initialize_with_custom_host_and_port
    redis = build_redis(host: "myredis", port: 7000)

    assert_equal "myredis", redis.options[:host]
    assert_equal 7000, redis.options[:port]
  end

  def test_initialize_with_url_redis_scheme
    redis = build_redis(url: "redis://myhost:6380/3")

    assert_equal "myhost", redis.options[:host]
    assert_equal 6380, redis.options[:port]
    assert_equal 3, redis.options[:db]
    refute redis.options[:ssl]
  end

  def test_initialize_with_url_rediss_scheme
    redis = build_redis(url: "rediss://securehost:6381/2")

    assert_equal "securehost", redis.options[:host]
    assert_equal 6381, redis.options[:port]
    assert_equal 2, redis.options[:db]
    assert redis.options[:ssl]
  end

  def test_initialize_url_with_password
    redis = build_redis(url: "redis://:secret@host:6379/0")

    assert_equal "secret", redis.options[:password]
  end

  def test_initialize_url_with_username_and_password
    redis = build_redis(url: "redis://admin:secret@host:6379/0")

    assert_equal "admin", redis.options[:username]
    assert_equal "secret", redis.options[:password]
  end

  def test_initialize_url_username_same_as_password_is_ignored
    # When user == password, username is not set (redis-rb compat)
    redis = build_redis(url: "redis://secret:secret@host:6379/0")

    assert_nil redis.options[:username]
    assert_equal "secret", redis.options[:password]
  end

  def test_initialize_url_empty_username_is_ignored
    redis = build_redis(url: "redis://:pass@host:6379/0")

    assert_nil redis.options[:username]
  end

  def test_initialize_url_empty_path
    redis = build_redis(url: "redis://host:6379")

    assert_equal 0, redis.options[:db]
  end

  def test_initialize_url_root_path
    redis = build_redis(url: "redis://host:6379/")

    assert_equal 0, redis.options[:db]
  end

  def test_initialize_url_unix_scheme
    redis = build_redis(url: "unix:///var/run/redis.sock")

    assert_equal "/var/run/redis.sock", redis.options[:path]
  end

  def test_initialize_with_connect_timeout
    redis = build_redis(connect_timeout: 10.0)

    assert_in_delta(10.0, redis.options[:timeout])
    refute redis.options.key?(:connect_timeout)
  end

  def test_initialize_with_read_timeout_fallback
    # Default timeout (5.0) is already set via DEFAULT_OPTIONS merge,
    # so ||= short-circuits and read_timeout key is NOT deleted
    redis = build_redis(read_timeout: 8.0)

    assert_in_delta(5.0, redis.options[:timeout])
    # read_timeout stays because ||= short-circuited (delete was not called)
    assert redis.options.key?(:read_timeout)
  end

  def test_initialize_with_write_timeout_fallback
    # Same as read_timeout - default timeout takes precedence via ||=
    redis = build_redis(write_timeout: 7.0)

    assert_in_delta(5.0, redis.options[:timeout])
    # write_timeout stays because ||= short-circuited
    assert redis.options.key?(:write_timeout)
  end

  def test_initialize_timeout_not_overridden_by_read_timeout
    # If timeout is already set, read_timeout does not override it
    redis = build_redis(timeout: 3.0, read_timeout: 8.0)

    assert_in_delta(3.0, redis.options[:timeout])
  end

  def test_initialize_timeout_not_overridden_by_write_timeout
    redis = build_redis(timeout: 3.0, write_timeout: 8.0)

    assert_in_delta(3.0, redis.options[:timeout])
  end

  def test_initialize_driver_option_is_ignored
    redis = build_redis(driver: :hiredis)

    refute redis.options.key?(:driver)
  end

  def test_initialize_with_id
    redis = build_redis(id: "my-connection")
    info = redis.connection

    assert_equal "my-connection", info[:id]
  end

  def test_initialize_with_path_option
    redis = build_redis(path: "/tmp/redis.sock")

    assert_equal "/tmp/redis.sock", redis.options[:path]
  end

  # Sentinel configuration
  def test_initialize_with_sentinels
    mock_sentinel_client = mock("sentinel_client")
    RedisRuby.stubs(:sentinel).returns(mock_sentinel_client)

    redis = build_redis(
      sentinels: [{ host: "s1", port: 26_379 }],
      name: "mymaster"
    )
    # It should have called RedisRuby.sentinel
    assert_instance_of Redis, redis
  end

  def test_initialize_sentinel_with_role
    mock_sentinel_client = mock("sentinel_client")
    RedisRuby.expects(:sentinel).with(
      sentinels: [{ host: "s1", port: 26_379 }],
      service_name: "mymaster",
      role: :replica,
      password: nil,
      username: nil,
      timeout: 5.0
    ).returns(mock_sentinel_client)

    build_redis(
      sentinels: [{ host: "s1", port: 26_379 }],
      name: "mymaster",
      role: :replica
    )
  end

  def test_initialize_sentinel_default_role_is_master
    mock_sentinel_client = mock("sentinel_client")
    RedisRuby.expects(:sentinel).with(
      sentinels: [{ host: "s1", port: 26_379 }],
      service_name: "mymaster",
      role: :master,
      password: nil,
      username: nil,
      timeout: 5.0
    ).returns(mock_sentinel_client)

    build_redis(
      sentinels: [{ host: "s1", port: 26_379 }],
      name: "mymaster"
    )
  end

  # =================================================================
  # VERSION constant
  # =================================================================

  def test_version
    assert_equal RedisRuby::VERSION, Redis::VERSION
  end

  # =================================================================
  # Connection info and state
  # =================================================================

  def test_connection_returns_host_port_db_id_location
    redis = build_redis(host: "myhost", port: 7000, db: 2, id: "conn1")
    info = redis.connection

    assert_equal "myhost", info[:host]
    assert_equal 7000, info[:port]
    assert_equal 2, info[:db]
    assert_equal "conn1", info[:id]
    assert_equal "myhost:7000", info[:location]
  end

  def test_connection_location_with_path
    redis = build_redis(path: "/tmp/redis.sock")
    info = redis.connection

    assert_equal "/tmp/redis.sock", info[:location]
  end

  def test_connected
    @mock_client.expects(:connected?).returns(true)
    redis = build_redis

    assert_predicate redis, :connected?
  end

  def test_connected_false
    @mock_client.expects(:connected?).returns(false)
    redis = build_redis

    refute_predicate redis, :connected?
  end

  # =================================================================
  # quit / close / disconnect!
  # =================================================================

  def test_quit_closes_and_returns_ok
    @mock_client.expects(:close)
    redis = build_redis

    assert_equal "OK", redis.quit
  end

  def test_close_delegates
    @mock_client.expects(:close)
    redis = build_redis
    redis.close
  end

  def test_disconnect_bang_is_alias_for_close
    @mock_client.expects(:close)
    redis = build_redis
    redis.disconnect!
  end

  # =================================================================
  # _client accessor
  # =================================================================

  def test_client_accessor
    redis = build_redis

    assert_equal @mock_client, redis._client
  end

  # =================================================================
  # ping
  # =================================================================

  def test_ping_without_message
    @mock_client.expects(:ping).returns("PONG")
    redis = build_redis

    assert_equal "PONG", redis.ping
  end

  def test_ping_with_message
    @mock_client.expects(:call).with("PING", "hello").returns("hello")
    redis = build_redis

    assert_equal "hello", redis.ping("hello")
  end

  # =================================================================
  # echo
  # =================================================================

  def test_echo
    @mock_client.expects(:call).with("ECHO", "hello").returns("hello")
    redis = build_redis

    assert_equal "hello", redis.echo("hello")
  end

  # =================================================================
  # select
  # =================================================================

  def test_select
    @mock_client.expects(:call).with("SELECT", 3).returns("OK")
    redis = build_redis

    assert_equal "OK", redis.select(3)
  end

  # =================================================================
  # call (raw)
  # =================================================================

  def test_call_raw
    @mock_client.expects(:call).with("SET", "k", "v").returns("OK")
    redis = build_redis

    assert_equal "OK", redis.call("SET", "k", "v")
  end

  # =================================================================
  # Error Translation
  # =================================================================

  def test_error_translation_connection_error
    @mock_client.expects(:ping).raises(RedisRuby::ConnectionError, "conn lost")
    redis = build_redis
    assert_raises(Redis::ConnectionError) { redis.ping }
  end

  def test_error_translation_timeout_error
    @mock_client.expects(:ping).raises(RedisRuby::TimeoutError, "timed out")
    redis = build_redis
    assert_raises(Redis::TimeoutError) { redis.ping }
  end

  def test_error_translation_command_error
    @mock_client.expects(:ping).raises(RedisRuby::CommandError, "ERR unknown")
    redis = build_redis
    assert_raises(Redis::CommandError) { redis.ping }
  end

  def test_error_translation_wrongtype
    @mock_client.expects(:get).with("k").raises(RedisRuby::CommandError, "WRONGTYPE Operation")
    redis = build_redis
    assert_raises(Redis::WrongTypeError) { redis.get("k") }
  end

  def test_error_translation_auth_error
    @mock_client.expects(:ping).raises(RedisRuby::CommandError, "NOAUTH Authentication required")
    redis = build_redis
    assert_raises(Redis::AuthenticationError) { redis.ping }
  end

  def test_error_translation_auth_error_err_auth
    @mock_client.expects(:ping).raises(RedisRuby::CommandError, "ERR AUTH failed")
    redis = build_redis
    assert_raises(Redis::AuthenticationError) { redis.ping }
  end

  def test_error_translation_permission_error
    @mock_client.expects(:ping).raises(RedisRuby::CommandError, "NOPERM this user")
    redis = build_redis
    assert_raises(Redis::PermissionError) { redis.ping }
  end

  def test_error_translation_cluster_down
    @mock_client.expects(:ping).raises(RedisRuby::ClusterDownError, "CLUSTERDOWN")
    redis = build_redis
    assert_raises(Redis::ClusterDownError) { redis.ping }
  end

  def test_error_translation_moved_error
    @mock_client.expects(:ping).raises(RedisRuby::MovedError, "MOVED 12345 127.0.0.1:6379")
    redis = build_redis
    err = assert_raises(Redis::MovedError) { redis.ping }
    assert_equal 12_345, err.slot
    assert_equal "127.0.0.1", err.host
    assert_equal 6379, err.port
  end

  def test_error_translation_ask_error
    @mock_client.expects(:ping).raises(RedisRuby::AskError, "ASK 999 10.0.0.1:6380")
    redis = build_redis
    err = assert_raises(Redis::AskError) { redis.ping }
    assert_equal 999, err.slot
    assert_equal "10.0.0.1", err.host
    assert_equal 6380, err.port
  end

  def test_error_translation_cluster_error
    @mock_client.expects(:ping).raises(RedisRuby::ClusterError, "cluster problem")
    redis = build_redis
    assert_raises(Redis::ClusterError) { redis.ping }
  end

  def test_error_translation_passthrough_for_unknown_error
    # Unknown error types are passed through unchanged
    translated = Redis::ErrorTranslation.translate(RuntimeError.new("something"))

    assert_instance_of RuntimeError, translated
  end

  # =================================================================
  # MovedError / AskError parsing
  # =================================================================

  def test_moved_error_parsing_no_match
    err = Redis::MovedError.new("not a moved message")

    assert_nil err.slot
    assert_nil err.host
    assert_nil err.port
  end

  def test_ask_error_parsing_no_match
    err = Redis::AskError.new("not an ask message")

    assert_nil err.slot
    assert_nil err.host
    assert_nil err.port
  end

  # =================================================================
  # FutureNotReady
  # =================================================================

  def test_future_not_ready_message
    err = Redis::FutureNotReady.new

    assert_match(/pipeline executes/, err.message)
  end

  # =================================================================
  # String commands delegation
  # =================================================================

  def test_set_basic
    @mock_client.expects(:set).with("k", "v",
                                    ex: nil, px: nil, exat: nil, pxat: nil,
                                    nx: false, xx: false, keepttl: false, get: false).returns("OK")
    redis = build_redis

    assert_equal "OK", redis.set("k", "v")
  end

  def test_set_with_options
    @mock_client.expects(:set).with("k", "v",
                                    ex: 60, px: nil, exat: nil, pxat: nil,
                                    nx: true, xx: false, keepttl: false, get: false).returns("OK")
    redis = build_redis

    assert_equal "OK", redis.set("k", "v", ex: 60, nx: true)
  end

  def test_get
    @mock_client.expects(:get).with("k").returns("v")
    redis = build_redis

    assert_equal "v", redis.get("k")
  end

  def test_incr
    @mock_client.expects(:incr).with("k").returns(2)
    redis = build_redis

    assert_equal 2, redis.incr("k")
  end

  def test_decr
    @mock_client.expects(:decr).with("k").returns(0)
    redis = build_redis

    assert_equal 0, redis.decr("k")
  end

  def test_incrby
    @mock_client.expects(:incrby).with("k", 5).returns(10)
    redis = build_redis

    assert_equal 10, redis.incrby("k", 5)
  end

  def test_decrby
    @mock_client.expects(:decrby).with("k", 3).returns(7)
    redis = build_redis

    assert_equal 7, redis.decrby("k", 3)
  end

  def test_incrbyfloat
    @mock_client.expects(:incrbyfloat).with("k", 1.5).returns("3.5")
    redis = build_redis

    assert_equal "3.5", redis.incrbyfloat("k", 1.5)
  end

  def test_append
    @mock_client.expects(:append).with("k", "more").returns(8)
    redis = build_redis

    assert_equal 8, redis.append("k", "more")
  end

  def test_strlen
    @mock_client.expects(:strlen).with("k").returns(5)
    redis = build_redis

    assert_equal 5, redis.strlen("k")
  end

  def test_getrange
    @mock_client.expects(:getrange).with("k", 0, 3).returns("test")
    redis = build_redis

    assert_equal "test", redis.getrange("k", 0, 3)
  end

  def test_setrange
    @mock_client.expects(:setrange).with("k", 5, "abc").returns(8)
    redis = build_redis

    assert_equal 8, redis.setrange("k", 5, "abc")
  end

  def test_mget_with_splat
    @mock_client.expects(:mget).with("k1", "k2").returns(%w[v1 v2])
    redis = build_redis

    assert_equal %w[v1 v2], redis.mget("k1", "k2")
  end

  def test_mget_with_array
    @mock_client.expects(:mget).with("k1", "k2").returns(%w[v1 v2])
    redis = build_redis

    assert_equal %w[v1 v2], redis.mget(%w[k1 k2])
  end

  def test_mset
    @mock_client.expects(:mset).with("k1", "v1", "k2", "v2").returns("OK")
    redis = build_redis

    assert_equal "OK", redis.mset("k1", "v1", "k2", "v2")
  end

  def test_msetnx_returns_true
    @mock_client.expects(:msetnx).with("k1", "v1").returns(1)
    redis = build_redis

    assert redis.msetnx("k1", "v1")
  end

  def test_msetnx_returns_false
    @mock_client.expects(:msetnx).with("k1", "v1").returns(0)
    redis = build_redis

    refute redis.msetnx("k1", "v1")
  end

  def test_setnx
    @mock_client.expects(:setnx).with("k", "v").returns(true)
    redis = build_redis

    assert redis.setnx("k", "v")
  end

  def test_setex
    @mock_client.expects(:setex).with("k", 60, "v").returns("OK")
    redis = build_redis

    assert_equal "OK", redis.setex("k", 60, "v")
  end

  def test_psetex
    @mock_client.expects(:psetex).with("k", 5000, "v").returns("OK")
    redis = build_redis

    assert_equal "OK", redis.psetex("k", 5000, "v")
  end

  def test_getset
    @mock_client.expects(:getset).with("k", "new").returns("old")
    redis = build_redis

    assert_equal "old", redis.getset("k", "new")
  end

  def test_getdel
    @mock_client.expects(:getdel).with("k").returns("v")
    redis = build_redis

    assert_equal "v", redis.getdel("k")
  end

  def test_getex
    @mock_client.expects(:getex).with("k", ex: 60, px: nil, exat: nil, pxat: nil, persist: false).returns("v")
    redis = build_redis

    assert_equal "v", redis.getex("k", ex: 60)
  end

  # =================================================================
  # Key commands delegation
  # =================================================================

  def test_del
    @mock_client.expects(:del).with("k1", "k2").returns(2)
    redis = build_redis

    assert_equal 2, redis.del("k1", "k2")
  end

  def test_delete_is_alias_for_del
    @mock_client.expects(:del).with("k").returns(1)
    redis = build_redis

    assert_equal 1, redis.delete("k")
  end

  def test_exists
    @mock_client.expects(:exists).with("k").returns(1)
    redis = build_redis

    assert_equal 1, redis.exists("k")
  end

  def test_expire
    @mock_client.expects(:expire).with("k", 60, nx: false, xx: false, gt: false, lt: false).returns(1)
    redis = build_redis

    assert_equal 1, redis.expire("k", 60)
  end

  def test_pexpire
    @mock_client.expects(:pexpire).with("k", 5000, nx: false, xx: false, gt: false, lt: false).returns(1)
    redis = build_redis

    assert_equal 1, redis.pexpire("k", 5000)
  end

  def test_expireat
    @mock_client.expects(:expireat).with("k", 1_000_000, nx: false, xx: false, gt: false, lt: false).returns(1)
    redis = build_redis

    assert_equal 1, redis.expireat("k", 1_000_000)
  end

  def test_pexpireat
    @mock_client.expects(:pexpireat).with("k", 1_000_000_000, nx: false, xx: false, gt: false, lt: false).returns(1)
    redis = build_redis

    assert_equal 1, redis.pexpireat("k", 1_000_000_000)
  end

  def test_ttl
    @mock_client.expects(:ttl).with("k").returns(120)
    redis = build_redis

    assert_equal 120, redis.ttl("k")
  end

  def test_pttl
    @mock_client.expects(:pttl).with("k").returns(120_000)
    redis = build_redis

    assert_equal 120_000, redis.pttl("k")
  end

  def test_persist
    @mock_client.expects(:persist).with("k").returns(1)
    redis = build_redis

    assert_equal 1, redis.persist("k")
  end

  def test_expiretime
    @mock_client.expects(:expiretime).with("k").returns(1_700_000_000)
    redis = build_redis

    assert_equal 1_700_000_000, redis.expiretime("k")
  end

  def test_pexpiretime
    @mock_client.expects(:pexpiretime).with("k").returns(1_700_000_000_000)
    redis = build_redis

    assert_equal 1_700_000_000_000, redis.pexpiretime("k")
  end

  def test_keys
    @mock_client.expects(:keys).with("*").returns(%w[k1 k2])
    redis = build_redis

    assert_equal %w[k1 k2], redis.keys("*")
  end

  def test_scan
    @mock_client.expects(:scan).with(0, match: nil, count: nil, type: nil).returns(["5", ["k1"]])
    redis = build_redis

    assert_equal ["5", ["k1"]], redis.scan(0)
  end

  def test_scan_with_options
    @mock_client.expects(:scan).with(0, match: "key*", count: 100, type: "string").returns(["5", ["k1"]])
    redis = build_redis

    assert_equal ["5", ["k1"]], redis.scan(0, match: "key*", count: 100, type: "string")
  end

  def test_scan_iter
    enumerator = Enumerator.new { |y| y.yield "k1" }
    @mock_client.expects(:scan_iter).with(match: "*", count: 10, type: nil).returns(enumerator)
    redis = build_redis

    assert_equal enumerator, redis.scan_iter
  end

  def test_type
    @mock_client.expects(:type).with("k").returns("string")
    redis = build_redis

    assert_equal "string", redis.type("k")
  end

  def test_rename
    @mock_client.expects(:rename).with("old", "new").returns("OK")
    redis = build_redis

    assert_equal "OK", redis.rename("old", "new")
  end

  def test_renamenx
    @mock_client.expects(:renamenx).with("old", "new").returns(1)
    redis = build_redis

    assert_equal 1, redis.renamenx("old", "new")
  end

  def test_randomkey
    @mock_client.expects(:randomkey).returns("somekey")
    redis = build_redis

    assert_equal "somekey", redis.randomkey
  end

  def test_unlink
    @mock_client.expects(:unlink).with("k1", "k2").returns(2)
    redis = build_redis

    assert_equal 2, redis.unlink("k1", "k2")
  end

  def test_dump
    @mock_client.expects(:dump).with("k").returns("\x00\x01")
    redis = build_redis

    assert_equal "\x00\x01", redis.dump("k")
  end

  def test_restore
    @mock_client.expects(:restore).with("k", 0, "\x00\x01", replace: false).returns("OK")
    redis = build_redis

    assert_equal "OK", redis.restore("k", 0, "\x00\x01")
  end

  def test_restore_with_replace
    @mock_client.expects(:restore).with("k", 0, "\x00\x01", replace: true).returns("OK")
    redis = build_redis

    assert_equal "OK", redis.restore("k", 0, "\x00\x01", replace: true)
  end

  def test_touch
    @mock_client.expects(:touch).with("k1", "k2").returns(2)
    redis = build_redis

    assert_equal 2, redis.touch("k1", "k2")
  end

  def test_memory_usage
    @mock_client.expects(:memory_usage).with("k").returns(128)
    redis = build_redis

    assert_equal 128, redis.memory_usage("k")
  end

  def test_copy
    @mock_client.expects(:copy).with("src", "dst", db: nil, replace: false).returns(1)
    redis = build_redis

    assert_equal 1, redis.copy("src", "dst")
  end

  def test_copy_with_replace
    @mock_client.expects(:copy).with("src", "dst", db: 2, replace: true).returns(1)
    redis = build_redis

    assert_equal 1, redis.copy("src", "dst", db: 2, replace: true)
  end

  # =================================================================
  # Hash commands
  # =================================================================

  def test_hset
    @mock_client.expects(:hset).with("h", "f", "v").returns(1)
    redis = build_redis

    assert_equal 1, redis.hset("h", "f", "v")
  end

  def test_hget
    @mock_client.expects(:hget).with("h", "f").returns("v")
    redis = build_redis

    assert_equal "v", redis.hget("h", "f")
  end

  def test_hsetnx_returns_true
    @mock_client.expects(:hsetnx).with("h", "f", "v").returns(1)
    redis = build_redis

    assert redis.hsetnx("h", "f", "v")
  end

  def test_hsetnx_returns_false
    @mock_client.expects(:hsetnx).with("h", "f", "v").returns(0)
    redis = build_redis

    refute redis.hsetnx("h", "f", "v")
  end

  def test_hmget
    @mock_client.expects(:hmget).with("h", "f1", "f2").returns(%w[v1 v2])
    redis = build_redis

    assert_equal %w[v1 v2], redis.hmget("h", "f1", "f2")
  end

  def test_hmset
    @mock_client.expects(:hmset).with("h", "f1", "v1", "f2", "v2").returns("OK")
    redis = build_redis

    assert_equal "OK", redis.hmset("h", "f1", "v1", "f2", "v2")
  end

  def test_hgetall
    @mock_client.expects(:hgetall).with("h").returns({ "f" => "v" })
    redis = build_redis

    assert_equal({ "f" => "v" }, redis.hgetall("h"))
  end

  def test_hdel_single
    @mock_client.expects(:hdel).with("h", "f1").returns(1)
    redis = build_redis

    assert_equal 1, redis.hdel("h", "f1")
  end

  def test_hdel_array_flattened
    @mock_client.expects(:hdel).with("h", "f1", "f2").returns(2)
    redis = build_redis

    assert_equal 2, redis.hdel("h", %w[f1 f2])
  end

  def test_hexists_true
    @mock_client.expects(:hexists).with("h", "f").returns(1)
    redis = build_redis

    assert redis.hexists("h", "f")
  end

  def test_hexists_false
    @mock_client.expects(:hexists).with("h", "f").returns(0)
    redis = build_redis

    refute redis.hexists("h", "f")
  end

  def test_hkeys
    @mock_client.expects(:hkeys).with("h").returns(%w[f1 f2])
    redis = build_redis

    assert_equal %w[f1 f2], redis.hkeys("h")
  end

  def test_hvals
    @mock_client.expects(:hvals).with("h").returns(%w[v1 v2])
    redis = build_redis

    assert_equal %w[v1 v2], redis.hvals("h")
  end

  def test_hlen
    @mock_client.expects(:hlen).with("h").returns(3)
    redis = build_redis

    assert_equal 3, redis.hlen("h")
  end

  def test_hstrlen
    @mock_client.expects(:hstrlen).with("h", "f").returns(5)
    redis = build_redis

    assert_equal 5, redis.hstrlen("h", "f")
  end

  def test_hincrby
    @mock_client.expects(:hincrby).with("h", "f", 3).returns(10)
    redis = build_redis

    assert_equal 10, redis.hincrby("h", "f", 3)
  end

  def test_hincrbyfloat
    @mock_client.expects(:hincrbyfloat).with("h", "f", 1.5).returns("3.5")
    redis = build_redis

    assert_equal "3.5", redis.hincrbyfloat("h", "f", 1.5)
  end

  def test_hscan
    @mock_client.expects(:hscan).with("h", 0, match: nil, count: nil).returns(["0", [%w[f v]]])
    redis = build_redis

    assert_equal ["0", [%w[f v]]], redis.hscan("h", 0)
  end

  def test_hscan_iter
    enumerator = Enumerator.new { |y| y.yield %w[f v] }
    @mock_client.expects(:hscan_iter).with("h", match: "*", count: 10).returns(enumerator)
    redis = build_redis

    assert_equal enumerator, redis.hscan_iter("h")
  end

  def test_hrandfield_without_count
    @mock_client.expects(:hrandfield).with("h", count: nil, withvalues: false).returns("f1")
    redis = build_redis

    assert_equal "f1", redis.hrandfield("h")
  end

  def test_hrandfield_with_count
    @mock_client.expects(:hrandfield).with("h", count: 2, withvalues: false).returns(%w[f1 f2])
    redis = build_redis

    assert_equal %w[f1 f2], redis.hrandfield("h", 2)
  end

  def test_hrandfield_with_values_but_no_count_raises
    redis = build_redis
    assert_raises(ArgumentError) { redis.hrandfield("h", nil, with_values: true) }
  end

  def test_hrandfield_with_values_and_count
    @mock_client.expects(:hrandfield).with("h", count: 2, withvalues: true).returns([%w[f1 v1]])
    redis = build_redis

    assert_equal [%w[f1 v1]], redis.hrandfield("h", 2, with_values: true)
  end

  # =================================================================
  # Hash field expiration commands
  # =================================================================

  def test_hexpire
    @mock_client.expects(:hexpire).with("h", 60, "f1", "f2", nx: false, xx: false, gt: false, lt: false).returns([1, 1])
    redis = build_redis

    assert_equal [1, 1], redis.hexpire("h", 60, "f1", "f2")
  end

  def test_hexpire_with_array_fields
    @mock_client.expects(:hexpire).with("h", 60, "f1", "f2", nx: false, xx: false, gt: false, lt: false).returns([1, 1])
    redis = build_redis

    assert_equal [1, 1], redis.hexpire("h", 60, %w[f1 f2])
  end

  def test_hpexpire
    @mock_client.expects(:hpexpire).with("h", 5000, "f1", nx: false, xx: false, gt: false, lt: false).returns([1])
    redis = build_redis

    assert_equal [1], redis.hpexpire("h", 5000, "f1")
  end

  def test_hexpireat
    @mock_client.expects(:hexpireat).with("h", 1_700_000_000, "f1", nx: false, xx: false, gt: false,
                                                                    lt: false).returns([1])
    redis = build_redis

    assert_equal [1], redis.hexpireat("h", 1_700_000_000, "f1")
  end

  def test_hpexpireat
    @mock_client.expects(:hpexpireat).with("h", 1_700_000_000_000, "f1", nx: false, xx: false, gt: false,
                                                                         lt: false).returns([1])
    redis = build_redis

    assert_equal [1], redis.hpexpireat("h", 1_700_000_000_000, "f1")
  end

  def test_httl
    @mock_client.expects(:httl).with("h", "f1").returns([60])
    redis = build_redis

    assert_equal [60], redis.httl("h", "f1")
  end

  def test_httl_with_array
    @mock_client.expects(:httl).with("h", "f1", "f2").returns([60, 120])
    redis = build_redis

    assert_equal [60, 120], redis.httl("h", %w[f1 f2])
  end

  def test_hpttl
    @mock_client.expects(:hpttl).with("h", "f1").returns([5000])
    redis = build_redis

    assert_equal [5000], redis.hpttl("h", "f1")
  end

  def test_hexpiretime
    @mock_client.expects(:hexpiretime).with("h", "f1").returns([1_700_000_000])
    redis = build_redis

    assert_equal [1_700_000_000], redis.hexpiretime("h", "f1")
  end

  def test_hpexpiretime
    @mock_client.expects(:hpexpiretime).with("h", "f1").returns([1_700_000_000_000])
    redis = build_redis

    assert_equal [1_700_000_000_000], redis.hpexpiretime("h", "f1")
  end

  def test_hpersist
    @mock_client.expects(:hpersist).with("h", "f1").returns([1])
    redis = build_redis

    assert_equal [1], redis.hpersist("h", "f1")
  end

  def test_hpersist_with_array
    @mock_client.expects(:hpersist).with("h", "f1", "f2").returns([1, 1])
    redis = build_redis

    assert_equal [1, 1], redis.hpersist("h", %w[f1 f2])
  end

  # =================================================================
  # List commands
  # =================================================================

  def test_lpush_single
    @mock_client.expects(:lpush).with("l", "v").returns(1)
    redis = build_redis

    assert_equal 1, redis.lpush("l", "v")
  end

  def test_lpush_array_flattened
    @mock_client.expects(:lpush).with("l", "v1", "v2").returns(2)
    redis = build_redis

    assert_equal 2, redis.lpush("l", %w[v1 v2])
  end

  def test_rpush
    @mock_client.expects(:rpush).with("l", "v1", "v2").returns(2)
    redis = build_redis

    assert_equal 2, redis.rpush("l", %w[v1 v2])
  end

  def test_lpushx
    @mock_client.expects(:lpushx).with("l", "v").returns(1)
    redis = build_redis

    assert_equal 1, redis.lpushx("l", "v")
  end

  def test_rpushx
    @mock_client.expects(:rpushx).with("l", "v").returns(1)
    redis = build_redis

    assert_equal 1, redis.rpushx("l", "v")
  end

  def test_lpop_without_count
    @mock_client.expects(:lpop).with("l", nil).returns("v")
    redis = build_redis

    assert_equal "v", redis.lpop("l")
  end

  def test_lpop_with_count
    @mock_client.expects(:lpop).with("l", 3).returns(%w[v1 v2 v3])
    redis = build_redis

    assert_equal %w[v1 v2 v3], redis.lpop("l", 3)
  end

  def test_rpop_without_count
    @mock_client.expects(:rpop).with("l", nil).returns("v")
    redis = build_redis

    assert_equal "v", redis.rpop("l")
  end

  def test_rpop_with_count
    @mock_client.expects(:rpop).with("l", 2).returns(%w[v1 v2])
    redis = build_redis

    assert_equal %w[v1 v2], redis.rpop("l", 2)
  end

  def test_lrange
    @mock_client.expects(:lrange).with("l", 0, -1).returns(%w[a b])
    redis = build_redis

    assert_equal %w[a b], redis.lrange("l", 0, -1)
  end

  def test_llen
    @mock_client.expects(:llen).with("l").returns(5)
    redis = build_redis

    assert_equal 5, redis.llen("l")
  end

  def test_lindex
    @mock_client.expects(:lindex).with("l", 2).returns("c")
    redis = build_redis

    assert_equal "c", redis.lindex("l", 2)
  end

  def test_lset
    @mock_client.expects(:lset).with("l", 0, "new").returns("OK")
    redis = build_redis

    assert_equal "OK", redis.lset("l", 0, "new")
  end

  def test_lrem
    @mock_client.expects(:lrem).with("l", 0, "v").returns(2)
    redis = build_redis

    assert_equal 2, redis.lrem("l", 0, "v")
  end

  def test_ltrim
    @mock_client.expects(:ltrim).with("l", 0, 5).returns("OK")
    redis = build_redis

    assert_equal "OK", redis.ltrim("l", 0, 5)
  end

  def test_linsert
    @mock_client.expects(:linsert).with("l", "BEFORE", "pivot", "v").returns(4)
    redis = build_redis

    assert_equal 4, redis.linsert("l", "BEFORE", "pivot", "v")
  end

  def test_rpoplpush
    @mock_client.expects(:rpoplpush).with("src", "dst").returns("v")
    redis = build_redis

    assert_equal "v", redis.rpoplpush("src", "dst")
  end

  def test_lmove
    @mock_client.expects(:lmove).with("src", "dst", "LEFT", "RIGHT").returns("v")
    redis = build_redis

    assert_equal "v", redis.lmove("src", "dst", "LEFT", "RIGHT")
  end

  def test_lmove_invalid_wherefrom_raises
    redis = build_redis
    assert_raises(ArgumentError) { redis.lmove("src", "dst", "INVALID", "RIGHT") }
  end

  def test_lmove_invalid_whereto_raises
    redis = build_redis
    assert_raises(ArgumentError) { redis.lmove("src", "dst", "LEFT", "INVALID") }
  end

  def test_blpop
    @mock_client.expects(:blpop).with("l", timeout: 5).returns(%w[l v])
    redis = build_redis

    assert_equal %w[l v], redis.blpop("l", timeout: 5)
  end

  def test_brpop
    @mock_client.expects(:brpop).with("l", timeout: 5).returns(%w[l v])
    redis = build_redis

    assert_equal %w[l v], redis.brpop("l", timeout: 5)
  end

  def test_brpoplpush
    @mock_client.expects(:brpoplpush).with("src", "dst", timeout: 5).returns("v")
    redis = build_redis

    assert_equal "v", redis.brpoplpush("src", "dst", timeout: 5)
  end

  def test_blmove
    @mock_client.expects(:blmove).with("src", "dst", "LEFT", "RIGHT", timeout: 5).returns("v")
    redis = build_redis

    assert_equal "v", redis.blmove("src", "dst", "LEFT", "RIGHT", timeout: 5)
  end

  def test_lmpop
    @mock_client.expects(:lmpop).with("l", direction: :left, count: nil).returns(["l", ["v"]])
    redis = build_redis

    assert_equal ["l", ["v"]], redis.lmpop("l")
  end

  def test_lmpop_with_modifier_right
    @mock_client.expects(:lmpop).with("l", direction: :right, count: 2).returns(["l", %w[v1 v2]])
    redis = build_redis

    assert_equal ["l", %w[v1 v2]], redis.lmpop("l", modifier: "RIGHT", count: 2)
  end

  def test_blmpop
    @mock_client.expects(:blmpop).with(5, "l", direction: :left, count: nil).returns(["l", ["v"]])
    redis = build_redis

    assert_equal ["l", ["v"]], redis.blmpop(5, "l")
  end

  def test_blmpop_with_modifier
    @mock_client.expects(:blmpop).with(5, "l", direction: :right, count: 1).returns(["l", ["v"]])
    redis = build_redis

    assert_equal ["l", ["v"]], redis.blmpop(5, "l", modifier: "RIGHT", count: 1)
  end

  # =================================================================
  # Set commands
  # =================================================================

  def test_sadd
    @mock_client.expects(:sadd).with("s", "m1").returns(1)
    redis = build_redis

    assert_equal 1, redis.sadd("s", "m1")
  end

  def test_sadd_array_flattened
    @mock_client.expects(:sadd).with("s", "m1", "m2").returns(2)
    redis = build_redis

    assert_equal 2, redis.sadd("s", %w[m1 m2])
  end

  def test_srem
    @mock_client.expects(:srem).with("s", "m1").returns(1)
    redis = build_redis

    assert_equal 1, redis.srem("s", "m1")
  end

  def test_srem_array_flattened
    @mock_client.expects(:srem).with("s", "m1", "m2").returns(2)
    redis = build_redis

    assert_equal 2, redis.srem("s", %w[m1 m2])
  end

  def test_sismember_true
    @mock_client.expects(:sismember).with("s", "m").returns(1)
    redis = build_redis

    assert redis.sismember("s", "m")
  end

  def test_sismember_false
    @mock_client.expects(:sismember).with("s", "m").returns(0)
    redis = build_redis

    refute redis.sismember("s", "m")
  end

  def test_smismember
    @mock_client.expects(:smismember).with("s", "m1", "m2").returns([1, 0])
    redis = build_redis

    assert_equal [true, false], redis.smismember("s", "m1", "m2")
  end

  def test_smembers
    @mock_client.expects(:smembers).with("s").returns(%w[m1 m2])
    redis = build_redis

    assert_equal %w[m1 m2], redis.smembers("s")
  end

  def test_scard
    @mock_client.expects(:scard).with("s").returns(3)
    redis = build_redis

    assert_equal 3, redis.scard("s")
  end

  def test_spop_without_count
    @mock_client.expects(:spop).with("s", nil).returns("m1")
    redis = build_redis

    assert_equal "m1", redis.spop("s")
  end

  def test_spop_with_count
    @mock_client.expects(:spop).with("s", 2).returns(%w[m1 m2])
    redis = build_redis

    assert_equal %w[m1 m2], redis.spop("s", 2)
  end

  def test_srandmember
    @mock_client.expects(:srandmember).with("s", nil).returns("m1")
    redis = build_redis

    assert_equal "m1", redis.srandmember("s")
  end

  def test_smove_true
    @mock_client.expects(:smove).with("src", "dst", "m").returns(1)
    redis = build_redis

    assert redis.smove("src", "dst", "m")
  end

  def test_smove_false
    @mock_client.expects(:smove).with("src", "dst", "m").returns(0)
    redis = build_redis

    refute redis.smove("src", "dst", "m")
  end

  def test_sinter
    @mock_client.expects(:sinter).with("s1", "s2").returns(["m"])
    redis = build_redis

    assert_equal ["m"], redis.sinter("s1", "s2")
  end

  def test_sinterstore
    @mock_client.expects(:sinterstore).with("dst", "s1", "s2").returns(1)
    redis = build_redis

    assert_equal 1, redis.sinterstore("dst", "s1", "s2")
  end

  def test_sintercard
    @mock_client.expects(:sintercard).with("s1", "s2", limit: 5).returns(2)
    redis = build_redis

    assert_equal 2, redis.sintercard("s1", "s2", limit: 5)
  end

  def test_sunion
    @mock_client.expects(:sunion).with("s1", "s2").returns(%w[m1 m2])
    redis = build_redis

    assert_equal %w[m1 m2], redis.sunion("s1", "s2")
  end

  def test_sunionstore
    @mock_client.expects(:sunionstore).with("dst", "s1").returns(2)
    redis = build_redis

    assert_equal 2, redis.sunionstore("dst", "s1")
  end

  def test_sdiff
    @mock_client.expects(:sdiff).with("s1", "s2").returns(["m1"])
    redis = build_redis

    assert_equal ["m1"], redis.sdiff("s1", "s2")
  end

  def test_sdiffstore
    @mock_client.expects(:sdiffstore).with("dst", "s1", "s2").returns(1)
    redis = build_redis

    assert_equal 1, redis.sdiffstore("dst", "s1", "s2")
  end

  def test_sscan
    @mock_client.expects(:sscan).with("s", 0, match: nil, count: nil).returns(["0", ["m1"]])
    redis = build_redis

    assert_equal ["0", ["m1"]], redis.sscan("s", 0)
  end

  def test_sscan_iter
    enumerator = Enumerator.new { |y| y.yield "m1" }
    @mock_client.expects(:sscan_iter).with("s", match: "*", count: 10).returns(enumerator)
    redis = build_redis

    assert_equal enumerator, redis.sscan_iter("s")
  end

  # =================================================================
  # Sorted set commands
  # =================================================================

  def test_zadd_single_member_returns_boolean
    @mock_client.expects(:zadd).with("z", 1.0, "m", nx: false, xx: false, gt: false, lt: false, ch: false,
                                                    incr: false).returns(1)
    redis = build_redis

    assert redis.zadd("z", 1.0, "m")
  end

  def test_zadd_single_member_returns_false_when_zero
    @mock_client.expects(:zadd).with("z", 1.0, "m", nx: false, xx: false, gt: false, lt: false, ch: false,
                                                    incr: false).returns(0)
    redis = build_redis

    refute redis.zadd("z", 1.0, "m")
  end

  def test_zadd_flat_array
    @mock_client.expects(:zadd).with("z", 1.0, "m1", 2.0, "m2", nx: false, xx: false, gt: false, lt: false, ch: false,
                                                                incr: false).returns(2)
    redis = build_redis

    assert_equal 2, redis.zadd("z", [1.0, "m1", 2.0, "m2"])
  end

  def test_zadd_nested_array
    @mock_client.expects(:zadd).with("z", 1.0, "m1", 2.0, "m2", nx: false, xx: false, gt: false, lt: false, ch: false,
                                                                incr: false).returns(2)
    redis = build_redis

    assert_equal 2, redis.zadd("z", [[1.0, "m1"], [2.0, "m2"]])
  end

  def test_zadd_empty_array_returns_zero
    redis = build_redis

    assert_equal 0, redis.zadd("z", [])
  end

  def test_zadd_with_incr_returns_float
    @mock_client.expects(:zadd).with("z", 1.0, "m", nx: false, xx: false, gt: false, lt: false, ch: false,
                                                    incr: true).returns("3.5")
    redis = build_redis

    assert_in_delta(3.5, redis.zadd("z", 1.0, "m", incr: true))
  end

  def test_zadd_multiple_args_flattened
    @mock_client.expects(:zadd).with("z", 1.0, "m1", 2.0, "m2", nx: false, xx: false, gt: false, lt: false, ch: false,
                                                                incr: false).returns(2)
    redis = build_redis

    assert_equal 2, redis.zadd("z", 1.0, "m1", 2.0, "m2")
  end

  def test_zrem_single_member_returns_boolean
    @mock_client.expects(:zrem).with("z", "m").returns(1)
    redis = build_redis

    assert redis.zrem("z", "m")
  end

  def test_zrem_single_member_returns_false
    @mock_client.expects(:zrem).with("z", "m").returns(0)
    redis = build_redis

    refute redis.zrem("z", "m")
  end

  def test_zrem_multiple_members_returns_count
    @mock_client.expects(:zrem).with("z", "m1", "m2").returns(2)
    redis = build_redis

    assert_equal 2, redis.zrem("z", "m1", "m2")
  end

  def test_zrem_empty_members_returns_zero
    redis = build_redis

    assert_equal 0, redis.zrem("z")
  end

  def test_zscore
    @mock_client.expects(:zscore).with("z", "m").returns("3.5")
    redis = build_redis

    assert_in_delta(3.5, redis.zscore("z", "m"))
  end

  def test_zscore_nil
    @mock_client.expects(:zscore).with("z", "m").returns(nil)
    redis = build_redis

    assert_nil redis.zscore("z", "m")
  end

  def test_zmscore
    @mock_client.expects(:zmscore).with("z", "m1", "m2").returns(["1.5", nil])
    redis = build_redis
    result = redis.zmscore("z", "m1", "m2")

    assert_in_delta(1.5, result[0])
    assert_nil result[1]
  end

  def test_zrank_without_score
    @mock_client.expects(:zrank).with("z", "m", withscore: false).returns(2)
    redis = build_redis

    assert_equal 2, redis.zrank("z", "m")
  end

  def test_zrank_with_score
    @mock_client.expects(:zrank).with("z", "m", withscore: true).returns([2, "3.5"])
    redis = build_redis
    result = redis.zrank("z", "m", with_score: true)

    assert_equal [2, 3.5], result
  end

  def test_zrank_with_score_nil_result
    @mock_client.expects(:zrank).with("z", "m", withscore: true).returns(nil)
    redis = build_redis

    assert_nil redis.zrank("z", "m", withscore: true)
  end

  def test_zrevrank_without_score
    @mock_client.expects(:zrevrank).with("z", "m", withscore: false).returns(0)
    redis = build_redis

    assert_equal 0, redis.zrevrank("z", "m")
  end

  def test_zrevrank_with_score
    @mock_client.expects(:zrevrank).with("z", "m", withscore: true).returns([0, "5.0"])
    redis = build_redis

    assert_equal [0, 5.0], redis.zrevrank("z", "m", withscore: true)
  end

  def test_zrevrank_with_score_nil_result
    @mock_client.expects(:zrevrank).with("z", "m", withscore: true).returns(nil)
    redis = build_redis

    assert_nil redis.zrevrank("z", "m", with_score: true)
  end

  def test_zcard
    @mock_client.expects(:zcard).with("z").returns(5)
    redis = build_redis

    assert_equal 5, redis.zcard("z")
  end

  def test_zcount
    @mock_client.expects(:zcount).with("z", "-inf", "+inf").returns(10)
    redis = build_redis

    assert_equal 10, redis.zcount("z", "-inf", "+inf")
  end

  def test_zrange_without_scores
    @mock_client.expects(:zrange).with("z", 0, -1, byscore: false, bylex: false, rev: false, limit: nil,
                                                   withscores: false).returns(%w[m1 m2])
    redis = build_redis

    assert_equal %w[m1 m2], redis.zrange("z", 0, -1)
  end

  def test_zrange_with_scores_flat_array
    @mock_client.expects(:zrange).with("z", 0, -1, byscore: false, bylex: false, rev: false, limit: nil,
                                                   withscores: true).returns(["m1", "1.0", "m2", "2.0"])
    redis = build_redis
    result = redis.zrange("z", 0, -1, withscores: true)

    assert_equal [["m1", 1.0], ["m2", 2.0]], result
  end

  def test_zrange_with_scores_nested_array
    @mock_client.expects(:zrange).with("z", 0, -1, byscore: false, bylex: false, rev: false, limit: nil,
                                                   withscores: true).returns([["m1", "1.0"], ["m2", "2.0"]])
    redis = build_redis
    result = redis.zrange("z", 0, -1, with_scores: true)

    assert_equal [["m1", 1.0], ["m2", 2.0]], result
  end

  def test_zrangestore
    @mock_client.expects(:zrangestore).with("dst", "z", 0, -1, byscore: false, bylex: false, rev: false,
                                                               limit: nil).returns(3)
    redis = build_redis

    assert_equal 3, redis.zrangestore("dst", "z", 0, -1)
  end

  def test_zrangestore_with_by_score
    @mock_client.expects(:zrangestore).with("dst", "z", 0, 100, byscore: true, bylex: false, rev: false,
                                                                limit: nil).returns(2)
    redis = build_redis

    assert_equal 2, redis.zrangestore("dst", "z", 0, 100, by_score: true)
  end

  def test_zrangestore_with_by_lex
    @mock_client.expects(:zrangestore).with("dst", "z", "[a", "[z", byscore: false, bylex: true, rev: false,
                                                                    limit: nil).returns(2)
    redis = build_redis

    assert_equal 2, redis.zrangestore("dst", "z", "[a", "[z", by_lex: true)
  end

  def test_zrevrange_without_scores
    @mock_client.expects(:zrevrange).with("z", 0, -1, withscores: false).returns(%w[m2 m1])
    redis = build_redis

    assert_equal %w[m2 m1], redis.zrevrange("z", 0, -1)
  end

  def test_zrevrange_with_scores
    @mock_client.expects(:zrevrange).with("z", 0, -1, withscores: true).returns([["m2", "2.0"], ["m1", "1.0"]])
    redis = build_redis
    result = redis.zrevrange("z", 0, -1, with_scores: true)

    assert_equal [["m2", 2.0], ["m1", 1.0]], result
  end

  def test_zrangebyscore_without_scores
    @mock_client.expects(:zrangebyscore).with("z", "-inf", "+inf", withscores: false, limit: nil).returns(["m1"])
    redis = build_redis

    assert_equal ["m1"], redis.zrangebyscore("z", "-inf", "+inf")
  end

  def test_zrangebyscore_with_scores
    @mock_client.expects(:zrangebyscore).with("z", 0, 100, withscores: true, limit: nil).returns([["m1", "1.0"]])
    redis = build_redis
    result = redis.zrangebyscore("z", 0, 100, withscores: true)

    assert_equal [["m1", 1.0]], result
  end

  def test_zrevrangebyscore
    @mock_client.expects(:zrevrangebyscore).with("z", "+inf", "-inf", withscores: false,
                                                                      limit: nil).returns(%w[m2 m1])
    redis = build_redis

    assert_equal %w[m2 m1], redis.zrevrangebyscore("z", "+inf", "-inf")
  end

  def test_zrevrangebyscore_with_scores
    @mock_client.expects(:zrevrangebyscore).with("z", "+inf", "-inf", withscores: true,
                                                                      limit: nil).returns([["m2", "2.0"]])
    redis = build_redis
    result = redis.zrevrangebyscore("z", "+inf", "-inf", with_scores: true)

    assert_equal [["m2", 2.0]], result
  end

  def test_zincrby
    @mock_client.expects(:zincrby).with("z", 2, "m").returns("5.0")
    redis = build_redis

    assert_in_delta(5.0, redis.zincrby("z", 2, "m"))
  end

  def test_zremrangebyrank
    @mock_client.expects(:zremrangebyrank).with("z", 0, 2).returns(3)
    redis = build_redis

    assert_equal 3, redis.zremrangebyrank("z", 0, 2)
  end

  def test_zremrangebyscore
    @mock_client.expects(:zremrangebyscore).with("z", 0, 100).returns(5)
    redis = build_redis

    assert_equal 5, redis.zremrangebyscore("z", 0, 100)
  end

  def test_zpopmin
    @mock_client.expects(:zpopmin).with("z", nil).returns(["m", "1.0"])
    redis = build_redis

    assert_equal ["m", "1.0"], redis.zpopmin("z")
  end

  def test_zpopmin_with_count
    @mock_client.expects(:zpopmin).with("z", 2).returns([["m1", "1.0"], ["m2", "2.0"]])
    redis = build_redis

    assert_equal [["m1", "1.0"], ["m2", "2.0"]], redis.zpopmin("z", 2)
  end

  def test_zpopmax
    @mock_client.expects(:zpopmax).with("z", nil).returns(["m", "5.0"])
    redis = build_redis

    assert_equal ["m", "5.0"], redis.zpopmax("z")
  end

  def test_bzpopmin
    @mock_client.expects(:bzpopmin).with("z", timeout: 0).returns(["z", "m", "1.0"])
    redis = build_redis

    assert_equal ["z", "m", "1.0"], redis.bzpopmin("z")
  end

  def test_bzpopmax
    @mock_client.expects(:bzpopmax).with("z", timeout: 5).returns(["z", "m", "5.0"])
    redis = build_redis

    assert_equal ["z", "m", "5.0"], redis.bzpopmax("z", timeout: 5)
  end

  def test_zscan
    @mock_client.expects(:zscan).with("z", 0, match: nil, count: nil).returns(["0", [["m", "1.0"]]])
    redis = build_redis

    assert_equal ["0", [["m", "1.0"]]], redis.zscan("z", 0)
  end

  def test_zscan_iter
    enumerator = Enumerator.new { |y| y.yield ["m", "1.0"] }
    @mock_client.expects(:zscan_iter).with("z", match: "*", count: 10).returns(enumerator)
    redis = build_redis

    assert_equal enumerator, redis.zscan_iter("z")
  end

  def test_zinterstore
    @mock_client.expects(:zinterstore).with("dst", %w[z1 z2], weights: nil, aggregate: nil).returns(1)
    redis = build_redis

    assert_equal 1, redis.zinterstore("dst", %w[z1 z2])
  end

  def test_zunionstore
    @mock_client.expects(:zunionstore).with("dst", %w[z1 z2], weights: [1, 2], aggregate: "MAX").returns(3)
    redis = build_redis

    assert_equal 3, redis.zunionstore("dst", %w[z1 z2], weights: [1, 2], aggregate: "MAX")
  end

  def test_zunion_without_scores
    @mock_client.expects(:zunion).with(%w[z1 z2], weights: nil, aggregate: nil,
                                                  withscores: false).returns(%w[m1 m2])
    redis = build_redis

    assert_equal %w[m1 m2], redis.zunion("z1", "z2")
  end

  def test_zunion_with_scores
    @mock_client.expects(:zunion).with(["z1"], weights: nil, aggregate: nil, withscores: true).returns([["m1", "1.0"]])
    redis = build_redis
    result = redis.zunion("z1", with_scores: true)

    assert_equal [["m1", 1.0]], result
  end

  def test_zinter_without_scores
    @mock_client.expects(:zinter).with(%w[z1 z2], weights: nil, aggregate: nil, withscores: false).returns(["m1"])
    redis = build_redis

    assert_equal ["m1"], redis.zinter("z1", "z2")
  end

  def test_zinter_with_scores
    @mock_client.expects(:zinter).with(["z1"], weights: nil, aggregate: nil, withscores: true).returns([["m1", "2.0"]])
    redis = build_redis
    result = redis.zinter("z1", withscores: true)

    assert_equal [["m1", 2.0]], result
  end

  def test_zdiff_without_scores
    @mock_client.expects(:zdiff).with(%w[z1 z2], withscores: false).returns(["m1"])
    redis = build_redis

    assert_equal ["m1"], redis.zdiff("z1", "z2")
  end

  def test_zdiff_with_scores
    @mock_client.expects(:zdiff).with(["z1"], withscores: true).returns([["m1", "1.0"]])
    redis = build_redis
    result = redis.zdiff("z1", with_scores: true)

    assert_equal [["m1", 1.0]], result
  end

  def test_zdiffstore
    @mock_client.expects(:zdiffstore).with("dst", %w[z1 z2]).returns(1)
    redis = build_redis

    assert_equal 1, redis.zdiffstore("dst", %w[z1 z2])
  end

  def test_zintercard
    @mock_client.expects(:zintercard).with("z1", "z2", limit: nil).returns(2)
    redis = build_redis

    assert_equal 2, redis.zintercard("z1", "z2")
  end

  def test_zlexcount
    @mock_client.expects(:zlexcount).with("z", "-", "+").returns(5)
    redis = build_redis

    assert_equal 5, redis.zlexcount("z", "-", "+")
  end

  def test_zrangebylex
    @mock_client.expects(:zrangebylex).with("z", "[a", "[z", limit: nil).returns(%w[a b])
    redis = build_redis

    assert_equal %w[a b], redis.zrangebylex("z", "[a", "[z")
  end

  def test_zrevrangebylex
    @mock_client.expects(:zrevrangebylex).with("z", "[z", "[a", limit: nil).returns(%w[z b])
    redis = build_redis

    assert_equal %w[z b], redis.zrevrangebylex("z", "[z", "[a")
  end

  def test_zremrangebylex
    @mock_client.expects(:zremrangebylex).with("z", "[a", "[c").returns(3)
    redis = build_redis

    assert_equal 3, redis.zremrangebylex("z", "[a", "[c")
  end

  def test_zrandmember_without_scores
    @mock_client.expects(:zrandmember).with("z", nil, withscores: false).returns("m1")
    redis = build_redis

    assert_equal "m1", redis.zrandmember("z")
  end

  def test_zrandmember_with_scores
    @mock_client.expects(:zrandmember).with("z", 2, withscores: true).returns(["m1", "1.0", "m2", "2.0"])
    redis = build_redis
    result = redis.zrandmember("z", 2, withscores: true)

    assert_equal [["m1", 1.0], ["m2", 2.0]], result
  end

  def test_zrandmember_with_scores_non_array
    @mock_client.expects(:zrandmember).with("z", nil, withscores: true).returns(nil)
    redis = build_redis

    assert_nil redis.zrandmember("z", nil, with_scores: true)
  end

  def test_zmpop
    @mock_client.expects(:zmpop).with("z", modifier: :min, count: nil).returns(["z", [["m1", "1.0"]]])
    redis = build_redis
    result = redis.zmpop("z")

    assert_equal "z", result[0]
    assert_equal [["m1", 1.0]], result[1]
  end

  def test_zmpop_nil_result
    @mock_client.expects(:zmpop).with("z", modifier: :min, count: nil).returns(nil)
    redis = build_redis

    assert_nil redis.zmpop("z")
  end

  def test_zmpop_with_modifier
    @mock_client.expects(:zmpop).with("z", modifier: :max, count: 2).returns(["z", [["m2", "2.0"]]])
    redis = build_redis
    result = redis.zmpop("z", modifier: "MAX", count: 2)

    assert_equal "z", result[0]
  end

  def test_bzmpop
    @mock_client.expects(:bzmpop).with(5, "z", modifier: :min, count: nil).returns(["z", [["m1", "1.0"]]])
    redis = build_redis
    result = redis.bzmpop(5, "z")

    assert_equal "z", result[0]
    assert_equal [["m1", 1.0]], result[1]
  end

  def test_bzmpop_nil_result
    @mock_client.expects(:bzmpop).with(5, "z", modifier: :min, count: nil).returns(nil)
    redis = build_redis

    assert_nil redis.bzmpop(5, "z")
  end

  # =================================================================
  # parse_float (tested indirectly via zscore/zincrby)
  # =================================================================

  def test_parse_float_with_infinity
    @mock_client.expects(:zscore).with("z", "m").returns("inf")
    redis = build_redis

    assert_equal Float::INFINITY, redis.zscore("z", "m")
  end

  def test_parse_float_with_plus_infinity
    @mock_client.expects(:zscore).with("z", "m").returns("+inf")
    redis = build_redis

    assert_equal Float::INFINITY, redis.zscore("z", "m")
  end

  def test_parse_float_with_minus_infinity
    @mock_client.expects(:zscore).with("z", "m").returns("-inf")
    redis = build_redis

    assert_equal(-Float::INFINITY, redis.zscore("z", "m"))
  end

  def test_parse_float_with_float_value
    @mock_client.expects(:zscore).with("z", "m").returns(3.14)
    redis = build_redis

    assert_in_delta(3.14, redis.zscore("z", "m"))
  end

  def test_parse_float_with_integer_string
    @mock_client.expects(:zscore).with("z", "m").returns("42")
    redis = build_redis

    assert_in_delta(42.0, redis.zscore("z", "m"))
  end

  # =================================================================
  # transform_scores (tested indirectly via zrange withscores)
  # =================================================================

  def test_transform_scores_empty_array
    @mock_client.expects(:zrange).with("z", 0, -1, byscore: false, bylex: false, rev: false, limit: nil,
                                                   withscores: true).returns([])
    redis = build_redis

    assert_empty redis.zrange("z", 0, -1, withscores: true)
  end

  # =================================================================
  # Scripting commands
  # =================================================================

  def test_eval_with_keyword_args
    @mock_client.expects(:eval).with("return 1", 0).returns(1)
    redis = build_redis

    assert_equal 1, redis.eval("return 1")
  end

  def test_eval_with_keyword_keys_and_argv
    @mock_client.expects(:eval).with("script", 2, "k1", "k2", "a1").returns("OK")
    redis = build_redis

    assert_equal "OK", redis.eval("script", keys: %w[k1 k2], argv: ["a1"])
  end

  def test_eval_with_3_positional_args
    @mock_client.expects(:eval).with("script", 1, "k1", "a1").returns("OK")
    redis = build_redis

    assert_equal "OK", redis.eval("script", ["k1"], ["a1"])
  end

  def test_eval_with_2_positional_args
    @mock_client.expects(:eval).with("script", 2, "k1", "k2").returns("OK")
    redis = build_redis

    assert_equal "OK", redis.eval("script", %w[k1 k2])
  end

  def test_eval_wrong_number_of_args
    redis = build_redis
    assert_raises(ArgumentError) { redis.eval("s1", "s2", "s3", "s4") }
  end

  def test_evalsha_with_keyword_args
    @mock_client.expects(:evalsha).with("abc123", 0).returns(1)
    redis = build_redis

    assert_equal 1, redis.evalsha("abc123")
  end

  def test_evalsha_with_keyword_keys_and_argv
    @mock_client.expects(:evalsha).with("abc", 1, "k1", "a1").returns("OK")
    redis = build_redis

    assert_equal "OK", redis.evalsha("abc", keys: ["k1"], argv: ["a1"])
  end

  def test_evalsha_with_3_positional_args
    @mock_client.expects(:evalsha).with("abc", 1, "k1", "a1").returns("OK")
    redis = build_redis

    assert_equal "OK", redis.evalsha("abc", ["k1"], ["a1"])
  end

  def test_evalsha_with_2_positional_args
    @mock_client.expects(:evalsha).with("abc", 2, "k1", "k2").returns("OK")
    redis = build_redis

    assert_equal "OK", redis.evalsha("abc", %w[k1 k2])
  end

  def test_evalsha_wrong_number_of_args
    redis = build_redis
    assert_raises(ArgumentError) { redis.evalsha("a", "b", "c", "d") }
  end

  # =================================================================
  # Script subcommands
  # =================================================================

  def test_script_load
    @mock_client.expects(:script_load).with("return 1").returns("sha123")
    redis = build_redis

    assert_equal "sha123", redis.script("load", "return 1")
  end

  def test_script_exists_single_sha_returns_boolean
    @mock_client.expects(:script_exists).with("sha1").returns([true])
    redis = build_redis

    assert redis.script("exists", "sha1")
  end

  def test_script_exists_single_sha_with_integer
    @mock_client.expects(:script_exists).with("sha1").returns([1])
    redis = build_redis

    assert redis.script("exists", "sha1")
  end

  def test_script_exists_array_returns_array
    @mock_client.expects(:script_exists).with("sha1", "sha2").returns([true, false])
    redis = build_redis

    assert_equal [true, false], redis.script("exists", %w[sha1 sha2])
  end

  def test_script_exists_multiple_shas_returns_array
    @mock_client.expects(:script_exists).with("sha1", "sha2").returns([1, 0])
    redis = build_redis
    result = redis.script("exists", "sha1", "sha2")

    assert_equal [true, false], result
  end

  def test_script_flush
    @mock_client.expects(:script_flush).with(nil).returns("OK")
    redis = build_redis

    assert_equal "OK", redis.script("flush")
  end

  def test_script_kill
    @mock_client.expects(:script_kill).returns("OK")
    redis = build_redis

    assert_equal "OK", redis.script("kill")
  end

  def test_script_unknown_subcommand
    @mock_client.expects(:call).with("SCRIPT", "DEBUG", "yes").returns("OK")
    redis = build_redis

    assert_equal "OK", redis.script("debug", "yes")
  end

  def test_script_load_direct
    @mock_client.expects(:script_load).with("return 1").returns("sha")
    redis = build_redis

    assert_equal "sha", redis.script_load("return 1")
  end

  def test_script_exists_direct
    @mock_client.expects(:script_exists).with("sha1").returns([1])
    redis = build_redis

    assert redis.script_exists("sha1")
  end

  def test_script_flush_direct
    @mock_client.expects(:script_flush).with(nil).returns("OK")
    redis = build_redis

    assert_equal "OK", redis.script_flush
  end

  def test_script_flush_with_mode
    @mock_client.expects(:script_flush).with("ASYNC").returns("OK")
    redis = build_redis

    assert_equal "OK", redis.script_flush("ASYNC")
  end

  def test_script_kill_direct
    @mock_client.expects(:script_kill).returns("OK")
    redis = build_redis

    assert_equal "OK", redis.script_kill
  end

  # =================================================================
  # HyperLogLog commands
  # =================================================================

  def test_pfadd_returns_true
    @mock_client.expects(:pfadd).with("hll", "a", "b").returns(1)
    redis = build_redis

    assert redis.pfadd("hll", "a", "b")
  end

  def test_pfadd_returns_false
    @mock_client.expects(:pfadd).with("hll", "a").returns(0)
    redis = build_redis

    refute redis.pfadd("hll", "a")
  end

  def test_pfcount
    @mock_client.expects(:pfcount).with("hll").returns(5)
    redis = build_redis

    assert_equal 5, redis.pfcount("hll")
  end

  def test_pfmerge
    @mock_client.expects(:pfmerge).with("dst", "src1", "src2").returns("OK")
    redis = build_redis

    assert_equal "OK", redis.pfmerge("dst", "src1", "src2")
  end

  # =================================================================
  # Geo commands
  # =================================================================

  def test_geoadd
    @mock_client.expects(:geoadd).with("geo", 13.361, 38.115, "Palermo", nx: false, xx: false, ch: false).returns(1)
    redis = build_redis

    assert_equal 1, redis.geoadd("geo", 13.361, 38.115, "Palermo")
  end

  def test_geopos
    @mock_client.expects(:geopos).with("geo", "Palermo").returns([[13.361, 38.115]])
    redis = build_redis

    assert_equal [[13.361, 38.115]], redis.geopos("geo", "Palermo")
  end

  def test_geodist
    @mock_client.expects(:geodist).with("geo", "P", "C", unit: "km").returns("166.2742")
    redis = build_redis

    assert_equal "166.2742", redis.geodist("geo", "P", "C", unit: "km")
  end

  def test_geohash
    @mock_client.expects(:geohash).with("geo", "Palermo").returns(["sqc8b49rny0"])
    redis = build_redis

    assert_equal ["sqc8b49rny0"], redis.geohash("geo", "Palermo")
  end

  def test_geosearch
    @mock_client.expects(:geosearch).with("geo", fromlonlat: [15.0, 37.0], byradius: [200, "km"]).returns(["Palermo"])
    redis = build_redis

    assert_equal ["Palermo"], redis.geosearch("geo", fromlonlat: [15.0, 37.0], byradius: [200, "km"])
  end

  def test_geosearchstore
    @mock_client.expects(:geosearchstore).with("dst", "geo", fromlonlat: [15.0, 37.0], byradius: [200, "km"]).returns(1)
    redis = build_redis

    assert_equal 1, redis.geosearchstore("dst", "geo", fromlonlat: [15.0, 37.0], byradius: [200, "km"])
  end

  # =================================================================
  # Bitmap commands
  # =================================================================

  def test_setbit
    @mock_client.expects(:setbit).with("bm", 7, 1).returns(0)
    redis = build_redis

    assert_equal 0, redis.setbit("bm", 7, 1)
  end

  def test_getbit
    @mock_client.expects(:getbit).with("bm", 7).returns(1)
    redis = build_redis

    assert_equal 1, redis.getbit("bm", 7)
  end

  def test_bitcount_without_range
    @mock_client.expects(:bitcount).with("bm", nil, nil, nil).returns(5)
    redis = build_redis

    assert_equal 5, redis.bitcount("bm")
  end

  def test_bitcount_with_range
    @mock_client.expects(:bitcount).with("bm", 0, 10, nil).returns(3)
    redis = build_redis

    assert_equal 3, redis.bitcount("bm", 0, 10)
  end

  def test_bitcount_with_scale
    @mock_client.expects(:bitcount).with("bm", 0, 10, "BYTE").returns(3)
    redis = build_redis

    assert_equal 3, redis.bitcount("bm", 0, 10, scale: :byte)
  end

  def test_bitpos
    @mock_client.expects(:bitpos).with("bm", 1, nil, nil, nil).returns(7)
    redis = build_redis

    assert_equal 7, redis.bitpos("bm", 1)
  end

  def test_bitpos_with_range_and_scale
    @mock_client.expects(:bitpos).with("bm", 1, 0, 10, "BIT").returns(3)
    redis = build_redis

    assert_equal 3, redis.bitpos("bm", 1, 0, 10, scale: :bit)
  end

  def test_bitop
    @mock_client.expects(:bitop).with("AND", "dst", "k1", "k2").returns(4)
    redis = build_redis

    assert_equal 4, redis.bitop("AND", "dst", "k1", "k2")
  end

  def test_bitop_array_flattened
    @mock_client.expects(:bitop).with("OR", "dst", "k1", "k2").returns(4)
    redis = build_redis

    assert_equal 4, redis.bitop("OR", "dst", %w[k1 k2])
  end

  def test_bitfield
    @mock_client.expects(:bitfield).with("bf", "GET", "u8", 0).returns([42])
    redis = build_redis

    assert_equal [42], redis.bitfield("bf", "GET", "u8", 0)
  end

  def test_bitfield_ro
    @mock_client.expects(:bitfield_ro).with("bf", "GET", "u8", 0).returns([42])
    redis = build_redis

    assert_equal [42], redis.bitfield_ro("bf", "GET", "u8", 0)
  end

  # =================================================================
  # Server commands
  # =================================================================

  def test_info
    @mock_client.expects(:info).with(nil).returns("# Server\nredis_version:7.0\nprocess_id:123\n")
    redis = build_redis
    result = redis.info

    assert_equal "7.0", result["redis_version"]
    assert_equal "123", result["process_id"]
  end

  def test_info_parses_comments_and_empty_lines
    @mock_client.expects(:info).with("server").returns("# Server\n\nredis_version:7.0\n")
    redis = build_redis
    result = redis.info("server")

    assert_equal({ "redis_version" => "7.0" }, result)
  end

  def test_info_skips_lines_without_colon
    @mock_client.expects(:info).with(nil).returns("nocolon\nkey:value\n")
    redis = build_redis
    result = redis.info

    assert_equal({ "key" => "value" }, result)
  end

  def test_dbsize
    @mock_client.expects(:dbsize).returns(42)
    redis = build_redis

    assert_equal 42, redis.dbsize
  end

  def test_flushdb
    @mock_client.expects(:flushdb).with(async: false).returns("OK")
    redis = build_redis

    assert_equal "OK", redis.flushdb
  end

  def test_flushdb_async
    @mock_client.expects(:flushdb).with(async: true).returns("OK")
    redis = build_redis

    assert_equal "OK", redis.flushdb(async: true)
  end

  def test_flushall
    @mock_client.expects(:flushall).with(async: false).returns("OK")
    redis = build_redis

    assert_equal "OK", redis.flushall
  end

  def test_save
    @mock_client.expects(:save).returns("OK")
    redis = build_redis

    assert_equal "OK", redis.save
  end

  def test_bgsave
    @mock_client.expects(:bgsave).returns("OK")
    redis = build_redis

    assert_equal "OK", redis.bgsave
  end

  def test_bgrewriteaof
    @mock_client.expects(:bgrewriteaof).returns("OK")
    redis = build_redis

    assert_equal "OK", redis.bgrewriteaof
  end

  def test_lastsave
    @mock_client.expects(:lastsave).returns(1_700_000_000)
    redis = build_redis

    assert_equal 1_700_000_000, redis.lastsave
  end

  def test_time
    @mock_client.expects(:time).returns([1_700_000_000, 123_456])
    redis = build_redis

    assert_equal [1_700_000_000, 123_456], redis.time
  end

  # =================================================================
  # Config commands
  # =================================================================

  def test_config_get
    @mock_client.expects(:config_get).with("maxmemory").returns(%w[maxmemory 0])
    redis = build_redis

    assert_equal({ "maxmemory" => "0" }, redis.config("get", "maxmemory"))
  end

  def test_config_get_hash_result
    @mock_client.expects(:config_get).with("maxmemory").returns({ "maxmemory" => "0" })
    redis = build_redis

    assert_equal({ "maxmemory" => "0" }, redis.config("get", "maxmemory"))
  end

  def test_config_set
    @mock_client.expects(:config_set).with("maxmemory", "100mb").returns("OK")
    redis = build_redis

    assert_equal "OK", redis.config("set", "maxmemory", "100mb")
  end

  def test_config_rewrite
    @mock_client.expects(:config_rewrite).returns("OK")
    redis = build_redis

    assert_equal "OK", redis.config("rewrite")
  end

  def test_config_resetstat
    @mock_client.expects(:config_resetstat).returns("OK")
    redis = build_redis

    assert_equal "OK", redis.config("resetstat")
  end

  def test_config_unknown_subcommand
    @mock_client.expects(:call).with("CONFIG", "FOO", "bar").returns("OK")
    redis = build_redis

    assert_equal "OK", redis.config("foo", "bar")
  end

  def test_config_get_direct
    @mock_client.expects(:config_get).with("maxmemory").returns(%w[maxmemory 0])
    redis = build_redis

    assert_equal({ "maxmemory" => "0" }, redis.config_get("maxmemory"))
  end

  def test_config_set_direct
    @mock_client.expects(:config_set).with("maxmemory", "100mb").returns("OK")
    redis = build_redis

    assert_equal "OK", redis.config_set("maxmemory", "100mb")
  end

  def test_config_rewrite_direct
    @mock_client.expects(:config_rewrite).returns("OK")
    redis = build_redis

    assert_equal "OK", redis.config_rewrite
  end

  def test_config_resetstat_direct
    @mock_client.expects(:config_resetstat).returns("OK")
    redis = build_redis

    assert_equal "OK", redis.config_resetstat
  end

  # =================================================================
  # Client commands
  # =================================================================

  def test_client_list
    @mock_client.expects(:client_list).returns("id=1 addr=127.0.0.1\n")
    redis = build_redis

    assert_equal "id=1 addr=127.0.0.1\n", redis.client_list
  end

  def test_client_getname
    @mock_client.expects(:client_getname).returns("myconn")
    redis = build_redis

    assert_equal "myconn", redis.client_getname
  end

  def test_client_setname
    @mock_client.expects(:client_setname).with("myconn").returns("OK")
    redis = build_redis

    assert_equal "OK", redis.client_setname("myconn")
  end

  def test_client_kill
    @mock_client.expects(:client_kill).with(addr: "127.0.0.1:6379").returns(1)
    redis = build_redis

    assert_equal 1, redis.client_kill(addr: "127.0.0.1:6379")
  end

  # =================================================================
  # Debug / Slowlog
  # =================================================================

  def test_debug_object
    @mock_client.expects(:debug_object).with("k").returns("Value at:0x123")
    redis = build_redis

    assert_equal "Value at:0x123", redis.debug_object("k")
  end

  def test_slowlog
    @mock_client.expects(:slowlog).with("get", 10).returns([])
    redis = build_redis

    assert_empty redis.slowlog("get", 10)
  end

  # =================================================================
  # Watch / Unwatch
  # =================================================================

  def test_watch_without_block
    @mock_client.expects(:watch).with("k1", "k2").returns("OK")
    redis = build_redis

    assert_equal "OK", redis.watch("k1", "k2")
  end

  def test_watch_with_block_yields_self
    @mock_client.expects(:watch).with("k1").yields.returns("OK")
    redis = build_redis
    yielded_obj = nil
    redis.watch("k1") { |r| yielded_obj = r }

    assert_equal redis, yielded_obj
  end

  def test_watch_with_array_arg
    @mock_client.expects(:watch).with("k1", "k2").returns("OK")
    redis = build_redis

    assert_equal "OK", redis.watch(%w[k1 k2])
  end

  def test_unwatch
    @mock_client.expects(:unwatch).returns("OK")
    redis = build_redis

    assert_equal "OK", redis.unwatch
  end

  # =================================================================
  # Pipeline
  # =================================================================

  def test_pipelined_returns_results
    mock_connection = mock("connection")
    @mock_client.stubs(:send).with(:ensure_connected)
    @mock_client.stubs(:instance_variable_get).with(:@connection).returns(mock_connection)

    mock_pipeline = mock("pipeline")
    mock_pipeline.expects(:call_2args).with("SET", "k", "v")
    mock_pipeline.expects(:call_1arg).with("GET", "k")
    mock_pipeline.expects(:execute).returns(%w[OK v])

    RedisRuby::Pipeline.stubs(:new).with(mock_connection).returns(mock_pipeline)

    redis = build_redis
    results = redis.pipelined do |pipe|
      pipe.set("k", "v")
      pipe.get("k")
    end

    assert_equal %w[OK v], results
  end

  def test_pipelined_with_error_and_exception_true
    mock_connection = mock("connection")
    @mock_client.stubs(:send).with(:ensure_connected)
    @mock_client.stubs(:instance_variable_get).with(:@connection).returns(mock_connection)

    cmd_error = RedisRuby::CommandError.new("ERR something")

    mock_pipeline = mock("pipeline")
    mock_pipeline.expects(:call_2args).with("SET", "k", "v")
    mock_pipeline.expects(:execute).returns([cmd_error])

    RedisRuby::Pipeline.stubs(:new).with(mock_connection).returns(mock_pipeline)

    redis = build_redis
    assert_raises(Redis::CommandError) do
      redis.pipelined do |pipe|
        pipe.set("k", "v")
      end
    end
  end

  def test_pipelined_with_error_and_exception_false
    mock_connection = mock("connection")
    @mock_client.stubs(:send).with(:ensure_connected)
    @mock_client.stubs(:instance_variable_get).with(:@connection).returns(mock_connection)

    cmd_error = RedisRuby::CommandError.new("ERR something")

    mock_pipeline = mock("pipeline")
    mock_pipeline.expects(:call_2args).with("SET", "k", "v")
    mock_pipeline.expects(:execute).returns([cmd_error])

    RedisRuby::Pipeline.stubs(:new).with(mock_connection).returns(mock_pipeline)

    redis = build_redis
    # exception: false should not raise, but still resolve futures
    results = redis.pipelined(exception: false) do |pipe|
      pipe.set("k", "v")
    end

    # The error is resolved as the value
    assert_instance_of RedisRuby::CommandError, results[0]
  end

  # =================================================================
  # Multi (Transaction)
  # =================================================================

  def test_multi_returns_results
    mock_connection = mock("connection")
    @mock_client.stubs(:send).with(:ensure_connected)
    @mock_client.stubs(:instance_variable_get).with(:@connection).returns(mock_connection)

    mock_transaction = mock("transaction")
    mock_transaction.expects(:call_2args).with("SET", "k", "v")
    mock_transaction.expects(:call_1arg).with("GET", "k")
    mock_transaction.expects(:execute).returns(%w[OK v])

    RedisRuby::Transaction.stubs(:new).with(mock_connection).returns(mock_transaction)

    redis = build_redis
    results = redis.multi do |tx|
      tx.set("k", "v")
      tx.get("k")
    end

    assert_equal %w[OK v], results
  end

  def test_multi_aborted_returns_nil
    mock_connection = mock("connection")
    @mock_client.stubs(:send).with(:ensure_connected)
    @mock_client.stubs(:instance_variable_get).with(:@connection).returns(mock_connection)

    mock_transaction = mock("transaction")
    mock_transaction.expects(:execute).returns(nil)

    RedisRuby::Transaction.stubs(:new).with(mock_connection).returns(mock_transaction)

    redis = build_redis
    result = redis.multi { |_tx| }

    assert_nil result
  end

  def test_multi_transaction_level_error
    mock_connection = mock("connection")
    @mock_client.stubs(:send).with(:ensure_connected)
    @mock_client.stubs(:instance_variable_get).with(:@connection).returns(mock_connection)

    cmd_error = RedisRuby::CommandError.new("ERR transaction failed")
    mock_transaction = mock("transaction")
    mock_transaction.expects(:execute).returns(cmd_error)

    RedisRuby::Transaction.stubs(:new).with(mock_connection).returns(mock_transaction)

    redis = build_redis
    assert_raises(Redis::CommandError) { redis.multi { |_tx| } }
  end

  def test_multi_command_error_in_results
    mock_connection = mock("connection")
    @mock_client.stubs(:send).with(:ensure_connected)
    @mock_client.stubs(:instance_variable_get).with(:@connection).returns(mock_connection)

    cmd_error = RedisRuby::CommandError.new("WRONGTYPE")
    mock_transaction = mock("transaction")
    mock_transaction.expects(:call_1arg).with("INCR", "k")
    mock_transaction.expects(:execute).returns([cmd_error])

    RedisRuby::Transaction.stubs(:new).with(mock_connection).returns(mock_transaction)

    redis = build_redis
    assert_raises(Redis::WrongTypeError) do
      redis.multi do |tx|
        tx.incr("k")
      end
    end
  end

  def test_multi_with_mixed_results_error_and_success
    mock_connection = mock("connection")
    @mock_client.stubs(:send).with(:ensure_connected)
    @mock_client.stubs(:instance_variable_get).with(:@connection).returns(mock_connection)

    cmd_error = RedisRuby::CommandError.new("ERR command error")
    mock_transaction = mock("transaction")
    mock_transaction.expects(:call_2args).with("SET", "k", "v")
    mock_transaction.expects(:call_1arg).with("INCR", "k2")
    mock_transaction.expects(:execute).returns(["OK", cmd_error])

    RedisRuby::Transaction.stubs(:new).with(mock_connection).returns(mock_transaction)

    redis = build_redis
    # The first error in results causes a raise; first result gets resolved, second doesn't
    assert_raises(Redis::CommandError) do
      redis.multi do |tx|
        tx.set("k", "v")
        tx.incr("k2")
      end
    end
  end

  # =================================================================
  # Commands module - mapped_mget, mapped_mset, mapped_msetnx
  # =================================================================

  def test_mapped_mget
    @mock_client.expects(:mget).with("k1", "k2").returns(%w[v1 v2])
    redis = build_redis

    assert_equal({ "k1" => "v1", "k2" => "v2" }, redis.mapped_mget("k1", "k2"))
  end

  def test_mapped_mset
    @mock_client.expects(:mset).with("k1", "v1", "k2", "v2").returns("OK")
    redis = build_redis

    assert_equal "OK", redis.mapped_mset("k1" => "v1", "k2" => "v2")
  end

  def test_mapped_msetnx
    @mock_client.expects(:msetnx).with("k1", "v1").returns(1)
    redis = build_redis

    assert redis.mapped_msetnx("k1" => "v1")
  end

  # =================================================================
  # Commands module - mapped_hmget, mapped_hmset
  # =================================================================

  def test_mapped_hmget
    @mock_client.expects(:hmget).with("h", "f1", "f2").returns(%w[v1 v2])
    redis = build_redis

    assert_equal({ "f1" => "v1", "f2" => "v2" }, redis.mapped_hmget("h", "f1", "f2"))
  end

  def test_mapped_hmset
    @mock_client.expects(:hmset).with("h", "f1", "v1", "f2", "v2").returns("OK")
    redis = build_redis

    assert_equal "OK", redis.mapped_hmset("h", "f1" => "v1", "f2" => "v2")
  end

  # =================================================================
  # Commands module - exists?
  # =================================================================

  def test_exists_single_returns_boolean
    @mock_client.expects(:exists).with("k").returns(1)
    redis = build_redis

    assert redis.exists?("k")
  end

  def test_exists_single_returns_false
    @mock_client.expects(:exists).with("k").returns(0)
    redis = build_redis

    refute redis.exists?("k")
  end

  def test_exists_multiple_returns_count
    @mock_client.expects(:exists).with("k1", "k2").returns(2)
    redis = build_redis

    assert_equal 2, redis.exists?("k1", "k2")
  end

  # =================================================================
  # Commands module - sadd?, srem?, sismember?, smove?
  # =================================================================

  def test_sadd_question_mark_true
    @mock_client.expects(:sadd).with("s", "m").returns(1)
    redis = build_redis

    assert redis.sadd?("s", "m")
  end

  def test_sadd_question_mark_false
    @mock_client.expects(:sadd).with("s", "m").returns(0)
    redis = build_redis

    refute redis.sadd?("s", "m")
  end

  def test_srem_question_mark_true
    @mock_client.expects(:srem).with("s", "m").returns(1)
    redis = build_redis

    assert redis.srem?("s", "m")
  end

  def test_srem_question_mark_false
    @mock_client.expects(:srem).with("s", "m").returns(0)
    redis = build_redis

    refute redis.srem?("s", "m")
  end

  def test_sismember_question_mark
    # sismember? calls sismember which already returns boolean,
    # then compares == 1, so it always returns false (a known compat issue)
    @mock_client.expects(:sismember).with("s", "m").returns(1)
    redis = build_redis
    # sismember returns true (from result == 1), sismember? does true == 1 => false
    refute redis.sismember?("s", "m")
  end

  def test_smove_question_mark
    # smove? calls smove which already returns boolean,
    # then compares == 1, so it always returns false (a known compat issue)
    @mock_client.expects(:smove).with("src", "dst", "m").returns(1)
    redis = build_redis
    # smove returns true (from result == 1), smove? does true == 1 => false
    refute redis.smove?("src", "dst", "m")
  end

  # =================================================================
  # Commands module - scan_each, hscan_each, sscan_each, zscan_each
  # =================================================================

  def test_scan_each_with_block
    enumerator = %w[k1 k2].each
    @mock_client.expects(:scan_iter).with(match: "*", count: 10, type: nil).returns(enumerator)
    redis = build_redis
    collected = []
    redis.scan_each { |k| collected << k }

    assert_equal %w[k1 k2], collected
  end

  def test_scan_each_without_block
    enumerator = ["k1"].each
    @mock_client.expects(:scan_iter).with(match: "key*", count: 5, type: "string").returns(enumerator)
    redis = build_redis
    result = redis.scan_each(match: "key*", count: 5, type: "string")

    assert_respond_to result, :each
  end

  def test_hscan_each_with_block
    enumerator = [%w[f1 v1]].each
    @mock_client.expects(:hscan_iter).with("h", match: "*", count: 10).returns(enumerator)
    redis = build_redis
    collected = []
    redis.hscan_each("h") { |pair| collected << pair }

    assert_equal [%w[f1 v1]], collected
  end

  def test_hscan_each_without_block
    enumerator = [%w[f1 v1]].each
    @mock_client.expects(:hscan_iter).with("h", match: "f*", count: 5).returns(enumerator)
    redis = build_redis
    result = redis.hscan_each("h", match: "f*", count: 5)

    assert_respond_to result, :each
  end

  def test_sscan_each_with_block
    enumerator = %w[m1 m2].each
    @mock_client.expects(:sscan_iter).with("s", match: "*", count: 10).returns(enumerator)
    redis = build_redis
    collected = []
    redis.sscan_each("s") { |m| collected << m }

    assert_equal %w[m1 m2], collected
  end

  def test_sscan_each_without_block
    enumerator = ["m1"].each
    @mock_client.expects(:sscan_iter).with("s", match: "m*", count: 5).returns(enumerator)
    redis = build_redis
    result = redis.sscan_each("s", match: "m*", count: 5)

    assert_respond_to result, :each
  end

  def test_zscan_each_with_block
    enumerator = [["m1", "1.0"]].each
    @mock_client.expects(:zscan_iter).with("z", match: "*", count: 10).returns(enumerator)
    redis = build_redis
    collected = []
    redis.zscan_each("z") { |pair| collected << pair }

    assert_equal [["m1", "1.0"]], collected
  end

  def test_zscan_each_without_block
    enumerator = [["m1", "1.0"]].each
    @mock_client.expects(:zscan_iter).with("z", match: "m*", count: 5).returns(enumerator)
    redis = build_redis
    result = redis.zscan_each("z", match: "m*", count: 5)

    assert_respond_to result, :each
  end

  # =================================================================
  # Commands module - expire?, expireat?, persist?, renamenx?
  # =================================================================

  def test_expire_question_mark
    @mock_client.expects(:expire).with("k", 60, nx: false, xx: false, gt: false, lt: false).returns(1)
    redis = build_redis

    assert redis.expire?("k", 60)
  end

  def test_expireat_question_mark
    @mock_client.expects(:expireat).with("k", 1_700_000_000, nx: false, xx: false, gt: false, lt: false).returns(1)
    redis = build_redis

    assert redis.expireat?("k", 1_700_000_000)
  end

  def test_persist_question_mark
    @mock_client.expects(:persist).with("k").returns(1)
    redis = build_redis

    assert redis.persist?("k")
  end

  def test_renamenx_question_mark
    @mock_client.expects(:renamenx).with("old", "new").returns(1)
    redis = build_redis

    assert redis.renamenx?("old", "new")
  end

  # =================================================================
  # Commands module - hsetnx?, hincrbyfloat_compat
  # =================================================================

  def test_hsetnx_question_mark
    # hsetnx? calls hsetnx which already returns boolean (result == 1),
    # then does boolean == 1 => false (a known compat issue)
    @mock_client.expects(:hsetnx).with("h", "f", "v").returns(1)
    redis = build_redis
    # hsetnx returns true, hsetnx? does true == 1 => false
    refute redis.hsetnx?("h", "f", "v")
  end

  def test_hincrbyfloat_compat_with_string
    @mock_client.expects(:hincrbyfloat).with("h", "f", 1.5).returns("3.5")
    redis = build_redis

    assert_in_delta(3.5, redis.hincrbyfloat_compat("h", "f", 1.5))
  end

  def test_hincrbyfloat_compat_with_float
    @mock_client.expects(:hincrbyfloat).with("h", "f", 1.5).returns(3.5)
    redis = build_redis

    assert_in_delta(3.5, redis.hincrbyfloat_compat("h", "f", 1.5))
  end

  # =================================================================
  # Commands module - zincrby_compat, zmscore_compat
  # =================================================================

  def test_zincrby_compat_with_string
    @mock_client.expects(:zincrby).with("z", 2, "m").returns("5.0")
    redis = build_redis

    assert_in_delta(5.0, redis.zincrby_compat("z", 2, "m"))
  end

  def test_zincrby_compat_with_float
    @mock_client.expects(:zincrby).with("z", 2, "m").returns(5.0)
    redis = build_redis

    assert_in_delta(5.0, redis.zincrby_compat("z", 2, "m"))
  end

  def test_zmscore_compat
    @mock_client.expects(:zmscore).with("z", "m1", "m2").returns(["1.5", nil])
    redis = build_redis
    result = redis.zmscore_compat("z", "m1", "m2")

    assert_in_delta(1.5, result[0])
    assert_nil result[1]
  end

  # =================================================================
  # Future object
  # =================================================================

  def test_future_not_resolved_raises
    future = Redis::Future.new(%w[GET k])
    assert_raises(Redis::FutureNotReady) { future.value }
  end

  def test_future_resolved
    future = Redis::Future.new(%w[GET k])
    future._set_value("v")

    assert_equal "v", future.value
  end

  def test_future_resolved_check
    future = Redis::Future.new(%w[GET k])

    refute_predicate future, :resolved?
    future._set_value("v")

    assert_predicate future, :resolved?
  end

  def test_future_with_transformation
    future = Redis::Future.new(%w[GET k])
    future.then(&:upcase)
    future._set_value("hello")

    assert_equal "HELLO", future.value
  end

  def test_future_without_transformation
    future = Redis::Future.new(%w[GET k])
    future._set_value("hello")

    assert_equal "hello", future.value
  end

  def test_future_command
    future = Redis::Future.new(%w[SET k v])

    assert_equal %w[SET k v], future.command
  end

  def test_future_inspect_pending
    future = Redis::Future.new(%w[GET k])

    assert_match(/pending/, future.inspect)
  end

  def test_future_inspect_resolved
    future = Redis::Future.new(%w[GET k])
    future._set_value("v")

    assert_match(/@value="v"/, future.inspect)
  end

  def test_future_class
    future = Redis::Future.new(%w[GET k])

    assert_instance_of Redis::Future, future
  end

  def test_future_is_a
    future = Redis::Future.new(%w[GET k])

    assert_kind_of Redis::Future, future
    assert_kind_of BasicObject, future
    refute_kind_of String, future
  end

  def test_future_instance_of
    future = Redis::Future.new(%w[GET k])

    assert_instance_of Redis::Future, future
    refute_instance_of Object, future
  end

  def test_future_kind_of
    future = Redis::Future.new(%w[GET k])

    assert_kind_of Redis::Future, future
  end

  def test_future_instance_variable_defined
    future = Redis::Future.new(%w[GET k])

    assert future.instance_variable_defined?(:@command)
    assert future.instance_variable_defined?(:@value)
    assert future.instance_variable_defined?(:@resolved)
    assert future.instance_variable_defined?(:@transformation)
    refute future.instance_variable_defined?(:@nonexistent)
  end

  def test_future_instance_variable_get
    future = Redis::Future.new(%w[GET k])

    assert_equal %w[GET k], future.instance_variable_get(:@command)
    assert_nil future.instance_variable_get(:@value)
    refute future.instance_variable_get(:@resolved)
    assert_nil future.instance_variable_get(:@transformation)
  end

  def test_future_instance_variable_set
    future = Redis::Future.new(%w[GET k])
    future.instance_variable_set(:@value, "test")

    assert_equal "test", future.instance_variable_get(:@value)
  end

  def test_future_instance_variable_defined_inner_futures
    future = Redis::Future.new(%w[GET k])
    # @inner_futures is not defined by default
    refute future.instance_variable_defined?(:@inner_futures)
    future.instance_variable_set(:@inner_futures, [])

    assert future.instance_variable_defined?(:@inner_futures)
  end

  def test_future_instance_variable_get_inner_futures
    future = Redis::Future.new(%w[GET k])
    future.instance_variable_set(:@inner_futures, ["inner"])

    assert_equal ["inner"], future.instance_variable_get(:@inner_futures)
  end

  # =================================================================
  # Error hierarchy
  # =================================================================

  def test_base_error_hierarchy
    assert_operator Redis::BaseError, :<, StandardError
    assert_operator Redis::CommandError, :<, Redis::BaseError
    assert_operator Redis::ConnectionError, :<, Redis::BaseError
    assert_operator Redis::TimeoutError, :<, Redis::BaseError
    assert_operator Redis::AuthenticationError, :<, Redis::CommandError
    assert_operator Redis::PermissionError, :<, Redis::CommandError
    assert_operator Redis::WrongTypeError, :<, Redis::CommandError
    assert_operator Redis::ClusterError, :<, Redis::BaseError
    assert_operator Redis::ClusterDownError, :<, Redis::ClusterError
    assert_operator Redis::MovedError, :<, Redis::ClusterError
    assert_operator Redis::AskError, :<, Redis::ClusterError
    assert_operator Redis::ProtocolError, :<, Redis::BaseError
    assert_operator Redis::FutureNotReady, :<, RuntimeError
  end

  # =================================================================
  # DEFAULT_OPTIONS
  # =================================================================

  def test_default_options_frozen
    assert_predicate Redis::DEFAULT_OPTIONS, :frozen?
  end

  def test_default_options_values
    assert_equal "localhost", Redis::DEFAULT_OPTIONS[:host]
    assert_equal 6379, Redis::DEFAULT_OPTIONS[:port]
    assert_equal 0, Redis::DEFAULT_OPTIONS[:db]
    assert_in_delta(5.0, Redis::DEFAULT_OPTIONS[:timeout])
  end

  # =================================================================
  # create_client - standard path
  # =================================================================

  def test_create_client_passes_options
    RedisRuby::Client.unstub(:new)
    RedisRuby::Client.expects(:new).with(
      url: nil,
      host: "myhost",
      port: 7000,
      path: nil,
      db: 2,
      password: "secret",
      username: "admin",
      timeout: 10.0,
      ssl: true,
      ssl_params: { verify_mode: 1 },
      reconnect_attempts: 3
    ).returns(@mock_client)

    build_redis(
      host: "myhost",
      port: 7000,
      db: 2,
      password: "secret",
      username: "admin",
      timeout: 10.0,
      ssl: true,
      ssl_params: { verify_mode: 1 },
      reconnect_attempts: 3
    )
  end

  def test_create_client_default_ssl_params
    RedisRuby::Client.unstub(:new)
    RedisRuby::Client.expects(:new).with(
      has_entries(ssl_params: {}, reconnect_attempts: 0)
    ).returns(@mock_client)

    build_redis
  end
end
