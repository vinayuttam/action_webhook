# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "action_webhook"

require "minitest/autorun"
require "active_support"
require "active_support/test_case"

# Mock Rails.logger for testing
class MockLogger
  def info(msg); end
  def warn(msg); end
  def error(msg); end
end

# Set up a mock logger
ActionWebhook::Base.class_eval do
  private

  def logger
    @logger ||= MockLogger.new
  end
end
