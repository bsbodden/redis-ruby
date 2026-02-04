# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../test_helper"

class ACLCommandsTest < Minitest::Test
  def setup
    @client = RedisRuby::Client.new
    @connection = mock("connection")
    @client.instance_variable_set(:@connection, @connection)
    @connection.stubs(:connected?).returns(true)
  end

  # --- ACL SETUSER ---

  def test_acl_setuser_basic
    @connection.expects(:call_direct).with("ACL", "SETUSER", "testuser", "on", ">password", "~*", "+@all")
      .returns("OK")
    result = @client.acl_setuser("testuser", "on", ">password", "~*", "+@all")
    assert_equal "OK", result
  end

  def test_acl_setuser_no_rules
    @connection.expects(:call_direct).with("ACL", "SETUSER", "testuser")
      .returns("OK")
    result = @client.acl_setuser("testuser")
    assert_equal "OK", result
  end

  # --- ACL GETUSER ---

  def test_acl_getuser
    expected = { "flags" => ["on"], "passwords" => [], "commands" => "+@all", "keys" => "~*" }
    @connection.expects(:call_direct).with("ACL", "GETUSER", "testuser").returns(expected)
    result = @client.acl_getuser("testuser")
    assert_equal expected, result
  end

  # --- ACL DELUSER ---

  def test_acl_deluser_single
    @connection.expects(:call_direct).with("ACL", "DELUSER", "testuser").returns(1)
    result = @client.acl_deluser("testuser")
    assert_equal 1, result
  end

  def test_acl_deluser_multiple
    @connection.expects(:call_direct).with("ACL", "DELUSER", "user1", "user2").returns(2)
    result = @client.acl_deluser("user1", "user2")
    assert_equal 2, result
  end

  # --- ACL LIST ---

  def test_acl_list
    expected = ["user default on ~* +@all"]
    @connection.expects(:call_direct).with("ACL", "LIST").returns(expected)
    result = @client.acl_list
    assert_equal expected, result
  end

  # --- ACL USERS ---

  def test_acl_users
    expected = ["default", "testuser"]
    @connection.expects(:call_direct).with("ACL", "USERS").returns(expected)
    result = @client.acl_users
    assert_equal expected, result
  end

  # --- ACL WHOAMI ---

  def test_acl_whoami
    @connection.expects(:call_direct).with("ACL", "WHOAMI").returns("default")
    result = @client.acl_whoami
    assert_equal "default", result
  end

  # --- ACL CAT ---

  def test_acl_cat_all
    expected = ["string", "hash", "list", "set", "sortedset"]
    @connection.expects(:call_direct).with("ACL", "CAT").returns(expected)
    result = @client.acl_cat
    assert_equal expected, result
  end

  def test_acl_cat_category
    expected = ["get", "set", "mget", "mset"]
    @connection.expects(:call_direct).with("ACL", "CAT", "string").returns(expected)
    result = @client.acl_cat("string")
    assert_equal expected, result
  end

  # --- ACL GENPASS ---

  def test_acl_genpass_default
    @connection.expects(:call_direct).with("ACL", "GENPASS").returns("abcdef1234567890")
    result = @client.acl_genpass
    assert_equal "abcdef1234567890", result
  end

  def test_acl_genpass_bits
    @connection.expects(:call_direct).with("ACL", "GENPASS", 128).returns("abcdef12")
    result = @client.acl_genpass(128)
    assert_equal "abcdef12", result
  end

  # --- ACL LOG ---

  def test_acl_log_all
    expected = [{ "reason" => "auth", "client-info" => "addr=127.0.0.1" }]
    @connection.expects(:call_direct).with("ACL", "LOG").returns(expected)
    result = @client.acl_log
    assert_equal expected, result
  end

  def test_acl_log_count
    expected = [{ "reason" => "auth" }]
    @connection.expects(:call_direct).with("ACL", "LOG", 5).returns(expected)
    result = @client.acl_log(5)
    assert_equal expected, result
  end

  def test_acl_log_reset
    @connection.expects(:call_direct).with("ACL", "LOG", "RESET").returns("OK")
    result = @client.acl_log_reset
    assert_equal "OK", result
  end

  # --- ACL SAVE / LOAD ---

  def test_acl_save
    @connection.expects(:call_direct).with("ACL", "SAVE").returns("OK")
    result = @client.acl_save
    assert_equal "OK", result
  end

  def test_acl_load
    @connection.expects(:call_direct).with("ACL", "LOAD").returns("OK")
    result = @client.acl_load
    assert_equal "OK", result
  end

  # --- ACL DRYRUN ---

  def test_acl_dryrun
    @connection.expects(:call_direct).with("ACL", "DRYRUN", "testuser", "SET", "foo", "bar")
      .returns("OK")
    result = @client.acl_dryrun("testuser", "SET", "foo", "bar")
    assert_equal "OK", result
  end

  def test_acl_dryrun_denied
    @connection.expects(:call_direct).with("ACL", "DRYRUN", "limited", "SET", "foo", "bar")
      .returns("User limited has no permissions to run the 'set' command")
    result = @client.acl_dryrun("limited", "SET", "foo", "bar")
    assert_equal "User limited has no permissions to run the 'set' command", result
  end
end
