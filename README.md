# ActionWebhook 🪝

[![Gem Version](https://badge.fury.io/rb/action_webhook.svg)](https://badge.fury.io/rb/action_webhook)
[![CI](https://github.com/vinayuttam/action_webhook/workflows/CI/badge.svg)](https://github.com/vinayuttam/action_webhook/actions/workflows/main.yml)
[![Release](https://github.com/vinayuttam/action_webhook/workflows/Release/badge.svg)](https://github.com/vinayuttam/action_webhook/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**ActionWebhook** is a Rails-friendly framework for delivering structured webhooks with the elegance and familiarity of ActionMailer. Built for modern Rails applications, it provides a clean, testable, and reliable way to send webhooks to external services.

## ✨ Features

- **🎯 ActionMailer-inspired API** - Familiar patterns for Rails developers
- **📄 ERB Template Support** - Dynamic JSON payloads with embedded Ruby
- **🔄 Smart Retry Logic** - Only retries failed URLs, not successful ones
- **⚡ ActiveJob Integration** - Queue webhooks using your existing job infrastructure
- **🎣 Flexible Callbacks** - Hook into delivery lifecycle events
- **🛡️ Error Handling** - Comprehensive error handling and logging
- **🧪 Test-Friendly** - Built-in testing utilities and helpers
- **📊 Multiple Endpoints** - Send to multiple URLs simultaneously with selective retry
- **🔧 Highly Configurable** - Fine-tune behavior per webhook class
- **📝 Comprehensive Logging** - Detailed logging for debugging and monitoring

## 📦 Installation

Add this line to your application's Gemfile:

```ruby
gem 'action_webhook'
```

And then execute:

```bash
$ bundle install
```

## 🚀 Quick Start

### 1. Generate a Webhook Class

```ruby
# app/webhooks/user_webhook.rb
class UserWebhook < ActionWebhook::Base
  def user_created
    @user = params[:user]
    @timestamp = Time.current

    endpoints = [
      {
        url: 'https://api.example.com/webhooks',
        headers: {
          'Authorization' => 'Bearer your-token',
          'Content-Type' => 'application/json'
        }
      }
    ]

    deliver(endpoints)
  end
end
```

### 2. Create a Payload Template

```erb
<!-- app/webhooks/user_webhook/user_created.json.erb -->
{
  "event": "user.created",
  "timestamp": "<%= @timestamp.iso8601 %>",
  "data": {
    "user": {
      "id": <%= @user.id %>,
      "email": "<%= @user.email %>",
      "name": "<%= @user.name %>",
      "created_at": "<%= @user.created_at.iso8601 %>"
    }
  }
}
```

### 3. Trigger the Webhook

```ruby
# Immediate delivery
UserWebhook.user_created(user: @user).deliver_now

# Background delivery (recommended)
UserWebhook.user_created(user: @user).deliver_later

# With custom queue
UserWebhook.user_created(user: @user).deliver_later(queue: 'webhooks')
```

## 🔧 Advanced Configuration

### Retry Configuration

ActionWebhook intelligently retries only the URLs that fail, not all URLs in a batch:

```ruby
class PaymentWebhook < ActionWebhook::Base
  # Configure retry behavior
  self.max_retries = 5
  self.retry_delay = 30.seconds
  self.retry_backoff = :exponential  # :exponential, :linear, or :fixed
  self.retry_jitter = 5.seconds      # Adds randomness to prevent thundering herd

  def payment_completed
    @payment = params[:payment]

    endpoints = [
      { url: 'https://accounting.example.com/webhooks' },
      { url: 'https://analytics.example.com/webhooks' },
      { url: 'https://notifications.example.com/webhooks' }
    ]

    deliver(endpoints)
    # If only analytics.example.com fails, only that URL will be retried
  end
end
```

### Smart Callbacks

Get notified about successful deliveries immediately and permanent failures after retries are exhausted:

```ruby
class OrderWebhook < ActionWebhook::Base
  # Called immediately when any URLs succeed
  after_deliver :handle_successful_deliveries

  # Called when retries are exhausted for failed URLs
  after_retries_exhausted :handle_permanent_failures

  def order_created
    @order = params[:order]
    deliver(webhook_endpoints)
  end

  private

  def handle_successful_deliveries(successful_responses)
    successful_responses.each do |response|
      Rails.logger.info "Webhook delivered to #{response[:url]} (#{response[:status]})"
    end
  end

  def handle_permanent_failures(failed_responses)
    failed_responses.each do |response|
      Rails.logger.error "Webhook permanently failed for #{response[:url]} after #{response[:attempt]} attempts"
      AdminMailer.webhook_failure(@order.id, response).deliver_later
    end
  end
end
```

### Debug Configuration

Enable detailed logging of headers and request information for debugging:

```ruby
class MyWebhook < ActionWebhook::Base
  self.debug_headers = true  # Enable header debugging

  def user_created
    @user = params[:user]
    endpoints = [
      {
        url: 'https://api.example.com/webhooks',
        headers: [
          { 'key' => 'Authorization', 'value' => 'Bearer token123' },
          { 'key' => 'X-Custom-Header', 'value' => 'debug-mode' }
        ]
      }
    ]
    deliver(endpoints)
  end
end
```

When `debug_headers` is enabled, you'll see detailed logs like:

```
ActionWebhook Headers Debug:
  Default headers: {}
  Processed headers: {"Authorization"=>"Bearer token123", "X-Custom-Header"=>"debug-mode"}
  Final headers: {"Authorization"=>"Bearer token123", "X-Custom-Header"=>"debug-mode", "Content-Type"=>"application/json"}

ActionWebhook Request Debug:
  URL: https://api.example.com/webhooks
  Headers: {"Authorization"=>"Bearer token123", "X-Custom-Header"=>"debug-mode", "Content-Type"=>"application/json"}
  Payload size: 156 bytes
```

### Multiple Endpoints with Selective Retry

Send to multiple endpoints efficiently with intelligent retry logic:

```ruby
class NotificationWebhook < ActionWebhook::Base
  def user_registered
    @user = params[:user]

    endpoints = [
      {
        url: 'https://analytics.example.com/events',
        headers: { 'X-API-Key' => Rails.application.credentials.analytics_key }
      },
      {
        url: 'https://crm.example.com/webhooks',
        headers: { 'Authorization' => "Bearer #{Rails.application.credentials.crm_token}" }
      },
      {
        url: 'https://marketing.example.com/api/events',
        headers: { 'X-Service-Token' => Rails.application.credentials.marketing_token }
      }
    ]

    deliver(endpoints)
    # If marketing.example.com fails but others succeed,
    # only marketing.example.com will be retried
  end
end
```

### Real-world Example: E-commerce Order Processing

```ruby
class OrderWebhook < ActionWebhook::Base
  self.max_retries = 3
  self.retry_delay = 30.seconds
  self.retry_backoff = :exponential

  after_deliver :log_successful_integrations
  after_retries_exhausted :handle_integration_failures

  def order_placed
    @order = params[:order]

    endpoints = [
      { url: 'https://inventory.company.com/webhooks' },      # Update inventory
      { url: 'https://shipping.company.com/api/orders' },     # Create shipping label
      { url: 'https://analytics.company.com/events' },       # Track conversion
      { url: 'https://email.company.com/order-confirmation' }, # Send confirmation
      { url: 'https://accounting.company.com/webhooks' }     # Update books
    ]

    deliver(endpoints)
  end

  private

  def log_successful_integrations(responses)
    responses.each do |response|
      OrderIntegration.create!(
        order: @order,
        service_url: response[:url],
        status: 'success',
        http_status: response[:status],
        attempt: response[:attempt]
      )
    end
  end

  def handle_integration_failures(responses)
    responses.each do |response|
      OrderIntegration.create!(
        order: @order,
        service_url: response[:url],
        status: 'failed',
        error_message: response[:error],
        final_attempt: response[:attempt]
      )

      # Alert based on criticality
      case response[:url]
      when /inventory|accounting/
        CriticalAlert.webhook_failure(@order, response)
      else
        StandardAlert.webhook_failure(@order, response)
      end
    end
  end
end
```

## 🔗 Header Formats

ActionWebhook supports two different header formats to accommodate various storage and usage patterns:

### Hash Format (Standard)

The traditional approach where headers are provided as a simple hash:

```ruby
endpoints = [
  {
    url: 'https://api.example.com/webhooks',
    headers: {
      'Authorization' => 'Bearer token123',
      'Content-Type' => 'application/json',
      'X-Custom-Header' => 'custom-value'
    }
  }
]
```

### Array Format (Database-Friendly)

Useful when storing headers in databases where you need structured data with separate key and value fields:

```ruby
endpoints = [
  {
    url: 'https://api.example.com/webhooks',
    headers: [
      { 'key' => 'Authorization', 'value' => 'Bearer token123' },
      { 'key' => 'Content-Type', 'value' => 'application/json' },
      { 'key' => 'X-Custom-Header', 'value' => 'custom-value' }
    ]
  }
]
```

### Symbol Keys Support

Both string and symbol keys are supported in the array format:

```ruby
headers: [
  { key: 'Authorization', value: 'Bearer token123' },
  { key: 'Content-Type', value: 'application/json' }
]
```

This flexibility makes it easy to integrate with various data storage patterns, whether you're storing headers as JSON in a database column or using a separate headers table with key/value pairs.

## 🧪 Testing

ActionWebhook provides testing utilities to make webhook testing straightforward:

```ruby
# In your test files
require 'action_webhook/test_helper'

class UserWebhookTest < ActiveSupport::TestCase
  include ActionWebhook::TestHelper

  test "user_created webhook sends correct payload" do
    user = users(:john)

    # Test immediate delivery
    webhook = UserWebhook.user_created(user: user)

    assert_enqueued_webhook_deliveries 1 do
      webhook.deliver_later
    end

    # Test payload content
    perform_enqueued_webhook_deliveries do
      webhook.deliver_later
    end

    # Verify webhook was sent
    assert_webhook_delivered UserWebhook, :user_created
  end
end
```

## 📚 Documentation

Comprehensive documentation is available in the [docs](./docs) directory:

- **[Installation Guide](./docs/installation.md)** - Detailed setup instructions
- **[Quick Start Tutorial](./docs/quick-start.md)** - Step-by-step getting started
- **[Configuration Reference](./docs/configuration.md)** - All configuration options
- **[Basic Usage](./docs/basic-usage.md)** - Core concepts and patterns
- **[Template System](./docs/templates.md)** - Working with ERB templates
- **[Queue Management](./docs/queue-management.md)** - ActiveJob integration
- **[Retry Logic](./docs/retry-logic.md)** - Error handling and retries
- **[Callbacks](./docs/callbacks.md)** - Lifecycle hooks and callbacks
- **[Error Handling](./docs/error-handling.md)** - Comprehensive error strategies
- **[Testing Guide](./docs/testing.md)** - Testing webhooks effectively
- **[API Reference](./docs/api/)** - Complete API documentation
- **[Examples](./docs/examples/)** - Real-world usage examples

## 🤝 Contributing

We love contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📋 Requirements

- Ruby >= 3.1.0
- ActiveJob >= 6.0 (included in Rails 6.0+)

## 📄 License

This gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## 🙋‍♂️ Support

- **Documentation**: [docs](./docs)
- **Issues**: [GitHub Issues](https://github.com/vinayuttam/action_webhook/issues)
- **Discussions**: [GitHub Discussions](https://github.com/vinayuttam/action_webhook/discussions)

## 🎯 Roadmap

- [ ] GraphQL webhook support
- [ ] Webhook signature verification
- [ ] Built-in webhook endpoint discovery
- [ ] Metrics and monitoring integration
- [ ] Advanced filtering and conditional delivery

## 📝 Documentation Notes

This documentation was generated with assistance from GitHub Copilot to ensure comprehensive coverage and clarity. If you find any errors, inconsistencies, or areas that need improvement, please [open an issue](https://github.com/vinayuttam/action_webhook/issues) so we can make corrections and keep the documentation accurate and helpful for everyone.

---

**ActionWebhook** - Making webhook delivery as elegant as sending emails in Rails. 🚀
