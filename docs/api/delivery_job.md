# ActionWebhook::DeliveryJob API Reference

The `ActionWebhook::DeliveryJob` is an ActiveJob class responsible for executing webhook deliveries in the background. It handles the serialization/deserialization of webhook data and manages error handling for background processing.

## Class Overview

```ruby
class ActionWebhook::DeliveryJob < ActiveJob::Base
  queue_as { ActionWebhook::Base.deliver_later_queue_name || :webhooks }

  rescue_from StandardError do |exception|
    # Error handling logic
  end
end
```

## Queue Configuration

The job uses a configurable queue name that can be set globally or per webhook class:

- **Global queue**: Set via `ActionWebhook::Base.deliver_later_queue_name`
- **Default queue**: `:webhooks` if no custom queue is specified
- **Per-class queue**: Can be overridden in individual webhook classes

## Methods

### `#perform(delivery_method, serialized_webhook)`

Executes the webhook delivery in the background.

**Parameters:**
- `delivery_method` (String): The method to call on the webhook instance (typically "deliver_now")
- `serialized_webhook` (Hash): The serialized webhook data containing all necessary information

**Process:**
1. Deserializes the webhook data
2. Reconstructs the webhook instance
3. Calls the specified delivery method
4. Handles any errors that occur during execution

**Example:**
```ruby
# This is typically called internally by ActionWebhook
ActionWebhook::DeliveryJob.perform_later(
  "deliver_now",
  {
    "webhook_class" => "UserWebhook",
    "action_name" => "created",
    "webhook_details" => [...],
    "params" => {...},
    "attempts" => 0,
    "instance_variables" => {...}
  }
)
```

## Error Handling

The job includes comprehensive error handling:

### Standard Error Rescue

```ruby
rescue_from StandardError do |exception|
  Rails.logger.error("ActionWebhook delivery failed: #{exception.message}")
  Rails.logger.error(exception.backtrace.join("\n"))

  # Re-raise in development/test for debugging
  raise exception if Rails.env.development? || Rails.env.test?
end
```

### Error Scenarios

1. **Serialization Errors**: Issues with webhook data serialization/deserialization
2. **Network Errors**: HTTP connection failures, timeouts
3. **Application Errors**: Custom webhook logic failures
4. **Queue Adapter Errors**: Issues with the ActiveJob backend

## Queue Integration

### Supported Adapters

Works with all ActiveJob queue adapters:

- **Sidekiq**: `config.active_job.queue_adapter = :sidekiq`
- **Resque**: `config.active_job.queue_adapter = :resque`
- **Delayed Job**: `config.active_job.queue_adapter = :delayed_job`
- **Async**: `config.active_job.queue_adapter = :async` (development)
- **Inline**: `config.active_job.queue_adapter = :inline` (testing)

### Queue Priority

```ruby
# Set queue priority in webhook class
class UserWebhook < ActionWebhook::Base
  self.deliver_later_queue_name = 'high_priority_webhooks'
end

# Or when enqueuing
UserWebhook.created(user).deliver_later(queue: 'urgent')
```

## Monitoring and Observability

### Logging

The job automatically logs:
- Job execution start/completion
- Error details with full stack traces
- Webhook delivery attempts and results

### Metrics Integration

Can be integrated with monitoring systems:

```ruby
# Custom job class with metrics
class MonitoredDeliveryJob < ActionWebhook::DeliveryJob
  around_perform do |job, block|
    start_time = Time.current

    block.call

    StatsD.increment('webhook.delivery.success')
    StatsD.timing('webhook.delivery.duration', Time.current - start_time)
  rescue => error
    StatsD.increment('webhook.delivery.error')
    raise
  end
end

# Use custom job class
class UserWebhook < ActionWebhook::Base
  self.delivery_job = MonitoredDeliveryJob
end
```

## Serialization

### Webhook Data Serialization

The job handles serialization of:
- Action name and parameters
- Webhook endpoint details
- Instance variables from webhook context
- Retry attempt counts
- Webhook class information

### Global ID Support

When available, supports GlobalID for ActiveRecord objects:

```ruby
class UserWebhook < ActionWebhook::Base
  def created(user)
    @user = user  # Automatically serialized via GlobalID
    deliver(endpoints)
  end
end
```

## Configuration Examples

### Basic Configuration

```ruby
# config/application.rb
config.active_job.queue_adapter = :sidekiq

# Webhook configuration
ActionWebhook.configure do |config|
  config.deliver_later_queue_name = 'webhooks'
end
```

### Advanced Configuration

```ruby
# config/initializers/action_webhook.rb
ActionWebhook.configure do |config|
  config.delivery_job = CustomDeliveryJob
  config.deliver_later_queue_name = 'webhook_delivery'
end

# Custom delivery job with additional features
class CustomDeliveryJob < ActionWebhook::DeliveryJob
  retry_on Net::TimeoutError, wait: :exponentially_longer
  discard_on ActiveJob::DeserializationError

  before_perform :setup_monitoring
  after_perform :cleanup_resources

  private

  def setup_monitoring
    @start_time = Time.current
  end

  def cleanup_resources
    duration = Time.current - @start_time
    Rails.logger.info("Webhook job completed in #{duration}s")
  end
end
```

## Testing

### Testing Delivery Jobs

```ruby
# spec/jobs/action_webhook/delivery_job_spec.rb
RSpec.describe ActionWebhook::DeliveryJob do
  include ActiveJob::TestHelper

  it 'performs webhook delivery' do
    webhook_data = {
      "webhook_class" => "UserWebhook",
      "action_name" => "created",
      # ... other serialized data
    }

    expect {
      ActionWebhook::DeliveryJob.perform_now("deliver_now", webhook_data)
    }.to perform_job
  end

  it 'handles errors gracefully' do
    invalid_data = { "webhook_class" => "NonExistentWebhook" }

    expect {
      ActionWebhook::DeliveryJob.perform_now("deliver_now", invalid_data)
    }.to raise_error(NameError)
  end
end
```

### Integration Testing

```ruby
# Test with actual webhook
RSpec.describe UserWebhook do
  it 'enqueues delivery job' do
    user = create(:user)

    expect {
      UserWebhook.created(user).deliver_later
    }.to have_enqueued_job(ActionWebhook::DeliveryJob)
      .with("deliver_now", hash_including("webhook_class" => "UserWebhook"))
  end
end
```

## Performance Considerations

### Memory Usage

- Webhook data is serialized to minimize memory footprint
- Instance variables are selectively serialized
- Large objects should be passed by ID and reloaded in webhook

### Concurrency

- Jobs can be processed concurrently based on queue adapter
- Each job handles one webhook delivery attempt
- Retry logic creates new job instances

## Troubleshooting

### Common Issues

1. **Serialization Failures**
   ```ruby
   # Problem: Complex objects can't be serialized
   @complex_object = SomeComplexClass.new

   # Solution: Pass IDs and reload
   @user_id = user.id
   # In template: User.find(@user_id)
   ```

2. **Queue Adapter Issues**
   ```ruby
   # Ensure queue adapter is properly configured
   # config/application.rb
   config.active_job.queue_adapter = :sidekiq
   ```

3. **Memory Leaks**
   ```ruby
   # Avoid storing large datasets in instance variables
   # Use pagination or streaming instead
   ```

## See Also

- [ActionWebhook::Base](base.md) - Main webhook class
- [Configuration](configuration.md) - Configuration options
- [Queue Management](../queue-management.md) - Queue setup and management
- [Error Handling](../error-handling.md) - Error handling strategies
