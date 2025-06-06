# ActionWebhook Configuration API Reference

This document covers all configuration options available in ActionWebhook for customizing webhook behavior, queue management, error handling, and more.

## Global Configuration

### `ActionWebhook.configure`

Configure global settings for ActionWebhook.

**Example:**
```ruby
# config/initializers/action_webhook.rb
ActionWebhook.configure do |config|
  config.default_timeout = 30
  config.default_retries = 3
  config.default_queue = 'webhooks'
  config.logger = Rails.logger
end
```

## Configuration Options

### Network Configuration

#### `timeout`
- **Type:** `Integer`
- **Default:** `30`
- **Description:** Default timeout for HTTP requests in seconds

```ruby
config.timeout = 45 # 45 seconds timeout
```

#### `open_timeout`
- **Type:** `Integer`
- **Default:** `10`
- **Description:** Timeout for establishing HTTP connections in seconds

```ruby
config.open_timeout = 15
```

#### `read_timeout`
- **Type:** `Integer`
- **Default:** `30`
- **Description:** Timeout for reading HTTP responses in seconds

```ruby
config.read_timeout = 60
```

#### `max_redirects`
- **Type:** `Integer`
- **Default:** `3`
- **Description:** Maximum number of HTTP redirects to follow

```ruby
config.max_redirects = 5
```

### Retry Configuration

#### `default_retries`
- **Type:** `Integer`
- **Default:** `3`
- **Description:** Default number of retry attempts for failed webhooks

```ruby
config.default_retries = 5
```

#### `retry_wait`
- **Type:** `Symbol` or `Proc`
- **Default:** `:exponentially_longer`
- **Description:** Default wait strategy between retries

```ruby
# Exponential backoff
config.retry_wait = :exponentially_longer

# Fixed delay
config.retry_wait = 30.seconds

# Custom logic
config.retry_wait = ->(executions) { [executions ** 2, 300].min }
```

#### `retry_jitter`
- **Type:** `Float`
- **Default:** `0.15`
- **Description:** Random factor added to retry delays (0.0 to 1.0)

```ruby
config.retry_jitter = 0.25 # 25% jitter
```

#### `max_retry_delay`
- **Type:** `Integer`
- **Default:** `3600` (1 hour)
- **Description:** Maximum delay between retries in seconds

```ruby
config.max_retry_delay = 1800 # 30 minutes max
```

### Queue Configuration

#### `default_queue`
- **Type:** `String` or `Symbol`
- **Default:** `'default'`
- **Description:** Default queue name for webhook jobs

```ruby
config.default_queue = 'webhooks'
```

#### `queue_adapter`
- **Type:** `Symbol`
- **Default:** Rails default
- **Description:** ActiveJob queue adapter to use

```ruby
config.queue_adapter = :sidekiq
```

#### `queue_priority`
- **Type:** `Integer`
- **Default:** `0`
- **Description:** Default job priority

```ruby
config.queue_priority = 5
```

### Logging Configuration

#### `logger`
- **Type:** `Logger`
- **Default:** `Rails.logger`
- **Description:** Logger instance for webhook events

```ruby
config.logger = Logger.new(STDOUT)
```

#### `log_level`
- **Type:** `Symbol`
- **Default:** `:info`
- **Description:** Logging level for webhook events

```ruby
config.log_level = :debug
```

#### `log_payload`
- **Type:** `Boolean`
- **Default:** `false`
- **Description:** Whether to log webhook payloads (be careful with sensitive data)

```ruby
config.log_payload = true # Only in development!
```

### Error Handling Configuration

#### `raise_delivery_errors`
- **Type:** `Boolean`
- **Default:** `true`
- **Description:** Whether to raise exceptions on delivery failures

```ruby
config.raise_delivery_errors = false # Suppress errors
```

#### `error_handler`
- **Type:** `Proc`
- **Default:** `nil`
- **Description:** Custom error handler for webhook failures

```ruby
config.error_handler = ->(error, webhook) do
  ErrorTracker.notify(error, webhook: webhook.class.name)
end
```

#### `circuit_breaker_enabled`
- **Type:** `Boolean`
- **Default:** `false`
- **Description:** Enable circuit breaker pattern for failing endpoints

```ruby
config.circuit_breaker_enabled = true
```

#### `circuit_breaker_threshold`
- **Type:** `Integer`
- **Default:** `5`
- **Description:** Number of failures before opening circuit

```ruby
config.circuit_breaker_threshold = 10
```

#### `circuit_breaker_timeout`
- **Type:** `Integer`
- **Default:** `300` (5 minutes)
- **Description:** Seconds to keep circuit open

```ruby
config.circuit_breaker_timeout = 600 # 10 minutes
```

### Security Configuration

#### `verify_ssl`
- **Type:** `Boolean`
- **Default:** `true`
- **Description:** Whether to verify SSL certificates

```ruby
config.verify_ssl = false # Only for development!
```

#### `ca_file`
- **Type:** `String`
- **Default:** `nil`
- **Description:** Path to custom CA certificate file

```ruby
config.ca_file = '/path/to/ca-certificates.crt'
```

#### `default_headers`
- **Type:** `Hash`
- **Default:** `{ 'Content-Type' => 'application/json', 'User-Agent' => 'ActionWebhook/1.0' }`
- **Description:** Default headers included in all requests

```ruby
config.default_headers = {
  'Content-Type' => 'application/json',
  'User-Agent' => 'MyApp/1.0',
  'X-API-Version' => '2024-01-01'
}
```

#### `signature_header`
- **Type:** `String`
- **Default:** `'X-Webhook-Signature'`
- **Description:** Header name for webhook signatures

```ruby
config.signature_header = 'X-Hub-Signature-256'
```

#### `signature_algorithm`
- **Type:** `String`
- **Default:** `'sha256'`
- **Description:** Algorithm for generating webhook signatures

```ruby
config.signature_algorithm = 'sha1'
```

### Payload Configuration

#### `max_payload_size`
- **Type:** `Integer`
- **Default:** `1048576` (1 MB)
- **Description:** Maximum payload size in bytes

```ruby
config.max_payload_size = 5.megabytes
```

#### `payload_format`
- **Type:** `Symbol`
- **Default:** `:json`
- **Description:** Default payload format

```ruby
config.payload_format = :form # or :xml
```

#### `json_options`
- **Type:** `Hash`
- **Default:** `{}`
- **Description:** Options passed to JSON.generate

```ruby
config.json_options = { symbolize_names: true }
```

### Monitoring Configuration

#### `metrics_enabled`
- **Type:** `Boolean`
- **Default:** `false`
- **Description:** Enable metrics collection

```ruby
config.metrics_enabled = true
```

#### `metrics_backend`
- **Type:** `Symbol`
- **Default:** `:statsd`
- **Description:** Metrics backend to use

```ruby
config.metrics_backend = :datadog
```

#### `metrics_prefix`
- **Type:** `String`
- **Default:** `'webhook'`
- **Description:** Prefix for metric names

```ruby
config.metrics_prefix = 'myapp.webhooks'
```

#### `health_check_url`
- **Type:** `String`
- **Default:** `nil`
- **Description:** URL for webhook health checks

```ruby
config.health_check_url = '/health/webhooks'
```

## Per-Class Configuration

Configure settings for specific webhook classes:

```ruby
class UserWebhook < ActionWebhook::Base
  # Override global settings
  configure do |config|
    config.timeout = 60
    config.retries = 5
    config.queue = 'user_webhooks'
  end
end
```

## Environment-Specific Configuration

Configure different settings per environment:

```ruby
# config/environments/production.rb
ActionWebhook.configure do |config|
  config.timeout = 30
  config.verify_ssl = true
  config.circuit_breaker_enabled = true
  config.metrics_enabled = true
end

# config/environments/development.rb
ActionWebhook.configure do |config|
  config.timeout = 60
  config.verify_ssl = false
  config.log_payload = true
  config.raise_delivery_errors = true
end

# config/environments/test.rb
ActionWebhook.configure do |config|
  config.timeout = 5
  config.retries = 0
  config.raise_delivery_errors = true
end
```

## Configuration Validation

ActionWebhook validates configuration on startup:

```ruby
ActionWebhook.configure do |config|
  config.timeout = -1 # Will raise ArgumentError
  config.max_payload_size = "invalid" # Will raise TypeError
end
```

## Dynamic Configuration

Change configuration at runtime:

```ruby
# Temporarily change timeout
original_timeout = ActionWebhook.config.timeout
ActionWebhook.config.timeout = 60

begin
  webhook.deliver_now
ensure
  ActionWebhook.config.timeout = original_timeout
end
```

## Configuration Helpers

### `#configured?`

Check if ActionWebhook has been configured:

```ruby
ActionWebhook.configured? # => true/false
```

### `#reset_config!`

Reset configuration to defaults:

```ruby
ActionWebhook.reset_config!
```

### `#config`

Access current configuration:

```ruby
ActionWebhook.config.timeout # => 30
ActionWebhook.config.default_queue # => 'webhooks'
```

## Configuration Examples

### High-Performance Setup

```ruby
ActionWebhook.configure do |config|
  config.timeout = 15
  config.default_retries = 2
  config.max_retry_delay = 300
  config.circuit_breaker_enabled = true
  config.metrics_enabled = true
end
```

### Development Setup

```ruby
ActionWebhook.configure do |config|
  config.timeout = 60
  config.verify_ssl = false
  config.log_payload = true
  config.log_level = :debug
  config.raise_delivery_errors = true
end
```

### Secure Production Setup

```ruby
ActionWebhook.configure do |config|
  config.verify_ssl = true
  config.ca_file = '/etc/ssl/certs/ca-certificates.crt'
  config.signature_algorithm = 'sha256'
  config.max_payload_size = 2.megabytes
  config.circuit_breaker_enabled = true
  config.metrics_enabled = true
  config.error_handler = ->(error, webhook) do
    Sentry.capture_exception(error, extra: {
      webhook_class: webhook.class.name
    })
  end
end
```

## See Also

- [Basic Usage](../basic-usage.md) - Getting started guide
- [Queue Management](../queue-management.md) - Queue configuration
- [Error Handling](../error-handling.md) - Error handling options
- [Security](../security.md) - Security configuration
