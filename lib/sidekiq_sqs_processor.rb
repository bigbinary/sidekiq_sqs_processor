require 'sidekiq'
require 'aws-sdk-sqs'
require 'json'
require 'benchmark'
require 'logger'
require 'securerandom'

require_relative 'sidekiq_sqs_processor/version'
require_relative 'sidekiq_sqs_processor/configuration'
require_relative 'sidekiq_sqs_processor/base_worker'
require_relative 'sidekiq_sqs_processor/continuous_poller'
require_relative 'sidekiq_sqs_processor/continuous_poller'
require_relative 'sidekiq_sqs_processor/railtie' if defined?(Rails)

# Main module for the SidekiqSqsProcessor gem
# Provides configuration and management interfaces for SQS message processing with Sidekiq
module SidekiqSqsProcessor
  class << self
    attr_writer :configuration
    
    # Get the current configuration
    # @return [SidekiqSqsProcessor::Configuration]
    def configuration
      @configuration ||= Configuration.new
    end
    
    # Configure the gem
    # @yield [config] Gives the configuration object to the block
    # @example
    #   SidekiqSqsProcessor.configure do |config|
    #     config.aws_region = 'us-east-1'
    #     config.queue_urls = ['https://sqs.us-east-1.amazonaws.com/123456789012/my-queue']
    #   end
    def configure
      yield(configuration)
    end
    
    # Start the continuous poller
    # @return [Boolean] Whether the poller was started
    def start_continuous_poller
      ContinuousPoller.instance.start
    end
    
    # Stop the continuous poller
    # @return [Boolean] Whether the poller was stopped
    def stop_continuous_poller
      ContinuousPoller.instance.stop
    end
    
    # Check if the continuous poller is running
    # @return [Boolean] Whether the poller is running
    def continuous_poller_running?
      ContinuousPoller.instance.running?
    end
    
    # Get statistics about the continuous poller
    # @return [Hash] Statistics about the poller threads
    def continuous_poller_stats
      ContinuousPoller.instance.stats
    end
    
    # Get the AWS SQS client
    # @return [Aws::SQS::Client]
    def sqs_client
      @sqs_client ||= create_sqs_client
    end
    
    # Explicitly set the SQS client (primarily for testing)
    # @param client [Aws::SQS::Client] The SQS client to use
    def sqs_client=(client)
      @sqs_client = client
    end
    
    # Create a new SQS client based on configuration
    # @return [Aws::SQS::Client] The AWS SQS client
    def create_sqs_client
      options = { region: configuration.aws_region }
      
      # Use custom credentials if provided
      if configuration.aws_credentials
        options[:credentials] = configuration.aws_credentials
      elsif configuration.aws_access_key_id && configuration.aws_secret_access_key
        options[:access_key_id] = configuration.aws_access_key_id
        options[:secret_access_key] = configuration.aws_secret_access_key
      end
      
      Aws::SQS::Client.new(options)
    end
    
    # Get the logger
    # @return [Logger] The logger
    def logger
      configuration.logger || Sidekiq.logger
    end
    
    # Reset the configuration and clients
    # Used primarily for testing
    def reset!
      @configuration = nil
      @sqs_client = nil
    end
    
    # Validate the current configuration
    # @return [Boolean] Whether the configuration is valid
    # @raise [ArgumentError] If the configuration is invalid
    def validate_configuration!
      configuration.validate!
    end
    
    # Find all worker classes that inherit from SidekiqSqsProcessor::BaseWorker
    # @return [Array<Class>] Array of worker classes
    def worker_classes
      ObjectSpace.each_object(Class).select { |c| c < BaseWorker rescue false }
    end
    
    # Get a worker class by name
    # @param name [String] The worker class name
    # @return [Class, nil] The worker class or nil if not found
    def find_worker_class(name)
      Object.const_get(name) rescue nil
    end
    
    # Enqueue a message directly to a specific worker
    # @param worker_class [Class, String] The worker class or name
    # @param message_body [Hash, String] The message body
    # @param options [Hash] Additional options for the message
    # @return [String] The Sidekiq job ID
    def enqueue_message(worker_class, message_body, options = {})
      # If worker_class is a string, convert to actual class
      worker_class = Object.const_get(worker_class) if worker_class.is_a?(String)
      
      # Ensure the worker is a SidekiqSqsProcessor::BaseWorker
      unless worker_class < BaseWorker
        raise ArgumentError, "Worker class must inherit from SidekiqSqsProcessor::BaseWorker"
      end
      
      # Create a simulated SQS message
      message_data = {
        'message_id' => SecureRandom.uuid,
        'body' => message_body.is_a?(String) ? message_body : JSON.generate(message_body),
        'attributes' => {},
        'message_attributes' => options[:message_attributes] || {},
        'enqueued_at' => Time.now.to_f
      }
      
      # Special handling for receipt_handle and queue_url if used for testing
      message_data['receipt_handle'] = options[:receipt_handle] if options[:receipt_handle]
      message_data['queue_url'] = options[:queue_url] if options[:queue_url]
      
      # Enqueue to Sidekiq
      worker_class.perform_async(message_data)
    end
    
    # Handle an error using the configured error handler
    # @param error [Exception] The error to handle
    # @param context [Hash] Additional context for the error
    def handle_error(error, context = {})
      configuration.handle_error(error, context)
    end
  end
end
