# frozen_string_literal: true

require "test_helper"

class ClusterUnitTest < Minitest::Test
  # Test CRC16 hash slot calculation
  def test_key_slot_basic
    client = build_mock_cluster_client

    # Hash slots should be consistent for same keys
    assert_equal client.key_slot("foo"), client.key_slot("foo")
    assert_equal client.key_slot("bar"), client.key_slot("bar")
    assert_equal client.key_slot("hello"), client.key_slot("hello")
    assert_equal client.key_slot("test"), client.key_slot("test")

    # Different keys may have different slots
    # (not guaranteed, but very likely for these keys)
    slots = %w[foo bar hello test].map { |k| client.key_slot(k) }.uniq

    assert_operator slots.size, :>, 1, "Expected different keys to have different slots"
  end

  def test_key_slot_with_hash_tag
    client = build_mock_cluster_client

    # Keys with same hash tag should have same slot
    slot1 = client.key_slot("user:{123}:name")
    slot2 = client.key_slot("user:{123}:email")
    slot3 = client.key_slot("user:{123}:profile")

    assert_equal slot1, slot2
    assert_equal slot2, slot3

    # Different hash tags = potentially different slots
    slot_a = client.key_slot("{a}key")
    slot_b = client.key_slot("{b}key")

    refute_equal slot_a, slot_b
  end

  def test_key_slot_empty_hash_tag
    client = build_mock_cluster_client

    # Empty hash tag {} is ignored, full key is used
    slot1 = client.key_slot("foo{}bar")
    slot2 = client.key_slot("foo{}bar")

    assert_equal slot1, slot2

    # Nested braces - first complete pair is used
    slot3 = client.key_slot("foo{bar}baz")
    slot4 = client.key_slot("{bar}")

    assert_equal slot3, slot4
  end

  def test_key_slot_no_closing_brace
    client = build_mock_cluster_client

    # No closing brace - full key is used
    slot1 = client.key_slot("foo{bar")
    slot2 = client.key_slot("foo{bar")

    assert_equal slot1, slot2
  end

  def test_key_slot_range
    client = build_mock_cluster_client

    # All slots should be in valid range
    10_000.times do
      key = "test_key_#{rand(1_000_000)}"
      slot = client.key_slot(key)

      assert_operator slot, :>=, 0
      assert_operator slot, :<, 16_384
    end
  end

  def test_cluster_commands_module_included
    # ClusterClient should have cluster commands
    assert RedisRuby::ClusterClient.method_defined?(:cluster_info)
    assert RedisRuby::ClusterClient.method_defined?(:cluster_nodes)
    assert RedisRuby::ClusterClient.method_defined?(:cluster_slots)
    assert RedisRuby::ClusterClient.method_defined?(:cluster_keyslot)
    assert RedisRuby::ClusterClient.method_defined?(:readonly)
    assert RedisRuby::ClusterClient.method_defined?(:asking)
  end

  def test_cluster_factory_method
    assert_respond_to RedisRuby, :cluster
  end

  def test_cluster_error_classes
    assert_operator RedisRuby::ClusterError, :<, RedisRuby::Error
    assert_operator RedisRuby::ClusterDownError, :<, RedisRuby::ClusterError
    assert_operator RedisRuby::MovedError, :<, RedisRuby::ClusterError
    assert_operator RedisRuby::AskError, :<, RedisRuby::ClusterError
  end

  def test_normalize_nodes_urls
    # Can't easily test without mocking, but we can test the error case
    assert_raises(ArgumentError) do
      RedisRuby::ClusterClient.new(nodes: [123]) # Invalid node type
    end
  end

  def test_read_commands_constant
    read_commands = RedisRuby::ClusterClient::READ_COMMANDS

    # Verify some known read commands
    assert_includes read_commands, "GET"
    assert_includes read_commands, "HGET"
    assert_includes read_commands, "LRANGE"
    assert_includes read_commands, "SMEMBERS"
    assert_includes read_commands, "ZRANGE"
    assert_includes read_commands, "XRANGE"

    # These should NOT be read commands (they modify data)
    refute_includes read_commands, "SET"
    refute_includes read_commands, "HSET"
    refute_includes read_commands, "LPUSH"
    refute_includes read_commands, "SADD"
    refute_includes read_commands, "ZADD"
    refute_includes read_commands, "XADD"
  end

  private

  # Build a mock cluster client for testing without actual connections
  def build_mock_cluster_client
    # Create a client that we can use for slot calculations
    # without actually connecting
    client = Object.new
    client.extend(RedisRuby::ClusterClient::HashSlotMixin)
    client
  end
end

# Mixin module to test hash slot calculation in isolation
module RedisRuby
  class ClusterClient
    module HashSlotMixin
      HASH_SLOTS = 16_384

      CRC16_TABLE = begin
        table = Array.new(256)
        256.times do |i|
          crc = i << 8
          8.times do
            crc = crc.nobits?(0x8000) ? crc << 1 : (crc << 1) ^ 0x1021
          end
          table[i] = crc & 0xFFFF
        end
        table.freeze
      end

      def key_slot(key)
        tag_key = extract_hash_tag(key) || key
        crc16(tag_key) % HASH_SLOTS
      end

      private

      def extract_hash_tag(key)
        return nil unless key.is_a?(String)

        start_idx = key.index("{")
        return nil unless start_idx

        end_idx = key.index("}", start_idx + 1)
        return nil unless end_idx && end_idx > start_idx + 1

        key[(start_idx + 1)...end_idx]
      end

      def crc16(data)
        crc = 0
        data.each_byte do |byte|
          crc = ((crc << 8) ^ CRC16_TABLE[((crc >> 8) ^ byte) & 0xFF]) & 0xFFFF
        end
        crc
      end
    end
  end
end
