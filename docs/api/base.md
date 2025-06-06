# ActionWebhook::Base API Reference

The `ActionWebhook::Base` class is the core class that all webhook classes inherit from. It provides the fundamental functionality for webhook delivery, error handling, and queue management.

## Class Overview

```ruby
class ActionWebhook::Base
  include ActiveJob::Core
  include ActiveJob::QueueAdapter
  include ActiveJob::Logging
end
```

## Class Methods

### `.perform_later(*args, **options)`

Enqueues the webhook for background processing using ActiveJob.

**Parameters:**
- `*args` - Arguments to pass to the webhook constructor
- `**options` - Job options (queue, priority, wait, etc.)

**Returns:** `ActiveJob::Base` instance

**Example:**
```ruby
UserWebhook.perform_later(user, queue: 'webhooks_high', priority: 10)
```

### `.perform_now(*args)`

Executes the webhook immediately in the current process.

**Parameters:**
- `*args` - Arguments to pass to the webhook constructor

**Returns:** `nil`

**Example:**
```ruby
UserWebhook.perform_now(user)
```

### `.perform_at(time, *args, **options)`

Schedules the webhook for execution at a specific time.

**Parameters:**
- `time` - `Time` object indicating when to execute
- `*args` - Arguments to pass to the webhook constructor
- `**options` - Job options

**Returns:** `ActiveJob::Base` instance

**Example:**
```ruby
UserWebhook.perform_at(1.hour.from_now, user)
```

### `.perform_in(interval, *args, **options)`

Schedules the webhook for execution after a specific interval.

**Parameters:**
- `interval` - `ActiveSupport::Duration` or number of seconds
- `*args` - Arguments to pass to the webhook constructor
- `**options` - Job options

**Returns:** `ActiveJob::Base` instance

**Example:**
```ruby
UserWebhook.perform_in(30.minutes, user)
```

## Instance Methods

### `#initialize(*args)`

Initializes a new webhook instance. This method should be overridden in subclasses to set up webhook-specific data.

**Parameters:**
- `*args` - Variable arguments passed from the job

**Example:**
```ruby
def initialize(user)
  @user = user
  @payload = {
    id: user.id,
    email: user.email,
    event: 'user.created'
  }
  super
end
```

### `#perform`

Main entry point for webhook execution. Called by ActiveJob when the job is processed.

**Returns:** `nil`

**Note:** This method calls `deliver_now` internally and handles job-specific concerns.

### `#deliver_now`

Executes the webhook delivery immediately. Handles callbacks, error handling, and HTTP requests.

**Returns:** `nil`

**Example:**
```ruby
webhook = UserWebhook.new(user)
webhook.deliver_now
```

### `#deliver_later(**options)`

Enqueues the current webhook instance for background processing.

**Parameters:**
- `**options` - Job options (queue, priority, wait, etc.)

**Returns:** `ActiveJob::Base` instance

**Example:**
```ruby
webhook = UserWebhook.new(user)
webhook.deliver_later(queue: 'webhooks', priority: 5)
```

## HTTP Methods

### `#post_webhook(url, payload, headers = {})`

Sends an HTTP POST request to the specified webhook endpoint.

**Parameters:**
- `url` (String) - The webhook endpoint URL
- `payload` (Hash) - The data to send in the request body
- `headers` (Hash) - HTTP headers to include (optional)

**Returns:** `HTTParty::Response`

**Raises:**
- `Net::HTTPError` - For HTTP error responses
- `Net::TimeoutError` - For request timeouts
- `SocketError` - For connection issues

**Example:**
```ruby
response = post_webhook(
  'https://example.com/webhook',
  { id: 1, event: 'user.created' },
  { 'Authorization' => 'Bearer token123' }
)
```

## Callback Methods

### `#before_deliver(*method_names, **options, &block)`

Registers callbacks to run before webhook delivery.

**Parameters:**
- `*method_names` - Names of methods to call
- `**options` - Callback options (`if`, `unless`, etc.)
- `&block` - Block to execute

**Example:**
```ruby
before_deliver :validate_payload, :add_timestamp, if: :should_validate?
```

### `#after_deliver(*method_names, **options, &block)`

Registers callbacks to run after webhook delivery.

**Parameters:**
- `*method_names` - Names of methods to call
- `**options` - Callback options (`if`, `unless`, etc.)
- `&block` - Block to execute

**Example:**
```ruby
after_deliver :log_delivery, :update_metrics
```

### `#around_deliver(*method_names, **options, &block)`

Registers callbacks to wrap the webhook delivery process.

**Parameters:**
- `*method_names` - Names of methods to call
- `**options` - Callback options (`if`, `unless`, etc.)
- `&block` - Block to execute

**Example:**
```ruby
around_deliver :measure_performance
```

## Template Methods

These methods are designed to be overridden in subclasses to customize webhook behavior.

### `#payload_template`

Returns the payload data structure to send to webhook endpoints.

**Returns:** `Hash`

**Example:**
```ruby
def payload_template
  {
    event: 'user.created',
    timestamp: Time.current.iso8601,
    data: {
      id: @user.id,
      email: @user.email
    }
  }
end
```

### `#headers_template`

Returns the HTTP headers to include in webhook requests.

**Returns:** `Hash`

**Example:**
```ruby
def headers_template
  {
    'Content-Type' => 'application/json',
    'X-Webhook-Signature' => generate_signature(@payload)
  }
end
```

### `#endpoints`

Returns the list of webhook endpoints to deliver to.

**Returns:** `Array<String>` or `Array<Hash>`

**Example:**
```ruby
def endpoints
  [
    'https://app1.example.com/webhook',
    'https://app2.example.com/webhook'
  ]
end
```

## Error Handling Methods

### `#retry_job(**options)`

Schedules the current job for retry with the specified options.

**Parameters:**
- `**options` - Retry options (`wait`, `wait_until`, `priority`, etc.)

**Example:**
```ruby
retry_job(wait: 30.seconds)
retry_job(wait_until: 1.hour.from_now)
```

### `#discard_with_error(message)`

Discards the current job and logs the specified error message.

**Parameters:**
- `message` (String) - Error message to log

**Example:**
```ruby
discard_with_error("Invalid payload: missing required fields")
```

### `#rescue_from(exception_class, with: method_name)`

Registers an exception handler for the specified exception class.

**Parameters:**
- `exception_class` - The exception class to handle
- `with` - The method name to call when the exception occurs

**Example:**
```ruby
rescue_from Net::TimeoutError, with: :handle_timeout
rescue_from Net::HTTPServerError, with: :handle_server_error
```

## State Methods

### `#delivery_successful?`

Returns whether the last webhook delivery attempt was successful.

**Returns:** `Boolean`

### `#last_error`

Returns the last error that occurred during webhook delivery.

**Returns:** `Exception` or `nil`

### `#executions`

Returns the number of times this job has been executed (including retries).

**Returns:** `Integer`

### `#delivery_duration`

Returns the duration of the last delivery attempt in seconds.

**Returns:** `Float` or `nil`

## Configuration Methods

### `#queue_as(queue_name)`

Sets the default queue for this webhook class.

**Parameters:**
- `queue_name` (String or Symbol) - The queue name

**Example:**
```ruby
class HighPriorityWebhook < ActionWebhook::Base
  queue_as :webhooks_high
end
```

### `#retry_on(exception_class, **options)`

Configures retry behavior for specific exception types.

**Parameters:**
- `exception_class` - The exception class to retry on
- `**options` - Retry options (`wait`, `attempts`, etc.)

**Example:**
```ruby
retry_on Net::HTTPServerError, wait: :exponentially_longer, attempts: 3
```

### `#discard_on(exception_class, &block)`

Configures the job to be discarded when specific exceptions occur.

**Parameters:**
- `exception_class` - The exception class to discard on
- `&block` - Optional block to execute before discarding

**Example:**
```ruby
discard_on Net::HTTPUnauthorized do |job, error|
  Rails.logger.error "Unauthorized webhook: #{error.message}"
end
```

## Private Methods

These methods are intended for internal use but can be overridden in subclasses.

### `#deliver_webhooks`

Internal method that handles the actual delivery logic. Override to customize delivery behavior.

### `#process_webhook(endpoint, payload)`

Processes a single webhook delivery to a specific endpoint.

**Parameters:**
- `endpoint` (String or Hash) - The endpoint URL or configuration
- `payload` (Hash) - The payload to deliver

### `#handle_delivery_error(error, endpoint)`

Handles errors that occur during webhook delivery.

**Parameters:**
- `error` (Exception) - The error that occurred
- `endpoint` (String) - The endpoint where the error occurred

### `#record_delivery_metrics(success, duration, endpoint)`

Records metrics about webhook delivery performance.

**Parameters:**
- `success` (Boolean) - Whether the delivery was successful
- `duration` (Float) - Delivery duration in seconds
- `endpoint` (String) - The endpoint URL

## Constants

### `DEFAULT_TIMEOUT`

The default timeout for HTTP requests in seconds.

**Value:** `30`

### `DEFAULT_HEADERS`

Default HTTP headers included in all webhook requests.

**Value:**
```ruby
{
  'Content-Type' => 'application/json',
  'User-Agent' => 'ActionWebhook/1.0'
}
```

### `MAX_RETRIES`

Default maximum number of retry attempts.

**Value:** `3`

## See Also

- [Basic Usage](../basic-usage.md) - Getting started with ActionWebhook
- [Configuration](../configuration.md) - Configuration options
- [Error Handling](../error-handling.md) - Error handling strategies
- [Callbacks](../callbacks.md) - Using callbacks and hooks
