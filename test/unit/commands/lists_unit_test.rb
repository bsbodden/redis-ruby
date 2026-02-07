# frozen_string_literal: true

require_relative "../unit_test_helper"

class ListsUnitTest < Minitest::Test
  def test_responds_to_lpush
    client = RedisRuby::Client.new

    assert_respond_to client, :lpush
  end

  def test_responds_to_rpush
    client = RedisRuby::Client.new

    assert_respond_to client, :rpush
  end

  def test_responds_to_lpop
    client = RedisRuby::Client.new

    assert_respond_to client, :lpop
  end

  def test_responds_to_rpop
    client = RedisRuby::Client.new

    assert_respond_to client, :rpop
  end

  def test_responds_to_lrange
    client = RedisRuby::Client.new

    assert_respond_to client, :lrange
  end

  def test_responds_to_llen
    client = RedisRuby::Client.new

    assert_respond_to client, :llen
  end

  def test_responds_to_lindex
    client = RedisRuby::Client.new

    assert_respond_to client, :lindex
  end

  def test_responds_to_lset
    client = RedisRuby::Client.new

    assert_respond_to client, :lset
  end

  def test_responds_to_linsert
    client = RedisRuby::Client.new

    assert_respond_to client, :linsert
  end

  def test_responds_to_ltrim
    client = RedisRuby::Client.new

    assert_respond_to client, :ltrim
  end

  def test_responds_to_lrem
    client = RedisRuby::Client.new

    assert_respond_to client, :lrem
  end

  def test_responds_to_blpop
    client = RedisRuby::Client.new

    assert_respond_to client, :blpop
  end

  def test_responds_to_brpop
    client = RedisRuby::Client.new

    assert_respond_to client, :brpop
  end

  def test_responds_to_lmove
    client = RedisRuby::Client.new

    assert_respond_to client, :lmove
  end

  def test_responds_to_blmove
    client = RedisRuby::Client.new

    assert_respond_to client, :blmove
  end

  def test_responds_to_lpos
    client = RedisRuby::Client.new

    assert_respond_to client, :lpos
  end

  def test_responds_to_lmpop
    client = RedisRuby::Client.new

    assert_respond_to client, :lmpop
  end

  def test_responds_to_blmpop
    client = RedisRuby::Client.new

    assert_respond_to client, :blmpop
  end

  def test_responds_to_lpushx
    client = RedisRuby::Client.new

    assert_respond_to client, :lpushx
  end

  def test_responds_to_rpushx
    client = RedisRuby::Client.new

    assert_respond_to client, :rpushx
  end
end
