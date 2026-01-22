# frozen_string_literal: true

module RedisRuby
  module Commands
    # Hash commands
    #
    # @see https://redis.io/commands/?group=hash
    module Hashes
      # Set the string value of a hash field
      #
      # @param key [String]
      # @param field [String]
      # @param value [String]
      # @return [Integer] 1 if field is new, 0 if updated
      def hset(key, *field_values)
        call("HSET", key, *field_values)
      end

      # Get the value of a hash field
      #
      # @param key [String]
      # @param field [String]
      # @return [String, nil] value or nil
      def hget(key, field)
        call("HGET", key, field)
      end

      # Set the value of a hash field, only if the field does not exist
      #
      # @param key [String]
      # @param field [String]
      # @param value [String]
      # @return [Integer] 1 if set, 0 if field already exists
      def hsetnx(key, field, value)
        call("HSETNX", key, field, value)
      end

      # Get the values of multiple hash fields
      #
      # @param key [String]
      # @param fields [Array<String>]
      # @return [Array<String, nil>] values (nil for missing fields)
      def hmget(key, *fields)
        call("HMGET", key, *fields)
      end

      # Set multiple hash fields to multiple values
      #
      # @param key [String]
      # @param field_values [Array] field1, value1, field2, value2, ...
      # @return [String] "OK"
      def hmset(key, *field_values)
        call("HMSET", key, *field_values)
      end

      # Get all fields and values in a hash
      #
      # @param key [String]
      # @return [Hash] field-value pairs
      def hgetall(key)
        result = call("HGETALL", key)
        return {} if result.empty?

        # Convert array to hash: [f1, v1, f2, v2] -> {f1 => v1, f2 => v2}
        result.each_slice(2).to_h
      end

      # Delete one or more hash fields
      #
      # @param key [String]
      # @param fields [Array<String>]
      # @return [Integer] number of fields deleted
      def hdel(key, *fields)
        call("HDEL", key, *fields)
      end

      # Check if a hash field exists
      #
      # @param key [String]
      # @param field [String]
      # @return [Integer] 1 if exists, 0 if not
      def hexists(key, field)
        call("HEXISTS", key, field)
      end

      # Get all fields in a hash
      #
      # @param key [String]
      # @return [Array<String>] field names
      def hkeys(key)
        call("HKEYS", key)
      end

      # Get all values in a hash
      #
      # @param key [String]
      # @return [Array<String>] values
      def hvals(key)
        call("HVALS", key)
      end

      # Get the number of fields in a hash
      #
      # @param key [String]
      # @return [Integer] number of fields
      def hlen(key)
        call("HLEN", key)
      end

      # Get the length of the value of a hash field
      #
      # @param key [String]
      # @param field [String]
      # @return [Integer] length, or 0 if field/key doesn't exist
      def hstrlen(key, field)
        call("HSTRLEN", key, field)
      end

      # Increment the integer value of a hash field
      #
      # @param key [String]
      # @param field [String]
      # @param increment [Integer]
      # @return [Integer] value after increment
      def hincrby(key, field, increment)
        call("HINCRBY", key, field, increment)
      end

      # Increment the float value of a hash field
      #
      # @param key [String]
      # @param field [String]
      # @param increment [Float]
      # @return [String] value after increment (as string)
      def hincrbyfloat(key, field, increment)
        call("HINCRBYFLOAT", key, field, increment)
      end

      # Incrementally iterate hash fields and values
      #
      # @param key [String]
      # @param cursor [Integer] cursor position (0 to start)
      # @param match [String, nil] pattern to match
      # @param count [Integer, nil] hint for number of elements
      # @return [Array] [next_cursor, [field, value, ...]]
      def hscan(key, cursor, match: nil, count: nil)
        args = ["HSCAN", key, cursor]
        args.push("MATCH", match) if match
        args.push("COUNT", count) if count
        call(*args)
      end

      # Get random fields from a hash
      #
      # @param key [String]
      # @param count [Integer, nil] number of fields to return
      # @param withvalues [Boolean] include values
      # @return [String, Array] random field(s), or field-value pairs
      def hrandfield(key, count: nil, withvalues: false)
        args = ["HRANDFIELD", key]
        args.push(count) if count
        args.push("WITHVALUES") if withvalues
        call(*args)
      end

      # Set expiration (seconds) on hash fields (Redis 7.4+)
      #
      # @param key [String]
      # @param seconds [Integer] TTL in seconds
      # @param fields [Array<String>] fields to set expiration on
      # @param nx [Boolean] only set if field has no expiration
      # @param xx [Boolean] only set if field already has expiration
      # @param gt [Boolean] only set if new TTL > current TTL
      # @param lt [Boolean] only set if new TTL < current TTL
      # @return [Array<Integer>] status for each field (1=set, 0=not set, -2=no field)
      def hexpire(key, seconds, *fields, nx: false, xx: false, gt: false, lt: false)
        call(*build_hexpire_args("HEXPIRE", key, seconds, fields, nx: nx, xx: xx, gt: gt, lt: lt))
      end

      # Set expiration (milliseconds) on hash fields (Redis 7.4+)
      #
      # @param key [String]
      # @param milliseconds [Integer] TTL in milliseconds
      # @param fields [Array<String>] fields to set expiration on
      # @param nx [Boolean] only set if field has no expiration
      # @param xx [Boolean] only set if field already has expiration
      # @param gt [Boolean] only set if new TTL > current TTL
      # @param lt [Boolean] only set if new TTL < current TTL
      # @return [Array<Integer>] status for each field
      def hpexpire(key, milliseconds, *fields, nx: false, xx: false, gt: false, lt: false)
        call(*build_hexpire_args("HPEXPIRE", key, milliseconds, fields, nx: nx, xx: xx, gt: gt, lt: lt))
      end

      # Set expiration (unix timestamp seconds) on hash fields (Redis 7.4+)
      #
      # @param key [String]
      # @param unix_time [Integer] Unix timestamp in seconds
      # @param fields [Array<String>] fields to set expiration on
      # @param nx [Boolean] only set if field has no expiration
      # @param xx [Boolean] only set if field already has expiration
      # @param gt [Boolean] only set if new expiration > current
      # @param lt [Boolean] only set if new expiration < current
      # @return [Array<Integer>] status for each field
      def hexpireat(key, unix_time, *fields, nx: false, xx: false, gt: false, lt: false)
        call(*build_hexpire_args("HEXPIREAT", key, unix_time, fields, nx: nx, xx: xx, gt: gt, lt: lt))
      end

      # Set expiration (unix timestamp milliseconds) on hash fields (Redis 7.4+)
      #
      # @param key [String]
      # @param unix_time_ms [Integer] Unix timestamp in milliseconds
      # @param fields [Array<String>] fields to set expiration on
      # @param nx [Boolean] only set if field has no expiration
      # @param xx [Boolean] only set if field already has expiration
      # @param gt [Boolean] only set if new expiration > current
      # @param lt [Boolean] only set if new expiration < current
      # @return [Array<Integer>] status for each field
      def hpexpireat(key, unix_time_ms, *fields, nx: false, xx: false, gt: false, lt: false)
        call(*build_hexpire_args("HPEXPIREAT", key, unix_time_ms, fields, nx: nx, xx: xx, gt: gt, lt: lt))
      end

      # Get TTL (seconds) for hash fields (Redis 7.4+)
      #
      # @param key [String]
      # @param fields [Array<String>] fields to get TTL for
      # @return [Array<Integer>] TTL for each field (-1=no expiry, -2=no field)
      def httl(key, *fields)
        call("HTTL", key, "FIELDS", fields.length, *fields)
      end

      # Get TTL (milliseconds) for hash fields (Redis 7.4+)
      #
      # @param key [String]
      # @param fields [Array<String>] fields to get TTL for
      # @return [Array<Integer>] TTL in ms for each field (-1=no expiry, -2=no field)
      def hpttl(key, *fields)
        call("HPTTL", key, "FIELDS", fields.length, *fields)
      end

      # Get expiration time (unix timestamp seconds) for hash fields (Redis 7.4+)
      #
      # @param key [String]
      # @param fields [Array<String>] fields to get expiration for
      # @return [Array<Integer>] Unix timestamp for each field (-1=no expiry, -2=no field)
      def hexpiretime(key, *fields)
        call("HEXPIRETIME", key, "FIELDS", fields.length, *fields)
      end

      # Get expiration time (unix timestamp ms) for hash fields (Redis 7.4+)
      #
      # @param key [String]
      # @param fields [Array<String>] fields to get expiration for
      # @return [Array<Integer>] Unix timestamp (ms) for each field (-1=no expiry, -2=no field)
      def hpexpiretime(key, *fields)
        call("HPEXPIRETIME", key, "FIELDS", fields.length, *fields)
      end

      # Remove expiration from hash fields (Redis 7.4+)
      #
      # @param key [String]
      # @param fields [Array<String>] fields to persist
      # @return [Array<Integer>] status for each field (1=removed, -1=no expiry, -2=no field)
      def hpersist(key, *fields)
        call("HPERSIST", key, "FIELDS", fields.length, *fields)
      end

      private

      # Build arguments for hash expiration commands
      # @private
      def build_hexpire_args(command, key, value, fields, nx:, xx:, gt:, lt:)
        args = [command, key, value]
        args.push("NX") if nx
        args.push("XX") if xx
        args.push("GT") if gt
        args.push("LT") if lt
        args.push("FIELDS", fields.length, *fields)
        args
      end
    end
  end
end
