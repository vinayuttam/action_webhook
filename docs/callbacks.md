# Callbacks and Hooks

ActionWebhook provides a comprehensive callback system that allows you to hook into the webhook delivery lifecycle. This guide covers all available callbacks and how to use them effectively.

## Callback Overview

ActionWebhook supports callbacks at various stages of the webhook delivery process:

- **Before delivery** - Set up, validate, or modify webhook data
- **After delivery** - Handle success/failure, logging, cleanup
- **Around delivery** - Wrap the entire delivery process
- **Conditional callbacks** - Execute only under certain conditions

## Available Callbacks

### Before Callbacks

Execute code before webhook delivery:

```ruby
class CallbackWebhook < ActionWebhook::Base
  before_deliver :validate_payload
  before_deliver :add_timestamp
  before_deliver :check_rate_limits

  private

  def validate_payload
    raise ArgumentError, "Invalid payload" unless @payload.is_a?(Hash)
    raise ArgumentError, "Missing required fields" unless required_fields_present?
  end

  def add_timestamp
    @payload[:timestamp] = Time.current.iso8601
  end

  def check_rate_limits
    if rate_limit_exceeded?
      delay_delivery(calculate_delay)
    end
  end

  def required_fields_present?
    %w[id event data].all? { |field| @payload.key?(field.to_sym) }
  end
end
```

### After Callbacks

Execute code after webhook delivery:

```ruby
class CallbackWebhook < ActionWebhook::Base
  after_deliver :log_delivery
  after_deliver :update_metrics
  after_deliver :notify_completion

  private

  def log_delivery
    if delivery_successful?
      Rails.logger.info "Webhook delivered successfully to #{endpoint_url}"
    else
      Rails.logger.error "Webhook delivery failed to #{endpoint_url}: #{last_error&.message}"
    end
  end

  def update_metrics
    WebhookMetrics.record_delivery(
      webhook_class: self.class.name,
      endpoint: endpoint_url,
      success: delivery_successful?,
      duration: delivery_duration
    )
  end

  def notify_completion
    if delivery_successful?
      WebhookDeliveryNotifier.success(self)
    else
      WebhookDeliveryNotifier.failure(self, last_error)
    end
  end
end
```

### Around Callbacks

Wrap the entire delivery process:

```ruby
class CallbackWebhook < ActionWebhook::Base
  around_deliver :measure_performance
  around_deliver :handle_circuit_breaker

  private

  def measure_performance
    start_time = Time.current

    begin
      yield # Execute the delivery
    ensure
      duration = Time.current - start_time
      record_performance_metrics(duration)
    end
  end

  def handle_circuit_breaker
    if circuit_breaker_open?
      Rails.logger.warn "Circuit breaker open for #{endpoint_url}"
      return
    end

    begin
      yield
      circuit_breaker_record_success
    rescue => error
      circuit_breaker_record_failure
      raise
    end
  end

  def record_performance_metrics(duration)
    StatsD.histogram('webhook.delivery.duration', duration * 1000, tags: {
      webhook_class: self.class.name,
      endpoint_host: URI.parse(endpoint_url).host
    })
  end
end
```

## Conditional Callbacks

Execute callbacks only under certain conditions:

```ruby
class ConditionalCallbackWebhook < ActionWebhook::Base
  before_deliver :validate_business_hours, if: :business_hours_required?
  before_deliver :add_priority_headers, if: :high_priority?
  after_deliver :send_notification, unless: :silent_mode?
  after_deliver :trigger_followup, if: :followup_required?

  private

  def business_hours_required?
    @payload[:requires_business_hours] == true
  end

  def high_priority?
    @payload[:priority] == 'high'
  end

  def silent_mode?
    @options[:silent] == true
  end

  def followup_required?
    delivery_successful? && @payload[:followup_action].present?
  end

  def validate_business_hours
    unless business_hours?
      schedule_for_business_hours
      halt_delivery
    end
  end

  def add_priority_headers
    @headers['X-Priority'] = 'high'
    @headers['X-Urgent'] = 'true'
  end

  def send_notification
    NotificationService.webhook_delivered(self)
  end

  def trigger_followup
    FollowupWebhook.perform_later(@payload[:followup_action])
  end

  def business_hours?
    Time.current.wday.between?(1, 5) && Time.current.hour.between?(9, 17)
  end

  def schedule_for_business_hours
    next_business_day = Time.current.next_weekday.beginning_of_day + 9.hours
    self.class.perform_at(next_business_day, @payload, @options)
  end

  def halt_delivery
    throw(:abort)
  end
end
```

## Callback Chain Control

Control callback execution flow:

```ruby
class ControlledCallbackWebhook < ActionWebhook::Base
  before_deliver :check_prerequisites
  before_deliver :prepare_payload
  after_deliver :cleanup_resources

  private

  def check_prerequisites
    unless prerequisites_met?
      Rails.logger.warn "Prerequisites not met for webhook delivery"
      throw(:abort) # Halt the callback chain and skip delivery
    end
  end

  def prepare_payload
    return unless @payload[:needs_preparation]

    begin
      @payload = PayloadPreprocessor.process(@payload)
    rescue => error
      Rails.logger.error "Payload preparation failed: #{error.message}"
      throw(:abort)
    end
  end

  def cleanup_resources
    # This runs regardless of delivery success/failure
    TempFileCleanup.clean(@payload[:temp_files])
  end

  def prerequisites_met?
    required_services_available? && rate_limits_ok? && endpoint_reachable?
  end
end
```

## Class-Level Callbacks

Define callbacks that apply to all instances:

```ruby
class BaseWebhook < ActionWebhook::Base
  before_deliver :log_delivery_start
  after_deliver :log_delivery_end
  around_deliver :track_delivery_time

  class << self
    def configure_callbacks(&block)
      instance_eval(&block)
    end
  end

  private

  def log_delivery_start
    Rails.logger.info "Starting webhook delivery: #{self.class.name} to #{endpoint_url}"
  end

  def log_delivery_end
    status = delivery_successful? ? 'SUCCESS' : 'FAILED'
    Rails.logger.info "Webhook delivery #{status}: #{self.class.name}"
  end

  def track_delivery_time
    start_time = Time.current
    yield
  ensure
    duration = Time.current - start_time
    WebhookAnalytics.record_delivery_time(self.class.name, duration)
  end
end

# Configure callbacks for specific webhook types
class OrderWebhook < BaseWebhook
  configure_callbacks do
    before_deliver :validate_order_data
    after_deliver :update_order_status
  end

  private

  def validate_order_data
    raise ArgumentError, "Invalid order data" unless @payload[:order_id].present?
  end

  def update_order_status
    return unless delivery_successful?

    Order.find(@payload[:order_id]).update!(webhook_delivered_at: Time.current)
  end
end
```

## Error Handling in Callbacks

Handle errors within callbacks:

```ruby
class ErrorHandlingCallbackWebhook < ActionWebhook::Base
  before_deliver :risky_preparation
  after_deliver :cleanup_with_error_handling

  private

  def risky_preparation
    begin
      perform_risky_operation
    rescue RiskyOperationError => error
      Rails.logger.warn "Risky operation failed: #{error.message}"
      # Continue with delivery despite the error
    rescue CriticalError => error
      Rails.logger.error "Critical error in preparation: #{error.message}"
      throw(:abort) # Halt delivery
    end
  end

  def cleanup_with_error_handling
    begin
      perform_cleanup
    rescue => error
      # Log but don't re-raise - cleanup errors shouldn't affect delivery status
      Rails.logger.error "Cleanup error: #{error.message}"
    end
  end

  def perform_risky_operation
    # Some operation that might fail
    ExternalService.prepare_data(@payload)
  end

  def perform_cleanup
    # Cleanup operations
    TempCache.clear(@payload[:cache_key])
  end
end
```

## Callback Inheritance

Inherit and extend callbacks in subclasses:

```ruby
class BaseWebhook < ActionWebhook::Base
  before_deliver :base_preparation
  after_deliver :base_cleanup

  private

  def base_preparation
    @delivery_id = SecureRandom.uuid
    Rails.logger.info "Webhook delivery started: #{@delivery_id}"
  end

  def base_cleanup
    Rails.logger.info "Webhook delivery completed: #{@delivery_id}"
  end
end

class ExtendedWebhook < BaseWebhook
  # These callbacks run in addition to parent callbacks
  before_deliver :extended_preparation
  after_deliver :extended_cleanup

  private

  def extended_preparation
    @custom_headers = generate_custom_headers
  end

  def extended_cleanup
    CustomMetrics.record_delivery(@delivery_id, delivery_successful?)
  end
end

class OverriddenWebhook < BaseWebhook
  # Skip parent callbacks and define your own
  skip_before_deliver :base_preparation
  before_deliver :custom_preparation

  private

  def custom_preparation
    # Custom logic instead of base_preparation
    @custom_delivery_id = "custom_#{SecureRandom.hex(8)}"
  end
end
```

## Callback Metadata

Pass data between callbacks:

```ruby
class MetadataCallbackWebhook < ActionWebhook::Base
  before_deliver :set_delivery_context
  before_deliver :prepare_signed_payload
  after_deliver :record_delivery_metrics

  private

  def set_delivery_context
    @delivery_context = {
      delivery_id: SecureRandom.uuid,
      started_at: Time.current,
      endpoint_host: URI.parse(endpoint_url).host
    }
  end

  def prepare_signed_payload
    @delivery_context[:signature] = generate_signature(@payload)
    @headers['X-Webhook-Signature'] = @delivery_context[:signature]
  end

  def record_delivery_metrics
    @delivery_context[:completed_at] = Time.current
    @delivery_context[:duration] = @delivery_context[:completed_at] - @delivery_context[:started_at]
    @delivery_context[:success] = delivery_successful?

    DeliveryMetrics.record(@delivery_context)
  end

  def generate_signature(payload)
    OpenSSL::HMAC.hexdigest('sha256', webhook_secret, payload.to_json)
  end

  def webhook_secret
    Rails.application.credentials.webhook_secret
  end
end
```

## Testing Callbacks

Test callback behavior:

```ruby
# spec/webhooks/callback_webhook_spec.rb
RSpec.describe CallbackWebhook do
  let(:webhook) { described_class.new(payload) }
  let(:payload) { { id: 1, event: 'test', data: {} } }

  describe 'before_deliver callbacks' do
    it 'validates payload' do
      webhook.instance_variable_set(:@payload, {})

      expect { webhook.deliver_now }.to raise_error(ArgumentError, "Missing required fields")
    end

    it 'adds timestamp to payload' do
      expect(webhook.instance_variable_get(:@payload)).not_to have_key(:timestamp)

      webhook.send(:add_timestamp)

      expect(webhook.instance_variable_get(:@payload)).to have_key(:timestamp)
    end
  end

  describe 'after_deliver callbacks' do
    before do
      allow(webhook).to receive(:post_webhook).and_return(double(success?: true))
    end

    it 'logs successful delivery' do
      expect(Rails.logger).to receive(:info).with(/Webhook delivered successfully/)

      webhook.deliver_now
    end

    it 'updates metrics' do
      expect(WebhookMetrics).to receive(:record_delivery)

      webhook.deliver_now
    end
  end

  describe 'conditional callbacks' do
    context 'when high priority' do
      let(:payload) { { id: 1, event: 'test', data: {}, priority: 'high' } }

      it 'adds priority headers' do
        webhook.send(:add_priority_headers)

        expect(webhook.instance_variable_get(:@headers)['X-Priority']).to eq('high')
      end
    end

    context 'when not high priority' do
      it 'does not add priority headers' do
        expect(webhook.send(:high_priority?)).to be false
      end
    end
  end

  describe 'callback chain control' do
    it 'halts delivery when prerequisites not met' do
      allow(webhook).to receive(:prerequisites_met?).and_return(false)
      expect(webhook).not_to receive(:post_webhook)

      webhook.deliver_now
    end
  end
end
```

## Performance Considerations

Optimize callback performance:

```ruby
class OptimizedCallbackWebhook < ActionWebhook::Base
  # Use method references for better performance
  before_deliver :validate_payload, :add_timestamp
  after_deliver :log_delivery, :update_metrics

  # Avoid expensive operations in callbacks
  before_deliver :lightweight_preparation
  after_deliver :schedule_heavy_processing

  private

  def lightweight_preparation
    # Quick validations and modifications only
    @payload[:delivery_id] = SecureRandom.uuid
  end

  def schedule_heavy_processing
    # Schedule expensive operations as separate jobs
    HeavyProcessingJob.perform_later(@payload, delivery_successful?)
  end

  def validate_payload
    # Fast validation logic
    return if @payload.is_a?(Hash) && @payload.key?(:id)

    throw(:abort)
  end
end
```

## Best Practices

1. **Keep callbacks focused** - Each callback should have a single responsibility
2. **Handle errors gracefully** - Don't let callback errors break webhook delivery
3. **Use conditional callbacks** - Apply callbacks only when needed
4. **Optimize performance** - Keep callbacks lightweight and fast
5. **Test callback behavior** - Ensure callbacks work correctly in all scenarios
6. **Document callback purpose** - Make callback intent clear for maintainers
7. **Avoid side effects** - Be careful about modifying shared state
8. **Use around callbacks sparingly** - They can make code harder to follow
9. **Consider callback order** - Callbacks execute in definition order
10. **Log important callback actions** - For debugging and monitoring

## See Also

- [Basic Usage](basic-usage.md) - Core webhook concepts
- [Error Handling](error-handling.md) - Handling errors in callbacks
- [Testing](testing.md) - Testing webhook callbacks
- [Templates](templates.md) - Using callbacks with templates
