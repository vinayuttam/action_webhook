# Queue Management

ActionWebhook integrates seamlessly with ActiveJob to provide robust queue management for webhook delivery. This guide covers queue configuration, job priority, and performance optimization.

## Overview

ActionWebhook uses background jobs to deliver webhooks asynchronously, ensuring your application remains responsive even when delivering webhooks to slow or unreliable endpoints.

## Queue Configuration

### Default Queue Setup

ActionWebhook uses the default ActiveJob queue by default:

```ruby
class UserWebhook < ActionWebhook::Base
  def deliver
    deliver_later # Uses default queue
  end
end
```

### Custom Queue Configuration

Specify custom queues for different types of webhooks:

```ruby
class HighPriorityWebhook < ActionWebhook::Base
  def deliver
    deliver_later(queue: 'webhooks_high')
  end
end

class LowPriorityWebhook < ActionWebhook::Base
  def deliver
    deliver_later(queue: 'webhooks_low')
  end
end
```

### Queue Configuration in Rails

Configure queues in your Rails application:

```ruby
# config/application.rb
config.active_job.queue_adapter = :sidekiq

# config/initializers/sidekiq.rb
Sidekiq.configure_server do |config|
  config.redis = { url: ENV['REDIS_URL'] }
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV['REDIS_URL'] }
end
```

## Queue Adapters

ActionWebhook supports all ActiveJob queue adapters:

### Sidekiq (Recommended)

```ruby
# Gemfile
gem 'sidekiq'

# config/application.rb
config.active_job.queue_adapter = :sidekiq

# config/sidekiq.yml
:queues:
  - webhooks_critical
  - webhooks_high
  - webhooks_normal
  - webhooks_low
  - default
```

### Resque

```ruby
# Gemfile
gem 'resque'

# config/application.rb
config.active_job.queue_adapter = :resque
```

### DelayedJob

```ruby
# Gemfile
gem 'delayed_job_active_record'

# config/application.rb
config.active_job.queue_adapter = :delayed_job
```

### Good Job

```ruby
# Gemfile
gem 'good_job'

# config/application.rb
config.active_job.queue_adapter = :good_job
```

## Priority and Scheduling

### Job Priority

Set job priority based on webhook importance:

```ruby
class CriticalWebhook < ActionWebhook::Base
  def deliver
    deliver_later(priority: 10) # Higher number = higher priority
  end
end

class NormalWebhook < ActionWebhook::Base
  def deliver
    deliver_later(priority: 5)
  end
end

class LowPriorityWebhook < ActionWebhook::Base
  def deliver
    deliver_later(priority: 1)
  end
end
```

### Delayed Execution

Schedule webhooks for future delivery:

```ruby
class ScheduledWebhook < ActionWebhook::Base
  def deliver_in_future(delay)
    deliver_later(wait: delay)
  end

  def deliver_at_specific_time(time)
    deliver_later(wait_until: time)
  end
end

# Usage
webhook = ScheduledWebhook.new(user)
webhook.deliver_in_future(1.hour)
webhook.deliver_at_specific_time(Time.zone.parse("2024-01-01 09:00:00"))
```

## Queue-Specific Configuration

Configure different retry policies per queue:

```ruby
class QueueSpecificWebhook < ActionWebhook::Base
  def deliver
    case webhook_type
    when :critical
      deliver_later(
        queue: 'webhooks_critical',
        priority: 10,
        retry: 5
      )
    when :normal
      deliver_later(
        queue: 'webhooks_normal',
        priority: 5,
        retry: 3
      )
    when :low_priority
      deliver_later(
        queue: 'webhooks_low',
        priority: 1,
        retry: 1
      )
    end
  end

  private

  def webhook_type
    # Determine webhook priority based on your logic
    :normal
  end
end
```

## Performance Optimization

### Batch Processing

Process multiple webhooks in batches:

```ruby
class BatchWebhookProcessor
  def self.process_batch(webhook_data_array)
    webhook_data_array.each do |data|
      WebhookJob.perform_later(data)
    end
  end

  def self.process_batch_with_delay(webhook_data_array, delay_between_jobs = 1.second)
    webhook_data_array.each_with_index do |data, index|
      WebhookJob.set(wait: index * delay_between_jobs).perform_later(data)
    end
  end
end
```

### Queue Monitoring

Monitor queue performance:

```ruby
class WebhookQueueMonitor
  def self.queue_stats
    {
      pending: Sidekiq::Queue.new('webhooks').size,
      processing: Sidekiq::Workers.new.size,
      failed: Sidekiq::RetrySet.new.size
    }
  end

  def self.alert_if_queue_backed_up(threshold = 1000)
    stats = queue_stats
    if stats[:pending] > threshold
      AlertService.notify("Webhook queue backed up: #{stats[:pending]} pending jobs")
    end
  end
end
```

### Resource Management

Limit concurrent webhook processing:

```ruby
# config/sidekiq.yml
:concurrency: 10
:queues:
  - [webhooks_critical, 3]
  - [webhooks_high, 2]
  - [webhooks_normal, 3]
  - [webhooks_low, 1]
  - [default, 1]
```

## Advanced Queue Patterns

### Dead Letter Queue

Handle failed webhooks:

```ruby
class WebhookJob < ApplicationJob
  queue_as :webhooks

  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  discard_on ActiveJob::DeserializationError do |job, error|
    # Log the error and move to dead letter queue
    DeadLetterQueue.add(job, error)
  end

  def perform(webhook_data)
    webhook = WebhookFactory.create(webhook_data)
    webhook.deliver_now
  end
end
```

### Circuit Breaker Pattern

Prevent cascading failures:

```ruby
class CircuitBreakerWebhook < ActionWebhook::Base
  def deliver
    if circuit_breaker_open?
      Rails.logger.warn "Circuit breaker open for #{endpoint_url}"
      return
    end

    begin
      deliver_now
      record_success
    rescue => error
      record_failure
      raise
    end
  end

  private

  def circuit_breaker_open?
    failure_count > threshold && last_failure_time > 5.minutes.ago
  end

  def record_success
    Rails.cache.delete(failure_key)
  end

  def record_failure
    Rails.cache.increment(failure_key, 1, expires_in: 1.hour)
    Rails.cache.write(last_failure_key, Time.current)
  end

  def failure_key
    "webhook_failures:#{endpoint_url}"
  end

  def last_failure_key
    "webhook_last_failure:#{endpoint_url}"
  end

  def threshold
    5
  end
end
```

### Rate Limiting

Control webhook delivery rate:

```ruby
class RateLimitedWebhook < ActionWebhook::Base
  def deliver
    if rate_limit_exceeded?
      delay = calculate_delay
      deliver_later(wait: delay)
    else
      deliver_now
      record_delivery
    end
  end

  private

  def rate_limit_exceeded?
    current_rate > allowed_rate
  end

  def current_rate
    Rails.cache.read(rate_key) || 0
  end

  def allowed_rate
    10 # 10 requests per minute
  end

  def record_delivery
    Rails.cache.increment(rate_key, 1, expires_in: 1.minute)
  end

  def calculate_delay
    excess = current_rate - allowed_rate
    (excess * 10).seconds # 10 seconds per excess request
  end

  def rate_key
    "webhook_rate:#{endpoint_host}:#{Time.current.strftime('%Y%m%d%H%M')}"
  end

  def endpoint_host
    URI.parse(endpoint_url).host
  end
end
```

## Monitoring and Metrics

### Queue Health Monitoring

```ruby
class WebhookQueueHealth
  def self.check
    {
      total_pending: total_pending_jobs,
      queue_breakdown: queue_breakdown,
      oldest_job_age: oldest_job_age,
      processing_rate: processing_rate,
      failure_rate: failure_rate
    }
  end

  def self.total_pending_jobs
    Sidekiq::Queue.all.sum(&:size)
  end

  def self.queue_breakdown
    Sidekiq::Queue.all.map do |queue|
      {
        name: queue.name,
        size: queue.size,
        latency: queue.latency
      }
    end
  end

  def self.oldest_job_age
    oldest_job = Sidekiq::Queue.all.flat_map(&:entries).min_by(&:created_at)
    oldest_job ? Time.current - oldest_job.created_at : 0
  end

  def self.processing_rate
    # Calculate jobs processed per minute
    processed_count = Rails.cache.read('webhook_processed_count') || 0
    processed_count / 60.0 # assuming count is for last hour
  end

  def self.failure_rate
    failed_count = Sidekiq::RetrySet.new.size
    total_count = total_pending_jobs + failed_count
    return 0 if total_count == 0
    (failed_count.to_f / total_count * 100).round(2)
  end
end
```

### Performance Metrics

```ruby
class WebhookMetrics
  def self.record_delivery(webhook_class, duration, success)
    tags = {
      webhook_class: webhook_class.name,
      success: success
    }

    # Record to your metrics system (StatsD, DataDog, etc.)
    StatsD.histogram('webhook.delivery.duration', duration, tags: tags)
    StatsD.increment('webhook.delivery.count', tags: tags)
  end

  def self.record_queue_metrics
    WebhookQueueHealth.check.each do |metric, value|
      StatsD.gauge("webhook.queue.#{metric}", value)
    end
  end
end
```

## Best Practices

1. **Use appropriate queues** - Separate critical and non-critical webhooks
2. **Set reasonable timeouts** - Prevent jobs from running indefinitely
3. **Monitor queue health** - Set up alerts for backed-up queues
4. **Implement circuit breakers** - Prevent cascading failures
5. **Use rate limiting** - Respect webhook endpoint limits
6. **Clean up failed jobs** - Regularly review and clean dead letter queues
7. **Scale workers appropriately** - Match worker count to load patterns
8. **Use batch processing** - Group similar webhooks when possible

## Troubleshooting

### Common Issues

1. **Queue backed up**: Increase worker count or optimize webhook processing
2. **High failure rate**: Check endpoint health and implement circuit breakers
3. **Memory issues**: Reduce job payload size and clean up old jobs
4. **Rate limit errors**: Implement proper rate limiting and backoff strategies

### Debugging Queue Issues

```ruby
# Check queue status
Sidekiq::Queue.new('webhooks').each do |job|
  puts "Job: #{job.klass}, Created: #{job.created_at}, Args: #{job.args}"
end

# Check failed jobs
Sidekiq::RetrySet.new.each do |job|
  puts "Failed: #{job.klass}, Error: #{job.error_message}, Retry Count: #{job.retry_count}"
end

# Clear specific queue
Sidekiq::Queue.new('webhooks').clear
```

## See Also

- [Configuration](configuration.md) - Queue configuration options
- [Error Handling](error-handling.md) - Handling queue failures
- [Retry Logic](retry-logic.md) - Configuring retry behavior
- [Monitoring](monitoring.md) - Queue monitoring and alerting
