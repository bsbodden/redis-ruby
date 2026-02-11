# frozen_string_literal: true

require "json"

module RedisRuby
  module Commands
    # RedisJSON commands for native JSON document storage
    #
    # Provides commands for storing, retrieving, and manipulating JSON documents.
    # Requires Redis Stack or the RedisJSON module.
    #
    # @see https://redis.io/docs/stack/json/
    #
    # @example Basic usage
    #   client.json_set("user:1", "$", { name: "Alice", age: 30 })
    #   client.json_get("user:1", "$.name")  # => ["Alice"]
    #
    module JSON
      # Frozen command constants to avoid string allocations
      CMD_JSON_SET = "JSON.SET"
      CMD_JSON_GET = "JSON.GET"
      CMD_JSON_MGET = "JSON.MGET"
      CMD_JSON_DEL = "JSON.DEL"
      CMD_JSON_TYPE = "JSON.TYPE"
      CMD_JSON_NUMINCRBY = "JSON.NUMINCRBY"
      CMD_JSON_NUMMULTBY = "JSON.NUMMULTBY"
      CMD_JSON_STRAPPEND = "JSON.STRAPPEND"
      CMD_JSON_STRLEN = "JSON.STRLEN"
      CMD_JSON_ARRAPPEND = "JSON.ARRAPPEND"
      CMD_JSON_ARRLEN = "JSON.ARRLEN"
      CMD_JSON_ARRINDEX = "JSON.ARRINDEX"
      CMD_JSON_ARRINSERT = "JSON.ARRINSERT"
      CMD_JSON_ARRPOP = "JSON.ARRPOP"
      CMD_JSON_ARRTRIM = "JSON.ARRTRIM"
      CMD_JSON_OBJKEYS = "JSON.OBJKEYS"
      CMD_JSON_OBJLEN = "JSON.OBJLEN"
      CMD_JSON_CLEAR = "JSON.CLEAR"
      CMD_JSON_TOGGLE = "JSON.TOGGLE"
      CMD_JSON_DEBUG = "JSON.DEBUG"

      # Frozen options
      OPT_NX = "NX"
      OPT_XX = "XX"
      OPT_MEMORY = "MEMORY"
      DEFAULT_PATH = "$"

      # Set JSON value at path
      #
      # @param key [String] Redis key
      # @param path [String] JSONPath (default "$" for root)
      # @param value [Object] Value to set (will be JSON encoded)
      # @param nx [Boolean] Only set if path doesn't exist
      # @param xx [Boolean] Only set if path exists
      # @return [String, nil] "OK" or nil
      # @example
      #   client.json_set("doc", "$", { name: "test" })
      #   client.json_set("doc", "$.age", 30)
      def json_set(key, path, value, nx: false, xx: false)
        json_val = ::JSON.generate(value)
        # Fast path: no options
        return call_3args(CMD_JSON_SET, key, path, json_val) if !nx && !xx

        args = [key, path, json_val]
        args << OPT_NX if nx
        args << OPT_XX if xx
        call(CMD_JSON_SET, *args)
      end

      # Get JSON value at path(s)
      #
      # @param key [String] Redis key
      # @param paths [Array<String>] JSONPaths to retrieve (default "$")
      # @return [Object, nil] Decoded JSON value(s) or nil
      # @example
      #   client.json_get("doc", "$.name")  # => ["test"]
      #   client.json_get("doc", "$.name", "$.age")  # => { "$.name" => [...], "$.age" => [...] }
      def json_get(key, *paths)
        # Fast path: default path
        result = if paths.empty?
                   call_2args(CMD_JSON_GET, key, DEFAULT_PATH)
                 elsif paths.size == 1
                   call_2args(CMD_JSON_GET, key, paths[0])
                 else
                   call(CMD_JSON_GET, key, *paths)
                 end
        return nil if result.nil?

        ::JSON.parse(result)
      end

      # Get JSON values from multiple keys
      #
      # @param keys [Array<String>] Redis keys
      # @param path [String] JSONPath (default "$")
      # @return [Array] Array of decoded JSON values (nil for missing keys)
      # @example
      #   client.json_mget("doc1", "doc2", path: "$.name")
      def json_mget(*keys, path: "$")
        results = call(CMD_JSON_MGET, *keys, path)
        results.map { |r| r.nil? ? nil : ::JSON.parse(r) }
      end

      # Delete JSON value at path
      #
      # @param key [String] Redis key
      # @param path [String] JSONPath (default "$" for entire document)
      # @return [Integer] Number of paths deleted
      # @example
      #   client.json_del("doc", "$.age")
      def json_del(key, path = "$")
        call_2args(CMD_JSON_DEL, key, path)
      end

      # Get JSON value type at path
      #
      # @param key [String] Redis key
      # @param path [String] JSONPath (default "$")
      # @return [Array<String>] Array of type names
      # @example
      #   client.json_type("doc", "$.name")  # => ["string"]
      def json_type(key, path = "$")
        call_2args(CMD_JSON_TYPE, key, path)
      end

      # Increment numeric value at path
      #
      # @param key [String] Redis key
      # @param path [String] JSONPath to numeric value
      # @param value [Numeric] Amount to increment by
      # @return [Array<Numeric>] New value(s)
      # @example
      #   client.json_numincrby("doc", "$.age", 1)  # => [31]
      def json_numincrby(key, path, value)
        result = call_3args(CMD_JSON_NUMINCRBY, key, path, value.to_s)
        ::JSON.parse(result)
      end

      # Multiply numeric value at path
      #
      # @param key [String] Redis key
      # @param path [String] JSONPath to numeric value
      # @param value [Numeric] Amount to multiply by
      # @return [Array<Numeric>] New value(s)
      # @example
      #   client.json_nummultby("doc", "$.score", 2)  # => [200]
      def json_nummultby(key, path, value)
        result = call_3args(CMD_JSON_NUMMULTBY, key, path, value.to_s)
        ::JSON.parse(result)
      end

      # Append string to value at path
      #
      # @param key [String] Redis key
      # @param path [String] JSONPath to string value
      # @param value [String] String to append
      # @return [Array<Integer>] New string length(s)
      # @example
      #   client.json_strappend("doc", "$.name", " Smith")
      def json_strappend(key, path, value)
        call_3args(CMD_JSON_STRAPPEND, key, path, ::JSON.generate(value))
      end

      # Get string length at path
      #
      # @param key [String] Redis key
      # @param path [String] JSONPath to string value (default "$")
      # @return [Array<Integer>] String length(s)
      # @example
      #   client.json_strlen("doc", "$.name")  # => [5]
      def json_strlen(key, path = "$")
        call_2args(CMD_JSON_STRLEN, key, path)
      end

      # Append values to array at path
      #
      # @param key [String] Redis key
      # @param path [String] JSONPath to array
      # @param values [Array] Values to append
      # @return [Array<Integer>] New array length(s)
      # @example
      #   client.json_arrappend("doc", "$.tags", "ruby", "redis")
      def json_arrappend(key, path, *values)
        json_values = values.map { |v| ::JSON.generate(v) }
        call(CMD_JSON_ARRAPPEND, key, path, *json_values)
      end

      # Get array length at path
      #
      # @param key [String] Redis key
      # @param path [String] JSONPath to array (default "$")
      # @return [Array<Integer>] Array length(s)
      # @example
      #   client.json_arrlen("doc", "$.tags")  # => [3]
      def json_arrlen(key, path = "$")
        call_2args(CMD_JSON_ARRLEN, key, path)
      end

      # Get index of value in array
      #
      # @param key [String] Redis key
      # @param path [String] JSONPath to array
      # @param value [Object] Value to find
      # @param start [Integer] Start index (default 0)
      # @param stop [Integer] Stop index (default 0 = end)
      # @return [Array<Integer>] Index of value (-1 if not found)
      # @example
      #   client.json_arrindex("doc", "$.tags", "ruby")  # => [0]
      def json_arrindex(key, path, value, start: 0, stop: 0)
        call(CMD_JSON_ARRINDEX, key, path, ::JSON.generate(value), start, stop)
      end

      # Insert values into array at index
      #
      # @param key [String] Redis key
      # @param path [String] JSONPath to array
      # @param index [Integer] Index to insert at
      # @param values [Array] Values to insert
      # @return [Array<Integer>] New array length(s)
      # @example
      #   client.json_arrinsert("doc", "$.tags", 1, "new_tag")
      def json_arrinsert(key, path, index, *values)
        json_values = values.map { |v| ::JSON.generate(v) }
        call(CMD_JSON_ARRINSERT, key, path, index, *json_values)
      end

      # Pop value from array
      #
      # @param key [String] Redis key
      # @param path [String] JSONPath to array (default "$")
      # @param index [Integer] Index to pop from (default -1 = last)
      # @return [Array] Popped value(s)
      # @example
      #   client.json_arrpop("doc", "$.tags")  # => ["last_tag"]
      def json_arrpop(key, path = "$", index = -1)
        result = call_3args(CMD_JSON_ARRPOP, key, path, index)
        return nil if result.nil?

        if result.is_a?(Array)
          result.map { |r| r.nil? ? nil : ::JSON.parse(r) }
        else
          ::JSON.parse(result)
        end
      end

      # Trim array to specified range
      #
      # @param key [String] Redis key
      # @param path [String] JSONPath to array
      # @param start [Integer] Start index
      # @param stop [Integer] Stop index
      # @return [Array<Integer>] New array length(s)
      # @example
      #   client.json_arrtrim("doc", "$.tags", 0, 2)
      def json_arrtrim(key, path, start, stop)
        call(CMD_JSON_ARRTRIM, key, path, start, stop)
      end

      # Get object keys at path
      #
      # @param key [String] Redis key
      # @param path [String] JSONPath to object (default "$")
      # @return [Array<Array<String>>] Array of key arrays
      # @example
      #   client.json_objkeys("doc")  # => [["name", "age"]]
      def json_objkeys(key, path = "$")
        call_2args(CMD_JSON_OBJKEYS, key, path)
      end

      # Get object length at path
      #
      # @param key [String] Redis key
      # @param path [String] JSONPath to object (default "$")
      # @return [Array<Integer>] Number of keys in object(s)
      # @example
      #   client.json_objlen("doc")  # => [2]
      def json_objlen(key, path = "$")
        call_2args(CMD_JSON_OBJLEN, key, path)
      end

      # Clear container value (array/object) at path
      #
      # @param key [String] Redis key
      # @param path [String] JSONPath (default "$")
      # @return [Integer] Number of values cleared
      # @example
      #   client.json_clear("doc", "$.tags")
      def json_clear(key, path = "$")
        call_2args(CMD_JSON_CLEAR, key, path)
      end

      # Toggle boolean value at path
      #
      # @param key [String] Redis key
      # @param path [String] JSONPath to boolean value
      # @return [Array<Boolean>] New value(s)
      # @example
      #   client.json_toggle("doc", "$.active")  # => [false]
      def json_toggle(key, path)
        result = call_2args(CMD_JSON_TOGGLE, key, path)
        result.map { |v| v == 1 }
      end

      # Debug memory usage of key
      #
      # @param key [String] Redis key
      # @param path [String] JSONPath (default "$")
      # @return [Integer] Memory usage in bytes
      # @example
      #   client.json_debug_memory("doc")  # => 256
      def json_debug_memory(key, path = "$")
        call(CMD_JSON_DEBUG, OPT_MEMORY, key, path)
      end

      # Create a chainable JSON proxy for idiomatic operations
      #
      # @param key_parts [Array<Symbol, String>] Key components (joined with ":")
      # @return [RedisRuby::DSL::JSONProxy] Chainable JSON proxy
      #
      # @example Basic usage
      #   redis.json(:user, 1).set(name: "Alice", age: 30)
      #   redis.json(:user, 1).get(:name)  # => "Alice"
      #
      # @example Chaining operations
      #   redis.json(:user, 1)
      #     .set(name: "Alice", age: 30)
      #     .increment(:age, 1)
      #     .append(:tags, "ruby", "redis")
      #
      # @example Symbol-based paths
      #   redis.json(:user, 1).set(:name, "Alice")
      #   redis.json(:user, 1).get(:name)  # => "Alice"
      #   redis.json(:user, 1).increment(:age)
      def json(*key_parts)
        require_relative "../dsl/json_proxy"
        RedisRuby::DSL::JSONProxy.new(self, *key_parts)
      end
    end
  end
end
