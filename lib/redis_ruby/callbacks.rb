# frozen_string_literal: true

module RedisRuby
  # Response callbacks for custom response parsing
  #
  # Allows registering custom transformations for command responses.
  # Callbacks are applied automatically when the command is executed.
  #
  # @example Register a custom callback
  #   client.response_callbacks.register("HGETALL") do |response|
  #     response.each_slice(2).to_h
  #   end
  #
  # @example With symbolized keys
  #   client.response_callbacks.register("HGETALL") do |response|
  #     response.each_slice(2).map { |k, v| [k.to_sym, v] }.to_h
  #   end
  #
  # @example Time parsing
  #   client.response_callbacks.register("TIME") do |response|
  #     Time.at(response[0].to_i, response[1].to_i)
  #   end
  #
  class ResponseCallbacks
    # Default callbacks for common commands
    DEFAULTS = {
      "INFO" => ->(r) { parse_info(r) },
      "CLIENT LIST" => ->(r) { parse_client_list(r) },
      "DEBUG OBJECT" => ->(r) { parse_debug_object(r) },
      "MEMORY STATS" => ->(r) { r.is_a?(Array) ? r.each_slice(2).to_h : r },
      "CONFIG GET" => ->(r) { r.is_a?(Array) ? r.each_slice(2).to_h : r },
      "ACL LOG" => ->(r) { r.is_a?(Array) ? r.map { |e| e.each_slice(2).to_h } : r },
    }.freeze

    def initialize
      @callbacks = {}
    end

    # Register a callback for a command
    #
    # @param command [String] Command name (e.g., "GET", "HGETALL")
    # @param callback [Proc, nil] Callback proc, or block
    # @yield [response] Block to process response
    # @return [self]
    def register(command, callback = nil, &block)
      cb = callback || block
      raise ArgumentError, "Callback required" unless cb

      @callbacks[normalize_command(command)] = cb
      self
    end

    # Unregister a callback
    #
    # @param command [String] Command name
    # @return [Boolean] true if callback was removed
    def unregister(command)
      @callbacks.delete(normalize_command(command)) ? true : false
    end

    # Check if a callback is registered
    #
    # @param command [String] Command name
    # @return [Boolean]
    def registered?(command)
      @callbacks.key?(normalize_command(command)) || DEFAULTS.key?(normalize_command(command))
    end

    # Apply callback to a response
    #
    # @param command [String] Command name
    # @param response [Object] Raw response
    # @return [Object] Transformed response
    def apply(command, response)
      cmd = normalize_command(command)

      # Check custom callbacks first
      return @callbacks[cmd].call(response) if @callbacks.key?(cmd)

      # Check defaults
      return DEFAULTS[cmd].call(response) if DEFAULTS.key?(cmd)

      # No callback, return as-is
      response
    end

    # Get all registered callbacks
    #
    # @return [Hash] Command => callback mapping
    def to_h
      @callbacks.dup
    end

    # Reset to default callbacks only
    def reset!
      @callbacks.clear
      self
    end

    # Load default callbacks
    #
    # @return [self]
    def load_defaults!
      DEFAULTS.each { |cmd, cb| @callbacks[cmd] = cb }
      self
    end

    private

    def normalize_command(command)
      command.to_s.upcase
    end

    class << self
      # Parse INFO response into a hash
      #
      # @param response [String] Raw INFO response
      # @return [Hash] Parsed info
      def parse_info(response)
        return response unless response.is_a?(String)

        result = {}
        current_section = nil

        response.each_line do |line|
          line = line.strip
          next if line.empty?

          current_section = process_info_line(line, result, current_section)
        end

        result
      end

      def process_info_line(line, result, current_section)
        if line.start_with?("#")
          current_section = line[1..].strip.downcase.to_sym
          result[current_section] ||= {}
        elsif line.include?(":")
          store_info_entry(line, result, current_section)
        end
        current_section
      end

      def store_info_entry(line, result, current_section)
        key, value = line.split(":", 2)
        parsed_value = parse_info_value(value)

        if current_section
          result[current_section][key] = parsed_value
        else
          result[key] = parsed_value
        end
      end

      # Parse a single INFO value
      def parse_info_value(value)
        case value
        when /^\d+$/
          value.to_i
        when /^\d+\.\d+$/
          value.to_f
        else
          value
        end
      end

      # Parse CLIENT LIST response
      #
      # @param response [String] Raw CLIENT LIST response
      # @return [Array<Hash>] List of client info hashes
      def parse_client_list(response)
        return response unless response.is_a?(String)

        response.split("\n").map do |line|
          line.split.each_with_object({}) do |pair, hash|
            key, value = pair.split("=", 2)
            hash[key] = value if key
          end
        end
      end

      # Parse DEBUG OBJECT response
      #
      # @param response [String] Raw DEBUG OBJECT response
      # @return [Hash] Parsed debug info
      def parse_debug_object(response)
        return response unless response.is_a?(String)

        result = {}
        response.split.each do |pair|
          if pair.include?(":")
            key, value = pair.split(":", 2)
            result[key] = parse_info_value(value)
          end
        end
        result
      end
    end
  end
end
