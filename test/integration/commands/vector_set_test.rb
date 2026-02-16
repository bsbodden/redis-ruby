# frozen_string_literal: true

require "test_helper"

class VectorSetCommandsTest < RedisRubyTestCase
  use_testcontainers!

  def setup
    super
    @vset_key = "vset:test:#{SecureRandom.hex(4)}"

    # Check if Vector Set commands are available (Redis 8.0+)
    begin
      redis.vcard("__test_vset__")
    rescue RR::CommandError => e
      if e.message.include?("unknown command") || e.message.include?("ERR unknown")
        skip "Vector Set commands not available (requires Redis 8.0+)"
      end
    end
  end

  def teardown
    begin
      redis.del(@vset_key)
    rescue StandardError
      nil
    end
    super
  end

  # Helper to convert float array to FP32 blob
  def to_fp32_blob(float_array)
    float_array.pack("e*")
  end

  # Helper to validate quantized vectors with tolerance
  def vectors_close?(original, quantized, tolerance: 0.1)
    return false if original.length != quantized.length

    max_diff = original.zip(quantized).map { |o, q| (o - q).abs }.max
    max_diff <= tolerance
  end

  def test_vadd_with_values
    vector = [1.0, 2.0, 3.0]
    result = redis.vadd(@vset_key, vector, "elem1")

    assert_equal 1, result

    # Verify element was added
    card = redis.vcard(@vset_key)

    assert_equal 1, card
  end

  def test_vadd_with_fp32_blob
    vector = [1.0, 2.0, 3.0]
    fp32_blob = to_fp32_blob(vector)

    result = redis.vadd(@vset_key, fp32_blob, "elem_fp32")

    assert_equal 1, result

    card = redis.vcard(@vset_key)

    assert_equal 1, card
  end

  def test_vadd_update_existing
    vector1 = [1.0, 2.0, 3.0]
    vector2 = [4.0, 5.0, 6.0]

    # Add element
    redis.vadd(@vset_key, vector1, "elem1")

    # Update element (returns 0 for update)
    result = redis.vadd(@vset_key, vector2, "elem1")

    assert_equal 0, result

    # Still only 1 element
    card = redis.vcard(@vset_key)

    assert_equal 1, card
  end

  def test_vadd_with_attributes
    vector = [1.0, 2.0, 3.0]
    attrs = { category: "electronics", price: 99.99 }

    redis.vadd(@vset_key, vector, "product1", attributes: attrs)

    # Verify attributes
    retrieved_attrs = redis.vgetattr(@vset_key, "product1")

    assert_equal "electronics", retrieved_attrs["category"]
    assert_in_delta(99.99, retrieved_attrs["price"])
  end

  def test_vadd_with_quantization
    vector = [1.0, 2.0, 3.0, 4.0, 5.0]

    result = redis.vadd(@vset_key, vector, "quant_elem", quantization: "NOQUANT")

    assert_equal 1, result
  end

  def test_vadd_with_reduce_dim
    vector = [1.0, 2.0, 3.0, 4.0, 5.0]

    redis.vadd(@vset_key, vector, "reduced", reduce_dim: 3)

    dim = redis.vdim(@vset_key)

    assert_equal 3, dim
  end

  def test_vdim
    vector = [1.0, 2.0, 3.0, 4.0]
    redis.vadd(@vset_key, vector, "elem1")

    dim = redis.vdim(@vset_key)

    assert_equal 4, dim
  end

  def test_vcard
    redis.vadd(@vset_key, [1.0, 2.0], "a")
    redis.vadd(@vset_key, [3.0, 4.0], "b")
    redis.vadd(@vset_key, [5.0, 6.0], "c")

    card = redis.vcard(@vset_key)

    assert_equal 3, card
  end

  def test_vrem
    redis.vadd(@vset_key, [1.0, 2.0], "to_remove")

    assert_equal 1, redis.vcard(@vset_key)

    result = redis.vrem(@vset_key, "to_remove")

    assert_equal 1, result

    assert_equal 0, redis.vcard(@vset_key)
  end

  def test_vrem_nonexistent
    redis.vadd(@vset_key, [1.0, 2.0], "exists")

    result = redis.vrem(@vset_key, "does_not_exist")

    assert_equal 0, result
  end

  def test_vemb
    original = [1.0, 2.0, 3.0]
    redis.vadd(@vset_key, original, "elem1", quantization: "NOQUANT")

    emb = redis.vemb(@vset_key, "elem1")

    assert_kind_of Array, emb
    assert_equal 3, emb.length
    assert vectors_close?(original, emb, tolerance: 0.001)
  end

  def test_vemb_nonexistent
    redis.vadd(@vset_key, [1.0, 2.0], "exists")

    emb = redis.vemb(@vset_key, "nonexistent")

    assert_nil emb
  end

  def test_vemb_raw
    redis.vadd(@vset_key, [1.0, 2.0, 3.0], "elem1")

    raw = redis.vemb(@vset_key, "elem1", raw: true)

    assert_kind_of Hash, raw
    assert raw.key?("quantization")
    assert raw.key?("l2")
  end

  def test_vsim_basic
    # Add some vectors
    redis.vadd(@vset_key, [1.0, 0.0, 0.0], "x_axis")
    redis.vadd(@vset_key, [0.0, 1.0, 0.0], "y_axis")
    redis.vadd(@vset_key, [0.0, 0.0, 1.0], "z_axis")
    redis.vadd(@vset_key, [0.9, 0.1, 0.0], "near_x")

    # Search for similar to x_axis
    results = redis.vsim(@vset_key, [1.0, 0.0, 0.0], count: 2)

    assert_kind_of Array, results
    assert_equal 2, results.length
    assert_includes results, "x_axis"
    assert_includes results, "near_x"
  end

  def test_vsim_with_scores
    redis.vadd(@vset_key, [1.0, 0.0], "a")
    redis.vadd(@vset_key, [0.0, 1.0], "b")

    results = redis.vsim(@vset_key, [1.0, 0.0], with_scores: true, count: 2)

    assert_kind_of Hash, results
    assert results.key?("a")
    assert_kind_of Float, results["a"]
  end

  def test_vsim_by_element
    redis.vadd(@vset_key, [1.0, 0.0], "reference")
    redis.vadd(@vset_key, [0.9, 0.1], "similar")
    redis.vadd(@vset_key, [0.0, 1.0], "different")

    # Search using element name instead of vector
    results = redis.vsim(@vset_key, "reference", count: 2)

    assert_includes results, "reference"
    assert_includes results, "similar"
  end

  def test_vsim_with_attribs
    redis.vadd(@vset_key, [1.0, 0.0], "item1", attributes: { type: "a" })
    redis.vadd(@vset_key, [0.0, 1.0], "item2", attributes: { type: "b" })

    results = redis.vsim(@vset_key, [1.0, 0.0], with_attribs: true, count: 2)

    assert_kind_of Hash, results
    assert results["item1"]["type"] == "a" || results["item1"] == { "type" => "a" }
  end

  def test_vsim_with_filter
    redis.vadd(@vset_key, [1.0, 0.0], "cheap", attributes: { price: 10 })
    redis.vadd(@vset_key, [0.9, 0.1], "expensive", attributes: { price: 100 })

    # Filter by price
    results = redis.vsim(@vset_key, [1.0, 0.0],
                         filter: ".price < 50",
                         count: 10)

    assert_includes results, "cheap"
    refute_includes results, "expensive"
  end

  def test_vinfo
    redis.vadd(@vset_key, [1.0, 2.0, 3.0], "elem1")
    redis.vadd(@vset_key, [4.0, 5.0, 6.0], "elem2")

    info = redis.vinfo(@vset_key)

    assert_kind_of Hash, info
    # Should contain size/dimension info
    assert_predicate info.length, :positive?
  end

  def test_vsetattr
    redis.vadd(@vset_key, [1.0, 2.0], "elem1")

    result = redis.vsetattr(@vset_key, "elem1", { color: "red", size: "large" })

    assert_equal 1, result

    attrs = redis.vgetattr(@vset_key, "elem1")

    assert_equal "red", attrs["color"]
    assert_equal "large", attrs["size"]
  end

  def test_vsetattr_remove
    redis.vadd(@vset_key, [1.0, 2.0], "elem1", attributes: { key: "value" })

    # Remove attributes by setting empty hash
    redis.vsetattr(@vset_key, "elem1", {})

    attrs = redis.vgetattr(@vset_key, "elem1")

    assert_nil attrs
  end

  def test_vgetattr
    redis.vadd(@vset_key, [1.0, 2.0], "with_attrs", attributes: { a: 1, b: "two" })

    attrs = redis.vgetattr(@vset_key, "with_attrs")

    assert_equal 1, attrs["a"]
    assert_equal "two", attrs["b"]
  end

  def test_vgetattr_no_attrs
    redis.vadd(@vset_key, [1.0, 2.0], "no_attrs")

    attrs = redis.vgetattr(@vset_key, "no_attrs")

    assert_nil attrs
  end

  def test_vrandmember
    redis.vadd(@vset_key, [1.0, 0.0], "a")
    redis.vadd(@vset_key, [0.0, 1.0], "b")
    redis.vadd(@vset_key, [1.0, 1.0], "c")

    # Get single random member
    member = redis.vrandmember(@vset_key)

    assert_includes %w[a b c], member

    # Get multiple random members
    members = redis.vrandmember(@vset_key, 2)

    assert_equal 2, members.length
  end

  def test_vlinks
    # Create a set with enough elements to have links
    10.times do |i|
      redis.vadd(@vset_key, [i.to_f, (10 - i).to_f], "elem#{i}")
    end

    links = redis.vlinks(@vset_key, "elem5")

    # Links should be an array (one per level)
    assert_kind_of Array, links
  end

  def test_vadd_invalid_vector
    assert_raises(ArgumentError) do
      redis.vadd(@vset_key, nil, "elem1")
    end

    assert_raises(ArgumentError) do
      redis.vadd(@vset_key, 123, "elem1")
    end
  end
end
