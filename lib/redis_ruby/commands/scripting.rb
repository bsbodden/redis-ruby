# frozen_string_literal: true

require "digest/sha1"

module RedisRuby
  module Commands
    # Lua scripting commands
    #
    # Redis supports server-side Lua scripting for atomic operations.
    # Scripts are executed atomically - no other command runs during script execution.
    #
    # @example Simple script
    #   redis.eval("return 'hello'", 0)
    #   # => "hello"
    #
    # @example Script with keys and arguments
    #   redis.eval("return redis.call('SET', KEYS[1], ARGV[1])", 1, "mykey", "myvalue")
    #
    # @example Using EVALSHA for cached scripts
    #   sha = redis.script_load("return redis.call('INCR', KEYS[1])")
    #   redis.evalsha(sha, 1, "counter")
    #
    # @see https://redis.io/commands/?group=scripting
    module Scripting
      # Frozen command constants to avoid string allocations
      CMD_EVAL = "EVAL"
      CMD_EVALSHA = "EVALSHA"
      CMD_EVAL_RO = "EVAL_RO"
      CMD_EVALSHA_RO = "EVALSHA_RO"
      CMD_SCRIPT = "SCRIPT"

      # Frozen subcommands
      SUBCMD_LOAD = "LOAD"
      SUBCMD_EXISTS = "EXISTS"
      SUBCMD_FLUSH = "FLUSH"
      SUBCMD_KILL = "KILL"
      SUBCMD_DEBUG = "DEBUG"

      # Execute a Lua script
      #
      # @param script [String] Lua script to execute
      # @param numkeys [Integer] Number of keys (KEYS array size)
      # @param keys_and_args [Array] Keys followed by arguments
      # @return [Object] Script return value
      #
      # @example No keys or args
      #   redis.eval("return 42", 0)
      #
      # @example With keys and args
      #   redis.eval("return redis.call('SET', KEYS[1], ARGV[1])", 1, "key", "value")
      def eval(script, numkeys, *keys_and_args)
        # Fast path: no keys or args
        return call_2args(CMD_EVAL, script, numkeys) if keys_and_args.empty?

        call(CMD_EVAL, script, numkeys, *keys_and_args)
      end

      # Execute a cached Lua script by SHA1 hash
      #
      # More efficient than EVAL when running the same script repeatedly.
      # Raises NOSCRIPT error if script not cached - use script_load first.
      #
      # @param sha [String] SHA1 hash of the script
      # @param numkeys [Integer] Number of keys
      # @param keys_and_args [Array] Keys followed by arguments
      # @return [Object] Script return value
      #
      # @example
      #   sha = redis.script_load("return redis.call('GET', KEYS[1])")
      #   redis.evalsha(sha, 1, "mykey")
      def evalsha(sha, numkeys, *keys_and_args)
        # Fast path: no keys or args
        return call_2args(CMD_EVALSHA, sha, numkeys) if keys_and_args.empty?

        call(CMD_EVALSHA, sha, numkeys, *keys_and_args)
      end

      # Execute a Lua script in read-only mode (Redis 7.0+)
      #
      # Like EVAL but ensures the script only reads data.
      # Can be routed to read replicas.
      #
      # @param script [String] Lua script to execute
      # @param numkeys [Integer] Number of keys
      # @param keys_and_args [Array] Keys followed by arguments
      # @return [Object] Script return value
      def eval_ro(script, numkeys, *keys_and_args)
        # Fast path: no keys or args
        return call_2args(CMD_EVAL_RO, script, numkeys) if keys_and_args.empty?

        call(CMD_EVAL_RO, script, numkeys, *keys_and_args)
      end

      # Execute a cached Lua script in read-only mode (Redis 7.0+)
      #
      # Like EVALSHA but ensures the script only reads data.
      #
      # @param sha [String] SHA1 hash of the script
      # @param numkeys [Integer] Number of keys
      # @param keys_and_args [Array] Keys followed by arguments
      # @return [Object] Script return value
      def evalsha_ro(sha, numkeys, *keys_and_args)
        # Fast path: no keys or args
        return call_2args(CMD_EVALSHA_RO, sha, numkeys) if keys_and_args.empty?

        call(CMD_EVALSHA_RO, sha, numkeys, *keys_and_args)
      end

      # Load a script into the script cache
      #
      # @param script [String] Lua script to cache
      # @return [String] SHA1 hash of the script
      #
      # @example
      #   sha = redis.script_load("return 'cached'")
      #   # => "a42059b356c875f0717db19a51f6aaa9161e77a2"
      def script_load(script)
        call(CMD_SCRIPT, SUBCMD_LOAD, script)
      end

      # Check if scripts exist in the cache
      #
      # @param shas [Array<String>] SHA1 hashes to check
      # @return [Array<Boolean>] True/false for each SHA
      #
      # @example
      #   redis.script_exists(sha1, sha2)
      #   # => [true, false]
      def script_exists(*shas)
        result = call(CMD_SCRIPT, SUBCMD_EXISTS, *shas)
        result.map { |v| v == 1 }
      end

      # Flush the script cache
      #
      # @param mode [Symbol, nil] :async or :sync (default: sync)
      # @return [String] "OK"
      #
      # @example
      #   redis.script_flush
      #   redis.script_flush(:async)
      def script_flush(mode = nil)
        # Redis 6.2+ requires SYNC or ASYNC argument
        # Default to SYNC for backwards compatibility
        flush_mode = mode ? mode.to_s.upcase : "SYNC"
        call(CMD_SCRIPT, SUBCMD_FLUSH, flush_mode)
      end

      # Kill currently executing script
      #
      # Only works if the script has not yet performed any writes.
      #
      # @return [String] "OK"
      def script_kill
        call_2args(CMD_SCRIPT, SUBCMD_KILL)
      end

      # Get debugging info about a script
      #
      # @param subcommand [String] DEBUG subcommand
      # @param args [Array] Subcommand arguments
      # @return [Object] Debug information
      def script_debug(mode)
        call(CMD_SCRIPT, SUBCMD_DEBUG, mode.to_s.upcase)
      end

      # Register a script for efficient repeated execution
      #
      # Returns a Script object that automatically handles EVALSHA/EVAL
      # fallback. On first call, the script is sent via EVAL and cached
      # on the server. Subsequent calls use EVALSHA.
      #
      # @param script [String] Lua script source
      # @return [Script] Callable script object
      #
      # @example
      #   incr = redis.register_script("return redis.call('INCR', KEYS[1])")
      #   incr.call(keys: ["counter"])  # => 1
      #   incr.call(keys: ["counter"])  # => 2
      def register_script(script)
        Script.new(script, self)
      end

      # Execute a script with automatic EVALSHA/EVAL fallback
      #
      # Tries EVALSHA first, falls back to EVAL if script not cached.
      # Caches the script after first execution.
      #
      # @param script [String] Lua script
      # @param keys [Array<String>] Key names
      # @param args [Array] Arguments
      # @return [Object] Script return value
      #
      # @example
      #   redis.evalsha_or_eval("return redis.call('GET', KEYS[1])", ["mykey"])
      def evalsha_or_eval(script, keys = [], args = [])
        sha = Digest::SHA1.hexdigest(script)
        begin
          evalsha(sha, keys.size, *keys, *args)
        rescue CommandError => e
          raise unless e.message.include?("NOSCRIPT")

          eval(script, keys.size, *keys, *args) # rubocop:disable Security/Eval
        end
      end
    end
  end
end
