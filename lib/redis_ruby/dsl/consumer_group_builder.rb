# frozen_string_literal: true

module RR
  module DSL
    # DSL builder for Redis Stream consumer group operations
    #
    # Provides a block-based DSL for managing consumer groups,
    # making group operations more declarative and Ruby-esque.
    #
    # @example Create consumer group
    #   redis.consumer_group(:events, :processors) do
    #     create_from "$"
    #   end
    #
    # @example Create from beginning
    #   redis.consumer_group(:events, :processors) do
    #     create_from_beginning
    #   end
    #
    # @example Destroy group
    #   redis.consumer_group(:events, :processors) do
    #     destroy
    #   end
    class ConsumerGroupBuilder
      # @param [RR::Client] Redis client
      # @param stream_key [String] Stream key
      # @param group_name [String] Consumer group name
      def initialize(redis, stream_key, group_name)
        @redis = redis
        @stream_key = stream_key
        @group_name = group_name
      end

      # Create the consumer group starting from a specific ID
      #
      # @param id [String] Starting ID ("$" for new entries, "0" for beginning)
      # @param mkstream [Boolean] Create stream if it doesn't exist
      # @param entriesread [Integer] Entries read counter for lag tracking (Redis 7.0+)
      # @return [String] "OK"
      #
      # @example
      #   create_from "$"
      #   create_from "0"
      #   create_from "$", mkstream: true
      def create_from(id, mkstream: false, entriesread: nil)
        @redis.xgroup_create(@stream_key, @group_name, id.to_s,
                             mkstream: mkstream,
                             entriesread: entriesread)
      end

      # Create the consumer group starting from the beginning
      #
      # @param mkstream [Boolean] Create stream if it doesn't exist
      # @param entriesread [Integer] Entries read counter for lag tracking
      # @return [String] "OK"
      #
      # @example
      #   create_from_beginning
      #   create_from_beginning mkstream: true
      def create_from_beginning(mkstream: false, entriesread: nil)
        create_from("0", mkstream: mkstream, entriesread: entriesread)
      end

      # Create the consumer group for new entries only
      #
      # @param mkstream [Boolean] Create stream if it doesn't exist
      # @param entriesread [Integer] Entries read counter for lag tracking
      # @return [String] "OK"
      #
      # @example
      #   create_from_now
      #   create_from_now mkstream: true
      def create_from_now(mkstream: false, entriesread: nil)
        create_from("$", mkstream: mkstream, entriesread: entriesread)
      end

      # Destroy the consumer group
      #
      # @return [Integer] 1 if group was destroyed, 0 if it didn't exist
      #
      # @example
      #   destroy
      def destroy
        @redis.xgroup_destroy(@stream_key, @group_name)
      end

      # Update the consumer group's last delivered ID
      #
      # @param id [String] New last delivered ID
      # @return [String] "OK"
      #
      # @example
      #   update_id "1000-0"
      #   update_id "$"
      def update_id(id)
        @redis.xgroup_setid(@stream_key, @group_name, id.to_s)
      end
      alias set_id update_id

      # Create a consumer in the group
      #
      # @param consumer_name [String, Symbol] Consumer name
      # @return [Integer] 1 if consumer was created, 0 if it already existed
      #
      # @example
      #   create_consumer :worker1
      def create_consumer(consumer_name)
        @redis.xgroup_createconsumer(@stream_key, @group_name, consumer_name.to_s)
      end

      # Delete a consumer from the group
      #
      # @param consumer_name [String, Symbol] Consumer name
      # @return [Integer] Number of pending entries the consumer had
      #
      # @example
      #   delete_consumer :worker1
      def delete_consumer(consumer_name)
        @redis.xgroup_delconsumer(@stream_key, @group_name, consumer_name.to_s)
      end

      # Get information about the consumer group
      #
      # @return [Array<Hash>] Array of group information hashes
      #
      # @example
      #   info
      def info
        @redis.xinfo_groups(@stream_key)
      end

      # Get information about consumers in the group
      #
      # @return [Array<Hash>] Array of consumer information hashes
      #
      # @example
      #   consumers
      def consumers
        @redis.xinfo_consumers(@stream_key, @group_name)
      end
    end
  end
end
