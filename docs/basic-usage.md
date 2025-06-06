# Basic Usage

This guide covers the fundamental concepts and patterns for using ActionWebhook in your Rails application.

## Core Concepts

### Webhook Classes

Webhook classes are similar to ActionMailer classes. They define methods that correspond to different events in your application:

```ruby
class UserWebhook < ApplicationWebhook
  def created(user)
    @user = user
    @event_type = 'user.created'

    deliver(webhook_endpoints_for('user.created'))
  end

  def updated(user, changes = {})
    @user = user
    @changes = changes
    @event_type = 'user.updated'

    deliver(webhook_endpoints_for('user.updated'))
  end

  def deleted(user_id, user_data)
    @user_id = user_id
    @user_data = user_data
    @event_type = 'user.deleted'

    deliver(webhook_endpoints_for('user.deleted'))
  end

  private

  def webhook_endpoints_for(event)
    WebhookSubscription.active.where(event: event).map do |subscription|
      {
        url: subscription.url,
        headers: subscription.headers
      }
    end
  end
end
```

### Templates

Templates define the JSON payload structure using ERB:

```erb
<!-- app/webhooks/user_webhook/created.json.erb -->
{
  "event": "<%= @event_type %>",
  "timestamp": "<%= Time.current.iso8601 %>",
  "id": "<%= SecureRandom.uuid %>",
  "data": {
    "user": {
      "id": <%= @user.id %>,
      "email": "<%= @user.email %>",
      "name": "<%= @user.name %>",
      "created_at": "<%= @user.created_at.iso8601 %>",
      "updated_at": "<%= @user.updated_at.iso8601 %>"
    }
  },
  "meta": {
    "version": "1.0",
    "source": "user_service"
  }
}
```

### Delivery Methods

ActionWebhook provides three delivery methods:

```ruby
user = User.find(1)

# Immediate delivery (blocking)
UserWebhook.created(user).deliver_now

# Background delivery (non-blocking, recommended)
UserWebhook.created(user).deliver_later

# Test mode (for testing, captures instead of sending)
ActionWebhook::Base.delivery_method = :test
UserWebhook.created(user).deliver_now
```

## Delivery Options

### Queue Management

```ruby
# Use default queue
UserWebhook.created(user).deliver_later

# Use specific queue
UserWebhook.created(user).deliver_later(queue: 'webhooks')

# Use high-priority queue
UserWebhook.created(user).deliver_later(queue: 'webhooks_critical')

# Delay delivery
UserWebhook.created(user).deliver_later(wait: 5.minutes)

# Combine queue and delay
UserWebhook.created(user).deliver_later(
  queue: 'webhooks',
  wait: 1.minute
)
```

### Class-Level Queue Configuration

```ruby
class CriticalWebhook < ApplicationWebhook
  self.deliver_later_queue_name = 'webhooks_critical'

  def payment_failed(payment)
    @payment = payment
    deliver(critical_webhook_endpoints)
  end
end

# All deliveries from CriticalWebhook will use 'webhooks_critical' queue
CriticalWebhook.payment_failed(payment).deliver_later
```

## Endpoint Configuration

### Static Endpoints

```ruby
class NotificationWebhook < ApplicationWebhook
  def system_alert(message)
    @message = message
    @severity = 'high'

    endpoints = [
      {
        url: 'https://slack.com/api/webhooks/your-webhook',
        headers: { 'Content-Type' => 'application/json' }
      },
      {
        url: 'https://your-monitoring.com/alerts',
        headers: {
          'Authorization' => 'Bearer your-token',
          'X-Alert-Source' => 'rails-app'
        }
      }
    ]

    deliver(endpoints)
  end
end
```

### Dynamic Endpoints

```ruby
class OrderWebhook < ApplicationWebhook
  def status_changed(order)
    @order = order
    @previous_status = order.status_was

    # Get endpoints based on order properties
    endpoints = []

    # Customer notification endpoint
    if order.customer.webhook_url.present?
      endpoints << {
        url: order.customer.webhook_url,
        headers: customer_headers(order.customer)
      }
    end

    # Vendor notification endpoints
    order.vendor_integrations.active.each do |integration|
      endpoints << {
        url: integration.webhook_url,
        headers: vendor_headers(integration)
      }
    end

    # Internal system endpoints
    endpoints += internal_system_endpoints(order)

    deliver(endpoints) if endpoints.any?
  end

  private

  def customer_headers(customer)
    {
      'Authorization' => "Bearer #{customer.api_token}",
      'X-Customer-ID' => customer.id.to_s
    }
  end

  def vendor_headers(integration)
    {
      'Authorization' => "Bearer #{integration.secret_token}",
      'X-Vendor-ID' => integration.vendor_id.to_s,
      'X-Integration-Type' => integration.type
    }
  end

  def internal_system_endpoints(order)
    systems = []

    systems << inventory_system_endpoint if order.affects_inventory?
    systems << accounting_system_endpoint if order.affects_accounting?
    systems << shipping_system_endpoint if order.affects_shipping?

    systems.compact
  end
end
```

## Instance Variables

Instance variables defined in webhook methods are automatically available in templates:

```ruby
class ProductWebhook < ApplicationWebhook
  def price_changed(product, old_price, new_price)
    # These instance variables will be available in the template
    @product = product
    @old_price = old_price
    @new_price = new_price
    @change_percentage = ((new_price - old_price) / old_price * 100).round(2)
    @event_time = Time.current
    @triggered_by = Current.user&.email || 'system'

    deliver(product_webhook_endpoints)
  end

  private

  def product_webhook_endpoints
    # Get all active subscriptions for product events
    WebhookSubscription
      .active
      .where(event: ['product.price_changed', 'product.*'])
      .map { |sub| { url: sub.url, headers: sub.headers } }
  end
end
```

Template:
```erb
<!-- app/webhooks/product_webhook/price_changed.json.erb -->
{
  "event": "product.price_changed",
  "timestamp": "<%= @event_time.iso8601 %>",
  "triggered_by": "<%= @triggered_by %>",
  "data": {
    "product": {
      "id": <%= @product.id %>,
      "name": "<%= @product.name %>",
      "sku": "<%= @product.sku %>"
    },
    "price_change": {
      "old_price": <%= @old_price %>,
      "new_price": <%= @new_price %>,
      "change_amount": <%= @new_price - @old_price %>,
      "change_percentage": <%= @change_percentage %>
    }
  }
}
```

## Advanced Patterns

### Conditional Delivery

```ruby
class SmartWebhook < ApplicationWebhook
  def user_activity(user, activity_type, metadata = {})
    return unless should_send_webhook?(user, activity_type)

    @user = user
    @activity_type = activity_type
    @metadata = metadata

    endpoints = relevant_endpoints(user, activity_type)
    deliver(endpoints) if endpoints.any?
  end

  private

  def should_send_webhook?(user, activity_type)
    # Don't send for internal users
    return false if user.internal?

    # Don't send for certain activity types in test mode
    return false if Rails.env.test? && activity_type == 'debug'

    # Rate limiting: don't send too many webhooks for the same user
    return false if recent_webhook_count(user) > 10

    true
  end

  def relevant_endpoints(user, activity_type)
    WebhookSubscription
      .active
      .where(event: ["user.#{activity_type}", 'user.*'])
      .where('user_filters IS NULL OR user_filters @> ?', { user_type: user.type }.to_json)
      .map { |sub| { url: sub.url, headers: sub.headers } }
  end

  def recent_webhook_count(user)
    Rails.cache.fetch("webhook_count:#{user.id}", expires_in: 1.hour) do
      WebhookDelivery.where(
        user_id: user.id,
        created_at: 1.hour.ago..Time.current
      ).count
    end
  end
end
```

### Bulk Operations

```ruby
class BulkWebhook < ApplicationWebhook
  def users_imported(users, import_id)
    @users = users
    @import_id = import_id
    @total_count = users.size
    @success_count = users.count(&:persisted?)
    @error_count = @total_count - @success_count

    deliver(bulk_operation_endpoints)
  end

  # For very large datasets, consider batching
  def large_dataset_updated(dataset_id, batch_size = 1000)
    dataset = Dataset.find(dataset_id)
    total_records = dataset.records.count
    batches = (total_records / batch_size.to_f).ceil

    (0...batches).each do |batch_index|
      @dataset_id = dataset_id
      @batch_index = batch_index
      @batch_size = batch_size
      @total_batches = batches
      @total_records = total_records

      # Use delay to spread out the webhook deliveries
      deliver_later(wait: batch_index * 30.seconds)
    end
  end

  private

  def bulk_operation_endpoints
    WebhookSubscription
      .active
      .where(event: 'bulk.operation')
      .map { |sub| { url: sub.url, headers: sub.headers } }
  end
end
```

### Error Recovery

```ruby
class ResilientWebhook < ApplicationWebhook
  # Custom retry logic
  self.max_retries = 5
  self.retry_delay = 30.seconds
  self.retry_backoff = :exponential

  def critical_event(data)
    @data = data
    @event_id = SecureRandom.uuid

    # Store event for potential replay
    store_event_for_replay(@event_id, data)

    deliver(critical_event_endpoints)
  end

  # Callback for successful delivery
  after_deliver :mark_event_delivered

  # Callback when retries are exhausted
  after_retries_exhausted :handle_delivery_failure

  private

  def store_event_for_replay(event_id, data)
    WebhookEvent.create!(
      event_id: event_id,
      event_type: 'critical_event',
      payload: data,
      webhook_class: self.class.name,
      status: 'pending'
    )
  end

  def mark_event_delivered(response)
    WebhookEvent.find_by(event_id: @event_id)&.update!(
      status: 'delivered',
      delivered_at: Time.current,
      response_data: response
    )
  end

  def handle_delivery_failure(response)
    event = WebhookEvent.find_by(event_id: @event_id)
    event&.update!(
      status: 'failed',
      failure_reason: response.inspect,
      failed_at: Time.current
    )

    # Notify operations team
    OperationsMailer.webhook_delivery_failed(event).deliver_now
  end

  def critical_event_endpoints
    WebhookSubscription
      .active
      .where(event: 'critical.event')
      .order(:priority)
      .map { |sub| { url: sub.url, headers: sub.headers } }
  end
end
```

## Integration with Models

### ActiveRecord Callbacks

```ruby
class User < ApplicationRecord
  after_create_commit :send_created_webhook
  after_update_commit :send_updated_webhook, if: :saved_changes?
  after_destroy_commit :send_deleted_webhook

  private

  def send_created_webhook
    UserWebhook.created(self).deliver_later(queue: 'webhooks')
  end

  def send_updated_webhook
    # Only send webhook for significant changes
    significant_changes = saved_changes.except('updated_at', 'last_seen_at')
    return if significant_changes.empty?

    UserWebhook.updated(self, significant_changes).deliver_later(queue: 'webhooks')
  end

  def send_deleted_webhook
    # Since the record is deleted, we need to pass the data
    user_data = {
      id: id,
      email: email,
      name: name,
      deleted_at: Time.current
    }

    UserWebhook.deleted(id, user_data).deliver_later(queue: 'webhooks')
  end
end
```

### Service Objects

```ruby
class UserRegistrationService
  def call(user_params)
    ActiveRecord::Base.transaction do
      user = User.create!(user_params)
      create_user_profile(user)
      send_welcome_email(user)

      # Send webhook after successful registration
      UserWebhook.registered(user).deliver_later(queue: 'user_events')

      user
    end
  rescue ActiveRecord::RecordInvalid => e
    # Send failure webhook
    RegistrationWebhook.failed(user_params, e.message).deliver_later
    raise
  end

  private

  def create_user_profile(user)
    user.create_profile!(default_profile_attributes)
  end

  def send_welcome_email(user)
    UserMailer.welcome(user).deliver_later
  end

  def default_profile_attributes
    { visibility: 'private', notifications_enabled: true }
  end
end
```

## Next Steps

- [Templates](templates.md) - Learn advanced template techniques
- [Queue Management](queue-management.md) - Organize webhook processing
- [Retry Logic](retry-logic.md) - Handle failures gracefully
- [Testing](testing.md) - Write tests for your webhooks
