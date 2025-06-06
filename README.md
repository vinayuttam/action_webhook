# ActionWebhook 🪝

[![Gem Version](https://badge.fury.io/rb/action_webhook.svg)](https://badge.fury.io/rb/action_webhook)
[![CI](https://github.com/vinayuttam/action_webhook/workflows/CI/badge.svg)](https://github.com/vinayuttam/action_webhook/actions/workflows/main.yml)
[![Release](https://github.com/vinayuttam/action_webhook/workflows/Release/badge.svg)](https://github.com/vinayuttam/action_webhook/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**ActionWebhook** is a Rails-friendly framework for delivering structured webhooks with the elegance and familiarity of ActionMailer. Built for modern Rails applications, it provides a clean, testable, and reliable way to send webhooks to external services.

## ✨ Features

- **🎯 ActionMailer-inspired API** - Familiar patterns for Rails developers
- **📄 ERB Template Support** - Dynamic JSON payloads with embedded Ruby
- **🔄 Built-in Retry Logic** - Configurable retry strategies with exponential backoff
- **⚡ ActiveJob Integration** - Queue webhooks using your existing job infrastructure
- **🎣 Flexible Callbacks** - Hook into delivery lifecycle events
- **🛡️ Error Handling** - Comprehensive error handling and logging
- **🧪 Test-Friendly** - Built-in testing utilities and helpers
- **📊 Multiple Endpoints** - Send to multiple URLs simultaneously
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

```ruby
class PaymentWebhook < ActionWebhook::Base
  # Configure retry behavior
  self.max_retries = 5
  self.retry_delay = 30.seconds
  self.backoff_multiplier = 2.0

  def payment_completed
    # webhook logic
  end
end
```

### Callbacks and Hooks

```ruby
class OrderWebhook < ActionWebhook::Base
  # Lifecycle callbacks
  before_deliver :validate_payload
  after_deliver :log_success
  after_retries_exhausted :notify_admin

  def order_created
    @order = params[:order]
    deliver(webhook_endpoints)
  end

  private

  def validate_payload
    raise 'Invalid order' unless @order.valid?
  end

  def log_success(response)
    Rails.logger.info "Webhook delivered successfully for order #{@order.id}"
  end

  def notify_admin(response)
    AdminMailer.webhook_failure(@order.id, response).deliver_later
  end
end
```

### Multiple Endpoints

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
  end
end
```

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
