# frozen_string_literal: true

require_relative "lib/redis_ruby/version"

Gem::Specification.new do |spec|
  spec.name = "redis-ruby"
  spec.version = RR::VERSION
  spec.authors = ["Brian Sam-Bodden"]
  spec.email = ["brian@redis.com"]

  spec.summary = "A modern, high-performance Redis client for Ruby"
  spec.description = <<~DESC
    redis-ruby is a next-generation Redis client for Ruby, built from the ground up
    for performance, developer experience, and full Redis 8+ feature support including
    JSON, Search, TimeSeries, and probabilistic data structures.
  DESC
  spec.homepage = "https://github.com/redis-developer/redis-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/redis-developer/redis-ruby"
  spec.metadata["changelog_uri"] = "https://github.com/redis-developer/redis-ruby/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://rubydoc.info/gems/redis-ruby"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies (connection_pool for future pooling support)
  spec.add_dependency "connection_pool", "~> 2.4"
end
