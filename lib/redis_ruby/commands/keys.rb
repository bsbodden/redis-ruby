# frozen_string_literal: true

module RedisRuby
  module Commands
    # Key commands (generic commands that work on any key type)
    #
    # @see https://redis.io/commands/?group=generic
    module Keys
      # Frozen command constants to avoid string allocations
      CMD_DEL = "DEL"
      CMD_EXISTS = "EXISTS"
      CMD_EXPIRE = "EXPIRE"
      CMD_PEXPIRE = "PEXPIRE"
      CMD_EXPIREAT = "EXPIREAT"
      CMD_PEXPIREAT = "PEXPIREAT"
      CMD_TTL = "TTL"
      CMD_PTTL = "PTTL"
      CMD_PERSIST = "PERSIST"
      CMD_EXPIRETIME = "EXPIRETIME"
      CMD_PEXPIRETIME = "PEXPIRETIME"
      CMD_KEYS = "KEYS"
      CMD_SCAN = "SCAN"
      CMD_TYPE = "TYPE"
      CMD_RENAME = "RENAME"
      CMD_RENAMENX = "RENAMENX"
      CMD_RANDOMKEY = "RANDOMKEY"
      CMD_UNLINK = "UNLINK"
      CMD_RESTORE = "RESTORE"
      CMD_DUMP = "DUMP"
      CMD_TOUCH = "TOUCH"
      CMD_MEMORY = "MEMORY"
      CMD_COPY = "COPY"

      # Frozen option strings
      OPT_MATCH = "MATCH"
      OPT_COUNT = "COUNT"
      OPT_TYPE = "TYPE"
      OPT_REPLACE = "REPLACE"
      OPT_DB = "DB"
      OPT_USAGE = "USAGE"
      OPT_NX = "NX"
      OPT_XX = "XX"
      OPT_GT = "GT"
      OPT_LT = "LT"
      # Delete one or more keys
      #
      # @param keys [Array<String>]
      # @return [Integer] number of keys deleted
      def del(*keys)
        # Fast path for single key (most common)
        return call_1arg(CMD_DEL, keys[0]) if keys.size == 1

        call(CMD_DEL, *keys)
      end

      # Check if one or more keys exist
      #
      # @param keys [Array<String>]
      # @return [Integer] number of keys that exist
      def exists(*keys)
        # Fast path for single key (most common)
        return call_1arg(CMD_EXISTS, keys[0]) if keys.size == 1

        call(CMD_EXISTS, *keys)
      end

      # Set a key's time to live in seconds
      #
      # @param key [String]
      # @param seconds [Integer]
      # @param nx [Boolean] only set if key has no expiration (Redis 7.0+)
      # @param xx [Boolean] only set if key already has expiration (Redis 7.0+)
      # @param gt [Boolean] only set if new TTL > current TTL (Redis 7.0+)
      # @param lt [Boolean] only set if new TTL < current TTL (Redis 7.0+)
      # @return [Integer] 1 if timeout was set, 0 if not set
      def expire(key, seconds, nx: false, xx: false, gt: false, lt: false)
        call(*build_expire_args(CMD_EXPIRE, key, seconds, nx: nx, xx: xx, gt: gt, lt: lt))
      end

      # Set a key's time to live in milliseconds
      #
      # @param key [String]
      # @param milliseconds [Integer]
      # @param nx [Boolean] only set if key has no expiration (Redis 7.0+)
      # @param xx [Boolean] only set if key already has expiration (Redis 7.0+)
      # @param gt [Boolean] only set if new TTL > current TTL (Redis 7.0+)
      # @param lt [Boolean] only set if new TTL < current TTL (Redis 7.0+)
      # @return [Integer] 1 if timeout was set, 0 if not set
      def pexpire(key, milliseconds, nx: false, xx: false, gt: false, lt: false)
        call(*build_expire_args(CMD_PEXPIRE, key, milliseconds, nx: nx, xx: xx, gt: gt, lt: lt))
      end

      # Set the expiration for a key as a Unix timestamp (seconds)
      #
      # @param key [String]
      # @param timestamp [Integer]
      # @param nx [Boolean] only set if key has no expiration (Redis 7.0+)
      # @param xx [Boolean] only set if key already has expiration (Redis 7.0+)
      # @param gt [Boolean] only set if new expiration > current (Redis 7.0+)
      # @param lt [Boolean] only set if new expiration < current (Redis 7.0+)
      # @return [Integer] 1 if timeout was set, 0 if not set
      def expireat(key, timestamp, nx: false, xx: false, gt: false, lt: false)
        call(*build_expire_args(CMD_EXPIREAT, key, timestamp, nx: nx, xx: xx, gt: gt, lt: lt))
      end

      # Set the expiration for a key as a Unix timestamp (milliseconds)
      #
      # @param key [String]
      # @param timestamp [Integer]
      # @param nx [Boolean] only set if key has no expiration (Redis 7.0+)
      # @param xx [Boolean] only set if key already has expiration (Redis 7.0+)
      # @param gt [Boolean] only set if new expiration > current (Redis 7.0+)
      # @param lt [Boolean] only set if new expiration < current (Redis 7.0+)
      # @return [Integer] 1 if timeout was set, 0 if not set
      def pexpireat(key, timestamp, nx: false, xx: false, gt: false, lt: false)
        call(*build_expire_args(CMD_PEXPIREAT, key, timestamp, nx: nx, xx: xx, gt: gt, lt: lt))
      end

      # Get the time to live for a key in seconds
      #
      # @param key [String]
      # @return [Integer] TTL in seconds, -1 if no TTL, -2 if key doesn't exist
      def ttl(key)
        call_1arg(CMD_TTL, key)
      end

      # Get the time to live for a key in milliseconds
      #
      # @param key [String]
      # @return [Integer] TTL in milliseconds, -1 if no TTL, -2 if key doesn't exist
      def pttl(key)
        call_1arg(CMD_PTTL, key)
      end

      # Remove the expiration from a key
      #
      # @param key [String]
      # @return [Integer] 1 if timeout was removed, 0 if key doesn't exist or has no TTL
      def persist(key)
        call_1arg(CMD_PERSIST, key)
      end

      # Get the expiration Unix timestamp for a key (seconds)
      #
      # @param key [String]
      # @return [Integer] timestamp, -1 if no TTL, -2 if key doesn't exist
      def expiretime(key)
        call_1arg(CMD_EXPIRETIME, key)
      end

      # Get the expiration Unix timestamp for a key (milliseconds)
      #
      # @param key [String]
      # @return [Integer] timestamp, -1 if no TTL, -2 if key doesn't exist
      def pexpiretime(key)
        call_1arg(CMD_PEXPIRETIME, key)
      end

      # Find all keys matching the given pattern
      #
      # @param pattern [String] glob-style pattern
      # @return [Array<String>] matching keys
      # @note Use SCAN in production for large datasets
      def keys(pattern)
        call_1arg(CMD_KEYS, pattern)
      end

      # Incrementally iterate over keys
      #
      # @param cursor [Integer] cursor position (0 to start)
      # @param match [String, nil] pattern to match
      # @param count [Integer, nil] hint for number of elements to return
      # @param type [String, nil] filter by key type
      # @return [Array] [next_cursor, keys]
      def scan(cursor, match: nil, count: nil, type: nil)
        args = [CMD_SCAN, cursor]
        args.push(OPT_MATCH, match) if match
        args.push(OPT_COUNT, count) if count
        args.push(OPT_TYPE, type) if type
        call(*args)
      end

      # Determine the type stored at key
      #
      # @param key [String]
      # @return [String] type (string, list, set, zset, hash, stream, none)
      def type(key)
        call_1arg(CMD_TYPE, key)
      end

      # Rename a key
      #
      # @param key [String] old name
      # @param newkey [String] new name
      # @return [String] "OK"
      # @raise [CommandError] if key doesn't exist
      def rename(key, newkey)
        call_2args(CMD_RENAME, key, newkey)
      end

      # Rename a key, only if the new key does not exist
      #
      # @param key [String] old name
      # @param newkey [String] new name
      # @return [Integer] 1 if renamed, 0 if newkey already exists
      def renamenx(key, newkey)
        call_2args(CMD_RENAMENX, key, newkey)
      end

      # Return a random key from the database
      #
      # @return [String, nil] random key or nil if database is empty
      def randomkey
        call(CMD_RANDOMKEY)
      end

      # Unlink one or more keys (async delete)
      #
      # @param keys [Array<String>]
      # @return [Integer] number of keys unlinked
      def unlink(*keys)
        call(CMD_UNLINK, *keys)
      end

      # Create a key using the provided serialized value
      #
      # @param key [String]
      # @param ttl [Integer] TTL in milliseconds (0 for no expiry)
      # @param serialized_value [String] serialized value from DUMP
      # @param replace [Boolean] replace existing key
      # @return [String] "OK"
      def restore(key, ttl, serialized_value, replace: false)
        args = [CMD_RESTORE, key, ttl, serialized_value]
        args.push(OPT_REPLACE) if replace
        call(*args)
      end

      # Serialize the value stored at key
      #
      # @param key [String]
      # @return [String, nil] serialized value or nil if key doesn't exist
      def dump(key)
        call_1arg(CMD_DUMP, key)
      end

      # Touch one or more keys (update last access time)
      #
      # @param keys [Array<String>]
      # @return [Integer] number of keys touched
      def touch(*keys)
        call(CMD_TOUCH, *keys)
      end

      # Get the number of bytes that a key and its value require in RAM
      #
      # @param key [String]
      # @return [Integer, nil] bytes or nil if key doesn't exist
      def memory_usage(key)
        call(CMD_MEMORY, OPT_USAGE, key)
      end

      # Copy a key
      #
      # @param source [String]
      # @param destination [String]
      # @param db [Integer, nil] destination database
      # @param replace [Boolean] replace existing key
      # @return [Integer] 1 if copied, 0 if not copied
      def copy(source, destination, db: nil, replace: false)
        args = [CMD_COPY, source, destination]
        args.push(OPT_DB, db) if db
        args.push(OPT_REPLACE) if replace
        call(*args)
      end

      # Iterate over keys matching pattern
      #
      # Returns an Enumerator that handles cursor management automatically.
      # Much safer than KEYS for large datasets.
      #
      # @param match [String] pattern to match (default: "*")
      # @param count [Integer] hint for number of elements per iteration
      # @param type [String, nil] filter by key type
      # @return [Enumerator] yields each matching key
      # @example
      #   client.scan_iter(match: "user:*").each { |key| puts key }
      #   client.scan_iter(match: "session:*", count: 100).to_a
      #   client.scan_iter(type: "string").first(10)
      def scan_iter(match: "*", count: 10, type: nil)
        Enumerator.new do |yielder|
          cursor = "0"
          loop do
            cursor, keys = scan(cursor, match: match, count: count, type: type)
            keys.each { |key| yielder << key }
            break if cursor == "0"
          end
        end
      end

      private

      # Build arguments for expiration commands with NX/XX/GT/LT options
      # @private
      def build_expire_args(command, key, value, nx:, xx:, gt:, lt:)
        args = [command, key, value]
        args.push(OPT_NX) if nx
        args.push(OPT_XX) if xx
        args.push(OPT_GT) if gt
        args.push(OPT_LT) if lt
        args
      end
    end
  end
end
