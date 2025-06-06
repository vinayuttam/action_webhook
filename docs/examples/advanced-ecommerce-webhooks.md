# Advanced E-commerce Webhook Implementation

This example demonstrates a comprehensive webhook implementation for an e-commerce platform, showcasing advanced features like conditional delivery, multiple endpoint types, error handling, and monitoring integration.

## Webhook Class Structure

```ruby
# app/webhooks/ecommerce/order_webhook.rb
module Ecommerce
  class OrderWebhook < ActionWebhook::Base
    # Configuration
    configure do |config|
      config.timeout = 30.seconds
      config.retries = 5
      config.retry_delay = 10.seconds
      config.retry_backoff = :exponential
      config.queue = 'critical_webhooks'
    end

    # Callbacks for monitoring and error handling
    after_deliver :update_delivery_metrics
    after_retries_exhausted :handle_delivery_failure

    # Order lifecycle events
    def order_created(order, customer_data = {})
      @order = order
      @customer = order.customer
      @customer_data = customer_data
      @event_type = 'order.created'
      @timestamp = Time.current

      # Get endpoints based on order characteristics
      endpoints = build_endpoints_for_order_created
      deliver(endpoints)
    end

    def order_payment_confirmed(order, payment_details)
      @order = order
      @customer = order.customer
      @payment = payment_details
      @event_type = 'order.payment_confirmed'
      @timestamp = Time.current

      endpoints = build_endpoints_for_payment_confirmed
      deliver(endpoints)
    end

    def order_shipped(order, shipping_info)
      @order = order
      @customer = order.customer
      @shipping = shipping_info
      @tracking_number = shipping_info[:tracking_number]
      @carrier = shipping_info[:carrier]
      @event_type = 'order.shipped'
      @timestamp = Time.current

      endpoints = build_endpoints_for_shipped
      deliver(endpoints)
    end

    def order_delivered(order, delivery_confirmation)
      @order = order
      @customer = order.customer
      @delivery = delivery_confirmation
      @event_type = 'order.delivered'
      @timestamp = Time.current

      endpoints = build_endpoints_for_delivered
      deliver(endpoints)
    end

    def order_cancelled(order, cancellation_reason)
      @order = order
      @customer = order.customer
      @cancellation = cancellation_reason
      @event_type = 'order.cancelled'
      @timestamp = Time.current

      endpoints = build_endpoints_for_cancelled
      deliver(endpoints)
    end

    def order_refunded(order, refund_details)
      @order = order
      @customer = order.customer
      @refund = refund_details
      @event_type = 'order.refunded'
      @timestamp = Time.current

      endpoints = build_endpoints_for_refunded
      deliver(endpoints)
    end

    private

    # Endpoint builders with conditional logic
    def build_endpoints_for_order_created
      endpoints = []

      # Always notify internal systems
      endpoints.concat(internal_system_endpoints)

      # Notify customer-facing systems
      endpoints.concat(customer_notification_endpoints)

      # High-value orders get additional notifications
      if @order.total_amount > 1000
        endpoints.concat(high_value_order_endpoints)
      end

      # B2B customers have different integrations
      if @customer.business_customer?
        endpoints.concat(b2b_integration_endpoints)
      end

      # International orders need customs notifications
      if @order.international_shipping?
        endpoints.concat(customs_integration_endpoints)
      end

      endpoints
    end

    def build_endpoints_for_payment_confirmed
      endpoints = []

      # Financial systems
      endpoints.concat(accounting_system_endpoints)
      endpoints.concat(fraud_detection_endpoints)

      # Fulfillment systems
      endpoints.concat(warehouse_management_endpoints)

      # Customer communication
      endpoints.concat(email_service_endpoints)

      # Third-party integrations
      if @order.marketplace_order?
        endpoints.concat(marketplace_notification_endpoints)
      end

      endpoints
    end

    def build_endpoints_for_shipped
      endpoints = []

      # Customer notifications
      endpoints.concat(customer_notification_endpoints)
      endpoints.concat(sms_notification_endpoints) if @customer.sms_notifications_enabled?

      # Tracking integrations
      endpoints.concat(tracking_service_endpoints)

      # Analytics and reporting
      endpoints.concat(analytics_endpoints)

      endpoints
    end

    def build_endpoints_for_delivered
      endpoints = []

      # Customer success
      endpoints.concat(customer_success_endpoints)

      # Review request systems
      endpoints.concat(review_platform_endpoints)

      # Analytics
      endpoints.concat(analytics_endpoints)

      endpoints
    end

    def build_endpoints_for_cancelled
      endpoints = []

      # Inventory management
      endpoints.concat(inventory_adjustment_endpoints)

      # Financial systems
      endpoints.concat(accounting_system_endpoints)

      # Customer communication
      endpoints.concat(customer_notification_endpoints)

      endpoints
    end

    def build_endpoints_for_refunded
      endpoints = []

      # Financial systems
      endpoints.concat(accounting_system_endpoints)
      endpoints.concat(payment_processor_endpoints)

      # Customer communication
      endpoints.concat(customer_notification_endpoints)

      # Fraud prevention
      endpoints.concat(fraud_detection_endpoints)

      endpoints
    end

    # Endpoint definitions with proper authentication
    def internal_system_endpoints
      [
        {
          url: Rails.application.credentials.internal_api[:order_service_url],
          headers: {
            'Authorization' => "Bearer #{Rails.application.credentials.internal_api[:token]}",
            'X-Service-Name' => 'ecommerce-webhooks',
            'Content-Type' => 'application/json'
          }
        }
      ]
    end

    def customer_notification_endpoints
      [
        {
          url: Rails.application.credentials.notification_service[:webhook_url],
          headers: {
            'Authorization' => "Bearer #{Rails.application.credentials.notification_service[:token]}",
            'X-Customer-ID' => @customer.id.to_s,
            'X-Event-Type' => @event_type
          }
        }
      ]
    end

    def high_value_order_endpoints
      [
        {
          url: Rails.application.credentials.vip_service[:webhook_url],
          headers: {
            'Authorization' => "Bearer #{Rails.application.credentials.vip_service[:token]}",
            'X-Order-Value' => @order.total_amount.to_s,
            'X-Priority' => 'high'
          }
        }
      ]
    end

    def b2b_integration_endpoints
      return [] unless @customer.b2b_integration_enabled?

      [
        {
          url: @customer.b2b_webhook_url,
          headers: {
            'Authorization' => "Bearer #{@customer.b2b_api_token}",
            'X-Integration-Version' => '2.1',
            'X-Customer-ID' => @customer.external_id
          }
        }
      ]
    end

    def customs_integration_endpoints
      [
        {
          url: Rails.application.credentials.customs_service[:webhook_url],
          headers: {
            'Authorization' => "Bearer #{Rails.application.credentials.customs_service[:token]}",
            'X-Destination-Country' => @order.shipping_address.country_code,
            'X-Customs-Value' => @order.customs_value.to_s
          }
        }
      ]
    end

    def accounting_system_endpoints
      [
        {
          url: Rails.application.credentials.accounting_system[:webhook_url],
          headers: {
            'Authorization' => "Bearer #{Rails.application.credentials.accounting_system[:token]}",
            'X-Transaction-Type' => 'order_financial_event',
            'X-Fiscal-Year' => Date.current.year.to_s
          }
        }
      ]
    end

    def fraud_detection_endpoints
      [
        {
          url: Rails.application.credentials.fraud_detection[:webhook_url],
          headers: {
            'Authorization' => "Bearer #{Rails.application.credentials.fraud_detection[:token]}",
            'X-Risk-Level' => @order.fraud_risk_level,
            'X-Customer-Trust-Score' => @customer.trust_score.to_s
          }
        }
      ]
    end

    def warehouse_management_endpoints
      warehouses = @order.line_items.map(&:fulfillment_warehouse).uniq

      warehouses.map do |warehouse|
        {
          url: warehouse.webhook_url,
          headers: {
            'Authorization' => "Bearer #{warehouse.api_token}",
            'X-Warehouse-ID' => warehouse.id.to_s,
            'X-Priority' => @order.priority_level
          }
        }
      end
    end

    def email_service_endpoints
      [
        {
          url: Rails.application.credentials.email_service[:webhook_url],
          headers: {
            'Authorization' => "Bearer #{Rails.application.credentials.email_service[:token]}",
            'X-Template-Category' => 'transactional',
            'X-Customer-Segment' => @customer.segment
          }
        }
      ]
    end

    def marketplace_notification_endpoints
      return [] unless @order.marketplace_order?

      [
        {
          url: @order.marketplace.webhook_url,
          headers: {
            'Authorization' => "Bearer #{@order.marketplace.api_token}",
            'X-Marketplace-Order-ID' => @order.marketplace_order_id,
            'X-Seller-ID' => @order.seller_id
          }
        }
      ]
    end

    def sms_notification_endpoints
      [
        {
          url: Rails.application.credentials.sms_service[:webhook_url],
          headers: {
            'Authorization' => "Bearer #{Rails.application.credentials.sms_service[:token]}",
            'X-Phone-Number' => @customer.phone_number,
            'X-Message-Type' => 'order_update'
          }
        }
      ]
    end

    def tracking_service_endpoints
      [
        {
          url: Rails.application.credentials.tracking_service[:webhook_url],
          headers: {
            'Authorization' => "Bearer #{Rails.application.credentials.tracking_service[:token]}",
            'X-Tracking-Number' => @tracking_number,
            'X-Carrier' => @carrier
          }
        }
      ]
    end

    def analytics_endpoints
      [
        {
          url: Rails.application.credentials.analytics_service[:webhook_url],
          headers: {
            'Authorization' => "Bearer #{Rails.application.credentials.analytics_service[:token]}",
            'X-Event-Category' => 'order_lifecycle',
            'X-Customer-Cohort' => @customer.cohort
          }
        }
      ]
    end

    def customer_success_endpoints
      [
        {
          url: Rails.application.credentials.customer_success[:webhook_url],
          headers: {
            'Authorization' => "Bearer #{Rails.application.credentials.customer_success[:token]}",
            'X-Customer-Journey-Stage' => 'post_purchase',
            'X-Order-Experience-Score' => calculate_order_experience_score
          }
        }
      ]
    end

    def review_platform_endpoints
      return [] unless @customer.review_requests_enabled?

      [
        {
          url: Rails.application.credentials.review_platform[:webhook_url],
          headers: {
            'Authorization' => "Bearer #{Rails.application.credentials.review_platform[:token]}",
            'X-Product-Categories' => @order.product_categories.join(','),
            'X-Review-Delay' => '7d'
          }
        }
      ]
    end

    def inventory_adjustment_endpoints
      [
        {
          url: Rails.application.credentials.inventory_service[:webhook_url],
          headers: {
            'Authorization' => "Bearer #{Rails.application.credentials.inventory_service[:token]}",
            'X-Adjustment-Type' => 'order_cancellation',
            'X-Reason-Code' => @cancellation[:reason_code]
          }
        }
      ]
    end

    def payment_processor_endpoints
      [
        {
          url: Rails.application.credentials.payment_processor[:webhook_url],
          headers: {
            'Authorization' => "Bearer #{Rails.application.credentials.payment_processor[:token]}",
            'X-Transaction-ID' => @order.payment_transaction_id,
            'X-Refund-Type' => @refund[:type]
          }
        }
      ]
    end

    # Callback implementations
    def update_delivery_metrics(response)
      success_count = response.count { |r| r[:success] }
      total_count = response.size

      # Update order webhook delivery status
      @order.update!(
        last_webhook_delivered_at: Time.current,
        webhook_delivery_success_rate: (success_count.to_f / total_count * 100).round(2)
      )

      # Log to monitoring service
      Rails.logger.info "Order webhook delivered", {
        order_id: @order.id,
        event_type: @event_type,
        endpoints_count: total_count,
        success_count: success_count,
        success_rate: success_count.to_f / total_count
      }

      # Update metrics
      StatsD.increment('webhook.delivery.order.success', success_count)
      StatsD.increment('webhook.delivery.order.total', total_count)
      StatsD.gauge('webhook.delivery.order.success_rate', success_count.to_f / total_count)
    end

    def handle_delivery_failure(response)
      Rails.logger.error "Order webhook delivery failed permanently", {
        order_id: @order.id,
        customer_id: @customer.id,
        event_type: @event_type,
        response: response
      }

      # Create failure record for investigation
      WebhookDeliveryFailure.create!(
        webhook_class: self.class.name,
        action_name: @event_type,
        order_id: @order.id,
        customer_id: @customer.id,
        response_data: response,
        failed_at: Time.current
      )

      # Alert operations team for critical events
      if critical_event?
        AlertService.webhook_failure(
          message: "Critical order webhook failed: #{@event_type}",
          order_id: @order.id,
          customer_email: @customer.email,
          urgency: 'high'
        )
      end

      # Fallback to alternative notification methods
      case @event_type
      when 'order.payment_confirmed'
        # Critical - use direct API call
        PaymentConfirmationService.direct_notify(@order)
      when 'order.shipped'
        # Important - send email backup
        OrderMailer.shipped_notification(@order).deliver_now
      when 'order.delivered'
        # Medium priority - queue for retry later
        RetryWebhookJob.set(wait: 1.hour).perform_later(@order.id, @event_type)
      end
    end

    # Helper methods
    def critical_event?
      %w[order.payment_confirmed order.shipped order.refunded].include?(@event_type)
    end

    def calculate_order_experience_score
      score = 100

      # Deduct points for delays
      if @order.shipped_late?
        score -= 20
      end

      # Deduct points for customer service interactions
      score -= (@order.support_tickets.count * 10)

      # Add points for premium customers
      if @customer.premium?
        score += 10
      end

      [score, 0].max
    end
  end
end
```

## Template Examples

### Order Created Template

```erb
<%# app/views/ecommerce/order_webhook/order_created.json.erb %>
{
  "event": {
    "type": "<%= @event_type %>",
    "timestamp": "<%= @timestamp.iso8601 %>",
    "id": "<%= SecureRandom.uuid %>"
  },
  "order": {
    "id": "<%= @order.id %>",
    "number": "<%= @order.number %>",
    "status": "<%= @order.status %>",
    "total_amount": <%= @order.total_amount %>,
    "currency": "<%= @order.currency %>",
    "created_at": "<%= @order.created_at.iso8601 %>",
    "updated_at": "<%= @order.updated_at.iso8601 %>",
    "line_items": [
      <% @order.line_items.each_with_index do |item, index| %>
      {
        "id": "<%= item.id %>",
        "product_id": "<%= item.product_id %>",
        "variant_id": "<%= item.variant_id %>",
        "sku": "<%= item.sku %>",
        "title": "<%= item.title %>",
        "quantity": <%= item.quantity %>,
        "price": <%= item.price %>,
        "total": <%= item.total %>
      }<%= index < @order.line_items.size - 1 ? ',' : '' %>
      <% end %>
    ],
    "shipping_address": {
      "name": "<%= @order.shipping_address.name %>",
      "address1": "<%= @order.shipping_address.address1 %>",
      "address2": "<%= @order.shipping_address.address2 %>",
      "city": "<%= @order.shipping_address.city %>",
      "state": "<%= @order.shipping_address.state %>",
      "zip": "<%= @order.shipping_address.zip %>",
      "country": "<%= @order.shipping_address.country %>",
      "country_code": "<%= @order.shipping_address.country_code %>"
    },
    "billing_address": {
      "name": "<%= @order.billing_address.name %>",
      "address1": "<%= @order.billing_address.address1 %>",
      "address2": "<%= @order.billing_address.address2 %>",
      "city": "<%= @order.billing_address.city %>",
      "state": "<%= @order.billing_address.state %>",
      "zip": "<%= @order.billing_address.zip %>",
      "country": "<%= @order.billing_address.country %>",
      "country_code": "<%= @order.billing_address.country_code %>"
    }
  },
  "customer": {
    "id": "<%= @customer.id %>",
    "email": "<%= @customer.email %>",
    "first_name": "<%= @customer.first_name %>",
    "last_name": "<%= @customer.last_name %>",
    "phone": "<%= @customer.phone %>",
    "customer_type": "<%= @customer.customer_type %>",
    "segment": "<%= @customer.segment %>",
    "lifetime_value": <%= @customer.lifetime_value %>,
    "order_count": <%= @customer.orders.count %>
  },
  <% if @customer_data.any? %>
  "customer_data": <%= @customer_data.to_json %>,
  <% end %>
  "metadata": {
    "source": "ecommerce_platform",
    "version": "2.1",
    "environment": "<%= Rails.env %>",
    "webhook_id": "<%= SecureRandom.uuid %>"
  }
}
```

### Order Shipped Template

```erb
<%# app/views/ecommerce/order_webhook/order_shipped.json.erb %>
{
  "event": {
    "type": "<%= @event_type %>",
    "timestamp": "<%= @timestamp.iso8601 %>",
    "id": "<%= SecureRandom.uuid %>"
  },
  "order": {
    "id": "<%= @order.id %>",
    "number": "<%= @order.number %>",
    "status": "<%= @order.status %>",
    "shipped_at": "<%= @order.shipped_at.iso8601 %>"
  },
  "customer": {
    "id": "<%= @customer.id %>",
    "email": "<%= @customer.email %>",
    "first_name": "<%= @customer.first_name %>",
    "last_name": "<%= @customer.last_name %>"
  },
  "shipping": {
    "tracking_number": "<%= @tracking_number %>",
    "carrier": "<%= @carrier %>",
    "service": "<%= @shipping[:service] %>",
    "estimated_delivery": "<%= @shipping[:estimated_delivery]&.iso8601 %>",
    "tracking_url": "<%= @shipping[:tracking_url] %>",
    "weight": <%= @shipping[:weight] %>,
    "dimensions": {
      "length": <%= @shipping[:dimensions][:length] %>,
      "width": <%= @shipping[:dimensions][:width] %>,
      "height": <%= @shipping[:dimensions][:height] %>
    }
  },
  "metadata": {
    "source": "ecommerce_platform",
    "version": "2.1",
    "environment": "<%= Rails.env %>",
    "webhook_id": "<%= SecureRandom.uuid %>"
  }
}
```

## Usage Examples

### Basic Order Webhook

```ruby
# In your order controller or service
class OrdersController < ApplicationController
  def create
    @order = Order.new(order_params)

    if @order.save
      # Trigger webhook notification
      Ecommerce::OrderWebhook.order_created(@order).deliver_later

      render json: @order, status: :created
    else
      render json: @order.errors, status: :unprocessable_entity
    end
  end

  def update_shipping
    @order = Order.find(params[:id])

    if @order.update(shipping_params)
      # Trigger shipped webhook
      shipping_info = {
        tracking_number: @order.tracking_number,
        carrier: @order.carrier,
        service: @order.shipping_service,
        estimated_delivery: @order.estimated_delivery_date,
        tracking_url: @order.tracking_url,
        weight: @order.package_weight,
        dimensions: @order.package_dimensions
      }

      Ecommerce::OrderWebhook.order_shipped(@order, shipping_info).deliver_later

      render json: @order
    else
      render json: @order.errors, status: :unprocessable_entity
    end
  end
end
```

### Background Job Integration

```ruby
# app/jobs/order_webhook_job.rb
class OrderWebhookJob < ApplicationJob
  queue_as :webhooks

  def perform(order_id, event_type, additional_data = {})
    order = Order.find(order_id)
    webhook = Ecommerce::OrderWebhook.new

    case event_type
    when 'created'
      webhook.order_created(order, additional_data)
    when 'payment_confirmed'
      webhook.order_payment_confirmed(order, additional_data)
    when 'shipped'
      webhook.order_shipped(order, additional_data)
    when 'delivered'
      webhook.order_delivered(order, additional_data)
    when 'cancelled'
      webhook.order_cancelled(order, additional_data)
    when 'refunded'
      webhook.order_refunded(order, additional_data)
    else
      raise ArgumentError, "Unknown event type: #{event_type}"
    end

    webhook.deliver_now
  end
end
```

### Model Integration

```ruby
# app/models/order.rb
class Order < ApplicationRecord
  belongs_to :customer
  has_many :line_items

  after_create :trigger_created_webhook
  after_update :trigger_status_webhooks

  private

  def trigger_created_webhook
    OrderWebhookJob.perform_later(id, 'created')
  end

  def trigger_status_webhooks
    if saved_change_to_status?
      case status
      when 'payment_confirmed'
        payment_details = {
          payment_method: payment_method,
          transaction_id: payment_transaction_id,
          amount: total_amount
        }
        OrderWebhookJob.perform_later(id, 'payment_confirmed', payment_details)
      when 'shipped'
        shipping_info = build_shipping_info
        OrderWebhookJob.perform_later(id, 'shipped', shipping_info)
      when 'delivered'
        delivery_info = build_delivery_info
        OrderWebhookJob.perform_later(id, 'delivered', delivery_info)
      when 'cancelled'
        cancellation_info = build_cancellation_info
        OrderWebhookJob.perform_later(id, 'cancelled', cancellation_info)
      end
    end
  end
end
```

## Testing

```ruby
# spec/webhooks/ecommerce/order_webhook_spec.rb
RSpec.describe Ecommerce::OrderWebhook do
  let(:customer) { create(:customer, :premium) }
  let(:order) { create(:order, customer: customer, total_amount: 1500) }

  describe '#order_created' do
    it 'delivers to all appropriate endpoints' do
      # Stub external service calls
      stub_request(:post, /internal-api/).to_return(status: 200)
      stub_request(:post, /notification-service/).to_return(status: 200)
      stub_request(:post, /vip-service/).to_return(status: 200)  # High value order

      response = described_class.order_created(order).deliver_now

      expect(response).to all(include(success: true))
      expect(response.size).to eq(3)  # Internal + notification + VIP
    end

    it 'includes proper headers for authentication' do
      described_class.order_created(order).deliver_now

      expect(WebMock).to have_requested(:post, /internal-api/)
        .with(headers: { 'Authorization' => /Bearer/ })
    end
  end

  describe '#order_shipped' do
    let(:shipping_info) do
      {
        tracking_number: '1234567890',
        carrier: 'UPS',
        service: 'Ground',
        estimated_delivery: 3.days.from_now
      }
    end

    it 'sends tracking information to customer' do
      stub_request(:post, /notification-service/).to_return(status: 200)

      described_class.order_shipped(order, shipping_info).deliver_now

      expect(WebMock).to have_requested(:post, /notification-service/)
        .with(
          body: /1234567890/,
          headers: { 'X-Customer-ID' => order.customer.id.to_s }
        )
    end
  end
end
```

This comprehensive example demonstrates:

1. **Complex endpoint routing** based on order and customer characteristics
2. **Proper authentication** for different services
3. **Template organization** for different event types
4. **Error handling and fallback strategies**
5. **Monitoring and metrics integration**
6. **Background job integration**
7. **Model lifecycle integration**
8. **Comprehensive testing approach**

The implementation shows how ActionWebhook can be used in a real-world, production-ready e-commerce system with multiple integrations and complex business logic.
