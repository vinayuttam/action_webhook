# Multi-Tenant SaaS Webhook Integration

This example demonstrates how to implement webhooks in a multi-tenant SaaS application with tenant-specific configurations, isolation, and security considerations.

## Architecture Overview

In a multi-tenant SaaS application, webhooks need to:
- Maintain tenant data isolation
- Support tenant-specific configurations
- Handle different webhook endpoints per tenant
- Implement proper authentication and authorization
- Scale efficiently across tenants

## Base Webhook Class

```ruby
# app/webhooks/saas/base_webhook.rb
module Saas
  class BaseWebhook < ActionWebhook::Base
    include TenantScoped

    # Tenant-specific configuration
    configure do |config|
      config.timeout = 30.seconds
      config.retries = 3
      config.retry_delay = 15.seconds
      config.queue = 'tenant_webhooks'
    end

    # Global callbacks for all tenant webhooks
    after_deliver :track_tenant_webhook_usage
    after_retries_exhausted :handle_tenant_webhook_failure

    attr_accessor :tenant

    def initialize(tenant = nil)
      super()
      @tenant = tenant || Current.tenant
      validate_tenant_access!
    end

    protected

    # Get webhook endpoints specific to the tenant
    def tenant_webhook_endpoints(event_type)
      return [] unless @tenant

      @tenant.webhook_subscriptions
             .active
             .for_event_type(event_type)
             .map { |subscription| build_endpoint_from_subscription(subscription) }
    end

    # Build endpoint configuration from subscription
    def build_endpoint_from_subscription(subscription)
      {
        url: subscription.endpoint_url,
        headers: build_tenant_headers(subscription),
        subscription_id: subscription.id,
        tenant_id: @tenant.id
      }
    end

    # Build headers including tenant-specific authentication
    def build_tenant_headers(subscription)
      headers = {
        'Content-Type' => 'application/json',
        'X-Tenant-ID' => @tenant.id.to_s,
        'X-Webhook-Source' => 'saas-platform',
        'X-Webhook-Version' => '1.0',
        'X-Webhook-Timestamp' => Time.current.to_i.to_s
      }

      # Add authentication based on subscription type
      case subscription.auth_type
      when 'bearer_token'
        headers['Authorization'] = "Bearer #{subscription.auth_token}"
      when 'api_key'
        headers['X-API-Key'] = subscription.auth_token
      when 'basic_auth'
        encoded_auth = Base64.strict_encode64("#{subscription.auth_username}:#{subscription.auth_password}")
        headers['Authorization'] = "Basic #{encoded_auth}"
      when 'hmac_signature'
        # HMAC signature will be added in post_webhook method
        headers['X-Signature-Method'] = 'HMAC-SHA256'
      end

      # Add custom headers from subscription
      if subscription.custom_headers.present?
        headers.merge!(subscription.custom_headers)
      end

      headers
    end

    # Override post_webhook to add HMAC signatures for secure subscriptions
    def post_webhook(webhook_details, payload)
      webhook_details_with_signatures = webhook_details.map do |detail|
        if hmac_subscription?(detail[:subscription_id])
          detail = detail.dup
          subscription = WebhookSubscription.find(detail[:subscription_id])
          signature = generate_hmac_signature(payload, subscription.signing_secret)
          detail[:headers] = detail[:headers].merge('X-Signature' => signature)
        end
        detail
      end

      super(webhook_details_with_signatures, payload)
    end

    private

    def validate_tenant_access!
      raise ArgumentError, "Tenant is required for webhook delivery" unless @tenant
      raise SecurityError, "Access denied for tenant #{@tenant.id}" unless can_access_tenant?
    end

    def can_access_tenant?
      # Implement your tenant access control logic
      return true if Current.user&.system_admin?
      return true if Current.user&.tenant_id == @tenant.id
      return true if Current.api_key&.tenant_id == @tenant.id

      false
    end

    def hmac_subscription?(subscription_id)
      return false unless subscription_id

      WebhookSubscription.find(subscription_id).auth_type == 'hmac_signature'
    rescue ActiveRecord::RecordNotFound
      false
    end

    def generate_hmac_signature(payload, secret)
      "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, payload.to_json)}"
    end

    def track_tenant_webhook_usage(response)
      # Track webhook usage per tenant for billing/analytics
      TenantWebhookUsage.create!(
        tenant: @tenant,
        webhook_class: self.class.name,
        action_name: @action_name,
        endpoint_count: response.size,
        success_count: response.count { |r| r[:success] },
        delivered_at: Time.current
      )

      # Update tenant metrics
      @tenant.increment!(:webhook_deliveries_count)

      # Track usage for billing
      BillingService.track_webhook_usage(@tenant, response.size)
    end

    def handle_tenant_webhook_failure(response)
      Rails.logger.error "Tenant webhook delivery failed", {
        tenant_id: @tenant.id,
        webhook_class: self.class.name,
        action_name: @action_name,
        failed_endpoints: response.reject { |r| r[:success] }.size
      }

      # Notify tenant administrators
      TenantNotificationService.webhook_failure(
        tenant: @tenant,
        webhook_class: self.class.name,
        action_name: @action_name,
        failure_details: response
      )

      # Create support ticket for premium tenants
      if @tenant.premium?
        SupportTicketService.create_webhook_failure_ticket(@tenant, response)
      end
    end
  end
end
```

## User Event Webhooks

```ruby
# app/webhooks/saas/user_webhook.rb
module Saas
  class UserWebhook < BaseWebhook
    def user_created(user, tenant = nil)
      @user = user
      @tenant = tenant || user.tenant
      @event_type = 'user.created'
      @timestamp = Time.current

      endpoints = tenant_webhook_endpoints('user.created')
      return if endpoints.empty?

      deliver(endpoints)
    end

    def user_updated(user, changes, tenant = nil)
      @user = user
      @tenant = tenant || user.tenant
      @changes = changes
      @event_type = 'user.updated'
      @timestamp = Time.current

      # Only send webhook if significant fields changed
      significant_changes = %w[email role status subscription_plan]
      return unless (changes.keys & significant_changes).any?

      endpoints = tenant_webhook_endpoints('user.updated')
      return if endpoints.empty?

      deliver(endpoints)
    end

    def user_deleted(user, tenant = nil)
      @user = user
      @tenant = tenant || user.tenant
      @event_type = 'user.deleted'
      @timestamp = Time.current

      endpoints = tenant_webhook_endpoints('user.deleted')
      return if endpoints.empty?

      deliver(endpoints)
    end

    def user_subscription_changed(user, old_plan, new_plan, tenant = nil)
      @user = user
      @tenant = tenant || user.tenant
      @old_plan = old_plan
      @new_plan = new_plan
      @event_type = 'user.subscription_changed'
      @timestamp = Time.current

      endpoints = tenant_webhook_endpoints('user.subscription_changed')
      return if endpoints.empty?

      deliver(endpoints)
    end
  end
end
```

## Billing Event Webhooks

```ruby
# app/webhooks/saas/billing_webhook.rb
module Saas
  class BillingWebhook < BaseWebhook
    def invoice_created(invoice, tenant = nil)
      @invoice = invoice
      @tenant = tenant || invoice.tenant
      @event_type = 'invoice.created'
      @timestamp = Time.current

      endpoints = tenant_webhook_endpoints('invoice.created')
      return if endpoints.empty?

      deliver(endpoints)
    end

    def invoice_paid(invoice, payment, tenant = nil)
      @invoice = invoice
      @payment = payment
      @tenant = tenant || invoice.tenant
      @event_type = 'invoice.paid'
      @timestamp = Time.current

      endpoints = tenant_webhook_endpoints('invoice.paid')
      return if endpoints.empty?

      deliver(endpoints)
    end

    def payment_failed(invoice, payment_attempt, tenant = nil)
      @invoice = invoice
      @payment_attempt = payment_attempt
      @tenant = tenant || invoice.tenant
      @event_type = 'payment.failed'
      @timestamp = Time.current

      endpoints = tenant_webhook_endpoints('payment.failed')
      return if endpoints.empty?

      deliver(endpoints)
    end

    def subscription_created(subscription, tenant = nil)
      @subscription = subscription
      @tenant = tenant || subscription.tenant
      @event_type = 'subscription.created'
      @timestamp = Time.current

      endpoints = tenant_webhook_endpoints('subscription.created')
      return if endpoints.empty?

      deliver(endpoints)
    end

    def subscription_cancelled(subscription, cancellation_reason, tenant = nil)
      @subscription = subscription
      @cancellation_reason = cancellation_reason
      @tenant = tenant || subscription.tenant
      @event_type = 'subscription.cancelled'
      @timestamp = Time.current

      endpoints = tenant_webhook_endpoints('subscription.cancelled')
      return if endpoints.empty?

      deliver(endpoints)
    end
  end
end
```

## Models and Database Schema

### Webhook Subscription Model

```ruby
# app/models/webhook_subscription.rb
class WebhookSubscription < ApplicationRecord
  belongs_to :tenant
  belongs_to :created_by, class_name: 'User'

  validates :endpoint_url, presence: true, format: URI.regexp(%w[http https])
  validates :event_types, presence: true
  validates :auth_type, inclusion: { in: %w[none bearer_token api_key basic_auth hmac_signature] }

  enum status: { active: 0, inactive: 1, failed: 2 }

  scope :for_event_type, ->(event_type) { where('event_types @> ?', [event_type].to_json) }

  before_save :encrypt_sensitive_fields
  after_initialize :decrypt_sensitive_fields

  def self.available_event_types
    %w[
      user.created user.updated user.deleted user.subscription_changed
      invoice.created invoice.paid payment.failed
      subscription.created subscription.cancelled subscription.updated
      project.created project.updated project.deleted
      team.created team.updated team.deleted team.member_added team.member_removed
    ]
  end

  private

  def encrypt_sensitive_fields
    if auth_token_changed? && auth_token.present?
      self.encrypted_auth_token = encrypt(auth_token)
      self.auth_token = nil
    end

    if auth_password_changed? && auth_password.present?
      self.encrypted_auth_password = encrypt(auth_password)
      self.auth_password = nil
    end

    if signing_secret_changed? && signing_secret.present?
      self.encrypted_signing_secret = encrypt(signing_secret)
      self.signing_secret = nil
    end
  end

  def decrypt_sensitive_fields
    self.auth_token = decrypt(encrypted_auth_token) if encrypted_auth_token.present?
    self.auth_password = decrypt(encrypted_auth_password) if encrypted_auth_password.present?
    self.signing_secret = decrypt(encrypted_signing_secret) if encrypted_signing_secret.present?
  end

  def encrypt(value)
    # Use Rails encrypted attributes or your encryption service
    Rails.application.message_encryptor.encrypt_and_sign(value)
  end

  def decrypt(encrypted_value)
    Rails.application.message_encryptor.decrypt_and_verify(encrypted_value)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end
end
```

### Database Migration

```ruby
# db/migrate/xxx_create_webhook_subscriptions.rb
class CreateWebhookSubscriptions < ActiveRecord::Migration[7.0]
  def change
    create_table :webhook_subscriptions do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }

      t.string :endpoint_url, null: false
      t.json :event_types, null: false, default: []
      t.string :auth_type, null: false, default: 'none'

      # Encrypted authentication fields
      t.text :encrypted_auth_token
      t.string :auth_username
      t.text :encrypted_auth_password
      t.text :encrypted_signing_secret

      # Custom headers and metadata
      t.json :custom_headers, default: {}
      t.json :metadata, default: {}

      # Status and monitoring
      t.integer :status, default: 0
      t.datetime :last_delivery_at
      t.datetime :last_success_at
      t.datetime :last_failure_at
      t.integer :failure_count, default: 0
      t.integer :total_deliveries, default: 0
      t.integer :successful_deliveries, default: 0

      t.timestamps
    end

    add_index :webhook_subscriptions, [:tenant_id, :status]
    add_index :webhook_subscriptions, :event_types, using: :gin
  end
end

# db/migrate/xxx_create_tenant_webhook_usages.rb
class CreateTenantWebhookUsages < ActiveRecord::Migration[7.0]
  def change
    create_table :tenant_webhook_usages do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :webhook_class, null: false
      t.string :action_name, null: false
      t.integer :endpoint_count, null: false, default: 0
      t.integer :success_count, null: false, default: 0
      t.datetime :delivered_at, null: false

      t.timestamps
    end

    add_index :tenant_webhook_usages, [:tenant_id, :delivered_at]
    add_index :tenant_webhook_usages, :webhook_class
  end
end
```

## Tenant Configuration

```ruby
# app/models/tenant.rb
class Tenant < ApplicationRecord
  has_many :webhook_subscriptions, dependent: :destroy
  has_many :tenant_webhook_usages, dependent: :destroy
  has_many :users, dependent: :destroy

  # Webhook configuration per tenant
  def webhook_rate_limit
    case plan_type
    when 'basic'
      100 # webhooks per hour
    when 'professional'
      1000
    when 'enterprise'
      10000
    else
      50
    end
  end

  def webhook_features_enabled?
    %w[professional enterprise].include?(plan_type)
  end

  def can_create_webhook_subscription?
    return false unless webhook_features_enabled?
    return true if enterprise?

    webhook_subscriptions.active.count < webhook_subscription_limit
  end

  def webhook_subscription_limit
    case plan_type
    when 'professional'
      5
    when 'enterprise'
      50
    else
      1
    end
  end

  # Check if tenant has exceeded webhook rate limit
  def webhook_rate_limit_exceeded?
    recent_usage = tenant_webhook_usages
                    .where(delivered_at: 1.hour.ago..Time.current)
                    .sum(:endpoint_count)

    recent_usage >= webhook_rate_limit
  end
end
```

## Authentication and Authorization

```ruby
# app/controllers/api/v1/webhook_subscriptions_controller.rb
module Api
  module V1
    class WebhookSubscriptionsController < ApplicationController
      before_action :authenticate_tenant!
      before_action :check_webhook_features!
      before_action :find_subscription, only: [:show, :update, :destroy, :test]

      def index
        @subscriptions = current_tenant.webhook_subscriptions
                                      .includes(:created_by)
                                      .order(created_at: :desc)

        render json: @subscriptions, each_serializer: WebhookSubscriptionSerializer
      end

      def create
        unless current_tenant.can_create_webhook_subscription?
          return render json: {
            error: 'Webhook subscription limit reached'
          }, status: :forbidden
        end

        @subscription = current_tenant.webhook_subscriptions.build(subscription_params)
        @subscription.created_by = current_user

        if @subscription.save
          render json: @subscription, serializer: WebhookSubscriptionSerializer, status: :created
        else
          render json: { errors: @subscription.errors }, status: :unprocessable_entity
        end
      end

      def update
        if @subscription.update(subscription_params)
          render json: @subscription, serializer: WebhookSubscriptionSerializer
        else
          render json: { errors: @subscription.errors }, status: :unprocessable_entity
        end
      end

      def destroy
        @subscription.destroy
        head :no_content
      end

      def test
        # Send a test webhook
        test_payload = {
          event: {
            type: 'test.webhook',
            timestamp: Time.current.iso8601,
            id: SecureRandom.uuid
          },
          tenant: {
            id: current_tenant.id,
            name: current_tenant.name
          },
          test_data: {
            message: 'This is a test webhook delivery',
            timestamp: Time.current.iso8601
          }
        }

        response = deliver_test_webhook(@subscription, test_payload)

        if response[:success]
          render json: { message: 'Test webhook delivered successfully', response: response }
        else
          render json: { error: 'Test webhook delivery failed', response: response }, status: :bad_request
        end
      end

      private

      def authenticate_tenant!
        # Implement your tenant authentication logic
        current_tenant_id = request.headers['X-Tenant-ID'] ||
                           current_user&.tenant_id ||
                           current_api_key&.tenant_id

        @current_tenant = Tenant.find(current_tenant_id) if current_tenant_id

        render json: { error: 'Tenant authentication required' }, status: :unauthorized unless @current_tenant
      end

      def check_webhook_features!
        unless current_tenant.webhook_features_enabled?
          render json: {
            error: 'Webhook features not available for your plan'
          }, status: :forbidden
        end
      end

      def find_subscription
        @subscription = current_tenant.webhook_subscriptions.find(params[:id])
      end

      def subscription_params
        params.require(:webhook_subscription).permit(
          :endpoint_url,
          :auth_type,
          :auth_token,
          :auth_username,
          :auth_password,
          :signing_secret,
          event_types: [],
          custom_headers: {},
          metadata: {}
        )
      end

      def deliver_test_webhook(subscription, payload)
        webhook_detail = {
          url: subscription.endpoint_url,
          headers: build_test_headers(subscription),
          subscription_id: subscription.id,
          tenant_id: current_tenant.id
        }

        # Create a test webhook instance
        webhook = Saas::BaseWebhook.new(current_tenant)
        webhook.instance_variable_set(:@action_name, 'test')

        response = webhook.post_webhook([webhook_detail], payload)
        response.first
      end

      def build_test_headers(subscription)
        headers = {
          'Content-Type' => 'application/json',
          'X-Tenant-ID' => current_tenant.id.to_s,
          'X-Webhook-Source' => 'saas-platform',
          'X-Webhook-Version' => '1.0',
          'X-Webhook-Test' => 'true'
        }

        case subscription.auth_type
        when 'bearer_token'
          headers['Authorization'] = "Bearer #{subscription.auth_token}"
        when 'api_key'
          headers['X-API-Key'] = subscription.auth_token
        when 'basic_auth'
          encoded_auth = Base64.strict_encode64("#{subscription.auth_username}:#{subscription.auth_password}")
          headers['Authorization'] = "Basic #{encoded_auth}"
        end

        headers.merge!(subscription.custom_headers) if subscription.custom_headers.present?
        headers
      end

      attr_reader :current_tenant
    end
  end
end
```

## Template Examples

### User Created Template

```erb
<%# app/views/saas/user_webhook/user_created.json.erb %>
{
  "event": {
    "type": "<%= @event_type %>",
    "timestamp": "<%= @timestamp.iso8601 %>",
    "id": "<%= SecureRandom.uuid %>",
    "tenant_id": "<%= @tenant.id %>"
  },
  "user": {
    "id": "<%= @user.id %>",
    "email": "<%= @user.email %>",
    "first_name": "<%= @user.first_name %>",
    "last_name": "<%= @user.last_name %>",
    "role": "<%= @user.role %>",
    "status": "<%= @user.status %>",
    "created_at": "<%= @user.created_at.iso8601 %>",
    "last_sign_in_at": "<%= @user.last_sign_in_at&.iso8601 %>",
    "email_verified": <%= @user.email_verified? %>,
    "phone": "<%= @user.phone %>",
    "timezone": "<%= @user.timezone %>",
    "locale": "<%= @user.locale %>"
  },
  "tenant": {
    "id": "<%= @tenant.id %>",
    "name": "<%= @tenant.name %>",
    "plan": "<%= @tenant.plan_type %>",
    "domain": "<%= @tenant.domain %>"
  },
  "metadata": {
    "webhook_version": "1.0",
    "source": "saas-platform",
    "environment": "<%= Rails.env %>"
  }
}
```

### Invoice Paid Template

```erb
<%# app/views/saas/billing_webhook/invoice_paid.json.erb %>
{
  "event": {
    "type": "<%= @event_type %>",
    "timestamp": "<%= @timestamp.iso8601 %>",
    "id": "<%= SecureRandom.uuid %>",
    "tenant_id": "<%= @tenant.id %>"
  },
  "invoice": {
    "id": "<%= @invoice.id %>",
    "number": "<%= @invoice.number %>",
    "amount_due": <%= @invoice.amount_due %>,
    "amount_paid": <%= @invoice.amount_paid %>,
    "currency": "<%= @invoice.currency %>",
    "status": "<%= @invoice.status %>",
    "due_date": "<%= @invoice.due_date.iso8601 %>",
    "paid_at": "<%= @invoice.paid_at&.iso8601 %>",
    "period_start": "<%= @invoice.period_start.iso8601 %>",
    "period_end": "<%= @invoice.period_end.iso8601 %>",
    "line_items": [
      <% @invoice.line_items.each_with_index do |item, index| %>
      {
        "id": "<%= item.id %>",
        "description": "<%= item.description %>",
        "amount": <%= item.amount %>,
        "quantity": <%= item.quantity %>,
        "unit_price": <%= item.unit_price %>
      }<%= index < @invoice.line_items.size - 1 ? ',' : '' %>
      <% end %>
    ]
  },
  "payment": {
    "id": "<%= @payment.id %>",
    "amount": <%= @payment.amount %>,
    "currency": "<%= @payment.currency %>",
    "method": "<%= @payment.payment_method %>",
    "status": "<%= @payment.status %>",
    "processed_at": "<%= @payment.processed_at.iso8601 %>",
    "reference": "<%= @payment.reference %>"
  },
  "tenant": {
    "id": "<%= @tenant.id %>",
    "name": "<%= @tenant.name %>",
    "plan": "<%= @tenant.plan_type %>"
  },
  "metadata": {
    "webhook_version": "1.0",
    "source": "saas-platform",
    "environment": "<%= Rails.env %>"
  }
}
```

## Usage in Application

### Service Integration

```ruby
# app/services/user_service.rb
class UserService
  def self.create_user(params, tenant)
    user = tenant.users.build(params)

    if user.save
      # Trigger webhook asynchronously
      Saas::UserWebhook.user_created(user, tenant).deliver_later

      # Other post-creation logic
      UserOnboardingService.start_onboarding(user)
      AnalyticsService.track_user_created(user)

      user
    else
      user
    end
  end

  def self.update_user(user, params)
    changes = user.changes_to_save

    if user.update(params)
      # Only send webhook if significant changes occurred
      if significant_changes?(changes)
        Saas::UserWebhook.user_updated(user, changes).deliver_later
      end

      user
    else
      user
    end
  end

  private

  def self.significant_changes?(changes)
    significant_fields = %w[email role status subscription_plan_id]
    (changes.keys & significant_fields).any?
  end
end
```

### Background Job Processing

```ruby
# app/jobs/tenant_webhook_job.rb
class TenantWebhookJob < ApplicationJob
  queue_as :tenant_webhooks

  def perform(tenant_id, webhook_class, method_name, *args)
    tenant = Tenant.find(tenant_id)

    # Check rate limits
    if tenant.webhook_rate_limit_exceeded?
      Rails.logger.warn "Webhook rate limit exceeded for tenant #{tenant_id}"
      return
    end

    # Instantiate webhook with tenant context
    webhook_class_const = webhook_class.constantize
    webhook = webhook_class_const.new(tenant)

    # Call the webhook method
    webhook.send(method_name, *args)
    webhook.deliver_now

  rescue => e
    Rails.logger.error "Tenant webhook job failed: #{e.message}", {
      tenant_id: tenant_id,
      webhook_class: webhook_class,
      method_name: method_name,
      error: e.message
    }

    # Track the failure
    WebhookFailureTracker.track(tenant_id, webhook_class, method_name, e)

    raise
  end
end
```

This multi-tenant webhook implementation provides:

1. **Tenant Isolation**: Complete separation of webhook configurations and data
2. **Flexible Authentication**: Support for multiple authentication methods
3. **Rate Limiting**: Per-tenant rate limits based on subscription plans
4. **Security**: HMAC signatures and encrypted credential storage
5. **Monitoring**: Comprehensive tracking and failure handling
6. **Scalability**: Efficient queuing and processing across tenants
7. **API Management**: RESTful API for webhook subscription management

The architecture ensures that each tenant's webhook integrations are completely isolated while providing a consistent and secure webhook delivery system.
