# frozen_string_literal: true

require_relative "../unit_test_helper"

class SetsUnitTest < Minitest::Test
  def test_responds_to_sadd
    client = RedisRuby::Client.new
    assert_respond_to client, :sadd
  end

  def test_responds_to_srem
    client = RedisRuby::Client.new
    assert_respond_to client, :srem
  end

  def test_responds_to_smembers
    client = RedisRuby::Client.new
    assert_respond_to client, :smembers
  end

  def test_responds_to_sismember
    client = RedisRuby::Client.new
    assert_respond_to client, :sismember
  end

  def test_responds_to_scard
    client = RedisRuby::Client.new
    assert_respond_to client, :scard
  end

  def test_responds_to_spop
    client = RedisRuby::Client.new
    assert_respond_to client, :spop
  end

  def test_responds_to_srandmember
    client = RedisRuby::Client.new
    assert_respond_to client, :srandmember
  end

  def test_responds_to_smove
    client = RedisRuby::Client.new
    assert_respond_to client, :smove
  end

  def test_responds_to_sdiff
    client = RedisRuby::Client.new
    assert_respond_to client, :sdiff
  end

  def test_responds_to_sdiffstore
    client = RedisRuby::Client.new
    assert_respond_to client, :sdiffstore
  end

  def test_responds_to_sinter
    client = RedisRuby::Client.new
    assert_respond_to client, :sinter
  end

  def test_responds_to_sinterstore
    client = RedisRuby::Client.new
    assert_respond_to client, :sinterstore
  end

  def test_responds_to_sunion
    client = RedisRuby::Client.new
    assert_respond_to client, :sunion
  end

  def test_responds_to_sunionstore
    client = RedisRuby::Client.new
    assert_respond_to client, :sunionstore
  end

  def test_responds_to_sscan
    client = RedisRuby::Client.new
    assert_respond_to client, :sscan
  end

  def test_responds_to_smismember
    client = RedisRuby::Client.new
    assert_respond_to client, :smismember
  end

  def test_responds_to_sintercard
    client = RedisRuby::Client.new
    assert_respond_to client, :sintercard
  end
end
