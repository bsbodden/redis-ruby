# frozen_string_literal: true

require_relative "unit_test_helper"

# Tests for redis-rb issues #1235 and #1144
# Configuration and command argument validation.
class InputValidationTest < Minitest::Test
  # --- DB option validation (redis-rb #1235) ---

  def test_db_must_be_integer
    assert_raises(ArgumentError) do
      RR::Client.new(db: "mydb")
    end
  end

  def test_db_string_error_message_is_descriptive
    error = assert_raises(ArgumentError) do
      RR::Client.new(db: "mydb")
    end

    assert_match(/db must be an Integer/, error.message)
  end

  def test_db_as_float_raises_error
    assert_raises(ArgumentError) do
      RR::Client.new(db: 1.5)
    end
  end

  def test_db_as_nil_raises_error
    assert_raises(ArgumentError) do
      RR::Client.new(db: nil)
    end
  end

  def test_db_negative_raises_error
    assert_raises(ArgumentError) do
      RR::Client.new(db: -1)
    end
  end

  def test_db_zero_is_valid
    client = RR::Client.new(db: 0)

    assert_equal 0, client.instance_variable_get(:@db)
  end

  def test_db_positive_integer_is_valid
    client = RR::Client.new(db: 5)

    assert_equal 5, client.instance_variable_get(:@db)
  end

  # --- Port validation ---

  def test_port_must_be_integer
    assert_raises(ArgumentError) do
      RR::Client.new(port: "6379")
    end
  end

  def test_port_positive_integer_is_valid
    client = RR::Client.new(port: 6380)

    assert_equal 6380, client.instance_variable_get(:@port)
  end

  # --- Timeout validation ---

  def test_timeout_must_be_numeric
    assert_raises(ArgumentError) do
      RR::Client.new(timeout: "5")
    end
  end

  def test_timeout_as_integer_is_valid
    client = RR::Client.new(timeout: 5)

    assert_equal 5, client.instance_variable_get(:@timeout)
  end

  def test_timeout_as_float_is_valid
    client = RR::Client.new(timeout: 2.5)

    assert_in_delta(2.5, client.instance_variable_get(:@timeout))
  end
end
