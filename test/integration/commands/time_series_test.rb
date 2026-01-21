# frozen_string_literal: true

require "test_helper"

class TimeSeriesCommandsTest < RedisRubyTestCase
  use_testcontainers!

  def setup
    super
    @ts_key = "ts:test:#{SecureRandom.hex(4)}"
    @ts_key2 = "ts:test2:#{SecureRandom.hex(4)}"
    @ts_dest = "ts:dest:#{SecureRandom.hex(4)}"
  end

  def teardown
    redis.del(@ts_key, @ts_key2, @ts_dest)
    super
  end

  def test_ts_create
    result = redis.ts_create(@ts_key)
    assert_equal "OK", result
  end

  def test_ts_create_with_options
    result = redis.ts_create(@ts_key,
                             retention: 86_400_000,
                             labels: { sensor: "temp", location: "room1" })
    assert_equal "OK", result

    info = redis.ts_info(@ts_key)
    assert_equal 86_400_000, info["retentionTime"]
  end

  def test_ts_add_with_auto_timestamp
    redis.ts_create(@ts_key)

    timestamp = redis.ts_add(@ts_key, "*", 25.5)
    assert_kind_of Integer, timestamp
    assert timestamp > 0
  end

  def test_ts_add_with_specific_timestamp
    redis.ts_create(@ts_key)

    ts = 1640000000000
    result = redis.ts_add(@ts_key, ts, 23.5)
    assert_equal ts, result
  end

  def test_ts_add_creates_series
    # Add without creating first (auto-create)
    timestamp = redis.ts_add(@ts_key, "*", 20.0, labels: { type: "auto" })
    assert_kind_of Integer, timestamp

    # Verify it was created with labels
    info = redis.ts_info(@ts_key)
    labels = info["labels"]
    assert labels.any? { |l| l.include?("type") && l.include?("auto") }
  end

  def test_ts_madd
    redis.ts_create(@ts_key)
    redis.ts_create(@ts_key2)

    results = redis.ts_madd(
      [@ts_key, "*", 10.0],
      [@ts_key2, "*", 20.0]
    )

    assert_equal 2, results.length
    assert results.all? { |r| r.is_a?(Integer) && r > 0 }
  end

  def test_ts_incrby
    redis.ts_create(@ts_key)
    redis.ts_add(@ts_key, "*", 100.0)

    result = redis.ts_incrby(@ts_key, 10.0)
    assert_kind_of Integer, result

    # Get latest value
    sample = redis.ts_get(@ts_key)
    assert sample[1].to_f >= 110.0
  end

  def test_ts_decrby
    redis.ts_create(@ts_key)
    redis.ts_add(@ts_key, "*", 100.0)

    result = redis.ts_decrby(@ts_key, 10.0)
    assert_kind_of Integer, result

    sample = redis.ts_get(@ts_key)
    assert sample[1].to_f <= 90.0
  end

  def test_ts_get
    redis.ts_create(@ts_key)

    ts = 1640000000000
    redis.ts_add(@ts_key, ts, 42.5)

    sample = redis.ts_get(@ts_key)
    assert_equal 2, sample.length
    assert_equal ts, sample[0]
    assert_equal "42.5", sample[1].to_s
  end

  def test_ts_get_empty
    redis.ts_create(@ts_key)

    sample = redis.ts_get(@ts_key)
    assert_equal [], sample
  end

  def test_ts_range
    redis.ts_create(@ts_key)

    # Add samples with specific timestamps
    base_ts = 1640000000000
    5.times do |i|
      redis.ts_add(@ts_key, base_ts + i * 1000, i * 10.0)
    end

    # Get all samples
    samples = redis.ts_range(@ts_key, "-", "+")

    assert_equal 5, samples.length
    assert_equal base_ts, samples[0][0]
  end

  def test_ts_range_with_count
    redis.ts_create(@ts_key)

    base_ts = 1640000000000
    10.times do |i|
      redis.ts_add(@ts_key, base_ts + i * 1000, i.to_f)
    end

    # Get only first 3
    samples = redis.ts_range(@ts_key, "-", "+", count: 3)

    assert_equal 3, samples.length
  end

  def test_ts_range_with_aggregation
    redis.ts_create(@ts_key)

    base_ts = 1640000000000
    6.times do |i|
      redis.ts_add(@ts_key, base_ts + i * 1000, i * 10.0)
    end

    # Aggregate every 2 seconds with avg
    samples = redis.ts_range(@ts_key, "-", "+",
                             aggregation: "avg",
                             bucket_duration: 2000)

    # Should have fewer samples due to aggregation
    assert samples.length < 6
  end

  def test_ts_revrange
    redis.ts_create(@ts_key)

    base_ts = 1640000000000
    3.times do |i|
      redis.ts_add(@ts_key, base_ts + i * 1000, i.to_f)
    end

    samples = redis.ts_revrange(@ts_key, "-", "+")

    assert_equal 3, samples.length
    # First sample should be the latest (highest timestamp)
    assert samples[0][0] > samples[1][0]
  end

  def test_ts_mrange
    redis.ts_create(@ts_key, labels: { sensor: "temp" })
    redis.ts_create(@ts_key2, labels: { sensor: "temp" })

    redis.ts_add(@ts_key, "*", 25.0)
    redis.ts_add(@ts_key2, "*", 30.0)

    results = redis.ts_mrange("-", "+", ["sensor=temp"])

    assert results.length >= 2
  end

  def test_ts_mget
    redis.ts_create(@ts_key, labels: { type: "test" })
    redis.ts_create(@ts_key2, labels: { type: "test" })

    redis.ts_add(@ts_key, "*", 10.0)
    redis.ts_add(@ts_key2, "*", 20.0)

    results = redis.ts_mget(["type=test"])

    assert results.length >= 2
  end

  def test_ts_info
    redis.ts_create(@ts_key, retention: 3600000, labels: { env: "test" })
    redis.ts_add(@ts_key, "*", 100.0)

    info = redis.ts_info(@ts_key)

    assert_kind_of Hash, info
    assert info.key?("totalSamples") || info.key?("total_samples")
    assert_equal 3600000, info["retentionTime"]
  end

  def test_ts_alter
    redis.ts_create(@ts_key, retention: 1000)

    result = redis.ts_alter(@ts_key, retention: 5000)
    assert_equal "OK", result

    info = redis.ts_info(@ts_key)
    assert_equal 5000, info["retentionTime"]
  end

  def test_ts_del
    redis.ts_create(@ts_key)

    base_ts = 1640000000000
    5.times do |i|
      redis.ts_add(@ts_key, base_ts + i * 1000, i.to_f)
    end

    # Delete middle samples
    deleted = redis.ts_del(@ts_key, base_ts + 1000, base_ts + 3000)
    assert deleted >= 2

    # Check remaining samples
    samples = redis.ts_range(@ts_key, "-", "+")
    assert samples.length < 5
  end

  def test_ts_createrule
    redis.ts_create(@ts_key)
    redis.ts_create(@ts_dest)

    result = redis.ts_createrule(@ts_key, @ts_dest, "avg", 5000)
    assert_equal "OK", result

    info = redis.ts_info(@ts_key)
    rules = info["rules"]
    assert rules.any? { |r| r.include?(@ts_dest) }
  end

  def test_ts_deleterule
    redis.ts_create(@ts_key)
    redis.ts_create(@ts_dest)
    redis.ts_createrule(@ts_key, @ts_dest, "avg", 5000)

    result = redis.ts_deleterule(@ts_key, @ts_dest)
    assert_equal "OK", result

    info = redis.ts_info(@ts_key)
    rules = info["rules"]
    assert_equal [], rules
  end

  def test_ts_queryindex
    # Create series with unique label
    unique_label = "test_#{SecureRandom.hex(4)}"
    redis.ts_create(@ts_key, labels: { unique: unique_label })

    keys = redis.ts_queryindex("unique=#{unique_label}")

    assert_includes keys, @ts_key
  end

  def test_ts_range_with_filter_by_value
    redis.ts_create(@ts_key)

    base_ts = 1640000000000
    [10, 50, 100, 150, 200].each_with_index do |val, i|
      redis.ts_add(@ts_key, base_ts + i * 1000, val.to_f)
    end

    # Filter to only values between 40 and 160
    samples = redis.ts_range(@ts_key, "-", "+", filter_by_value: [40, 160])

    values = samples.map { |s| s[1].to_f }
    assert values.all? { |v| v >= 40 && v <= 160 }
  end
end
