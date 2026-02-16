# frozen_string_literal: true

require_relative "../unit_test_helper"

class SetsUnitTest < Minitest::Test
  def test_responds_to_sadd
    client = RR::Client.new

    assert_respond_to client, :sadd
  end

  def test_responds_to_srem
    client = RR::Client.new

    assert_respond_to client, :srem
  end

  def test_responds_to_smembers
    client = RR::Client.new

    assert_respond_to client, :smembers
  end

  def test_responds_to_sismember
    client = RR::Client.new

    assert_respond_to client, :sismember
  end

  def test_responds_to_scard
    client = RR::Client.new

    assert_respond_to client, :scard
  end

  def test_responds_to_spop
    client = RR::Client.new

    assert_respond_to client, :spop
  end

  def test_responds_to_srandmember
    client = RR::Client.new

    assert_respond_to client, :srandmember
  end

  def test_responds_to_smove
    client = RR::Client.new

    assert_respond_to client, :smove
  end

  def test_responds_to_sdiff
    client = RR::Client.new

    assert_respond_to client, :sdiff
  end

  def test_responds_to_sdiffstore
    client = RR::Client.new

    assert_respond_to client, :sdiffstore
  end

  def test_responds_to_sinter
    client = RR::Client.new

    assert_respond_to client, :sinter
  end

  def test_responds_to_sinterstore
    client = RR::Client.new

    assert_respond_to client, :sinterstore
  end

  def test_responds_to_sunion
    client = RR::Client.new

    assert_respond_to client, :sunion
  end

  def test_responds_to_sunionstore
    client = RR::Client.new

    assert_respond_to client, :sunionstore
  end

  def test_responds_to_sscan
    client = RR::Client.new

    assert_respond_to client, :sscan
  end

  def test_responds_to_smismember
    client = RR::Client.new

    assert_respond_to client, :smismember
  end

  def test_responds_to_sintercard
    client = RR::Client.new

    assert_respond_to client, :sintercard
  end
end
