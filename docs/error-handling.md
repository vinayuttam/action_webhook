# Error Handling

ActionWebhook provides comprehensive error handling mechanisms to deal with various failure scenarios during webhook delivery. This guide covers error types, handling strategies, and recovery mechanisms.

## Error Categories

### Network Errors

Common network-related failures:

```ruby
class NetworkErrorWebhook < ActionWebhook::Base
  rescue_from Net::TimeoutError, with: :handle_timeout
  rescue_from Net::ConnectTimeout, with: :handle_connection_timeout
  rescue_from Net::ReadTimeout, with: :handle_read_timeout
  rescue_from SocketError, with: :handle_socket_error

  private

  def handle_timeout(error)
    Rails.logger.warn "Webhook timeout for #{endpoint_url}: #{error.message}"

    # Retry with exponential backoff
    retry_job(wait: exponential_backoff)
  end

  def handle_connection_timeout(error)
    Rails.logger.warn "Connection timeout for #{endpoint_url}: #{error.message}"

    # Mark endpoint as potentially down
    mark_endpoint_suspicious

    # Retry after longer delay
    retry_job(wait: 5.minutes)
  end

  def handle_read_timeout(error)
    Rails.logger.warn "Read timeout for #{endpoint_url}: #{error.message}"

    # Could be server overload, retry with backoff
    retry_job(wait: exponential_backoff)
  end

  def handle_socket_error(error)
    Rails.logger.error "Socket error for #{endpoint_url}: #{error.message}"

    # DNS issues or endpoint down
    if executions >= max_retries
      notify_endpoint_failure
      mark_endpoint_down
    else
      retry_job(wait: 30.minutes)
    end
  end
end
```

### HTTP Errors

Handle different HTTP status codes:

```ruby
class HttpErrorWebhook < ActionWebhook::Base
  rescue_from Net::HTTPError, with: :handle_http_error

  private

  def handle_http_error(error)
    response = error.response
    status_code = response.code.to_i

    case status_code
    when 400..499
      handle_client_error(error, status_code)
    when 500..599
      handle_server_error(error, status_code)
    else
      handle_unknown_error(error, status_code)
    end
  end

  def handle_client_error(error, status_code)
    case status_code
    when 400
      Rails.logger.error "Bad request to #{endpoint_url}: #{error.response.body}"
      # Don't retry bad requests
      discard_with_error("Bad request: payload may be malformed")
    when 401
      Rails.logger.error "Unauthorized webhook to #{endpoint_url}"
      # Check if credentials need refresh
      if can_refresh_credentials?
        refresh_credentials_and_retry
      else
        discard_with_error("Unauthorized: invalid credentials")
      end
    when 403
      Rails.logger.error "Forbidden webhook to #{endpoint_url}"
      discard_with_error("Forbidden: insufficient permissions")
    when 404
      Rails.logger.error "Webhook endpoint not found: #{endpoint_url}"
      # Maybe endpoint was moved or removed
      check_for_redirect_or_disable
    when 422
      Rails.logger.error "Unprocessable webhook to #{endpoint_url}: #{error.response.body}"
      discard_with_error("Unprocessable entity: invalid payload structure")
    when 429
      handle_rate_limit(error)
    else
      Rails.logger.error "Client error #{status_code} for #{endpoint_url}: #{error.response.body}"
      discard_with_error("Client error: #{status_code}")
    end
  end

  def handle_server_error(error, status_code)
    Rails.logger.warn "Server error #{status_code} for #{endpoint_url}: #{error.response.body}"

    case status_code
    when 502, 503, 504
      # Temporary server issues, retry with backoff
      if executions < max_retries
        retry_job(wait: exponential_backoff)
      else
        notify_persistent_server_error
      end
    when 500
      # Internal server error, might be temporary
      if executions < max_retries
        retry_job(wait: exponential_backoff * 2) # Longer wait for 500s
      else
        discard_with_error("Persistent internal server error")
      end
    else
      # Other server errors
      if executions < max_retries
        retry_job(wait: exponential_backoff)
      else
        discard_with_error("Persistent server error: #{status_code}")
      end
    end
  end

  def handle_rate_limit(error)
    response = error.response

    # Extract rate limit information from headers
    reset_time = extract_rate_limit_reset(response)
    retry_after = extract_retry_after(response)

    wait_time = retry_after || reset_time || default_rate_limit_wait

    Rails.logger.warn "Rate limited by #{endpoint_url}, retrying after #{wait_time} seconds"
    retry_job(wait: wait_time.seconds)
  end

  def extract_rate_limit_reset(response)
    reset_header = response['X-RateLimit-Reset']
    return nil unless reset_header

    # Handle Unix timestamp
    if reset_header.match?(/^\d+$/)
      Time.at(reset_header.to_i) - Time.current
    else
      nil
    end
  end

  def extract_retry_after(response)
    retry_after = response['Retry-After']
    return nil unless retry_after

    retry_after.to_i
  end

  def default_rate_limit_wait
    300 # 5 minutes
  end
end
```

### Payload Errors

Handle payload-related issues:

```ruby
class PayloadErrorWebhook < ActionWebhook::Base
  rescue_from JSON::GeneratorError, with: :handle_json_error
  rescue_from ArgumentError, with: :handle_argument_error
  rescue_from PayloadValidationError, with: :handle_payload_validation_error

  before_deliver :validate_payload

  private

  def validate_payload
    raise PayloadValidationError, "Payload cannot be nil" if @payload.nil?
    raise PayloadValidationError, "Payload must be a Hash" unless @payload.is_a?(Hash)
    raise PayloadValidationError, "Payload too large" if payload_too_large?

    validate_required_fields
    validate_field_types
    sanitize_payload
  end

  def validate_required_fields
    required_fields.each do |field|
      unless @payload.key?(field)
        raise PayloadValidationError, "Missing required field: #{field}"
      end
    end
  end

  def validate_field_types
    field_validations.each do |field, expected_type|
      next unless @payload.key?(field)

      actual_value = @payload[field]
      unless actual_value.is_a?(expected_type)
        raise PayloadValidationError,
              "Field #{field} must be #{expected_type}, got #{actual_value.class}"
      end
    end
  end

  def sanitize_payload
    # Remove sensitive or problematic fields
    sensitive_fields.each { |field| @payload.delete(field) }

    # Convert symbols to strings for JSON serialization
    @payload = deep_stringify_keys(@payload)
  end

  def handle_json_error(error)
    Rails.logger.error "JSON serialization error: #{error.message}"

    # Try to identify the problematic field
    problematic_field = identify_json_problem(@payload)

    if problematic_field
      Rails.logger.error "Problematic field: #{problematic_field}"
      # Remove the problematic field and retry
      @payload.delete(problematic_field)
      perform
    else
      discard_with_error("Unable to serialize payload to JSON")
    end
  end

  def handle_argument_error(error)
    Rails.logger.error "Argument error: #{error.message}"
    discard_with_error("Invalid arguments provided")
  end

  def handle_payload_validation_error(error)
    Rails.logger.error "Payload validation error: #{error.message}"

    # Log the invalid payload for debugging
    Rails.logger.debug "Invalid payload: #{@payload.inspect}"

    discard_with_error("Payload validation failed: #{error.message}")
  end

  def payload_too_large?
    @payload.to_json.bytesize > max_payload_size
  end

  def max_payload_size
    1.megabyte
  end

  def required_fields
    %i[id event data]
  end

  def field_validations
    {
      id: String,
      event: String,
      data: Hash,
      timestamp: Time
    }
  end

  def sensitive_fields
    %w[password auth_token secret_key]
  end

  def identify_json_problem(obj, path = '')
    case obj
    when Hash
      obj.each do |key, value|
        current_path = path.empty? ? key.to_s : "#{path}.#{key}"
        result = identify_json_problem(value, current_path)
        return result if result
      end
    when Array
      obj.each_with_index do |value, index|
        current_path = "#{path}[#{index}]"
        result = identify_json_problem(value, current_path)
        return result if result
      end
    else
      # Check if this value can be serialized
      begin
        obj.to_json
      rescue
        return path
      end
    end

    nil
  end

  def deep_stringify_keys(obj)
    case obj
    when Hash
      obj.transform_keys(&:to_s).transform_values { |v| deep_stringify_keys(v) }
    when Array
      obj.map { |v| deep_stringify_keys(v) }
    else
      obj
    end
  end

  class PayloadValidationError < StandardError; end
end
```

### Configuration Errors

Handle configuration-related issues:

```ruby
class ConfigurationErrorWebhook < ActionWebhook::Base
  rescue_from ConfigurationError, with: :handle_configuration_error
  rescue_from MissingCredentialsError, with: :handle_missing_credentials

  before_deliver :validate_configuration

  private

  def validate_configuration
    raise ConfigurationError, "Endpoint URL not configured" if endpoint_url.blank?
    raise ConfigurationError, "Invalid endpoint URL" unless valid_url?(endpoint_url)
    raise MissingCredentialsError, "Webhook credentials not found" unless credentials_available?
  end

  def handle_configuration_error(error)
    Rails.logger.error "Configuration error: #{error.message}"

    # Notify administrators about configuration issues
    AdminNotifier.configuration_error(self.class.name, error.message).deliver_now

    discard_with_error("Configuration error: #{error.message}")
  end

  def handle_missing_credentials(error)
    Rails.logger.error "Missing credentials: #{error.message}"

    # Try to refresh credentials if possible
    if can_refresh_credentials?
      refresh_credentials
      perform # Retry with new credentials
    else
      AdminNotifier.missing_credentials(self.class.name).deliver_now
      discard_with_error("Credentials not available")
    end
  end

  def valid_url?(url)
    uri = URI.parse(url)
    uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
  rescue URI::InvalidURIError
    false
  end

  def credentials_available?
    # Check if required credentials are present
    webhook_credentials.present?
  end

  def can_refresh_credentials?
    # Logic to determine if credentials can be refreshed
    credential_refresh_service.available?
  end

  def refresh_credentials
    new_credentials = credential_refresh_service.refresh
    update_webhook_credentials(new_credentials)
  end

  class ConfigurationError < StandardError; end
  class MissingCredentialsError < StandardError; end
end
```

## Error Recovery Strategies

### Exponential Backoff

Implement intelligent retry timing:

```ruby
class ExponentialBackoffWebhook < ActionWebhook::Base
  rescue_from StandardError, with: :handle_with_backoff

  private

  def handle_with_backoff(error)
    if should_retry?(error)
      wait_time = calculate_backoff
      Rails.logger.warn "Retrying webhook after #{wait_time}s: #{error.message}"
      retry_job(wait: wait_time.seconds)
    else
      Rails.logger.error "Webhook failed permanently: #{error.message}"
      handle_permanent_failure(error)
    end
  end

  def should_retry?(error)
    return false if executions >= max_retries
    return false if permanent_error?(error)

    true
  end

  def calculate_backoff
    base_delay = 2 ** [executions, 8].min # Cap at 256 seconds base
    jitter = rand(0.5..1.5) # Add randomness
    [base_delay * jitter, max_delay].min
  end

  def max_delay
    1800 # 30 minutes
  end

  def max_retries
    5
  end

  def permanent_error?(error)
    case error
    when Net::HTTPClientError
      error.response.code.to_i.between?(400, 499) && error.response.code.to_i != 429
    when ConfigurationError, PayloadValidationError
      true
    else
      false
    end
  end
end
```

### Circuit Breaker

Prevent cascading failures:

```ruby
class CircuitBreakerWebhook < ActionWebhook::Base
  rescue_from StandardError, with: :handle_with_circuit_breaker

  private

  def handle_with_circuit_breaker(error)
    if circuit_breaker_open?
      Rails.logger.warn "Circuit breaker open for #{endpoint_url}"
      schedule_circuit_breaker_retry
      return
    end

    begin
      # Record the attempt
      record_attempt

      # If we get here without an error, record success
      record_success
    rescue => retry_error
      record_failure

      if should_open_circuit?
        open_circuit_breaker
      end

      raise retry_error
    end
  end

  def circuit_breaker_open?
    circuit_state == 'open' && circuit_opened_at > circuit_timeout.ago
  end

  def should_open_circuit?
    failure_count >= failure_threshold &&
    failure_rate >= failure_rate_threshold
  end

  def open_circuit_breaker
    Rails.cache.write(circuit_state_key, 'open')
    Rails.cache.write(circuit_opened_key, Time.current)

    Rails.logger.warn "Circuit breaker opened for #{endpoint_url}"
    AdminNotifier.circuit_breaker_opened(endpoint_url).deliver_later
  end

  def record_attempt
    Rails.cache.increment(attempt_count_key, 1, expires_in: 1.hour)
  end

  def record_success
    Rails.cache.delete(failure_count_key)
    Rails.cache.delete(circuit_state_key)
  end

  def record_failure
    Rails.cache.increment(failure_count_key, 1, expires_in: 1.hour)
  end

  def schedule_circuit_breaker_retry
    # Retry after circuit timeout
    retry_job(wait: circuit_timeout)
  end

  def circuit_state
    Rails.cache.read(circuit_state_key) || 'closed'
  end

  def circuit_opened_at
    Rails.cache.read(circuit_opened_key) || 1.hour.ago
  end

  def failure_count
    Rails.cache.read(failure_count_key) || 0
  end

  def failure_rate
    attempts = Rails.cache.read(attempt_count_key) || 0
    return 0 if attempts == 0

    (failure_count.to_f / attempts * 100).round(2)
  end

  def circuit_state_key
    "circuit_breaker:#{endpoint_host}:state"
  end

  def circuit_opened_key
    "circuit_breaker:#{endpoint_host}:opened_at"
  end

  def failure_count_key
    "circuit_breaker:#{endpoint_host}:failures"
  end

  def attempt_count_key
    "circuit_breaker:#{endpoint_host}:attempts"
  end

  def endpoint_host
    URI.parse(endpoint_url).host
  end

  def failure_threshold
    5
  end

  def failure_rate_threshold
    50 # 50%
  end

  def circuit_timeout
    10.minutes
  end
end
```

## Dead Letter Queue

Handle permanently failed webhooks:

```ruby
class DeadLetterWebhook < ActionWebhook::Base
  rescue_from StandardError, with: :handle_with_dead_letter

  private

  def handle_with_dead_letter(error)
    if should_retry?(error)
      retry_job(wait: exponential_backoff)
    else
      send_to_dead_letter_queue(error)
    end
  end

  def send_to_dead_letter_queue(error)
    Rails.logger.error "Sending webhook to dead letter queue: #{error.message}"

    DeadLetterQueue.add(
      webhook_class: self.class.name,
      payload: @payload,
      endpoint_url: endpoint_url,
      error: {
        message: error.message,
        class: error.class.name,
        backtrace: error.backtrace&.first(10)
      },
      attempts: executions,
      failed_at: Time.current
    )

    # Notify administrators
    AdminNotifier.webhook_dead_letter(self, error).deliver_later
  end

  def should_retry?(error)
    executions < max_retries && !permanent_error?(error)
  end
end

class DeadLetterQueue
  def self.add(webhook_data)
    # Store in database
    WebhookFailure.create!(webhook_data)

    # Store in Redis for quick access
    Redis.current.lpush('webhook_dead_letters', webhook_data.to_json)

    # Limit dead letter queue size
    Redis.current.ltrim('webhook_dead_letters', 0, 999)
  end

  def self.retry_all
    WebhookFailure.pending.find_each do |failure|
      retry_webhook(failure)
    end
  end

  def self.retry_webhook(failure)
    webhook_class = failure.webhook_class.constantize
    webhook_class.perform_later(failure.payload)
    failure.update!(retried_at: Time.current)
  end
end
```

## Error Monitoring and Alerting

Set up comprehensive error monitoring:

```ruby
class MonitoredErrorWebhook < ActionWebhook::Base
  rescue_from StandardError, with: :handle_monitored_error

  private

  def handle_monitored_error(error)
    # Record error metrics
    record_error_metrics(error)

    # Send to error tracking service
    report_to_error_tracker(error)

    # Alert if error rate is high
    check_error_rate_and_alert

    # Handle the error normally
    if should_retry?(error)
      retry_job(wait: exponential_backoff)
    else
      discard_with_error(error.message)
    end
  end

  def record_error_metrics(error)
    tags = {
      webhook_class: self.class.name,
      error_class: error.class.name,
      endpoint_host: URI.parse(endpoint_url).host,
      http_status: extract_http_status(error)
    }

    StatsD.increment('webhook.error.count', tags: tags)
    StatsD.histogram('webhook.error.retry_count', executions, tags: tags)
  end

  def report_to_error_tracker(error)
    Sentry.capture_exception(error, extra: {
      webhook_class: self.class.name,
      endpoint_url: endpoint_url,
      payload_size: @payload.to_s.bytesize,
      attempt: executions
    })
  end

  def check_error_rate_and_alert
    error_rate = calculate_recent_error_rate

    if error_rate > error_rate_threshold
      AlertService.webhook_error_rate_high(
        webhook_class: self.class.name,
        endpoint: endpoint_url,
        error_rate: error_rate
      )
    end
  end

  def calculate_recent_error_rate
    # Calculate error rate for last hour
    total_attempts = Rails.cache.read("webhook_attempts:#{self.class.name}") || 0
    error_count = Rails.cache.read("webhook_errors:#{self.class.name}") || 0

    return 0 if total_attempts == 0

    (error_count.to_f / total_attempts * 100).round(2)
  end

  def error_rate_threshold
    25 # 25%
  end

  def extract_http_status(error)
    case error
    when Net::HTTPError
      error.response&.code
    else
      nil
    end
  end
end
```

## Testing Error Handling

Test your error handling logic:

```ruby
# spec/webhooks/error_handling_webhook_spec.rb
RSpec.describe ErrorHandlingWebhook do
  let(:webhook) { described_class.new(payload) }
  let(:payload) { { id: 1, event: 'test', data: {} } }

  describe 'network error handling' do
    it 'retries on timeout errors' do
      allow(webhook).to receive(:post_webhook).and_raise(Net::TimeoutError)
      expect(webhook).to receive(:retry_job)

      webhook.perform
    end

    it 'marks endpoint as down after max retries' do
      allow(webhook).to receive(:executions).and_return(5)
      allow(webhook).to receive(:post_webhook).and_raise(SocketError)

      expect(webhook).to receive(:mark_endpoint_down)
      webhook.perform
    end
  end

  describe 'HTTP error handling' do
    it 'does not retry on 4xx errors' do
      error = Net::HTTPBadRequest.new('400', '400', 'Bad Request')
      allow(webhook).to receive(:post_webhook).and_raise(error)

      expect(webhook).not_to receive(:retry_job)
      webhook.perform
    end

    it 'retries on 5xx errors' do
      error = Net::HTTPInternalServerError.new('500', '500', 'Internal Server Error')
      allow(webhook).to receive(:post_webhook).and_raise(error)

      expect(webhook).to receive(:retry_job)
      webhook.perform
    end

    it 'handles rate limiting' do
      error = Net::HTTPTooManyRequests.new('429', '429', 'Too Many Requests')
      allow(error).to receive(:response).and_return({ 'Retry-After' => '60' })
      allow(webhook).to receive(:post_webhook).and_raise(error)

      expect(webhook).to receive(:retry_job).with(wait: 60.seconds)
      webhook.perform
    end
  end

  describe 'payload error handling' do
    it 'discards webhooks with invalid payloads' do
      webhook.instance_variable_set(:@payload, nil)

      expect { webhook.perform }.to raise_error(/Payload cannot be nil/)
    end

    it 'handles JSON serialization errors' do
      invalid_object = Object.new
      def invalid_object.to_json
        raise JSON::GeneratorError, "Cannot serialize"
      end

      webhook.instance_variable_set(:@payload, { data: invalid_object })

      expect(webhook).to receive(:discard_with_error)
      webhook.perform
    end
  end
end
```

## Best Practices

1. **Categorize errors appropriately** - Distinguish between retryable and permanent errors
2. **Use exponential backoff** - Prevent overwhelming failing services
3. **Implement circuit breakers** - Protect against cascading failures
4. **Monitor error rates** - Set up alerts for unusual error patterns
5. **Log comprehensively** - Include context for debugging
6. **Handle credentials gracefully** - Refresh when possible, alert when not
7. **Validate early** - Catch payload issues before attempting delivery
8. **Use dead letter queues** - Don't lose failed webhooks
9. **Test error scenarios** - Ensure error handling works as expected
10. **Alert on patterns** - Monitor for systematic issues

## See Also

- [Retry Logic](retry-logic.md) - Configuring retry behavior
- [Queue Management](queue-management.md) - Managing failed jobs
- [Monitoring](monitoring.md) - Monitoring webhook health
- [Testing](testing.md) - Testing error handling
