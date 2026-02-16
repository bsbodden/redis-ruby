# frozen_string_literal: true

module RR
  module Concerns
    # Shared operations for single-connection clients
    #
    # Provides common methods for clients that use a single connection.
    # The including class must define:
    # - @connection: A connection object
    # - #ensure_connected: Method to ensure connection is established
    module SingleConnectionOperations
      # Ping the Redis server
      #
      # @return [String] "PONG"
      def ping
        call("PING")
      end

      # Execute commands in a pipeline
      #
      # @yield [Pipeline] pipeline object to queue commands
      # @return [Array] results from all commands
      def pipelined
        ensure_connected
        pipeline = Pipeline.new(@connection)
        yield pipeline
        results = pipeline.execute
        results.map { |r| r.is_a?(CommandError) ? raise(r) : r }
      end

      # Execute commands in a transaction (MULTI/EXEC)
      #
      # @yield [Transaction] transaction object to queue commands
      # @return [Array, nil] results from all commands, or nil if aborted
      def multi
        ensure_connected
        transaction = Transaction.new(@connection)
        yield transaction
        results = transaction.execute
        return nil if results.nil?

        # Handle case where transaction itself failed (e.g., MISCONF)
        raise results if results.is_a?(CommandError)

        results.map { |r| r.is_a?(CommandError) ? raise(r) : r }
      end

      # Watch keys for changes (optimistic locking)
      #
      # @param keys [Array<String>] keys to watch
      # @yield [optional] block to execute while watching
      # @return [Object] result of block, or "OK" if no block
      def watch(*keys, &block)
        ensure_connected
        result = @connection.call("WATCH", *keys)
        return result unless block

        begin
          yield
        ensure
          @connection.call("UNWATCH")
        end
      end

      # Unwatch all watched keys
      #
      # @return [String] "OK"
      def unwatch
        call("UNWATCH")
      end
    end
  end
end
