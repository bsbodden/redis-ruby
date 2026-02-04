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
        call("ACL", "SETUSER", username, *rules)
      end

      # Get user details
      #
      # @param username [String] Username to query
      # @return [Hash, nil] User details or nil if user doesn't exist
      def acl_getuser(username)
        call("ACL", "GETUSER", username)
      end

      # Delete one or more users
      #
      # @param usernames [Array<String>] Usernames to delete
      # @return [Integer] Number of users deleted
      def acl_deluser(*usernames)
        call("ACL", "DELUSER", *usernames)
      end

      # List all ACL rules
      #
      # @return [Array<String>] ACL rules for all users
      def acl_list
        call("ACL", "LIST")
      end

      # List all usernames
      #
      # @return [Array<String>] All usernames
      def acl_users
        call("ACL", "USERS")
      end

      # Get the current connection's username
      #
      # @return [String] Current username
      def acl_whoami
        call("ACL", "WHOAMI")
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
          call("ACL", "CAT", category)
        else
          call("ACL", "CAT")
        end
      end

      # Generate a random password
      #
      # @param bits [Integer, nil] Number of bits (default: 256)
      # @return [String] Random hex string
      def acl_genpass(bits = nil)
        if bits
          call("ACL", "GENPASS", bits)
        else
          call("ACL", "GENPASS")
        end
      end

      # Get the ACL security log
      #
      # @param count [Integer, nil] Maximum number of entries
      # @return [Array<Hash>] Log entries
      def acl_log(count = nil)
        if count
          call("ACL", "LOG", count)
        else
          call("ACL", "LOG")
        end
      end

      # Reset the ACL security log
      #
      # @return [String] "OK"
      def acl_log_reset
        call("ACL", "LOG", "RESET")
      end

      # Save the current ACL rules to the configured ACL file
      #
      # @return [String] "OK"
      def acl_save
        call("ACL", "SAVE")
      end

      # Load ACL rules from the configured ACL file
      #
      # @return [String] "OK"
      def acl_load
        call("ACL", "LOAD")
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
        call("ACL", "DRYRUN", username, *args)
      end
    end
  end
end
