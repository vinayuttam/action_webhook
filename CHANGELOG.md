# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 30 July 2025

### 🔗 Enhanced Header Support

- **Multiple Header Formats**: Added support for array-based header format alongside existing hash format
- **Database-Friendly Headers**: Headers can now be provided as `[{'key' => 'name', 'value' => 'value'}]` format
- **Flexible Key Types**: Support for both string and symbol keys in array format (`key`/`:key`, `value`/`:value`)
- **Backward Compatibility**: Existing hash-based headers continue to work without changes
- **Auto-Detection**: Automatic detection and transformation of header formats in `build_headers` method
- **Robust Error Handling**: Graceful handling of malformed data with logging and fallbacks
- **Type Safety**: Automatic conversion of keys and values to strings for HTTP consistency
- **Comprehensive Testing**: Extensive test coverage for edge cases and reliability

### 🛡️ Reliability Improvements

- **Null Safety**: Handles `nil` keys/values gracefully without errors
- **Malformed Data Handling**: Skips invalid header items with warning logs
- **Type Validation**: Validates input types and provides helpful error messages
- **Consistent Output**: Ensures all headers are properly formatted for HTTP requests

### 📚 Documentation Updates

- Added comprehensive header format documentation to README
- Updated inline code documentation with detailed examples
- Enhanced class-level documentation with usage patterns

## [1.1.0] - 2025-06-06

### 🚀 Enhanced Retry Logic

- **Selective Retry**: Only retry URLs that actually failed, not all URLs in a batch delivery
- **Intelligent Response Handling**: Separate successful and failed responses for more efficient processing
- **Targeted Callbacks**: `after_deliver` callback now triggers immediately for successful deliveries
- **Improved Logging**: More detailed retry logging showing exact number of URLs being retried

### 🔧 Technical Improvements

- Enhanced `deliver_now` method to handle partial failures intelligently
- Updated `retry_with_backoff` to accept specific failed webhook details
- Improved serialization to only include failed URLs in retry jobs
- Better separation of concerns between success and failure handling

### 📊 Benefits

- **Efficiency**: Reduces unnecessary retry attempts for successful deliveries
- **Performance**: Lower resource usage by avoiding redundant network calls
- **Reliability**: More accurate callback invocation for monitoring and alerting
- **Observability**: Better insights into which specific endpoints are failing

## [1.0.0] - 2025-06-06

### 🎉 First Stable Release

This is the first stable release of ActionWebhook, providing a complete, production-ready framework for webhook delivery in Rails applications.

### ✨ Features

- **ActionMailer-inspired API** - Familiar patterns for Rails developers with `deliver_now` and `deliver_later` methods
- **ERB Template Support** - Dynamic JSON payload generation using embedded Ruby templates
- **Built-in Retry Logic** - Configurable retry strategies with exponential backoff and maximum retry limits
- **ActiveJob Integration** - Seamless integration with Rails job queuing system
- **Flexible Callbacks** - Lifecycle hooks including `before_deliver`, `after_deliver`, and `after_retries_exhausted`
- **Multiple Endpoint Support** - Send webhooks to multiple URLs simultaneously with different headers
- **Comprehensive Error Handling** - Robust error handling with detailed logging and graceful degradation
- **Test Utilities** - Built-in testing helpers for webhook verification in test suites
- **Highly Configurable** - Per-webhook class configuration for retries, delays, and behavior

### 🔧 Core Components

- `ActionWebhook::Base` - Main webhook base class with delivery methods
- `ActionWebhook::DeliveryJob` - ActiveJob class for background webhook processing
- `ActionWebhook::Configuration` - Global and per-class configuration management
- `ActionWebhook::Callbacks` - Callback system for lifecycle hooks
- `ActionWebhook::TestHelper` - Testing utilities and helpers

### 🛠️ Technical Details

- **Ruby Support**: >= 3.1.0
- **Rails Support**: >= 7.0
- **Dependencies**: HTTParty for HTTP requests, Rails for ActiveJob integration
- **Template Engine**: ERB for dynamic payload generation
- **Logging**: Comprehensive logging with success, warning, and error levels

### 🔒 Breaking Changes

- Fixed `post_webhook` method signature to use single `payload` parameter instead of array for consistent delivery
- Updated parameter validation to ensure proper type checking
- Standardized callback method signatures for consistency

### 📈 Performance & Reliability

- Optimized HTTP request handling with proper timeout configuration
- Implemented exponential backoff for retry logic
- Added comprehensive error logging for debugging and monitoring
- Memory-efficient payload template rendering

### 📚 Documentation

- Complete wiki-style documentation in `/docs` directory
- Installation and quick start guides
- Configuration reference with all available options
- Advanced usage patterns and real-world examples
- API reference documentation
- Testing guide with practical examples
- Error handling strategies

### 🧪 Testing

- Comprehensive test suite ensuring reliability
- Testing utilities for easy webhook verification
- Support for both immediate and queued delivery testing
- Mock and stub helpers for external service testing

## [0.1.1] - 2024-XX-XX

### Fixed
- Initial bug fixes and stability improvements

## [0.1.0] - 2024-XX-XX

### Added
- Initial release with basic webhook functionality
