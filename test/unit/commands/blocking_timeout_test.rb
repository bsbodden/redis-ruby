# frozen_string_literal: true

require_relative "../unit_test_helper"

# Tests for redis-rb issue #1279
# Blocking commands must add the command timeout to the socket read
# timeout to prevent premature ReadTimeoutError.
class BlockingTimeoutTest < Minitest::Test
  # Test that blocking commands use blocking_call with timeout
  # by verifying the method signature and delegation

  def test_blpop_calls_blocking_call_with_timeout
    client = RR::Client.new
    client.stubs(:ensure_connected)

    # Expect blocking_call to be invoked with the timeout value
    client.expects(:blocking_call).with(0, "BLPOP", "key", 0).returns(nil)
    client.blpop("key", timeout: 0)
  end

  def test_blpop_with_nonzero_timeout_passes_timeout
    client = RR::Client.new
    client.stubs(:ensure_connected)

    client.expects(:blocking_call).with(5, "BLPOP", "key", 5).returns(nil)
    client.blpop("key", timeout: 5)
  end

  def test_brpop_calls_blocking_call_with_timeout
    client = RR::Client.new
    client.stubs(:ensure_connected)

    client.expects(:blocking_call).with(10, "BRPOP", "list1", "list2", 10).returns(nil)
    client.brpop("list1", "list2", timeout: 10)
  end

  def test_brpoplpush_calls_blocking_call_with_timeout
    client = RR::Client.new
    client.stubs(:ensure_connected)

    client.expects(:blocking_call).with(5, "BRPOPLPUSH", "src", "dst", 5).returns(nil)
    client.brpoplpush("src", "dst", timeout: 5)
  end

  def test_blmove_calls_blocking_call_with_timeout
    client = RR::Client.new
    client.stubs(:ensure_connected)

    client.expects(:blocking_call).with(3, "BLMOVE", "src", "dst", "LEFT", "RIGHT", 3).returns(nil)
    client.blmove("src", "dst", :left, :right, timeout: 3)
  end

  def test_bzpopmin_calls_blocking_call_with_timeout
    client = RR::Client.new
    client.stubs(:ensure_connected)

    client.expects(:blocking_call).with(5, "BZPOPMIN", "zset", 5).returns(nil)
    client.bzpopmin("zset", timeout: 5)
  end

  def test_bzpopmax_calls_blocking_call_with_timeout
    client = RR::Client.new
    client.stubs(:ensure_connected)

    client.expects(:blocking_call).with(5, "BZPOPMAX", "zset", 5).returns(nil)
    client.bzpopmax("zset", timeout: 5)
  end

  def test_blocking_call_method_exists
    client = RR::Client.new

    assert_respond_to client, :blocking_call
  end
end
