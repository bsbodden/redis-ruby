# frozen_string_literal: true

require_relative "unit_test_helper"

# Tests for redis-rb issue #1306
# Nested multi calls must raise ArgumentError client-side
# rather than sending MULTI twice to the server.
# Follows redis-py's approach of client-side prevention.
class NestedMultiTest < Minitest::Test
  def test_transaction_is_always_in_multi_state
    connection = mock("connection")
    tx = RR::Transaction.new(connection)

    assert tx.in_multi?
  end

  def test_transaction_multi_not_allowed_inside_transaction
    # The Transaction object represents an already-started MULTI block,
    # so calling multi on it should raise
    connection = mock("connection")
    tx = RR::Transaction.new(connection)

    assert_raises(ArgumentError) do
      tx.multi { |_inner| }
    end
  end

  def test_nested_multi_error_message_is_descriptive
    connection = mock("connection")
    tx = RR::Transaction.new(connection)

    error = assert_raises(ArgumentError) do
      tx.multi { |_inner| }
    end

    assert_match(/MULTI calls cannot be nested/, error.message)
  end
end
