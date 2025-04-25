# ActionWebhook

A Rails-friendly framework for delivering structured webhooks with the elegance of ActionMailer.

---

## 📦 Installation

Add this line to your Gemfile:

```ruby
gem 'action_webhook'
```

## 🚀 Usage

1. Create a webhook class

```ruby
# app/webhooks/user_webhook.rb

class UserWebhook < ActionWebhook::Base
  # Configure retries specifically for this webhook
  self.max_retries = 5
  self.retry_delay = 10.seconds

  # Define callbacks
  after_deliver :log_success
  after_retries_exhausted :notify_admin

  def created
    @user = User.first
    @timestamp = Time.current

    endpoints = [
      {
        url: 'https://rbaskets.in/2ka8ww5',
        headers: {  # Changed from 'header' to 'headers'
          'Authorization' => 'PKRYigFRa9dRIWFpz7S8CNao2EyTG5nLnr3k8ta85U'  # Changed from symbol to string key
        }
      }
    ]

    deliver(endpoints)
  end

  private

  def log_success(response)  # Only needs one parameter
    Rails.logger.info "Successfully delivered webhook for user #{@user.id}"
  end

  def notify_admin(response)  # Only needs one parameter
    Rails.logger.info "Exhausted webhooks retries for user #{@user.id}"
    # Consider adding more robust failure notification here
    # AdminMailer.webhook_failure_alert(@user.id, response).deliver_later
  end
end

```

2. Create the Payload Template

```ruby
<!-- app/webhooks/user_webhook/created.json.erb -->
{
  "event": "user_created",
  "user_id": "<%= user[:id] %>",
  "email": "<%= user[:email] %>",
  "created_at": "<%= user[:created_at] %>"
}
```

3. Trigger the webhook

```ruby
UserWebhook.created.deliver_now
```
