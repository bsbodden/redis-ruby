# frozen_string_literal: true

require_relative "../unit_test_helper"

class ServerBranchTest < Minitest::Test
  class MockClient
    include RedisRuby::Commands::Server

    attr_reader :last_command

    def call(*args)
      @last_command = args
      "OK"
    end

    def call_1arg(cmd, a1)
      @last_command = [cmd, a1]
      "OK"
    end

    def call_2args(cmd, a1, a2)
      @last_command = [cmd, a1, a2]
      "OK"
    end

    def call_3args(cmd, a1, a2, a3)
      @last_command = [cmd, a1, a2, a3]
      "OK"
    end
  end

  def setup
    @client = MockClient.new
  end

  # info
  def test_info_without_section
    @client.info

    assert_equal ["INFO"], @client.last_command
  end

  def test_info_with_section
    @client.info("server")

    assert_equal %w[INFO server], @client.last_command
  end

  # dbsize
  def test_dbsize
    @client.dbsize

    assert_equal ["DBSIZE"], @client.last_command
  end

  # flushdb
  def test_flushdb_no_mode
    @client.flushdb

    assert_equal ["FLUSHDB"], @client.last_command
  end

  def test_flushdb_async
    @client.flushdb(:async)

    assert_equal %w[FLUSHDB ASYNC], @client.last_command
  end

  def test_flushdb_sync
    @client.flushdb(:sync)

    assert_equal %w[FLUSHDB SYNC], @client.last_command
  end

  # flushall
  def test_flushall_no_mode
    @client.flushall

    assert_equal ["FLUSHALL"], @client.last_command
  end

  def test_flushall_async
    @client.flushall(:async)

    assert_equal %w[FLUSHALL ASYNC], @client.last_command
  end

  def test_flushall_sync
    @client.flushall(:sync)

    assert_equal %w[FLUSHALL SYNC], @client.last_command
  end

  # select, swapdb
  def test_select
    @client.select(1)

    assert_equal ["SELECT", 1], @client.last_command
  end

  def test_swapdb
    @client.swapdb(0, 1)

    assert_equal ["SWAPDB", 0, 1], @client.last_command
  end

  # persistence
  def test_save
    @client.save

    assert_equal ["SAVE"], @client.last_command
  end

  def test_bgsave_no_schedule
    @client.bgsave

    assert_equal ["BGSAVE"], @client.last_command
  end

  def test_bgsave_with_schedule
    @client.bgsave(schedule: true)

    assert_equal %w[BGSAVE SCHEDULE], @client.last_command
  end

  def test_bgrewriteaof
    @client.bgrewriteaof

    assert_equal ["BGREWRITEAOF"], @client.last_command
  end

  def test_lastsave
    @client.lastsave

    assert_equal ["LASTSAVE"], @client.last_command
  end

  # shutdown
  def test_shutdown_no_mode
    @client.shutdown

    assert_equal ["SHUTDOWN"], @client.last_command
  end

  def test_shutdown_nosave
    @client.shutdown(:nosave)

    assert_equal %w[SHUTDOWN NOSAVE], @client.last_command
  end

  def test_shutdown_save
    @client.shutdown(:save)

    assert_equal %w[SHUTDOWN SAVE], @client.last_command
  end

  # time
  def test_time
    @client.time

    assert_equal ["TIME"], @client.last_command
  end

  # config
  def test_config_get
    @client.config_get("maxmemory")

    assert_equal %w[CONFIG GET maxmemory], @client.last_command
  end

  def test_config_set
    @client.config_set("maxmemory", "100mb")

    assert_equal %w[CONFIG SET maxmemory 100mb], @client.last_command
  end

  def test_config_rewrite
    @client.config_rewrite

    assert_equal %w[CONFIG REWRITE], @client.last_command
  end

  def test_config_resetstat
    @client.config_resetstat

    assert_equal %w[CONFIG RESETSTAT], @client.last_command
  end

  # client
  def test_client_list_no_type
    @client.client_list

    assert_equal %w[CLIENT LIST], @client.last_command
  end

  def test_client_list_with_type
    @client.client_list(type: "normal")

    assert_equal %w[CLIENT LIST TYPE normal], @client.last_command
  end

  def test_client_getname
    @client.client_getname

    assert_equal %w[CLIENT GETNAME], @client.last_command
  end

  def test_client_setname
    @client.client_setname("myconn")

    assert_equal %w[CLIENT SETNAME myconn], @client.last_command
  end

  def test_client_id
    @client.client_id

    assert_equal %w[CLIENT ID], @client.last_command
  end

  def test_client_info
    @client.client_info

    assert_equal %w[CLIENT INFO], @client.last_command
  end

  def test_client_kill_by_id
    @client.client_kill(id: 123)

    assert_equal ["CLIENT", "KILL", "ID", 123], @client.last_command
  end

  def test_client_kill_by_addr
    @client.client_kill(addr: "127.0.0.1:6379")

    assert_equal ["CLIENT", "KILL", "ADDR", "127.0.0.1:6379"], @client.last_command
  end

  def test_client_kill_no_filter
    @client.client_kill

    assert_equal %w[CLIENT KILL], @client.last_command
  end

  def test_client_pause
    @client.client_pause(5000)

    assert_equal ["CLIENT", "PAUSE", 5000], @client.last_command
  end

  def test_client_unpause
    @client.client_unpause

    assert_equal %w[CLIENT UNPAUSE], @client.last_command
  end

  def test_client_no_evict_enabled
    @client.client_no_evict(true)

    assert_equal %w[CLIENT NO-EVICT ON], @client.last_command
  end

  def test_client_no_evict_disabled
    @client.client_no_evict(false)

    assert_equal %w[CLIENT NO-EVICT OFF], @client.last_command
  end

  # slowlog
  def test_slowlog_get_no_count
    @client.slowlog_get

    assert_equal %w[SLOWLOG GET], @client.last_command
  end

  def test_slowlog_get_with_count
    @client.slowlog_get(10)

    assert_equal ["SLOWLOG", "GET", 10], @client.last_command
  end

  def test_slowlog_len
    @client.slowlog_len

    assert_equal %w[SLOWLOG LEN], @client.last_command
  end

  def test_slowlog_reset
    @client.slowlog_reset

    assert_equal %w[SLOWLOG RESET], @client.last_command
  end

  # memory
  def test_memory_doctor
    @client.memory_doctor

    assert_equal %w[MEMORY DOCTOR], @client.last_command
  end

  def test_memory_stats
    @client.memory_stats

    assert_equal %w[MEMORY STATS], @client.last_command
  end

  def test_memory_purge
    @client.memory_purge

    assert_equal %w[MEMORY PURGE], @client.last_command
  end

  def test_memory_malloc_stats
    @client.memory_malloc_stats

    assert_equal %w[MEMORY MALLOC-STATS], @client.last_command
  end

  # object
  def test_object_encoding
    @client.object_encoding("key")

    assert_equal %w[OBJECT ENCODING key], @client.last_command
  end

  def test_object_freq
    @client.object_freq("key")

    assert_equal %w[OBJECT FREQ key], @client.last_command
  end

  def test_object_idletime
    @client.object_idletime("key")

    assert_equal %w[OBJECT IDLETIME key], @client.last_command
  end

  def test_object_refcount
    @client.object_refcount("key")

    assert_equal %w[OBJECT REFCOUNT key], @client.last_command
  end

  # command
  def test_command_count
    @client.command_count

    assert_equal %w[COMMAND COUNT], @client.last_command
  end

  def test_command_docs_single
    @client.command_docs("GET")

    assert_equal %w[COMMAND DOCS GET], @client.last_command
  end

  def test_command_docs_multiple
    @client.command_docs("GET", "SET")

    assert_equal %w[COMMAND DOCS GET SET], @client.last_command
  end

  def test_command_info_single
    @client.command_info("GET")

    assert_equal %w[COMMAND INFO GET], @client.last_command
  end

  def test_command_info_multiple
    @client.command_info("GET", "SET")

    assert_equal %w[COMMAND INFO GET SET], @client.last_command
  end

  def test_command_list
    @client.command_list

    assert_equal %w[COMMAND LIST], @client.last_command
  end

  # latency
  def test_latency_latest
    @client.latency_latest

    assert_equal %w[LATENCY LATEST], @client.last_command
  end

  def test_latency_history
    @client.latency_history("command")

    assert_equal %w[LATENCY HISTORY command], @client.last_command
  end

  def test_latency_reset_no_events
    @client.latency_reset

    assert_equal %w[LATENCY RESET], @client.last_command
  end

  def test_latency_reset_single_event
    @client.latency_reset("command")

    assert_equal %w[LATENCY RESET command], @client.last_command
  end

  def test_latency_reset_multiple_events
    @client.latency_reset("command", "fast-command")

    assert_equal %w[LATENCY RESET command fast-command], @client.last_command
  end

  def test_latency_doctor
    @client.latency_doctor

    assert_equal %w[LATENCY DOCTOR], @client.last_command
  end

  def test_latency_graph
    @client.latency_graph("command")

    assert_equal %w[LATENCY GRAPH command], @client.last_command
  end

  def test_client_trackinginfo
    @client.client_trackinginfo

    assert_equal %w[CLIENT TRACKINGINFO], @client.last_command
  end

  # module
  def test_module_list
    @client.module_list

    assert_equal %w[MODULE LIST], @client.last_command
  end

  def test_module_load_no_args
    @client.module_load("/path/to/module.so")

    assert_equal ["MODULE", "LOAD", "/path/to/module.so"], @client.last_command
  end

  def test_module_load_with_args
    @client.module_load("/path/to/module.so", "arg1", "arg2")

    assert_equal ["MODULE", "LOAD", "/path/to/module.so", "arg1", "arg2"], @client.last_command
  end

  def test_module_unload
    @client.module_unload("mymodule")

    assert_equal %w[MODULE UNLOAD mymodule], @client.last_command
  end

  # replication
  def test_replicaof
    @client.replicaof("host", 6379)

    assert_equal ["REPLICAOF", "host", 6379], @client.last_command
  end

  def test_replicaof_no_one
    @client.replicaof_no_one

    assert_equal %w[REPLICAOF NO ONE], @client.last_command
  end

  def test_wait
    @client.wait(1, 5000)

    assert_equal ["WAIT", 1, 5000], @client.last_command
  end

  def test_waitaof
    @client.waitaof(1, 1, 5000)

    assert_equal ["WAITAOF", 1, 1, 5000], @client.last_command
  end

  # misc
  def test_echo
    @client.echo("hello")

    assert_equal %w[ECHO hello], @client.last_command
  end

  def test_debug_object
    @client.debug_object("key")

    assert_equal %w[DEBUG OBJECT key], @client.last_command
  end

  def test_lolwut_no_version
    @client.lolwut

    assert_equal ["LOLWUT"], @client.last_command
  end

  def test_lolwut_with_version
    @client.lolwut(version: 5)

    assert_equal ["LOLWUT", "VERSION", 5], @client.last_command
  end
end
