# frozen_string_literal: true

# redis-rb compatibility layer
#
# This file provides backward compatibility for users migrating from redis-rb.
# Simply require "redis" and use the Redis class as you would with redis-rb.
#
# For the native redis-ruby API, use:
#   require "redis_ruby"
#   client = RR.new  # (after we complete the RR rename)
#
require_relative "redis-rb-compat"
