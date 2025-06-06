# Retry Logic

ActionWebhook provides robust retry mechanisms to handle temporary failures when delivering webhooks. This guide covers retry configuration, strategies, and best practices.

## Overview

Webhook delivery can fail for various reasons - network issues, temporary service outages, or rate limiting. ActionWebhook's retry system helps ensure reliable delivery while avoiding overwhelming failing endpoints.

**Key Feature**: ActionWebhook intelligently retries only the URLs that failed, not all URLs in a batch delivery. This means if you're sending to 5 endpoints and only 2 fail, only those 2 will be retried.

## Built-in Retry Behavior

ActionWebhook includes built-in retry logic that automatically handles failures:

```ruby
class UserWebhook < ActionWebhook::Base
  # Built-in retry configuration (class-level settings)
  self.max_retries = 3                    # Maximum retry attempts
  self.retry_delay = 30.seconds           # Base delay between retries
  self.retry_backoff = :exponential       # Backoff strategy (:exponential, :linear, or :fixed)
  self.retry_jitter = 5.seconds           # Random jitter to prevent thundering herd

  def created(user)
    @user = user
    endpoints = [
      { url: 'https://api1.example.com/webhooks', headers: { 'Authorization' => 'Bearer token1' } },
      { url: 'https://api2.example.com/webhooks', headers: { 'Authorization' => 'Bearer token2' } },
      { url: 'https://api3.example.com/webhooks', headers: { 'Authorization' => 'Bearer token3' } }
    ]
    deliver(endpoints)
  end
end

# If api2.example.com fails but api1 and api3 succeed,
# only api2.example.com will be retried
UserWebhook.created(user).deliver_now
```

## Retry Configuration Options

### Class-Level Configuration

Configure retry behavior for all instances of a webhook class:

```ruby
class OrderWebhook < ActionWebhook::Base
  # Maximum number of retry attempts (default: 3)
  self.max_retries = 5

  # Base delay between retries (default: 30.seconds)
  self.retry_delay = 1.minute

  # Backoff strategy (default: :exponential)
  # Options: :exponential, :linear, :fixed
  self.retry_backoff = :exponential

  # Random jitter to prevent thundering herd (default: 5.seconds)
  self.retry_jitter = 10.seconds

  def created(order)
    @order = order
    endpoints = get_webhook_endpoints('order.created')
    deliver(endpoints)
  end
end
```

### Backoff Strategies

#### Exponential Backoff (Default)
Doubles the delay with each retry attempt:

```ruby
class ExponentialBackoffWebhook < ActionWebhook::Base
  self.retry_backoff = :exponential
  self.retry_delay = 30.seconds

  # Retry delays: 30s, 60s, 120s, 240s, 480s...
end
```

#### Linear Backoff
Increases delay by a fixed amount each time:

```ruby
class LinearBackoffWebhook < ActionWebhook::Base
  self.retry_backoff = :linear
  self.retry_delay = 30.seconds

  # Retry delays: 30s, 60s, 90s, 120s, 150s...
end
```

#### Fixed Backoff
Uses the same delay for all retry attempts:

```ruby
class FixedBackoffWebhook < ActionWebhook::Base
  self.retry_backoff = :fixed
  self.retry_delay = 45.seconds

  # Retry delays: 45s, 45s, 45s, 45s, 45s...
end
```

## How Selective Retry Works

ActionWebhook's intelligent retry system only retries URLs that actually failed:

```ruby
class NotificationWebhook < ActionWebhook::Base
  self.max_retries = 3

  def user_signed_up(user)
    @user = user
    endpoints = [
      { url: 'https://analytics.example.com/webhook' },      # Service A
      { url: 'https://email-service.example.com/webhook' },  # Service B
      { url: 'https://crm.example.com/webhook' },            # Service C
      { url: 'https://slack.example.com/webhook' }           # Service D
    ]
    deliver(endpoints)
  end
end

# Example scenario:
webhook = NotificationWebhook.user_signed_up(user)
response = webhook.deliver_now

# If the response looks like this:
# [
#   { success: true, url: 'https://analytics.example.com/webhook', status: 200 },
#   { success: false, url: 'https://email-service.example.com/webhook', status: 500 },
#   { success: true, url: 'https://crm.example.com/webhook', status: 201 },
#   { success: false, url: 'https://slack.example.com/webhook', status: 503 }
# ]
#
# Only https://email-service.example.com/webhook and https://slack.example.com/webhook
# will be retried. The successful deliveries to analytics and CRM services won't be repeated.
```

### Retry Process Flow

1. **Initial Delivery**: All URLs are attempted
2. **Response Analysis**: Successful and failed responses are separated
3. **Success Callback**: Triggered immediately for successful deliveries
4. **Selective Retry**: Only failed URLs are queued for retry
5. **Backoff Calculation**: Delay is calculated based on attempt number
6. **Background Retry**: Failed URLs are retried via ActiveJob
7. **Exhaustion Handling**: After max retries, exhaustion callback is triggered

```ruby
class DetailedWebhook < ActionWebhook::Base
  self.max_retries = 3

  # Called immediately when any URLs succeed
  after_deliver :handle_successful_deliveries

  # Called when retries are exhausted for failed URLs
  after_retries_exhausted :handle_permanent_failures

  def created(resource)
    @resource = resource
    endpoints = get_endpoints_for_event('created')
    deliver(endpoints)
  end

  private

  def handle_successful_deliveries(successful_responses)
    successful_responses.each do |response|
      Rails.logger.info "Webhook delivered successfully to #{response[:url]} (Status: #{response[:status]})"
      # Mark endpoint as healthy in monitoring system
      EndpointHealth.mark_success(response[:url])
    end
  end

  def handle_permanent_failures(failed_responses)
    failed_responses.each do |response|
      Rails.logger.error "Webhook permanently failed for #{response[:url]} after #{response[:attempt]} attempts"
      # Disable endpoint or alert administrators
      EndpointHealth.mark_failed(response[:url])
      AlertService.webhook_failure(response)
    end
  end
end
```

## Monitoring Retry Behavior

Track and monitor retry attempts:

```ruby
class MonitoredWebhook < ActionWebhook::Base
  self.max_retries = 5

  after_deliver :track_successful_deliveries
  after_retries_exhausted :track_permanent_failures

  def send_notification(data)
    @data = data
    endpoints = WebhookEndpoint.active.pluck(:url, :headers)
    deliver(endpoints)
  end

  private

  def track_successful_deliveries(successful_responses)
    successful_responses.each do |response|
      StatsD.increment('webhook.delivery.success', tags: {
        webhook_class: self.class.name,
        endpoint: response[:url],
        attempt: response[:attempt]
      })

      # Track response time if available
      if response[:response_time]
        StatsD.histogram('webhook.delivery.response_time', response[:response_time])
      end
    end
  end

  def track_permanent_failures(failed_responses)
    failed_responses.each do |response|
      StatsD.increment('webhook.delivery.permanent_failure', tags: {
        webhook_class: self.class.name,
        endpoint: response[:url],
        final_attempt: response[:attempt],
        error_type: response[:error] ? 'exception' : 'http_error'
      })

      # Alert on permanent failures
      if response[:attempt] >= self.class.max_retries
        SlackNotifier.webhook_failed_permanently(response)
      end
    end
  end
end
```

### Custom Retry Logic

For advanced use cases, you can override the retry behavior:

```ruby
class CustomRetryWebhook < ActionWebhook::Base
  # Override to implement custom retry logic
  def deliver_now
    @attempts += 1
    response = process_webhook

    successful_responses = response.select { |r| r[:success] }
    failed_responses = response.reject { |r| r[:success] }

    # Handle successful deliveries
    if successful_responses.any?
      invoke_callback(self.class.after_deliver_callback, successful_responses)
    end

    # Custom retry logic for failed responses
    if failed_responses.any? && should_retry?
      failed_webhook_details = extract_failed_webhook_details(failed_responses)

      # Custom retry conditions
      retryable_failures = failed_webhook_details.select { |detail| retryable_endpoint?(detail[:url]) }

      if retryable_failures.any?
        custom_retry_with_backoff(retryable_failures)
      end

      # Handle non-retryable failures immediately
      non_retryable = failed_webhook_details - retryable_failures
      if non_retryable.any?
        non_retryable_responses = failed_responses.select { |r| non_retryable.any? { |detail| detail[:url] == r[:url] } }
        invoke_callback(self.class.after_retries_exhausted_callback, non_retryable_responses)
      end
    elsif failed_responses.any?
      # All retries exhausted
      invoke_callback(self.class.after_retries_exhausted_callback, failed_responses)
    end

    response
  end

  private

  def should_retry?
    @attempts < self.class.max_retries
  end

  def retryable_endpoint?(url)
    # Custom logic to determine if endpoint should be retried
    # e.g., check if endpoint is temporarily disabled
    !Rails.cache.read("endpoint_disabled:#{url}")
  end

  def custom_retry_with_backoff(failed_webhook_details)
    # Custom backoff calculation
    delay = calculate_custom_delay

    # Schedule retry job
    job_class = resolve_job_class
    serialized_webhook = serialize
    serialized_webhook["webhook_details"] = failed_webhook_details

    job_class.set(wait: delay).perform_later("deliver_now", serialized_webhook)
  end

  def calculate_custom_delay
    # Example: Different delays based on time of day
    base_delay = self.class.retry_delay

    if Time.current.hour.between?(9, 17) # Business hours
      base_delay
    else
      base_delay * 2 # Longer delays outside business hours
    end
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
# spec/webhooks/user_webhook_spec.rb
RSpec.describe UserWebhook do
  let(:webhook) { described_class.new }
  let(:endpoints) do
    [
      { url: 'https://success.example.com/webhook' },
      { url: 'https://failure.example.com/webhook' }
    ]
  end

  before do
    webhook.instance_variable_set(:@user, create(:user))
    webhook.instance_variable_set(:@webhook_details, endpoints)
    webhook.instance_variable_set(:@action_name, :created)
  end

  describe 'selective retry behavior' do
    it 'only retries failed URLs' do
      # Mock HTTP responses
      allow(HTTParty).to receive(:post).with('https://success.example.com/webhook', any_args)
                                      .and_return(double(success?: true, code: 200, body: '{}'))

      allow(HTTParty).to receive(:post).with('https://failure.example.com/webhook', any_args)
                                      .and_return(double(success?: false, code: 500, body: 'Server Error'))

      # Mock job enqueuing for retry
      allow(ActionWebhook::DeliveryJob).to receive(:set).and_return(ActionWebhook::DeliveryJob)
      expect(ActionWebhook::DeliveryJob).to receive(:perform_later) do |method, serialized_webhook|
        expect(method).to eq('deliver_now')
        expect(serialized_webhook['webhook_details'].size).to eq(1)
        expect(serialized_webhook['webhook_details'].first[:url]).to eq('https://failure.example.com/webhook')
      end

      response = webhook.deliver_now

      expect(response.size).to eq(2)
      expect(response.count { |r| r[:success] }).to eq(1)
      expect(response.count { |r| !r[:success] }).to eq(1)
    end

    it 'calls success callback for successful deliveries' do
      expect(webhook).to receive(:invoke_callback) do |callback, responses|
        expect(responses.size).to eq(1)
        expect(responses.first[:success]).to be true
        expect(responses.first[:url]).to eq('https://success.example.com/webhook')
      end

      allow(HTTParty).to receive(:post).with('https://success.example.com/webhook', any_args)
                                      .and_return(double(success?: true, code: 200, body: '{}'))

      allow(HTTParty).to receive(:post).with('https://failure.example.com/webhook', any_args)
                                      .and_return(double(success?: false, code: 500, body: 'Server Error'))

      webhook.deliver_now
    end

    it 'exhausts retries only for failed URLs' do
      webhook.instance_variable_set(:@attempts, 3) # Max retries reached

      allow(HTTParty).to receive(:post).and_return(double(success?: false, code: 500, body: 'Server Error'))

      expect(webhook).to receive(:invoke_callback).with(described_class.after_retries_exhausted_callback, anything) do |callback, responses|
        expect(responses.size).to eq(2) # Both URLs failed
        expect(responses.all? { |r| !r[:success] }).to be true
      end

      webhook.deliver_now
    end
  end

  describe 'backoff calculation' do
    let(:webhook_with_config) do
      Class.new(ActionWebhook::Base) do
        self.retry_delay = 10.seconds
        self.retry_backoff = :exponential
        self.retry_jitter = 2.seconds
      end.new
    end

    it 'calculates exponential backoff correctly' do
      webhook_with_config.instance_variable_set(:@attempts, 1)
      delay = webhook_with_config.send(:calculate_backoff_delay)
      expect(delay).to be_between(8, 14) # 10s + jitter (8-12s range)

      webhook_with_config.instance_variable_set(:@attempts, 2)
      delay = webhook_with_config.send(:calculate_backoff_delay)
      expect(delay).to be_between(18, 24) # 20s + jitter (18-22s range)
    end

    it 'calculates linear backoff correctly' do
      webhook_class = Class.new(ActionWebhook::Base) do
        self.retry_delay = 10.seconds
        self.retry_backoff = :linear
        self.retry_jitter = 2.seconds
      end

      webhook_linear = webhook_class.new
      webhook_linear.instance_variable_set(:@attempts, 2)
      delay = webhook_linear.send(:calculate_backoff_delay)
      expect(delay).to be_between(18, 24) # (10s * 2) + jitter
    end

    it 'calculates fixed backoff correctly' do
      webhook_class = Class.new(ActionWebhook::Base) do
        self.retry_delay = 15.seconds
        self.retry_backoff = :fixed
        self.retry_jitter = 3.seconds
      end

      webhook_fixed = webhook_class.new
      webhook_fixed.instance_variable_set(:@attempts, 5)
      delay = webhook_fixed.send(:calculate_backoff_delay)
      expect(delay).to be_between(12, 21) # 15s + jitter (12-18s range)
    end
  end

  describe 'configuration' do
    it 'respects class-level retry settings' do
      webhook_class = Class.new(ActionWebhook::Base) do
        self.max_retries = 5
        self.retry_delay = 1.minute
        self.retry_backoff = :linear
      end

      expect(webhook_class.max_retries).to eq(5)
      expect(webhook_class.retry_delay).to eq(1.minute)
      expect(webhook_class.retry_backoff).to eq(:linear)
    end
  end
end
```

## Configuration Options

Configure retry behavior globally or per webhook class:

```ruby
# config/initializers/action_webhook.rb
ActionWebhook.configure do |config|
  # These would be global defaults if implemented
  # Currently, configuration is done at the class level
end

# Per-class configuration (current approach)
class GlobalRetryWebhook < ActionWebhook::Base
  # Set defaults for all webhook classes that inherit from this
  self.max_retries = 5
  self.retry_delay = 1.minute
  self.retry_backoff = :exponential
  self.retry_jitter = 10.seconds
end

class UserWebhook < GlobalRetryWebhook
  # Inherits retry configuration from GlobalRetryWebhook
  # Can override specific settings if needed
  self.max_retries = 3 # Override just this setting
end

class CriticalWebhook < ActionWebhook::Base
  # More aggressive retry for critical webhooks
  self.max_retries = 10
  self.retry_delay = 10.seconds
  self.retry_backoff = :exponential
  self.retry_jitter = 5.seconds
end
```

## Advanced Use Cases

### Conditional Retry Based on Response

```ruby
class SmartRetryWebhook < ActionWebhook::Base
  def deliver_now
    @attempts += 1
    response = process_webhook

    successful_responses = response.select { |r| r[:success] }
    failed_responses = response.reject { |r| r[:success] }

    # Handle successes immediately
    invoke_callback(self.class.after_deliver_callback, successful_responses) if successful_responses.any?

    # Smart retry logic for failures
    if failed_responses.any? && @attempts < self.class.max_retries
      retryable_failures = failed_responses.select { |r| retryable_error?(r) }

      if retryable_failures.any?
        failed_webhook_details = retryable_failures.map { |r|
          @webhook_details.find { |detail| detail[:url] == r[:url] }
        }.compact
        retry_with_backoff(failed_webhook_details)
      end

      # Handle non-retryable failures as permanent
      non_retryable = failed_responses - retryable_failures
      invoke_callback(self.class.after_retries_exhausted_callback, non_retryable) if non_retryable.any?
    elsif failed_responses.any?
      invoke_callback(self.class.after_retries_exhausted_callback, failed_responses)
    end

    response
  end

  private

  def retryable_error?(response)
    # Don't retry 4xx client errors (except 408, 409, 429)
    if response[:status]
      case response[:status]
      when 400..499
        [408, 409, 429].include?(response[:status])
      when 500..599
        true # Retry all 5xx server errors
      else
        false
      end
    else
      # Retry network errors (when status is nil but error is present)
      response[:error].present?
    end
  end
end
```

### Circuit Breaker Integration

```ruby
class CircuitBreakerWebhook < ActionWebhook::Base
  def post_webhook(webhook_details, payload)
    responses = []

    webhook_details.each do |detail|
      if circuit_open?(detail[:url])
        responses << {
          success: false,
          status: nil,
          error: "Circuit breaker open for #{detail[:url]}",
          url: detail[:url],
          attempt: @attempts
        }
        next
      end

      detail[:headers] ||= {}
      headers = build_headers(detail[:headers])

      begin
        response = send_webhook_request(detail[:url], payload, headers)
        responses << build_response_hash(response, detail[:url])
        log_webhook_result(response, detail[:url])

        # Record success for circuit breaker
        record_success(detail[:url]) if response.success?
      rescue StandardError => e
        responses << build_error_response_hash(e, detail[:url])
        log_webhook_error(e, detail[:url])

        # Record failure for circuit breaker
        record_failure(detail[:url])
      end
    end

    responses
  end

  private

  def circuit_open?(url)
    failure_count = Rails.cache.read("circuit_failures:#{url}") || 0
    failure_count >= 5
  end

  def record_success(url)
    Rails.cache.delete("circuit_failures:#{url}")
  end

  def record_failure(url)
    Rails.cache.increment("circuit_failures:#{url}", 1, expires_in: 1.hour)

    # Open circuit if too many failures
    if Rails.cache.read("circuit_failures:#{url}") >= 5
      Rails.cache.write("circuit_open:#{url}", true, expires_in: 10.minutes)
    end
  end
end
```

## Best Practices

1. **Use selective retry** - ActionWebhook automatically retries only failed URLs, maximizing efficiency
2. **Configure appropriate retry limits** - Balance reliability with resource usage
3. **Choose the right backoff strategy** - Exponential for most cases, linear for predictable loads, fixed for consistent timing
4. **Add jitter** - Prevents thundering herd problems when multiple webhooks retry simultaneously
5. **Monitor retry patterns** - Track which endpoints fail frequently to identify issues
6. **Handle permanent failures** - Use the `after_retries_exhausted` callback to handle URLs that never succeed
7. **Implement circuit breakers** - Prevent overwhelming consistently failing endpoints
8. **Use appropriate timeouts** - Don't let slow endpoints block retries for fast ones
9. **Test retry behavior** - Ensure your retry configuration works as expected under various failure scenarios
10. **Consider rate limits** - Some APIs have rate limits that affect retry timing

### Example Production Configuration

```ruby
class ProductionWebhook < ActionWebhook::Base
  # Conservative retry settings for production
  self.max_retries = 3
  self.retry_delay = 30.seconds
  self.retry_backoff = :exponential
  self.retry_jitter = 10.seconds

  # Callbacks for monitoring and alerting
  after_deliver :log_successful_deliveries
  after_retries_exhausted :handle_permanent_failures

  private

  def log_successful_deliveries(successful_responses)
    successful_responses.each do |response|
      Rails.logger.info "Webhook delivered: #{response[:url]} (#{response[:status]}) attempt #{response[:attempt]}"
    end
  end

  def handle_permanent_failures(failed_responses)
    failed_responses.each do |response|
      Rails.logger.error "Webhook permanently failed: #{response[:url]} after #{response[:attempt]} attempts"

      # Alert operations team
      ErrorTracker.notify(
        "Webhook delivery failed permanently",
        extra: {
          url: response[:url],
          attempts: response[:attempt],
          last_error: response[:error] || "HTTP #{response[:status]}"
        }
      )

      # Optionally disable the endpoint
      WebhookEndpoint.find_by(url: response[:url])&.mark_as_failing!
    end
  end
end
```

## Key Benefits of ActionWebhook's Retry System

- **Efficiency**: Only failed URLs are retried, not successful ones
- **Reliability**: Automatic retry with configurable backoff strategies
- **Observability**: Built-in callbacks for monitoring success and failure
- **Flexibility**: Customizable retry logic for advanced use cases
- **Performance**: Background processing via ActiveJob prevents blocking
- **Resilience**: Jitter prevents thundering herd problems

## See Also

- [Error Handling](error-handling.md) - Comprehensive error handling strategies
- [Queue Management](queue-management.md) - Managing webhook job queues
- [Monitoring](monitoring.md) - Monitoring webhook delivery and failures
- [Configuration](configuration.md) - Configuring retry behavior
