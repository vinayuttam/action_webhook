# frozen_string_literal: true

require "active_job"
require "httparty"

require "action_webhook/version"
require "action_webhook/delivery_job"
require "action_webhook/base"

module ActionWebhook
  class Error < StandardError; end
end
