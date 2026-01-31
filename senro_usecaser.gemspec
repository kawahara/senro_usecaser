# frozen_string_literal: true

require_relative "lib/senro_usecaser/version"

Gem::Specification.new do |spec|
  spec.name = "senro_usecaser"
  spec.version = SenroUsecaser::VERSION
  spec.authors = ["Shogo Kawahara"]
  spec.email = ["kawahara@bucyou.net"]

  spec.summary = "A type-safe UseCase pattern implementation library for Ruby"
  spec.description = <<~DESC
    SenroUsecaser is a UseCase pattern implementation library for Ruby.
    It provides type-safe input/output, DI container with namespaces,
    and flexible composition with organize/include/extend patterns.
    Compatible with both Steep (RBS) and Sorbet.
  DESC
  spec.homepage = "https://github.com/kawahara/senro_usecaser"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # No runtime dependencies - pure Ruby implementation
end
