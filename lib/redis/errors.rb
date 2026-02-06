# frozen_string_literal: true

class Redis
  # Base error class for all Redis errors
  # Maintains compatibility with redis-rb's error hierarchy
  class BaseError < StandardError; end

  # Raised when a command fails
  class CommandError < BaseError; end

  # Raised when a connection cannot be established or is lost
  class ConnectionError < BaseError; end

  # Raised when a timeout occurs
  class TimeoutError < BaseError; end

  # Raised when authentication fails
  class AuthenticationError < CommandError; end

  # Raised when permission is denied
  class PermissionError < CommandError; end

  # Raised when WRONGTYPE error occurs
  class WrongTypeError < CommandError; end

  # Raised during cluster operations
  class ClusterError < BaseError; end

  # Raised when cluster is down
  class ClusterDownError < ClusterError; end

  # Cluster redirect errors
  class MovedError < ClusterError
    attr_reader :slot, :host, :port

    def initialize(message)
      super
      # Parse "MOVED 12345 127.0.0.1:6379" format
      return unless message =~ /MOVED (\d+) ([^:]+):(\d+)/

      @slot = ::Regexp.last_match(1).to_i
      @host = ::Regexp.last_match(2)
      @port = ::Regexp.last_match(3).to_i
    end
  end

  class AskError < ClusterError
    attr_reader :slot, :host, :port

    def initialize(message)
      super
      # Parse "ASK 12345 127.0.0.1:6379" format
      return unless message =~ /ASK (\d+) ([^:]+):(\d+)/

      @slot = ::Regexp.last_match(1).to_i
      @host = ::Regexp.last_match(2)
      @port = ::Regexp.last_match(3).to_i
    end
  end

  # Raised when trying to access a Future that hasn't been resolved
  class FutureNotReady < RuntimeError
    def initialize
      super("Value will be available once the pipeline executes")
    end
  end

  # Raised when a protocol error occurs
  class ProtocolError < BaseError; end

  # Module for translating RedisRuby errors to Redis errors
  module ErrorTranslation
    module_function

    # Translate a RedisRuby error to a Redis error
    #
    # @param error [Exception] original error
    # @return [Exception] translated error
    def translate(error)
      case error
      when ::RedisRuby::ConnectionError
        Redis::ConnectionError.new(error.message)
      when ::RedisRuby::TimeoutError
        Redis::TimeoutError.new(error.message)
      when ::RedisRuby::CommandError
        translate_command_error(error)
      when ::RedisRuby::ClusterDownError
        Redis::ClusterDownError.new(error.message)
      when ::RedisRuby::MovedError
        Redis::MovedError.new(error.message)
      when ::RedisRuby::AskError
        Redis::AskError.new(error.message)
      when ::RedisRuby::ClusterError
        Redis::ClusterError.new(error.message)
      else
        error
      end
    end

    # Translate command errors to more specific types
    def translate_command_error(error)
      message = error.message
      case message
      when /WRONGTYPE/
        Redis::WrongTypeError.new(message)
      when /NOAUTH|ERR.*AUTH/i
        Redis::AuthenticationError.new(message)
      when /NOPERM/
        Redis::PermissionError.new(message)
      else
        Redis::CommandError.new(message)
      end
    end
  end
end
