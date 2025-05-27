# frozen_string_literal: true

module ActionWebhook
  # Job responsible for delivering webhooks in the background
  class DeliveryJob < ActiveJob::Base
    queue_as { ActionWebhook::Base.deliver_later_queue_name || :webhooks }

    # Performs the webhook delivery with the specified delivery method
    #
    # @param delivery_method [String] The delivery method to call (e.g., "deliver_now")
    # @param serialized_webhook [Hash] The serialized webhook data
    def perform(delivery_method, serialized_webhook)
      # Reconstruct the webhook from serialized data
      webhook_class = serialized_webhook["webhook_class"].constantize
      webhook = webhook_class.new
      webhook.deserialize(serialized_webhook)

      # Invoke the specified delivery method
      webhook.send(delivery_method)
    end

    # Handles serialization failures by logging errors
    rescue_from StandardError do |exception|
      # Log the error
      Rails.logger.error("ActionWebhook delivery failed: #{exception.message}")
      Rails.logger.error(exception.backtrace.join("\n"))

      # Re-raise the exception if in development or test
      raise exception if Rails.env.development? || Rails.env.test?
    end
  end
end
