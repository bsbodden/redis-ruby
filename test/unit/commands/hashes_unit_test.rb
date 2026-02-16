# frozen_string_literal: true

require_relative "../unit_test_helper"

class HashesUnitTest < Minitest::Test
  def test_responds_to_hget
    client = RR::Client.new

    assert_respond_to client, :hget
  end

  def test_responds_to_hset
    client = RR::Client.new

    assert_respond_to client, :hset
  end

  def test_responds_to_hsetnx
    client = RR::Client.new

    assert_respond_to client, :hsetnx
  end

  def test_responds_to_hdel
    client = RR::Client.new

    assert_respond_to client, :hdel
  end

  def test_responds_to_hexists
    client = RR::Client.new

    assert_respond_to client, :hexists
  end

  def test_responds_to_hgetall
    client = RR::Client.new

    assert_respond_to client, :hgetall
  end

  def test_responds_to_hincrby
    client = RR::Client.new

    assert_respond_to client, :hincrby
  end

  def test_responds_to_hincrbyfloat
    client = RR::Client.new

    assert_respond_to client, :hincrbyfloat
  end

  def test_responds_to_hkeys
    client = RR::Client.new

    assert_respond_to client, :hkeys
  end

  def test_responds_to_hlen
    client = RR::Client.new

    assert_respond_to client, :hlen
  end

  def test_responds_to_hmget
    client = RR::Client.new

    assert_respond_to client, :hmget
  end

  def test_responds_to_hmset
    client = RR::Client.new

    assert_respond_to client, :hmset
  end

  def test_responds_to_hvals
    client = RR::Client.new

    assert_respond_to client, :hvals
  end

  def test_responds_to_hscan
    client = RR::Client.new

    assert_respond_to client, :hscan
  end

  def test_responds_to_hstrlen
    client = RR::Client.new

    assert_respond_to client, :hstrlen
  end

  def test_responds_to_hrandfield
    client = RR::Client.new

    assert_respond_to client, :hrandfield
  end
end
