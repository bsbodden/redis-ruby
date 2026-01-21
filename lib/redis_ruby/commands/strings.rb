# frozen_string_literal: true

module RedisRuby
  module Commands
    # String commands
    #
    # @see https://redis.io/commands/?group=string
    module Strings
      # Increment the integer value of a key by one
      #
      # @param key [String]
      # @return [Integer] value after increment
      def incr(key)
        call("INCR", key)
      end

      # Decrement the integer value of a key by one
      #
      # @param key [String]
      # @return [Integer] value after decrement
      def decr(key)
        call("DECR", key)
      end

      # Increment the integer value of a key by the given amount
      #
      # @param key [String]
      # @param increment [Integer]
      # @return [Integer] value after increment
      def incrby(key, increment)
        call("INCRBY", key, increment)
      end

      # Decrement the integer value of a key by the given amount
      #
      # @param key [String]
      # @param decrement [Integer]
      # @return [Integer] value after decrement
      def decrby(key, decrement)
        call("DECRBY", key, decrement)
      end

      # Increment the float value of a key by the given amount
      #
      # @param key [String]
      # @param increment [Float]
      # @return [String] value after increment (as string)
      def incrbyfloat(key, increment)
        call("INCRBYFLOAT", key, increment)
      end

      # Append a value to a key
      #
      # @param key [String]
      # @param value [String]
      # @return [Integer] length of string after append
      def append(key, value)
        call("APPEND", key, value)
      end

      # Get the length of the value stored at key
      #
      # @param key [String]
      # @return [Integer] length of string, or 0 if key doesn't exist
      def strlen(key)
        call("STRLEN", key)
      end

      # Get a substring of the string stored at key
      #
      # @param key [String]
      # @param start_pos [Integer] start index (0-based, negative for end-relative)
      # @param end_pos [Integer] end index (inclusive)
      # @return [String] substring
      def getrange(key, start_pos, end_pos)
        call("GETRANGE", key, start_pos, end_pos)
      end

      # Overwrite part of a string at key starting at the specified offset
      #
      # @param key [String]
      # @param offset [Integer]
      # @param value [String]
      # @return [Integer] length of string after modification
      def setrange(key, offset, value)
        call("SETRANGE", key, offset, value)
      end

      # Get the values of multiple keys
      #
      # @param keys [Array<String>]
      # @return [Array<String, nil>] values (nil for missing keys)
      def mget(*keys)
        call("MGET", *keys)
      end

      # Set multiple keys to multiple values
      #
      # @param args [Array] key-value pairs (key1, value1, key2, value2, ...)
      # @return [String] "OK"
      def mset(*)
        call("MSET", *)
      end

      # Set multiple keys to multiple values, only if none of the keys exist
      #
      # @param args [Array] key-value pairs
      # @return [Integer] 1 if all keys were set, 0 if no keys were set
      def msetnx(*)
        call("MSETNX", *)
      end

      # Set the value of a key, only if the key does not exist
      #
      # @param key [String]
      # @param value [String]
      # @return [Boolean] true if key was set, false if key already existed
      def setnx(key, value)
        call("SETNX", key, value) == 1
      end

      # Set the value and expiration of a key (seconds)
      #
      # @param key [String]
      # @param seconds [Integer] TTL in seconds
      # @param value [String]
      # @return [String] "OK"
      def setex(key, seconds, value)
        call("SETEX", key, seconds, value)
      end

      # Set the value and expiration of a key (milliseconds)
      #
      # @param key [String]
      # @param milliseconds [Integer] TTL in milliseconds
      # @param value [String]
      # @return [String] "OK"
      def psetex(key, milliseconds, value)
        call("PSETEX", key, milliseconds, value)
      end

      # Set the value of a key and return its old value
      #
      # @param key [String]
      # @param value [String]
      # @return [String, nil] old value, or nil if key didn't exist
      def getset(key, value)
        call("GETSET", key, value)
      end

      # Get the value of a key and delete it
      #
      # @param key [String]
      # @return [String, nil] value, or nil if key didn't exist
      def getdel(key)
        call("GETDEL", key)
      end

      # Get the value of a key and optionally set its expiration
      #
      # @param key [String]
      # @param ex [Integer, nil] expiration in seconds
      # @param px [Integer, nil] expiration in milliseconds
      # @param exat [Integer, nil] absolute Unix timestamp in seconds
      # @param pxat [Integer, nil] absolute Unix timestamp in milliseconds
      # @param persist [Boolean] remove TTL
      # @return [String, nil] value
      def getex(key, ex: nil, px: nil, exat: nil, pxat: nil, persist: false)
        args = ["GETEX", key]
        args.push("EX", ex) if ex
        args.push("PX", px) if px
        args.push("EXAT", exat) if exat
        args.push("PXAT", pxat) if pxat
        args.push("PERSIST") if persist
        call(*args)
      end
    end
  end
end
