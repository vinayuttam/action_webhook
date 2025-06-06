# Testing

Comprehensive testing is crucial for reliable webhook delivery. This guide covers testing strategies, tools, and best practices for ActionWebhook applications.

## Testing Overview

ActionWebhook testing involves several areas:
- Unit testing webhook classes
- Integration testing webhook delivery
- Testing error handling and retry logic
- Testing callback behavior
- Testing queue integration
- End-to-end testing with real endpoints

## Unit Testing

### Basic Webhook Testing

```ruby
# spec/webhooks/user_webhook_spec.rb
RSpec.describe UserWebhook do
  let(:user) { create(:user) }
  let(:webhook) { described_class.new(user) }

  describe '#initialize' do
    it 'sets up the webhook with user data' do
      expect(webhook.instance_variable_get(:@user)).to eq(user)
      expect(webhook.instance_variable_get(:@payload)).to include(
        id: user.id,
        email: user.email
      )
    end
  end

  describe '#payload_template' do
    it 'returns the correct payload structure' do
      payload = webhook.send(:payload_template)

      expect(payload).to include(
        event: 'user.created',
        timestamp: be_a(String),
        data: include(
          id: user.id,
          email: user.email,
          name: user.full_name
        )
      )
    end

    it 'excludes sensitive information' do
      payload = webhook.send(:payload_template)

      expect(payload.to_json).not_to include('password')
      expect(payload.to_json).not_to include('auth_token')
    end
  end

  describe '#headers_template' do
    it 'includes required headers' do
      headers = webhook.send(:headers_template)

      expect(headers).to include(
        'Content-Type' => 'application/json',
        'User-Agent' => 'ActionWebhook/1.0'
      )
    end

    it 'includes authentication headers when configured' do
      allow(webhook).to receive(:webhook_secret).and_return('secret123')

      headers = webhook.send(:headers_template)

      expect(headers).to have_key('X-Webhook-Signature')
    end
  end
end
```

### Testing Callback Behavior

```ruby
# spec/webhooks/callback_webhook_spec.rb
RSpec.describe CallbackWebhook do
  let(:webhook) { described_class.new(payload) }
  let(:payload) { { id: 1, event: 'test', data: {} } }

  describe 'before_deliver callbacks' do
    it 'validates payload before delivery' do
      webhook.instance_variable_set(:@payload, {})

      expect { webhook.deliver_now }.to raise_error(ArgumentError)
    end

    it 'adds timestamp to payload' do
      expect(webhook.instance_variable_get(:@payload)).not_to have_key(:timestamp)

      webhook.send(:add_timestamp)

      expect(webhook.instance_variable_get(:@payload)).to have_key(:timestamp)
    end

    it 'halts delivery when prerequisites not met' do
      allow(webhook).to receive(:prerequisites_met?).and_return(false)
      expect(webhook).not_to receive(:post_webhook)

      webhook.deliver_now
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

    it 'updates metrics after delivery' do
      expect(WebhookMetrics).to receive(:record_delivery)

      webhook.deliver_now
    end
  end

  describe 'conditional callbacks' do
    context 'when high priority' do
      let(:payload) { { id: 1, event: 'test', data: {}, priority: 'high' } }

      it 'executes priority callbacks' do
        expect(webhook).to receive(:add_priority_headers)

        webhook.deliver_now
      end
    end

    context 'when not high priority' do
      it 'skips priority callbacks' do
        expect(webhook).not_to receive(:add_priority_headers)

        webhook.deliver_now
      end
    end
  end
end
```

## Integration Testing

### Testing HTTP Delivery

```ruby
# spec/webhooks/integration/webhook_delivery_spec.rb
RSpec.describe 'Webhook Delivery Integration' do
  let(:webhook) { UserWebhook.new(user) }
  let(:user) { create(:user) }

  before do
    stub_request(:post, "https://example.com/webhook")
      .to_return(status: 200, body: '{"success": true}')
  end

  it 'delivers webhook successfully' do
    webhook.deliver_now

    expect(WebMock).to have_requested(:post, "https://example.com/webhook")
      .with(
        body: hash_including(
          'event' => 'user.created',
          'data' => hash_including('id' => user.id)
        ),
        headers: hash_including(
          'Content-Type' => 'application/json'
        )
      )
  end

  it 'includes authentication headers' do
    webhook.deliver_now

    expect(WebMock).to have_requested(:post, "https://example.com/webhook")
      .with(headers: hash_including('X-Webhook-Signature'))
  end

  it 'handles successful responses' do
    expect { webhook.deliver_now }.not_to raise_error
    expect(webhook.delivery_successful?).to be true
  end

  it 'handles error responses' do
    stub_request(:post, "https://example.com/webhook")
      .to_return(status: 500, body: 'Internal Server Error')

    expect { webhook.deliver_now }.to raise_error(Net::HTTPServerError)
  end
end
```

### Testing Multiple Endpoints

```ruby
# spec/webhooks/integration/multi_endpoint_spec.rb
RSpec.describe 'Multi-Endpoint Webhook Delivery' do
  let(:webhook) { MultiEndpointWebhook.new(order) }
  let(:order) { create(:order) }

  before do
    # Stub multiple endpoints
    stub_request(:post, "https://endpoint1.com/webhook")
      .to_return(status: 200, body: '{"success": true}')

    stub_request(:post, "https://endpoint2.com/webhook")
      .to_return(status: 200, body: '{"received": true}')

    stub_request(:post, "https://endpoint3.com/webhook")
      .to_return(status: 500, body: 'Server Error')
  end

  it 'delivers to all configured endpoints' do
    webhook.deliver_now

    expect(WebMock).to have_requested(:post, "https://endpoint1.com/webhook")
    expect(WebMock).to have_requested(:post, "https://endpoint2.com/webhook")
    expect(WebMock).to have_requested(:post, "https://endpoint3.com/webhook")
  end

  it 'continues delivery even if one endpoint fails' do
    expect { webhook.deliver_now }.not_to raise_error

    # Should still deliver to successful endpoints
    expect(WebMock).to have_requested(:post, "https://endpoint1.com/webhook")
    expect(WebMock).to have_requested(:post, "https://endpoint2.com/webhook")
  end

  it 'tracks delivery status per endpoint' do
    webhook.deliver_now

    expect(webhook.endpoint_results).to include(
      'https://endpoint1.com/webhook' => { success: true },
      'https://endpoint2.com/webhook' => { success: true },
      'https://endpoint3.com/webhook' => { success: false }
    )
  end
end
```

## Testing Error Handling

### Network Error Testing

```ruby
# spec/webhooks/error_handling_spec.rb
RSpec.describe 'Webhook Error Handling' do
  let(:webhook) { ErrorHandlingWebhook.new(payload) }
  let(:payload) { { id: 1, event: 'test' } }

  describe 'network errors' do
    it 'retries on timeout errors' do
      allow(webhook).to receive(:post_webhook).and_raise(Net::TimeoutError)
      expect(webhook).to receive(:retry_job).with(wait: anything)

      webhook.perform
    end

    it 'retries on connection errors' do
      allow(webhook).to receive(:post_webhook).and_raise(Net::ConnectTimeout)
      expect(webhook).to receive(:retry_job).with(wait: anything)

      webhook.perform
    end

    it 'gives up after max retries' do
      allow(webhook).to receive(:executions).and_return(5)
      allow(webhook).to receive(:post_webhook).and_raise(Net::TimeoutError)

      expect(webhook).not_to receive(:retry_job)
      expect { webhook.perform }.to raise_error(Net::TimeoutError)
    end
  end

  describe 'HTTP errors' do
    it 'does not retry on 4xx client errors' do
      error = Net::HTTPBadRequest.new('400', '400', 'Bad Request')
      allow(webhook).to receive(:post_webhook).and_raise(error)

      expect(webhook).not_to receive(:retry_job)
      webhook.perform
    end

    it 'retries on 5xx server errors' do
      error = Net::HTTPInternalServerError.new('500', '500', 'Internal Server Error')
      allow(webhook).to receive(:post_webhook).and_raise(error)

      expect(webhook).to receive(:retry_job)
      webhook.perform
    end

    it 'handles rate limiting with proper delay' do
      error = Net::HTTPTooManyRequests.new('429', '429', 'Too Many Requests')
      response = { 'Retry-After' => '60' }
      allow(error).to receive(:response).and_return(response)
      allow(webhook).to receive(:post_webhook).and_raise(error)

      expect(webhook).to receive(:retry_job).with(wait: 60.seconds)
      webhook.perform
    end
  end

  describe 'payload errors' do
    it 'handles invalid JSON gracefully' do
      invalid_payload = { data: Object.new }
      webhook.instance_variable_set(:@payload, invalid_payload)

      expect(webhook).to receive(:discard_with_error)
      webhook.perform
    end

    it 'validates required fields' do
      webhook.instance_variable_set(:@payload, {})

      expect { webhook.perform }.to raise_error(/Missing required/)
    end
  end
end
```

### Retry Logic Testing

```ruby
# spec/webhooks/retry_logic_spec.rb
RSpec.describe 'Webhook Retry Logic' do
  let(:webhook) { RetryWebhook.new(payload) }
  let(:payload) { { id: 1, event: 'test' } }

  describe 'exponential backoff' do
    it 'calculates correct backoff times' do
      expect(webhook.send(:calculate_backoff_time, 1)).to be_within(1).of(2)
      expect(webhook.send(:calculate_backoff_time, 2)).to be_within(2).of(4)
      expect(webhook.send(:calculate_backoff_time, 3)).to be_within(4).of(8)
    end

    it 'caps maximum backoff time' do
      long_backoff = webhook.send(:calculate_backoff_time, 10)
      expect(long_backoff).to be <= webhook.send(:max_delay)
    end

    it 'includes jitter in backoff calculation' do
      backoff1 = webhook.send(:calculate_backoff_time, 3)
      backoff2 = webhook.send(:calculate_backoff_time, 3)

      # Should be different due to jitter
      expect(backoff1).not_to eq(backoff2)
    end
  end

  describe 'retry conditions' do
    it 'retries transient errors' do
      allow(webhook).to receive(:executions).and_return(1)

      expect(webhook.send(:should_retry?, Net::TimeoutError.new)).to be true
    end

    it 'does not retry permanent errors' do
      error = Net::HTTPBadRequest.new('400', '400', 'Bad Request')

      expect(webhook.send(:should_retry?, error)).to be false
    end

    it 'stops retrying after max attempts' do
      allow(webhook).to receive(:executions).and_return(5)

      expect(webhook.send(:should_retry?, Net::TimeoutError.new)).to be false
    end
  end
end
```

## Testing Queue Integration

### ActiveJob Testing

```ruby
# spec/webhooks/queue_integration_spec.rb
RSpec.describe 'Webhook Queue Integration' do
  include ActiveJob::TestHelper

  let(:webhook) { QueuedWebhook.new(payload) }
  let(:payload) { { id: 1, event: 'test' } }

  describe 'job queuing' do
    it 'enqueues webhook for background processing' do
      expect { webhook.deliver_later }.to have_enqueued_job(WebhookJob)
    end

    it 'uses correct queue' do
      expect { webhook.deliver_later(queue: 'webhooks_high') }
        .to have_enqueued_job(WebhookJob).on_queue('webhooks_high')
    end

    it 'schedules delayed delivery' do
      expect { webhook.deliver_later(wait: 1.hour) }
        .to have_enqueued_job(WebhookJob).at(1.hour.from_now)
    end

    it 'sets job priority' do
      expect { webhook.deliver_later(priority: 10) }
        .to have_enqueued_job(WebhookJob).with(priority: 10)
    end
  end

  describe 'job execution' do
    it 'processes webhook when job runs' do
      stub_request(:post, "https://example.com/webhook")
        .to_return(status: 200)

      perform_enqueued_jobs do
        webhook.deliver_later
      end

      expect(WebMock).to have_requested(:post, "https://example.com/webhook")
    end

    it 'retries failed jobs' do
      stub_request(:post, "https://example.com/webhook")
        .to_return(status: 500)

      expect do
        perform_enqueued_jobs { webhook.deliver_later }
      end.to have_performed_job(WebhookJob).exactly(4).times # Initial + 3 retries
    end
  end
end
```

### Sidekiq Testing

```ruby
# spec/webhooks/sidekiq_integration_spec.rb
RSpec.describe 'Webhook Sidekiq Integration', :sidekiq do
  let(:webhook) { SidekiqWebhook.new(payload) }
  let(:payload) { { id: 1, event: 'test' } }

  describe 'job scheduling' do
    it 'schedules webhook job' do
      expect { webhook.deliver_later }.to change(WebhookJob.jobs, :size).by(1)
    end

    it 'schedules job on correct queue' do
      webhook.deliver_later(queue: 'webhooks')

      job = WebhookJob.jobs.last
      expect(job['queue']).to eq('webhooks')
    end

    it 'schedules job with correct arguments' do
      webhook.deliver_later

      job = WebhookJob.jobs.last
      expect(job['args']).to include(payload)
    end
  end

  describe 'job processing' do
    it 'processes jobs correctly' do
      stub_request(:post, "https://example.com/webhook")
        .to_return(status: 200)

      webhook.deliver_later
      WebhookJob.drain

      expect(WebMock).to have_requested(:post, "https://example.com/webhook")
    end

    it 'handles job failures' do
      stub_request(:post, "https://example.com/webhook")
        .to_return(status: 500)

      webhook.deliver_later

      expect { WebhookJob.drain }.to raise_error(Net::HTTPServerError)

      # Job should be in retry queue
      expect(Sidekiq::RetrySet.new.size).to eq(1)
    end
  end
end
```

## Testing with Real Endpoints

### Webhook Test Server

```ruby
# spec/support/webhook_test_server.rb
require 'webrick'
require 'json'

class WebhookTestServer
  attr_reader :port, :requests

  def initialize
    @port = find_available_port
    @requests = []
    @server = nil
  end

  def start
    @server = WEBrick::HTTPServer.new(
      Port: @port,
      Logger: WEBrick::Log.new(File.open(File::NULL, 'w')),
      AccessLog: []
    )

    @server.mount_proc('/webhook') do |req, res|
      @requests << {
        method: req.request_method,
        headers: req.header,
        body: req.body,
        timestamp: Time.current
      }

      case req.request_method
      when 'POST'
        handle_post_request(req, res)
      else
        res.status = 405
        res.body = 'Method Not Allowed'
      end
    end

    Thread.new { @server.start }
    wait_for_server_to_start
  end

  def stop
    @server&.shutdown
  end

  def url
    "http://localhost:#{@port}/webhook"
  end

  def last_request
    @requests.last
  end

  def clear_requests
    @requests.clear
  end

  private

  def find_available_port
    server = TCPServer.new('localhost', 0)
    port = server.addr[1]
    server.close
    port
  end

  def handle_post_request(req, res)
    # Simulate different response scenarios based on request
    payload = JSON.parse(req.body) rescue {}

    case payload['test_scenario']
    when 'success'
      res.status = 200
      res.body = JSON.generate({ success: true, received_at: Time.current.iso8601 })
    when 'server_error'
      res.status = 500
      res.body = 'Internal Server Error'
    when 'rate_limit'
      res.status = 429
      res['Retry-After'] = '60'
      res.body = 'Rate Limited'
    when 'unauthorized'
      res.status = 401
      res.body = 'Unauthorized'
    else
      res.status = 200
      res.body = JSON.generate({ received: true })
    end

    res['Content-Type'] = 'application/json'
  end

  def wait_for_server_to_start
    10.times do
      begin
        Net::HTTP.get_response(URI("http://localhost:#{@port}/"))
        break
      rescue Errno::ECONNREFUSED
        sleep 0.1
      end
    end
  end
end
```

### Using Test Server

```ruby
# spec/webhooks/real_endpoint_spec.rb
RSpec.describe 'Real Endpoint Testing' do
  let(:test_server) { WebhookTestServer.new }
  let(:webhook) { TestWebhook.new(payload) }
  let(:payload) { { id: 1, event: 'test', test_scenario: 'success' } }

  before do
    test_server.start
    allow(webhook).to receive(:endpoint_url).and_return(test_server.url)
  end

  after do
    test_server.stop
  end

  it 'successfully delivers webhook to real endpoint' do
    webhook.deliver_now

    expect(test_server.requests).to have(1).item

    request = test_server.last_request
    expect(request[:method]).to eq('POST')
    expect(request[:headers]['content-type']).to include('application/json')

    body = JSON.parse(request[:body])
    expect(body).to include('id' => 1, 'event' => 'test')
  end

  it 'handles server errors from real endpoint' do
    webhook.instance_variable_set(:@payload, payload.merge(test_scenario: 'server_error'))

    expect { webhook.deliver_now }.to raise_error(Net::HTTPServerError)
    expect(test_server.requests).to have(1).item
  end

  it 'handles rate limiting from real endpoint' do
    webhook.instance_variable_set(:@payload, payload.merge(test_scenario: 'rate_limit'))

    expect { webhook.deliver_now }.to raise_error(Net::HTTPTooManyRequests)

    request = test_server.last_request
    expect(request[:headers]['retry-after']).to eq(['60'])
  end
end
```

## Performance Testing

### Load Testing

```ruby
# spec/performance/webhook_load_spec.rb
RSpec.describe 'Webhook Performance' do
  include ActiveJob::TestHelper

  let(:webhook_class) { PerformanceWebhook }

  describe 'throughput testing' do
    it 'handles high volume of webhooks' do
      webhook_count = 1000

      start_time = Time.current

      perform_enqueued_jobs do
        webhook_count.times do |i|
          webhook_class.perform_later({ id: i, event: 'test' })
        end
      end

      end_time = Time.current
      duration = end_time - start_time

      throughput = webhook_count / duration
      expect(throughput).to be > 10 # At least 10 webhooks per second
    end
  end

  describe 'memory usage' do
    it 'does not leak memory during webhook processing' do
      initial_memory = get_memory_usage

      100.times do |i|
        webhook = webhook_class.new({ id: i, event: 'test' })
        webhook.deliver_now
      end

      GC.start # Force garbage collection
      final_memory = get_memory_usage

      memory_increase = final_memory - initial_memory
      expect(memory_increase).to be < 50.megabytes
    end
  end

  private

  def get_memory_usage
    # Simple memory usage measurement
    `ps -o rss= -p #{Process.pid}`.to_i * 1024 # Convert KB to bytes
  end
end
```

## Test Helpers and Utilities

### Custom Matchers

```ruby
# spec/support/webhook_matchers.rb
RSpec::Matchers.define :deliver_webhook_to do |url|
  match do |webhook|
    @webhook = webhook
    @expected_url = url

    # Mock HTTP request and check if it's called with correct URL
    expect(webhook).to receive(:post_webhook) do |actual_url, payload, headers|
      @actual_url = actual_url
      @actual_payload = payload
      @actual_headers = headers
      actual_url == url
    end.and_return(double(success?: true))

    webhook.deliver_now
    true
  end

  failure_message do
    "expected webhook to deliver to #{@expected_url}, but delivered to #{@actual_url}"
  end

  chain :with_payload do |expected_payload|
    @expected_payload = expected_payload
  end

  chain :with_headers do |expected_headers|
    @expected_headers = expected_headers
  end
end

# Usage:
# expect(webhook).to deliver_webhook_to('https://example.com/webhook')
#   .with_payload(include(id: 1))
#   .with_headers(include('Content-Type' => 'application/json'))
```

### Test Factories

```ruby
# spec/factories/webhooks.rb
FactoryBot.define do
  factory :webhook_endpoint do
    url { "https://example.com/webhook" }
    secret { SecureRandom.hex(32) }
    active { true }

    trait :inactive do
      active { false }
    end

    trait :with_auth do
      headers { { 'Authorization' => 'Bearer token123' } }
    end
  end

  factory :webhook_delivery do
    webhook_endpoint
    payload { { id: 1, event: 'test', data: {} } }
    status { 'pending' }
    attempts { 0 }

    trait :successful do
      status { 'delivered' }
      delivered_at { Time.current }
    end

    trait :failed do
      status { 'failed' }
      error_message { 'Connection timeout' }
      attempts { 3 }
    end
  end
end
```

### Shared Examples

```ruby
# spec/support/webhook_shared_examples.rb
RSpec.shared_examples 'a webhook with retry logic' do
  it 'retries on transient failures' do
    allow(webhook).to receive(:post_webhook).and_raise(Net::TimeoutError)
    expect(webhook).to receive(:retry_job)

    webhook.perform
  end

  it 'does not retry permanent failures' do
    error = Net::HTTPBadRequest.new('400', '400', 'Bad Request')
    allow(webhook).to receive(:post_webhook).and_raise(error)
    expect(webhook).not_to receive(:retry_job)

    webhook.perform
  end

  it 'gives up after max retries' do
    allow(webhook).to receive(:executions).and_return(5)
    allow(webhook).to receive(:post_webhook).and_raise(Net::TimeoutError)
    expect(webhook).not_to receive(:retry_job)

    webhook.perform
  end
end

# Usage:
# RSpec.describe MyWebhook do
#   it_behaves_like 'a webhook with retry logic'
# end
```

## Best Practices

1. **Test all webhook components** - payload, headers, delivery logic
2. **Mock external requests** - Use WebMock or VCR for HTTP calls
3. **Test error scenarios** - Network errors, HTTP errors, payload issues
4. **Test queue integration** - Ensure jobs are queued and processed correctly
5. **Use real endpoints for integration tests** - Test with actual HTTP servers
6. **Test performance** - Ensure webhooks perform adequately under load
7. **Create reusable test helpers** - DRY up common testing patterns
8. **Test callback behavior** - Ensure callbacks execute in correct order
9. **Test configuration** - Verify webhook configuration is handled correctly
10. **Monitor test coverage** - Ensure all code paths are tested

## See Also

- [Basic Usage](basic-usage.md) - Core webhook concepts
- [Error Handling](error-handling.md) - Error handling strategies
- [Queue Management](queue-management.md) - Background job testing
- [Callbacks](callbacks.md) - Testing callback behavior
