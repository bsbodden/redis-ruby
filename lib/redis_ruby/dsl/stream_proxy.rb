# frozen_string_literal: true

module RR
  module DSL
    # Chainable proxy for Redis Stream operations
    #
    # Provides a fluent interface for working with a single stream,
    # making common operations more idiomatic and Ruby-esque.
    #
    # @example Basic usage
    #   stream = redis.stream(:events)
    #   stream.add(sensor: "temp", value: 23.5)
    #         .add(sensor: "humidity", value: 65)
    #         .trim(maxlen: 1000)
    #
    # @example Reading entries
    #   stream.read.from("0-0").count(10).each do |id, fields|
    #     puts "#{id}: #{fields}"
    #   end
    #
    # @example Consumer operations
    #   consumer = stream.consumer(:mygroup, :worker1)
    #   entries = consumer.read.count(10).execute
    #   consumer.ack(*entries.map(&:first))
    class StreamProxy
      # @param [RR::Client] Redis client
      # @param key [String] Stream key
      def initialize(redis, key)
        @redis = redis
        @key = key.to_s
      end

      # Add an entry to the stream
      #
      # @param fields [Hash] Field-value pairs (can be passed as keyword arguments)
      # @param entry_id [String] Entry ID (default: "*" for auto-generate)
      # @param maxlen [Integer] Maximum stream length
      # @param minid [String] Minimum ID to keep
      # @param approximate [Boolean] Allow approximate trimming
      # @param nomkstream [Boolean] Don't create stream if missing
      # @param limit [Integer] Maximum entries to delete in a single call
      # @return [self] Returns self for chaining
      #
      # @example With keyword arguments
      #   stream.add(temp: 23.5, humidity: 65)
      #
      # @example With hash and options
      #   stream.add({temp: 23.5}, entry_id: "1000-0", maxlen: 1000)
      def add(fields = nil, entry_id: "*", maxlen: nil, minid: nil, approximate: false, nomkstream: false, limit: nil,
              **kwargs)
        # If fields is nil, use kwargs as fields
        fields = kwargs if fields.nil?

        # Convert symbol keys to strings
        string_fields = fields.transform_keys(&:to_s)

        @redis.xadd(@key, string_fields,
                    id: entry_id,
                    maxlen: maxlen,
                    minid: minid,
                    approximate: approximate,
                    nomkstream: nomkstream,
                    limit: limit)
        self
      end

      # Trim the stream
      #
      # @param maxlen [Integer] Maximum stream length
      # @param minid [String] Minimum ID to keep
      # @param approximate [Boolean] Allow approximate trimming
      # @param limit [Integer] Maximum entries to delete
      # @return [Integer] Number of entries deleted
      #
      # @example
      #   stream.trim(maxlen: 1000)
      #   stream.trim(minid: "1000-0", approximate: true)
      def trim(maxlen: nil, minid: nil, approximate: false, limit: nil)
        @redis.xtrim(@key, maxlen: maxlen, minid: minid, approximate: approximate, limit: limit)
      end

      # Get the number of entries in the stream
      #
      # @return [Integer] Number of entries
      #
      # @example
      #   stream.length  # => 42
      def length
        @redis.xlen(@key)
      end
      alias size length
      alias count length

      # Delete entries from the stream
      #
      # @param ids [Array<String>] Entry IDs to delete
      # @return [Integer] Number of entries deleted
      #
      # @example
      #   stream.delete("1000-0", "1000-1")
      def delete(*ids)
        @redis.xdel(@key, *ids)
      end

      # Get stream information
      #
      # @param full [Boolean] Get full information including entries
      # @param count [Integer] Limit entries in full output
      # @return [Hash] Stream information
      #
      # @example
      #   stream.info
      #   stream.info(full: true, count: 10)
      def info(full: false, count: nil)
        @redis.xinfo_stream(@key, full: full, count: count)
      end

      # Create a reader for this stream
      #
      # @return [StreamReader] Reader builder
      #
      # @example
      #   stream.read.from("0-0").count(10).execute
      def read
        require_relative "stream_reader"
        StreamReader.new(@redis, @key)
      end

      # Get a consumer proxy for this stream
      #
      # @param group [String, Symbol] Consumer group name
      # @param consumer [String, Symbol] Consumer name
      # @return [ConsumerProxy] Consumer proxy
      #
      # @example
      #   consumer = stream.consumer(:mygroup, :worker1)
      #   entries = consumer.read.count(10).execute
      def consumer(group, consumer)
        require_relative "consumer_proxy"
        ConsumerProxy.new(@redis, @key, group.to_s, consumer.to_s)
      end

      # Get the stream key
      #
      # @return [String] Stream key
      attr_reader :key
    end
  end
end
