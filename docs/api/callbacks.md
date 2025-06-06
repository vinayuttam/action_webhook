# ActionWebhook Callbacks API Reference

ActionWebhook provides a comprehensive callback system that allows you to hook into various stages of the webhook delivery lifecycle. This enables custom logging, monitoring, error handling, and other cross-cutting concerns.

## Overview

Callbacks are methods that get executed at specific points during webhook processing. They provide hooks for:

- Pre-delivery setup and validation
- Post-delivery processing and cleanup
- Error handling and recovery
- Retry logic customization
- Metrics and monitoring

## Available Callbacks

### Delivery Lifecycle Callbacks

#### `after_deliver`

Called after successful webhook delivery to all endpoints.

**Method Signature:**
```ruby
after_deliver(callback_method = nil, &block)
```

**Callback Method Signature:**
```ruby
def callback_method(response)
  # response is an array of response hashes
end
```

**Example:**
```ruby
class UserWebhook < ActionWebhook::Base
  after_deliver :log_success

  def created(user)
    @user = user
    deliver(endpoints)
  end

  private

  def log_success(response)
    Rails.logger.info "Webhook delivered successfully for user #{@user.id}"
    response.each do |resp|
      Rails.logger.info "  -> #{resp[:url]}: #{resp[:status]}"
    end
  end
end
```

**With Block:**
```ruby
class UserWebhook < ActionWebhook::Base
  after_deliver do |response|
    UserWebhookDelivery.create!(
      user_id: @user.id,
      endpoints_count: response.size,
      delivered_at: Time.current
    )
  end
end
```

#### `after_retries_exhausted`

Called when all retry attempts have been exhausted and the webhook still fails.

**Method Signature:**
```ruby
after_retries_exhausted(callback_method = nil, &block)
```

**Callback Method Signature:**
```ruby
def callback_method(response)
  # response is an array of response hashes with errors
end
```

**Example:**
```ruby
class UserWebhook < ActionWebhook::Base
  after_retries_exhausted :handle_failure

  private

  def handle_failure(response)
    Rails.logger.error "Webhook delivery failed permanently for user #{@user.id}"

    # Send alert to monitoring service
    AlertService.webhook_failure(
      webhook: self.class.name,
      user_id: @user.id,
      errors: response.map { |r| r[:error] }
    )

    # Create failure record
    WebhookFailure.create!(
      webhook_class: self.class.name,
      action: @action_name,
      user_id: @user.id,
      response: response,
      failed_at: Time.current
    )
  end
end
```

### Custom Callback Types

You can define your own callback types using `define_callbacks`:

```ruby
class UserWebhook < ActionWebhook::Base
  extend ActiveSupport::Callbacks

  define_callbacks :before_delivery, :after_endpoint_delivery

  set_callback :before_delivery, :before, :validate_payload
  set_callback :after_endpoint_delivery, :after, :log_endpoint_result

  def created(user)
    @user = user
    run_callbacks :before_delivery do
      endpoints.each do |endpoint|
        result = deliver_to_endpoint(endpoint)
        run_callbacks :after_endpoint_delivery do
          process_endpoint_result(result)
        end
      end
    end
  end

  private

  def validate_payload
    raise "Invalid user data" unless @user&.valid?
  end

  def log_endpoint_result
    Rails.logger.info "Delivered to endpoint: #{@current_endpoint}"
  end
end
```

## Callback Context

### Available Instance Variables

Callbacks have access to all instance variables set in the webhook method:

```ruby
class OrderWebhook < ActionWebhook::Base
  after_deliver :update_order_status

  def shipped(order, tracking_info)
    @order = order
    @tracking_info = tracking_info
    @shipped_at = Time.current
    deliver(endpoints)
  end

  private

  def update_order_status(response)
    # All instance variables are available
    @order.update!(
      webhook_delivered_at: @shipped_at,
      tracking_webhook_sent: true
    )
  end
end
```

### Response Format

The response parameter contains an array of hashes with the following structure:

```ruby
[
  {
    success: true,
    status: 200,
    url: "https://api.example.com/webhook",
    attempt: 1,
    response_time: 0.25
  },
  {
    success: false,
    status: 500,
    error: "Internal Server Error",
    url: "https://api.other.com/webhook",
    attempt: 3,
    response_time: 5.0
  }
]
```

## Advanced Callback Patterns

### Conditional Callbacks

Execute callbacks only under certain conditions:

```ruby
class UserWebhook < ActionWebhook::Base
  after_deliver :send_notification, if: :high_priority_user?
  after_deliver :update_analytics, unless: :test_environment?

  private

  def high_priority_user?
    @user.premium? || @user.admin?
  end

  def test_environment?
    Rails.env.test?
  end

  def send_notification(response)
    NotificationService.webhook_delivered(@user, response)
  end

  def update_analytics(response)
    Analytics.track_webhook_delivery(
      user_id: @user.id,
      webhook_type: @action_name,
      success_rate: calculate_success_rate(response)
    )
  end
end
```

### Callback Inheritance

Callbacks are inherited by subclasses:

```ruby
class BaseWebhook < ActionWebhook::Base
  after_deliver :log_delivery
  after_retries_exhausted :alert_operations

  private

  def log_delivery(response)
    Rails.logger.info "#{self.class.name} delivered successfully"
  end

  def alert_operations(response)
    OperationsAlert.webhook_failed(self.class.name, response)
  end
end

class UserWebhook < BaseWebhook
  # Inherits both callbacks from BaseWebhook
  after_deliver :update_user_stats  # Additional callback

  private

  def update_user_stats(response)
    @user.increment_webhook_deliveries!
  end
end
```

### Multiple Callbacks

You can register multiple callbacks of the same type:

```ruby
class UserWebhook < ActionWebhook::Base
  after_deliver :log_success
  after_deliver :update_metrics
  after_deliver :send_confirmation

  private

  def log_success(response)
    Rails.logger.info "Webhook delivered for user #{@user.id}"
  end

  def update_metrics(response)
    Metrics.increment('webhook.delivery.success')
  end

  def send_confirmation(response)
    UserMailer.webhook_delivered(@user).deliver_later
  end
end
```

## Error Handling in Callbacks

### Callback Error Isolation

Errors in callbacks don't affect webhook delivery:

```ruby
class UserWebhook < ActionWebhook::Base
  after_deliver :risky_callback
  after_deliver :safe_callback

  private

  def risky_callback(response)
    # This might fail, but won't prevent safe_callback from running
    ThirdPartyService.unreliable_call(@user)
  rescue => e
    Rails.logger.error "Callback failed: #{e.message}"
    # Webhook delivery still succeeds
  end

  def safe_callback(response)
    # This will still execute even if risky_callback fails
    @user.touch(:last_webhook_at)
  end
end
```

### Callback-Specific Error Handling

```ruby
class UserWebhook < ActionWebhook::Base
  after_deliver do |response|
    begin
      ComplexAnalytics.process_webhook_data(@user, response)
    rescue Analytics::ProcessingError => e
      # Handle analytics-specific errors
      Rails.logger.warn "Analytics processing failed: #{e.message}"
      ErrorTracker.notify(e, user_id: @user.id)
    rescue => e
      # Handle any other errors
      Rails.logger.error "Unexpected callback error: #{e.message}"
      raise if Rails.env.development?
    end
  end
end
```

## Testing Callbacks

### Unit Testing

```ruby
# spec/webhooks/user_webhook_spec.rb
RSpec.describe UserWebhook do
  let(:user) { create(:user) }
  let(:webhook) { UserWebhook.new }

  describe 'callbacks' do
    before do
      webhook.instance_variable_set(:@user, user)
    end

    it 'logs success after delivery' do
      response = [{ success: true, url: 'http://example.com' }]

      expect(Rails.logger).to receive(:info)
        .with("Webhook delivered successfully for user #{user.id}")

      webhook.send(:log_success, response)
    end

    it 'handles failure after retries exhausted' do
      response = [{ success: false, error: 'Connection failed' }]

      expect(AlertService).to receive(:webhook_failure)
      expect(WebhookFailure).to receive(:create!)

      webhook.send(:handle_failure, response)
    end
  end
end
```

### Integration Testing

```ruby
# spec/integration/webhook_callbacks_spec.rb
RSpec.describe 'Webhook Callbacks' do
  let(:user) { create(:user) }

  it 'executes callbacks after successful delivery' do
    stub_request(:post, 'http://example.com/webhook')
      .to_return(status: 200)

    expect {
      UserWebhook.created(user).deliver_now
    }.to change(UserWebhookDelivery, :count).by(1)
      .and change { user.reload.last_webhook_at }
  end

  it 'executes failure callbacks after retries exhausted' do
    stub_request(:post, 'http://example.com/webhook')
      .to_return(status: 500).times(3)  # Max retries

    expect {
      UserWebhook.created(user).deliver_now
    }.to change(WebhookFailure, :count).by(1)
  end
end
```

## Performance Considerations

### Asynchronous Callbacks

For expensive callback operations, consider moving them to background jobs:

```ruby
class UserWebhook < ActionWebhook::Base
  after_deliver :trigger_async_processing

  private

  def trigger_async_processing(response)
    # Quick callback that enqueues heavy work
    AnalyticsProcessingJob.perform_later(@user.id, response)
    MetricsUpdateJob.perform_later(self.class.name, @action_name)
  end
end
```

### Callback Optimization

```ruby
class UserWebhook < ActionWebhook::Base
  after_deliver :optimized_callback

  private

  def optimized_callback(response)
    # Batch operations when possible
    updates = {
      last_webhook_at: Time.current,
      webhook_count: @user.webhook_count + 1
    }
    @user.update_columns(updates)  # Single query

    # Use efficient queries
    Rails.cache.increment("webhooks:#{Date.current}:count")
  end
end
```

## Best Practices

### 1. Keep Callbacks Lightweight

```ruby
# Good: Lightweight callback
after_deliver :record_delivery

def record_delivery(response)
  @user.touch(:last_webhook_at)
end

# Avoid: Heavy processing in callbacks
after_deliver :process_complex_analytics  # Move to background job instead
```

### 2. Handle Errors Gracefully

```ruby
# Always wrap risky operations
after_deliver do |response|
  begin
    ExternalService.notify(response)
  rescue => e
    Rails.logger.warn "External service notification failed: #{e.message}"
    # Don't re-raise unless critical
  end
end
```

### 3. Use Descriptive Method Names

```ruby
# Good: Clear purpose
after_deliver :update_delivery_metrics
after_retries_exhausted :alert_webhook_failure

# Avoid: Generic names
after_deliver :callback1
after_deliver :do_stuff
```

### 4. Document Complex Callbacks

```ruby
class UserWebhook < ActionWebhook::Base
  # Updates user engagement metrics and triggers
  # downstream analytics processing
  after_deliver :process_engagement_metrics

  private

  def process_engagement_metrics(response)
    # Implementation with clear comments
  end
end
```

## See Also

- [ActionWebhook::Base](base.md) - Main webhook class
- [Error Handling](../error-handling.md) - Error handling strategies
- [Testing](../testing.md) - Testing webhooks and callbacks
- [Basic Usage](../basic-usage.md) - Core webhook concepts
