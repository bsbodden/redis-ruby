# frozen_string_literal: true

require "securerandom"

module RR
  # Distributed lock implementation using Redis
  #
  # Provides a reliable distributed lock with automatic expiration,
  # ownership verification, and lock extension capabilities.
  #
  # Uses Lua scripts for atomic operations to ensure correctness.
  #
  # @example Basic usage
  #   lock = RR::Lock.new(client, "my-resource")
  #   if lock.acquire
  #     begin
  #       # Critical section
  #     ensure
  #       lock.release
  #     end
  #   end
  #
  # @example Block syntax (recommended)
  #   lock = RR::Lock.new(client, "my-resource")
  #   lock.synchronize do
  #     # Critical section - lock automatically released
  #   end
  #
  # @example With timeout and blocking
  #   lock = RR::Lock.new(client, "my-resource", timeout: 30)
  #   if lock.acquire(blocking: true, blocking_timeout: 5)
  #     # Got the lock within 5 seconds
  #   end
  #
  # @example Extending lock duration
  #   lock.acquire
  #   # ... long running operation ...
  #   lock.extend(additional_time: 10)  # Add 10 more seconds
  #
  class Lock
    class LockError < Error; end
    class LockNotOwnedError < LockError; end
    class LockAcquireError < LockError; end

    # Default lock timeout in seconds
    DEFAULT_TIMEOUT = 10.0

    # Default sleep interval when polling for lock
    DEFAULT_SLEEP = 0.1

    # Lua script to release lock only if we own it
    RELEASE_SCRIPT = <<~LUA
      if redis.call("GET", KEYS[1]) == ARGV[1] then
        return redis.call("DEL", KEYS[1])
      else
        return 0
      end
    LUA

    # Lua script to extend lock only if we own it
    EXTEND_SCRIPT = <<~LUA
      if redis.call("GET", KEYS[1]) == ARGV[1] then
        return redis.call("PEXPIRE", KEYS[1], ARGV[2])
      else
        return 0
      end
    LUA

    # Lua script to reacquire (reset TTL) only if we own it
    REACQUIRE_SCRIPT = <<~LUA
      if redis.call("GET", KEYS[1]) == ARGV[1] then
        return redis.call("PEXPIRE", KEYS[1], ARGV[2])
      else
        return 0
      end
    LUA

    attr_reader :name, :timeout, :sleep_interval, :token

    # Initialize a new distributed lock
    #
    # @param [RR::Client] Redis client instance
    # @param name [String] Lock name (key in Redis)
    # @param timeout [Float] Lock expiration time in seconds (default: 10)
    # @param sleep [Float] Sleep interval when polling for lock (default: 0.1)
    # @param thread_local [Boolean] Use thread-local token storage (default: true)
    def initialize(client, name, timeout: DEFAULT_TIMEOUT, sleep: DEFAULT_SLEEP, thread_local: true)
      @client = client
      @name = "lock:#{name}"
      @timeout = timeout
      @sleep_interval = sleep
      @thread_local = thread_local
      @token = nil
      @local_tokens = {}.compare_by_identity if thread_local

      # Register Lua scripts
      @release_script = @client.register_script(RELEASE_SCRIPT)
      @extend_script = @client.register_script(EXTEND_SCRIPT)
      @reacquire_script = @client.register_script(REACQUIRE_SCRIPT)
    end

    # Attempt to acquire the lock
    #
    # @param blocking [Boolean] Whether to block waiting for the lock (default: false)
    # @param blocking_timeout [Float, nil] Maximum time to wait for lock (nil = wait forever)
    # @param token [String, nil] Custom token for lock ownership (default: auto-generated)
    # @return [Boolean, String] true/token if acquired, false if not
    def acquire(blocking: false, blocking_timeout: nil, token: nil)
      token ||= generate_token
      timeout_ms = (@timeout * 1000).to_i

      if blocking
        acquire_with_blocking(token, timeout_ms, blocking_timeout)
      else
        acquire_once(token, timeout_ms)
      end
    end

    # Release the lock
    #
    # Only releases if the current client owns the lock.
    #
    # @return [Boolean] true if released, false if not owned
    # @raise [LockNotOwnedError] if raise_on_error and lock not owned
    def release
      token = current_token
      return false unless token

      result = @release_script.call(keys: [@name], argv: [token])
      released = result == 1

      clear_token if released
      released
    end

    # Extend the lock's TTL
    #
    # @param additional_time [Float] Seconds to add to current TTL
    # @param replace_ttl [Boolean] If true, set TTL to additional_time instead of adding
    # @return [Boolean] true if extended, false if not owned
    # @raise [LockNotOwnedError] if lock not owned
    def extend(additional_time: nil, replace_ttl: false)
      token = current_token
      raise LockNotOwnedError, "Cannot extend a lock that is not owned" unless token

      new_timeout = replace_ttl ? additional_time : (additional_time || @timeout)

      timeout_ms = (new_timeout * 1000).to_i
      result = @extend_script.call(keys: [@name], argv: [token, timeout_ms])
      result == 1
    end

    # Reacquire the lock (reset TTL to original timeout)
    #
    # Useful for long-running operations that need to periodically
    # refresh the lock to prevent expiration.
    #
    # @return [Boolean] true if reacquired, false if not owned
    # @raise [LockNotOwnedError] if lock not owned
    def reacquire
      token = current_token
      raise LockNotOwnedError, "Cannot reacquire a lock that is not owned" unless token

      timeout_ms = (@timeout * 1000).to_i
      result = @reacquire_script.call(keys: [@name], argv: [token, timeout_ms])
      result == 1
    end

    # Check if the current client owns the lock
    #
    # @return [Boolean] true if owned
    def owned?
      token = current_token
      return false unless token

      @client.get(@name) == token
    end

    # Check if the lock is currently held (by anyone)
    #
    # @return [Boolean] true if locked
    def locked?
      @client.exists(@name) == 1
    end

    # Get the remaining TTL of the lock
    #
    # @return [Float, nil] TTL in seconds, or nil if not locked
    def ttl
      pttl = @client.pttl(@name)
      return nil if pttl.negative?

      pttl / 1000.0
    end

    # Execute a block while holding the lock
    #
    # @param blocking [Boolean] Whether to block waiting for the lock
    # @param blocking_timeout [Float, nil] Maximum time to wait for lock
    # @yield Block to execute while holding the lock
    # @return [Object] Result of the block
    # @raise [LockAcquireError] if lock cannot be acquired
    def synchronize(blocking: true, blocking_timeout: nil)
      acquired = acquire(blocking: blocking, blocking_timeout: blocking_timeout)
      raise LockAcquireError, "Failed to acquire lock: #{@name}" unless acquired

      begin
        yield
      ensure
        release
      end
    end

    private

    # Generate a unique token for lock ownership
    def generate_token
      SecureRandom.uuid
    end

    # Get the current token (thread-local or instance)
    def current_token
      if @thread_local
        @local_tokens[Thread.current]
      else
        @token
      end
    end

    # Store the token
    def store_token(token)
      if @thread_local
        @local_tokens[Thread.current] = token
      else
        @token = token
      end
    end

    # Clear the stored token
    def clear_token
      if @thread_local
        @local_tokens.delete(Thread.current)
      else
        @token = nil
      end
    end

    # Try to acquire the lock once
    def acquire_once(token, timeout_ms)
      # SET key token NX PX timeout
      result = @client.set(@name, token, nx: true, px: timeout_ms)
      if result
        store_token(token)
        true
      else
        false
      end
    end

    # Acquire with blocking/polling
    def acquire_with_blocking(token, timeout_ms, blocking_timeout)
      deadline = blocking_timeout ? Time.now + blocking_timeout : nil

      loop do
        return true if acquire_once(token, timeout_ms)

        # Check if we've exceeded the blocking timeout
        return false if deadline && Time.now >= deadline

        # Sleep before retrying
        sleep(@sleep_interval)
      end
    end
  end
end
