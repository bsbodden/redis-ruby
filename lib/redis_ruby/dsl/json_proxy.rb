# frozen_string_literal: true

module RR
  module DSL
    # Chainable proxy for JSON operations
    #
    # Provides a fluent interface for working with JSON documents in Redis.
    # Supports symbol-based paths and method chaining.
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
    class JSONProxy
      # @param [RR::Client] Redis client
      # @param key_parts [Array] Key components (will be joined with ":")
      def initialize(client, *key_parts)
        @client = client
        @key = key_parts.map(&:to_s).join(":")
      end

      # Set JSON value at path
      #
      # When called with keyword arguments, sets the root document.
      # When called with positional arguments, sets a specific path.
      #
      # @overload set(**data)
      #   Set root document using keyword arguments
      #   @param data [Hash] Data to set
      #   @example
      #     json.set(name: "Alice", age: 30)
      #
      # @overload set(data)
      #   Set root document using a hash
      #   @param data [Hash] Data to set
      #   @example
      #     json.set({name: "Alice", age: 30})
      #
      # @overload set(path, value, nx: false, xx: false)
      #   Set value at specific path
      #   @param path [Symbol, String] JSONPath
      #   @param value [Object] Value to set
      #   @param nx [Boolean] Only set if path doesn't exist
      #   @param xx [Boolean] Only set if path exists
      #   @example
      #     json.set(:name, "Alice")
      #     json.set("$.age", 30, nx: true)
      #
      # @return [self] For chaining
      def set(*args, **kwargs)
        nx = kwargs.delete(:nx) || false
        xx = kwargs.delete(:xx) || false
        json_set_dispatch(args, kwargs, nx: nx, xx: xx)
        self
      end

      # Get JSON value at path(s)
      #
      # @param paths [Array<Symbol, String>] Paths to retrieve (default root)
      # @return [Object] Decoded JSON value(s)
      #
      # @example Get entire document
      #   json.get  # => { "name" => "Alice", "age" => 30 }
      #
      # @example Get specific path
      #   json.get(:name)  # => "Alice"
      #   json.get("$.age")  # => 30
      def get(*paths)
        return fetch_root if paths.empty?
        return fetch_single_path(paths[0]) if paths.size == 1

        normalized_paths = paths.map { |p| normalize_path(p) }
        @client.json_get(@key, *normalized_paths)
      end

      # Delete JSON value at path
      #
      # @param path [Symbol, String] Path to delete (default root)
      # @return [Integer] Number of paths deleted
      #
      # @example Delete specific path
      #   json.delete(:age)
      #
      # @example Delete entire document
      #   json.delete
      def delete(path = "$")
        path = normalize_path(path)
        @client.json_del(@key, path)
      end
      alias del delete

      # Get type of value at path
      #
      # @param path [Symbol, String] Path (default root)
      # @return [String] Type name
      #
      # @example
      #   json.type(:name)  # => "string"
      #   json.type(:tags)  # => "array"
      def type(path = "$")
        path = normalize_path(path)
        result = @client.json_type(@key, path)
        result.is_a?(Array) && result.size == 1 ? result[0] : result
      end

      # Increment numeric value at path
      #
      # @param path [Symbol, String] Path to numeric value
      # @param amount [Numeric] Amount to increment by (default 1)
      # @return [self] For chaining
      #
      # @example
      #   json.increment(:age)  # Increment by 1
      #   json.increment(:score, 10)  # Increment by 10
      def increment(path, amount = 1)
        path = normalize_path(path)
        @client.json_numincrby(@key, path, amount)
        self
      end
      alias incr increment

      # Decrement numeric value at path
      #
      # @param path [Symbol, String] Path to numeric value
      # @param amount [Numeric] Amount to decrement by (default 1)
      # @return [self] For chaining
      #
      # @example
      #   json.decrement(:age)  # Decrement by 1
      #   json.decrement(:score, 5)  # Decrement by 5
      def decrement(path, amount = 1)
        increment(path, -amount)
      end
      alias decr decrement

      # Multiply numeric value at path
      #
      # @param path [Symbol, String] Path to numeric value
      # @param factor [Numeric] Factor to multiply by
      # @return [self] For chaining
      #
      # @example
      #   json.multiply(:score, 2)  # Double the score
      def multiply(path, factor)
        path = normalize_path(path)
        @client.json_nummultby(@key, path, factor)
        self
      end
      alias mult multiply

      # Append values to array at path
      #
      # @param path [Symbol, String] Path to array
      # @param values [Array] Values to append
      # @return [self] For chaining
      #
      # @example
      #   json.append(:tags, "ruby", "redis")
      def append(path, *values)
        path = normalize_path(path)
        @client.json_arrappend(@key, path, *values)
        self
      end

      # Get array length at path
      #
      # @param path [Symbol, String] Path to array
      # @return [Integer] Array length
      #
      # @example
      #   json.array_length(:tags)  # => 3
      def array_length(path)
        path = normalize_path(path)
        result = @client.json_arrlen(@key, path)
        result.is_a?(Array) && result.size == 1 ? result[0] : result
      end
      alias arrlen array_length

      # Find index of value in array
      #
      # @param path [Symbol, String] Path to array
      # @param value [Object] Value to find
      # @return [Integer] Index of value (-1 if not found)
      #
      # @example
      #   json.array_index(:tags, "ruby")  # => 0
      def array_index(path, value)
        path = normalize_path(path)
        result = @client.json_arrindex(@key, path, value)
        result.is_a?(Array) && result.size == 1 ? result[0] : result
      end
      alias arrindex array_index

      # Insert values into array at index
      #
      # @param path [Symbol, String] Path to array
      # @param index [Integer] Index to insert at
      # @param values [Array] Values to insert
      # @return [self] For chaining
      #
      # @example
      #   json.array_insert(:tags, 1, "new_tag")
      def array_insert(path, index, *values)
        path = normalize_path(path)
        @client.json_arrinsert(@key, path, index, *values)
        self
      end
      alias arrinsert array_insert

      # Pop value from array
      #
      # @param path [Symbol, String] Path to array
      # @param index [Integer] Index to pop from (default -1 = last)
      # @return [Object] Popped value
      #
      # @example
      #   json.array_pop(:tags)  # Pop last element
      #   json.array_pop(:tags, 0)  # Pop first element
      def array_pop(path, index = -1)
        path = normalize_path(path)
        result = @client.json_arrpop(@key, path, index)
        result.is_a?(Array) && result.size == 1 ? result[0] : result
      end
      alias arrpop array_pop

      # Trim array to specified range
      #
      # @param path [Symbol, String] Path to array
      # @param range [Range, Array] Range or [start, stop]
      # @return [self] For chaining
      #
      # @example
      #   json.array_trim(:tags, 0..2)  # Keep first 3 elements
      #   json.array_trim(:tags, [0, 2])  # Same as above
      def array_trim(path, range)
        path = normalize_path(path)
        start, stop = range.is_a?(Range) ? [range.begin, range.end] : range
        @client.json_arrtrim(@key, path, start, stop)
        self
      end
      alias arrtrim array_trim

      # Get object keys at path
      #
      # @param path [Symbol, String] Path to object (default root)
      # @return [Array<String>] Object keys
      #
      # @example
      #   json.keys  # => ["name", "age"]
      #   json.keys(:address)  # => ["street", "city"]
      def keys(path = "$")
        path = normalize_path(path)
        result = @client.json_objkeys(@key, path)
        result.is_a?(Array) && result.size == 1 ? result[0] : result
      end

      # Get object length (number of keys) at path
      #
      # @param path [Symbol, String] Path to object (default root)
      # @return [Integer] Number of keys
      #
      # @example
      #   json.object_length  # => 2
      #   json.object_length(:address)  # => 3
      def object_length(path = "$")
        path = normalize_path(path)
        result = @client.json_objlen(@key, path)
        result.is_a?(Array) && result.size == 1 ? result[0] : result
      end
      alias objlen object_length

      # Clear container value (array/object) at path
      #
      # @param path [Symbol, String] Path (default root)
      # @return [self] For chaining
      #
      # @example
      #   json.clear(:tags)  # Clear array
      #   json.clear(:address)  # Clear object
      def clear(path = "$")
        path = normalize_path(path)
        @client.json_clear(@key, path)
        self
      end

      # Toggle boolean value at path
      #
      # @param path [Symbol, String] Path to boolean value
      # @return [Boolean] New value
      #
      # @example
      #   json.toggle(:active)  # => false
      def toggle(path)
        path = normalize_path(path)
        result = @client.json_toggle(@key, path)
        result.is_a?(Array) && result.size == 1 ? result[0] : result
      end

      # Check if key exists
      #
      # @return [Boolean] True if key exists
      #
      # @example
      #   json.exists?  # => true
      def exists?
        @client.exists(@key).positive?
      end

      private

      # Dispatch the set operation based on arguments
      def json_set_dispatch(args, kwargs, nx:, xx:)
        if args.empty? && !kwargs.empty?
          # set(name: "Alice", age: 30)
          @client.json_set(@key, "$", kwargs)
        elsif args.size == 1 && args[0].is_a?(Hash)
          # set({name: "Alice", age: 30})
          @client.json_set(@key, "$", args[0])
        elsif args.size >= 2
          # set(:name, "Alice") or set("$.age", 30, nx: true)
          json_set_at_path(args[0], args[1], nx: nx, xx: xx)
        end
      end

      # Set a value at a specific path with optional flags
      def json_set_at_path(path, value, nx:, xx:)
        path = normalize_path(path)
        if nx
          @client.json_set(@key, path, value, nx: true)
        elsif xx
          @client.json_set(@key, path, value, xx: true)
        else
          @client.json_set(@key, path, value)
        end
      end

      # Fetch the root document, unwrapping single-element arrays
      def fetch_root
        result = @client.json_get(@key)
        unwrap_single(result)
      end

      # Fetch a single path, unwrapping single-element arrays
      def fetch_single_path(path)
        path = normalize_path(path)
        result = @client.json_get(@key, path)
        unwrap_single(result)
      end

      # Unwrap single-element array results
      def unwrap_single(result)
        result.is_a?(Array) && result.size == 1 ? result[0] : result
      end

      # Normalize path to JSONPath format
      #
      # @param path [Symbol, String] Path
      # @return [String] Normalized JSONPath
      def normalize_path(path)
        return path if path.is_a?(String) && path.start_with?("$")

        path_str = path.to_s
        return path_str if path_str.start_with?("$")

        "$.#{path_str}"
      end
    end
  end
end
