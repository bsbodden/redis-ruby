# frozen_string_literal: true

module RedisRuby
  module Commands
    # Redis Functions commands (Redis 7.0+)
    #
    # Functions provide a more robust alternative to Lua scripting with
    # libraries, named functions, and better management capabilities.
    #
    # @example Load and call a function
    #   redis.function_load("#!lua name=mylib\nredis.register_function('myfunc', function() return 1 end)")
    #   redis.fcall("myfunc", keys: ["key1"], args: ["arg1"])
    #
    # @example List loaded libraries
    #   redis.function_list
    #   redis.function_list(library_name: "mylib", with_code: true)
    #
    # @see https://redis.io/commands/?group=scripting
    module Functions
      # Frozen command constants to avoid string allocations
      CMD_FUNCTION = "FUNCTION"
      CMD_FCALL = "FCALL"
      CMD_FCALL_RO = "FCALL_RO"

      # Frozen subcommands
      SUBCMD_LOAD = "LOAD"
      SUBCMD_LIST = "LIST"
      SUBCMD_DELETE = "DELETE"
      SUBCMD_FLUSH = "FLUSH"
      SUBCMD_DUMP = "DUMP"
      SUBCMD_RESTORE = "RESTORE"
      SUBCMD_STATS = "STATS"

      # Frozen options
      OPT_REPLACE = "REPLACE"
      OPT_LIBRARYNAME = "LIBRARYNAME"
      OPT_WITHCODE = "WITHCODE"

      # Load a function library into Redis
      #
      # @param code [String] Library code (must start with engine/name header)
      # @param replace [Boolean] Replace existing library if true
      # @return [String] Library name
      #
      # @example
      #   redis.function_load("#!lua name=mylib\nredis.register_function('myfunc', function() return 1 end)")
      #   # => "mylib"
      #
      # @example Replace existing
      #   redis.function_load(code, replace: true)
      def function_load(code, replace: false)
        if replace
          call(CMD_FUNCTION, SUBCMD_LOAD, OPT_REPLACE, code)
        else
          call_2args(CMD_FUNCTION, SUBCMD_LOAD, code)
        end
      end

      # List loaded function libraries
      #
      # @param library_name [String, nil] Filter by library name
      # @param with_code [Boolean] Include library source code
      # @return [Array<Hash>] List of library info hashes
      #
      # @example List all
      #   redis.function_list
      #
      # @example Filter by name with code
      #   redis.function_list(library_name: "mylib", with_code: true)
      def function_list(library_name: nil, with_code: false)
        # Fast path: no filters
        if library_name.nil? && !with_code
          return call_1arg(CMD_FUNCTION, SUBCMD_LIST)
        end

        args = [CMD_FUNCTION, SUBCMD_LIST]
        args.push(OPT_LIBRARYNAME, library_name) if library_name
        args.push(OPT_WITHCODE) if with_code
        call(*args)
      end

      # Delete a function library
      #
      # @param library_name [String] Name of the library to delete
      # @return [String] "OK"
      def function_delete(library_name)
        call_2args(CMD_FUNCTION, SUBCMD_DELETE, library_name)
      end

      # Flush all function libraries
      #
      # @param mode [Symbol, nil] :async or :sync (default: server decides)
      # @return [String] "OK"
      def function_flush(mode = nil)
        if mode
          call_2args(CMD_FUNCTION, SUBCMD_FLUSH, mode.to_s.upcase)
        else
          call_1arg(CMD_FUNCTION, SUBCMD_FLUSH)
        end
      end

      # Dump all function libraries as serialized binary
      #
      # @return [String] Serialized binary data
      def function_dump
        call_1arg(CMD_FUNCTION, SUBCMD_DUMP)
      end

      # Restore function libraries from serialized binary
      #
      # @param data [String] Serialized binary data from function_dump
      # @param policy [Symbol, nil] Restore policy (:flush, :append, :replace)
      # @return [String] "OK"
      def function_restore(data, policy: nil)
        if policy
          call(CMD_FUNCTION, SUBCMD_RESTORE, data, policy.to_s.upcase)
        else
          call_2args(CMD_FUNCTION, SUBCMD_RESTORE, data)
        end
      end

      # Get function statistics
      #
      # @return [Hash] Statistics about running scripts and engines
      def function_stats
        call_1arg(CMD_FUNCTION, SUBCMD_STATS)
      end

      # Call a function
      #
      # @param name [String] Function name
      # @param keys [Array<String>] Key names accessed by the function
      # @param args [Array] Additional arguments
      # @return [Object] Function return value
      #
      # @example
      #   redis.fcall("myfunc", keys: ["key1"], args: ["arg1"])
      def fcall(name, keys: [], args: [])
        # Fast path: no keys or args
        if keys.empty? && args.empty?
          return call_2args(CMD_FCALL, name, 0)
        end

        call(CMD_FCALL, name, keys.size, *keys, *args)
      end

      # Call a function in read-only mode
      #
      # Like FCALL but ensures the function only reads data.
      # Can be routed to read replicas.
      #
      # @param name [String] Function name
      # @param keys [Array<String>] Key names accessed by the function
      # @param args [Array] Additional arguments
      # @return [Object] Function return value
      def fcall_ro(name, keys: [], args: [])
        # Fast path: no keys or args
        if keys.empty? && args.empty?
          return call_2args(CMD_FCALL_RO, name, 0)
        end

        call(CMD_FCALL_RO, name, keys.size, *keys, *args)
      end
    end
  end
end
