# frozen_string_literal: true

require "test_helper"

class StreamsDSLTest < RedisRubyTestCase
  use_testcontainers!

  def setup
    super
    @stream_key = "test:stream:#{SecureRandom.hex(8)}"
  end

  def teardown
    begin
      # Clean up consumer groups
      begin
        redis.xgroup_destroy(@stream_key, "testgroup")
      rescue StandardError
        nil
      end
      redis.del(@stream_key)
    rescue StandardError
      nil
    end
    super
  end

  # ============================================================
  # StreamProxy Tests
  # ============================================================

  def test_stream_proxy_creation
    stream = redis.stream(:events)

    assert_instance_of RR::DSL::StreamProxy, stream
    assert_equal "events", stream.key
  end

  def test_stream_proxy_composite_key
    stream = redis.stream(:metrics, :temperature, :sensor1)

    assert_equal "metrics:temperature:sensor1", stream.key
  end

  def test_stream_add
    stream = redis.stream(@stream_key)
    result = stream.add(sensor: "temp", value: 23.5)

    assert_equal stream, result # Returns self for chaining
    assert_equal 1, redis.xlen(@stream_key)
  end

  def test_stream_add_chainable
    stream = redis.stream(@stream_key)
    stream.add(sensor: "temp", value: 23.5)
      .add(sensor: "humidity", value: 65)
      .add(sensor: "pressure", value: 1013)

    assert_equal 3, redis.xlen(@stream_key)
  end

  def test_stream_add_with_options
    stream = redis.stream(@stream_key)
    stream.add({ temp: 23.5 }, entry_id: "1000-0")

    entries = redis.xrange(@stream_key, "-", "+")

    assert_equal "1000-0", entries[0][0]
  end

  def test_stream_length
    stream = redis.stream(@stream_key)
    stream.add(a: 1).add(b: 2).add(c: 3)

    assert_equal 3, stream.length
    assert_equal 3, stream.size
    assert_equal 3, stream.count
  end

  def test_stream_trim
    stream = redis.stream(@stream_key)
    10.times { |i| stream.add(i: i) }

    deleted = stream.trim(maxlen: 5)

    assert_operator deleted, :>=, 5
    assert_operator stream.length, :<=, 5
  end

  def test_stream_delete
    stream = redis.stream(@stream_key)
    id1 = redis.xadd(@stream_key, { a: 1 })
    id2 = redis.xadd(@stream_key, { b: 2 })

    deleted = stream.delete(id1, id2)

    assert_equal 2, deleted
    assert_equal 0, stream.length
  end

  def test_stream_info
    stream = redis.stream(@stream_key)
    stream.add(a: 1)

    info = stream.info

    assert_kind_of Hash, info
    assert_equal 1, info["length"]
  end
  # ============================================================
  # StreamReader Tests
  # ============================================================

  def test_stream_read_from
    stream = redis.stream(@stream_key)
    redis.xadd(@stream_key, { a: 1 }, id: "1-0")
    redis.xadd(@stream_key, { b: 2 }, id: "2-0")
    redis.xadd(@stream_key, { c: 3 }, id: "3-0")

    entries = stream.read.from("1-0").execute

    assert_equal 2, entries.length
    assert_equal "2-0", entries[0][0]
  end

  def test_stream_read_range
    stream = redis.stream(@stream_key)
    redis.xadd(@stream_key, { a: 1 }, id: "1-0")
    redis.xadd(@stream_key, { b: 2 }, id: "2-0")
    redis.xadd(@stream_key, { c: 3 }, id: "3-0")

    entries = stream.read.range("-", "+").execute

    assert_equal 3, entries.length
  end

  def test_stream_read_reverse_range
    stream = redis.stream(@stream_key)
    redis.xadd(@stream_key, { a: 1 }, id: "1-0")
    redis.xadd(@stream_key, { b: 2 }, id: "2-0")
    redis.xadd(@stream_key, { c: 3 }, id: "3-0")

    entries = stream.read.reverse_range("+", "-").execute

    assert_equal 3, entries.length
    assert_equal "3-0", entries[0][0] # Reverse order
  end

  def test_stream_read_count
    stream = redis.stream(@stream_key)
    5.times { |i| redis.xadd(@stream_key, { i: i }) }

    entries = stream.read.from("0-0").count(2).execute

    assert_equal 2, entries.length
  end

  def test_stream_read_each
    stream = redis.stream(@stream_key)
    redis.xadd(@stream_key, { a: 1 }, id: "1-0")
    redis.xadd(@stream_key, { b: 2 }, id: "2-0")

    ids = stream.read.range("-", "+").enum_for(:each).map(&:first)

    assert_equal %w[1-0 2-0], ids
  end
end

class StreamsDSLTestPart2 < RedisRubyTestCase
  use_testcontainers!

  def setup
    super
    @stream_key = "test:stream:#{SecureRandom.hex(8)}"
  end

  def teardown
    begin
      # Clean up consumer groups
      begin
        redis.xgroup_destroy(@stream_key, "testgroup")
      rescue StandardError
        nil
      end
      redis.del(@stream_key)
    rescue StandardError
      nil
    end
    super
  end

  # ============================================================
  # StreamProxy Tests
  # ============================================================

  # ============================================================
  # ConsumerGroupBuilder Tests
  # ============================================================

  def test_consumer_group_create_from
    redis.xadd(@stream_key, { a: 1 })

    result = redis.consumer_group(@stream_key, :testgroup) do
      create_from "$"
    end

    assert_equal "OK", result

    groups = redis.xinfo_groups(@stream_key)

    assert_equal 1, groups.length
    assert_equal "testgroup", groups[0]["name"]
  end

  def test_consumer_group_create_from_beginning
    redis.xadd(@stream_key, { a: 1 })

    redis.consumer_group(@stream_key, :testgroup) do
      create_from_beginning
    end

    groups = redis.xinfo_groups(@stream_key)

    assert_equal "testgroup", groups[0]["name"]
  end

  def test_consumer_group_create_from_now
    redis.xadd(@stream_key, { a: 1 })

    redis.consumer_group(@stream_key, :testgroup) do
      create_from_now
    end

    groups = redis.xinfo_groups(@stream_key)

    assert_equal "testgroup", groups[0]["name"]
  end

  def test_consumer_group_create_with_mkstream
    result = redis.consumer_group("#{@stream_key}:new", :testgroup) do
      create_from "$", mkstream: true
    end

    assert_equal "OK", result
    redis.del("#{@stream_key}:new")
  end

  def test_consumer_group_destroy
    redis.xadd(@stream_key, { a: 1 })
    redis.xgroup_create(@stream_key, "testgroup", "$")

    result = redis.consumer_group(@stream_key, :testgroup) do
      destroy
    end

    assert_equal 1, result
  end

  def test_consumer_group_set_id
    redis.xadd(@stream_key, { a: 1 })
    redis.xgroup_create(@stream_key, "testgroup", "0")

    result = redis.consumer_group(@stream_key, :testgroup) do
      set_id "$"
    end

    assert_equal "OK", result
  end

  def test_consumer_group_create_consumer
    redis.xadd(@stream_key, { a: 1 })
    redis.xgroup_create(@stream_key, "testgroup", "$")

    result = redis.consumer_group(@stream_key, :testgroup) do
      create_consumer :worker1
    end

    assert_equal 1, result
  end

  def test_consumer_group_delete_consumer
    redis.xadd(@stream_key, { a: 1 })
    redis.xgroup_create(@stream_key, "testgroup", "$")
    redis.xgroup_createconsumer(@stream_key, "testgroup", "worker1")

    result = redis.consumer_group(@stream_key, :testgroup) do
      delete_consumer :worker1
    end

    assert_kind_of Integer, result
  end
end

class StreamsDSLTestPart3 < RedisRubyTestCase
  use_testcontainers!

  def setup
    super
    @stream_key = "test:stream:#{SecureRandom.hex(8)}"
  end

  def teardown
    begin
      # Clean up consumer groups
      begin
        redis.xgroup_destroy(@stream_key, "testgroup")
      rescue StandardError
        nil
      end
      redis.del(@stream_key)
    rescue StandardError
      nil
    end
    super
  end

  # ============================================================
  # StreamProxy Tests
  # ============================================================

  # ============================================================
  # ConsumerProxy Tests
  # ============================================================

  def test_consumer_proxy_creation
    stream = redis.stream(@stream_key)
    consumer = stream.consumer(:mygroup, :worker1)

    assert_instance_of RR::DSL::ConsumerProxy, consumer
    assert_equal @stream_key, consumer.stream_key
    assert_equal "mygroup", consumer.group_name
    assert_equal "worker1", consumer.consumer_name
  end

  def test_consumer_read
    redis.xadd(@stream_key, { a: 1 })
    redis.xgroup_create(@stream_key, "testgroup", "0")

    consumer = redis.stream(@stream_key).consumer(:testgroup, :worker1)
    entries = consumer.read.count(10).execute

    assert_equal 1, entries.length
  end

  def test_consumer_read_new_only
    redis.xadd(@stream_key, { a: 1 })
    redis.xgroup_create(@stream_key, "testgroup", "$")
    redis.xadd(@stream_key, { b: 2 })

    consumer = redis.stream(@stream_key).consumer(:testgroup, :worker1)
    entries = consumer.read.new_only.execute

    assert_equal 1, entries.length
    assert_equal({ "b" => "2" }, entries[0][1])
  end

  def test_consumer_read_pending_only
    redis.xadd(@stream_key, { a: 1 })
    redis.xgroup_create(@stream_key, "testgroup", "0")

    consumer = redis.stream(@stream_key).consumer(:testgroup, :worker1)
    # Read to create pending
    consumer.read.new_only.execute

    # Read pending
    entries = consumer.read.pending_only.execute

    assert_equal 1, entries.length
  end

  def test_consumer_ack
    redis.xadd(@stream_key, { a: 1 })
    redis.xgroup_create(@stream_key, "testgroup", "0")

    consumer = redis.stream(@stream_key).consumer(:testgroup, :worker1)
    entries = consumer.read.execute
    id = entries[0][0]

    acked = consumer.ack(id)

    assert_equal 1, acked
  end

  def test_consumer_pending
    redis.xadd(@stream_key, { a: 1 })
    redis.xgroup_create(@stream_key, "testgroup", "0")

    consumer = redis.stream(@stream_key).consumer(:testgroup, :worker1)
    consumer.read.execute

    pending = consumer.pending

    assert_kind_of Array, pending
  end
  # ============================================================
  # MultiStreamReader Tests
  # ============================================================

  def test_multi_stream_reader_creation
    reader = redis.streams(events: "0-0", metrics: "0-0")

    assert_instance_of RR::DSL::MultiStreamReader, reader
  end

  def test_multi_stream_read
    stream1 = "#{@stream_key}:1"
    stream2 = "#{@stream_key}:2"

    redis.xadd(stream1, { a: 1 })
    redis.xadd(stream2, { b: 2 })

    results = redis.streams(stream1 => "0-0", stream2 => "0-0").execute

    assert_kind_of Hash, results
    assert_equal 2, results.keys.length
    assert_equal 1, results[stream1].length
    assert_equal 1, results[stream2].length

    redis.del(stream1, stream2)
  end

  def test_multi_stream_read_with_count
    stream1 = "#{@stream_key}:1"
    stream2 = "#{@stream_key}:2"

    3.times { redis.xadd(stream1, { a: 1 }) }
    3.times { redis.xadd(stream2, { b: 2 }) }

    results = redis.streams(stream1 => "0-0", stream2 => "0-0").count(2).execute

    assert_operator results[stream1].length, :<=, 2
    assert_operator results[stream2].length, :<=, 2

    redis.del(stream1, stream2)
  end

  def test_multi_stream_each
    stream1 = "#{@stream_key}:1"
    stream2 = "#{@stream_key}:2"

    redis.xadd(stream1, { a: 1 })
    redis.xadd(stream2, { b: 2 })

    count = 0
    redis.streams(stream1 => "0-0", stream2 => "0-0").each do |_stream, _id, _fields|
      count += 1
    end

    assert_equal 2, count

    redis.del(stream1, stream2)
  end

  def test_multi_stream_each_stream
    stream1 = "#{@stream_key}:1"
    stream2 = "#{@stream_key}:2"

    redis.xadd(stream1, { a: 1 })
    redis.xadd(stream2, { b: 2 })

    streams = []
    redis.streams(stream1 => "0-0", stream2 => "0-0").each_stream do |stream, _entries|
      streams << stream
    end

    assert_equal 2, streams.length

    redis.del(stream1, stream2)
  end
end

class StreamsDSLTestPart4 < RedisRubyTestCase
  use_testcontainers!

  def setup
    super
    @stream_key = "test:stream:#{SecureRandom.hex(8)}"
  end

  def teardown
    begin
      # Clean up consumer groups
      begin
        redis.xgroup_destroy(@stream_key, "testgroup")
      rescue StandardError
        nil
      end
      redis.del(@stream_key)
    rescue StandardError
      nil
    end
    super
  end

  # ============================================================
  # StreamProxy Tests
  # ============================================================

  # ============================================================
  # Integration Tests
  # ============================================================

  def test_full_workflow
    # Create stream and add entries
    stream = redis.stream(@stream_key)
    stream.add(sensor: "temp", value: 23.5)
      .add(sensor: "humidity", value: 65)
      .add(sensor: "pressure", value: 1013)

    # Create consumer group
    redis.consumer_group(@stream_key, :processors) do
      create_from_beginning
    end

    # Read as consumer
    consumer = stream.consumer(:processors, :worker1)
    entries = consumer.read.count(10).execute

    assert_equal 3, entries.length

    # Acknowledge entries
    ids = entries.map(&:first)
    acked = consumer.ack(*ids)

    assert_equal 3, acked
  end

  def test_chainable_workflow
    result = redis.stream(@stream_key)
      .add(a: 1)
      .add(b: 2)
      .add(c: 3)

    assert_instance_of RR::DSL::StreamProxy, result
    assert_equal 3, redis.xlen(@stream_key)
  end
end
