# frozen_string_literal: true

require_relative "../unit_test_helper"

class HashesUnitTest < Minitest::Test
  def test_responds_to_hget
    client = RedisRuby::Client.new
    assert_respond_to client, :hget
  end

  def test_responds_to_hset
    client = RedisRuby::Client.new
    assert_respond_to client, :hset
  end

  def test_responds_to_hsetnx
    client = RedisRuby::Client.new
    assert_respond_to client, :hsetnx
  end

  def test_responds_to_hdel
    client = RedisRuby::Client.new
    assert_respond_to client, :hdel
  end

  def test_responds_to_hexists
    client = RedisRuby::Client.new
    assert_respond_to client, :hexists
  end

  def test_responds_to_hgetall
    client = RedisRuby::Client.new
    assert_respond_to client, :hgetall
  end

  def test_responds_to_hincrby
    client = RedisRuby::Client.new
    assert_respond_to client, :hincrby
  end

  def test_responds_to_hincrbyfloat
    client = RedisRuby::Client.new
    assert_respond_to client, :hincrbyfloat
  end

  def test_responds_to_hkeys
    client = RedisRuby::Client.new
    assert_respond_to client, :hkeys
  end

  def test_responds_to_hlen
    client = RedisRuby::Client.new
    assert_respond_to client, :hlen
  end

  def test_responds_to_hmget
    client = RedisRuby::Client.new
    assert_respond_to client, :hmget
  end

  def test_responds_to_hmset
    client = RedisRuby::Client.new
    assert_respond_to client, :hmset
  end

  def test_responds_to_hvals
    client = RedisRuby::Client.new
    assert_respond_to client, :hvals
  end

  def test_responds_to_hscan
    client = RedisRuby::Client.new
    assert_respond_to client, :hscan
  end

  def test_responds_to_hstrlen
    client = RedisRuby::Client.new
    assert_respond_to client, :hstrlen
  end

  def test_responds_to_hrandfield
    client = RedisRuby::Client.new
    assert_respond_to client, :hrandfield
  end
end
