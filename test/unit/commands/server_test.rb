# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../test_helper"

class ServerCommandsTest < Minitest::Test
  def setup
    @client = RedisRuby::Client.new
    @connection = mock("connection")
    @client.instance_variable_set(:@connection, @connection)
    @connection.stubs(:connected?).returns(true)
  end

  # --- INFO ---

  def test_info_all
    @connection.expects(:call_direct).with("INFO").returns("# Server\nredis_version:7.0.0\n")
    result = @client.info
    assert_equal "# Server\nredis_version:7.0.0\n", result
  end

  def test_info_section
    # INFO <section> uses call_1arg
    @connection.expects(:call_1arg).with("INFO", "memory").returns("# Memory\nused_memory:1000\n")
    result = @client.info("memory")
    assert_equal "# Memory\nused_memory:1000\n", result
  end

  # --- DBSIZE ---

  def test_dbsize
    @connection.expects(:call_direct).with("DBSIZE").returns(42)
    assert_equal 42, @client.dbsize
  end

  # --- FLUSHDB / FLUSHALL ---

  def test_flushdb
    @connection.expects(:call_direct).with("FLUSHDB").returns("OK")
    assert_equal "OK", @client.flushdb
  end

  def test_flushdb_async
    # FLUSHDB ASYNC uses call_1arg
    @connection.expects(:call_1arg).with("FLUSHDB", "ASYNC").returns("OK")
    assert_equal "OK", @client.flushdb(:async)
  end

  def test_flushall
    @connection.expects(:call_direct).with("FLUSHALL").returns("OK")
    assert_equal "OK", @client.flushall
  end

  def test_flushall_async
    # FLUSHALL ASYNC uses call_1arg
    @connection.expects(:call_1arg).with("FLUSHALL", "ASYNC").returns("OK")
    assert_equal "OK", @client.flushall(:async)
  end

  # --- SAVE / BGSAVE / BGREWRITEAOF ---

  def test_save
    @connection.expects(:call_direct).with("SAVE").returns("OK")
    assert_equal "OK", @client.save
  end

  def test_bgsave
    @connection.expects(:call_direct).with("BGSAVE").returns("Background saving started")
    assert_equal "Background saving started", @client.bgsave
  end

  def test_bgsave_schedule
    # BGSAVE SCHEDULE uses call_1arg
    @connection.expects(:call_1arg).with("BGSAVE", "SCHEDULE").returns("OK")
    assert_equal "OK", @client.bgsave(schedule: true)
  end

  def test_bgrewriteaof
    @connection.expects(:call_direct).with("BGREWRITEAOF").returns("Background append only file rewriting started")
    assert_equal "Background append only file rewriting started", @client.bgrewriteaof
  end

  def test_lastsave
    @connection.expects(:call_direct).with("LASTSAVE").returns(1700000000)
    assert_equal 1700000000, @client.lastsave
  end

  # --- TIME ---

  def test_time
    @connection.expects(:call_direct).with("TIME").returns([1700000000, 123456])
    assert_equal [1700000000, 123456], @client.time
  end

  # --- CONFIG ---

  def test_config_get
    # CONFIG GET <pattern> uses call_2args
    expected = { "maxmemory" => "0" }
    @connection.expects(:call_2args).with("CONFIG", "GET", "maxmemory").returns(expected)
    assert_equal expected, @client.config_get("maxmemory")
  end

  def test_config_set
    @connection.expects(:call_direct).with("CONFIG", "SET", "maxmemory", "100mb").returns("OK")
    assert_equal "OK", @client.config_set("maxmemory", "100mb")
  end

  def test_config_rewrite
    # CONFIG REWRITE uses call_1arg
    @connection.expects(:call_1arg).with("CONFIG", "REWRITE").returns("OK")
    assert_equal "OK", @client.config_rewrite
  end

  def test_config_resetstat
    # CONFIG RESETSTAT uses call_1arg
    @connection.expects(:call_1arg).with("CONFIG", "RESETSTAT").returns("OK")
    assert_equal "OK", @client.config_resetstat
  end

  # --- CLIENT ---

  def test_client_list
    # CLIENT LIST uses call_1arg
    @connection.expects(:call_1arg).with("CLIENT", "LIST").returns("id=1 addr=127.0.0.1:1234")
    assert_equal "id=1 addr=127.0.0.1:1234", @client.client_list
  end

  def test_client_list_with_type
    @connection.expects(:call_direct).with("CLIENT", "LIST", "TYPE", "normal").returns("id=1")
    assert_equal "id=1", @client.client_list(type: "normal")
  end

  def test_client_getname
    # CLIENT GETNAME uses call_1arg
    @connection.expects(:call_1arg).with("CLIENT", "GETNAME").returns("myconn")
    assert_equal "myconn", @client.client_getname
  end

  def test_client_setname
    # CLIENT SETNAME <name> uses call_2args
    @connection.expects(:call_2args).with("CLIENT", "SETNAME", "myconn").returns("OK")
    assert_equal "OK", @client.client_setname("myconn")
  end

  def test_client_id
    # CLIENT ID uses call_1arg
    @connection.expects(:call_1arg).with("CLIENT", "ID").returns(42)
    assert_equal 42, @client.client_id
  end

  def test_client_info
    # CLIENT INFO uses call_1arg
    expected = { "id" => 42, "name" => "myconn" }
    @connection.expects(:call_1arg).with("CLIENT", "INFO").returns(expected)
    assert_equal expected, @client.client_info
  end

  def test_client_kill
    @connection.expects(:call_direct).with("CLIENT", "KILL", "ID", 42).returns(1)
    assert_equal 1, @client.client_kill(id: 42)
  end

  def test_client_kill_by_addr
    @connection.expects(:call_direct).with("CLIENT", "KILL", "ADDR", "127.0.0.1:1234").returns(1)
    assert_equal 1, @client.client_kill(addr: "127.0.0.1:1234")
  end

  def test_client_pause
    # CLIENT PAUSE <timeout> uses call_2args
    @connection.expects(:call_2args).with("CLIENT", "PAUSE", 5000).returns("OK")
    assert_equal "OK", @client.client_pause(5000)
  end

  def test_client_unpause
    # CLIENT UNPAUSE uses call_1arg
    @connection.expects(:call_1arg).with("CLIENT", "UNPAUSE").returns("OK")
    assert_equal "OK", @client.client_unpause
  end

  def test_client_no_evict
    # CLIENT NO-EVICT ON/OFF uses call_2args
    @connection.expects(:call_2args).with("CLIENT", "NO-EVICT", "ON").returns("OK")
    assert_equal "OK", @client.client_no_evict(true)
  end

  # --- SLOWLOG ---

  def test_slowlog_get
    # SLOWLOG GET uses call_1arg
    expected = [[1, 1700000000, 10000, ["GET", "key"]]]
    @connection.expects(:call_1arg).with("SLOWLOG", "GET").returns(expected)
    assert_equal expected, @client.slowlog_get
  end

  def test_slowlog_get_count
    # SLOWLOG GET <count> uses call_2args
    @connection.expects(:call_2args).with("SLOWLOG", "GET", 10).returns([])
    assert_equal [], @client.slowlog_get(10)
  end

  def test_slowlog_len
    # SLOWLOG LEN uses call_1arg
    @connection.expects(:call_1arg).with("SLOWLOG", "LEN").returns(5)
    assert_equal 5, @client.slowlog_len
  end

  def test_slowlog_reset
    # SLOWLOG RESET uses call_1arg
    @connection.expects(:call_1arg).with("SLOWLOG", "RESET").returns("OK")
    assert_equal "OK", @client.slowlog_reset
  end

  # --- MEMORY ---

  def test_memory_doctor
    # MEMORY DOCTOR uses call_1arg
    @connection.expects(:call_1arg).with("MEMORY", "DOCTOR").returns("Sam, I have no memory problems")
    assert_equal "Sam, I have no memory problems", @client.memory_doctor
  end

  def test_memory_stats
    # MEMORY STATS uses call_1arg
    expected = { "peak.allocated" => 1000000 }
    @connection.expects(:call_1arg).with("MEMORY", "STATS").returns(expected)
    assert_equal expected, @client.memory_stats
  end

  def test_memory_purge
    # MEMORY PURGE uses call_1arg
    @connection.expects(:call_1arg).with("MEMORY", "PURGE").returns("OK")
    assert_equal "OK", @client.memory_purge
  end

  def test_memory_malloc_stats
    # MEMORY MALLOC-STATS uses call_1arg
    @connection.expects(:call_1arg).with("MEMORY", "MALLOC-STATS").returns("stats")
    assert_equal "stats", @client.memory_malloc_stats
  end

  # --- OBJECT ---

  def test_object_encoding
    # OBJECT ENCODING <key> uses call_2args
    @connection.expects(:call_2args).with("OBJECT", "ENCODING", "mykey").returns("ziplist")
    assert_equal "ziplist", @client.object_encoding("mykey")
  end

  def test_object_freq
    # OBJECT FREQ <key> uses call_2args
    @connection.expects(:call_2args).with("OBJECT", "FREQ", "mykey").returns(5)
    assert_equal 5, @client.object_freq("mykey")
  end

  def test_object_idletime
    # OBJECT IDLETIME <key> uses call_2args
    @connection.expects(:call_2args).with("OBJECT", "IDLETIME", "mykey").returns(100)
    assert_equal 100, @client.object_idletime("mykey")
  end

  def test_object_refcount
    # OBJECT REFCOUNT <key> uses call_2args
    @connection.expects(:call_2args).with("OBJECT", "REFCOUNT", "mykey").returns(1)
    assert_equal 1, @client.object_refcount("mykey")
  end

  # --- COMMAND ---

  def test_command_count
    # COMMAND COUNT uses call_1arg
    @connection.expects(:call_1arg).with("COMMAND", "COUNT").returns(242)
    assert_equal 242, @client.command_count
  end

  def test_command_docs
    # COMMAND DOCS <cmd> uses call_2args for single command
    expected = { "get" => { "summary" => "Get the value of a key" } }
    @connection.expects(:call_2args).with("COMMAND", "DOCS", "get").returns(expected)
    assert_equal expected, @client.command_docs("get")
  end

  def test_command_info
    # COMMAND INFO <cmd> uses call_2args for single command
    expected = { "get" => [1, ["readonly"], 1, 1, 1] }
    @connection.expects(:call_2args).with("COMMAND", "INFO", "get").returns(expected)
    assert_equal expected, @client.command_info("get")
  end

  def test_command_list
    # COMMAND LIST uses call_1arg
    @connection.expects(:call_1arg).with("COMMAND", "LIST").returns(["get", "set"])
    assert_equal ["get", "set"], @client.command_list
  end

  # --- LATENCY ---

  def test_latency_latest
    # LATENCY LATEST uses call_1arg
    @connection.expects(:call_1arg).with("LATENCY", "LATEST").returns([])
    assert_equal [], @client.latency_latest
  end

  def test_latency_history
    # LATENCY HISTORY <event> uses call_2args
    @connection.expects(:call_2args).with("LATENCY", "HISTORY", "command").returns([])
    assert_equal [], @client.latency_history("command")
  end

  def test_latency_reset
    # LATENCY RESET uses call_1arg for no events
    @connection.expects(:call_1arg).with("LATENCY", "RESET").returns(0)
    assert_equal 0, @client.latency_reset
  end

  def test_latency_reset_events
    @connection.expects(:call_direct).with("LATENCY", "RESET", "command", "fast-command").returns(2)
    assert_equal 2, @client.latency_reset("command", "fast-command")
  end

  # --- MODULE ---

  def test_module_list
    # MODULE LIST uses call_1arg
    @connection.expects(:call_1arg).with("MODULE", "LIST").returns([])
    assert_equal [], @client.module_list
  end

  def test_module_load
    # MODULE LOAD <path> uses call_2args for no extra args
    @connection.expects(:call_2args).with("MODULE", "LOAD", "/path/to/module.so").returns("OK")
    assert_equal "OK", @client.module_load("/path/to/module.so")
  end

  def test_module_load_with_args
    @connection.expects(:call_direct).with("MODULE", "LOAD", "/path/to/module.so", "arg1", "arg2").returns("OK")
    assert_equal "OK", @client.module_load("/path/to/module.so", "arg1", "arg2")
  end

  def test_module_unload
    # MODULE UNLOAD <name> uses call_2args
    @connection.expects(:call_2args).with("MODULE", "UNLOAD", "mymodule").returns("OK")
    assert_equal "OK", @client.module_unload("mymodule")
  end

  # --- MISC ---

  def test_echo
    # ECHO <message> uses call_1arg
    @connection.expects(:call_1arg).with("ECHO", "hello").returns("hello")
    assert_equal "hello", @client.echo("hello")
  end

  def test_select
    # SELECT <db> uses call_1arg
    @connection.expects(:call_1arg).with("SELECT", 2).returns("OK")
    assert_equal "OK", @client.select(2)
  end

  def test_swapdb
    # SWAPDB <db1> <db2> uses call_2args
    @connection.expects(:call_2args).with("SWAPDB", 0, 1).returns("OK")
    assert_equal "OK", @client.swapdb(0, 1)
  end

  def test_replicaof
    # REPLICAOF <host> <port> uses call_2args
    @connection.expects(:call_2args).with("REPLICAOF", "host", 6379).returns("OK")
    assert_equal "OK", @client.replicaof("host", 6379)
  end

  def test_replicaof_no_one
    # REPLICAOF NO ONE uses call_2args
    @connection.expects(:call_2args).with("REPLICAOF", "NO", "ONE").returns("OK")
    assert_equal "OK", @client.replicaof_no_one
  end

  def test_wait_command
    # WAIT <numreplicas> <timeout> uses call_2args
    @connection.expects(:call_2args).with("WAIT", 1, 1000).returns(1)
    assert_equal 1, @client.wait(1, 1000)
  end

  def test_waitaof
    # WAITAOF <numlocal> <numreplicas> <timeout> uses call_3args
    @connection.expects(:call_3args).with("WAITAOF", 1, 1, 1000).returns([1, 1])
    assert_equal [1, 1], @client.waitaof(1, 1, 1000)
  end

  def test_shutdown
    @connection.expects(:call_direct).with("SHUTDOWN").returns(nil)
    assert_nil @client.shutdown
  end

  def test_shutdown_nosave
    # SHUTDOWN NOSAVE uses call_1arg
    @connection.expects(:call_1arg).with("SHUTDOWN", "NOSAVE").returns(nil)
    assert_nil @client.shutdown(:nosave)
  end

  def test_debug_object
    # DEBUG OBJECT <key> uses call_2args
    @connection.expects(:call_2args).with("DEBUG", "OBJECT", "mykey").returns("Value at:0x7f encoding:raw refcount:1")
    assert_equal "Value at:0x7f encoding:raw refcount:1", @client.debug_object("mykey")
  end

  def test_lolwut
    @connection.expects(:call_direct).with("LOLWUT").returns("Redis ver. 7.0.0")
    assert_equal "Redis ver. 7.0.0", @client.lolwut
  end

  def test_lolwut_version
    # LOLWUT VERSION <num> uses call_2args
    @connection.expects(:call_2args).with("LOLWUT", "VERSION", 6).returns("art")
    assert_equal "art", @client.lolwut(version: 6)
  end
end
