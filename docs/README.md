# ActionWebhook Documentation

Welcome to the ActionWebhook documentation! This library provides a Rails-inspired way to define and deliver webhooks in your Rails applications.

## Table of Contents

### Getting Started
- [Installation](installation.md)
- [Quick Start Guide](quick-start.md)
- [Configuration](configuration.md)

### Core Concepts
- [Basic Usage](basic-usage.md)
- [Templates](templates.md)
- [Queue Management](queue-management.md)
- [Retry Logic](retry-logic.md)
- [Callbacks](callbacks.md)

### Advanced Topics
- [Error Handling](error-handling.md)
- [Testing](testing.md)
- [Performance](performance.md)
- [Security](security.md)

### Development & Deployment
- [GitHub Actions Workflows](github-actions.md)
- [Release Process](release-process.md)

### Guides
- [Rails Engine Integration](rails-engine-integration.md)
- [Background Jobs](background-jobs.md)
- [Monitoring & Logging](monitoring-logging.md)

### API Reference
- [ActionWebhook::Base](api/base.md)
- [Configuration Options](api/configuration.md)
- [DeliveryJob](api/delivery-job.md)

### Examples
- [User Management Webhooks](examples/user-webhooks.md)
- [Order Processing Webhooks](examples/order-webhooks.md)
- [Custom Headers & Authentication](examples/authentication.md)

## Overview

ActionWebhook is designed to make webhook delivery as simple and reliable as sending emails in Rails. It provides:

- **Template-based payloads** - Use ERB templates to define your webhook payloads
- **Reliable delivery** - Built-in retry logic with exponential backoff
- **Background processing** - Integrate with ActiveJob for asynchronous delivery
- **Rails Engine support** - Works seamlessly with Rails engines
- **Testing utilities** - Built-in test mode for development and testing

## Quick Example

```ruby
class UserWebhook < ActionWebhook::Base
  def created(user)
    @user = user
    endpoints = WebhookSubscription.where(event: 'user.created').pluck(:url, :headers)
    deliver(endpoints)
  end
end

# Usage
UserWebhook.created(user).deliver_now
UserWebhook.created(user).deliver_later(queue: 'webhooks')
```

## Need Help?

- Check the [FAQ](faq.md)
- Look at the [troubleshooting guide](troubleshooting.md)
- Review the [examples](examples/)

## Contributing

See our [contributing guide](../CONTRIBUTING.md) for information on how to contribute to this project.
