# frozen_string_literal: true

module RedisRuby
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
      # --- INFO ---

      # Get server information and statistics
      #
      # @param section [String, nil] Info section (server, clients, memory, etc.)
      # @return [String] Info output
      def info(section = nil)
        if section
          call("INFO", section)
        else
          call("INFO")
        end
      end

      # --- DATABASE ---

      # Return the number of keys in the selected database
      #
      # @return [Integer] Number of keys
      def dbsize
        call("DBSIZE")
      end

      # Remove all keys from the current database
      #
      # @param mode [Symbol, nil] :async or :sync
      # @return [String] "OK"
      def flushdb(mode = nil)
        if mode
          call("FLUSHDB", mode.to_s.upcase)
        else
          call("FLUSHDB")
        end
      end

      # Remove all keys from all databases
      #
      # @param mode [Symbol, nil] :async or :sync
      # @return [String] "OK"
      def flushall(mode = nil)
        if mode
          call("FLUSHALL", mode.to_s.upcase)
        else
          call("FLUSHALL")
        end
      end

      # Select the Redis logical database
      #
      # @param db [Integer] Database index
      # @return [String] "OK"
      def select(db)
        call("SELECT", db)
      end

      # Swap two Redis databases
      #
      # @param db1 [Integer] First database index
      # @param db2 [Integer] Second database index
      # @return [String] "OK"
      def swapdb(db1, db2)
        call("SWAPDB", db1, db2)
      end

      # --- PERSISTENCE ---

      # Synchronously save the dataset to disk
      #
      # @return [String] "OK"
      def save
        call("SAVE")
      end

      # Asynchronously save the dataset to disk
      #
      # @param schedule [Boolean] Schedule instead of immediate (Redis 6.2+)
      # @return [String] Status message
      def bgsave(schedule: false)
        if schedule
          call("BGSAVE", "SCHEDULE")
        else
          call("BGSAVE")
        end
      end

      # Asynchronously rewrite the AOF file
      #
      # @return [String] Status message
      def bgrewriteaof
        call("BGREWRITEAOF")
      end

      # Get the UNIX timestamp of the last successful save
      #
      # @return [Integer] UNIX timestamp
      def lastsave
        call("LASTSAVE")
      end

      # Shut down the server
      #
      # @param mode [Symbol, nil] :nosave or :save
      # @return [nil]
      def shutdown(mode = nil)
        if mode
          call("SHUTDOWN", mode.to_s.upcase)
        else
          call("SHUTDOWN")
        end
      end

      # --- TIME ---

      # Return the server time
      #
      # @return [Array] [unix_timestamp, microseconds]
      def time
        call("TIME")
      end

      # --- CONFIG ---

      # Get configuration parameters
      #
      # @param pattern [String] Glob-style pattern
      # @return [Hash] Parameter name => value pairs
      def config_get(pattern)
        call("CONFIG", "GET", pattern)
      end

      # Set a configuration parameter
      #
      # @param parameter [String] Parameter name
      # @param value [String] Parameter value
      # @return [String] "OK"
      def config_set(parameter, value)
        call("CONFIG", "SET", parameter, value)
      end

      # Rewrite the redis.conf file with in-memory configuration
      #
      # @return [String] "OK"
      def config_rewrite
        call("CONFIG", "REWRITE")
      end

      # Reset the stats returned by INFO
      #
      # @return [String] "OK"
      def config_resetstat
        call("CONFIG", "RESETSTAT")
      end

      # --- CLIENT ---

      # Get the list of client connections
      #
      # @param type [String, nil] Filter by type (normal, master, replica, pubsub)
      # @return [String] Client list output
      def client_list(type: nil)
        if type
          call("CLIENT", "LIST", "TYPE", type)
        else
          call("CLIENT", "LIST")
        end
      end

      # Get the current connection name
      #
      # @return [String, nil] Connection name
      def client_getname
        call("CLIENT", "GETNAME")
      end

      # Set the current connection name
      #
      # @param name [String] Connection name
      # @return [String] "OK"
      def client_setname(name)
        call("CLIENT", "SETNAME", name)
      end

      # Get the current connection ID
      #
      # @return [Integer] Client ID
      def client_id
        call("CLIENT", "ID")
      end

      # Get info about the current connection
      #
      # @return [Hash] Client info
      def client_info
        call("CLIENT", "INFO")
      end

      # Kill client connections
      #
      # @param id [Integer, nil] Client ID to kill
      # @param addr [String, nil] Client address (ip:port) to kill
      # @return [Integer] Number of clients killed
      def client_kill(id: nil, addr: nil)
        args = ["CLIENT", "KILL"]
        if id
          args.push("ID", id)
        elsif addr
          args.push("ADDR", addr)
        end
        call(*args)
      end

      # Suspend all clients for the specified time
      #
      # @param timeout_ms [Integer] Pause duration in milliseconds
      # @return [String] "OK"
      def client_pause(timeout_ms)
        call("CLIENT", "PAUSE", timeout_ms)
      end

      # Resume clients paused by CLIENT PAUSE
      #
      # @return [String] "OK"
      def client_unpause
        call("CLIENT", "UNPAUSE")
      end

      # Set client eviction mode
      #
      # @param enabled [Boolean] Enable or disable no-evict
      # @return [String] "OK"
      def client_no_evict(enabled)
        call("CLIENT", "NO-EVICT", enabled ? "ON" : "OFF")
      end

      # --- SLOWLOG ---

      # Get the slow log entries
      #
      # @param count [Integer, nil] Max entries to return
      # @return [Array] Slow log entries
      def slowlog_get(count = nil)
        if count
          call("SLOWLOG", "GET", count)
        else
          call("SLOWLOG", "GET")
        end
      end

      # Get the number of entries in the slow log
      #
      # @return [Integer] Number of entries
      def slowlog_len
        call("SLOWLOG", "LEN")
      end

      # Reset the slow log
      #
      # @return [String] "OK"
      def slowlog_reset
        call("SLOWLOG", "RESET")
      end

      # --- MEMORY ---

      # Get memory diagnostic report
      #
      # @return [String] Diagnostic report
      def memory_doctor
        call("MEMORY", "DOCTOR")
      end

      # Get memory allocator statistics
      #
      # @return [Hash] Memory statistics
      def memory_stats
        call("MEMORY", "STATS")
      end

      # Ask the allocator to release memory
      #
      # @return [String] "OK"
      def memory_purge
        call("MEMORY", "PURGE")
      end

      # Get allocator internal stats
      #
      # @return [String] Allocator stats
      def memory_malloc_stats
        call("MEMORY", "MALLOC-STATS")
      end

      # --- OBJECT ---

      # Get the encoding of a key's value
      #
      # @param key [String] Key name
      # @return [String] Encoding name
      def object_encoding(key)
        call("OBJECT", "ENCODING", key)
      end

      # Get the access frequency of a key (LFU policy)
      #
      # @param key [String] Key name
      # @return [Integer] Access frequency
      def object_freq(key)
        call("OBJECT", "FREQ", key)
      end

      # Get the idle time of a key in seconds
      #
      # @param key [String] Key name
      # @return [Integer] Idle time in seconds
      def object_idletime(key)
        call("OBJECT", "IDLETIME", key)
      end

      # Get the reference count of a key's value
      #
      # @param key [String] Key name
      # @return [Integer] Reference count
      def object_refcount(key)
        call("OBJECT", "REFCOUNT", key)
      end

      # --- COMMAND ---

      # Get the total number of commands
      #
      # @return [Integer] Command count
      def command_count
        call("COMMAND", "COUNT")
      end

      # Get command documentation
      #
      # @param command_names [Array<String>] Command names
      # @return [Hash] Command documentation
      def command_docs(*command_names)
        call("COMMAND", "DOCS", *command_names)
      end

      # Get command info
      #
      # @param command_names [Array<String>] Command names
      # @return [Hash] Command info
      def command_info(*command_names)
        call("COMMAND", "INFO", *command_names)
      end

      # List all command names
      #
      # @return [Array<String>] Command names
      def command_list
        call("COMMAND", "LIST")
      end

      # --- LATENCY ---

      # Get latest latency samples
      #
      # @return [Array] Latest latency events
      def latency_latest
        call("LATENCY", "LATEST")
      end

      # Get latency history for an event
      #
      # @param event [String] Event name
      # @return [Array] Latency history entries
      def latency_history(event)
        call("LATENCY", "HISTORY", event)
      end

      # Reset latency data for events
      #
      # @param events [Array<String>] Event names (empty = reset all)
      # @return [Integer] Number of events reset
      def latency_reset(*events)
        call("LATENCY", "RESET", *events)
      end

      # --- MODULE ---

      # List loaded modules
      #
      # @return [Array<Hash>] Module info
      def module_list
        call("MODULE", "LIST")
      end

      # Load a module
      #
      # @param path [String] Path to module .so file
      # @param args [Array<String>] Module arguments
      # @return [String] "OK"
      def module_load(path, *args)
        call("MODULE", "LOAD", path, *args)
      end

      # Unload a module
      #
      # @param name [String] Module name
      # @return [String] "OK"
      def module_unload(name)
        call("MODULE", "UNLOAD", name)
      end

      # --- REPLICATION ---

      # Make the server a replica of another instance
      #
      # @param host [String] Master host
      # @param port [Integer] Master port
      # @return [String] "OK"
      def replicaof(host, port)
        call("REPLICAOF", host, port)
      end

      # Promote replica to master
      #
      # @return [String] "OK"
      def replicaof_no_one
        call("REPLICAOF", "NO", "ONE")
      end

      # Wait for replicas to acknowledge writes
      #
      # @param numreplicas [Integer] Number of replicas to wait for
      # @param timeout_ms [Integer] Timeout in milliseconds
      # @return [Integer] Number of replicas that acknowledged
      def wait(numreplicas, timeout_ms)
        call("WAIT", numreplicas, timeout_ms)
      end

      # Wait for AOF sync on replicas (Redis 7.2+)
      #
      # @param numlocal [Integer] Number of local AOF syncs
      # @param numreplicas [Integer] Number of replica AOF syncs
      # @param timeout_ms [Integer] Timeout in milliseconds
      # @return [Array<Integer>] [local_syncs, replica_syncs]
      def waitaof(numlocal, numreplicas, timeout_ms)
        call("WAITAOF", numlocal, numreplicas, timeout_ms)
      end

      # --- MISC ---

      # Echo the given string
      #
      # @param message [String] Message to echo
      # @return [String] The echoed message
      def echo(message)
        call("ECHO", message)
      end

      # Get debugging information about a key
      #
      # @param key [String] Key name
      # @return [String] Debug info
      def debug_object(key)
        call("DEBUG", "OBJECT", key)
      end

      # Display server version art
      #
      # @param version [Integer, nil] Art version
      # @return [String] ASCII art
      def lolwut(version: nil)
        if version
          call("LOLWUT", "VERSION", version)
        else
          call("LOLWUT")
        end
      end
    end
  end
end
