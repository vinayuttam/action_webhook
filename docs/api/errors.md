# ActionWebhook Errors API Reference

ActionWebhook defines several error classes to help you handle different types of failures that can occur during webhook processing. Understanding these errors is crucial for implementing proper error handling and recovery strategies.

## Error Hierarchy

```
StandardError
├── ActionWebhook::Error (base error class)
│   ├── ActionWebhook::DeliveryError
│   │   ├── ActionWebhook::NetworkError
│   │   ├── ActionWebhook::HttpError
│   │   └── ActionWebhook::TimeoutError
│   ├── ActionWebhook::ConfigurationError
│   ├── ActionWebhook::TemplateError
│   ├── ActionWebhook::SerializationError
│   └── ActionWebhook::RetryError
└── ActiveJob::DeserializationError (from ActiveJob)
```

## Core Error Classes

### `ActionWebhook::Error`

Base error class for all ActionWebhook-specific errors.

```ruby
module ActionWebhook
  class Error < StandardError
    attr_reader :webhook_class, :action_name, :context

    def initialize(message, webhook_class: nil, action_name: nil, context: {})
      super(message)
      @webhook_class = webhook_class
      @action_name = action_name
      @context = context
    end
  end
end
```

**Usage:**
```ruby
begin
  UserWebhook.created(user).deliver_now
rescue ActionWebhook::Error => e
  Rails.logger.error "Webhook error: #{e.message}"
  Rails.logger.error "Webhook class: #{e.webhook_class}"
  Rails.logger.error "Action: #{e.action_name}"
  Rails.logger.error "Context: #{e.context}"
end
```

### `ActionWebhook::DeliveryError`

Raised when webhook delivery fails. This is the parent class for all delivery-related errors.

```ruby
class ActionWebhook::DeliveryError < ActionWebhook::Error
  attr_reader :url, :response, :attempt

  def initialize(message, url:, response: nil, attempt: 1, **kwargs)
    super(message, **kwargs)
    @url = url
    @response = response
    @attempt = attempt
  end
end
```

**Example:**
```ruby
begin
  webhook.deliver_now
rescue ActionWebhook::DeliveryError => e
  Rails.logger.error "Failed to deliver to #{e.url} on attempt #{e.attempt}"
  Rails.logger.error "Response: #{e.response&.body}"
end
```

### `ActionWebhook::NetworkError`

Raised for network-related failures (connection timeouts, DNS resolution, etc.).

```ruby
class ActionWebhook::NetworkError < ActionWebhook::DeliveryError
  def self.from_exception(exception, url:, attempt: 1, **kwargs)
    new(
      "Network error when delivering to #{url}: #{exception.message}",
      url: url,
      attempt: attempt,
      context: { original_exception: exception.class.name },
      **kwargs
    )
  end
end
```

**Common Scenarios:**
- Connection timeouts
- DNS resolution failures
- SSL certificate issues
- Network unreachable

**Example:**
```ruby
begin
  webhook.deliver_now
rescue ActionWebhook::NetworkError => e
  # Retry with exponential backoff
  RetryWebhookJob.set(wait: 2 ** e.attempt).perform_later(webhook.serialize)
end
```

### `ActionWebhook::HttpError`

Raised for HTTP-related errors (4xx, 5xx status codes).

```ruby
class ActionWebhook::HttpError < ActionWebhook::DeliveryError
  attr_reader :status_code, :response_body

  def initialize(message, status_code:, response_body: nil, **kwargs)
    super(message, **kwargs)
    @status_code = status_code
    @response_body = response_body
  end

  def client_error?
    status_code >= 400 && status_code < 500
  end

  def server_error?
    status_code >= 500 && status_code < 600
  end

  def retryable?
    server_error? || status_code == 429  # Retry server errors and rate limits
  end
end
```

**Example:**
```ruby
begin
  webhook.deliver_now
rescue ActionWebhook::HttpError => e
  case e.status_code
  when 401, 403
    Rails.logger.error "Authentication failed for #{e.url}"
    disable_webhook_endpoint(e.url)
  when 404
    Rails.logger.warn "Endpoint not found: #{e.url}"
    mark_endpoint_inactive(e.url)
  when 429
    Rails.logger.warn "Rate limited by #{e.url}"
    schedule_retry_with_delay(webhook, 60.minutes)
  when 500..599
    Rails.logger.error "Server error from #{e.url}: #{e.status_code}"
    schedule_retry(webhook) if e.retryable?
  end
end
```

### `ActionWebhook::TimeoutError`

Raised when HTTP requests timeout.

```ruby
class ActionWebhook::TimeoutError < ActionWebhook::NetworkError
  attr_reader :timeout_duration

  def initialize(message, timeout_duration:, **kwargs)
    super(message, **kwargs)
    @timeout_duration = timeout_duration
  end
end
```

**Example:**
```ruby
# Configure timeout handling
class UserWebhook < ActionWebhook::Base
  configure do |config|
    config.timeout = 30.seconds
  end

  # Handle timeout errors
  rescue_from ActionWebhook::TimeoutError do |error|
    Rails.logger.warn "Webhook timeout after #{error.timeout_duration}s for #{error.url}"
    if error.attempt < 3
      retry_job(wait: error.attempt * 30)
    else
      WebhookFailureAlert.timeout(error)
    end
  end
end
```

### `ActionWebhook::ConfigurationError`

Raised for configuration-related issues.

```ruby
class ActionWebhook::ConfigurationError < ActionWebhook::Error
  def self.invalid_queue(queue_name)
    new("Invalid queue name: #{queue_name}. Queue must be a string or symbol.")
  end

  def self.missing_template(template_path)
    new("Template not found: #{template_path}")
  end

  def self.invalid_retry_config(config)
    new("Invalid retry configuration: #{config}")
  end
end
```

**Examples:**
```ruby
# Invalid configuration
class UserWebhook < ActionWebhook::Base
  self.deliver_later_queue_name = 123  # Invalid type
  # Raises: ActionWebhook::ConfigurationError: Invalid queue name: 123
end

# Missing template
UserWebhook.new.generate_json_from_template('nonexistent')
# Raises: ActionWebhook::ConfigurationError: Template not found: user_webhook/nonexistent.json.erb
```

### `ActionWebhook::TemplateError`

Raised for template-related errors.

```ruby
class ActionWebhook::TemplateError < ActionWebhook::Error
  attr_reader :template_path, :line_number

  def initialize(message, template_path:, line_number: nil, **kwargs)
    super(message, **kwargs)
    @template_path = template_path
    @line_number = line_number
  end
end
```

**Common Scenarios:**
- ERB syntax errors
- Invalid JSON output
- Missing template variables
- Template not found

**Example:**
```ruby
begin
  webhook.build_payload
rescue ActionWebhook::TemplateError => e
  Rails.logger.error "Template error in #{e.template_path}"
  Rails.logger.error "Line #{e.line_number}: #{e.message}" if e.line_number

  # Send default payload
  fallback_payload = { error: "Template error", timestamp: Time.current }
  webhook.post_webhook(webhook.webhook_details, fallback_payload)
end
```

### `ActionWebhook::SerializationError`

Raised when webhook data cannot be serialized/deserialized for background processing.

```ruby
class ActionWebhook::SerializationError < ActionWebhook::Error
  attr_reader :object, :serialization_type

  def initialize(message, object: nil, serialization_type: nil, **kwargs)
    super(message, **kwargs)
    @object = object
    @serialization_type = serialization_type
  end
end
```

**Example:**
```ruby
class UserWebhook < ActionWebhook::Base
  def created(user)
    @user = user
    @complex_object = NonSerializableClass.new  # Problem!
    deliver(endpoints)
  end
end

begin
  UserWebhook.created(user).deliver_later
rescue ActionWebhook::SerializationError => e
  Rails.logger.error "Cannot serialize #{e.object.class.name} for background processing"
  # Fallback to immediate delivery
  UserWebhook.created(user).deliver_now
end
```

### `ActionWebhook::RetryError`

Raised when retry logic encounters issues.

```ruby
class ActionWebhook::RetryError < ActionWebhook::Error
  attr_reader :max_retries_reached, :retry_attempt

  def initialize(message, max_retries_reached: false, retry_attempt: 0, **kwargs)
    super(message, **kwargs)
    @max_retries_reached = max_retries_reached
    @retry_attempt = retry_attempt
  end
end
```

## Error Handling Patterns

### Rescue Specific Errors

```ruby
class UserWebhook < ActionWebhook::Base
  def created(user)
    @user = user
    deliver(endpoints)
  rescue ActionWebhook::NetworkError => e
    # Handle network issues
    Rails.logger.warn "Network error: #{e.message}"
    schedule_retry(delay: 1.minute)
  rescue ActionWebhook::HttpError => e
    # Handle HTTP errors based on status
    if e.client_error?
      Rails.logger.error "Client error (#{e.status_code}): #{e.message}"
      # Don't retry client errors
    elsif e.server_error?
      Rails.logger.warn "Server error (#{e.status_code}): #{e.message}"
      schedule_retry if e.retryable?
    end
  rescue ActionWebhook::TemplateError => e
    # Handle template issues
    Rails.logger.error "Template error: #{e.message}"
    send_fallback_notification
  end
end
```

### Global Error Handling

```ruby
# config/initializers/action_webhook.rb
ActionWebhook.configure do |config|
  config.error_handler = proc do |error, webhook_class, action_name|
    case error
    when ActionWebhook::NetworkError
      ErrorTracker.notify(error, tags: { type: 'webhook_network' })
    when ActionWebhook::HttpError
      if error.client_error?
        ErrorTracker.notify(error, level: 'warning')
      else
        ErrorTracker.notify(error, level: 'error')
      end
    when ActionWebhook::TemplateError
      ErrorTracker.notify(error, tags: {
        type: 'webhook_template',
        template: error.template_path
      })
    else
      ErrorTracker.notify(error)
    end
  end
end
```

### Circuit Breaker Pattern

```ruby
class ResilientWebhook < ActionWebhook::Base
  class_attribute :circuit_breaker, default: {}

  def deliver_with_circuit_breaker(endpoints)
    endpoints.each do |endpoint|
      if circuit_open?(endpoint[:url])
        Rails.logger.warn "Circuit breaker open for #{endpoint[:url]}"
        next
      end

      begin
        deliver_to_endpoint(endpoint)
        reset_circuit(endpoint[:url])
      rescue ActionWebhook::HttpError => e
        if e.server_error?
          increment_failure_count(endpoint[:url])
          open_circuit_if_needed(endpoint[:url])
        end
        raise
      end
    end
  end

  private

  def circuit_open?(url)
    circuit_breaker[url] && circuit_breaker[url][:open_until] > Time.current
  end

  def increment_failure_count(url)
    circuit_breaker[url] ||= { failures: 0 }
    circuit_breaker[url][:failures] += 1
  end

  def open_circuit_if_needed(url)
    if circuit_breaker[url][:failures] >= 3
      circuit_breaker[url][:open_until] = 5.minutes.from_now
      Rails.logger.warn "Circuit breaker opened for #{url}"
    end
  end

  def reset_circuit(url)
    circuit_breaker.delete(url)
  end
end
```

## Error Monitoring and Alerting

### Integration with Error Tracking Services

```ruby
# Sentry integration
class UserWebhook < ActionWebhook::Base
  after_retries_exhausted do |response|
    Sentry.capture_message(
      "Webhook delivery failed permanently",
      extra: {
        webhook_class: self.class.name,
        action: @action_name,
        user_id: @user&.id,
        response: response
      },
      level: 'error'
    )
  end
end

# Honeybadger integration
class OrderWebhook < ActionWebhook::Base
  rescue_from ActionWebhook::Error do |error|
    Honeybadger.notify(error,
      context: {
        webhook_class: self.class.name,
        action: @action_name,
        order_id: @order&.id
      }
    )
    raise # Re-raise to maintain normal error flow
  end
end
```

### Custom Error Handlers

```ruby
class WebhookErrorHandler
  def self.handle(error, webhook_instance)
    case error
    when ActionWebhook::NetworkError
      handle_network_error(error, webhook_instance)
    when ActionWebhook::HttpError
      handle_http_error(error, webhook_instance)
    when ActionWebhook::TemplateError
      handle_template_error(error, webhook_instance)
    else
      handle_generic_error(error, webhook_instance)
    end
  end

  private

  def self.handle_network_error(error, webhook_instance)
    # Log to monitoring service
    StatsD.increment('webhook.error.network')

    # Check if endpoint is consistently failing
    if consecutive_failures(error.url) > 5
      WebhookEndpoint.find_by(url: error.url)&.disable!
      AlertMailer.endpoint_disabled(error.url).deliver_now
    end
  end

  def self.handle_http_error(error, webhook_instance)
    StatsD.increment('webhook.error.http', tags: ["status:#{error.status_code}"])

    if error.status_code == 410  # Gone
      WebhookEndpoint.find_by(url: error.url)&.mark_as_gone!
    end
  end

  def self.handle_template_error(error, webhook_instance)
    # Template errors are usually code issues
    SlackNotifier.notify_developers(
      "Webhook template error in #{error.template_path}: #{error.message}"
    )
  end
end
```

## Testing Error Scenarios

```ruby
# spec/webhooks/user_webhook_spec.rb
RSpec.describe UserWebhook do
  let(:user) { create(:user) }

  describe 'error handling' do
    it 'handles network timeouts' do
      stub_request(:post, 'http://example.com/webhook')
        .to_timeout

      expect {
        UserWebhook.created(user).deliver_now
      }.to raise_error(ActionWebhook::TimeoutError)
    end

    it 'handles HTTP errors' do
      stub_request(:post, 'http://example.com/webhook')
        .to_return(status: 500, body: 'Internal Server Error')

      expect {
        UserWebhook.created(user).deliver_now
      }.to raise_error(ActionWebhook::HttpError) do |error|
        expect(error.status_code).to eq(500)
        expect(error.server_error?).to be true
        expect(error.retryable?).to be true
      end
    end

    it 'handles template errors' do
      allow(File).to receive(:exist?).and_return(false)

      expect {
        UserWebhook.created(user).deliver_now
      }.to raise_error(ActionWebhook::TemplateError)
    end
  end
end
```

## Best Practices

### 1. Use Specific Error Types

```ruby
# Good: Catch specific errors
begin
  webhook.deliver_now
rescue ActionWebhook::NetworkError
  # Handle network issues
rescue ActionWebhook::HttpError => e
  # Handle HTTP errors differently based on status
end

# Avoid: Generic error catching
begin
  webhook.deliver_now
rescue => e
  # Too broad, harder to handle appropriately
end
```

### 2. Log Error Context

```ruby
rescue ActionWebhook::DeliveryError => e
  Rails.logger.error "Webhook delivery failed", {
    webhook_class: e.webhook_class,
    action: e.action_name,
    url: e.url,
    attempt: e.attempt,
    error: e.message,
    context: e.context
  }
end
```

### 3. Implement Graceful Degradation

```ruby
def send_notification_with_fallback
  begin
    UserWebhook.created(@user).deliver_now
  rescue ActionWebhook::Error => e
    Rails.logger.warn "Webhook failed, using email fallback: #{e.message}"
    UserMailer.created(@user).deliver_now
  end
end
```

### 4. Monitor Error Rates

```ruby
class MonitoredWebhook < ActionWebhook::Base
  around_deliver do |webhook, block|
    start_time = Time.current

    begin
      block.call
      StatsD.increment('webhook.delivery.success')
    rescue ActionWebhook::Error => e
      StatsD.increment('webhook.delivery.error', tags: ["type:#{e.class.name}"])
      raise
    ensure
      duration = Time.current - start_time
      StatsD.timing('webhook.delivery.duration', duration)
    end
  end
end
```

## See Also

- [Error Handling Guide](../error-handling.md) - Comprehensive error handling strategies
- [Retry Logic](../retry-logic.md) - Retry configuration and patterns
- [Testing](../testing.md) - Testing error scenarios
- [Callbacks](callbacks.md) - Using callbacks for error handling
