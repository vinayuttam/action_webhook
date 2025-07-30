require 'test_helper'

class HeaderHandlingTest < ActiveSupport::TestCase
  class TestWebhook < ActionWebhook::Base
    def test_event
      deliver([{ url: 'http://example.com', headers: params[:headers] }])
    end
  end

  setup do
    @webhook = TestWebhook.new
  end

  test "build_headers handles hash format correctly" do
    headers = {
      'Authorization' => 'Bearer token123',
      'Content-Type' => 'application/xml',
      'X-Custom-Header' => 'custom-value'
    }

    result = @webhook.send(:build_headers, headers)

    assert_equal 'Bearer token123', result['Authorization']
    assert_equal 'application/xml', result['Content-Type']
    assert_equal 'custom-value', result['X-Custom-Header']
  end

  test "build_headers handles array format with string keys correctly" do
    headers = [
      { 'key' => 'Authorization', 'value' => 'Bearer token123' },
      { 'key' => 'Content-Type', 'value' => 'application/xml' },
      { 'key' => 'X-Custom-Header', 'value' => 'custom-value' }
    ]

    result = @webhook.send(:build_headers, headers)

    assert_equal 'Bearer token123', result['Authorization']
    assert_equal 'application/xml', result['Content-Type']
    assert_equal 'custom-value', result['X-Custom-Header']
  end

  test "build_headers handles array format with symbol keys correctly" do
    headers = [
      { key: 'Authorization', value: 'Bearer token123' },
      { key: 'Content-Type', value: 'application/xml' },
      { key: 'X-Custom-Header', value: 'custom-value' }
    ]

    result = @webhook.send(:build_headers, headers)

    assert_equal 'Bearer token123', result['Authorization']
    assert_equal 'application/xml', result['Content-Type']
    assert_equal 'custom-value', result['X-Custom-Header']
  end

  test "build_headers handles mixed key types in array format" do
    headers = [
      { 'key' => 'Authorization', 'value' => 'Bearer token123' },
      { key: 'Content-Type', value: 'application/xml' }
    ]

    result = @webhook.send(:build_headers, headers)

    assert_equal 'Bearer token123', result['Authorization']
    assert_equal 'application/xml', result['Content-Type']
  end

  test "build_headers handles nil headers gracefully" do
    result = @webhook.send(:build_headers, nil)

    assert result.is_a?(Hash)
    assert_equal 'application/json', result['Content-Type']
  end

  test "build_headers handles empty array gracefully" do
    result = @webhook.send(:build_headers, [])

    assert result.is_a?(Hash)
    assert_equal 'application/json', result['Content-Type']
  end

  test "build_headers handles empty hash gracefully" do
    result = @webhook.send(:build_headers, {})

    assert result.is_a?(Hash)
    assert_equal 'application/json', result['Content-Type']
  end

  test "build_headers skips malformed array items" do
    headers = [
      { 'key' => 'Authorization', 'value' => 'Bearer token123' },
      { 'invalid' => 'structure' },
      { 'key' => 'X-Custom-Header', 'value' => 'custom-value' },
      'not a hash',
      nil
    ]

    result = @webhook.send(:build_headers, headers)

    assert_equal 'Bearer token123', result['Authorization']
    assert_equal 'custom-value', result['X-Custom-Header']
    refute result.key?('invalid')
  end

  test "build_headers handles nil values in array format" do
    headers = [
      { 'key' => 'Authorization', 'value' => 'Bearer token123' },
      { 'key' => nil, 'value' => 'should be skipped' },
      { 'key' => 'Content-Type', 'value' => nil },
      { 'key' => 'X-Custom-Header', 'value' => 'custom-value' }
    ]

    result = @webhook.send(:build_headers, headers)

    assert_equal 'Bearer token123', result['Authorization']
    assert_equal 'custom-value', result['X-Custom-Header']
    refute result.key?(nil)
    refute result.key?('Content-Type') # Should be overridden by default
  end

  test "build_headers converts symbol keys to strings in hash format" do
    headers = {
      :Authorization => 'Bearer token123',
      :'Content-Type' => 'application/xml'
    }

    result = @webhook.send(:build_headers, headers)

    assert_equal 'Bearer token123', result['Authorization']
    assert_equal 'application/xml', result['Content-Type']
  end

  test "build_headers converts non-string values to strings" do
    headers = [
      { 'key' => 'X-Number-Header', 'value' => 123 },
      { 'key' => 'X-Boolean-Header', 'value' => true }
    ]

    result = @webhook.send(:build_headers, headers)

    assert_equal '123', result['X-Number-Header']
    assert_equal 'true', result['X-Boolean-Header']
  end

  test "build_headers preserves default Content-Type when not specified" do
    headers = { 'Authorization' => 'Bearer token123' }

    result = @webhook.send(:build_headers, headers)

    assert_equal 'application/json', result['Content-Type']
    assert_equal 'Bearer token123', result['Authorization']
  end

  test "build_headers preserves custom Content-Type when specified" do
    headers = [
      { 'key' => 'Authorization', 'value' => 'Bearer token123' },
      { 'key' => 'Content-Type', 'value' => 'application/xml' }
    ]

    result = @webhook.send(:build_headers, headers)

    assert_equal 'application/xml', result['Content-Type']
    assert_equal 'Bearer token123', result['Authorization']
  end

  test "build_headers handles unknown format gracefully" do
    result = @webhook.send(:build_headers, "invalid format")

    assert result.is_a?(Hash)
    assert_equal 'application/json', result['Content-Type']
  end

  test "build_headers merges with default_headers" do
    TestWebhook.default_headers = { 'X-Default-Header' => 'default-value' }

    headers = { 'Authorization' => 'Bearer token123' }
    result = @webhook.send(:build_headers, headers)

    assert_equal 'default-value', result['X-Default-Header']
    assert_equal 'Bearer token123', result['Authorization']
    assert_equal 'application/json', result['Content-Type']
  ensure
    TestWebhook.default_headers = {}
  end

  test "build_headers allows override of default_headers" do
    TestWebhook.default_headers = { 'X-Default-Header' => 'default-value' }

    headers = { 'X-Default-Header' => 'overridden-value' }
    result = @webhook.send(:build_headers, headers)

    assert_equal 'overridden-value', result['X-Default-Header']
  ensure
    TestWebhook.default_headers = {}
  end

  test "build_headers adds webhook attempt header when attempts > 0" do
    @webhook.attempts = 3
    headers = { 'Authorization' => 'Bearer token123' }

    result = @webhook.send(:build_headers, headers)

    assert_equal '3', result['X-Webhook-Attempt']
    assert_equal 'Bearer token123', result['Authorization']
  end

  test "build_headers does not add webhook attempt header on first attempt" do
    @webhook.attempts = 0
    headers = { 'Authorization' => 'Bearer token123' }

    result = @webhook.send(:build_headers, headers)

    refute result.key?('X-Webhook-Attempt')
    assert_equal 'Bearer token123', result['Authorization']
  end
end
