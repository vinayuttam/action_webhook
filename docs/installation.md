# Installation

## Requirements

- Ruby 2.7+
- Rails 6.0+
- Redis (for background job processing)

## Gemfile

Add ActionWebhook to your Gemfile:

```ruby
gem 'action_webhook'
```

Then run:

```bash
bundle install
```

## Generator

Run the installation generator to set up the basic configuration:

```bash
rails generate action_webhook:install
```

This will create:
- `config/initializers/action_webhook.rb` - Configuration file
- `app/webhooks/` - Directory for your webhook classes
- `app/webhooks/application_webhook.rb` - Base webhook class
- Migration for webhook delivery tracking (optional)

## Database Setup

If you want to track webhook deliveries in your database (recommended for production):

```bash
rails db:migrate
```

## Background Job Setup

ActionWebhook works with any ActiveJob adapter. For production, we recommend using Sidekiq:

```ruby
# Gemfile
gem 'sidekiq'

# config/application.rb
config.active_job.queue_adapter = :sidekiq
```

## Verification

Verify the installation by creating a simple webhook:

```ruby
# app/webhooks/test_webhook.rb
class TestWebhook < ApplicationWebhook
  def ping
    @message = "Hello, World!"
    @timestamp = Time.current

    endpoints = [{ url: 'https://httpbin.org/post' }]
    deliver(endpoints)
  end
end
```

Test it in the Rails console:

```ruby
TestWebhook.ping.deliver_now
```

## Next Steps

- [Quick Start Guide](quick-start.md) - Build your first webhook
- [Configuration](configuration.md) - Configure ActionWebhook for your needs
- [Basic Usage](basic-usage.md) - Learn the core concepts
