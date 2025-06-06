# Templates and Customization

ActionWebhook provides a flexible template system for customizing HTTP request parameters, headers, and payload structure.

## Template System Overview

The template system uses ERB (Embedded Ruby) to dynamically generate webhook content. Templates can access instance variables and methods from your webhook class.

## Available Variables

### Standard Variables
- `@payload` - The data being sent to the webhook
- `@endpoint` - The webhook endpoint configuration
- `@event` - The event that triggered the webhook
- `@timestamp` - The time when the webhook was triggered

### Custom Variables
You can expose additional variables by defining them in your webhook class:

```ruby
class OrderWebhook < ActionWebhook::Base
  def initialize(order)
    @order = order
    @customer = order.customer
    super
  end

  private

  def payload_template
    {
      event: "order.created",
      order_id: @order.id,
      customer_email: @customer.email,
      total: @order.total_amount
    }
  end
end
```

## Template Types

### 1. Payload Templates

Customize the JSON payload sent to webhook endpoints:

```ruby
class CustomPayloadWebhook < ActionWebhook::Base
  private

  def payload_template
    {
      timestamp: Time.current.iso8601,
      event: event_name,
      data: {
        id: @record.id,
        type: @record.class.name.underscore,
        attributes: @record.attributes.except('created_at', 'updated_at')
      },
      metadata: {
        version: "1.0",
        source: "action_webhook"
      }
    }
  end
end
```

### 2. Header Templates

Customize HTTP headers for webhook requests:

```ruby
class SignedWebhook < ActionWebhook::Base
  private

  def headers_template
    payload_json = @payload.to_json
    signature = generate_signature(payload_json)

    {
      'Content-Type' => 'application/json',
      'X-Webhook-Signature' => signature,
      'X-Webhook-Timestamp' => Time.current.to_i.to_s,
      'User-Agent' => 'ActionWebhook/1.0'
    }
  end

  def generate_signature(payload)
    OpenSSL::HMAC.hexdigest('sha256', webhook_secret, payload)
  end

  def webhook_secret
    Rails.application.credentials.webhook_secret
  end
end
```

### 3. URL Templates

Dynamically generate webhook URLs:

```ruby
class DynamicUrlWebhook < ActionWebhook::Base
  private

  def url_template(base_url)
    "#{base_url}/webhooks/#{@event}/#{@record.id}"
  end

  def deliver_webhooks
    endpoints.each do |endpoint|
      url = url_template(endpoint.url)
      post_webhook(url, @payload, endpoint.headers)
    end
  end
end
```

## ERB Templates

For complex templates, you can use ERB template files:

### 1. Create Template Files

```erb
<!-- app/views/webhooks/order_created.json.erb -->
{
  "event": "order.created",
  "timestamp": "<%= @timestamp.iso8601 %>",
  "order": {
    "id": <%= @order.id %>,
    "number": "<%= @order.number %>",
    "status": "<%= @order.status %>",
    "total": <%= @order.total_amount %>,
    "customer": {
      "id": <%= @order.customer.id %>,
      "email": "<%= @order.customer.email %>",
      "name": "<%= @order.customer.full_name %>"
    },
    "items": [
      <% @order.items.each_with_index do |item, index| %>
      {
        "id": <%= item.id %>,
        "name": "<%= item.name %>",
        "quantity": <%= item.quantity %>,
        "price": <%= item.price %>
      }<%= index < @order.items.count - 1 ? ',' : '' %>
      <% end %>
    ]
  }
}
```

### 2. Use Template in Webhook Class

```ruby
class OrderWebhook < ActionWebhook::Base
  def initialize(order)
    @order = order
    @timestamp = Time.current
    super
  end

  private

  def payload_template
    template = File.read(Rails.root.join('app/views/webhooks/order_created.json.erb'))
    erb = ERB.new(template)
    JSON.parse(erb.result(binding))
  end
end
```

## Conditional Templates

Use conditional logic in templates:

```ruby
class ConditionalWebhook < ActionWebhook::Base
  private

  def payload_template
    base_payload = {
      event: @event,
      timestamp: Time.current.iso8601,
      data: @record.attributes
    }

    # Add customer data only for orders
    if @record.is_a?(Order)
      base_payload[:customer] = {
        id: @record.customer.id,
        email: @record.customer.email
      }
    end

    # Add different fields based on event type
    case @event
    when 'created'
      base_payload[:welcome_message] = "Welcome to our service!"
    when 'updated'
      base_payload[:changes] = @record.previous_changes
    when 'deleted'
      base_payload[:deleted_at] = Time.current.iso8601
    end

    base_payload
  end
end
```

## Template Helpers

Create helper methods for common template operations:

```ruby
class WebhookWithHelpers < ActionWebhook::Base
  private

  def payload_template
    {
      event: @event,
      timestamp: formatted_timestamp,
      data: sanitized_attributes,
      metadata: request_metadata
    }
  end

  def formatted_timestamp
    Time.current.strftime("%Y-%m-%d %H:%M:%S UTC")
  end

  def sanitized_attributes
    @record.attributes.except(*sensitive_fields)
  end

  def sensitive_fields
    %w[password password_digest auth_token]
  end

  def request_metadata
    {
      source: 'action_webhook',
      version: ActionWebhook::VERSION,
      environment: Rails.env
    }
  end
end
```

## Template Inheritance

Create base templates for common patterns:

```ruby
class BaseWebhook < ActionWebhook::Base
  private

  def payload_template
    {
      event: @event,
      timestamp: Time.current.iso8601,
      data: data_template,
      metadata: metadata_template
    }
  end

  def data_template
    # Override in subclasses
    {}
  end

  def metadata_template
    {
      source: 'action_webhook',
      version: ActionWebhook::VERSION
    }
  end
end

class UserWebhook < BaseWebhook
  private

  def data_template
    {
      id: @user.id,
      email: @user.email,
      name: @user.full_name,
      created_at: @user.created_at.iso8601
    }
  end
end
```

## Security Considerations

### 1. Sanitize Sensitive Data

```ruby
class SecureWebhook < ActionWebhook::Base
  private

  def payload_template
    {
      event: @event,
      data: sanitized_data
    }
  end

  def sanitized_data
    @record.attributes.except(*sensitive_attributes)
  end

  def sensitive_attributes
    %w[password password_digest auth_token secret_key]
  end
end
```

### 2. Add Request Signatures

```ruby
class SignedWebhook < ActionWebhook::Base
  private

  def headers_template
    payload_json = @payload.to_json
    {
      'Content-Type' => 'application/json',
      'X-Webhook-Signature' => generate_hmac_signature(payload_json),
      'X-Webhook-Timestamp' => Time.current.to_i.to_s
    }
  end

  def generate_hmac_signature(payload)
    secret = Rails.application.credentials.webhook_secret
    'sha256=' + OpenSSL::HMAC.hexdigest('sha256', secret, payload)
  end
end
```

## Testing Templates

Test your templates to ensure they generate correct output:

```ruby
# spec/webhooks/order_webhook_spec.rb
RSpec.describe OrderWebhook do
  let(:order) { create(:order) }
  let(:webhook) { described_class.new(order) }

  describe '#payload_template' do
    it 'includes all required fields' do
      payload = webhook.send(:payload_template)

      expect(payload).to include(:event, :timestamp, :order)
      expect(payload[:order]).to include(:id, :number, :status, :total)
    end

    it 'excludes sensitive information' do
      payload = webhook.send(:payload_template)

      expect(payload.to_json).not_to include('password')
      expect(payload.to_json).not_to include('auth_token')
    end
  end
end
```

## Best Practices

1. **Keep templates simple** - Complex logic should be in helper methods
2. **Sanitize data** - Always exclude sensitive information
3. **Use consistent structure** - Maintain consistent payload format across webhooks
4. **Add versioning** - Include version information in payloads
5. **Test thoroughly** - Test templates with various data scenarios
6. **Document payload structure** - Provide clear documentation for webhook consumers

## See Also

- [Basic Usage](basic-usage.md) - Core webhook concepts
- [Configuration](configuration.md) - Webhook configuration options
- [Error Handling](error-handling.md) - Handling template errors
- [Testing](testing.md) - Testing webhook templates
