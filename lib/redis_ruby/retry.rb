# frozen_string_literal: true

module RR
  # Retry policy for automatic command retry on transient failures.
  #
  # Inspired by redis-py's Retry class. Provides configurable retry
  # behavior with pluggable backoff strategies.
  #
  # @example Basic usage
  #   retry_policy = RR::Retry.new(retries: 3)
  #   retry_policy.call { client.get("key") }
  #
  # @example With exponential backoff
  #   retry_policy = RR::Retry.new(
  #     retries: 5,
  #     backoff: RR::ExponentialWithJitterBackoff.new(base: 0.1, cap: 2.0)
  #   )
  #
  # @example With callback
  #   retry_policy = RR::Retry.new(
  #     retries: 3,
  #     on_retry: ->(error, attempt) { logger.warn("Retry #{attempt}: #{error}") }
  #   )
  #
  class Retry
    # Default errors that trigger a retry
    DEFAULT_SUPPORTED_ERRORS = [ConnectionError, TimeoutError].freeze

    # @param retries [Integer] Maximum number of retry attempts (0 = no retries)
    # @param backoff [#compute] Backoff strategy (default: ExponentialWithJitterBackoff)
    # @param supported_errors [Array<Class>] Error classes that trigger retries
    # @param on_retry [Proc, nil] Callback invoked before each retry (error, attempt)
    def initialize(retries: 3, backoff: nil, supported_errors: DEFAULT_SUPPORTED_ERRORS, on_retry: nil)
      @retries = retries
      @backoff = backoff || ExponentialWithJitterBackoff.new
      @supported_errors = supported_errors
      @on_retry = on_retry
    end

    # Execute a block with automatic retry on supported errors.
    #
    # @yield The operation to execute
    # @return [Object] Result of the block
    # @raise [Error] The last error if all retries are exhausted
    def call
      attempts = 0
      begin
        yield
      rescue *@supported_errors => e
        attempts += 1
        raise if attempts > @retries

        delay = @backoff.compute(attempts)
        @on_retry&.call(e, attempts)
        sleep(delay) if delay.positive?
        retry
      end
    end
  end

  # No backoff - retry immediately.
  #
  # @example
  #   backoff = RR::NoBackoff.new
  #   backoff.compute(1) # => 0
  class NoBackoff
    # @param _failures [Integer] Number of consecutive failures (ignored)
    # @return [Integer] Always returns 0
    def compute(_failures)
      0
    end
  end

  # Constant backoff - always wait the same duration.
  #
  # @example
  #   backoff = RR::ConstantBackoff.new(0.5)
  #   backoff.compute(1) # => 0.5
  #   backoff.compute(5) # => 0.5
  class ConstantBackoff
    # @param delay [Float] Fixed delay in seconds
    def initialize(delay)
      @delay = delay
    end

    # @param _failures [Integer] Number of consecutive failures (ignored)
    # @return [Float] The fixed delay
    def compute(_failures)
      @delay
    end
  end

  # Exponential backoff without jitter.
  #
  # Delay = min(cap, base * 2^(failures-1))
  #
  # @example
  #   backoff = RR::ExponentialBackoff.new(base: 0.1, cap: 10.0)
  #   backoff.compute(1) # => 0.1
  #   backoff.compute(2) # => 0.2
  #   backoff.compute(3) # => 0.4
  class ExponentialBackoff
    # @param base [Float] Base delay in seconds
    # @param cap [Float] Maximum delay cap in seconds
    def initialize(base: 0.1, cap: 10.0)
      @base = base
      @cap = cap
    end

    # @param failures [Integer] Number of consecutive failures
    # @return [Float] Delay in seconds
    def compute(failures)
      delay = @base * (2**(failures - 1))
      [delay, @cap].min
    end
  end

  # Exponential backoff with full jitter (recommended).
  #
  # Delay = random(0, min(cap, base * 2^(failures-1)))
  #
  # This is the recommended strategy per AWS architecture blog.
  # Full jitter provides the best spread across retrying clients.
  #
  # @example
  #   backoff = RR::ExponentialWithJitterBackoff.new(base: 0.1, cap: 10.0)
  class ExponentialWithJitterBackoff
    # @param base [Float] Base delay in seconds
    # @param cap [Float] Maximum delay cap in seconds
    def initialize(base: 0.1, cap: 10.0)
      @base = base
      @cap = cap
    end

    # @param failures [Integer] Number of consecutive failures
    # @return [Float] Random delay in [0, min(cap, base * 2^(failures-1))]
    def compute(failures)
      delay = @base * (2**(failures - 1))
      delay = [delay, @cap].min
      rand * delay
    end
  end

  # Equal jitter backoff.
  #
  # Delay = delay/2 + random(0, delay/2)
  # where delay = min(cap, base * 2^(failures-1))
  #
  # Provides a guaranteed minimum wait time of half the computed delay.
  #
  # @example
  #   backoff = RR::EqualJitterBackoff.new(base: 0.1, cap: 10.0)
  class EqualJitterBackoff
    # @param base [Float] Base delay in seconds
    # @param cap [Float] Maximum delay cap in seconds
    def initialize(base: 0.1, cap: 10.0)
      @base = base
      @cap = cap
    end

    # @param failures [Integer] Number of consecutive failures
    # @return [Float] Delay with guaranteed minimum of half the base delay
    def compute(failures)
      delay = @base * (2**(failures - 1))
      delay = [delay, @cap].min
      half = delay / 2.0
      half + (rand * half)
    end
  end
end
