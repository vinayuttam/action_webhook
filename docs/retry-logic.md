# Retry Logic

ActionWebhook provides robust retry mechanisms to handle temporary failures when delivering webhooks. This guide covers retry configuration, strategies, and best practices.

## Overview

Webhook delivery can fail for various reasons - network issues, temporary service outages, or rate limiting. ActionWebhook's retry system helps ensure reliable delivery while avoiding overwhelming failing endpoints.

## Default Retry Behavior

ActionWebhook uses ActiveJob's retry mechanisms by default:

```ruby
class WebhookJob < ApplicationJob
  queue_as :webhooks

  # Default: retry up to 3 times with exponential backoff
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(webhook_data)
    webhook = ActionWebhook::Base.new(webhook_data)
    webhook.deliver_now
  end
end
```

## Custom Retry Configuration

### Basic Retry Settings

Configure retry attempts and timing:

```ruby
class BasicRetryWebhook < ActionWebhook::Base
  # Retry up to 5 times with fixed 30-second intervals
  retry_on Net::TimeoutError, wait: 30.seconds, attempts: 5

  # Different retry settings for different errors
  retry_on Net::HTTPServerError, wait: :exponentially_longer, attempts: 3
  retry_on Net::HTTPTooManyRequests, wait: 1.minute, attempts: 10
end
```

### Advanced Retry Strategies

#### Exponential Backoff

```ruby
class ExponentialBackoffWebhook < ActionWebhook::Base
  retry_on StandardError,
           wait: :exponentially_longer,
           attempts: 5,
           jitter: 0.15 # Add randomness to prevent thundering herd

  private

  def deliver_with_retry
    begin
      deliver_now
    rescue Net::HTTPServerError => error
      # Custom exponential backoff calculation
      wait_time = calculate_backoff_time(executions)
      retry_job(wait: wait_time)
    end
  end

  def calculate_backoff_time(attempt)
    base_delay = 2 ** attempt # 2, 4, 8, 16, 32 seconds
    jitter = rand(0.5..1.5) # Add randomness
    [base_delay * jitter, 300].min # Cap at 5 minutes
  end
end
```

#### Linear Backoff

```ruby
class LinearBackoffWebhook < ActionWebhook::Base
  retry_on StandardError, attempts: 5 do |job, error|
    # Linear backoff: 30s, 60s, 90s, 120s, 150s
    wait_time = job.executions * 30.seconds
    job.retry_job(wait: wait_time)
  end
end
```

#### Custom Backoff Strategy

```ruby
class CustomBackoffWebhook < ActionWebhook::Base
  retry_on StandardError, attempts: 10 do |job, error|
    wait_time = case job.executions
                when 1..2
                  30.seconds # Quick retries first
                when 3..5
                  5.minutes # Medium delay
                else
                  30.minutes # Long delay for persistent failures
                end

    job.retry_job(wait: wait_time)
  end
end
```

## Error-Specific Retry Logic

Handle different types of errors with specific retry strategies:

```ruby
class ErrorSpecificRetryWebhook < ActionWebhook::Base
  # Don't retry on client errors (4xx)
  discard_on Net::HTTPClientError

  # Quick retry for temporary network issues
  retry_on Net::TimeoutError,
           Net::ConnectTimeout,
           wait: 10.seconds,
           attempts: 3

  # Longer wait for server errors
  retry_on Net::HTTPServerError,
           wait: :exponentially_longer,
           attempts: 5

  # Special handling for rate limits
  retry_on Net::HTTPTooManyRequests do |job, error|
    # Extract rate limit reset time from response headers
    reset_time = extract_rate_limit_reset(error.response)
    wait_until = reset_time || 1.hour.from_now
    job.retry_job(wait_until: wait_until)
  end

  private

  def extract_rate_limit_reset(response)
    return nil unless response

    reset_header = response['X-RateLimit-Reset'] || response['Retry-After']
    return nil unless reset_header

    # Handle Unix timestamp
    if reset_header.match?(/^\d+$/)
      Time.at(reset_header.to_i)
    # Handle seconds from now
    else
      reset_header.to_i.seconds.from_now
    end
  end
end
```

## Conditional Retry Logic

Implement complex retry logic based on conditions:

```ruby
class ConditionalRetryWebhook < ActionWebhook::Base
  def perform
    deliver_now
  rescue => error
    if should_retry?(error)
      handle_retry(error)
    else
      handle_permanent_failure(error)
    end
  end

  private

  def should_retry?(error)
    return false if executions >= max_attempts
    return false if permanent_error?(error)
    return false if endpoint_disabled?

    true
  end

  def permanent_error?(error)
    case error
    when Net::HTTPUnauthorized, Net::HTTPForbidden
      true
    when Net::HTTPNotFound
      # Maybe the endpoint was removed
      true
    when Net::HTTPClientError
      # Most 4xx errors shouldn't be retried
      true
    else
      false
    end
  end

  def endpoint_disabled?
    # Check if endpoint has been disabled due to too many failures
    Rails.cache.read("webhook_disabled:#{endpoint_url}").present?
  end

  def handle_retry(error)
    wait_time = calculate_retry_delay(error)
    retry_job(wait: wait_time)
  end

  def calculate_retry_delay(error)
    base_delay = case error
                when Net::HTTPTooManyRequests
                  1.hour
                when Net::HTTPServerError
                  [30.seconds * (2 ** executions), 30.minutes].min
                else
                  30.seconds
                end

    # Add jitter to prevent thundering herd
    jitter = rand(0.8..1.2)
    base_delay * jitter
  end

  def max_attempts
    5
  end
end
```

## Dead Letter Queue

Handle webhooks that have exhausted all retry attempts:

```ruby
class DeadLetterWebhook < ActionWebhook::Base
  retry_on StandardError, attempts: 3

  # Move to dead letter queue after final failure
  discard_on StandardError do |job, error|
    DeadLetterQueue.add(
      job: job,
      error: error,
      final_attempt: true,
      webhook_data: job.arguments.first
    )
  end
end

class DeadLetterQueue
  def self.add(job:, error:, final_attempt: false, webhook_data: nil)
    Rails.logger.error "Webhook failed permanently: #{error.message}"

    # Store in database for later analysis
    WebhookFailure.create!(
      job_class: job.class.name,
      job_arguments: job.arguments,
      error_message: error.message,
      error_backtrace: error.backtrace,
      final_attempt: final_attempt,
      failed_at: Time.current,
      webhook_data: webhook_data
    )

    # Optionally notify administrators
    AdminMailer.webhook_failure_notification(job, error).deliver_later
  end

  def self.retry_failed_webhook(failure_id)
    failure = WebhookFailure.find(failure_id)

    # Recreate and retry the job
    job_class = failure.job_class.constantize
    job_class.perform_later(*failure.job_arguments)

    failure.update!(retried_at: Time.current)
  end
end
```

## Circuit Breaker Pattern

Prevent overwhelming failing endpoints:

```ruby
class CircuitBreakerRetryWebhook < ActionWebhook::Base
  def perform
    if circuit_open?
      raise CircuitOpenError, "Circuit breaker open for #{endpoint_url}"
    end

    begin
      deliver_now
      record_success
    rescue => error
      record_failure

      if should_open_circuit?
        open_circuit
      end

      raise error
    end
  end

  # Don't retry when circuit is open
  discard_on CircuitOpenError

  private

  def circuit_open?
    Rails.cache.read(circuit_key) == 'open'
  end

  def should_open_circuit?
    failure_count >= failure_threshold &&
    failure_rate >= failure_rate_threshold
  end

  def open_circuit
    Rails.cache.write(circuit_key, 'open', expires_in: circuit_timeout)
    Rails.logger.warn "Circuit breaker opened for #{endpoint_url}"
  end

  def record_success
    Rails.cache.delete(failure_count_key)
    Rails.cache.delete(failure_rate_key)
  end

  def record_failure
    Rails.cache.increment(failure_count_key, 1, expires_in: 1.hour)
    Rails.cache.increment(failure_rate_key, 1, expires_in: 5.minutes)
  end

  def failure_count
    Rails.cache.read(failure_count_key) || 0
  end

  def failure_rate
    Rails.cache.read(failure_rate_key) || 0
  end

  def circuit_key
    "circuit_breaker:#{endpoint_url}"
  end

  def failure_count_key
    "failure_count:#{endpoint_url}"
  end

  def failure_rate_key
    "failure_rate:#{endpoint_url}"
  end

  def failure_threshold
    5
  end

  def failure_rate_threshold
    3 # failures per 5 minutes
  end

  def circuit_timeout
    10.minutes
  end

  class CircuitOpenError < StandardError; end
end
```

## Monitoring and Alerting

Track retry metrics for monitoring:

```ruby
class MonitoredRetryWebhook < ActionWebhook::Base
  retry_on StandardError, attempts: 5 do |job, error|
    # Record retry metrics
    record_retry_metrics(job, error)

    # Alert on too many retries
    alert_if_too_many_retries(job)

    job.retry_job(wait: :exponentially_longer)
  end

  discard_on StandardError do |job, error|
    # Record final failure metrics
    record_final_failure_metrics(job, error)

    # Alert on permanent failure
    alert_permanent_failure(job, error)
  end

  private

  def record_retry_metrics(job, error)
    StatsD.increment('webhook.retry.count', tags: {
      webhook_class: self.class.name,
      error_class: error.class.name,
      attempt: job.executions
    })
  end

  def record_final_failure_metrics(job, error)
    StatsD.increment('webhook.failure.final', tags: {
      webhook_class: self.class.name,
      error_class: error.class.name,
      total_attempts: job.executions
    })
  end

  def alert_if_too_many_retries(job)
    if job.executions >= 3
      AlertService.notify(
        "Webhook retry threshold exceeded",
        webhook_class: self.class.name,
        attempts: job.executions,
        endpoint: endpoint_url
      )
    end
  end

  def alert_permanent_failure(job, error)
    AlertService.notify(
      "Webhook permanently failed",
      webhook_class: self.class.name,
      error: error.message,
      endpoint: endpoint_url,
      total_attempts: job.executions
    )
  end
end
```

## Testing Retry Logic

Test your retry configurations:

```ruby
# spec/webhooks/retry_webhook_spec.rb
RSpec.describe RetryWebhook do
  let(:webhook) { described_class.new(user_data) }

  describe 'retry behavior' do
    it 'retries on server errors' do
      allow(webhook).to receive(:deliver_now).and_raise(Net::HTTPServerError)

      expect(webhook).to receive(:retry_job).with(wait: anything)

      webhook.perform
    end

    it 'does not retry on client errors' do
      allow(webhook).to receive(:deliver_now).and_raise(Net::HTTPUnauthorized)

      expect(webhook).not_to receive(:retry_job)
      expect { webhook.perform }.to raise_error(Net::HTTPUnauthorized)
    end

    it 'respects maximum retry attempts' do
      allow(webhook).to receive(:executions).and_return(5)
      allow(webhook).to receive(:deliver_now).and_raise(Net::HTTPServerError)

      expect(webhook).not_to receive(:retry_job)
      expect { webhook.perform }.to raise_error(Net::HTTPServerError)
    end
  end

  describe 'backoff calculation' do
    it 'increases wait time exponentially' do
      expect(webhook.send(:calculate_backoff_time, 1)).to be_within(1).of(2)
      expect(webhook.send(:calculate_backoff_time, 2)).to be_within(2).of(4)
      expect(webhook.send(:calculate_backoff_time, 3)).to be_within(4).of(8)
    end

    it 'caps maximum wait time' do
      long_wait = webhook.send(:calculate_backoff_time, 10)
      expect(long_wait).to be <= 300 # 5 minutes max
    end
  end
end
```

## Configuration Options

Configure retry behavior globally:

```ruby
# config/initializers/action_webhook.rb
ActionWebhook.configure do |config|
  config.default_retry_attempts = 3
  config.default_retry_wait = :exponentially_longer
  config.retry_jitter = 0.15
  config.max_retry_delay = 30.minutes
  config.circuit_breaker_enabled = true
  config.circuit_breaker_threshold = 5
  config.circuit_breaker_timeout = 10.minutes
end
```

## Best Practices

1. **Use appropriate retry strategies** - Exponential backoff for most cases
2. **Don't retry client errors** - 4xx errors usually indicate permanent issues
3. **Respect rate limits** - Parse rate limit headers and wait appropriately
4. **Implement circuit breakers** - Prevent overwhelming failing endpoints
5. **Monitor retry metrics** - Track retry rates and failure patterns
6. **Set reasonable limits** - Don't retry indefinitely
7. **Handle dead letters** - Have a plan for permanently failed webhooks
8. **Add jitter** - Prevent thundering herd problems
9. **Test retry logic** - Ensure your retry behavior works as expected
10. **Alert on patterns** - Monitor for systematic failures

## See Also

- [Error Handling](error-handling.md) - Comprehensive error handling strategies
- [Queue Management](queue-management.md) - Managing webhook job queues
- [Monitoring](monitoring.md) - Monitoring webhook delivery and failures
- [Configuration](configuration.md) - Configuring retry behavior
