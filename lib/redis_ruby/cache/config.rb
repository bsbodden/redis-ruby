# frozen_string_literal: true

module RR
  class Cache
    # Immutable configuration for client-side caching
    #
    # @example Default config
    #   config = Cache::Config.new
    #
    # @example Custom config
    #   config = Cache::Config.new(max_entries: 5000, ttl: 300, mode: :optin)
    #
    # @example From shorthand
    #   Config.from(true)                    # => default config
    #   Config.from(max_entries: 5000)       # => custom config
    #   Config.from(Config.new(...))         # => passthrough
    #
    class Config
      VALID_MODES = %i[default optin optout broadcast].freeze

      attr_reader :max_entries, :ttl, :mode, :cacheable_commands, :key_filter, :store

      # @param max_entries [Integer] Maximum cache size (LRU eviction)
      # @param ttl [Float, nil] Time-to-live for entries in seconds (nil = no TTL)
      # @param mode [Symbol] :default, :optin, :optout, or :broadcast
      # @param cacheable_commands [Array<String>, nil] Custom allow list (nil = default)
      # @param key_filter [Proc, nil] Proc for key filtering
      # @param store [Cache::Store, nil] Custom store backend (nil = built-in LRU)
      def initialize(max_entries: DEFAULT_MAX_ENTRIES, ttl: DEFAULT_TTL, mode: :default,
                     cacheable_commands: nil, key_filter: nil, store: nil)
        validate_mode!(mode)
        validate_max_entries!(max_entries)

        @max_entries = max_entries
        @ttl = ttl
        @mode = mode.to_sym
        @cacheable_commands = cacheable_commands&.map(&:upcase)&.freeze
        @key_filter = key_filter
        @store = store
        freeze
      end

      # Build a Config from various shorthand forms
      #
      # @param option [Boolean, Hash, Config] Cache option
      # @return [Config]
      def self.from(option)
        case option
        when true then new
        when Hash then new(**option)
        when Config then option
        else raise ArgumentError, "Invalid cache option: #{option.inspect}"
        end
      end

      private

      def validate_mode!(mode)
        return if VALID_MODES.include?(mode.to_sym)

        raise ArgumentError, "Invalid mode: #{mode.inspect}. Valid modes: #{VALID_MODES.join(", ")}"
      end

      def validate_max_entries!(max_entries)
        return if max_entries.is_a?(Integer) && max_entries > 0

        raise ArgumentError, "max_entries must be a positive Integer, got #{max_entries.inspect}"
      end
    end
  end
end
