# frozen_string_literal: true

module RR
  # Production-ready failure detector with sliding window for Active-Active clients.
  #
  # Tracks failures and successes over a sliding time window to determine if a
  # failover should be triggered. Unlike a circuit breaker that uses consecutive
  # failures, this detector calculates the failure rate over a time window, making
  # it more suitable for distributed systems where occasional failures are expected.
  #
  # The detector uses a sliding window approach:
  # - Records timestamps of all failures and successes
  # - Automatically prunes entries outside the window
  # - Calculates failure rate as: failures / (failures + successes)
  # - Triggers failover when both minimum failures and failure rate thresholds are exceeded
  #
  # Thread-safe using Mutex for synchronization. Uses monotonic time for accurate
  # window tracking that is not affected by system clock changes.
  #
  # Inspired by redis-py's failure detector implementation, adapted to idiomatic Ruby.
  #
  # @example Basic usage
  #   detector = RR::FailureDetector.new(
  #     window_size: 2.0,              # 2 second sliding window
  #     min_failures: 1000,            # Need at least 1000 failures
  #     failure_rate_threshold: 0.10   # 10% failure rate triggers failover
  #   )
  #
  #   # Record operations
  #   detector.record_failure
  #   detector.record_success
  #
  #   # Check if should failover
  #   if detector.failure_threshold_exceeded?
  #     puts "Failure threshold exceeded, triggering failover"
  #     failover_to_next_region
  #   end
  #
  # @example Monitoring statistics
  #   stats = detector.stats
  #   puts "Failures: #{stats[:total_failures]}"
  #   puts "Successes: #{stats[:total_successes]}"
  #   puts "Failure rate: #{(stats[:failure_rate] * 100).round(2)}%"
  #
  # @example Resetting after failover
  #   detector.reset!  # Clear all recorded data after failover
  #
  class FailureDetector
    # Default sliding window size in seconds
    DEFAULT_WINDOW_SIZE = 2.0

    # Default minimum failures required to trigger failover
    DEFAULT_MIN_FAILURES = 1000

    # Default failure rate threshold (10%)
    DEFAULT_FAILURE_RATE_THRESHOLD = 0.10

    attr_reader :window_size, :min_failures, :failure_rate_threshold

    # Initialize a new failure detector.
    #
    # @param window_size [Numeric] Duration of the sliding window in seconds (default: 2.0)
    # @param min_failures [Integer] Minimum number of failures required to trigger
    #   failover, prevents triggering on low traffic (default: 1000)
    # @param failure_rate_threshold [Numeric] Failure rate threshold (0.0 to 1.0)
    #   that triggers failover (default: 0.10 for 10%)
    # @raise [ArgumentError] if parameters are invalid
    def initialize(window_size: DEFAULT_WINDOW_SIZE,
                   min_failures: DEFAULT_MIN_FAILURES,
                   failure_rate_threshold: DEFAULT_FAILURE_RATE_THRESHOLD)
      raise ArgumentError, "window_size must be positive" unless window_size.positive?
      raise ArgumentError, "min_failures must be positive" unless min_failures.positive?
      unless failure_rate_threshold.between?(0.0, 1.0)
        raise ArgumentError, "failure_rate_threshold must be between 0.0 and 1.0"
      end

      @mutex = Mutex.new
      @window_size = window_size
      @min_failures = min_failures
      @failure_rate_threshold = failure_rate_threshold

      # Arrays to store timestamps of failures and successes
      @failure_timestamps = []
      @success_timestamps = []
    end

    # Record a failure.
    #
    # Adds the current timestamp to the failure list. Old entries outside
    # the sliding window are automatically pruned.
    def record_failure
      @mutex.synchronize do
        now = monotonic_time
        @failure_timestamps << now
        prune_old_entries(now)
      end
    end

    # Record a success.
    #
    # Adds the current timestamp to the success list. Old entries outside
    # the sliding window are automatically pruned.
    def record_success
      @mutex.synchronize do
        now = monotonic_time
        @success_timestamps << now
        prune_old_entries(now)
      end
    end

    # Check if failure threshold has been exceeded.
    #
    # Returns true if both conditions are met:
    # 1. Number of failures in window >= min_failures
    # 2. Failure rate >= failure_rate_threshold
    #
    # @return [Boolean] true if failover should be triggered
    def failure_threshold_exceeded?
      @mutex.synchronize do
        now = monotonic_time
        prune_old_entries(now)

        failures_in_window = @failure_timestamps.size
        successes_in_window = @success_timestamps.size
        total_operations = failures_in_window + successes_in_window

        # Need minimum failures and minimum total operations
        return false if failures_in_window < @min_failures
        return false if total_operations.zero?

        failure_rate = failures_in_window.to_f / total_operations
        failure_rate >= @failure_rate_threshold
      end
    end

    # Reset all recorded failures and successes.
    #
    # Clears all timestamps. Typically called after a successful failover
    # to start fresh with the new region.
    def reset!
      @mutex.synchronize do
        @failure_timestamps.clear
        @success_timestamps.clear
      end
    end

    # Get current statistics.
    #
    # Returns a hash with current failure and success counts within the
    # sliding window, along with the calculated failure rate.
    #
    # @return [Hash] Statistics hash with keys:
    #   - :total_failures [Integer] Number of failures in current window
    #   - :total_successes [Integer] Number of successes in current window
    #   - :failure_rate [Float] Current failure rate (0.0 to 1.0)
    #   - :window_size [Float] Configured window size in seconds
    #   - :min_failures [Integer] Configured minimum failures threshold
    #   - :failure_rate_threshold [Float] Configured failure rate threshold
    def stats
      @mutex.synchronize do
        now = monotonic_time
        prune_old_entries(now)

        failures = @failure_timestamps.size
        successes = @success_timestamps.size
        total = failures + successes

        {
          total_failures: failures,
          total_successes: successes,
          failure_rate: total.zero? ? 0.0 : failures.to_f / total,
          window_size: @window_size,
          min_failures: @min_failures,
          failure_rate_threshold: @failure_rate_threshold,
        }
      end
    end

    private

    # Prune entries outside the sliding window.
    #
    # Removes timestamps that are older than window_size seconds from the
    # current time. Since timestamps are appended in monotonic order, the
    # arrays are sorted — we use binary search to find the cutoff index
    # in O(log n) instead of scanning the entire array with delete_if O(n).
    #
    # Must be called within a mutex synchronize block.
    #
    # @param now [Float] Current monotonic time
    def prune_old_entries(now)
      cutoff_time = now - @window_size
      prune_sorted!(@failure_timestamps, cutoff_time)
      prune_sorted!(@success_timestamps, cutoff_time)
    end

    # Remove all entries before cutoff_time from a sorted array.
    #
    # @param timestamps [Array<Float>] Sorted timestamps (monotonic order)
    # @param cutoff_time [Float] Entries before this time are removed
    def prune_sorted!(timestamps, cutoff_time)
      return if timestamps.empty? || timestamps.first >= cutoff_time

      if timestamps.last < cutoff_time
        timestamps.clear
        return
      end

      idx = timestamps.bsearch_index { |t| t >= cutoff_time }
      timestamps.shift(idx) if idx
    end

    # Get monotonic time in seconds.
    #
    # Uses Process.clock_gettime with CLOCK_MONOTONIC to get time that is
    # not affected by system clock changes (NTP adjustments, DST, etc.).
    # This ensures accurate window tracking.
    #
    # @return [Float] Monotonic time in seconds
    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
