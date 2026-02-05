# frozen_string_literal: true

module RedisRuby
  module Commands
    # ACL (Access Control List) commands (Redis 6.0+)
    #
    # Manage users, permissions, and security rules.
    #
    # @example Create a user
    #   redis.acl_setuser("myuser", "on", ">password", "~*", "+@all")
    #
    # @example Check current user
    #   redis.acl_whoami  # => "default"
    #
    # @see https://redis.io/commands/?group=server
    module ACL
      # Frozen command constants to avoid string allocations
      CMD_ACL = "ACL"

      # Frozen subcommands
      SUBCMD_SETUSER = "SETUSER"
      SUBCMD_GETUSER = "GETUSER"
      SUBCMD_DELUSER = "DELUSER"
      SUBCMD_LIST = "LIST"
      SUBCMD_USERS = "USERS"
      SUBCMD_WHOAMI = "WHOAMI"
      SUBCMD_CAT = "CAT"
      SUBCMD_GENPASS = "GENPASS"
      SUBCMD_LOG = "LOG"
      SUBCMD_SAVE = "SAVE"
      SUBCMD_LOAD = "LOAD"
      SUBCMD_DRYRUN = "DRYRUN"
      OPT_RESET = "RESET"

      # Create or modify a user with ACL rules
      #
      # @param username [String] Username to create or modify
      # @param rules [Array<String>] ACL rules (e.g. "on", ">pass", "~*", "+@all")
      # @return [String] "OK"
      #
      # @example Create user with full access
      #   redis.acl_setuser("admin", "on", ">secret", "~*", "+@all")
      #
      # @example Create read-only user
      #   redis.acl_setuser("reader", "on", ">pass", "~*", "+@read")
      def acl_setuser(username, *rules)
        call(CMD_ACL, SUBCMD_SETUSER, username, *rules)
      end

      # Get user details
      #
      # @param username [String] Username to query
      # @return [Hash, nil] User details or nil if user doesn't exist
      def acl_getuser(username)
        call_2args(CMD_ACL, SUBCMD_GETUSER, username)
      end

      # Delete one or more users
      #
      # @param usernames [Array<String>] Usernames to delete
      # @return [Integer] Number of users deleted
      def acl_deluser(*usernames)
        # Fast path for single user
        if usernames.size == 1
          return call_2args(CMD_ACL, SUBCMD_DELUSER, usernames[0])
        end

        call(CMD_ACL, SUBCMD_DELUSER, *usernames)
      end

      # List all ACL rules
      #
      # @return [Array<String>] ACL rules for all users
      def acl_list
        call_1arg(CMD_ACL, SUBCMD_LIST)
      end

      # List all usernames
      #
      # @return [Array<String>] All usernames
      def acl_users
        call_1arg(CMD_ACL, SUBCMD_USERS)
      end

      # Get the current connection's username
      #
      # @return [String] Current username
      def acl_whoami
        call_1arg(CMD_ACL, SUBCMD_WHOAMI)
      end

      # List available ACL categories or commands in a category
      #
      # @param category [String, nil] Category name to list commands for
      # @return [Array<String>] Categories or commands
      #
      # @example List all categories
      #   redis.acl_cat
      #
      # @example List commands in a category
      #   redis.acl_cat("string")
      def acl_cat(category = nil)
        if category
          call_2args(CMD_ACL, SUBCMD_CAT, category)
        else
          call_1arg(CMD_ACL, SUBCMD_CAT)
        end
      end

      # Generate a random password
      #
      # @param bits [Integer, nil] Number of bits (default: 256)
      # @return [String] Random hex string
      def acl_genpass(bits = nil)
        if bits
          call_2args(CMD_ACL, SUBCMD_GENPASS, bits)
        else
          call_1arg(CMD_ACL, SUBCMD_GENPASS)
        end
      end

      # Get the ACL security log
      #
      # @param count [Integer, nil] Maximum number of entries
      # @return [Array<Hash>] Log entries
      def acl_log(count = nil)
        if count
          call_2args(CMD_ACL, SUBCMD_LOG, count)
        else
          call_1arg(CMD_ACL, SUBCMD_LOG)
        end
      end

      # Reset the ACL security log
      #
      # @return [String] "OK"
      def acl_log_reset
        call_2args(CMD_ACL, SUBCMD_LOG, OPT_RESET)
      end

      # Save the current ACL rules to the configured ACL file
      #
      # @return [String] "OK"
      def acl_save
        call_1arg(CMD_ACL, SUBCMD_SAVE)
      end

      # Load ACL rules from the configured ACL file
      #
      # @return [String] "OK"
      def acl_load
        call_1arg(CMD_ACL, SUBCMD_LOAD)
      end

      # Test a command against a user's permissions without executing it
      #
      # @param username [String] Username to test
      # @param args [Array<String>] Command and arguments to test
      # @return [String] "OK" if permitted, or error description
      #
      # @example
      #   redis.acl_dryrun("testuser", "SET", "foo", "bar")
      def acl_dryrun(username, *args)
        call(CMD_ACL, SUBCMD_DRYRUN, username, *args)
      end
    end
  end
end
