# frozen_string_literal: true

require "socket"

module RedisRuby
  # Sentinel discovery and management
  #
  # Handles discovering Redis masters and replicas through Sentinel servers.
  # Implements retry logic and health checking for high availability.
  #
  # Based on patterns from redis-py, redis-client (Ruby), and async-redis.
  #
  # @example
  #   manager = SentinelManager.new(
  #     sentinels: [{ host: "sentinel1", port: 26379 }],
  #     service_name: "mymaster"
  #   )
  #   master = manager.discover_master  # => { host: "master", port: 6379 }
  #
  # rubocop:disable Metrics/ClassLength
  class SentinelManager
    DEFAULT_SENTINEL_PORT = 26_379
    DEFAULT_TIMEOUT = 0.5
    SENTINEL_DELAY = 0.25 # Delay between sentinel retries (from redis-client)
    MIN_OTHER_SENTINELS = 0 # Minimum other sentinels required (from redis-py)

    attr_reader :service_name, :sentinels

    # Initialize Sentinel manager
    #
    # @param sentinels [Array<Hash>] List of Sentinel hosts with :host and :port
    # @param service_name [String] Name of the monitored master
    # @param password [String, nil] Sentinel password (if AUTH is required)
    # @param sentinel_password [String, nil] Alias for password
    # @param timeout [Float] Connection timeout for Sentinel queries
    # @param min_other_sentinels [Integer] Minimum number of peer sentinels required
    def initialize(sentinels:, service_name:, password: nil, sentinel_password: nil,
                   timeout: DEFAULT_TIMEOUT, min_other_sentinels: MIN_OTHER_SENTINELS)
      @sentinels = normalize_sentinels(sentinels)
      @service_name = service_name
      @password = password || sentinel_password
      @timeout = timeout
      @min_other_sentinels = min_other_sentinels
      @mutex = Mutex.new
      @slave_rr_counter = nil # Round-robin counter for slaves
    end

    # Discover the current master address
    #
    # Queries each Sentinel in order until a valid master is found.
    # Implements the pattern from redis-py's discover_master.
    #
    # @return [Hash] { host: String, port: Integer }
    # @raise [MasterNotFoundError] if no master can be found
    def discover_master
      @mutex.synchronize do
        errors = []

        @sentinels.each_with_index do |sentinel, index|
          address = query_master_from_sentinel(sentinel)
          if address
            # Move successful sentinel to front (redis-py pattern)
            promote_sentinel(index) if index.positive?
            return address
          end
        rescue StandardError => e
          errors << "#{sentinel[:host]}:#{sentinel[:port]} - #{e.message}"
          sleep SENTINEL_DELAY
          next
        end

        raise MasterNotFoundError,
              "No master found for '#{@service_name}'. Errors: #{errors.join("; ")}"
      end
    end

    # Discover available replica addresses
    #
    # @return [Array<Hash>] List of { host: String, port: Integer }
    # @raise [ReplicaNotFoundError] if no replicas can be found
    def discover_replicas
      @mutex.synchronize do
        errors = []

        @sentinels.each do |sentinel|
          replicas = query_replicas_from_sentinel(sentinel)
          return replicas if replicas && !replicas.empty?
        rescue StandardError => e
          errors << "#{sentinel[:host]}:#{sentinel[:port]} - #{e.message}"
          sleep SENTINEL_DELAY
          next
        end

        raise ReplicaNotFoundError,
              "No replicas found for '#{@service_name}'. Errors: #{errors.join("; ")}"
      end
    end

    # Get a random replica address (for load balancing)
    #
    # @return [Hash] { host: String, port: Integer }
    # @raise [ReplicaNotFoundError] if no replicas available
    def random_replica
      replicas = discover_replicas
      replicas.sample
    end

    # Rotate through replicas using round-robin (redis-py pattern)
    #
    # @yield [Hash] Yields each replica address in turn
    # @return [Enumerator] if no block given
    def rotate_replicas
      return enum_for(:rotate_replicas) unless block_given?

      replicas = discover_replicas

      if replicas.any?
        @slave_rr_counter ||= rand(replicas.length)

        replicas.length.times do
          @slave_rr_counter = (@slave_rr_counter + 1) % replicas.length
          yield replicas[@slave_rr_counter]
        end
      end

      # Fallback to master connection (redis-py pattern)
      begin
        yield discover_master
      rescue MasterNotFoundError
        # Ignore if master also not found
      end

      raise ReplicaNotFoundError, "No replica found for '#{@service_name}'"
    end

    # Rotate through Sentinel list (for load balancing)
    def rotate_sentinels!
      @mutex.synchronize do
        @sentinels.rotate!
      end
    end

    # Reset cached state (for failover)
    def reset
      @mutex.synchronize do
        @slave_rr_counter = nil
      end
    end

    # Check if a Sentinel is reachable
    #
    # @param sentinel [Hash] { host: String, port: Integer }
    # @return [Boolean]
    def sentinel_reachable?(sentinel)
      conn = create_sentinel_connection(sentinel)
      result = conn.call("PING")
      conn.close
      result == "PONG"
    rescue StandardError
      false
    end

    # Get all Sentinel addresses for the service
    #
    # @return [Array<Hash>] List of Sentinel addresses
    def discover_sentinels
      result = []

      @sentinels.each do |sentinel|
        conn = create_sentinel_connection(sentinel)
        response = conn.call("SENTINEL", "SENTINELS", @service_name)
        conn.close

        response.each do |info|
          info_hash = parse_info_array(info)
          result << {
            host: info_hash["ip"],
            port: info_hash["port"].to_i,
          }
        end
        break unless result.empty?
      rescue StandardError
        next
      end

      result.uniq { |s| "#{s[:host]}:#{s[:port]}" }
    end

    private

    # Normalize sentinel configuration
    # rubocop:disable Metrics/CyclomaticComplexity
    def normalize_sentinels(sentinels)
      sentinels.map do |sentinel|
        case sentinel
        when Hash
          {
            host: sentinel[:host] || sentinel["host"],
            port: (sentinel[:port] || sentinel["port"] || DEFAULT_SENTINEL_PORT).to_i,
          }
        when String
          host, port = sentinel.split(":")
          { host: host, port: (port || DEFAULT_SENTINEL_PORT).to_i }
        else
          raise ArgumentError, "Invalid sentinel configuration: #{sentinel.inspect}"
        end
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity

    # Query master address from a specific Sentinel
    # Uses SENTINEL MASTERS to check master state (redis-py pattern)
    def query_master_from_sentinel(sentinel)
      conn = create_sentinel_connection(sentinel)
      begin
        # Use SENTINEL MASTERS to get state info (redis-py pattern)
        masters = conn.call("SENTINEL", "MASTERS")
        state = find_master_state(masters, @service_name)

        return nil unless state && check_master_state(state)

        # Refresh sentinels list from this sentinel
        refresh_sentinels(conn)

        address = { host: state["ip"], port: state["port"].to_i }

        # Optionally verify master is actually reachable
        # (disabled by default for performance, enabled in redis-py with check_connection)
        address
      ensure
        conn.close
      end
    end

    # Check if master state is valid (redis-py pattern)
    # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def check_master_state(state)
      # Not a master, or marked as down
      return false unless state["role-reported"] == "master" || state["flags"]&.include?("master")
      return false if state["flags"]&.include?("s_down")
      return false if state["flags"]&.include?("o_down")

      # Check if sentinel has enough peers
      num_other_sentinels = state["num-other-sentinels"].to_i
      return false if num_other_sentinels < @min_other_sentinels

      true
    end
    # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    # Find master state by name from SENTINEL MASTERS result
    def find_master_state(masters, name)
      return nil unless masters.is_a?(Array)

      masters.each do |master_array|
        info = parse_info_array(master_array)
        return info if info["name"] == name
      end

      nil
    end

    # Refresh sentinels list from discovered sentinels (redis-client pattern)
    def refresh_sentinels(conn)
      response = conn.call("SENTINEL", "SENTINELS", @service_name)
      return unless response.is_a?(Array)

      response.each do |sentinel_array|
        info = parse_info_array(sentinel_array)
        new_sentinel = { host: info["ip"], port: info["port"].to_i }

        # Add if not already in list
        unless @sentinels.any? { |s| s[:host] == new_sentinel[:host] && s[:port] == new_sentinel[:port] }
          @sentinels << new_sentinel
        end
      end
    rescue StandardError
      # Ignore errors refreshing sentinels
    end

    # Promote a sentinel to the front of the list (redis-py pattern)
    def promote_sentinel(index)
      @sentinels[0], @sentinels[index] = @sentinels[index], @sentinels[0]
    end

    # Query replica addresses from a specific Sentinel
    # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def query_replicas_from_sentinel(sentinel)
      conn = create_sentinel_connection(sentinel)
      begin
        result = conn.call("SENTINEL", "REPLICAS", @service_name)

        return [] unless result.is_a?(Array)

        result.filter_map do |replica_info|
          info = parse_info_array(replica_info)

          # Skip replicas that are down or disconnected
          next if info["flags"]&.include?("s_down") ||
                  info["flags"]&.include?("o_down") ||
                  info["flags"]&.include?("disconnected")

          {
            host: info["ip"],
            port: info["port"].to_i,
          }
        end
      ensure
        conn.close
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    # Verify that the address is actually a master
    def verify_master_role?(address)
      conn = Connection::TCP.new(
        host: address[:host],
        port: address[:port],
        timeout: @timeout
      )
      begin
        result = conn.call("ROLE")
        result.is_a?(Array) && result[0] == "master"
      rescue StandardError
        false
      ensure
        conn.close
      end
    end

    # Create a connection to a Sentinel server
    def create_sentinel_connection(sentinel)
      conn = Connection::TCP.new(
        host: sentinel[:host],
        port: sentinel[:port],
        timeout: @timeout
      )

      # Authenticate if password is set
      conn.call("AUTH", @password) if @password

      conn
    end

    # Parse Sentinel info array into hash
    def parse_info_array(array)
      return {} unless array.is_a?(Array)

      Hash[*array]
    end
  end
  # rubocop:enable Metrics/ClassLength
end
