# frozen_string_literal: true

module RedisRuby
  module Commands
    # Key commands (generic commands that work on any key type)
    #
    # @see https://redis.io/commands/?group=generic
    module Keys
      # Delete one or more keys
      #
      # @param keys [Array<String>]
      # @return [Integer] number of keys deleted
      def del(*keys)
        call("DEL", *keys)
      end

      # Check if one or more keys exist
      #
      # @param keys [Array<String>]
      # @return [Integer] number of keys that exist
      def exists(*keys)
        call("EXISTS", *keys)
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
        args = ["EXPIRE", key, seconds]
        args.push("NX") if nx
        args.push("XX") if xx
        args.push("GT") if gt
        args.push("LT") if lt
        call(*args)
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
        args = ["PEXPIRE", key, milliseconds]
        args.push("NX") if nx
        args.push("XX") if xx
        args.push("GT") if gt
        args.push("LT") if lt
        call(*args)
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
        args = ["EXPIREAT", key, timestamp]
        args.push("NX") if nx
        args.push("XX") if xx
        args.push("GT") if gt
        args.push("LT") if lt
        call(*args)
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
        args = ["PEXPIREAT", key, timestamp]
        args.push("NX") if nx
        args.push("XX") if xx
        args.push("GT") if gt
        args.push("LT") if lt
        call(*args)
      end

      # Get the time to live for a key in seconds
      #
      # @param key [String]
      # @return [Integer] TTL in seconds, -1 if no TTL, -2 if key doesn't exist
      def ttl(key)
        call("TTL", key)
      end

      # Get the time to live for a key in milliseconds
      #
      # @param key [String]
      # @return [Integer] TTL in milliseconds, -1 if no TTL, -2 if key doesn't exist
      def pttl(key)
        call("PTTL", key)
      end

      # Remove the expiration from a key
      #
      # @param key [String]
      # @return [Integer] 1 if timeout was removed, 0 if key doesn't exist or has no TTL
      def persist(key)
        call("PERSIST", key)
      end

      # Get the expiration Unix timestamp for a key (seconds)
      #
      # @param key [String]
      # @return [Integer] timestamp, -1 if no TTL, -2 if key doesn't exist
      def expiretime(key)
        call("EXPIRETIME", key)
      end

      # Get the expiration Unix timestamp for a key (milliseconds)
      #
      # @param key [String]
      # @return [Integer] timestamp, -1 if no TTL, -2 if key doesn't exist
      def pexpiretime(key)
        call("PEXPIRETIME", key)
      end

      # Find all keys matching the given pattern
      #
      # @param pattern [String] glob-style pattern
      # @return [Array<String>] matching keys
      # @note Use SCAN in production for large datasets
      def keys(pattern)
        call("KEYS", pattern)
      end

      # Incrementally iterate over keys
      #
      # @param cursor [Integer] cursor position (0 to start)
      # @param match [String, nil] pattern to match
      # @param count [Integer, nil] hint for number of elements to return
      # @param type [String, nil] filter by key type
      # @return [Array] [next_cursor, keys]
      def scan(cursor, match: nil, count: nil, type: nil)
        args = ["SCAN", cursor]
        args.push("MATCH", match) if match
        args.push("COUNT", count) if count
        args.push("TYPE", type) if type
        call(*args)
      end

      # Determine the type stored at key
      #
      # @param key [String]
      # @return [String] type (string, list, set, zset, hash, stream, none)
      def type(key)
        call("TYPE", key)
      end

      # Rename a key
      #
      # @param key [String] old name
      # @param newkey [String] new name
      # @return [String] "OK"
      # @raise [CommandError] if key doesn't exist
      def rename(key, newkey)
        call("RENAME", key, newkey)
      end

      # Rename a key, only if the new key does not exist
      #
      # @param key [String] old name
      # @param newkey [String] new name
      # @return [Integer] 1 if renamed, 0 if newkey already exists
      def renamenx(key, newkey)
        call("RENAMENX", key, newkey)
      end

      # Return a random key from the database
      #
      # @return [String, nil] random key or nil if database is empty
      def randomkey
        call("RANDOMKEY")
      end

      # Unlink one or more keys (async delete)
      #
      # @param keys [Array<String>]
      # @return [Integer] number of keys unlinked
      def unlink(*keys)
        call("UNLINK", *keys)
      end

      # Create a key using the provided serialized value
      #
      # @param key [String]
      # @param ttl [Integer] TTL in milliseconds (0 for no expiry)
      # @param serialized_value [String] serialized value from DUMP
      # @param replace [Boolean] replace existing key
      # @return [String] "OK"
      def restore(key, ttl, serialized_value, replace: false)
        args = ["RESTORE", key, ttl, serialized_value]
        args.push("REPLACE") if replace
        call(*args)
      end

      # Serialize the value stored at key
      #
      # @param key [String]
      # @return [String, nil] serialized value or nil if key doesn't exist
      def dump(key)
        call("DUMP", key)
      end

      # Touch one or more keys (update last access time)
      #
      # @param keys [Array<String>]
      # @return [Integer] number of keys touched
      def touch(*keys)
        call("TOUCH", *keys)
      end

      # Get the number of bytes that a key and its value require in RAM
      #
      # @param key [String]
      # @return [Integer, nil] bytes or nil if key doesn't exist
      def memory_usage(key)
        call("MEMORY", "USAGE", key)
      end

      # Copy a key
      #
      # @param source [String]
      # @param destination [String]
      # @param db [Integer, nil] destination database
      # @param replace [Boolean] replace existing key
      # @return [Integer] 1 if copied, 0 if not copied
      def copy(source, destination, db: nil, replace: false)
        args = ["COPY", source, destination]
        args.push("DB", db) if db
        args.push("REPLACE") if replace
        call(*args)
      end
    end
  end
end
