# frozen_string_literal: true

require_relative "../unit_test_helper"

class KeysBranchTest < Minitest::Test
  class MockClient
    include RR::Commands::Keys

    attr_reader :last_command

    def call(*args)
      @last_command = args
      mock_return(args)
    end

    def call_1arg(cmd, arg_one)
      @last_command = [cmd, arg_one]
      mock_return([cmd, arg_one])
    end

    def call_2args(cmd, arg_one, arg_two)
      @last_command = [cmd, arg_one, arg_two]
      mock_return([cmd, arg_one, arg_two])
    end

    def call_3args(cmd, arg_one, arg_two, arg_three)
      @last_command = [cmd, arg_one, arg_two, arg_three]
      mock_return([cmd, arg_one, arg_two, arg_three])
    end

    MOCK_RETURNS = {
      "TYPE" => "string", "KEYS" => %w[key1 key2],
      "SCAN" => ["0", %w[key1 key2]], "RANDOMKEY" => "somekey",
      "DUMP" => "\x00\x05value\t\x00", "MEMORY" => 128,
    }.freeze

    NUMERIC_CMDS = %w[DEL EXISTS EXPIRE PEXPIRE EXPIREAT PEXPIREAT TTL PTTL
                      PERSIST EXPIRETIME PEXPIRETIME UNLINK TOUCH COPY RENAMENX].freeze

    private

    def mock_return(args)
      return 1 if NUMERIC_CMDS.include?(args[0])

      MOCK_RETURNS.fetch(args[0], "OK")
    end
  end

  def setup
    @client = MockClient.new
  end

  # ============================================================
  # DEL - single key fast path and multi-key path
  # ============================================================

  def test_del_single_key_fast_path
    result = @client.del("mykey")

    assert_equal %w[DEL mykey], @client.last_command
    assert_equal 1, result
  end

  def test_del_multiple_keys
    @client.del("key1", "key2", "key3")

    assert_equal %w[DEL key1 key2 key3], @client.last_command
  end
  # ============================================================
  # EXISTS - single key fast path and multi-key path
  # ============================================================

  def test_exists_single_key_fast_path
    result = @client.exists("mykey")

    assert_equal %w[EXISTS mykey], @client.last_command
    assert_equal 1, result
  end

  def test_exists_multiple_keys
    @client.exists("key1", "key2")

    assert_equal %w[EXISTS key1 key2], @client.last_command
  end
  # ============================================================
  # EXPIRE - with all flag combinations
  # ============================================================

  def test_expire_no_flags
    @client.expire("mykey", 60)

    assert_equal ["EXPIRE", "mykey", 60], @client.last_command
  end

  def test_expire_with_nx
    @client.expire("mykey", 60, nx: true)

    assert_equal ["EXPIRE", "mykey", 60, "NX"], @client.last_command
  end

  def test_expire_with_xx
    @client.expire("mykey", 60, xx: true)

    assert_equal ["EXPIRE", "mykey", 60, "XX"], @client.last_command
  end

  def test_expire_with_gt
    @client.expire("mykey", 60, gt: true)

    assert_equal ["EXPIRE", "mykey", 60, "GT"], @client.last_command
  end

  def test_expire_with_lt
    @client.expire("mykey", 60, lt: true)

    assert_equal ["EXPIRE", "mykey", 60, "LT"], @client.last_command
  end

  def test_expire_with_nx_and_gt
    @client.expire("mykey", 60, nx: true, gt: true)

    assert_equal ["EXPIRE", "mykey", 60, "NX", "GT"], @client.last_command
  end

  def test_expire_all_flags
    @client.expire("mykey", 60, nx: true, xx: true, gt: true, lt: true)

    assert_equal ["EXPIRE", "mykey", 60, "NX", "XX", "GT", "LT"], @client.last_command
  end

  def test_expire_false_flags_not_added
    @client.expire("mykey", 60, nx: false, xx: false, gt: false, lt: false)

    assert_equal ["EXPIRE", "mykey", 60], @client.last_command
  end
  # ============================================================
  # PEXPIRE - with all flag combinations
  # ============================================================

  def test_pexpire_no_flags
    @client.pexpire("mykey", 60_000)

    assert_equal ["PEXPIRE", "mykey", 60_000], @client.last_command
  end

  def test_pexpire_with_nx
    @client.pexpire("mykey", 60_000, nx: true)

    assert_equal ["PEXPIRE", "mykey", 60_000, "NX"], @client.last_command
  end

  def test_pexpire_with_xx
    @client.pexpire("mykey", 60_000, xx: true)

    assert_equal ["PEXPIRE", "mykey", 60_000, "XX"], @client.last_command
  end

  def test_pexpire_with_gt
    @client.pexpire("mykey", 60_000, gt: true)

    assert_equal ["PEXPIRE", "mykey", 60_000, "GT"], @client.last_command
  end

  def test_pexpire_with_lt
    @client.pexpire("mykey", 60_000, lt: true)

    assert_equal ["PEXPIRE", "mykey", 60_000, "LT"], @client.last_command
  end
end

class KeysBranchTestPart2 < Minitest::Test
  class MockClient
    include RR::Commands::Keys

    attr_reader :last_command

    def call(*args)
      @last_command = args
      mock_return(args)
    end

    def call_1arg(cmd, arg_one)
      @last_command = [cmd, arg_one]
      mock_return([cmd, arg_one])
    end

    def call_2args(cmd, arg_one, arg_two)
      @last_command = [cmd, arg_one, arg_two]
      mock_return([cmd, arg_one, arg_two])
    end

    def call_3args(cmd, arg_one, arg_two, arg_three)
      @last_command = [cmd, arg_one, arg_two, arg_three]
      mock_return([cmd, arg_one, arg_two, arg_three])
    end

    MOCK_RETURNS = {
      "TYPE" => "string", "KEYS" => %w[key1 key2],
      "SCAN" => ["0", %w[key1 key2]], "RANDOMKEY" => "somekey",
      "DUMP" => "\x00\x05value\t\x00", "MEMORY" => 128,
    }.freeze

    NUMERIC_CMDS = %w[DEL EXISTS EXPIRE PEXPIRE EXPIREAT PEXPIREAT TTL PTTL
                      PERSIST EXPIRETIME PEXPIRETIME UNLINK TOUCH COPY RENAMENX].freeze

    private

    def mock_return(args)
      return 1 if NUMERIC_CMDS.include?(args[0])

      MOCK_RETURNS.fetch(args[0], "OK")
    end
  end

  def setup
    @client = MockClient.new
  end

  # ============================================================
  # DEL - single key fast path and multi-key path
  # ============================================================

  # ============================================================
  # EXPIREAT - with all flag combinations
  # ============================================================

  def test_expireat_no_flags
    @client.expireat("mykey", 1_700_000_000)

    assert_equal ["EXPIREAT", "mykey", 1_700_000_000], @client.last_command
  end

  def test_expireat_with_nx
    @client.expireat("mykey", 1_700_000_000, nx: true)

    assert_equal ["EXPIREAT", "mykey", 1_700_000_000, "NX"], @client.last_command
  end

  def test_expireat_with_xx
    @client.expireat("mykey", 1_700_000_000, xx: true)

    assert_equal ["EXPIREAT", "mykey", 1_700_000_000, "XX"], @client.last_command
  end

  def test_expireat_with_gt
    @client.expireat("mykey", 1_700_000_000, gt: true)

    assert_equal ["EXPIREAT", "mykey", 1_700_000_000, "GT"], @client.last_command
  end

  def test_expireat_with_lt
    @client.expireat("mykey", 1_700_000_000, lt: true)

    assert_equal ["EXPIREAT", "mykey", 1_700_000_000, "LT"], @client.last_command
  end
  # ============================================================
  # PEXPIREAT - with all flag combinations
  # ============================================================

  def test_pexpireat_no_flags
    @client.pexpireat("mykey", 1_700_000_000_000)

    assert_equal ["PEXPIREAT", "mykey", 1_700_000_000_000], @client.last_command
  end

  def test_pexpireat_with_nx
    @client.pexpireat("mykey", 1_700_000_000_000, nx: true)

    assert_equal ["PEXPIREAT", "mykey", 1_700_000_000_000, "NX"], @client.last_command
  end

  def test_pexpireat_with_xx
    @client.pexpireat("mykey", 1_700_000_000_000, xx: true)

    assert_equal ["PEXPIREAT", "mykey", 1_700_000_000_000, "XX"], @client.last_command
  end

  def test_pexpireat_with_gt
    @client.pexpireat("mykey", 1_700_000_000_000, gt: true)

    assert_equal ["PEXPIREAT", "mykey", 1_700_000_000_000, "GT"], @client.last_command
  end

  def test_pexpireat_with_lt
    @client.pexpireat("mykey", 1_700_000_000_000, lt: true)

    assert_equal ["PEXPIREAT", "mykey", 1_700_000_000_000, "LT"], @client.last_command
  end
  # ============================================================
  # TTL / PTTL
  # ============================================================

  def test_ttl
    result = @client.ttl("mykey")

    assert_equal %w[TTL mykey], @client.last_command
    assert_equal 1, result
  end

  def test_pttl
    result = @client.pttl("mykey")

    assert_equal %w[PTTL mykey], @client.last_command
    assert_equal 1, result
  end
  # ============================================================
  # PERSIST
  # ============================================================

  def test_persist
    result = @client.persist("mykey")

    assert_equal %w[PERSIST mykey], @client.last_command
    assert_equal 1, result
  end
  # ============================================================
  # EXPIRETIME / PEXPIRETIME
  # ============================================================

  def test_expiretime
    result = @client.expiretime("mykey")

    assert_equal %w[EXPIRETIME mykey], @client.last_command
    assert_equal 1, result
  end

  def test_pexpiretime
    result = @client.pexpiretime("mykey")

    assert_equal %w[PEXPIRETIME mykey], @client.last_command
    assert_equal 1, result
  end
  # ============================================================
  # KEYS
  # ============================================================

  def test_keys
    result = @client.keys("*")

    assert_equal ["KEYS", "*"], @client.last_command
    assert_equal %w[key1 key2], result
  end

  def test_keys_with_pattern
    @client.keys("user:*")

    assert_equal ["KEYS", "user:*"], @client.last_command
  end
end

class KeysBranchTestPart3 < Minitest::Test
  class MockClient
    include RR::Commands::Keys

    attr_reader :last_command

    def call(*args)
      @last_command = args
      mock_return(args)
    end

    def call_1arg(cmd, arg_one)
      @last_command = [cmd, arg_one]
      mock_return([cmd, arg_one])
    end

    def call_2args(cmd, arg_one, arg_two)
      @last_command = [cmd, arg_one, arg_two]
      mock_return([cmd, arg_one, arg_two])
    end

    def call_3args(cmd, arg_one, arg_two, arg_three)
      @last_command = [cmd, arg_one, arg_two, arg_three]
      mock_return([cmd, arg_one, arg_two, arg_three])
    end

    MOCK_RETURNS = {
      "TYPE" => "string", "KEYS" => %w[key1 key2],
      "SCAN" => ["0", %w[key1 key2]], "RANDOMKEY" => "somekey",
      "DUMP" => "\x00\x05value\t\x00", "MEMORY" => 128,
    }.freeze

    NUMERIC_CMDS = %w[DEL EXISTS EXPIRE PEXPIRE EXPIREAT PEXPIREAT TTL PTTL
                      PERSIST EXPIRETIME PEXPIRETIME UNLINK TOUCH COPY RENAMENX].freeze

    private

    def mock_return(args)
      return 1 if NUMERIC_CMDS.include?(args[0])

      MOCK_RETURNS.fetch(args[0], "OK")
    end
  end

  def setup
    @client = MockClient.new
  end

  # ============================================================
  # DEL - single key fast path and multi-key path
  # ============================================================

  # ============================================================
  # SCAN - all option combinations
  # ============================================================

  def test_scan_no_options
    cursor, keys = @client.scan("0")

    assert_equal %w[SCAN 0], @client.last_command
    assert_equal "0", cursor
    assert_equal %w[key1 key2], keys
  end

  def test_scan_with_match
    @client.scan("0", match: "user:*")

    assert_equal ["SCAN", "0", "MATCH", "user:*"], @client.last_command
  end

  def test_scan_with_count
    @client.scan("0", count: 100)

    assert_equal ["SCAN", "0", "COUNT", 100], @client.last_command
  end

  def test_scan_with_type
    @client.scan("0", type: "string")

    assert_equal %w[SCAN 0 TYPE string], @client.last_command
  end

  def test_scan_with_all_options
    @client.scan("0", match: "user:*", count: 50, type: "hash")

    assert_equal ["SCAN", "0", "MATCH", "user:*", "COUNT", 50, "TYPE", "hash"], @client.last_command
  end

  def test_scan_match_nil_not_added
    @client.scan("0", match: nil)

    assert_equal %w[SCAN 0], @client.last_command
  end

  def test_scan_count_nil_not_added
    @client.scan("0", count: nil)

    assert_equal %w[SCAN 0], @client.last_command
  end

  def test_scan_type_nil_not_added
    @client.scan("0", type: nil)

    assert_equal %w[SCAN 0], @client.last_command
  end
  # ============================================================
  # TYPE
  # ============================================================

  def test_type
    result = @client.type("mykey")

    assert_equal %w[TYPE mykey], @client.last_command
    assert_equal "string", result
  end
  # ============================================================
  # RENAME / RENAMENX
  # ============================================================

  def test_rename
    result = @client.rename("old", "new")

    assert_equal %w[RENAME old new], @client.last_command
    assert_equal "OK", result
  end

  def test_renamenx
    result = @client.renamenx("old", "new")

    assert_equal %w[RENAMENX old new], @client.last_command
    assert_equal 1, result
  end
  # ============================================================
  # RANDOMKEY
  # ============================================================

  def test_randomkey
    result = @client.randomkey

    assert_equal ["RANDOMKEY"], @client.last_command
    assert_equal "somekey", result
  end
  # ============================================================
  # UNLINK
  # ============================================================

  def test_unlink
    result = @client.unlink("key1", "key2")

    assert_equal %w[UNLINK key1 key2], @client.last_command
    assert_equal 1, result
  end

  def test_unlink_single_key
    @client.unlink("key1")

    assert_equal %w[UNLINK key1], @client.last_command
  end
  # ============================================================
  # RESTORE - with and without replace
  # ============================================================

  def test_restore_without_replace
    @client.restore("mykey", 0, "\x00\x05data")

    assert_equal ["RESTORE", "mykey", 0, "\x00\x05data"], @client.last_command
  end

  def test_restore_with_replace
    @client.restore("mykey", 0, "\x00\x05data", replace: true)

    assert_equal ["RESTORE", "mykey", 0, "\x00\x05data", "REPLACE"], @client.last_command
  end

  def test_restore_replace_false_not_added
    @client.restore("mykey", 1000, "\x00\x05data", replace: false)

    assert_equal ["RESTORE", "mykey", 1000, "\x00\x05data"], @client.last_command
  end
  # ============================================================
  # DUMP
  # ============================================================

  def test_dump
    result = @client.dump("mykey")

    assert_equal %w[DUMP mykey], @client.last_command
    assert_equal "\x00\x05value\t\x00", result
  end
end

class KeysBranchTestPart4 < Minitest::Test
  class MockClient
    include RR::Commands::Keys

    attr_reader :last_command

    def call(*args)
      @last_command = args
      mock_return(args)
    end

    def call_1arg(cmd, arg_one)
      @last_command = [cmd, arg_one]
      mock_return([cmd, arg_one])
    end

    def call_2args(cmd, arg_one, arg_two)
      @last_command = [cmd, arg_one, arg_two]
      mock_return([cmd, arg_one, arg_two])
    end

    def call_3args(cmd, arg_one, arg_two, arg_three)
      @last_command = [cmd, arg_one, arg_two, arg_three]
      mock_return([cmd, arg_one, arg_two, arg_three])
    end

    MOCK_RETURNS = {
      "TYPE" => "string", "KEYS" => %w[key1 key2],
      "SCAN" => ["0", %w[key1 key2]], "RANDOMKEY" => "somekey",
      "DUMP" => "\x00\x05value\t\x00", "MEMORY" => 128,
    }.freeze

    NUMERIC_CMDS = %w[DEL EXISTS EXPIRE PEXPIRE EXPIREAT PEXPIREAT TTL PTTL
                      PERSIST EXPIRETIME PEXPIRETIME UNLINK TOUCH COPY RENAMENX].freeze

    private

    def mock_return(args)
      return 1 if NUMERIC_CMDS.include?(args[0])

      MOCK_RETURNS.fetch(args[0], "OK")
    end
  end

  def setup
    @client = MockClient.new
  end

  # ============================================================
  # DEL - single key fast path and multi-key path
  # ============================================================

  # ============================================================
  # TOUCH
  # ============================================================

  def test_touch
    result = @client.touch("key1", "key2")

    assert_equal %w[TOUCH key1 key2], @client.last_command
    assert_equal 1, result
  end

  def test_touch_single_key
    @client.touch("key1")

    assert_equal %w[TOUCH key1], @client.last_command
  end
  # ============================================================
  # MEMORY USAGE
  # ============================================================

  def test_memory_usage
    result = @client.memory_usage("mykey")

    assert_equal %w[MEMORY USAGE mykey], @client.last_command
    assert_equal 128, result
  end
  # ============================================================
  # COPY - all option combinations
  # ============================================================

  def test_copy_simple
    result = @client.copy("src", "dst")

    assert_equal %w[COPY src dst], @client.last_command
    assert_equal 1, result
  end

  def test_copy_with_db
    @client.copy("src", "dst", db: 2)

    assert_equal ["COPY", "src", "dst", "DB", 2], @client.last_command
  end

  def test_copy_with_replace
    @client.copy("src", "dst", replace: true)

    assert_equal %w[COPY src dst REPLACE], @client.last_command
  end

  def test_copy_with_db_and_replace
    @client.copy("src", "dst", db: 3, replace: true)

    assert_equal ["COPY", "src", "dst", "DB", 3, "REPLACE"], @client.last_command
  end

  def test_copy_db_nil_not_added
    @client.copy("src", "dst", db: nil)

    assert_equal %w[COPY src dst], @client.last_command
  end

  def test_copy_replace_false_not_added
    @client.copy("src", "dst", replace: false)

    assert_equal %w[COPY src dst], @client.last_command
  end
  # ============================================================
  # SCAN_ITER - enumerator with cursor management
  # ============================================================

  def test_scan_iter_returns_enumerator
    result = @client.scan_iter

    assert_instance_of Enumerator, result
  end

  def test_scan_iter_iterates_keys
    # MockClient returns cursor "0" immediately, so loop ends after one call
    keys = @client.scan_iter(match: "*", count: 10).to_a

    assert_equal %w[key1 key2], keys
  end

  def test_scan_iter_with_type
    keys = @client.scan_iter(match: "*", count: 10, type: "string").to_a

    assert_equal %w[key1 key2], keys
  end

  def test_scan_iter_with_custom_match_and_count
    keys = @client.scan_iter(match: "user:*", count: 50).to_a

    assert_equal %w[key1 key2], keys
  end

  # Test scan_iter with multiple cursor iterations
  class MultiCursorMockClient
    include RR::Commands::Keys

    attr_reader :scan_calls

    def initialize
      @scan_calls = 0
    end

    def call(*args)
      if args[0] == "SCAN"
        @scan_calls += 1
        if @scan_calls == 1
          ["42", %w[key1 key2]]
        else
          ["0", %w[key3]]
        end
      else
        "OK"
      end
    end

    def call_1arg(cmd, arg_one) = call(cmd, arg_one)
    def call_2args(cmd, arg_one, arg_two) = call(cmd, arg_one, arg_two)
    def call_3args(cmd, arg_one, arg_two, arg_three) = call(cmd, arg_one, arg_two, arg_three)
  end

  def test_scan_iter_multiple_cursors
    client = MultiCursorMockClient.new
    keys = client.scan_iter.to_a

    assert_equal %w[key1 key2 key3], keys
    assert_equal 2, client.scan_calls
  end
end
