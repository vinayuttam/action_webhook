# Quick Start Guide

This guide will walk you through creating your first webhook in 5 minutes.

## Step 1: Create a Webhook Class

Create a new webhook class in `app/webhooks/`:

```ruby
# app/webhooks/user_webhook.rb
class UserWebhook < ApplicationWebhook
  def created(user)
    @user = user
    @event = 'user.created'
    @timestamp = Time.current

    # Get webhook endpoints from your configuration
    endpoints = [
      {
        url: 'https://your-app.com/webhooks/user-created',
        headers: { 'Authorization' => 'Bearer your-secret-token' }
      }
    ]

    deliver(endpoints)
  end

  def updated(user)
    @user = user
    @event = 'user.updated'
    @timestamp = Time.current

    endpoints = WebhookSubscription.where(event: 'user.updated').map do |sub|
      { url: sub.url, headers: sub.headers }
    end

    deliver(endpoints)
  end
end
```

## Step 2: Create a Template

Create an ERB template for your webhook payload:

```erb
<!-- app/webhooks/user_webhook/created.json.erb -->
{
  "event": "<%= @event %>",
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

## Step 3: Trigger the Webhook

In your controller or model, trigger the webhook:

```ruby
# app/controllers/users_controller.rb
class UsersController < ApplicationController
  def create
    @user = User.new(user_params)

    if @user.save
      # Send webhook immediately
      UserWebhook.created(@user).deliver_now

      # Or send in background
      # UserWebhook.created(@user).deliver_later

      redirect_to @user, notice: 'User was successfully created.'
    else
      render :new
    end
  end
end
```

Or use ActiveRecord callbacks:

```ruby
# app/models/user.rb
class User < ApplicationRecord
  after_create_commit :send_created_webhook
  after_update_commit :send_updated_webhook

  private

  def send_created_webhook
    UserWebhook.created(self).deliver_later(queue: 'webhooks')
  end

  def send_updated_webhook
    UserWebhook.updated(self).deliver_later(queue: 'webhooks')
  end
end
```

## Step 4: Test Your Webhook

### In Development

Use a service like [ngrok](https://ngrok.com/) to create a public URL for testing:

```bash
ngrok http 3000
```

Then use the ngrok URL in your webhook endpoints.

### In Rails Console

```ruby
# Create a test user
user = User.create!(name: 'John Doe', email: 'john@example.com')

# Send webhook immediately
response = UserWebhook.created(user).deliver_now

# Check the response
puts response.inspect
# => [{:success=>true, :status=>200, :body=>"...", :url=>"...", :attempt=>1}]
```

### Test Mode

For testing, you can use test mode:

```ruby
# In your test setup
ActionWebhook::Base.delivery_method = :test

# Your webhook calls will be captured instead of sent
UserWebhook.created(user).deliver_now

# Check captured webhooks
ActionWebhook::Base.deliveries.count # => 1
ActionWebhook::Base.deliveries.first # => #<UserWebhook...>
```

## Step 5: Background Processing

For production, always use background processing:

```ruby
# Immediate delivery
UserWebhook.created(user).deliver_now

# Background delivery (default queue)
UserWebhook.created(user).deliver_later

# Background delivery with specific queue
UserWebhook.created(user).deliver_later(queue: 'webhooks')

# Background delivery with delay
UserWebhook.created(user).deliver_later(wait: 5.minutes)

# Background delivery with queue and delay
UserWebhook.created(user).deliver_later(queue: 'webhooks', wait: 1.minute)
```

## What's Next?

Now that you have a basic webhook working, explore these topics:

- [Templates](templates.md) - Learn more about creating dynamic payloads
- [Queue Management](queue-management.md) - Organize your webhook processing
- [Retry Logic](retry-logic.md) - Handle failures gracefully
- [Error Handling](error-handling.md) - Debug and monitor webhook deliveries
- [Testing](testing.md) - Write tests for your webhooks

## Common Patterns

### Database-Driven Endpoints

```ruby
class UserWebhook < ApplicationWebhook
  def created(user)
    @user = user

    endpoints = WebhookSubscription
      .active
      .where(event: 'user.created')
      .map { |sub| { url: sub.url, headers: sub.headers.to_h } }

    deliver(endpoints) if endpoints.any?
  end
end
```

### Conditional Webhooks

```ruby
class OrderWebhook < ApplicationWebhook
  def status_changed(order)
    return unless should_send_webhook?(order)

    @order = order
    @previous_status = order.status_was

    endpoints = webhook_endpoints_for_order(order)
    deliver(endpoints)
  end

  private

  def should_send_webhook?(order)
    # Only send for significant status changes
    %w[paid shipped delivered cancelled].include?(order.status)
  end
end
```
