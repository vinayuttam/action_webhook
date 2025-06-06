# Simple User Webhook Example

This example demonstrates a basic user webhook that sends notifications when users are created, updated, or deleted.

## Webhook Class

```ruby
# app/webhooks/user_webhook.rb
class UserWebhook < ActionWebhook::Base
  def initialize(user, event = 'user.created')
    @user = user
    @event = event
    super
  end

  private

  def payload_template
    {
      event: @event,
      timestamp: Time.current.iso8601,
      data: {
        id: @user.id,
        email: @user.email,
        name: @user.full_name,
        created_at: @user.created_at.iso8601,
        updated_at: @user.updated_at.iso8601
      }
    }
  end

  def endpoints
    [
      'https://analytics.example.com/webhooks/users',
      'https://crm.example.com/api/webhooks'
    ]
  end
end
```

## Model Integration

```ruby
# app/models/user.rb
class User < ApplicationRecord
  after_create :send_creation_webhook
  after_update :send_update_webhook
  after_destroy :send_deletion_webhook

  private

  def send_creation_webhook
    UserWebhook.perform_later(self, 'user.created')
  end

  def send_update_webhook
    UserWebhook.perform_later(self, 'user.updated')
  end

  def send_deletion_webhook
    UserWebhook.perform_later(self, 'user.deleted')
  end
end
```

## Usage Examples

### Immediate Delivery

```ruby
# Send webhook immediately
user = User.create!(name: 'John Doe', email: 'john@example.com')
UserWebhook.new(user, 'user.created').deliver_now
```

### Background Delivery

```ruby
# Send webhook in background
user = User.create!(name: 'Jane Smith', email: 'jane@example.com')
UserWebhook.perform_later(user, 'user.created')
```

### Scheduled Delivery

```ruby
# Send webhook in 1 hour
user = User.find(1)
UserWebhook.perform_in(1.hour, user, 'user.updated')

# Send webhook at specific time
UserWebhook.perform_at(Time.zone.parse("2024-01-01 09:00:00"), user, 'user.reminder')
```

## Expected Payload

When a user is created, the webhook will send this payload:

```json
{
  "event": "user.created",
  "timestamp": "2024-01-15T10:30:00Z",
  "data": {
    "id": 123,
    "email": "john@example.com",
    "name": "John Doe",
    "created_at": "2024-01-15T10:29:30Z",
    "updated_at": "2024-01-15T10:29:30Z"
  }
}
```

## Testing

```ruby
# spec/webhooks/user_webhook_spec.rb
RSpec.describe UserWebhook do
  let(:user) { create(:user, name: 'Test User', email: 'test@example.com') }
  let(:webhook) { described_class.new(user, 'user.created') }

  describe '#payload_template' do
    it 'includes user data' do
      payload = webhook.send(:payload_template)

      expect(payload[:event]).to eq('user.created')
      expect(payload[:data]).to include(
        id: user.id,
        email: user.email,
        name: user.name
      )
    end
  end

  describe 'delivery' do
    before do
      stub_request(:post, "https://analytics.example.com/webhooks/users")
        .to_return(status: 200)
      stub_request(:post, "https://crm.example.com/api/webhooks")
        .to_return(status: 200)
    end

    it 'delivers to all endpoints' do
      webhook.deliver_now

      expect(WebMock).to have_requested(:post, "https://analytics.example.com/webhooks/users")
      expect(WebMock).to have_requested(:post, "https://crm.example.com/api/webhooks")
    end
  end
end
```

## Configuration

Add webhook configuration to your Rails app:

```ruby
# config/initializers/webhooks.rb
ActionWebhook.configure do |config|
  config.default_queue = 'webhooks'
  config.timeout = 30
  config.default_retries = 3
end
```

## Queue Configuration

Configure Sidekiq for background processing:

```yaml
# config/sidekiq.yml
:queues:
  - webhooks
  - default
```

This simple example shows how to set up basic user webhooks that integrate seamlessly with your Rails models and deliver notifications to external services when users are created, updated, or deleted.
