# frozen_string_literal: true

module RR
  module Protocol
    # Fast-path dispatch and encoding logic for common Redis commands
    #
    # Extracted from RESP3Encoder to reduce class complexity.
    # Routes commands to table-driven encoding based on argument count.
    # Dispatch tables are defined in the including class (RESP3Encoder).
    #
    # @api private
    module FastPathEncoders
      # Try fast-path encoding for common commands
      # Returns nil if no fast path matches
      def try_fast_path_encoding(command, args, argc)
        case argc
        when 1 then try_fast_path_fixed(self.class::FAST_PATH_1ARG, command, args, 1)
        when 2 then try_fast_path_fixed(self.class::FAST_PATH_2ARG, command, args, 2)
        when 3 then try_fast_path_fixed(self.class::FAST_PATH_3ARG, command, args, 3)
        else try_fast_path_batch(command, args, argc)
        end
      end

      # Try fixed-argument fast path using lookup table
      def try_fast_path_fixed(table, command, args, argc)
        prefix = table[command]
        return nil unless prefix

        encode_with_prefix(prefix, args, argc)
      end

      # Encode command using pre-built prefix and arguments
      def encode_with_prefix(prefix, args, argc)
        @buffer.clear
        @buffer << prefix
        argc.times { |i| dump_bulk_string_fast(args[i], @buffer) }
        @buffer
      end

      # Fast path for batch commands (MGET, MSET)
      def try_fast_path_batch(command, args, argc)
        return encode_batch_fast(self.class::MGET_CMD, args, argc) if command == "MGET" && argc.positive?
        return encode_batch_fast(self.class::MSET_CMD, args, argc) if command == "MSET" && argc.positive? && argc.even?

        nil
      end

      # Encode batch command (MGET/MSET) with variable args
      def encode_batch_fast(cmd_prefix, args, argc)
        @buffer.clear
        @buffer << self.class::ARRAY_PREFIX << int_to_s(argc + 1) << self.class::EOL << cmd_prefix
        args.each { |arg| dump_bulk_string_fast(arg, @buffer) }
        @buffer
      end
    end
  end
end
