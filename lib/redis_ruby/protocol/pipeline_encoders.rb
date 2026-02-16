# frozen_string_literal: true

module RR
  module Protocol
    # Pipeline encoding methods for RESP3 encoder
    #
    # Extracted from RESP3Encoder to reduce class complexity.
    # Handles fast-path encoding of common commands within pipelines.
    # Constants are resolved from the including class (RESP3Encoder).
    #
    # @api private
    module PipelineEncoders
      # Try fast path encoding for common pipeline commands
      # Returns true if fast path was used, false otherwise
      def try_pipeline_fast_path(first, size, cmd)
        if (entry = self.class::PIPELINE_1ARG_CMDS[first])
          encode_pipeline_1arg(size, entry[0], entry[1], cmd)
        elsif (entry = self.class::PIPELINE_2ARG_CMDS[first])
          encode_pipeline_2args(size, entry[0], entry[1], cmd)
        elsif (entry = self.class::PIPELINE_3ARG_CMDS[first])
          encode_pipeline_3args(size, entry[0], entry[1], cmd)
        else
          false
        end
      end

      # Encode pipeline command with 1 argument (CMD key)
      def encode_pipeline_1arg(size, expected_size, prefix, cmd)
        return false unless size == expected_size

        @buffer << prefix
        dump_bulk_string_fast(cmd[1], @buffer)
        true
      end

      # Encode pipeline command with 2 arguments (CMD key arg)
      def encode_pipeline_2args(size, expected_size, prefix, cmd)
        return false unless size == expected_size

        @buffer << prefix
        dump_bulk_string_fast(cmd[1], @buffer)
        dump_bulk_string_fast(cmd[2], @buffer)
        true
      end

      # Encode pipeline command with 3 arguments (CMD key arg1 arg2)
      def encode_pipeline_3args(size, expected_size, prefix, cmd)
        return false unless size == expected_size

        @buffer << prefix
        dump_bulk_string_fast(cmd[1], @buffer)
        dump_bulk_string_fast(cmd[2], @buffer)
        dump_bulk_string_fast(cmd[3], @buffer)
        true
      end
    end
  end
end
