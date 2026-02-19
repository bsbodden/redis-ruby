# frozen_string_literal: true

require "test_helper"

class TimeSeriesDSLTest < Minitest::Test
  def setup
    @redis = RR::Client.new
    @redis.flushdb
  end

  def teardown
    @redis.flushdb
    @redis.close
  end

  def test_time_series_builder_basic
    # Create time series with DSL
    result = @redis.time_series("temp:sensor1") do
      retention 86_400_000 # 24 hours
      labels sensor: "temp", location: "room1"
    end

    assert_equal "temp:sensor1", result

    # Verify it was created
    info = @redis.ts_info("temp:sensor1")

    assert_equal 86_400_000, info["retentionTime"]
    labels_hash = info["labels"].to_h

    assert_equal "temp", labels_hash["sensor"]
    assert_equal "room1", labels_hash["location"]
  end

  def test_time_series_builder_with_compaction
    # Create time series with compaction rules
    @redis.time_series("temp:raw") do
      retention 3_600_000 # 1 hour
      labels resolution: "raw"

      compact_to "temp:hourly", :avg, 3_600_000 do
        retention 86_400_000 # 24 hours
        labels resolution: "hourly"
      end
    end

    # Verify main series
    info = @redis.ts_info("temp:raw")

    assert_equal 3_600_000, info["retentionTime"]

    # Verify destination series
    info = @redis.ts_info("temp:hourly")

    assert_equal 86_400_000, info["retentionTime"]

    # Verify compaction rule exists
    rules = info["rules"]

    assert_equal 0, rules.length # Rules are on source, not destination

    # Check source has the rule
    info = @redis.ts_info("temp:raw")
    rules = info["rules"]

    assert_equal 1, rules.length
  end

  def test_time_series_proxy_add
    @redis.ts_create("temp:sensor1")

    # Add samples with chaining (use explicit timestamps to avoid duplicates)
    now = Time.now.to_i * 1000
    result = @redis.ts("temp:sensor1")
      .add(now, 23.5)
      .add(now + 1000, 24.0)
      .add(now + 2000, 23.8)

    assert_instance_of RR::DSL::TimeSeriesProxy, result

    # Verify samples were added
    samples = @redis.ts_range("temp:sensor1", "-", "+")

    assert_equal 3, samples.length
  end

  def test_time_series_proxy_increment_decrement
    @redis.ts_create("counter:requests")
    @redis.ts_add("counter:requests", "*", 100)

    # Increment and decrement
    @redis.ts("counter:requests")
      .increment(10)
      .decrement(5)

    # Get latest value
    latest = @redis.ts("counter:requests").get

    assert_equal "105", latest[1]
  end

  def test_time_series_proxy_get
    @redis.ts_create("temp:sensor1")
    timestamp = @redis.ts_add("temp:sensor1", "*", 23.5)

    # Get latest sample
    result = @redis.ts("temp:sensor1").get

    assert_equal timestamp, result[0]
    assert_equal "23.5", result[1]
  end

  def test_time_series_proxy_info
    @redis.ts_create("temp:sensor1", retention: 86_400_000)

    # Get info
    info = @redis.ts("temp:sensor1").info

    assert_equal 86_400_000, info["retentionTime"]
  end

  def test_time_series_proxy_delete
    @redis.ts_create("temp:sensor1")

    # Add samples with explicit timestamps
    now = Time.now.to_i * 1000
    @redis.ts_add("temp:sensor1", now, 23.5)
    @redis.ts_add("temp:sensor1", now + 1000, 24.0)
    @redis.ts_add("temp:sensor1", now + 2000, 23.8)

    # Delete middle sample
    deleted = @redis.ts("temp:sensor1").delete(from: now + 1000, to: now + 1000)

    assert_equal 1, deleted

    # Verify only 2 samples remain
    samples = @redis.ts_range("temp:sensor1", "-", "+")

    assert_equal 2, samples.length
  end

  def test_time_series_proxy_alter
    @redis.ts_create("temp:sensor1", retention: 3_600_000)

    # Alter retention
    @redis.ts("temp:sensor1").alter(retention: 86_400_000)

    # Verify change
    info = @redis.ts_info("temp:sensor1")

    assert_equal 86_400_000, info["retentionTime"]
  end

  def test_time_series_proxy_compact_to
    @redis.ts_create("temp:raw")
    @redis.ts_create("temp:hourly")

    # Create compaction rule
    @redis.ts("temp:raw").compact_to("temp:hourly", :avg, 3_600_000)

    # Verify rule exists
    info = @redis.ts_info("temp:raw")
    rules = info["rules"]

    assert_equal 1, rules.length
  end

  def test_time_series_proxy_add_many
    @redis.ts_create("temp:sensor1")

    # Add multiple samples
    now = Time.now.to_i * 1000
    @redis.ts("temp:sensor1").add_many(
      [now, 23.5],
      [now + 1000, 24.0],
      [now + 2000, 23.8]
    )

    # Verify samples
    samples = @redis.ts_range("temp:sensor1", "-", "+")

    assert_equal 3, samples.length
  end

  def test_time_series_query_builder_single_series
    @redis.ts_create("temp:sensor1")

    # Add samples
    now = Time.now.to_i * 1000
    @redis.ts_add("temp:sensor1", now, 23.5)
    @redis.ts_add("temp:sensor1", now + 60_000, 24.0)
    @redis.ts_add("temp:sensor1", now + 120_000, 23.8)

    # Query with builder
    result = @redis.ts_query("temp:sensor1")
      .from("-")
      .to("+")
      .execute

    assert_equal 3, result.length
  end

  def test_time_series_query_builder_with_aggregation
    @redis.ts_create("temp:sensor1")

    # Add samples
    now = Time.now.to_i * 1000
    10.times do |i|
      @redis.ts_add("temp:sensor1", now + (i * 60_000), 20 + i)
    end

    # Query with aggregation
    result = @redis.ts_query("temp:sensor1")
      .from("-")
      .to("+")
      .aggregate(:avg, 300_000) # 5 minute buckets
      .execute

    assert_predicate result.length, :positive?
    assert_operator result.length, :<, 10 # Should be aggregated
  end

  def test_time_series_query_builder_multi_series
    # Create multiple series with labels
    @redis.ts_create("temp:sensor1", labels: { sensor: "temp", location: "room1" })
    @redis.ts_create("temp:sensor2", labels: { sensor: "temp", location: "room2" })
    @redis.ts_create("humidity:sensor1", labels: { sensor: "humidity", location: "room1" })

    # Add samples
    now = Time.now.to_i * 1000
    @redis.ts_add("temp:sensor1", now, 23.5)
    @redis.ts_add("temp:sensor2", now, 24.0)
    @redis.ts_add("humidity:sensor1", now, 60.0)

    # Query with filter
    result = @redis.ts_query
      .filter(sensor: "temp")
      .from("-")
      .to("+")
      .with_labels
      .execute

    assert_equal 2, result.length
  end

  def test_time_series_query_builder_reverse
    @redis.ts_create("temp:sensor1")

    # Add samples
    now = Time.now.to_i * 1000
    @redis.ts_add("temp:sensor1", now, 23.5)
    @redis.ts_add("temp:sensor1", now + 60_000, 24.0)
    @redis.ts_add("temp:sensor1", now + 120_000, 23.8)

    # Query in reverse
    result = @redis.ts_query("temp:sensor1")
      .from("-")
      .to("+")
      .reverse
      .execute

    assert_equal 3, result.length
    # First result should be the latest timestamp
    assert_operator result[0][0], :>, result[1][0]
  end

  def test_time_series_query_builder_limit
    @redis.ts_create("temp:sensor1")

    # Add samples
    now = Time.now.to_i * 1000
    10.times do |i|
      @redis.ts_add("temp:sensor1", now + (i * 60_000), 20 + i)
    end

    # Query with limit
    result = @redis.ts_query("temp:sensor1")
      .from("-")
      .to("+")
      .limit(5)
      .execute

    assert_equal 5, result.length
  end

  def test_time_series_proxy_range
    @redis.ts_create("temp:sensor1")

    # Add samples
    now = Time.now.to_i * 1000
    @redis.ts_add("temp:sensor1", now, 23.5)
    @redis.ts_add("temp:sensor1", now + 60_000, 24.0)
    @redis.ts_add("temp:sensor1", now + 120_000, 23.8)

    # Query with proxy range method
    result = @redis.ts("temp:sensor1")
      .range(from: "-", to: "+")
      .execute

    assert_equal 3, result.length
  end

  def test_time_series_proxy_reverse_range
    @redis.ts_create("temp:sensor1")

    # Add samples
    now = Time.now.to_i * 1000
    @redis.ts_add("temp:sensor1", now, 23.5)
    @redis.ts_add("temp:sensor1", now + 60_000, 24.0)
    @redis.ts_add("temp:sensor1", now + 120_000, 23.8)

    # Query in reverse with proxy
    result = @redis.ts("temp:sensor1")
      .reverse_range(from: "-", to: "+")
      .execute

    assert_equal 3, result.length
    # First result should be the latest timestamp
    assert_operator result[0][0], :>, result[1][0]
  end
end
