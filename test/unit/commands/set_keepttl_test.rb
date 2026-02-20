# frozen_string_literal: true

require_relative "../unit_test_helper"

# Tests for redis-rb issue #1203
# SET with keepttl: true must include KEEPTTL option and return "OK".
class SetKeepttlTest < Minitest::Test
  class MockClient
    include RR::Commands::Strings

    attr_reader :last_command

    def call(*args)
      @last_command = args
      "OK"
    end

    def call_1arg(cmd, arg_one)
      @last_command = [cmd, arg_one]
      "OK"
    end

    def call_2args(cmd, arg_one, arg_two)
      @last_command = [cmd, arg_one, arg_two]
      "OK"
    end

    def call_3args(cmd, arg_one, arg_two, arg_three)
      @last_command = [cmd, arg_one, arg_two, arg_three]
      "OK"
    end
  end

  def setup
    @client = MockClient.new
  end

  def test_set_with_keepttl_sends_keepttl_option
    @client.set("key", "value", keepttl: true)

    assert_equal "SET", @client.last_command[0]
    assert_includes @client.last_command, "KEEPTTL"
  end

  def test_set_with_keepttl_returns_ok
    result = @client.set("key", "value", keepttl: true)

    assert_equal "OK", result
  end

  def test_set_with_keepttl_and_xx
    @client.set("key", "value", keepttl: true, xx: true)

    assert_includes @client.last_command, "KEEPTTL"
    assert_includes @client.last_command, "XX"
  end

  def test_set_without_keepttl_does_not_include_option
    @client.set("key", "value")

    refute_includes(@client.last_command, "KEEPTTL")
  end

  def test_set_with_keepttl_false_does_not_include_option
    @client.set("key", "value", keepttl: false)

    refute_includes(@client.last_command, "KEEPTTL")
  end

  def test_set_with_keepttl_and_get
    @client.set("key", "new_value", keepttl: true, get: true)

    assert_includes @client.last_command, "KEEPTTL"
    assert_includes @client.last_command, "GET"
  end
end
