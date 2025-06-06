module ActionWebhook
  # Base class for defining and delivering webhooks
  #
  # Subclass this and define webhook methods (e.g. `created`, `updated`) that
  # define instance variables and call deliver to send webhooks.
  #
  # Example:
  #
  #   class UserWebhook < ActionWebhook::Base
  #     def created(user)
  #       @user = user
  #       # Get webhook endpoints from your database or config
  #       endpoints = WebhookSubscription.where(event: 'user.created').map do |sub|
  #         { url: sub.url, headers: { 'Authorization' => "Bearer #{sub.token}" } }
  #       end
  #       deliver(endpoints)
  #     end
  #   end
  #
  # Then in your controller or model:
  #
  #   # Send immediately
  #   UserWebhook.created(user).deliver_now
  #
  #   # Send in background (uses default queue)
  #   UserWebhook.created(user).deliver_later
  #
  #   # Send in background with specific queue
  #   UserWebhook.created(user).deliver_later(queue: 'webhooks')
  #
  #   # Send in background with delay
  #   UserWebhook.created(user).deliver_later(wait: 5.minutes)
  #
  #   # Send in background with specific queue and delay
  #   UserWebhook.created(user).deliver_later(queue: 'webhooks', wait: 10.minutes)
  #
  # You can also configure the default queue at the class level:
  #
  #   class UserWebhook < ActionWebhook::Base
  #     self.deliver_later_queue_name = 'webhooks'
  #
  #     def created(user)
  #       @user = user
  #       endpoints = WebhookSubscription.where(event: 'user.created').map do |sub|
  #         { url: sub.url, headers: { 'Authorization' => "Bearer #{sub.token}" } }
  #       end
  #       deliver(endpoints)
  #     end
  #   end
  #
  class Base
    include GlobalID::Identification if defined?(GlobalID)
    include ActiveJob::SerializationAdapter::ObjectSerializer if defined?(ActiveJob::SerializationAdapter)

    # Delivery configuration
    class_attribute :delivery_job, instance_writer: false, default: -> { "ActionWebhook::DeliveryJob".constantize }
    class_attribute :deliver_later_queue_name, instance_writer: false
    class_attribute :default_headers, instance_writer: false, default: {}
    class_attribute :delivery_method, instance_writer: false, default: :deliver_now
    class_attribute :perform_deliveries, instance_writer: false, default: true

    # Retry configuration
    class_attribute :max_retries, instance_writer: false, default: 3
    class_attribute :retry_delay, instance_writer: false, default: 30.seconds
    class_attribute :retry_backoff, instance_writer: false, default: :exponential
    class_attribute :retry_jitter, instance_writer: false, default: 5.seconds

    # Callbacks
    class_attribute :after_deliver_callback, instance_writer: false
    class_attribute :after_retries_exhausted_callback, instance_writer: false

    attr_accessor :action_name, :webhook_details, :params, :attempts

    def initialize
      @_webhook_message = {}
      @_webhook_defaults = {}
      @attempts = 0
    end

    def deliver_now
      @attempts += 1
      response = process_webhook

      if response.all? { |r| r[:success] }
        invoke_callback(self.class.after_deliver_callback, response)
      elsif @attempts < self.class.max_retries
        retry_with_backoff
      else
        invoke_callback(self.class.after_retries_exhausted_callback, response)
      end

      response
    end

    def deliver_later(options = {})
      enqueue_delivery(:deliver_now, options)
    end

    def deliver(webhook_details, params = {})
      @action_name = caller_locations(1, 1)[0].label.to_sym
      @webhook_details = webhook_details
      @params = params

      DeliveryMessenger.new(self)
    end

    def build_payload(variables = {})
      assigns = extract_instance_variables
      assigns.merge!(variables)
      generate_json_from_template(@action_name, assigns)
    end

    def post_webhook(webhook_details, payload)
      responses = []

      webhook_details.each do |detail|
        detail[:headers] ||= {}
        headers = build_headers(detail[:headers])

        response = send_webhook_request(detail[:url], payload, headers)
        responses << build_response_hash(response, detail[:url])
        log_webhook_result(response, detail[:url])
      rescue StandardError => e
        responses << build_error_response_hash(e, detail[:url])
        log_webhook_error(e, detail[:url])
      end

      responses
    end

    def generate_json_from_template(input_event_name, assigns = {})
      event_name = extract_method_name(input_event_name.to_s)
      template_path = find_template_path(event_name)

      raise ArgumentError, "Template not found for #{event_name}" unless template_path

      render_json_template(template_path, assigns)
    rescue JSON::ParserError => e
      raise ArgumentError, "Invalid JSON in template #{event_name}: #{e.message}"
    end

    def extract_method_name(path)
      path.include?("#") ? path.split("#").last : path
    end

    def process_webhook
      payload = build_payload
      post_webhook(webhook_details, payload)
    end

    def serialize
      {
        "action_name" => @action_name.to_s,
        "webhook_details" => @webhook_details,
        "params" => @params,
        "attempts" => @attempts,
        "instance_variables" => collect_instance_variables,
        "webhook_class" => self.class.name
      }
    end

    def deserialize(data)
      @action_name = data["action_name"].to_sym
      @webhook_details = data["webhook_details"]
      @params = data["params"]
      @attempts = data["attempts"] || 0

      restore_instance_variables(data["instance_variables"])
    end

    class << self
      def method_missing(method_name, *args, &block)
        if public_instance_methods(false).include?(method_name)
          webhook = new
          webhook.send(method_name, *args, &block)
        else
          super
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        public_instance_methods(false).include?(method_name) || super
      end

      def deliveries
        @deliveries ||= []
      end

      def clear_deliveries
        @deliveries = []
      end

      def after_deliver(method_name = nil, &block)
        self.after_deliver_callback = block_given? ? block : method_name
      end

      def after_retries_exhausted(method_name = nil, &block)
        self.after_retries_exhausted_callback = block_given? ? block : method_name
      end
    end

    private

    EXCLUDED_INSTANCE_VARIABLES = %w[@action_name @webhook_details @params @attempts].freeze

    def invoke_callback(callback, response)
      return unless callback

      case callback
      when Symbol
        send(callback, response)
      when Proc
        callback.call(self, response)
      end
    end

    def extract_instance_variables
      assigns = {}
      instance_variables.each do |ivar|
        next if ivar.to_s.start_with?("@_")
        next if EXCLUDED_INSTANCE_VARIABLES.include?(ivar.to_s)

        assigns[ivar.to_s[1..].to_sym] = instance_variable_get(ivar)
      end
      assigns
    end

    def build_headers(detail_headers)
      headers = default_headers.merge(detail_headers)
      headers["Content-Type"] = "application/json" unless headers.key?("Content-Type")
      headers["X-Webhook-Attempt"] = @attempts.to_s if @attempts.positive?
      headers
    end

    def send_webhook_request(url, payload, headers)
      HTTParty.post(url, body: payload.to_json, headers: headers, timeout: 10)
    end

    def build_response_hash(response, url)
      {
        success: response.success?,
        status: response.code,
        body: response.body,
        url: url,
        attempt: @attempts
      }
    end

    def build_error_response_hash(error, url)
      {
        success: false,
        error: error.message,
        url: url,
        attempt: @attempts
      }
    end

    def log_webhook_result(response, url)
      if response.success?
        logger.info("Webhook delivered successfully: #{url} (Status: #{response.code}, Attempt: #{@attempts})")
      else
        logger.warn("Webhook delivery failed with HTTP error: #{url} (Status: #{response.code}, Attempt: #{@attempts})")
      end
    end

    def log_webhook_error(error, url)
      logger.error("Webhook delivery failed: #{error.message} for URL: #{url} (Attempt: #{@attempts})")
    end

    def find_template_path(event_name)
      webhook_class_name = self.class.name.underscore
      possible_paths = build_template_paths(webhook_class_name, event_name)
      possible_paths.find { |path| File.exist?(path) }
    end

    def build_template_paths(webhook_class_name, event_name)
      [
        File.join(Rails.root.to_s, "app/webhooks/#{webhook_class_name}/#{event_name}.json.erb"),
        engine_template_path(webhook_class_name, event_name),
        namespaced_engine_template_path(webhook_class_name, event_name)
      ].compact
    end

    def engine_template_path(webhook_class_name, event_name)
      return unless engine_root

      File.join(engine_root, "app/webhooks/#{webhook_class_name}/#{event_name}.json.erb")
    end

    def namespaced_engine_template_path(webhook_class_name, event_name)
      return unless engine_root && self.class.module_parent != Object

      parent_name = self.class.module_parent.name.underscore
      class_name = webhook_class_name.split("/").last
      File.join(engine_root, "app/webhooks/#{parent_name}/#{class_name}/#{event_name}.json.erb")
    end

    def render_json_template(template_path, assigns)
      template = ERB.new(File.read(template_path))
      json = template.result_with_hash(assigns)
      JSON.parse(json)
    end

    def collect_instance_variables
      result = {}
      instance_variables.each do |ivar|
        next if ivar.to_s.start_with?("@_")
        next if EXCLUDED_INSTANCE_VARIABLES.include?(ivar.to_s)

        result[ivar.to_s[1..]] = instance_variable_get(ivar)
      end
      result
    end

    def restore_instance_variables(variables)
      variables.each do |name, value|
        instance_variable_set("@#{name}", value)
      end
    end

    def retry_with_backoff
      delay = calculate_backoff_delay
      logger.info("Scheduling webhook retry #{@attempts + 1}/#{self.class.max_retries} in #{delay} seconds")

      job_class = resolve_job_class
      serialized_webhook = serialize

      enqueue_retry_job(job_class, serialized_webhook, delay)
    end

    def calculate_backoff_delay
      base_delay = self.class.retry_delay
      multiplier = case self.class.retry_backoff
                   when :exponential
                     2**(@attempts - 1)
                   when :linear
                     @attempts
                   else
                     1
                   end

      base_delay * multiplier + rand(self.class.retry_jitter)
    end

    def resolve_job_class
      self.class.delivery_job.is_a?(Proc) ? self.class.delivery_job.call : self.class.delivery_job
    end

    def enqueue_retry_job(job_class, serialized_webhook, delay)
      if deliver_later_queue_name
        job_class.set(queue: deliver_later_queue_name, wait: delay).perform_later("deliver_now", serialized_webhook)
      else
        job_class.set(wait: delay).perform_later("deliver_now", serialized_webhook)
      end
    end

    def engine_root
      return nil unless defined?(Rails::Engine)

      find_engine_root_for_module(self.class.module_parent)
    end

    def find_engine_root_for_module(mod)
      while mod != Object
        engine_constant = find_engine_constant(mod)
        return mod.const_get(engine_constant).root.to_s if engine_constant

        mod = mod.module_parent
      end

      nil
    end

    def find_engine_constant(mod)
      mod.constants.find do |c|
        const = mod.const_get(c)
        const.is_a?(Class) && const < Rails::Engine
      end
    end

    def enqueue_delivery(delivery_method, options = {})
      options = options.dup
      queue = options.delete(:queue) || self.class.deliver_later_queue_name
      job_class = resolve_job_class
      serialized_webhook = serialize

      enqueue_job(job_class, delivery_method.to_s, serialized_webhook, queue, options)
    end

    def enqueue_job(job_class, delivery_method, serialized_webhook, queue, options)
      if queue
        job_class.set(queue: queue).perform_later(delivery_method, serialized_webhook)
      elsif options[:wait]
        job_class.set(wait: options[:wait]).perform_later(delivery_method, serialized_webhook)
      else
        job_class.perform_later(delivery_method, serialized_webhook)
      end
    end

    def logger
      Rails.logger
    end
  end

  class DeliveryMessenger
    def initialize(webhook)
      @webhook = webhook
    end

    def deliver_now
      return nil if skip_delivery?
      return test_delivery if test_mode?

      @webhook.deliver_now
    end

    def deliver_later(options = {})
      @webhook.deliver_later(options)
    end

    private

    def skip_delivery?
      @webhook.respond_to?(:perform_deliveries) && !@webhook.perform_deliveries
    end

    def test_mode?
      @webhook.class.delivery_method == :test
    end

    def test_delivery
      ActionWebhook::Base.deliveries << @webhook
    end
  end
end
