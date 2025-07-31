# frozen_string_literal: true

require_relative "lib/action_webhook/version"

Gem::Specification.new do |spec|
  spec.name = "action_webhook"
  spec.version = ActionWebhook::VERSION
  spec.authors = ["Vinay Uttam Vemparala"]
  spec.email = ["15381417+vinayuttam@users.noreply.github.com"]

  spec.summary = "A gem for triggering webhooks similar to trigger emails on Rails"
  spec.description = "A Rails library for triggering webhooks. Inspired by ActionMailer from Rails"
  spec.homepage = "https://github.com/vinayuttam/action_webhook"
  spec.required_ruby_version = ">= 3.1.0"
  spec.license = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/vinayuttam/action_webhook/tree/main"
  spec.metadata["changelog_uri"] = "https://github.com/vinayuttam/action_webhook/blob/main/CHANGELOG.md"

  spec.files         = Dir["lib/**/*"]
  spec.require_paths = ["lib"]

  # Core dependencies
  spec.add_dependency "activejob", ">= 6.0", "< 8.0"
  spec.add_dependency "globalid", "~> 1.0"
  spec.add_dependency "httparty", "~> 0.18.1"

  spec.add_development_dependency "yard", "~> 0.9"
end
