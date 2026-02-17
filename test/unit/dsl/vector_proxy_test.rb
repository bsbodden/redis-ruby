# frozen_string_literal: true

require_relative "../unit_test_helper"

class VectorProxyMutationTest < Minitest::Test
  def setup
    @mock_client = mock("client")
    @mock_client.stubs(:vadd)
  end

  def test_add_many_does_not_mutate_input_hashes
    proxy = RR::DSL::VectorProxy.new(@mock_client, "my_vectors")
    input = [
      { id: "doc1", vector: [0.1, 0.2], category: "tech" },
      { id: "doc2", vector: [0.3, 0.4], category: "books" },
    ]
    original = input.map(&:dup)

    proxy.add_many(input)

    # Input hashes should not be modified
    assert_equal original[0], input[0], "add_many mutated the first input hash"
    assert_equal original[1], input[1], "add_many mutated the second input hash"
  end
end
