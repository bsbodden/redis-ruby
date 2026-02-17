# frozen_string_literal: true

module RR
  module Concerns
    # Shared operations for pooled clients
    #
    # Provides common methods for clients that use connection pooling.
    # The including class must define:
    # - @pool: A pool object with #with or #acquire method
    # - #with_connection: Method to get a connection from the pool
    module PooledOperations
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
        with_connection do |conn|
          pipeline = Pipeline.new(conn)
          yield pipeline

          if @instrumentation
            start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            results = pipeline.execute
            duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
            @instrumentation.record_pipeline(duration, pipeline.size)
          else
            results = pipeline.execute
          end

          results.map { |r| r.is_a?(CommandError) ? raise(r) : r }
        end
      end

      # Execute commands in a transaction (MULTI/EXEC)
      #
      # @yield [Transaction] transaction object to queue commands
      # @return [Array, nil] results from all commands, or nil if aborted
      def multi
        with_connection do |conn|
          transaction = Transaction.new(conn)
          yield transaction

          if @instrumentation
            start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            results = transaction.execute
            duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
            @instrumentation.record_transaction(duration, transaction.size)
          else
            results = transaction.execute
          end

          return nil if results.nil?

          # Handle case where transaction itself failed (e.g., MISCONF)
          raise results if results.is_a?(CommandError)

          results.map { |r| r.is_a?(CommandError) ? raise(r) : r }
        end
      end

      # Watch keys for changes (optimistic locking)
      #
      # @param keys [Array<String>] keys to watch
      # @yield [optional] block to execute while watching
      # @return [Object] result of block, or "OK" if no block
      def watch(*keys, &block)
        with_connection do |conn|
          result = conn.call("WATCH", *keys)
          return result unless block

          begin
            yield
          ensure
            conn.call("UNWATCH")
          end
        end
      end

      # Unwatch all watched keys
      #
      # @return [String] "OK"
      def unwatch
        call("UNWATCH")
      end

      private

      # Parse Redis URL using shared utility
      def parse_url(url)
        parsed = Utils::URLParser.parse(url)
        @host = parsed[:host] || self.class::DEFAULT_HOST
        @port = parsed[:port] || self.class::DEFAULT_PORT
        @db = parsed[:db] || self.class::DEFAULT_DB
        @password = parsed[:password]
      end
    end
  end
end
