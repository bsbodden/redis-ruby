# frozen_string_literal: true

require "digest/sha1"

module RedisRuby
  # Cached script object for efficient Lua script execution
  #
  # Created via Client#register_script. Automatically tries EVALSHA first
  # and falls back to EVAL if the script is not cached on the server.
  #
  # @example
  #   incr_script = redis.register_script("return redis.call('INCR', KEYS[1])")
  #   incr_script.call(keys: ["counter"])  # Uses EVALSHA, falls back to EVAL
  #   incr_script.call(keys: ["counter"])  # Uses EVALSHA (now cached)
  #
  class Script
    attr_reader :source, :sha

    # @param source [String] Lua script source code
    # @param client [Client] Redis client instance
    def initialize(source, client)
      @source = source
      @sha = Digest::SHA1.hexdigest(source)
      @client = client
    end

    # Execute the script
    #
    # Tries EVALSHA first, falls back to EVAL on NOSCRIPT error.
    #
    # @param keys [Array<String>] Key names (KEYS array in Lua)
    # @param args [Array] Arguments (ARGV array in Lua)
    # @return [Object] Script return value
    def call(keys: [], args: [])
      @client.evalsha(@sha, keys.size, *keys, *args)
    rescue CommandError => e
      raise unless e.message.include?("NOSCRIPT")

      @client.eval(@source, keys.size, *keys, *args)
    end
  end
end
