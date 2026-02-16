# frozen_string_literal: true

module RR
  module Commands
    # Server, configuration, and administrative commands
    #
    # Covers INFO, CONFIG, CLIENT, SLOWLOG, MEMORY, OBJECT, COMMAND,
    # LATENCY, MODULE, and miscellaneous server management commands.
    #
    # @see https://redis.io/commands/?group=server
    # @see https://redis.io/commands/?group=connection
    # @see https://redis.io/commands/?group=generic
    module Server
      # Frozen command constants to avoid string allocations
      CMD_INFO = "INFO"
      CMD_DBSIZE = "DBSIZE"
      CMD_FLUSHDB = "FLUSHDB"
      CMD_FLUSHALL = "FLUSHALL"
      CMD_SELECT = "SELECT"
      CMD_SWAPDB = "SWAPDB"
      CMD_SAVE = "SAVE"
      CMD_BGSAVE = "BGSAVE"
      CMD_BGREWRITEAOF = "BGREWRITEAOF"
      CMD_LASTSAVE = "LASTSAVE"
      CMD_SHUTDOWN = "SHUTDOWN"
      CMD_TIME = "TIME"
      CMD_CONFIG = "CONFIG"
      CMD_CLIENT = "CLIENT"
      CMD_SLOWLOG = "SLOWLOG"
      CMD_MEMORY = "MEMORY"
      CMD_OBJECT = "OBJECT"
      CMD_COMMAND = "COMMAND"
      CMD_LATENCY = "LATENCY"
      CMD_MODULE = "MODULE"
      CMD_REPLICAOF = "REPLICAOF"
      CMD_WAIT = "WAIT"
      CMD_WAITAOF = "WAITAOF"
      CMD_ECHO = "ECHO"
      CMD_DEBUG = "DEBUG"
      CMD_LOLWUT = "LOLWUT"

      # Frozen subcommands
      SUBCMD_GET = "GET"
      SUBCMD_SET = "SET"
      SUBCMD_REWRITE = "REWRITE"
      SUBCMD_RESETSTAT = "RESETSTAT"
      SUBCMD_LIST = "LIST"
      SUBCMD_GETNAME = "GETNAME"
      SUBCMD_SETNAME = "SETNAME"
      SUBCMD_ID = "ID"
      SUBCMD_INFO = "INFO"
      SUBCMD_KILL = "KILL"
      SUBCMD_PAUSE = "PAUSE"
      SUBCMD_UNPAUSE = "UNPAUSE"
      SUBCMD_NO_EVICT = "NO-EVICT"
      SUBCMD_LEN = "LEN"
      SUBCMD_RESET = "RESET"
      SUBCMD_DOCTOR = "DOCTOR"
      SUBCMD_STATS = "STATS"
      SUBCMD_PURGE = "PURGE"
      SUBCMD_MALLOC_STATS = "MALLOC-STATS"
      SUBCMD_ENCODING = "ENCODING"
      SUBCMD_FREQ = "FREQ"
      SUBCMD_IDLETIME = "IDLETIME"
      SUBCMD_REFCOUNT = "REFCOUNT"
      SUBCMD_COUNT = "COUNT"
      SUBCMD_DOCS = "DOCS"
      SUBCMD_LATEST = "LATEST"
      SUBCMD_HISTORY = "HISTORY"
      SUBCMD_LOAD = "LOAD"
      SUBCMD_UNLOAD = "UNLOAD"
      SUBCMD_OBJECT = "OBJECT"
      SUBCMD_GRAPH = "GRAPH"
      SUBCMD_TRACKINGINFO = "TRACKINGINFO"

      # Frozen options
      OPT_TYPE = "TYPE"
      OPT_ADDR = "ADDR"
      OPT_ON = "ON"
      OPT_OFF = "OFF"
      OPT_NO = "NO"
      OPT_ONE = "ONE"
      OPT_SCHEDULE = "SCHEDULE"
      OPT_ASYNC = "ASYNC"
      OPT_SYNC = "SYNC"
      OPT_NOSAVE = "NOSAVE"
      OPT_VERSION = "VERSION"

      # --- INFO ---

      # Get server information and statistics
      #
      # @param section [String, nil] Info section (server, clients, memory, etc.)
      # @return [String] Info output
      def info(section = nil)
        if section
          call_1arg(CMD_INFO, section)
        else
          call(CMD_INFO)
        end
      end

      # --- DATABASE ---

      # Return the number of keys in the selected database
      #
      # @return [Integer] Number of keys
      def dbsize
        call(CMD_DBSIZE)
      end

      # Remove all keys from the current database
      #
      # @param mode [Symbol, nil] :async or :sync
      # @return [String] "OK"
      def flushdb(mode = nil)
        if mode
          call_1arg(CMD_FLUSHDB, mode == :async ? OPT_ASYNC : OPT_SYNC)
        else
          call(CMD_FLUSHDB)
        end
      end

      # Remove all keys from all databases
      #
      # @param mode [Symbol, nil] :async or :sync
      # @return [String] "OK"
      def flushall(mode = nil)
        if mode
          call_1arg(CMD_FLUSHALL, mode == :async ? OPT_ASYNC : OPT_SYNC)
        else
          call(CMD_FLUSHALL)
        end
      end

      # Select the Redis logical database
      #
      # @param db [Integer] Database index
      # @return [String] "OK"
      def select(db)
        call_1arg(CMD_SELECT, db)
      end

      # Swap two Redis databases
      #
      # @param db1 [Integer] First database index
      # @param db2 [Integer] Second database index
      # @return [String] "OK"
      def swapdb(db1, db2)
        call_2args(CMD_SWAPDB, db1, db2)
      end

      # --- PERSISTENCE ---

      # Synchronously save the dataset to disk
      #
      # @return [String] "OK"
      def save
        call(CMD_SAVE)
      end

      # Asynchronously save the dataset to disk
      #
      # @param schedule [Boolean] Schedule instead of immediate (Redis 6.2+)
      # @return [String] Status message
      def bgsave(schedule: false)
        if schedule
          call_1arg(CMD_BGSAVE, OPT_SCHEDULE)
        else
          call(CMD_BGSAVE)
        end
      end

      # Asynchronously rewrite the AOF file
      #
      # @return [String] Status message
      def bgrewriteaof
        call(CMD_BGREWRITEAOF)
      end

      # Get the UNIX timestamp of the last successful save
      #
      # @return [Integer] UNIX timestamp
      def lastsave
        call(CMD_LASTSAVE)
      end

      # Shut down the server
      #
      # @param mode [Symbol, nil] :nosave or :save
      # @return [nil]
      def shutdown(mode = nil)
        if mode
          call_1arg(CMD_SHUTDOWN, mode == :nosave ? OPT_NOSAVE : CMD_SAVE)
        else
          call(CMD_SHUTDOWN)
        end
      end

      # --- TIME ---

      # Return the server time
      #
      # @return [Array] [unix_timestamp, microseconds]
      def time
        call(CMD_TIME)
      end

      # --- CONFIG ---

      # Get configuration parameters
      #
      # @param pattern [String] Glob-style pattern
      # @return [Hash] Parameter name => value pairs
      def config_get(pattern)
        call_2args(CMD_CONFIG, SUBCMD_GET, pattern)
      end

      # Set a configuration parameter
      #
      # @param parameter [String] Parameter name
      # @param value [String] Parameter value
      # @return [String] "OK"
      def config_set(parameter, value)
        call(CMD_CONFIG, SUBCMD_SET, parameter, value)
      end

      # Rewrite the redis.conf file with in-memory configuration
      #
      # @return [String] "OK"
      def config_rewrite
        call_1arg(CMD_CONFIG, SUBCMD_REWRITE)
      end

      # Reset the stats returned by INFO
      #
      # @return [String] "OK"
      def config_resetstat
        call_1arg(CMD_CONFIG, SUBCMD_RESETSTAT)
      end

      # --- CLIENT ---

      # Get the list of client connections
      #
      # @param type [String, nil] Filter by type (normal, master, replica, pubsub)
      # @return [String] Client list output
      def client_list(type: nil)
        if type
          call(CMD_CLIENT, SUBCMD_LIST, OPT_TYPE, type)
        else
          call_1arg(CMD_CLIENT, SUBCMD_LIST)
        end
      end

      # Get the current connection name
      #
      # @return [String, nil] Connection name
      def client_getname
        call_1arg(CMD_CLIENT, SUBCMD_GETNAME)
      end

      # Set the current connection name
      #
      # @param name [String] Connection name
      # @return [String] "OK"
      def client_setname(name)
        call_2args(CMD_CLIENT, SUBCMD_SETNAME, name)
      end

      # Get the current connection ID
      #
      # @return [Integer] Client ID
      def client_id
        call_1arg(CMD_CLIENT, SUBCMD_ID)
      end

      # Get info about the current connection
      #
      # @return [Hash] Client info
      def client_info
        call_1arg(CMD_CLIENT, SUBCMD_INFO)
      end

      # Kill client connections
      #
      # @param id [Integer, nil] Client ID to kill
      # @param addr [String, nil] Client address (ip:port) to kill
      # @return [Integer] Number of clients killed
      def client_kill(id: nil, addr: nil)
        if id
          call(CMD_CLIENT, SUBCMD_KILL, SUBCMD_ID, id)
        elsif addr
          call(CMD_CLIENT, SUBCMD_KILL, OPT_ADDR, addr)
        else
          call_1arg(CMD_CLIENT, SUBCMD_KILL)
        end
      end

      # Suspend all clients for the specified time
      #
      # @param timeout_ms [Integer] Pause duration in milliseconds
      # @return [String] "OK"
      def client_pause(timeout_ms)
        call_2args(CMD_CLIENT, SUBCMD_PAUSE, timeout_ms)
      end

      # Resume clients paused by CLIENT PAUSE
      #
      # @return [String] "OK"
      def client_unpause
        call_1arg(CMD_CLIENT, SUBCMD_UNPAUSE)
      end

      # Set client eviction mode
      #
      # @param enabled [Boolean] Enable or disable no-evict
      # @return [String] "OK"
      def client_no_evict(enabled)
        call_2args(CMD_CLIENT, SUBCMD_NO_EVICT, enabled ? OPT_ON : OPT_OFF)
      end

      # Get client tracking information
      #
      # Returns information about the current client's tracking status,
      # including whether tracking is enabled, redirect client ID,
      # tracked prefixes, and flags.
      #
      # @return [Array] Tracking information
      # @see https://redis.io/commands/client-trackinginfo/
      def client_trackinginfo
        call_1arg(CMD_CLIENT, SUBCMD_TRACKINGINFO)
      end

      # --- SLOWLOG ---

      # Get the slow log entries
      #
      # @param count [Integer, nil] Max entries to return
      # @return [Array] Slow log entries
      def slowlog_get(count = nil)
        if count
          call_2args(CMD_SLOWLOG, SUBCMD_GET, count)
        else
          call_1arg(CMD_SLOWLOG, SUBCMD_GET)
        end
      end

      # Get the number of entries in the slow log
      #
      # @return [Integer] Number of entries
      def slowlog_len
        call_1arg(CMD_SLOWLOG, SUBCMD_LEN)
      end

      # Reset the slow log
      #
      # @return [String] "OK"
      def slowlog_reset
        call_1arg(CMD_SLOWLOG, SUBCMD_RESET)
      end

      # --- MEMORY ---

      # Get memory diagnostic report
      #
      # @return [String] Diagnostic report
      def memory_doctor
        call_1arg(CMD_MEMORY, SUBCMD_DOCTOR)
      end

      # Get memory allocator statistics
      #
      # @return [Hash] Memory statistics
      def memory_stats
        call_1arg(CMD_MEMORY, SUBCMD_STATS)
      end

      # Ask the allocator to release memory
      #
      # @return [String] "OK"
      def memory_purge
        call_1arg(CMD_MEMORY, SUBCMD_PURGE)
      end

      # Get allocator internal stats
      #
      # @return [String] Allocator stats
      def memory_malloc_stats
        call_1arg(CMD_MEMORY, SUBCMD_MALLOC_STATS)
      end

      # --- OBJECT ---

      # Get the encoding of a key's value
      #
      # @param key [String] Key name
      # @return [String] Encoding name
      def object_encoding(key)
        call_2args(CMD_OBJECT, SUBCMD_ENCODING, key)
      end

      # Get the access frequency of a key (LFU policy)
      #
      # @param key [String] Key name
      # @return [Integer] Access frequency
      def object_freq(key)
        call_2args(CMD_OBJECT, SUBCMD_FREQ, key)
      end

      # Get the idle time of a key in seconds
      #
      # @param key [String] Key name
      # @return [Integer] Idle time in seconds
      def object_idletime(key)
        call_2args(CMD_OBJECT, SUBCMD_IDLETIME, key)
      end

      # Get the reference count of a key's value
      #
      # @param key [String] Key name
      # @return [Integer] Reference count
      def object_refcount(key)
        call_2args(CMD_OBJECT, SUBCMD_REFCOUNT, key)
      end

      # --- COMMAND ---

      # Get the total number of commands
      #
      # @return [Integer] Command count
      def command_count
        call_1arg(CMD_COMMAND, SUBCMD_COUNT)
      end

      # Get command documentation
      #
      # @param command_names [Array<String>] Command names
      # @return [Hash] Command documentation
      def command_docs(*command_names)
        # Fast path for single command
        return call_2args(CMD_COMMAND, SUBCMD_DOCS, command_names[0]) if command_names.size == 1

        call(CMD_COMMAND, SUBCMD_DOCS, *command_names)
      end

      # Get command info
      #
      # @param command_names [Array<String>] Command names
      # @return [Hash] Command info
      def command_info(*command_names)
        # Fast path for single command
        return call_2args(CMD_COMMAND, SUBCMD_INFO, command_names[0]) if command_names.size == 1

        call(CMD_COMMAND, SUBCMD_INFO, *command_names)
      end

      # List all command names
      #
      # @return [Array<String>] Command names
      def command_list
        call_1arg(CMD_COMMAND, SUBCMD_LIST)
      end

      # --- LATENCY ---

      # Get latest latency samples
      #
      # @return [Array] Latest latency events
      def latency_latest
        call_1arg(CMD_LATENCY, SUBCMD_LATEST)
      end

      # Get latency history for an event
      #
      # @param event [String] Event name
      # @return [Array] Latency history entries
      def latency_history(event)
        call_2args(CMD_LATENCY, SUBCMD_HISTORY, event)
      end

      # Reset latency data for events
      #
      # @param events [Array<String>] Event names (empty = reset all)
      # @return [Integer] Number of events reset
      def latency_reset(*events)
        # Fast path for no events
        return call_1arg(CMD_LATENCY, SUBCMD_RESET) if events.empty?

        # Fast path for single event
        return call_2args(CMD_LATENCY, SUBCMD_RESET, events[0]) if events.size == 1

        call(CMD_LATENCY, SUBCMD_RESET, *events)
      end

      # Get a human-readable latency analysis report
      #
      # Analyzes latency data and provides advice about possible
      # latency sources and remediation steps.
      #
      # @return [String] Human-readable latency report
      # @see https://redis.io/commands/latency-doctor/
      def latency_doctor
        call_1arg(CMD_LATENCY, SUBCMD_DOCTOR)
      end

      # Get a latency event's history as an ASCII-art graph
      #
      # @param event [String] The latency event name (e.g., "command", "fast-command")
      # @return [String] ASCII-art graph of latency history
      # @see https://redis.io/commands/latency-graph/
      def latency_graph(event)
        call_2args(CMD_LATENCY, SUBCMD_GRAPH, event)
      end

      # --- MODULE ---

      # List loaded modules
      #
      # @return [Array<Hash>] Module info
      def module_list
        call_1arg(CMD_MODULE, SUBCMD_LIST)
      end

      # Load a module
      #
      # @param path [String] Path to module .so file
      # @param args [Array<String>] Module arguments
      # @return [String] "OK"
      def module_load(path, *args)
        # Fast path for no args
        return call_2args(CMD_MODULE, SUBCMD_LOAD, path) if args.empty?

        call(CMD_MODULE, SUBCMD_LOAD, path, *args)
      end

      # Unload a module
      #
      # @param name [String] Module name
      # @return [String] "OK"
      def module_unload(name)
        call_2args(CMD_MODULE, SUBCMD_UNLOAD, name)
      end

      # --- REPLICATION ---

      # Make the server a replica of another instance
      #
      # @param host [String] Master host
      # @param port [Integer] Master port
      # @return [String] "OK"
      def replicaof(host, port)
        call_2args(CMD_REPLICAOF, host, port)
      end

      # Promote replica to master
      #
      # @return [String] "OK"
      def replicaof_no_one
        call_2args(CMD_REPLICAOF, OPT_NO, OPT_ONE)
      end

      # Wait for replicas to acknowledge writes
      #
      # @param numreplicas [Integer] Number of replicas to wait for
      # @param timeout_ms [Integer] Timeout in milliseconds
      # @return [Integer] Number of replicas that acknowledged
      def wait(numreplicas, timeout_ms)
        call_2args(CMD_WAIT, numreplicas, timeout_ms)
      end

      # Wait for AOF sync on replicas (Redis 7.2+)
      #
      # @param numlocal [Integer] Number of local AOF syncs
      # @param numreplicas [Integer] Number of replica AOF syncs
      # @param timeout_ms [Integer] Timeout in milliseconds
      # @return [Array<Integer>] [local_syncs, replica_syncs]
      def waitaof(numlocal, numreplicas, timeout_ms)
        call_3args(CMD_WAITAOF, numlocal, numreplicas, timeout_ms)
      end

      # --- MISC ---

      # Echo the given string
      #
      # @param message [String] Message to echo
      # @return [String] The echoed message
      def echo(message)
        call_1arg(CMD_ECHO, message)
      end

      # Get debugging information about a key
      #
      # @param key [String] Key name
      # @return [String] Debug info
      def debug_object(key)
        call_2args(CMD_DEBUG, SUBCMD_OBJECT, key)
      end

      # Display server version art
      #
      # @param version [Integer, nil] Art version
      # @return [String] ASCII art
      def lolwut(version: nil)
        if version
          call_2args(CMD_LOLWUT, OPT_VERSION, version)
        else
          call(CMD_LOLWUT)
        end
      end
    end
  end
end
