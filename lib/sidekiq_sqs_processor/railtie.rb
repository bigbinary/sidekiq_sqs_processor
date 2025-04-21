require 'rails'
require 'sidekiq'

module SidekiqSqsProcessor
  # Rails integration for SidekiqSqsProcessor
  # Handles initialization, configuration, and lifecycle management
  class Railtie < Rails::Railtie
    initializer "sidekiq_sqs_processor.configure_rails_initialization" do |app|
      # Set default logger to Rails logger if not specified
      SidekiqSqsProcessor.configuration.logger ||= Rails.logger
      
      # Disable polling in test environment by default
      if Rails.env.test? && !ENV['ENABLE_SQS_POLLING_IN_TEST']
        SidekiqSqsProcessor.configuration.polling_enabled = false
      end
      
      # Disable polling in development by default unless explicitly enabled
      if Rails.env.development? && !ENV['ENABLE_SQS_POLLING_IN_DEV']
        SidekiqSqsProcessor.configuration.polling_enabled = false
      end
      
      # Configure Sidekiq server middleware and lifecycle hooks
      if defined?(Sidekiq)
        Sidekiq.configure_server do |config|
          # Start continuous poller when Sidekiq server starts
          # Only if polling is enabled and type is continuous
          config.on(:startup) do
            if SidekiqSqsProcessor.configuration.polling_type == :continuous && 
               SidekiqSqsProcessor.configuration.polling_enabled &&
               SidekiqSqsProcessor.configuration.poll_on_startup
              
              # Only run the poller in the scheduler process if using Sidekiq Enterprise
              # For regular Sidekiq, this will run in every process
              if !defined?(Sidekiq::Enterprise) || Sidekiq.schedule?
                Rails.logger.info("Starting SidekiqSqsProcessor continuous poller")
                SidekiqSqsProcessor.start_continuous_poller
              end
            end
          end
          
          # Stop continuous poller when Sidekiq server shuts down
          config.on(:shutdown) do
            if SidekiqSqsProcessor.continuous_poller_running?
              Rails.logger.info("Stopping SidekiqSqsProcessor continuous poller")
              SidekiqSqsProcessor.stop_continuous_poller
            end
          end
        end
      end
      
      # Set up scheduled polling if enabled
      if defined?(Sidekiq::Cron) && 
         SidekiqSqsProcessor.configuration.polling_type == :scheduled &&
         SidekiqSqsProcessor.configuration.polling_enabled
        
        # Only set up in server mode
        if Sidekiq.server?
          frequency = SidekiqSqsProcessor.configuration.polling_frequency
          
          # Convert seconds to cron expression
          # Minimum 1 minute for cron
          minutes = [frequency / 60, 1].max
          cron_expression = minutes == 1 ? "* * * * *" : "*/#{minutes} * * * *"
          
          # Create the cron job
          Sidekiq::Cron::Job.create(
            name: 'SQS Polling Job',
            cron: cron_expression,
            class: 'SidekiqSqsProcessor::ScheduledPoller',
            queue: 'critical'
          )
          
          Rails.logger.info("Registered SidekiqSqsProcessor scheduled poller with cron: #{cron_expression}")
        end
      end
    end
    
    # Expose rake tasks if available
    rake_tasks do
      load "tasks/sidekiq_sqs_processor_tasks.rake" if File.exist?(File.join(File.dirname(__FILE__), "../tasks/sidekiq_sqs_processor_tasks.rake"))
    end
    
    # Register Rails generators
    generators do
      require_relative "../generators/sidekiq_sqs_processor/install_generator"
      require_relative "../generators/sidekiq_sqs_processor/worker_generator"
    end
    
    # Add local configuration options to Rails application configuration
    config.after_initialize do |app|
      # Validate configuration if in production
      if Rails.env.production? && SidekiqSqsProcessor.configuration.polling_enabled
        # Ensure configuration is valid
        unless SidekiqSqsProcessor.configuration.valid?
          Rails.logger.error("Invalid SidekiqSqsProcessor configuration")
          SidekiqSqsProcessor.configuration.validate!  # This will raise an error with details
        end
      end
    end
  end
end

