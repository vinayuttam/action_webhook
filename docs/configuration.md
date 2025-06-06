# Configuration

ActionWebhook provides extensive configuration options to customize its behavior for your application's needs.

## Global Configuration

Configure ActionWebhook in `config/initializers/action_webhook.rb`:

```ruby
# config/initializers/action_webhook.rb
ActionWebhook.configure do |config|
  # Default queue for background jobs
  config.default_queue_name = 'webhooks'

  # Default headers for all webhook requests
  config.default_headers = {
    'User-Agent' => 'YourApp/1.0',
    'X-Webhook-Source' => 'your-app'
  }

  # Default delivery method (:deliver_now, :deliver_later, or :test)
  config.delivery_method = :deliver_later

  # Enable/disable webhook deliveries globally
  config.perform_deliveries = Rails.env.production?

  # Default retry configuration
  config.max_retries = 3
  config.retry_delay = 30.seconds
  config.retry_backoff = :exponential # :exponential, :linear, or :none
  config.retry_jitter = 5.seconds

  # Timeout for HTTP requests
  config.request_timeout = 10.seconds

  # Custom job class for delivery
  config.delivery_job = 'ActionWebhook::DeliveryJob'
end
```

## Class-Level Configuration

Configure individual webhook classes:

```ruby
class UserWebhook < ApplicationWebhook
  # Custom queue for this webhook
  self.deliver_later_queue_name = 'user_webhooks'

  # Custom retry settings
  self.max_retries = 5
  self.retry_delay = 1.minute
  self.retry_backoff = :linear

  # Custom headers for all requests from this webhook
  self.default_headers = {
    'X-Webhook-Type' => 'user-events',
    'Authorization' => 'Bearer your-token'
  }

  # Custom delivery job
  self.delivery_job = CustomWebhookJob

  def created(user)
    @user = user
    deliver(webhook_endpoints)
  end
end
```

## Environment-Specific Configuration

### Development

```ruby
# config/environments/development.rb
config.after_initialize do
  ActionWebhook.configure do |webhook_config|
    # Use test mode in development
    webhook_config.delivery_method = :test
    webhook_config.perform_deliveries = false
  end
end
```

### Test

```ruby
# config/environments/test.rb
config.after_initialize do
  ActionWebhook.configure do |webhook_config|
    webhook_config.delivery_method = :test
    webhook_config.perform_deliveries = false
  end
end
```

### Production

```ruby
# config/environments/production.rb
config.after_initialize do
  ActionWebhook.configure do |webhook_config|
    webhook_config.delivery_method = :deliver_later
    webhook_config.perform_deliveries = true
    webhook_config.max_retries = 5
    webhook_config.retry_delay = 2.minutes
  end
end
```

## Queue Configuration

### Using Sidekiq

```ruby
# config/initializers/sidekiq.rb
Sidekiq.configure_server do |config|
  config.redis = { url: ENV['REDIS_URL'] }
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV['REDIS_URL'] }
end

# Define webhook-specific queues
# config/schedule.rb (if using sidekiq-cron)
Sidekiq::Cron::Job.load_from_hash({
  'webhook_processor' => {
    'cron' => '*/5 * * * *',
    'class' => 'WebhookProcessorJob',
    'queue' => 'webhooks'
  }
})
```

### Queue Priority

```ruby
# config/initializers/action_webhook.rb
ActionWebhook.configure do |config|
  # High priority for critical webhooks
  config.critical_queue = 'webhooks_critical'

  # Normal priority for standard webhooks
  config.default_queue_name = 'webhooks'

  # Low priority for bulk operations
  config.bulk_queue = 'webhooks_bulk'
end

# Usage in webhook classes
class PaymentWebhook < ApplicationWebhook
  self.deliver_later_queue_name = ActionWebhook.config.critical_queue
end

class BulkUserWebhook < ApplicationWebhook
  self.deliver_later_queue_name = ActionWebhook.config.bulk_queue
end
```

## Retry Configuration

### Basic Retry Settings

```ruby
class CriticalWebhook < ApplicationWebhook
  # Retry up to 10 times
  self.max_retries = 10

  # Start with 1 minute delay
  self.retry_delay = 1.minute

  # Use exponential backoff (1min, 2min, 4min, 8min, etc.)
  self.retry_backoff = :exponential

  # Add random jitter to prevent thundering herd
  self.retry_jitter = 30.seconds
end
```

### Advanced Retry Logic

```ruby
class SmartWebhook < ApplicationWebhook
  # Custom retry logic based on response
  def should_retry?(response)
    return false if response[:status] == 400 # Bad request - don't retry
    return false if response[:status] == 401 # Unauthorized - don't retry
    return true if response[:status] >= 500  # Server error - retry
    return true if response[:error]&.include?('timeout') # Timeout - retry

    false
  end

  # Custom retry delay based on attempt number
  def calculate_retry_delay(attempt)
    base_delay = self.class.retry_delay
    case attempt
    when 1..2
      base_delay
    when 3..5
      base_delay * 2
    else
      base_delay * 5
    end
  end
end
```

## Security Configuration

### Authentication

```ruby
class SecureWebhook < ApplicationWebhook
  self.default_headers = {
    'Authorization' => -> { "Bearer #{ENV['WEBHOOK_SECRET']}" },
    'X-API-Key' => ENV['API_KEY']
  }
end
```

### Signing Webhooks

```ruby
class SignedWebhook < ApplicationWebhook
  private

  def build_headers(detail_headers)
    headers = super

    # Add webhook signature
    payload_json = build_payload.to_json
    signature = OpenSSL::HMAC.hexdigest('SHA256', ENV['WEBHOOK_SECRET'], payload_json)
    headers['X-Webhook-Signature'] = "sha256=#{signature}"

    headers
  end
end
```

## Database Configuration

### Webhook Subscriptions Model

```ruby
# app/models/webhook_subscription.rb
class WebhookSubscription < ApplicationRecord
  validates :url, presence: true, format: URI::DEFAULT_PARSER.make_regexp(%w[http https])
  validates :event, presence: true
  validates :secret_token, presence: true

  scope :active, -> { where(active: true) }
  scope :for_event, ->(event) { where(event: event) }

  def headers
    {
      'Authorization' => "Bearer #{secret_token}",
      'Content-Type' => 'application/json'
    }.merge(custom_headers.to_h)
  end
end

# Migration
class CreateWebhookSubscriptions < ActiveRecord::Migration[7.0]
  def change
    create_table :webhook_subscriptions do |t|
      t.string :url, null: false
      t.string :event, null: false
      t.string :secret_token, null: false
      t.json :custom_headers, default: {}
      t.boolean :active, default: true
      t.timestamps
    end

    add_index :webhook_subscriptions, [:event, :active]
    add_index :webhook_subscriptions, :url
  end
end
```

## Logging Configuration

```ruby
# config/initializers/action_webhook.rb
ActionWebhook.configure do |config|
  # Custom logger
  config.logger = Rails.logger

  # Log level for webhook operations
  config.log_level = :info

  # Enable detailed logging in development
  if Rails.env.development?
    config.log_level = :debug
    config.log_requests = true
    config.log_responses = true
  end
end
```

## Monitoring Configuration

### Integration with Application Monitoring

```ruby
# config/initializers/action_webhook.rb
ActionWebhook.configure do |config|
  # Custom metrics reporting
  config.on_delivery_success = ->(webhook, response) {
    Metrics.increment('webhooks.delivered.success', tags: {
      webhook_class: webhook.class.name,
      url: response[:url]
    })
  }

  config.on_delivery_failure = ->(webhook, response) {
    Metrics.increment('webhooks.delivered.failure', tags: {
      webhook_class: webhook.class.name,
      error: response[:error],
      status: response[:status]
    })
  }
end
```

### Health Checks

```ruby
# app/controllers/health_controller.rb
class HealthController < ApplicationController
  def webhooks
    # Check webhook system health
    healthy = ActionWebhook.healthy?

    if healthy
      render json: { status: 'healthy', timestamp: Time.current }
    else
      render json: { status: 'unhealthy', timestamp: Time.current }, status: 503
    end
  end
end
```

## Next Steps

- [Queue Management](queue-management.md) - Organize webhook processing
- [Error Handling](error-handling.md) - Handle failures gracefully
- [Security](security.md) - Secure your webhook deliveries
