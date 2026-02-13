# frozen_string_literal: true

require_relative "lib/sift/version"

Gem::Specification.new do |spec|
  spec.name = "sift"
  spec.version = Sift::VERSION
  spec.authors = ["Derek Sivers"]
  spec.email = ["derek@sivers.org"]

  spec.summary = "Human-in-the-loop code review with Claude"
  spec.description = "Interactive TUI for reviewing code changes with AI-powered analysis and session continuity"
  spec.homepage = "https://github.com/sivers/sift"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.files = Dir.glob(%w[
    lib/**/*.rb
    exe/*
    LICENSE.txt
    README.md
  ])
  spec.bindir = "exe"
  spec.executables = ["sift", "sq"]
  spec.require_paths = ["lib"]

  spec.add_dependency "async", "~> 2.0"
  spec.add_dependency "cli-ui", "~> 2.0"
  spec.add_dependency "logger"
  spec.add_dependency "reline"

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "minitest-reporters", "~> 1.6"
  spec.add_development_dependency "rake", "~> 13.0"

  spec.metadata["rubygems_mfa_required"] = "true"
end
