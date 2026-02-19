# frozen_string_literal: true

module RR
  # Handles errors that occur during callback execution.
  #
  # Provides configurable error handling strategies to control how callback
  # errors are handled. This prevents one failing callback from breaking
  # the entire system.
  #
  # Strategies:
  # - :ignore - Silently ignore errors (not recommended for production)
  # - :log - Log errors using warn (default, recommended)
  # - :raise - Re-raise errors (useful for testing)
  #
  # @example Basic usage
  #   handler = RR::CallbackErrorHandler.new(strategy: :log)
  #   handler.handle_error(StandardError.new("Oops"), context: "connected callback")
  #
  # @example Custom logger
  #   handler = RR::CallbackErrorHandler.new(strategy: :log, logger: Rails.logger)
  #   handler.handle_error(error, context: "pool exhausted callback")
  #
  class CallbackErrorHandler
    # Available error handling strategies
    STRATEGIES = %i[ignore log raise].freeze

    # Default strategy
    DEFAULT_STRATEGY = :log

    attr_reader :strategy, :logger

    # Initialize a new callback error handler.
    #
    # @param strategy [Symbol] Error handling strategy (:ignore, :log, :raise)
    # @param logger [Logger, nil] Logger to use for :log strategy (defaults to warn)
    # @raise [ArgumentError] If strategy is invalid
    def initialize(strategy: DEFAULT_STRATEGY, logger: nil)
      unless STRATEGIES.include?(strategy)
        raise ArgumentError, "Invalid strategy: #{strategy}. Valid strategies: #{STRATEGIES.join(", ")}"
      end

      @strategy = strategy
      @logger = logger
    end

    # Handle an error that occurred during callback execution.
    #
    # @param error [Exception] The error that occurred
    # @param context [String, nil] Context information (e.g., event type, callback name)
    # @return [void]
    # @raise [Exception] If strategy is :raise, re-raises the error
    def handle_error(error, context: nil)
      case @strategy
      when :ignore
        # Do nothing
        nil
      when :log
        log_error(error, context)
      when :raise
        raise error
      end
    end

    # Execute a block with error handling.
    #
    # @param context [String, nil] Context information
    # @yield Block to execute
    # @return [Object, nil] Result of the block, or nil if error occurred
    def call(context: nil)
      yield
    rescue StandardError => e
      handle_error(e, context: context)
      nil
    end

    private

    # Log an error with context.
    #
    # @param error [Exception] The error to log
    # @param context [String, nil] Context information
    def log_error(error, context)
      message = if context
                  "Error in #{context}: #{error.class.name}: #{error.message}"
                else
                  "Callback error: #{error.class.name}: #{error.message}"
                end

      if @logger
        @logger.warn(message)
        @logger.debug(error.backtrace.join("\n")) if @logger.respond_to?(:debug)
      else
        warn message
      end
    end
  end
end
