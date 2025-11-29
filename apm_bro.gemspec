# frozen_string_literal: true

require_relative "lib/apm_bro/version"

Gem::Specification.new do |spec|
  spec.name = "apm_bro"
  spec.version = ApmBro::VERSION
  spec.authors = ["Emanuel Comsa"]
  spec.email = ["office@rubydev.ro"]

  spec.summary = "Minimal APM for Rails apps."
  spec.description = "Gem used by DeadBro - Rails APM to track performance metrics of Rails apps."
  spec.homepage = "https://www.deadbro.com"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = "https://www.deadbro.com"
  spec.metadata["source_code_uri"] = "https://github.com/rubydevro/apm_bro"

  spec.require_paths = ["lib"]
  spec.files = Dir["lib/**/*", "*.md", "*.txt"]
end
