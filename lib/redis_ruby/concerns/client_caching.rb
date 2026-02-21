# frozen_string_literal: true

module RR
  module Concerns
    # Extracted client-side caching helpers shared across Client, PooledClient, and SentinelClient
    #
    # Provides build_cache and cache-aware call path helpers.
    module ClientCaching
      private

      # Build and wire cache from option
      def build_cache(cache_option)
        config = Cache::Config.from(cache_option)
        @cache = Cache.new(self, config)
      end

      # Execute command through cache if enabled, otherwise direct
      def call_via_cache(command, args, &)
        if @cache&.enabled? && !args.empty?
          @cache.fetch(command, args[0], *args[1..], &)
        else
          yield
        end
      end

      # Execute 1-arg command through cache if enabled
      def call_1arg_via_cache(command, &)
        if @cache&.enabled?
          @cache.fetch(command, &)
        else
          yield
        end
      end

      # Execute 2-arg command through cache if enabled
      def call_2args_via_cache(command, arg1, arg2, &)
        if @cache&.enabled?
          @cache.fetch(command, arg1, arg2, &)
        else
          yield
        end
      end

      # Execute 3-arg command through cache if enabled
      def call_3args_via_cache(command, arg1, arg2, arg3, &)
        if @cache&.enabled?
          @cache.fetch(command, arg1, arg2, arg3, &)
        else
          yield
        end
      end
    end
  end
end
