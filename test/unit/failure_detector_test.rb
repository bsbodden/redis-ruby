# frozen_string_literal: true

require_relative "unit_test_helper"

class FailureDetectorTest < Minitest::Test
  # ============================================================
  # Initialization
  # ============================================================

  def test_initialize_with_defaults
    detector = RR::FailureDetector.new

    assert_equal 2.0, detector.window_size
    assert_equal 1000, detector.min_failures
    assert_equal 0.10, detector.failure_rate_threshold
  end

  def test_initialize_with_custom_values
    detector = RR::FailureDetector.new(
      window_size: 5.0,
      min_failures: 500,
      failure_rate_threshold: 0.25
    )

    assert_equal 5.0, detector.window_size
    assert_equal 500, detector.min_failures
    assert_equal 0.25, detector.failure_rate_threshold
  end

  def test_initialize_raises_on_non_positive_window_size
    assert_raises(ArgumentError) { RR::FailureDetector.new(window_size: 0) }
    assert_raises(ArgumentError) { RR::FailureDetector.new(window_size: -1) }
  end

  def test_initialize_raises_on_non_positive_min_failures
    assert_raises(ArgumentError) { RR::FailureDetector.new(min_failures: 0) }
    assert_raises(ArgumentError) { RR::FailureDetector.new(min_failures: -1) }
  end

  def test_initialize_raises_on_invalid_failure_rate_threshold
    assert_raises(ArgumentError) { RR::FailureDetector.new(failure_rate_threshold: -0.1) }
    assert_raises(ArgumentError) { RR::FailureDetector.new(failure_rate_threshold: 1.1) }
  end

  # ============================================================
  # record_failure / record_success
  # ============================================================

  def test_record_failure_increments_failure_count
    detector = RR::FailureDetector.new
    3.times { detector.record_failure }
    stats = detector.stats

    assert_equal 3, stats[:total_failures]
  end

  def test_record_success_increments_success_count
    detector = RR::FailureDetector.new
    5.times { detector.record_success }
    stats = detector.stats

    assert_equal 5, stats[:total_successes]
  end

  # ============================================================
  # failure_threshold_exceeded?
  # ============================================================

  def test_threshold_not_exceeded_with_no_data
    detector = RR::FailureDetector.new

    refute detector.failure_threshold_exceeded?
  end

  def test_threshold_not_exceeded_below_min_failures
    detector = RR::FailureDetector.new(min_failures: 10)
    5.times { detector.record_failure }

    refute detector.failure_threshold_exceeded?
  end

  def test_threshold_exceeded_when_both_conditions_met
    detector = RR::FailureDetector.new(min_failures: 3, failure_rate_threshold: 0.5)
    5.times { detector.record_failure }
    2.times { detector.record_success }

    assert detector.failure_threshold_exceeded?
  end

  def test_threshold_not_exceeded_when_rate_below_threshold
    detector = RR::FailureDetector.new(min_failures: 3, failure_rate_threshold: 0.5)
    3.times { detector.record_failure }
    10.times { detector.record_success }

    refute detector.failure_threshold_exceeded?
  end

  # ============================================================
  # Sliding window / pruning
  # ============================================================

  def test_old_entries_pruned_outside_window
    detector = RR::FailureDetector.new(window_size: 0.05, min_failures: 1,
                                       failure_rate_threshold: 0.5)
    3.times { detector.record_failure }

    # Entries should still be in window
    assert_equal 3, detector.stats[:total_failures]

    # Wait for entries to expire
    sleep 0.06

    # After pruning, entries should be gone
    assert_equal 0, detector.stats[:total_failures]
  end

  def test_pruned_failures_no_longer_trigger_threshold
    detector = RR::FailureDetector.new(window_size: 0.05, min_failures: 2,
                                       failure_rate_threshold: 0.5)
    3.times { detector.record_failure }

    assert detector.failure_threshold_exceeded?

    sleep 0.06

    refute detector.failure_threshold_exceeded?
  end

  # ============================================================
  # reset!
  # ============================================================

  def test_reset_clears_all_data
    detector = RR::FailureDetector.new
    5.times { detector.record_failure }
    5.times { detector.record_success }
    detector.reset!

    stats = detector.stats

    assert_equal 0, stats[:total_failures]
    assert_equal 0, stats[:total_successes]
    assert_equal 0.0, stats[:failure_rate]
  end

  # ============================================================
  # stats
  # ============================================================

  def test_stats_returns_correct_failure_rate
    detector = RR::FailureDetector.new(min_failures: 1)
    3.times { detector.record_failure }
    7.times { detector.record_success }

    stats = detector.stats

    assert_in_delta 0.3, stats[:failure_rate], 0.001
  end

  def test_stats_returns_zero_rate_when_no_operations
    detector = RR::FailureDetector.new
    stats = detector.stats

    assert_equal 0.0, stats[:failure_rate]
  end

  def test_stats_includes_configuration
    detector = RR::FailureDetector.new(window_size: 3.0, min_failures: 50,
                                       failure_rate_threshold: 0.2)
    stats = detector.stats

    assert_equal 3.0, stats[:window_size]
    assert_equal 50, stats[:min_failures]
    assert_equal 0.2, stats[:failure_rate_threshold]
  end
end
