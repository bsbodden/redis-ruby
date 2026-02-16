# frozen_string_literal: true

require_relative "../unit_test_helper"

# Comprehensive branch coverage tests for RR::Commands::TimeSeries
class TimeSeriesBranchTest < Minitest::Test
  class MockClient
    include RR::Commands::TimeSeries

    attr_reader :last_command

    def call(*args)
      @last_command = args
      "OK"
    end

    def call_1arg(cmd, a1)
      @last_command = [cmd, a1]
      mock_ts_return(cmd)
    end

    def call_2args(cmd, a1, a2)
      @last_command = [cmd, a1, a2]
      "OK"
    end

    def call_3args(cmd, a1, a2, a3)
      @last_command = [cmd, a1, a2, a3]
      "OK"
    end

    private

    def mock_ts_return(cmd)
      case cmd
      when "TS.GET" then [1_640_000_000, 23.5]
      when "TS.INFO" then ["totalSamples", 100, "memoryUsage", 4096]
      else "OK"
      end
    end
  end

  def setup
    @client = MockClient.new
  end

  # ============================================================
  # ts_create - fast path (no options)
  # ============================================================

  def test_ts_create_fast_path
    @client.ts_create("temp:sensor1")

    assert_equal ["TS.CREATE", "temp:sensor1"], @client.last_command
  end

  # ============================================================
  # ts_create - with retention
  # ============================================================

  def test_ts_create_with_retention
    @client.ts_create("temp:sensor1", retention: 86_400_000)

    assert_equal ["TS.CREATE", "temp:sensor1", "RETENTION", 86_400_000], @client.last_command
  end

  # ============================================================
  # ts_create - with encoding
  # ============================================================

  def test_ts_create_with_encoding
    @client.ts_create("temp:sensor1", encoding: "COMPRESSED")

    assert_equal ["TS.CREATE", "temp:sensor1", "ENCODING", "COMPRESSED"], @client.last_command
  end

  # ============================================================
  # ts_create - with chunk_size
  # ============================================================

  def test_ts_create_with_chunk_size
    @client.ts_create("temp:sensor1", chunk_size: 4096)

    assert_equal ["TS.CREATE", "temp:sensor1", "CHUNK_SIZE", 4096], @client.last_command
  end

  # ============================================================
  # ts_create - with duplicate_policy
  # ============================================================

  def test_ts_create_with_duplicate_policy
    @client.ts_create("temp:sensor1", duplicate_policy: "LAST")

    assert_equal ["TS.CREATE", "temp:sensor1", "DUPLICATE_POLICY", "LAST"], @client.last_command
  end

  # ============================================================
  # ts_create - with labels
  # ============================================================

  def test_ts_create_with_labels
    @client.ts_create("temp:sensor1", labels: { sensor: "temp", location: "room1" })

    assert_equal [
      "TS.CREATE", "temp:sensor1", "LABELS", "sensor", "temp", "location", "room1",
    ], @client.last_command
  end

  # ============================================================
  # ts_create - with ignore_max_time_diff only
  # ============================================================

  def test_ts_create_with_ignore_max_time_diff_only
    @client.ts_create("temp:sensor1", ignore_max_time_diff: 1000)

    assert_equal ["TS.CREATE", "temp:sensor1", "IGNORE", 1000], @client.last_command
  end

  # ============================================================
  # ts_create - with ignore_max_val_diff only
  # ============================================================

  def test_ts_create_with_ignore_max_val_diff_only
    @client.ts_create("temp:sensor1", ignore_max_val_diff: 0.5)

    assert_equal ["TS.CREATE", "temp:sensor1", "IGNORE", 0.5], @client.last_command
  end

  # ============================================================
  # ts_create - with both ignore options
  # ============================================================

  def test_ts_create_with_both_ignore_options
    @client.ts_create("temp:sensor1", ignore_max_time_diff: 1000, ignore_max_val_diff: 0.5)

    assert_equal ["TS.CREATE", "temp:sensor1", "IGNORE", 1000, 0.5], @client.last_command
  end

  # ============================================================
  # ts_create - with all options combined
  # ============================================================

  def test_ts_create_all_options
    @client.ts_create("temp:sensor1",
                      retention: 86_400_000,
                      encoding: "COMPRESSED",
                      chunk_size: 4096,
                      duplicate_policy: "LAST",
                      ignore_max_time_diff: 1000,
                      ignore_max_val_diff: 0.5,
                      labels: { sensor: "temp" })
    expected = [
      "TS.CREATE", "temp:sensor1",
      "RETENTION", 86_400_000,
      "ENCODING", "COMPRESSED",
      "CHUNK_SIZE", 4096,
      "DUPLICATE_POLICY", "LAST",
      "IGNORE", 1000, 0.5,
      "LABELS", "sensor", "temp",
    ]

    assert_equal expected, @client.last_command
  end

  # ============================================================
  # ts_del
  # ============================================================

  def test_ts_del
    @client.ts_del("temp:sensor1", 1_000_000, 2_000_000)

    assert_equal ["TS.DEL", "temp:sensor1", 1_000_000, 2_000_000], @client.last_command
  end

  # ============================================================
  # ts_alter - with retention
  # ============================================================

  def test_ts_alter_with_retention
    @client.ts_alter("temp:sensor1", retention: 172_800_000)

    assert_equal ["TS.ALTER", "temp:sensor1", "RETENTION", 172_800_000], @client.last_command
  end

  # ============================================================
  # ts_alter - with chunk_size
  # ============================================================

  def test_ts_alter_with_chunk_size
    @client.ts_alter("temp:sensor1", chunk_size: 8192)

    assert_equal ["TS.ALTER", "temp:sensor1", "CHUNK_SIZE", 8192], @client.last_command
  end

  # ============================================================
  # ts_alter - with duplicate_policy
  # ============================================================

  def test_ts_alter_with_duplicate_policy
    @client.ts_alter("temp:sensor1", duplicate_policy: "FIRST")

    assert_equal ["TS.ALTER", "temp:sensor1", "DUPLICATE_POLICY", "FIRST"], @client.last_command
  end

  # ============================================================
  # ts_alter - with labels
  # ============================================================

  def test_ts_alter_with_labels
    @client.ts_alter("temp:sensor1", labels: { sensor: "humidity" })

    assert_equal ["TS.ALTER", "temp:sensor1", "LABELS", "sensor", "humidity"], @client.last_command
  end

  # ============================================================
  # ts_alter - with ignore_max_time_diff only
  # ============================================================

  def test_ts_alter_with_ignore_max_time_diff_only
    @client.ts_alter("temp:sensor1", ignore_max_time_diff: 2000)

    assert_equal ["TS.ALTER", "temp:sensor1", "IGNORE", 2000], @client.last_command
  end

  # ============================================================
  # ts_alter - with ignore_max_val_diff only
  # ============================================================

  def test_ts_alter_with_ignore_max_val_diff_only
    @client.ts_alter("temp:sensor1", ignore_max_val_diff: 1.0)

    assert_equal ["TS.ALTER", "temp:sensor1", "IGNORE", 1.0], @client.last_command
  end

  # ============================================================
  # ts_alter - with both ignore options
  # ============================================================

  def test_ts_alter_with_both_ignore_options
    @client.ts_alter("temp:sensor1", ignore_max_time_diff: 2000, ignore_max_val_diff: 1.0)

    assert_equal ["TS.ALTER", "temp:sensor1", "IGNORE", 2000, 1.0], @client.last_command
  end

  # ============================================================
  # ts_alter - with all options
  # ============================================================

  def test_ts_alter_all_options
    @client.ts_alter("temp:sensor1",
                     retention: 172_800_000,
                     chunk_size: 8192,
                     duplicate_policy: "FIRST",
                     ignore_max_time_diff: 2000,
                     ignore_max_val_diff: 1.0,
                     labels: { sensor: "humidity", area: "kitchen" })
    expected = [
      "TS.ALTER", "temp:sensor1",
      "RETENTION", 172_800_000,
      "CHUNK_SIZE", 8192,
      "DUPLICATE_POLICY", "FIRST",
      "IGNORE", 2000, 1.0,
      "LABELS", "sensor", "humidity", "area", "kitchen",
    ]

    assert_equal expected, @client.last_command
  end

  # ============================================================
  # ts_alter - no options (just key)
  # ============================================================

  def test_ts_alter_no_options
    @client.ts_alter("temp:sensor1")

    assert_equal ["TS.ALTER", "temp:sensor1"], @client.last_command
  end

  # ============================================================
  # ts_add - fast path (no options)
  # ============================================================

  def test_ts_add_fast_path
    @client.ts_add("temp:sensor1", "*", 23.5)

    assert_equal ["TS.ADD", "temp:sensor1", "*", 23.5], @client.last_command
  end

  # ============================================================
  # ts_add - with specific timestamp
  # ============================================================

  def test_ts_add_with_timestamp
    @client.ts_add("temp:sensor1", 1_640_000_000_000, 23.5)

    assert_equal ["TS.ADD", "temp:sensor1", 1_640_000_000_000, 23.5], @client.last_command
  end

  # ============================================================
  # ts_add - with retention
  # ============================================================

  def test_ts_add_with_retention
    @client.ts_add("temp:sensor1", "*", 23.5, retention: 86_400_000)

    assert_equal [
      "TS.ADD", "temp:sensor1", "*", 23.5, "RETENTION", 86_400_000,
    ], @client.last_command
  end

  # ============================================================
  # ts_add - with encoding
  # ============================================================

  def test_ts_add_with_encoding
    @client.ts_add("temp:sensor1", "*", 23.5, encoding: "UNCOMPRESSED")

    assert_equal [
      "TS.ADD", "temp:sensor1", "*", 23.5, "ENCODING", "UNCOMPRESSED",
    ], @client.last_command
  end

  # ============================================================
  # ts_add - with chunk_size
  # ============================================================

  def test_ts_add_with_chunk_size
    @client.ts_add("temp:sensor1", "*", 23.5, chunk_size: 4096)

    assert_equal [
      "TS.ADD", "temp:sensor1", "*", 23.5, "CHUNK_SIZE", 4096,
    ], @client.last_command
  end

  # ============================================================
  # ts_add - with on_duplicate
  # ============================================================

  def test_ts_add_with_on_duplicate
    @client.ts_add("temp:sensor1", "*", 23.5, on_duplicate: "LAST")

    assert_equal [
      "TS.ADD", "temp:sensor1", "*", 23.5, "ON_DUPLICATE", "LAST",
    ], @client.last_command
  end

  # ============================================================
  # ts_add - with labels
  # ============================================================

  def test_ts_add_with_labels
    @client.ts_add("temp:sensor1", "*", 23.5, labels: { sensor: "temp" })

    assert_equal [
      "TS.ADD", "temp:sensor1", "*", 23.5, "LABELS", "sensor", "temp",
    ], @client.last_command
  end

  # ============================================================
  # ts_add - with ignore options
  # ============================================================

  def test_ts_add_with_ignore_max_time_diff
    @client.ts_add("temp:sensor1", "*", 23.5, ignore_max_time_diff: 500)

    assert_equal [
      "TS.ADD", "temp:sensor1", "*", 23.5, "IGNORE", 500,
    ], @client.last_command
  end

  def test_ts_add_with_ignore_max_val_diff
    @client.ts_add("temp:sensor1", "*", 23.5, ignore_max_val_diff: 0.1)

    assert_equal [
      "TS.ADD", "temp:sensor1", "*", 23.5, "IGNORE", 0.1,
    ], @client.last_command
  end

  def test_ts_add_with_both_ignore_options
    @client.ts_add("temp:sensor1", "*", 23.5, ignore_max_time_diff: 500, ignore_max_val_diff: 0.1)

    assert_equal [
      "TS.ADD", "temp:sensor1", "*", 23.5, "IGNORE", 500, 0.1,
    ], @client.last_command
  end

  # ============================================================
  # ts_add - with all options
  # ============================================================

  def test_ts_add_all_options
    @client.ts_add("temp:sensor1", "*", 23.5,
                   retention: 86_400_000,
                   encoding: "COMPRESSED",
                   chunk_size: 4096,
                   on_duplicate: "LAST",
                   ignore_max_time_diff: 500,
                   ignore_max_val_diff: 0.1,
                   labels: { sensor: "temp", area: "room1" })
    expected = [
      "TS.ADD", "temp:sensor1", "*", 23.5,
      "RETENTION", 86_400_000,
      "ENCODING", "COMPRESSED",
      "CHUNK_SIZE", 4096,
      "ON_DUPLICATE", "LAST",
      "IGNORE", 500, 0.1,
      "LABELS", "sensor", "temp", "area", "room1",
    ]

    assert_equal expected, @client.last_command
  end

  # ============================================================
  # ts_madd
  # ============================================================

  def test_ts_madd
    @client.ts_madd(["temp:1", "*", 23.5], ["temp:2", "*", 24.0], ["temp:3", "*", 22.8])

    assert_equal [
      "TS.MADD", "temp:1", "*", 23.5, "temp:2", "*", 24.0, "temp:3", "*", 22.8,
    ], @client.last_command
  end

  def test_ts_madd_single_sample
    @client.ts_madd(["temp:1", 1_000_000, 23.5])

    assert_equal ["TS.MADD", "temp:1", 1_000_000, 23.5], @client.last_command
  end

  # ============================================================
  # ts_incrby - fast path (no options)
  # ============================================================

  def test_ts_incrby_fast_path
    @client.ts_incrby("temp:sensor1", 1.5)

    assert_equal ["TS.INCRBY", "temp:sensor1", 1.5], @client.last_command
  end

  # ============================================================
  # ts_incrby - with timestamp
  # ============================================================

  def test_ts_incrby_with_timestamp
    @client.ts_incrby("temp:sensor1", 1.5, timestamp: 1_640_000_000_000)

    assert_equal [
      "TS.INCRBY", "temp:sensor1", 1.5, "TIMESTAMP", 1_640_000_000_000,
    ], @client.last_command
  end

  # ============================================================
  # ts_incrby - with retention
  # ============================================================

  def test_ts_incrby_with_retention
    @client.ts_incrby("temp:sensor1", 1.5, retention: 86_400_000)

    assert_equal [
      "TS.INCRBY", "temp:sensor1", 1.5, "RETENTION", 86_400_000,
    ], @client.last_command
  end

  # ============================================================
  # ts_incrby - with labels
  # ============================================================

  def test_ts_incrby_with_labels
    @client.ts_incrby("temp:sensor1", 1.5, labels: { sensor: "temp" })

    assert_equal [
      "TS.INCRBY", "temp:sensor1", 1.5, "LABELS", "sensor", "temp",
    ], @client.last_command
  end

  # ============================================================
  # ts_incrby - with chunk_size
  # ============================================================

  def test_ts_incrby_with_chunk_size
    @client.ts_incrby("temp:sensor1", 1.5, chunk_size: 4096)

    assert_equal [
      "TS.INCRBY", "temp:sensor1", 1.5, "CHUNK_SIZE", 4096,
    ], @client.last_command
  end

  # ============================================================
  # ts_incrby - with ignore options
  # ============================================================

  def test_ts_incrby_with_ignore_max_time_diff
    @client.ts_incrby("temp:sensor1", 1.5, ignore_max_time_diff: 500)

    assert_equal [
      "TS.INCRBY", "temp:sensor1", 1.5, "IGNORE", 500,
    ], @client.last_command
  end

  def test_ts_incrby_with_ignore_max_val_diff
    @client.ts_incrby("temp:sensor1", 1.5, ignore_max_val_diff: 0.1)

    assert_equal [
      "TS.INCRBY", "temp:sensor1", 1.5, "IGNORE", 0.1,
    ], @client.last_command
  end

  def test_ts_incrby_with_both_ignore_options
    @client.ts_incrby("temp:sensor1", 1.5, ignore_max_time_diff: 500, ignore_max_val_diff: 0.1)

    assert_equal [
      "TS.INCRBY", "temp:sensor1", 1.5, "IGNORE", 500, 0.1,
    ], @client.last_command
  end

  # ============================================================
  # ts_incrby - with all options
  # ============================================================

  def test_ts_incrby_all_options
    @client.ts_incrby("temp:sensor1", 1.5,
                      timestamp: 1_640_000_000_000,
                      retention: 86_400_000,
                      chunk_size: 4096,
                      ignore_max_time_diff: 500,
                      ignore_max_val_diff: 0.1,
                      labels: { sensor: "temp" })
    expected = [
      "TS.INCRBY", "temp:sensor1", 1.5,
      "TIMESTAMP", 1_640_000_000_000,
      "RETENTION", 86_400_000,
      "CHUNK_SIZE", 4096,
      "IGNORE", 500, 0.1,
      "LABELS", "sensor", "temp",
    ]

    assert_equal expected, @client.last_command
  end

  # ============================================================
  # ts_decrby - fast path (no options)
  # ============================================================

  def test_ts_decrby_fast_path
    @client.ts_decrby("temp:sensor1", 1.5)

    assert_equal ["TS.DECRBY", "temp:sensor1", 1.5], @client.last_command
  end

  # ============================================================
  # ts_decrby - with timestamp
  # ============================================================

  def test_ts_decrby_with_timestamp
    @client.ts_decrby("temp:sensor1", 1.5, timestamp: 1_640_000_000_000)

    assert_equal [
      "TS.DECRBY", "temp:sensor1", 1.5, "TIMESTAMP", 1_640_000_000_000,
    ], @client.last_command
  end

  # ============================================================
  # ts_decrby - with retention
  # ============================================================

  def test_ts_decrby_with_retention
    @client.ts_decrby("temp:sensor1", 1.5, retention: 86_400_000)

    assert_equal [
      "TS.DECRBY", "temp:sensor1", 1.5, "RETENTION", 86_400_000,
    ], @client.last_command
  end

  # ============================================================
  # ts_decrby - with labels
  # ============================================================

  def test_ts_decrby_with_labels
    @client.ts_decrby("temp:sensor1", 1.5, labels: { sensor: "temp" })

    assert_equal [
      "TS.DECRBY", "temp:sensor1", 1.5, "LABELS", "sensor", "temp",
    ], @client.last_command
  end

  # ============================================================
  # ts_decrby - with chunk_size
  # ============================================================

  def test_ts_decrby_with_chunk_size
    @client.ts_decrby("temp:sensor1", 1.5, chunk_size: 4096)

    assert_equal [
      "TS.DECRBY", "temp:sensor1", 1.5, "CHUNK_SIZE", 4096,
    ], @client.last_command
  end

  # ============================================================
  # ts_decrby - with ignore options
  # ============================================================

  def test_ts_decrby_with_ignore_max_time_diff
    @client.ts_decrby("temp:sensor1", 1.5, ignore_max_time_diff: 500)

    assert_equal [
      "TS.DECRBY", "temp:sensor1", 1.5, "IGNORE", 500,
    ], @client.last_command
  end

  def test_ts_decrby_with_ignore_max_val_diff
    @client.ts_decrby("temp:sensor1", 1.5, ignore_max_val_diff: 0.1)

    assert_equal [
      "TS.DECRBY", "temp:sensor1", 1.5, "IGNORE", 0.1,
    ], @client.last_command
  end

  def test_ts_decrby_with_both_ignore_options
    @client.ts_decrby("temp:sensor1", 1.5, ignore_max_time_diff: 500, ignore_max_val_diff: 0.1)

    assert_equal [
      "TS.DECRBY", "temp:sensor1", 1.5, "IGNORE", 500, 0.1,
    ], @client.last_command
  end

  # ============================================================
  # ts_decrby - with all options
  # ============================================================

  def test_ts_decrby_all_options
    @client.ts_decrby("temp:sensor1", 1.5,
                      timestamp: 1_640_000_000_000,
                      retention: 86_400_000,
                      chunk_size: 4096,
                      ignore_max_time_diff: 500,
                      ignore_max_val_diff: 0.1,
                      labels: { sensor: "temp" })
    expected = [
      "TS.DECRBY", "temp:sensor1", 1.5,
      "TIMESTAMP", 1_640_000_000_000,
      "RETENTION", 86_400_000,
      "CHUNK_SIZE", 4096,
      "IGNORE", 500, 0.1,
      "LABELS", "sensor", "temp",
    ]

    assert_equal expected, @client.last_command
  end

  # ============================================================
  # ts_createrule - basic
  # ============================================================

  def test_ts_createrule_basic
    @client.ts_createrule("temp:raw", "temp:hourly", "avg", 3_600_000)

    assert_equal [
      "TS.CREATERULE", "temp:raw", "temp:hourly", "AGGREGATION", "avg", 3_600_000,
    ], @client.last_command
  end

  # ============================================================
  # ts_createrule - with align_timestamp
  # ============================================================

  def test_ts_createrule_with_align_timestamp
    @client.ts_createrule("temp:raw", "temp:hourly", "avg", 3_600_000, align_timestamp: 0)

    assert_equal [
      "TS.CREATERULE", "temp:raw", "temp:hourly", "AGGREGATION", "avg", 3_600_000, 0,
    ], @client.last_command
  end

  # ============================================================
  # ts_createrule - without align_timestamp (nil)
  # ============================================================

  def test_ts_createrule_without_align_timestamp
    @client.ts_createrule("temp:raw", "temp:hourly", "sum", 60_000)

    assert_equal 6, @client.last_command.length
    assert_equal [
      "TS.CREATERULE", "temp:raw", "temp:hourly", "AGGREGATION", "sum", 60_000,
    ], @client.last_command
  end

  # ============================================================
  # ts_deleterule
  # ============================================================

  def test_ts_deleterule
    @client.ts_deleterule("temp:raw", "temp:hourly")

    assert_equal ["TS.DELETERULE", "temp:raw", "temp:hourly"], @client.last_command
  end

  # ============================================================
  # ts_range - fast path (no options)
  # ============================================================

  def test_ts_range_fast_path
    @client.ts_range("temp:sensor1", "-", "+")

    assert_equal ["TS.RANGE", "temp:sensor1", "-", "+"], @client.last_command
  end

  # ============================================================
  # ts_range - with latest
  # ============================================================

  def test_ts_range_with_latest
    @client.ts_range("temp:sensor1", "-", "+", latest: true)

    assert_includes @client.last_command, "LATEST"
  end

  # ============================================================
  # ts_range - with filter_by_ts
  # ============================================================

  def test_ts_range_with_filter_by_ts
    @client.ts_range("temp:sensor1", "-", "+", filter_by_ts: [1_000_000, 2_000_000])
    expected = [
      "TS.RANGE", "temp:sensor1", "-", "+", "FILTER_BY_TS", 1_000_000, 2_000_000,
    ]

    assert_equal expected, @client.last_command
  end

  # ============================================================
  # ts_range - with filter_by_value
  # ============================================================

  def test_ts_range_with_filter_by_value
    @client.ts_range("temp:sensor1", "-", "+", filter_by_value: [20.0, 30.0])
    expected = [
      "TS.RANGE", "temp:sensor1", "-", "+", "FILTER_BY_VALUE", 20.0, 30.0,
    ]

    assert_equal expected, @client.last_command
  end

  # ============================================================
  # ts_range - with count
  # ============================================================

  def test_ts_range_with_count
    @client.ts_range("temp:sensor1", "-", "+", count: 100)
    expected = [
      "TS.RANGE", "temp:sensor1", "-", "+", "COUNT", 100,
    ]

    assert_equal expected, @client.last_command
  end

  # ============================================================
  # ts_range - with align
  # ============================================================

  def test_ts_range_with_align
    @client.ts_range("temp:sensor1", "-", "+", align: 0, aggregation: "avg", bucket_duration: 3_600_000)

    assert_includes @client.last_command, "ALIGN"
    idx = @client.last_command.index("ALIGN")

    assert_equal 0, @client.last_command[idx + 1]
  end

  # ============================================================
  # ts_range - with aggregation and bucket_duration
  # ============================================================

  def test_ts_range_with_aggregation
    @client.ts_range("temp:sensor1", "-", "+", aggregation: "avg", bucket_duration: 3_600_000)
    expected = [
      "TS.RANGE", "temp:sensor1", "-", "+", "AGGREGATION", "avg", 3_600_000,
    ]

    assert_equal expected, @client.last_command
  end

  # ============================================================
  # ts_range - with aggregation + bucket_timestamp
  # ============================================================

  def test_ts_range_with_aggregation_and_bucket_timestamp
    @client.ts_range("temp:sensor1", "-", "+",
                     aggregation: "avg", bucket_duration: 3_600_000, bucket_timestamp: "start")
    expected = [
      "TS.RANGE", "temp:sensor1", "-", "+",
      "AGGREGATION", "avg", 3_600_000, "BUCKETTIMESTAMP", "start",
    ]

    assert_equal expected, @client.last_command
  end

  # ============================================================
  # ts_range - with aggregation + empty
  # ============================================================

  def test_ts_range_with_aggregation_and_empty
    @client.ts_range("temp:sensor1", "-", "+",
                     aggregation: "avg", bucket_duration: 3_600_000, empty: true)
    expected = [
      "TS.RANGE", "temp:sensor1", "-", "+",
      "AGGREGATION", "avg", 3_600_000, "EMPTY",
    ]

    assert_equal expected, @client.last_command
  end

  # ============================================================
  # ts_range - empty without aggregation (not added)
  # ============================================================

  def test_ts_range_empty_without_aggregation
    @client.ts_range("temp:sensor1", "-", "+", count: 10, empty: true)

    refute_includes @client.last_command, "EMPTY"
  end

  # ============================================================
  # ts_range - bucket_timestamp without aggregation (not added)
  # ============================================================

  def test_ts_range_bucket_timestamp_without_aggregation
    @client.ts_range("temp:sensor1", "-", "+", count: 10, bucket_timestamp: "end")

    refute_includes @client.last_command, "BUCKETTIMESTAMP"
  end

  # ============================================================
  # ts_range - with all options
  # ============================================================

  def test_ts_range_all_options
    @client.ts_range("temp:sensor1", "-", "+",
                     latest: true,
                     filter_by_ts: [1_000_000],
                     filter_by_value: [20.0, 30.0],
                     count: 100,
                     align: 0,
                     aggregation: "avg",
                     bucket_duration: 3_600_000,
                     bucket_timestamp: "start",
                     empty: true)
    expected = [
      "TS.RANGE", "temp:sensor1", "-", "+",
      "LATEST",
      "FILTER_BY_TS", 1_000_000,
      "FILTER_BY_VALUE", 20.0, 30.0,
      "COUNT", 100,
      "ALIGN", 0,
      "AGGREGATION", "avg", 3_600_000,
      "BUCKETTIMESTAMP", "start",
      "EMPTY",
    ]

    assert_equal expected, @client.last_command
  end

  # ============================================================
  # ts_revrange - fast path (no options)
  # ============================================================

  def test_ts_revrange_fast_path
    @client.ts_revrange("temp:sensor1", "-", "+")

    assert_equal ["TS.REVRANGE", "temp:sensor1", "-", "+"], @client.last_command
  end

  # ============================================================
  # ts_revrange - with latest
  # ============================================================

  def test_ts_revrange_with_latest
    @client.ts_revrange("temp:sensor1", "-", "+", latest: true)

    assert_includes @client.last_command, "LATEST"
    assert_equal "TS.REVRANGE", @client.last_command[0]
  end

  # ============================================================
  # ts_revrange - with filter_by_ts
  # ============================================================

  def test_ts_revrange_with_filter_by_ts
    @client.ts_revrange("temp:sensor1", "-", "+", filter_by_ts: [1_000_000, 2_000_000])

    assert_equal "TS.REVRANGE", @client.last_command[0]
    assert_includes @client.last_command, "FILTER_BY_TS"
  end

  # ============================================================
  # ts_revrange - with filter_by_value
  # ============================================================

  def test_ts_revrange_with_filter_by_value
    @client.ts_revrange("temp:sensor1", "-", "+", filter_by_value: [10.0, 50.0])

    assert_equal "TS.REVRANGE", @client.last_command[0]
    assert_includes @client.last_command, "FILTER_BY_VALUE"
  end

  # ============================================================
  # ts_revrange - with count
  # ============================================================

  def test_ts_revrange_with_count
    @client.ts_revrange("temp:sensor1", "-", "+", count: 50)

    assert_equal "TS.REVRANGE", @client.last_command[0]
    assert_includes @client.last_command, "COUNT"
  end

  # ============================================================
  # ts_revrange - with aggregation
  # ============================================================

  def test_ts_revrange_with_aggregation
    @client.ts_revrange("temp:sensor1", "-", "+",
                        aggregation: "sum", bucket_duration: 60_000)

    assert_equal "TS.REVRANGE", @client.last_command[0]
    assert_includes @client.last_command, "AGGREGATION"
  end

  # ============================================================
  # ts_revrange - with aggregation + bucket_timestamp + empty
  # ============================================================

  def test_ts_revrange_with_aggregation_bucket_timestamp_and_empty
    @client.ts_revrange("temp:sensor1", "-", "+",
                        aggregation: "avg", bucket_duration: 3_600_000,
                        bucket_timestamp: "end", empty: true)
    expected = [
      "TS.REVRANGE", "temp:sensor1", "-", "+",
      "AGGREGATION", "avg", 3_600_000, "BUCKETTIMESTAMP", "end", "EMPTY",
    ]

    assert_equal expected, @client.last_command
  end

  # ============================================================
  # ts_revrange - with all options
  # ============================================================

  def test_ts_revrange_all_options
    @client.ts_revrange("temp:sensor1", "-", "+",
                        latest: true,
                        filter_by_ts: [1_000_000],
                        filter_by_value: [20.0, 30.0],
                        count: 50,
                        align: 0,
                        aggregation: "avg",
                        bucket_duration: 3_600_000,
                        bucket_timestamp: "mid",
                        empty: true)
    expected = [
      "TS.REVRANGE", "temp:sensor1", "-", "+",
      "LATEST",
      "FILTER_BY_TS", 1_000_000,
      "FILTER_BY_VALUE", 20.0, 30.0,
      "COUNT", 50,
      "ALIGN", 0,
      "AGGREGATION", "avg", 3_600_000,
      "BUCKETTIMESTAMP", "mid",
      "EMPTY",
    ]

    assert_equal expected, @client.last_command
  end

  # ============================================================
  # ts_mrange - basic (filters only)
  # ============================================================

  def test_ts_mrange_basic
    @client.ts_mrange("-", "+", ["sensor=temp"])
    expected = [
      "TS.MRANGE", "-", "+", "FILTER", "sensor=temp",
    ]

    assert_equal expected, @client.last_command
  end

  # ============================================================
  # ts_mrange - with latest
  # ============================================================

  def test_ts_mrange_with_latest
    @client.ts_mrange("-", "+", ["sensor=temp"], latest: true)

    assert_includes @client.last_command, "LATEST"
  end

  # ============================================================
  # ts_mrange - with filter_by_ts
  # ============================================================

  def test_ts_mrange_with_filter_by_ts
    @client.ts_mrange("-", "+", ["sensor=temp"], filter_by_ts: [1_000_000, 2_000_000])

    assert_includes @client.last_command, "FILTER_BY_TS"
    idx = @client.last_command.index("FILTER_BY_TS")

    assert_equal 1_000_000, @client.last_command[idx + 1]
    assert_equal 2_000_000, @client.last_command[idx + 2]
  end

  # ============================================================
  # ts_mrange - with filter_by_value
  # ============================================================

  def test_ts_mrange_with_filter_by_value
    @client.ts_mrange("-", "+", ["sensor=temp"], filter_by_value: [20.0, 30.0])

    assert_includes @client.last_command, "FILTER_BY_VALUE"
    idx = @client.last_command.index("FILTER_BY_VALUE")

    assert_in_delta 20.0, @client.last_command[idx + 1]
    assert_in_delta 30.0, @client.last_command[idx + 2]
  end

  # ============================================================
  # ts_mrange - with withlabels
  # ============================================================

  def test_ts_mrange_with_withlabels
    @client.ts_mrange("-", "+", ["sensor=temp"], withlabels: true)

    assert_includes @client.last_command, "WITHLABELS"
  end

  def test_ts_mrange_without_withlabels
    @client.ts_mrange("-", "+", ["sensor=temp"], withlabels: false)

    refute_includes @client.last_command, "WITHLABELS"
  end

  # ============================================================
  # ts_mrange - with selected_labels
  # ============================================================

  def test_ts_mrange_with_selected_labels
    @client.ts_mrange("-", "+", ["sensor=temp"], selected_labels: %w[sensor location])

    assert_includes @client.last_command, "SELECTED_LABELS"
    idx = @client.last_command.index("SELECTED_LABELS")

    assert_equal "sensor", @client.last_command[idx + 1]
    assert_equal "location", @client.last_command[idx + 2]
  end

  # ============================================================
  # ts_mrange - with count
  # ============================================================

  def test_ts_mrange_with_count
    @client.ts_mrange("-", "+", ["sensor=temp"], count: 100)

    assert_includes @client.last_command, "COUNT"
    idx = @client.last_command.index("COUNT")

    assert_equal 100, @client.last_command[idx + 1]
  end

  # ============================================================
  # ts_mrange - with align
  # ============================================================

  def test_ts_mrange_with_align
    @client.ts_mrange("-", "+", ["sensor=temp"],
                      align: 0, aggregation: "avg", bucket_duration: 3_600_000)

    assert_includes @client.last_command, "ALIGN"
    idx = @client.last_command.index("ALIGN")

    assert_equal 0, @client.last_command[idx + 1]
  end

  # ============================================================
  # ts_mrange - with aggregation
  # ============================================================

  def test_ts_mrange_with_aggregation
    @client.ts_mrange("-", "+", ["sensor=temp"],
                      aggregation: "avg", bucket_duration: 3_600_000)

    assert_includes @client.last_command, "AGGREGATION"
    idx = @client.last_command.index("AGGREGATION")

    assert_equal "avg", @client.last_command[idx + 1]
    assert_equal 3_600_000, @client.last_command[idx + 2]
  end

  # ============================================================
  # ts_mrange - with aggregation + bucket_timestamp
  # ============================================================

  def test_ts_mrange_with_aggregation_and_bucket_timestamp
    @client.ts_mrange("-", "+", ["sensor=temp"],
                      aggregation: "avg", bucket_duration: 3_600_000, bucket_timestamp: "start")

    assert_includes @client.last_command, "BUCKETTIMESTAMP"
    idx = @client.last_command.index("BUCKETTIMESTAMP")

    assert_equal "start", @client.last_command[idx + 1]
  end

  # ============================================================
  # ts_mrange - with aggregation + empty
  # ============================================================

  def test_ts_mrange_with_aggregation_and_empty
    @client.ts_mrange("-", "+", ["sensor=temp"],
                      aggregation: "avg", bucket_duration: 3_600_000, empty: true)

    assert_includes @client.last_command, "EMPTY"
  end

  # ============================================================
  # ts_mrange - empty without aggregation (not added)
  # ============================================================

  def test_ts_mrange_empty_without_aggregation
    @client.ts_mrange("-", "+", ["sensor=temp"], empty: true)

    refute_includes @client.last_command, "EMPTY"
  end

  # ============================================================
  # ts_mrange - bucket_timestamp without aggregation (not added)
  # ============================================================

  def test_ts_mrange_bucket_timestamp_without_aggregation
    @client.ts_mrange("-", "+", ["sensor=temp"], bucket_timestamp: "end")

    refute_includes @client.last_command, "BUCKETTIMESTAMP"
  end

  # ============================================================
  # ts_mrange - with groupby and reduce
  # ============================================================

  def test_ts_mrange_with_groupby_and_reduce
    @client.ts_mrange("-", "+", ["sensor=temp"], groupby: "location", reduce: "avg")

    assert_includes @client.last_command, "GROUPBY"
    assert_includes @client.last_command, "REDUCE"
    idx = @client.last_command.index("GROUPBY")

    assert_equal "location", @client.last_command[idx + 1]
    assert_equal "REDUCE", @client.last_command[idx + 2]
    assert_equal "avg", @client.last_command[idx + 3]
  end

  # ============================================================
  # ts_mrange - without groupby (not added)
  # ============================================================

  def test_ts_mrange_without_groupby
    @client.ts_mrange("-", "+", ["sensor=temp"])

    refute_includes @client.last_command, "GROUPBY"
    refute_includes @client.last_command, "REDUCE"
  end

  # ============================================================
  # ts_mrange - with multiple filters
  # ============================================================

  def test_ts_mrange_with_multiple_filters
    @client.ts_mrange("-", "+", ["sensor=temp", "location=room1"])
    expected = [
      "TS.MRANGE", "-", "+", "FILTER", "sensor=temp", "location=room1",
    ]

    assert_equal expected, @client.last_command
  end

  # ============================================================
  # ts_mrange - with all options
  # ============================================================

  def test_ts_mrange_all_options
    @client.ts_mrange("-", "+", ["sensor=temp"],
                      latest: true,
                      filter_by_ts: [1_000_000],
                      filter_by_value: [20.0, 30.0],
                      withlabels: true,
                      count: 100,
                      align: 0,
                      aggregation: "avg",
                      bucket_duration: 3_600_000,
                      bucket_timestamp: "start",
                      empty: true,
                      groupby: "location",
                      reduce: "avg")
    expected = [
      "TS.MRANGE", "-", "+",
      "LATEST",
      "FILTER_BY_TS", 1_000_000,
      "FILTER_BY_VALUE", 20.0, 30.0,
      "WITHLABELS",
      "COUNT", 100,
      "ALIGN", 0,
      "AGGREGATION", "avg", 3_600_000,
      "BUCKETTIMESTAMP", "start",
      "EMPTY",
      "FILTER", "sensor=temp",
      "GROUPBY", "location", "REDUCE", "avg",
    ]

    assert_equal expected, @client.last_command
  end

  # ============================================================
  # ts_mrevrange - basic (filters only)
  # ============================================================

  def test_ts_mrevrange_basic
    @client.ts_mrevrange("-", "+", ["sensor=temp"])
    expected = [
      "TS.MREVRANGE", "-", "+", "FILTER", "sensor=temp",
    ]

    assert_equal expected, @client.last_command
  end

  # ============================================================
  # ts_mrevrange - with latest
  # ============================================================

  def test_ts_mrevrange_with_latest
    @client.ts_mrevrange("-", "+", ["sensor=temp"], latest: true)

    assert_equal "TS.MREVRANGE", @client.last_command[0]
    assert_includes @client.last_command, "LATEST"
  end

  # ============================================================
  # ts_mrevrange - with filter_by_ts
  # ============================================================

  def test_ts_mrevrange_with_filter_by_ts
    @client.ts_mrevrange("-", "+", ["sensor=temp"], filter_by_ts: [1_000_000])

    assert_equal "TS.MREVRANGE", @client.last_command[0]
    assert_includes @client.last_command, "FILTER_BY_TS"
  end

  # ============================================================
  # ts_mrevrange - with filter_by_value
  # ============================================================

  def test_ts_mrevrange_with_filter_by_value
    @client.ts_mrevrange("-", "+", ["sensor=temp"], filter_by_value: [10.0, 50.0])

    assert_equal "TS.MREVRANGE", @client.last_command[0]
    assert_includes @client.last_command, "FILTER_BY_VALUE"
  end

  # ============================================================
  # ts_mrevrange - with withlabels
  # ============================================================

  def test_ts_mrevrange_with_withlabels
    @client.ts_mrevrange("-", "+", ["sensor=temp"], withlabels: true)

    assert_equal "TS.MREVRANGE", @client.last_command[0]
    assert_includes @client.last_command, "WITHLABELS"
  end

  # ============================================================
  # ts_mrevrange - with selected_labels
  # ============================================================

  def test_ts_mrevrange_with_selected_labels
    @client.ts_mrevrange("-", "+", ["sensor=temp"], selected_labels: ["sensor"])

    assert_equal "TS.MREVRANGE", @client.last_command[0]
    assert_includes @client.last_command, "SELECTED_LABELS"
  end

  # ============================================================
  # ts_mrevrange - with count
  # ============================================================

  def test_ts_mrevrange_with_count
    @client.ts_mrevrange("-", "+", ["sensor=temp"], count: 50)

    assert_equal "TS.MREVRANGE", @client.last_command[0]
    assert_includes @client.last_command, "COUNT"
  end

  # ============================================================
  # ts_mrevrange - with aggregation
  # ============================================================

  def test_ts_mrevrange_with_aggregation
    @client.ts_mrevrange("-", "+", ["sensor=temp"],
                         aggregation: "sum", bucket_duration: 60_000)

    assert_equal "TS.MREVRANGE", @client.last_command[0]
    assert_includes @client.last_command, "AGGREGATION"
  end

  # ============================================================
  # ts_mrevrange - with aggregation + bucket_timestamp + empty
  # ============================================================

  def test_ts_mrevrange_with_aggregation_bucket_timestamp_and_empty
    @client.ts_mrevrange("-", "+", ["sensor=temp"],
                         aggregation: "avg", bucket_duration: 3_600_000,
                         bucket_timestamp: "end", empty: true)

    assert_equal "TS.MREVRANGE", @client.last_command[0]
    assert_includes @client.last_command, "BUCKETTIMESTAMP"
    assert_includes @client.last_command, "EMPTY"
  end

  # ============================================================
  # ts_mrevrange - with groupby and reduce
  # ============================================================

  def test_ts_mrevrange_with_groupby_and_reduce
    @client.ts_mrevrange("-", "+", ["sensor=temp"], groupby: "location", reduce: "sum")

    assert_equal "TS.MREVRANGE", @client.last_command[0]
    assert_includes @client.last_command, "GROUPBY"
    assert_includes @client.last_command, "REDUCE"
  end

  # ============================================================
  # ts_mrevrange - without groupby (not added)
  # ============================================================

  def test_ts_mrevrange_without_groupby
    @client.ts_mrevrange("-", "+", ["sensor=temp"])

    refute_includes @client.last_command, "GROUPBY"
    refute_includes @client.last_command, "REDUCE"
  end

  # ============================================================
  # ts_mrevrange - with all options
  # ============================================================

  def test_ts_mrevrange_all_options
    @client.ts_mrevrange("-", "+", ["sensor=temp"],
                         latest: true,
                         filter_by_ts: [1_000_000],
                         filter_by_value: [20.0, 30.0],
                         withlabels: true,
                         count: 50,
                         align: 0,
                         aggregation: "avg",
                         bucket_duration: 3_600_000,
                         bucket_timestamp: "mid",
                         empty: true,
                         groupby: "location",
                         reduce: "sum")
    expected = [
      "TS.MREVRANGE", "-", "+",
      "LATEST",
      "FILTER_BY_TS", 1_000_000,
      "FILTER_BY_VALUE", 20.0, 30.0,
      "WITHLABELS",
      "COUNT", 50,
      "ALIGN", 0,
      "AGGREGATION", "avg", 3_600_000,
      "BUCKETTIMESTAMP", "mid",
      "EMPTY",
      "FILTER", "sensor=temp",
      "GROUPBY", "location", "REDUCE", "sum",
    ]

    assert_equal expected, @client.last_command
  end

  # ============================================================
  # ts_get - fast path (no latest)
  # ============================================================

  def test_ts_get_fast_path
    result = @client.ts_get("temp:sensor1")

    assert_equal ["TS.GET", "temp:sensor1"], @client.last_command
    assert_equal [1_640_000_000, 23.5], result
  end

  # ============================================================
  # ts_get - with latest
  # ============================================================

  def test_ts_get_with_latest
    @client.ts_get("temp:sensor1", latest: true)

    assert_equal ["TS.GET", "temp:sensor1", "LATEST"], @client.last_command
  end

  # ============================================================
  # ts_get - without latest (explicit false)
  # ============================================================

  def test_ts_get_without_latest_explicit
    result = @client.ts_get("temp:sensor1", latest: false)

    assert_equal ["TS.GET", "temp:sensor1"], @client.last_command
    assert_equal [1_640_000_000, 23.5], result
  end

  # ============================================================
  # ts_mget - basic (filters only)
  # ============================================================

  def test_ts_mget_basic
    @client.ts_mget(["sensor=temp"])

    assert_equal ["TS.MGET", "FILTER", "sensor=temp"], @client.last_command
  end

  # ============================================================
  # ts_mget - with latest
  # ============================================================

  def test_ts_mget_with_latest
    @client.ts_mget(["sensor=temp"], latest: true)

    assert_equal ["TS.MGET", "LATEST", "FILTER", "sensor=temp"], @client.last_command
  end

  # ============================================================
  # ts_mget - without latest
  # ============================================================

  def test_ts_mget_without_latest
    @client.ts_mget(["sensor=temp"], latest: false)

    refute_includes @client.last_command, "LATEST"
  end

  # ============================================================
  # ts_mget - with withlabels
  # ============================================================

  def test_ts_mget_with_withlabels
    @client.ts_mget(["sensor=temp"], withlabels: true)

    assert_equal ["TS.MGET", "WITHLABELS", "FILTER", "sensor=temp"], @client.last_command
  end

  # ============================================================
  # ts_mget - without withlabels
  # ============================================================

  def test_ts_mget_without_withlabels
    @client.ts_mget(["sensor=temp"], withlabels: false)

    refute_includes @client.last_command, "WITHLABELS"
  end

  # ============================================================
  # ts_mget - with selected_labels
  # ============================================================

  def test_ts_mget_with_selected_labels
    @client.ts_mget(["sensor=temp"], selected_labels: %w[sensor location])
    expected = [
      "TS.MGET", "SELECTED_LABELS", "sensor", "location", "FILTER", "sensor=temp",
    ]

    assert_equal expected, @client.last_command
  end

  # ============================================================
  # ts_mget - without selected_labels
  # ============================================================

  def test_ts_mget_without_selected_labels
    @client.ts_mget(["sensor=temp"])

    refute_includes @client.last_command, "SELECTED_LABELS"
  end

  # ============================================================
  # ts_mget - with latest and withlabels
  # ============================================================

  def test_ts_mget_with_latest_and_withlabels
    @client.ts_mget(["sensor=temp"], latest: true, withlabels: true)
    expected = [
      "TS.MGET", "LATEST", "WITHLABELS", "FILTER", "sensor=temp",
    ]

    assert_equal expected, @client.last_command
  end

  # ============================================================
  # ts_mget - with all options
  # ============================================================

  def test_ts_mget_all_options
    @client.ts_mget(["sensor=temp", "location=room1"],
                    latest: true, withlabels: true, selected_labels: ["sensor"])
    expected = [
      "TS.MGET", "LATEST", "WITHLABELS", "SELECTED_LABELS", "sensor",
      "FILTER", "sensor=temp", "location=room1",
    ]

    assert_equal expected, @client.last_command
  end

  # ============================================================
  # ts_info - basic (no debug)
  # ============================================================

  def test_ts_info_basic
    result = @client.ts_info("temp:sensor1")

    assert_equal ["TS.INFO", "temp:sensor1"], @client.last_command
    assert_equal({ "totalSamples" => 100, "memoryUsage" => 4096 }, result)
  end

  # ============================================================
  # ts_info - with debug
  # ============================================================

  def test_ts_info_with_debug
    # Override call to return same info format for debug path
    def @client.call(*args)
      @last_command = args
      ["totalSamples", 100, "memoryUsage", 4096, "chunks", []]
    end

    result = @client.ts_info("temp:sensor1", debug: true)

    assert_equal ["TS.INFO", "temp:sensor1", "DEBUG"], @client.last_command
    assert_equal({ "totalSamples" => 100, "memoryUsage" => 4096, "chunks" => [] }, result)
  end

  # ============================================================
  # ts_info - debug false (explicit)
  # ============================================================

  def test_ts_info_debug_false
    result = @client.ts_info("temp:sensor1", debug: false)

    assert_equal ["TS.INFO", "temp:sensor1"], @client.last_command
    assert_instance_of Hash, result
  end

  # ============================================================
  # ts_queryindex
  # ============================================================

  def test_ts_queryindex_single_filter
    @client.ts_queryindex("sensor=temp")

    assert_equal ["TS.QUERYINDEX", "sensor=temp"], @client.last_command
  end

  def test_ts_queryindex_multiple_filters
    @client.ts_queryindex("sensor=temp", "location=room1")

    assert_equal ["TS.QUERYINDEX", "sensor=temp", "location=room1"], @client.last_command
  end

  # ============================================================
  # ts_mrange - selected_labels without withlabels
  # ============================================================

  def test_ts_mrange_selected_labels_without_withlabels
    @client.ts_mrange("-", "+", ["sensor=temp"], selected_labels: ["sensor"])

    assert_includes @client.last_command, "SELECTED_LABELS"
    refute_includes @client.last_command, "WITHLABELS"
  end

  # ============================================================
  # ts_mrevrange - selected_labels without withlabels
  # ============================================================

  def test_ts_mrevrange_selected_labels_without_withlabels
    @client.ts_mrevrange("-", "+", ["sensor=temp"], selected_labels: ["sensor"])

    assert_includes @client.last_command, "SELECTED_LABELS"
    refute_includes @client.last_command, "WITHLABELS"
  end

  # ============================================================
  # ts_mrange - align without aggregation (still added)
  # ============================================================

  def test_ts_mrange_align_without_aggregation
    @client.ts_mrange("-", "+", ["sensor=temp"], align: 0)

    assert_includes @client.last_command, "ALIGN"
    refute_includes @client.last_command, "AGGREGATION"
  end

  # ============================================================
  # ts_range - align without aggregation (still added)
  # ============================================================

  def test_ts_range_align_without_aggregation
    @client.ts_range("temp:sensor1", "-", "+", align: 0)

    assert_includes @client.last_command, "ALIGN"
    refute_includes @client.last_command, "AGGREGATION"
  end
end
