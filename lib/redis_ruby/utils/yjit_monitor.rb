# frozen_string_literal: true

module RedisRuby
  module Utils
    # YJIT performance monitoring utilities
    #
    # Provides methods to check YJIT status and performance metrics.
    # Useful for verifying that redis-ruby is running optimally with YJIT.
    #
    # @example Check YJIT status
    #   RedisRuby::Utils::YJITMonitor.enabled?  # => true
    #   RedisRuby::Utils::YJITMonitor.stats     # => { ratio_in_yjit: 97.5, ... }
    #
    # @example Enable YJIT at runtime (Ruby 3.3+)
    #   RedisRuby::Utils::YJITMonitor.enable!
    #
    module YJITMonitor
      class << self
        # Check if YJIT is available in this Ruby build
        #
        # @return [Boolean]
        def available?
          defined?(RubyVM::YJIT) ? true : false
        end

        # Check if YJIT is currently enabled
        #
        # @return [Boolean]
        def enabled?
          available? && RubyVM::YJIT.enabled?
        end

        # Enable YJIT at runtime (Ruby 3.3+)
        #
        # Best practice: call this after application boot to avoid
        # compiling initialization code.
        #
        # @return [Boolean] true if successfully enabled
        def enable!
          return false unless available?
          return true if enabled?

          if RubyVM::YJIT.respond_to?(:enable)
            RubyVM::YJIT.enable
            true
          else
            false
          end
        end

        # Get YJIT runtime statistics
        #
        # Key metrics:
        # - :ratio_in_yjit - Percentage of time spent in JIT code (target: 95%+)
        # - :code_region_size - Memory used for compiled code
        # - :yjit_alloc_size - Total YJIT memory allocation
        #
        # @return [Hash] YJIT statistics, or empty hash if unavailable
        def stats
          return {} unless enabled?

          RubyVM::YJIT.runtime_stats
        end

        # Get the percentage of execution time in YJIT compiled code
        #
        # Higher is better. Target 95%+ for well-optimized code.
        #
        # @return [Float, nil] Percentage, or nil if unavailable
        def ratio_in_yjit
          return nil unless enabled?

          stats[:ratio_in_yjit]
        end

        # Check if YJIT is performing well
        #
        # Returns true if YJIT is enabled and achieving 90%+ ratio.
        #
        # @return [Boolean]
        def healthy?
          ratio = ratio_in_yjit
          return false unless ratio

          ratio >= 90.0
        end

        # Get formatted status report
        #
        # @return [String] Human-readable status report
        def status_report
          lines = []
          lines << "YJIT Status Report"
          lines << ("-" * 40)
          append_status_details(lines)
          lines.join("\n")
        end

        private

        def append_status_details(lines)
          if !available?
            lines << "YJIT: Not available (Ruby built without YJIT)"
            lines << "Recommendation: Use Ruby 3.1+ with --yjit flag"
          elsif !enabled?
            lines << "YJIT: Available but not enabled"
            lines << "Recommendation: Start Ruby with --yjit or call YJITMonitor.enable!"
          else
            append_enabled_stats(lines)
          end
        end

        def append_enabled_stats(lines)
          s = stats
          lines << "YJIT: Enabled"
          lines << "Ratio in YJIT: #{format("%.1f", s[:ratio_in_yjit] || 0)}%"
          lines << "Code size: #{format_bytes(s[:code_region_size] || 0)}"
          lines << "YJIT alloc: #{format_bytes(s[:yjit_alloc_size] || 0)}"
          lines << ""
          lines << (healthy? ? "Status: Healthy (ratio >= 90%)" : "Status: Suboptimal (ratio < 90%)")
          lines << "Consider increasing --yjit-mem-size" unless healthy?
        end

        def format_bytes(bytes)
          return "0 B" if bytes.zero?

          units = %w[B KB MB GB]
          exp = (Math.log(bytes) / Math.log(1024)).to_i
          exp = [exp, units.length - 1].min
          format("%<size>.1f %<unit>s", size: bytes.to_f / (1024**exp), unit: units[exp])
        end
      end
    end
  end
end
