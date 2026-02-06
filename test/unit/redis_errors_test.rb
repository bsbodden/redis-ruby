# frozen_string_literal: true

require_relative "unit_test_helper"

# Load the Redis compat layer
require_relative "../../lib/redis/errors"

class RedisErrorsTest < Minitest::Test
  # ============================================================
  # Error class hierarchy
  # ============================================================

  def test_base_error_inherits_from_standard_error
    assert Redis::BaseError < StandardError
  end

  def test_command_error_inherits_from_base_error
    assert Redis::CommandError < Redis::BaseError
  end

  def test_connection_error_inherits_from_base_error
    assert Redis::ConnectionError < Redis::BaseError
  end

  def test_timeout_error_inherits_from_base_error
    assert Redis::TimeoutError < Redis::BaseError
  end

  def test_authentication_error_inherits_from_command_error
    assert Redis::AuthenticationError < Redis::CommandError
  end

  def test_permission_error_inherits_from_command_error
    assert Redis::PermissionError < Redis::CommandError
  end

  def test_wrong_type_error_inherits_from_command_error
    assert Redis::WrongTypeError < Redis::CommandError
  end

  def test_cluster_error_inherits_from_base_error
    assert Redis::ClusterError < Redis::BaseError
  end

  def test_cluster_down_error_inherits_from_cluster_error
    assert Redis::ClusterDownError < Redis::ClusterError
  end

  def test_protocol_error_inherits_from_base_error
    assert Redis::ProtocolError < Redis::BaseError
  end

  # ============================================================
  # MovedError
  # ============================================================

  def test_moved_error_parses_correctly
    error = Redis::MovedError.new("MOVED 12345 127.0.0.1:6379")
    assert_equal 12_345, error.slot
    assert_equal "127.0.0.1", error.host
    assert_equal 6379, error.port
  end

  def test_moved_error_preserves_message
    error = Redis::MovedError.new("MOVED 12345 127.0.0.1:6379")
    assert_equal "MOVED 12345 127.0.0.1:6379", error.message
  end

  def test_moved_error_non_matching_message
    error = Redis::MovedError.new("some other error")
    assert_nil error.slot
    assert_nil error.host
    assert_nil error.port
  end

  def test_moved_error_inherits_from_cluster_error
    assert Redis::MovedError < Redis::ClusterError
  end

  # ============================================================
  # AskError
  # ============================================================

  def test_ask_error_parses_correctly
    error = Redis::AskError.new("ASK 5000 192.168.1.1:7000")
    assert_equal 5000, error.slot
    assert_equal "192.168.1.1", error.host
    assert_equal 7000, error.port
  end

  def test_ask_error_preserves_message
    error = Redis::AskError.new("ASK 5000 192.168.1.1:7000")
    assert_equal "ASK 5000 192.168.1.1:7000", error.message
  end

  def test_ask_error_non_matching_message
    error = Redis::AskError.new("unrelated error")
    assert_nil error.slot
    assert_nil error.host
    assert_nil error.port
  end

  def test_ask_error_inherits_from_cluster_error
    assert Redis::AskError < Redis::ClusterError
  end

  # ============================================================
  # FutureNotReady
  # ============================================================

  def test_future_not_ready_has_message
    error = Redis::FutureNotReady.new
    assert_equal "Value will be available once the pipeline executes", error.message
  end

  def test_future_not_ready_inherits_from_runtime_error
    assert Redis::FutureNotReady < RuntimeError
  end

  # ============================================================
  # ErrorTranslation.translate
  # ============================================================

  def test_translate_connection_error
    original = RedisRuby::ConnectionError.new("connection lost")
    translated = Redis::ErrorTranslation.translate(original)
    assert_instance_of Redis::ConnectionError, translated
    assert_equal "connection lost", translated.message
  end

  def test_translate_timeout_error
    original = RedisRuby::TimeoutError.new("timed out")
    translated = Redis::ErrorTranslation.translate(original)
    assert_instance_of Redis::TimeoutError, translated
    assert_equal "timed out", translated.message
  end

  def test_translate_command_error_generic
    original = RedisRuby::CommandError.new("ERR something failed")
    translated = Redis::ErrorTranslation.translate(original)
    assert_instance_of Redis::CommandError, translated
    assert_equal "ERR something failed", translated.message
  end

  def test_translate_command_error_wrongtype
    original = RedisRuby::CommandError.new("WRONGTYPE Operation against a key")
    translated = Redis::ErrorTranslation.translate(original)
    assert_instance_of Redis::WrongTypeError, translated
  end

  def test_translate_command_error_noauth
    original = RedisRuby::CommandError.new("NOAUTH Authentication required")
    translated = Redis::ErrorTranslation.translate(original)
    assert_instance_of Redis::AuthenticationError, translated
  end

  def test_translate_command_error_err_auth
    original = RedisRuby::CommandError.new("ERR AUTH failed")
    translated = Redis::ErrorTranslation.translate(original)
    assert_instance_of Redis::AuthenticationError, translated
  end

  def test_translate_command_error_noperm
    original = RedisRuby::CommandError.new("NOPERM no permission")
    translated = Redis::ErrorTranslation.translate(original)
    assert_instance_of Redis::PermissionError, translated
  end

  def test_translate_cluster_down_error
    original = RedisRuby::ClusterDownError.new("CLUSTERDOWN cluster is down")
    translated = Redis::ErrorTranslation.translate(original)
    assert_instance_of Redis::ClusterDownError, translated
  end

  def test_translate_moved_error
    original = RedisRuby::MovedError.new("MOVED 12345 127.0.0.1:6379")
    translated = Redis::ErrorTranslation.translate(original)
    assert_instance_of Redis::MovedError, translated
  end

  def test_translate_ask_error
    original = RedisRuby::AskError.new("ASK 5000 192.168.1.1:7000")
    translated = Redis::ErrorTranslation.translate(original)
    assert_instance_of Redis::AskError, translated
  end

  def test_translate_generic_cluster_error
    original = RedisRuby::ClusterError.new("cluster problem")
    translated = Redis::ErrorTranslation.translate(original)
    assert_instance_of Redis::ClusterError, translated
  end

  def test_translate_unknown_error_returns_original
    original = RuntimeError.new("unknown")
    translated = Redis::ErrorTranslation.translate(original)
    assert_same original, translated
  end

  def test_translate_standard_error_returns_original
    original = StandardError.new("standard")
    translated = Redis::ErrorTranslation.translate(original)
    assert_same original, translated
  end
end
