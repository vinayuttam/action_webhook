# frozen_string_literal: true

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
  #   # Send in background
  #   UserWebhook.created(user).deliver_later
  #
  class Base
    # Add these lines near the top of your class
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
    class_attribute :retry_backoff, instance_writer: false, default: :exponential # :linear or :exponential
    class_attribute :retry_jitter, instance_writer: false, default: 5.seconds

    # Callbacks
    class_attribute :after_deliver_callback, instance_writer: false
    class_attribute :after_retries_exhausted_callback, instance_writer: false

    # The webhook action that will be performed
    attr_accessor :action_name

    # The webhook details (URLs and headers) that will be used
    attr_accessor :webhook_details

    # Stores the execution params for later delivery
    attr_accessor :params

    # Current attempt number for retries
    attr_accessor :attempts

    # Creates a new webhook and initializes its settings
    def initialize
      @_webhook_message = {}
      @_webhook_defaults = {}
      @attempts = 0
    end

    # Synchronously delivers the webhook
    def deliver_now
      @attempts += 1
      response = process_webhook

      # Call success callback if defined
      if response.all? { |r| r[:success] }
        invoke_callback(self.class.after_deliver_callback, response)
      elsif @attempts < self.class.max_retries
        # Schedule a retry with backoff
        retry_with_backoff
      else
        # We've exhausted all retries
        invoke_callback(self.class.after_retries_exhausted_callback, response)
      end

      response
    end

    # Helper method to invoke a callback that might be a symbol or a proc
    def invoke_callback(callback, response)
      return unless callback

      case callback
      when Symbol
        send(callback, response)
      when Proc
        callback.call(self, response)
      end
    end

    # Enqueues the webhook delivery via ActiveJob
    def deliver_later(options = {})
      enqueue_delivery(:deliver_now, options)
    end

    # Prepares the webhook for delivery using the current method as template name
    # and instance variables as template data
    #
    # @param webhook_details [Array<Hash>] Array of hashes with :url and :headers keys
    # @param params [Hash] Optional parameters to store for later delivery
    # @return [DeliveryMessenger] A messenger object for further delivery options
    def deliver(webhook_details, params = {})
      # Determine action name from the caller
      @action_name = caller_locations(1, 1)[0].label.to_sym
      @webhook_details = webhook_details
      @params = params

      # Return self for chaining with delivery methods
      DeliveryMessenger.new(self)
    end

    # Renders a template based on the action name
    #
    # @param variables [Hash] Optional variables to add to template context
    # @return [Hash] The JSON payload
    def build_payload(variables = {})
      # Combine instance variables and passed variables
      assigns = {}

      # Extract instance variables
      instance_variables.each do |ivar|
        # Skip internal instance variables
        next if ivar.to_s.start_with?("@_")
        next if %i[@action_name @webhook_details @params @attempts].include?(ivar)

        # Add to assigns with symbol key (without @)
        assigns[ivar.to_s[1..].to_sym] = instance_variable_get(ivar)
      end

      # Add passed variables
      assigns.merge!(variables)

      # Render the template
      generate_json_from_template(@action_name, assigns)
    end

    # Posts payload(s) to the given webhook endpoints
    #
    # @param webhook_details [Array<Hash>] An array of hashes containing `url` and `headers`
    # @param payloads [Array<Hash>] One payload for each webhook
    # @return [Array<Hash>] Array of response objects with status and body
    def post_webhook(webhook_details, payloads)
      responses = []

      webhook_details.each_with_index do |detail, idx|
        # Ensure headers exists
        detail[:headers] ||= {}

        # Merge default headers
        headers = default_headers.merge(detail[:headers])

        # Add content type if not present
        headers["Content-Type"] = "application/json" unless headers.key?("Content-Type")

        # Add attempt tracking in headers
        headers["X-Webhook-Attempt"] = @attempts.to_s if @attempts.positive?

        response = HTTParty.post(
          detail[:url],
          body: payloads[idx].to_json,
          headers: headers,
          timeout: 10 # Add reasonable timeout
        )

        responses << {
          success: response.success?,
          status: response.code,
          body: response.body,
          url: detail[:url],
          attempt: @attempts
        }
      rescue StandardError => e
        responses << {
          success: false,
          error: e.message,
          url: detail[:url],
          attempt: @attempts
        }
        logger.error("Webhook delivery failed: #{e.message} for URL: #{detail[:url]} (Attempt #{@attempts})")
      end

      responses
    end

    # Renders a JSON payload from a `.json.erb` template
    #
    # @param event_name [Symbol] the name of the webhook method (e.g. `:created`)
    # @param assigns [Hash] local variables to pass into the template
    # @return [Hash] the parsed JSON payload
    def generate_json_from_template(input_event_name, assigns = {})
      event_name = extract_method_name(input_event_name.to_s)
      webhook_class_name = self.class.name.underscore

      # Possible template locations
      possible_paths = [
        # Main app templates
        File.join(Rails.root.to_s, "app/webhooks/#{webhook_class_name}/#{event_name}.json.erb"),

        # Engine templates
        engine_root && File.join(engine_root, "app/webhooks/#{webhook_class_name}/#{event_name}.json.erb"),

        # Namespaced templates in engine
        engine_root && self.class.module_parent != Object &&
          File.join(engine_root,
                    "app/webhooks/#{self.class.module_parent.name.underscore}/#{webhook_class_name.split("/").last}/#{event_name}.json.erb")
      ].compact

      # Find the first template that exists
      template_path = possible_paths.find { |path| File.exist?(path) }

      unless template_path
        raise ArgumentError, "Template not found for #{event_name} in paths:\n#{possible_paths.join("\n")}"
      end

      template = ERB.new(File.read(template_path))
      json = template.result_with_hash(assigns)
      JSON.parse(json)
    rescue JSON::ParserError => e
      raise "Invalid JSON in template #{event_name}: #{e.message}"
    end

    def extract_method_name(path)
      path.include?("#") ? path.split("#").last : path
    end

    # Process the webhook to generate and send the payload
    def process_webhook
      # Render the message
      payloads = [build_payload]

      # Post the webhook
      post_webhook(webhook_details, payloads)
    end

    # Schedule a retry with appropriate backoff delay
    # Modify the retry_with_backoff method:
    def retry_with_backoff
      delay = calculate_backoff_delay

      logger.info("Scheduling webhook retry #{@attempts + 1}/#{self.class.max_retries} in #{delay} seconds")

      # Get the actual job class by evaluating the proc
      job_class = self.class.delivery_job.is_a?(Proc) ? self.class.delivery_job.call : self.class.delivery_job

      # Serialize the webhook and pass the serialized data instead of the object
      serialized_webhook = serialize

      # Re-enqueue with the calculated delay
      if deliver_later_queue_name
        job_class.set(queue: deliver_later_queue_name, wait: delay).perform_later("deliver_now", serialized_webhook)
      else
        job_class.set(wait: delay).perform_later("deliver_now", serialized_webhook)
      end
    end

    # Calculate delay based on retry strategy
    def calculate_backoff_delay
      base_delay = self.class.retry_delay

      delay = case self.class.retry_backoff
              when :exponential
                # 30s, 60s, 120s, etc.
                base_delay * (2**(@attempts - 1))
              when :linear
                # 30s, 60s, 90s, etc.
                base_delay * @attempts
              else
                base_delay
              end

      # Add jitter to prevent thundering herd problem
      jitter = rand(self.class.retry_jitter)
      delay + jitter
    end

    # For ActiveJob serialization
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

    # Restores state from serialized data
    def deserialize(data)
      @action_name = data["action_name"].to_sym
      @webhook_details = data["webhook_details"]
      @params = data["params"]
      @attempts = data["attempts"] || 0

      # Restore instance variables
      data["instance_variables"].each do |name, value|
        instance_variable_set("@#{name}", value)
      end
    end

    private

    # Collects all non-system instance variables for serialization
    def collect_instance_variables
      result = {}
      instance_variables.each do |ivar|
        # Skip internal instance variables
        next if ivar.to_s.start_with?("@_")
        next if %i[@action_name @webhook_details @params @attempts].include?(ivar)

        # Add to result without @
        result[ivar.to_s[1..]] = instance_variable_get(ivar)
      end
      result
    end

    # Find the engine root path
    def engine_root
      return nil unless defined?(Rails::Engine)

      mod = self.class.module_parent
      while mod != Object
        constants = mod.constants.select do |c|
          const = mod.const_get(c)
          const.is_a?(Class) && const < Rails::Engine
        end

        return mod.const_get(constants.first).root.to_s if constants.any?

        mod = mod.module_parent
      end

      nil
    end

    # Similarly update enqueue_delivery:
    def enqueue_delivery(delivery_method, options = {})
      options = options.dup
      queue = options.delete(:queue) || self.class.deliver_later_queue_name

      args = [delivery_method.to_s]

      # Get the actual job class by evaluating the proc
      job_class = self.class.delivery_job.is_a?(Proc) ? self.class.delivery_job.call : self.class.delivery_job

      # Serialize the webhook
      serialized_webhook = serialize

      # Use the delivery job to perform the delivery with serialized data
      if queue
        job_class.set(queue: queue).perform_later(*args, serialized_webhook)
      else
        job_class.set(wait: options[:wait]).perform_later(*args, serialized_webhook) if options[:wait]
        job_class.perform_later(*args, serialized_webhook) unless options[:wait]
      end
    end

    # Logger for webhook errors
    def logger
      Rails.logger
    end

    # Class methods
    class << self
      # Handle method calls on the class
      def method_missing(method_name, *args, &block)
        if public_instance_methods(false).include?(method_name)
          # Create a new instance
          webhook = new

          # Call the instance method
          webhook.send(method_name, *args, &block)
        else
          super
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        public_instance_methods(false).include?(method_name) || super
      end

      # Test delivery collection
      def deliveries
        @deliveries ||= []
      end

      # Reset the test delivery collection
      def clear_deliveries
        @deliveries = []
      end

      # Register callback for successful delivery
      def after_deliver(method_name = nil, &block)
        self.after_deliver_callback = block_given? ? block : method_name
      end

      # Register callback for when retries are exhausted
      def after_retries_exhausted(method_name = nil, &block)
        self.after_retries_exhausted_callback = block_given? ? block : method_name
      end
    end
  end

  # Delivery messenger for ActionMailer-like API
  class DeliveryMessenger
    def initialize(webhook)
      @webhook = webhook
    end

    def deliver_now
      if @webhook.respond_to?(:perform_deliveries) && !@webhook.perform_deliveries
        # Skip delivery
        nil
      elsif @webhook.class.delivery_method == :test
        # Test delivery
        ActionWebhook::Base.deliveries << @webhook
      else
        # Normal delivery
        @webhook.deliver_now
      end
    end

    def deliver_later(options = {})
      @webhook.deliver_later(options)
    end
  end
end
