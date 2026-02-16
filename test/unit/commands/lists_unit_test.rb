# frozen_string_literal: true

require_relative "../unit_test_helper"

class ListsUnitTest < Minitest::Test
  def test_responds_to_lpush
    client = RR::Client.new

    assert_respond_to client, :lpush
  end

  def test_responds_to_rpush
    client = RR::Client.new

    assert_respond_to client, :rpush
  end

  def test_responds_to_lpop
    client = RR::Client.new

    assert_respond_to client, :lpop
  end

  def test_responds_to_rpop
    client = RR::Client.new

    assert_respond_to client, :rpop
  end

  def test_responds_to_lrange
    client = RR::Client.new

    assert_respond_to client, :lrange
  end

  def test_responds_to_llen
    client = RR::Client.new

    assert_respond_to client, :llen
  end

  def test_responds_to_lindex
    client = RR::Client.new

    assert_respond_to client, :lindex
  end

  def test_responds_to_lset
    client = RR::Client.new

    assert_respond_to client, :lset
  end

  def test_responds_to_linsert
    client = RR::Client.new

    assert_respond_to client, :linsert
  end

  def test_responds_to_ltrim
    client = RR::Client.new

    assert_respond_to client, :ltrim
  end

  def test_responds_to_lrem
    client = RR::Client.new

    assert_respond_to client, :lrem
  end

  def test_responds_to_blpop
    client = RR::Client.new

    assert_respond_to client, :blpop
  end

  def test_responds_to_brpop
    client = RR::Client.new

    assert_respond_to client, :brpop
  end

  def test_responds_to_lmove
    client = RR::Client.new

    assert_respond_to client, :lmove
  end

  def test_responds_to_blmove
    client = RR::Client.new

    assert_respond_to client, :blmove
  end

  def test_responds_to_lpos
    client = RR::Client.new

    assert_respond_to client, :lpos
  end

  def test_responds_to_lmpop
    client = RR::Client.new

    assert_respond_to client, :lmpop
  end

  def test_responds_to_blmpop
    client = RR::Client.new

    assert_respond_to client, :blmpop
  end

  def test_responds_to_lpushx
    client = RR::Client.new

    assert_respond_to client, :lpushx
  end

  def test_responds_to_rpushx
    client = RR::Client.new

    assert_respond_to client, :rpushx
  end
end
